-- +goose Up
-- +goose StatementBegin

set timezone to 'UTC';

-- Drop api.vessel_fn
DROP FUNCTION IF EXISTS api.vessel_fn();
DROP FUNCTION IF EXISTS api.vessel_details_fn();
DROP FUNCTION IF EXISTS api.vessel_extended_fn();

-- Update api.vessel_view, add a field to indicate if the vessel name is missmatched with the registered name in auth.vessels. This is used to indicate to the user that they can sync the name from the metadata to the registration record.
DROP VIEW IF EXISTS api.vessel_view;
CREATE OR REPLACE VIEW api.vessel_view
WITH (security_invoker=true, security_barrier=true)
AS WITH latest_position AS (
         SELECT metrics.vessel_id,
            metrics."time",
            metrics.courseovergroundtrue,
            metrics.speedoverground,
            metrics.anglespeedapparent,
            metrics.longitude,
            metrics.latitude,
            st_makepoint(metrics.longitude, metrics.latitude) AS geo_point
           FROM api.metrics
          WHERE metrics.latitude IS NOT NULL
            AND metrics.longitude IS NOT NULL
            AND metrics.vessel_id = current_setting('vessel.id'::text, false)
          ORDER BY metrics."time" DESC
         LIMIT 1
        )
 SELECT m.vessel_id,
    m.name,                     -- raw, may be NULL: drives the "set in SignalK" note
    m.mmsi,                     -- raw, may be NULL (trigger nulls invalid input)
    v.name AS registered_name,
    v.mmsi AS registered_mmsi,
    -- Sync flags → button. TRUE only when SignalK reports something that
    -- differs AND is representable in auth.vessels.
    (m.name IS NOT NULL
       AND length(m.name) BETWEEN 3 AND 511
       AND m.name IS DISTINCT FROM v.name)          AS name_differs,
    (m.mmsi IS NOT NULL
       AND m.mmsi::numeric IS DISTINCT FROM v.mmsi) AS mmsi_differs,
    -- Missing flags → note. SignalK has no usable value for this field.
    (m.name IS NULL
       OR length(m.name) NOT BETWEEN 3 AND 511)     AS name_missing,
    (m.mmsi IS NULL)                                AS mmsi_missing,
    v.created_at,
    m.created_at AS first_contact,
    m."time"     AS last_contact,
    (now() - m."time") > 'PT1H10M'::interval AS offline,
    ais.description AS ship_type,
    mid.country,
    iso.alpha_2,
    m.length,
    m.beam,
    m.height,
    m.plugin_version,
    m.platform,
    m.configuration IS NOT NULL AS has_config,
    m.user_data -> 'make_model'::text AS make_model,
    (m.user_data -> 'polar'::text) IS NOT NULL AS has_polar,
    jsonb_array_length(COALESCE(m.user_data -> 'images'::text, '[]'::jsonb)) > 0 AS has_images,
    ((m.user_data -> 'images'::text) -> 0) ->> 'url'::text AS image_url,
    ((m.user_data -> 'images'::text) -> 0) ->> 'updated_at'::text AS image_updated_at,
    m.user_data -> 'images'::text AS images,
    m.user_data -> 'spec'::text  AS spec,
    jsonb_build_object('type', 'Feature',
        'geometry', st_asgeojson(st_makepoint(p.longitude, p.latitude))::jsonb,
        'properties', jsonb_build_object(
            'name', m.name,
            'time', p."time",
            'longitude', p.longitude,
            'latitude', p.latitude,
            'make_model', m.user_data -> 'make_model'::text,
            'image_url', ((m.user_data -> 'images'::text) -> 0) ->> 'url'::text)) AS geojson
   FROM auth.vessels v
     JOIN api.metadata m ON m.vessel_id = v.vessel_id
     LEFT JOIN aistypes ais ON ais.id = m.ship_type
     LEFT JOIN mid ON "left"(m.mmsi, 3)::numeric = mid.id
     LEFT JOIN iso3166 iso ON iso.id = mid.country_id
     LEFT JOIN latest_position p ON p.vessel_id = m.vessel_id
  WHERE m.vessel_id = current_setting('vessel.id'::text, false);

COMMENT ON VIEW api.vessel_view IS 'Primary vessel resource view. Exposes identity, AIS metadata, physical
     dimensions, plugin info, extended profile (make/model, polar, images),
     and live GeoJSON position. Replaces api.vessel_fn(). RLS-equivalent via
     vessel.id session config. One row per authenticated vessel session.
     api.metadata is the source of truth for name and mmsi; auth.vessels.name
     is the registration record. name_differs drives the identity-sync button
     in the vessel page (see api.vessel_sync_identity_fn).';

-- Add api.vessel_sync_identity_fn, Update auth.vessels name base on signalk data on user request.
CREATE OR REPLACE FUNCTION api.vessel_sync_identity_fn(_vessel_id text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $$
DECLARE
    _email   text := current_setting('user.email', false);
    v        auth.vessels%ROWTYPE;
    m        api.metadata%ROWTYPE;
    _vid     text;
    _name    text;
    _mmsi    numeric;
    _changes jsonb := '{}'::jsonb;
    _skipped jsonb := '{}'::jsonb;
BEGIN
    _vid := COALESCE(_vessel_id, current_setting('vessel.id', true));

    -- Ownership check: DEFINER bypasses RLS, so scope explicitly.
    SELECT * INTO v FROM auth.vessels
     WHERE vessel_id = _vid AND owner_email::text = _email;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown vessel' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO m FROM api.metadata WHERE vessel_id = _vid;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('synced', false, 'reason', 'no_metadata',
                                  'changes', _changes, 'skipped', _skipped);
    END IF;

    -- name — auth.vessels: NOT NULL, vessels_name_check length 3..511.
    -- Capped at 111 here (and in api.vessel_view) as a product decision:
    -- no real vessel name is longer. Keep both limits in step.
    IF m.name IS NULL THEN
        _skipped := _skipped || jsonb_build_object('name', 'missing');
    ELSIF length(m.name) NOT BETWEEN 3 AND 111 THEN
        _skipped := _skipped || jsonb_build_object('name', 'invalid_length');
    ELSIF m.name IS DISTINCT FROM v.name THEN
        _name := m.name;
        _changes := _changes || jsonb_build_object('name',
            jsonb_build_object('from', v.name, 'to', m.name));
    END IF;

    -- mmsi — api.metadata.metadata_mmsi_check guarantees ^[2-7]\d{8}$ when
    -- non-NULL, so the cast is safe. The range test below mirrors
    -- auth.vessels.valid_range_mmsi and is kept as the authoritative guard
    -- in case the metadata constraint is ever relaxed.
    IF m.mmsi IS NULL THEN
        _skipped := _skipped || jsonb_build_object('mmsi', 'missing');
    ELSE
        _mmsi := m.mmsi::numeric;
        IF _mmsi <= 100000000 OR _mmsi >= 800000000 THEN
            _skipped := _skipped || jsonb_build_object('mmsi', 'out_of_range');
            _mmsi := NULL;
        ELSIF EXISTS (SELECT 1 FROM auth.vessels
                       WHERE mmsi        = _mmsi
                         AND owner_email = v.owner_email
                         AND vessel_id  <> _vid) THEN
            -- Scoped to the owner: a match on another user's vessel is legal
            -- under UNIQUE (owner_email, mmsi). If vessels_mmsi_key is still
            -- global, that case is caught by the unique_violation handler.
            _skipped := _skipped || jsonb_build_object('mmsi', 'already_in_use');
            _mmsi := NULL;
        ELSIF _mmsi IS DISTINCT FROM v.mmsi THEN
            _changes := _changes || jsonb_build_object('mmsi',
                jsonb_build_object('from', v.mmsi, 'to', _mmsi));
        ELSE
            _mmsi := NULL;   -- already in sync
        END IF;
    END IF;

    IF _changes = '{}'::jsonb THEN
        RETURN jsonb_build_object('synced', false, 'reason', 'up_to_date',
                                  'changes', _changes, 'skipped', _skipped);
    END IF;

    BEGIN
        UPDATE auth.vessels
           SET name = COALESCE(_name, name),
               mmsi = COALESCE(_mmsi, mmsi)
         WHERE vessel_id = _vid;
    EXCEPTION WHEN unique_violation THEN
        -- Lost race, or vessels_mmsi_key is still global and another owner
        -- holds this MMSI. Report rather than surfacing a raw 23505.
        RETURN jsonb_build_object('synced', false, 'reason', 'mmsi_conflict',
                                  'changes', '{}'::jsonb,
                                  'skipped', _skipped ||
                                      jsonb_build_object('mmsi', 'already_in_use'));
    END;

    RETURN jsonb_build_object('synced', true, 'changes', _changes,
                              'skipped', _skipped);
END;
$$;

REVOKE ALL ON FUNCTION api.vessel_sync_identity_fn(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api.vessel_sync_identity_fn(text) TO user_role;

COMMENT ON FUNCTION api.vessel_sync_identity_fn(text) IS
 'User-initiated push of api.metadata identity (name, mmsi) into auth.vessels.
  api.metadata is the source of truth (SignalK); auth.vessels holds the
  registration record. Validates against auth.vessels constraints before
  writing and reports per-field skips rather than raising.
  Returns: {synced, reason?, changes{}, skipped{}} — always both objects.
  skipped reasons align with api.vessel_view flags: "missing" ↔ *_missing,
  "invalid_length"/"out_of_range"/"already_in_use" ↔ *_differs that cannot
  be applied. SECURITY DEFINER with explicit owner_email scoping because
  user_role cannot write auth. VOLATILE — reads session GUCs.';

-- DROP FUNCTION public.metrics_trigger_fn();
-- Update public.metrics_trigger_fn, project only time, status, latitude, longitude for previous metrics
CREATE OR REPLACE FUNCTION public.metrics_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
    DECLARE
        previous_metric record;
        stay_code INTEGER;
        logbook_id INTEGER;
        stay_id INTEGER;
        valid_status BOOLEAN := False;
        _vessel_id TEXT;
        distance double precision := 0;
    BEGIN
        --RAISE NOTICE 'metrics_trigger_fn';
        --RAISE WARNING 'metrics_trigger_fn [%] [%]', current_setting('vessel.id', true), NEW;
        -- Ensure vessel.id to new value to allow RLS
        IF NEW.vessel_id IS NULL THEN
            -- set vessel_id from jwt if not present in INSERT query
            NEW.vessel_id := current_setting('vessel.id');
        END IF;
        -- Boat metadata are check using api.metrics REFERENCES to api.metadata
        -- Fetch the latest entry to compare status against the new status to be insert
        -- Project only time, status, latitude, longitude
        SELECT time, status, latitude, longitude INTO previous_metric
            FROM api.metrics m 
            WHERE m.vessel_id IS NOT NULL
                AND m.vessel_id = current_setting('vessel.id', true)
            ORDER BY m.time DESC LIMIT 1;
        --RAISE NOTICE 'Metrics Status, New:[%] Previous:[%]', NEW.status, previous_metric.status;
        IF previous_metric.time = NEW.time THEN
            -- Ignore entry if same time
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], duplicate time [%] = [%]', NEW.vessel_id, previous_metric.time, NEW.time;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Duplicate time';
            RETURN NULL;
        END IF;
        IF previous_metric.time > NEW.time THEN
            -- Ignore entry if new time is later than previous time
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], new time is older than previous_metric.time [%] > [%]', NEW.vessel_id, previous_metric.time, NEW.time;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'New time is in the past from previous time';
            RETURN NULL;
        END IF;
        IF NEW.time > NOW() THEN
            -- Ignore entry if new time is in the future.
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], new time is in the future [%] > [%]', NEW.vessel_id, NEW.time, NOW();
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'New time is in the future';
            RETURN NULL;
        END IF;
        -- Check if latitude or longitude are not type double
        --IF public.isdouble(NEW.latitude::TEXT) IS False OR public.isdouble(NEW.longitude::TEXT) IS False THEN
        --    -- Ignore entry if null latitude,longitude
        --    RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], not a double type for latitude or longitude [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
        --    RETURN NULL;
        --END IF;
        -- Check if latitude or longitude are null
        IF NEW.latitude IS NULL OR NEW.longitude IS NULL THEN
            -- Ignore entry if null latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], null latitude or longitude [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Null latitude or longitude';
            RETURN NULL;
        END IF;
        -- Check if valid latitude
        IF NEW.latitude >= 90 OR NEW.latitude <= -90 THEN
            -- Ignore entry if invalid latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid latitude >= 90 OR <= -90 [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Invalid latitude >= 90 OR <= -90';
            RETURN NULL;
        END IF;
        -- Check if valid longitude
        IF NEW.longitude >= 180 OR NEW.longitude <= -180 THEN
            -- Ignore entry if invalid latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid longitude >= 180 OR <= -180 [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Invalid longitude >= 180 OR <= -180';
            RETURN NULL;
        END IF;
        -- Check for null island (0,0) — invalid GPS fix
        IF NEW.latitude = 0.0 AND NEW.longitude = 0.0 THEN
            -- Ignore entry if latitude,longitude are equal to 0.0
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], latitude and longitude are equal to 0.0 [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Null island position (0,0)';
            RETURN NULL;
        END IF;
        -- Check for suspiciously equal coordinates (GPS glitch)
        IF NEW.latitude = NEW.longitude AND ABS(NEW.latitude) > 1 THEN
            -- Ignore entry if latitude,longitude are equal
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], latitude and longitude are equal [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Latitude and longitude are equal';
            RETURN NULL;
        END IF;
/*
        -- Check for impossible position jumps (teleportation detection)
        --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], new latitude and longitude [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
        --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], prev latitude and longitude [%] [%]', NEW.vessel_id, previous_metric.latitude, previous_metric.longitude;
        IF previous_metric.longitude IS NOT NULL AND previous_metric.latitude IS NOT NULL
            AND (previous_metric.latitude <> NEW.latitude
            OR previous_metric.longitude <> NEW.longitude) THEN
            -- Calculate distance in meters
            distance := ST_Distance(
                ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography,
                ST_SetSRID(ST_MakePoint(previous_metric.longitude, previous_metric.latitude), 4326)::geography
            );
            --RAISE WARNING 'Metrics distance check, vessel_id [%], distance [% m]', NEW.vessel_id, distance;
            -- Check distance from previous point is > 500km, if yes ignore entry as it is likely a GPS glitch or data error
            IF distance::NUMERIC > 500000 THEN
                -- 'ANOMALY: Distance > 500km'
                RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], distance between previous metric and new metric is too long >500km, distance [% km]', 
                    NEW.vessel_id, ROUND((distance/1000)::numeric, 2);
                INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Distance from previous point is > 500km';
                RETURN NULL;
            END IF;
        END IF;
*/
        -- Check if speedOverGround is valid value
        IF NEW.speedoverground >= 40 THEN
            -- Ignore entry as speedOverGround is invalid
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], speedOverGround is invalid, over 40 < [%]', NEW.vessel_id, NEW.speedoverground;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Invalid speedOverGround over 40';
            RETURN NULL;
        END IF;
        -- Check if windSpeedApparent is valid value
        IF NEW.windspeedapparent >= 200 THEN
            -- Ignore entry as windSpeedApparent is invalid
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], windSpeedApparent is invalid, over 200 < [%]', NEW.vessel_id, NEW.windspeedapparent;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Invalid windSpeedApparent over 200';
            RETURN NULL;
        END IF;

        -- Debug If status NULL, what should we do ?
        --RAISE WARNING 'Metrics status, vessel_id [%], New:[%] Previous:[%]', NEW.vessel_id, NEW.status, previous_metric.status;
/*
        Problematic...
        -- Check if status is null but speed is over 3knots set status to sailing
        IF NEW.status IS NULL AND NEW.speedoverground >= 3 THEN
            RAISE WARNING 'Metrics Unknown NEW.status from vessel_id [%], null status, set to sailing because of speedoverground is +3 from [%]', NEW.vessel_id, NEW.status;
            NEW.status := 'sailing';
        -- Check if status is null then set status to default moored
        ELSIF NEW.status IS NULL THEN
            RAISE WARNING 'Metrics Unknown NEW.status from vessel_id [%], null status, set to default moored from [%]', NEW.vessel_id, NEW.status;
            NEW.status := 'moored';
        END IF;
*/
        IF NEW.status IS NULL AND previous_metric.status IS NOT NULL THEN
            RAISE WARNING 'Metrics Unknown NEW.status from vessel_id [%], null new status [%], set to previous_metric.status from [%]', NEW.vessel_id, NEW.status, previous_metric.status;
            NEW.status := previous_metric.status;
        END IF;

        IF previous_metric.status IS NULL THEN
            IF NEW.status = 'anchored' THEN
                RAISE WARNING 'Metrics Unknown previous_metric.status from vessel_id [%], [%] set to default current status [%]', NEW.vessel_id, previous_metric.status, NEW.status;
                previous_metric.status := NEW.status;
            ELSE
                RAISE WARNING 'Metrics Unknown previous_metric.status from vessel_id [%], [%] set to default status moored vs [%]', NEW.vessel_id, previous_metric.status, NEW.status;
                previous_metric.status := 'moored';
            END IF;
            -- Add new stay as no previous entry exist
            INSERT INTO api.stays 
                (vessel_id, active, arrived, latitude, longitude, stay_code)
                VALUES (current_setting('vessel.id', true), true, NEW.time, NEW.latitude, NEW.longitude, 1)
                RETURNING id INTO stay_id;
            -- Add stay entry to process queue for further processing
            --INSERT INTO process_queue (channel, payload, stored, ref_id)
            --    VALUES ('new_stay', stay_id, NOW(), current_setting('vessel.id', true));
            --RAISE WARNING 'Metrics Insert first stay as no previous metrics exist, stay_id stay_id [%] [%] [%]', stay_id, NEW.status, NEW.time;
        END IF;
        -- Check if status is valid enum
        SELECT NEW.status::name = any(enum_range(null::status_type)::name[]) INTO valid_status;
        IF valid_status IS False THEN
            -- Ignore entry if status is invalid
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid status [%]', NEW.vessel_id, NEW.status;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Invalid status';
            RETURN NULL;
        END IF;

        -- Check the state and if any previous/current entry
        -- If change of state and new status is sailing or motoring
        IF previous_metric.status::TEXT <> NEW.status::TEXT AND
            ( (NEW.status::TEXT = 'sailing' AND previous_metric.status::TEXT <> 'motoring')
             OR (NEW.status::TEXT = 'motoring' AND previous_metric.status::TEXT <> 'sailing') ) THEN
            RAISE WARNING 'Metrics Update status, vessel_id [%], try new logbook, New:[%] Previous:[%]', NEW.vessel_id, NEW.status, previous_metric.status;
            -- Start new log
            logbook_id := public.trip_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF logbook_id IS NULL THEN
                INSERT INTO api.logbook
                    (vessel_id, active, _from_time, _from_lat, _from_lng)
                    VALUES (current_setting('vessel.id', true), true, NEW.time, NEW.latitude, NEW.longitude)
                    RETURNING id INTO logbook_id;
                RAISE WARNING 'Metrics Insert new logbook, vessel_id [%], logbook_id [%] [%] [%]', NEW.vessel_id, logbook_id, NEW.status, NEW.time;
            ELSE
                UPDATE api.logbook
                    SET
                        active = false,
                        _to_time = NEW.time,
                        _to_lat = NEW.latitude,
                        _to_lng = NEW.longitude
                    WHERE id = logbook_id;
                RAISE WARNING 'Metrics Existing logbook, vessel_id [%], logbook_id [%] [%] [%]', NEW.vessel_id, logbook_id, NEW.status, NEW.time;
            END IF;

            -- End current stay
            stay_id := public.stay_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF stay_id IS NOT NULL THEN
                UPDATE api.stays
                    SET
                        active = false,
                        departed = NEW.time
                    WHERE id = stay_id;
                -- Add stay entry to process queue for further processing
                INSERT INTO process_queue (channel, payload, stored, ref_id)
                    VALUES ('new_stay', stay_id, NOW(), current_setting('vessel.id', true));
                RAISE WARNING 'Metrics Updating, vessel_id [%], Stay end current stay_id [%] [%] [%]', NEW.vessel_id, stay_id, NEW.status, NEW.time;
            ELSE
                RAISE WARNING 'Metrics Invalid, vessel_id [%], stay_id [%] [%]', NEW.vessel_id, stay_id, NEW.time;
            END IF;

        -- If change of state and new status is moored or anchored
        ELSIF previous_metric.status::TEXT <> NEW.status::TEXT AND
            ( (NEW.status::TEXT = 'moored' AND previous_metric.status::TEXT <> 'anchored')
             OR (NEW.status::TEXT = 'anchored' AND previous_metric.status::TEXT <> 'moored') ) THEN
            -- Start new stays
            RAISE WARNING 'Metrics Update status, vessel_id [%], try new stay, New:[%] Previous:[%]', NEW.vessel_id, NEW.status, previous_metric.status;
            stay_id := public.stay_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF stay_id IS NULL THEN
                RAISE WARNING 'Metrics Inserting, vessel_id [%], new stay [%]', NEW.vessel_id, NEW.status;
                -- If metric status is anchored set stay_code accordingly
                stay_code = 1;
                IF NEW.status = 'anchored' THEN
                    stay_code = 2;
                END IF;
                -- Add new stay
                INSERT INTO api.stays
                    (vessel_id, active, arrived, latitude, longitude, stay_code)
                    VALUES (current_setting('vessel.id', true), true, NEW.time, NEW.latitude, NEW.longitude, stay_code)
                    RETURNING id INTO stay_id;
                RAISE WARNING 'Metrics Insert, vessel_id [%], new stay, stay_id [%] [%] [%]', NEW.vessel_id, stay_id, NEW.status, NEW.time;
            ELSE
                RAISE WARNING 'Metrics Invalid, vessel_id [%], stay_id [%] [%]', NEW.vessel_id, stay_id, NEW.time;
                UPDATE api.stays
                    SET
                        active = false,
                        departed = NEW.time,
                        notes = 'Invalid stay?'
                    WHERE id = stay_id;
            END IF;

            -- End current log/trip
            -- Fetch logbook_id by vessel_id
            logbook_id := public.trip_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF logbook_id IS NOT NULL THEN
                -- todo check on time start vs end
                RAISE WARNING 'Metrics Updating, vessel_id [%], logbook status [%] [%] [%]', NEW.vessel_id, logbook_id, NEW.status, NEW.time;
                UPDATE api.logbook 
                    SET 
                        active = false, 
                        _to_time = NEW.time,
                        _to_lat = NEW.latitude,
                        _to_lng = NEW.longitude
                    WHERE id = logbook_id;
                -- Add logbook entry to process queue for later processing
                INSERT INTO process_queue (channel, payload, stored, ref_id)
                    VALUES ('pre_logbook', logbook_id, NOW(), current_setting('vessel.id', true));
            ELSE
                RAISE WARNING 'Metrics Invalid, vessel_id [%], logbook_id [%] [%] [%]', NEW.vessel_id, logbook_id, NEW.status, NEW.time;
            END IF;
        END IF;
        RETURN NEW; -- Finally insert the actual new metric
    END;
$function$
;

COMMENT ON FUNCTION public.metrics_trigger_fn() IS 'process metrics from vessel, generate pre_logbook and new_stay.';

-- DROP FUNCTION public.check_jwt();
-- Update public.check_jwt(), fix anonymous access for telegram bot
CREATE OR REPLACE FUNCTION public.check_jwt()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
-- Prevent unregister user or unregister vessel access
-- Allow anonymous access
DECLARE
  _role name := NULL;
  _email text := NULL;
  anonymous_rec record;
  _path name := NULL;
  _vid text := NULL;
  _vname text := NULL;
  boat TEXT := NULL;
  _pid INTEGER := 0; -- public_id
  _pvessel TEXT := NULL; -- public_type
  _ptype TEXT := NULL; -- public_type
  _ppath BOOLEAN := False; -- public_path
  _pvalid BOOLEAN := False; -- public_valid
  _pheader text := NULL; -- public_header
  valid_public_type BOOLEAN := False;
  account_rec record;
  vessel_rec record;
  _headers json := NULL;
BEGIN
  -- RESET settings to avoid sql shared session cache
  -- Valid for every new HTTP request
  PERFORM set_config('vessel.id', NULL, true);
  PERFORM set_config('vessel.name', NULL, true);
  PERFORM set_config('user.id', NULL, true);
  PERFORM set_config('user.email', NULL, true);
  -- Extract email and role from jwt token
  --RAISE WARNING 'check_jwt jwt %', current_setting('request.jwt.claims', true);
  SELECT current_setting('request.jwt.claims', true)::json->>'email' INTO _email;
  PERFORM set_config('user.email', _email, true);
  SELECT current_setting('request.jwt.claims', true)::json->>'role' INTO _role;
  --RAISE WARNING 'jwt email %', current_setting('request.jwt.claims', true)::json->>'email';
  --RAISE WARNING 'jwt email %', current_setting('request.jwt.claims.email', true);
  --RAISE WARNING 'jwt role %', current_setting('request.jwt.claims', true)::json->>'role';
  --RAISE WARNING 'cur_user %', current_user;
  --RAISE WARNING 'user.id [%], user.email [%]', current_setting('user.id', true), current_setting('user.email', true);
  --RAISE WARNING 'vessel.id [%], vessel.name [%]', current_setting('vessel.id', true), current_setting('vessel.name', true);

  --TODO SELECT current_setting('request.jwt.uid', true)::json->>'uid' INTO _user_id;
  --TODO RAISE WARNING 'jwt user_id %', current_setting('request.jwt.uid', true)::json->>'uid';
  --TODO SELECT current_setting('request.jwt.vid', true)::json->>'vid' INTO _vessel_id;
  --TODO RAISE WARNING 'jwt vessel_id %', current_setting('request.jwt.vid', true)::json->>'vid';

  IF _role = 'user_role' OR _role = 'bot_role' OR _role = 'mcp_role' THEN
    -- Check the user exist in the accounts table
    SELECT * INTO account_rec
        FROM auth.accounts
        WHERE auth.accounts.email = _email;
    IF account_rec.email IS NULL THEN
        RAISE WARNING 'public.check_jwt() Invalid user Unknown user or password [%]', _email;
        RAISE EXCEPTION 'Invalid user'
            USING HINT = 'Unknown user or password';
    END IF;
    -- Set session variables
    PERFORM set_config('user.id', account_rec.user_id, true);
    SELECT current_setting('request.path', true) into _path;
    --RAISE WARNING 'req path %', current_setting('request.path', true);
    -- Function allow without defined vessel like for anonymous role
    IF _path ~ '^\/rpc\/(login|signup|recover|reset)$' THEN
        RETURN;
    END IF;
    -- Function allow without defined vessel as user role
    -- openapi doc, user settings, otp code and vessel registration
    IF _path = '/rpc/settings_fn'
        OR _path = '/rpc/register_vessel'
        OR _path = '/rpc/update_user_preferences_fn'
        OR _path = '/rpc/versions_fn'
        OR _path = '/rpc/email_fn'
        OR _path = '/' THEN
        RETURN;
    END IF;
    /*-- Check a vessel and user exist
    SELECT auth.vessels.* INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = auth.accounts.email
            AND auth.accounts.email = _email;
    */
    SELECT * INTO vessel_rec
        FROM auth.vessels
        WHERE owner_email = _email;
    -- check if boat exist yet?
    IF vessel_rec.owner_email IS NULL THEN
        -- Return http status code 551 with message
        RAISE sqlstate 'PT551' using
            message = 'Vessel Required',
            detail = 'Invalid vessel',
            hint = 'Unknown vessel';
        --RETURN; -- ignore if not exist
    END IF;
    -- Redundant?
    IF vessel_rec.vessel_id IS NULL THEN
        RAISE EXCEPTION 'Invalid vessel'
            USING HINT = 'Unknown vessel id';
    END IF;
    -- Set session variables
    PERFORM set_config('vessel.id', vessel_rec.vessel_id, true);
    PERFORM set_config('vessel.name', vessel_rec.name, true);
    --RAISE WARNING 'public.check_jwt() user_role vessel.id [%]', current_setting('vessel.id', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.name [%]', current_setting('vessel.name', false);
  ELSIF _role = 'vessel_role' THEN
    SELECT current_setting('request.path', true) into _path;
    --RAISE WARNING 'req path %', current_setting('request.path', true);
    -- Function allow without defined vessel like for anonymous role
    IF _path ~ '^\/rpc\/(oauth_\w+)$' THEN
        RETURN;
    END IF;
    -- Extract vessel_id from jwt token
    SELECT current_setting('request.jwt.claims', true)::json->>'vid' INTO _vid;
    /*
    -- Check the vessel and user exist
    SELECT auth.vessels.* INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = auth.accounts.email
            AND auth.accounts.email = _email
            AND auth.vessels.vessel_id = _vid;
    */
    -- vessel_role vessel lookup  
    SELECT * INTO vessel_rec
        FROM auth.vessels
        WHERE owner_email = _email
            AND vessel_id = _vid;
    IF vessel_rec.owner_email IS NULL THEN
        RAISE WARNING 'public.check_jwt() Invalid vessel Unknown vessel owner_email [%]', _email;
        RAISE EXCEPTION 'Invalid vessel'
            USING HINT = 'Unknown vessel owner_email';
    END IF;
    PERFORM set_config('vessel.id', vessel_rec.vessel_id, true);
    PERFORM set_config('vessel.name', vessel_rec.name, true);
    --RAISE WARNING 'public.check_jwt() user_role vessel.name %', current_setting('vessel.name', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.id %', current_setting('vessel.id', false);
  ELSIF _role = 'api_anonymous' THEN
    SELECT current_setting('request.path', true) into _path;
    -- Function allow for anonymous role
    IF _path ~ '^(\/|\/rpc\/(login|signup|recover|reset|pushover_fn|telegram(_fn|_otp_fn)?|ispublic_fn|telemetry_fn))$' THEN
        RETURN;
    END IF;
    --RAISE WARNING 'public.check_jwt() api_anonymous path[%] vid:[%]', current_setting('request.path', true), current_setting('vessel.id', false); 
    -- Check if path is the a valid allow anonymous path
    SELECT _path ~ '^/(logs_view|log_view|rpc/timelapse_fn|rpc/timelapse2_fn|monitoring_live|monitoring_view|rpc/stats_fn|rpc/export_logbooks_geojson_point_trips_fn|rpc/export_logbooks_geojson_linestring_trips_fn|rpc/vessel_fn)$' INTO _ppath;
    if _ppath is True then
        -- Check is custom header is present and valid
        SELECT current_setting('request.headers', true)::json->>'x-is-public' into _pheader;
        --RAISE WARNING 'public.check_jwt() api_anonymous _pheader [%]', _pheader;
        if _pheader is null then
            return;
			--RAISE EXCEPTION 'Invalid public_header'
            --    USING HINT = 'Stop being so evil and maybe you can log in';
        end if;
        SELECT convert_from(decode(_pheader, 'base64'), 'utf-8')
                            ~ '\w+,public_(logs|logs_list|stats|timelapse|monitoring),\d+$' into _pvalid;
        RAISE WARNING 'public.check_jwt() api_anonymous _pvalid [%]', _pvalid;
        if _pvalid is null or _pvalid is False then
            RAISE EXCEPTION 'Invalid public_valid'
                USING HINT = 'Stop being so evil and maybe you can log in';
        end if;
        WITH regex AS (
            SELECT regexp_match(
                        convert_from(
                            decode(_pheader, 'base64'), 'utf-8'),
                        '(\w+),(public_(logs|logs_list|stats|timelapse|monitoring)),(\d+)$') AS match
            )
        SELECT match[1], match[2], match[4] into _pvessel, _ptype, _pid
            FROM regex;
        RAISE WARNING 'public.check_jwt() api_anonymous [%] [%] [%]', _pvessel, _ptype, _pid;
        if _pvessel is not null and _ptype is not null then
            -- Everything seem fine, get the vessel_id base on the vessel name.
            SELECT _ptype::name = any(enum_range(null::public_type)::name[]) INTO valid_public_type;
            IF valid_public_type IS False THEN
                -- Ignore entry if type is invalid
                RAISE EXCEPTION 'Invalid public_type'
                    USING HINT = 'Stop being so evil and maybe you can log in';
            END IF;
            -- Check if boat name match public_vessel name
            boat := '^' || _pvessel || '$';
            IF _ptype ~ '^public_(logs|timelapse)$' AND _pid > 0 THEN
                WITH log as (
                    SELECT vessel_id from api.logbook l where l.id = _pid
                )
                SELECT v.vessel_id, v.name into anonymous_rec
                    FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs, log l
                    WHERE v.vessel_id = l.vessel_id
                        AND a.email = v.owner_email
                        AND a.preferences->>'public_vessel'::text ~* boat
                        AND prefs.key = _ptype::TEXT
                        AND prefs.value::BOOLEAN = true;
                RAISE WARNING '-> ispublic_fn public_logs output boat:[%], type:[%], result:[%]', _pvessel, _ptype, anonymous_rec;
                IF anonymous_rec.vessel_id IS NOT NULL THEN
                    PERFORM set_config('vessel.id', anonymous_rec.vessel_id, true);
                    PERFORM set_config('vessel.name', anonymous_rec.name, true);
                    RETURN;
                END IF;
            ELSIF _ptype ~ '^public_(logs_list|stats|monitoring|timelapse)$' AND _pid = 0 THEN
                /*
                    SELECT v.vessel_id, v.name into anonymous_rec
                        FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs
                        WHERE a.email = v.owner_email
                            AND a.preferences->>'public_vessel'::text ~* boat
                            AND prefs.key = _ptype::TEXT
                            AND prefs.value::BOOLEAN = true;
                */
                -- Replace the ELSE branch anonymous lookup with:
                SELECT v.vessel_id, v.name INTO anonymous_rec
                    FROM auth.vessels v
                    JOIN auth.accounts a ON a.email = v.owner_email
                    WHERE a.preferences->>'public_vessel' = _pvessel   -- exact match, index-able
                    AND a.preferences->>_ptype::TEXT = 'true'
                    LIMIT 1;
                RAISE WARNING '-> ispublic_fn output boat:[%], type:[%], result:[%]', _pvessel, _ptype, anonymous_rec;
                IF anonymous_rec.vessel_id IS NOT NULL THEN
                    PERFORM set_config('vessel.id', anonymous_rec.vessel_id, true);
                    PERFORM set_config('vessel.name', anonymous_rec.name, true);
                    RETURN;
                END IF;
            END IF;
            --RAISE sqlstate 'PT404' using message = 'unknown resource';
        END IF; -- end anonymous path
    ELSE -- If path is not allow for anonymous role, block access
        RAISE sqlstate 'PT404' using message = 'unknown resource';    
    END IF;
  ELSIF _role <> 'api_anonymous' THEN
    RAISE EXCEPTION 'Invalid role'
      USING HINT = 'Stop being so evil and maybe you can log in';
  END IF;
END
$function$
;

COMMENT ON FUNCTION public.check_jwt() IS 'PostgREST API db-pre-request check, set_config according to role (api_anonymous,vessel_role,user_role)';


-- Refresh permissions user_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO user_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
-- Refresh permissions bot_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO bot_role;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO bot_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO bot_role;
-- Refresh permissions grafana
GRANT SELECT ON ALL TABLES IN SCHEMA api TO grafana;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO grafana;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO grafana;
-- Refresh permissions api_anonymous
GRANT SELECT ON ALL TABLES IN SCHEMA api TO api_anonymous;

GRANT EXECUTE ON FUNCTION api.stats_logs_fn TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.stats_stays_fn TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.stats_fn TO api_anonymous;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO api_anonymous;
-- Refresh permissions bot_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO bot_role;

REVOKE EXECUTE ON FUNCTION api.settings_fn() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api.settings_fn() TO user_role;

-- Restrict app_settings access to sql users
REVOKE SELECT ON public.app_settings FROM grafana;
REVOKE SELECT ON public.app_settings FROM scheduler;
REVOKE SELECT ON public.app_settings FROM bot_role;

-- +goose StatementEnd
