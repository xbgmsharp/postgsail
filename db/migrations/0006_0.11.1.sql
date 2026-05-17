-- +goose Up
-- +goose StatementBegin

set timezone to 'UTC';

-- EXPLAIN confirms stays_vessel_arrived_idx handles the query in 1ms / 46 buffers. Drop it.
DROP INDEX IF EXISTS api.stays_timeline_covering_idx;
-- the only query using stored has 24 calls and the planner will prefer the processed IS NULL partial indexes regardless. Drop it.
DROP INDEX IF EXISTS public.process_queue_stored_idx;
DROP INDEX IF EXISTS public.process_queue_channel_pending_covering_idx;

DROP INDEX IF EXISTS public.stays_moorage_vessel_idx;
-- stays_moorage_vessel_idx — rebuild with vessel_id in key, departed IS NOT NULL partial to match stays_view predicate
CREATE INDEX IF NOT EXISTS stays_moorage_vessel_idx
    ON api.stays (moorage_id, vessel_id)
    INCLUDE (id, arrived, departed, duration, stay_code, name)
    WHERE departed IS NOT NULL;

COMMENT ON INDEX api.stays_moorage_vessel_idx IS
    'Covers stays_view NL inner probe: moorages → stays join by moorage_id.
     vessel_id in key (not Filter) when join is driven from moorages side.
     INCLUDE covers all columns needed by stays_view without heap access.
     Partial: departed IS NOT NULL matches the stays_view WHERE predicate.';

-- process_queue, index covers eventlogs_view directly
CREATE INDEX process_queue_ref_id_processed_idx
  ON public.process_queue (ref_id, id DESC)
  WHERE processed IS NOT NULL;
COMMENT ON INDEX public.process_queue_ref_id_processed_idx IS
  'Optimizes: eventlogs_view user-facing event log
Query pattern: WHERE (ref_id = user.id OR ref_id = vessel.id) AND processed IS NOT NULL ORDER BY id DESC
Partial index: processed rows only (mirrors pending_idx which covers IS NULL side)
INCLUDE id DESC for ORDER BY pushdown';

-- Surpass by logbook_to_time_join_idx
DROP INDEX IF EXISTS api.logbook_to_time_idx;

-- Drop the weakest redundant index (superset exists in moorages_vessel_updated_at_idx)
DROP INDEX IF EXISTS api.moorages_vessel_id_idx;
 
-- New non-partial covering index for the common list-all-moorages pattern
-- used by moorages_view, moorages_geojson_view, stays_view hash-join build side
CREATE INDEX IF NOT EXISTS moorages_vessel_list_idx
    ON api.moorages (vessel_id)
    INCLUDE (id, name, stay_code, geog, latitude, longitude)
    WHERE vessel_id IS NOT NULL;
 
COMMENT ON INDEX api.moorages_vessel_list_idx IS
    'Non-partial covering index for moorages list queries that do NOT filter geog IS NOT NULL.
     moorages_vessel_idx (partial, geog IS NOT NULL) is ineligible when query lacks that predicate.
     moorages_vessel_updated_at_idx was winning by default — this gives a lighter, correct alternative.
     INCLUDE covers columns needed for the hash-join build side in moorages_view.
     moorages_vessel_idx is kept for detail/map queries that do include geog IS NOT NULL.';

-- Remove REDUNDANT UNIQUE CONSTRAINTS — drop where PK already implies uniqueness
-- api.stays_at: stay_code is already PRIMARY KEY
-- constraint stays_stay_code_fkey on table api.stays depends on index api.stays_at_stay_code_key
-- constraint moorages_stay_code_fkey on table api.moorages depends on index api.stays_at_stay_code_key
--ALTER TABLE api.stays_at
--    DROP CONSTRAINT IF EXISTS stays_at_stay_code_key;

-- public.aistypes: id is already PRIMARY KEY
ALTER TABLE public.aistypes
    DROP CONSTRAINT IF EXISTS aistypes_id_key;
 
-- public.badges: name is already PRIMARY KEY
ALTER TABLE public.badges
    DROP CONSTRAINT IF EXISTS badges_name_key;

-- Add MISSING PRIMARY KEYS — tables with only UNIQUE constraints, no PK
-- public.geocoders — had UNIQUE(name) only
ALTER TABLE public.geocoders
    ADD CONSTRAINT geocoders_pkey PRIMARY KEY (name);
ALTER TABLE public.geocoders
    DROP CONSTRAINT IF EXISTS geocoders_name_key;
 
-- public.app_settings — had UNIQUE(name) only
ALTER TABLE public.app_settings
    ADD CONSTRAINT app_settings_pkey PRIMARY KEY (name);
ALTER TABLE public.app_settings
    DROP CONSTRAINT IF EXISTS app_settings_name_key;
 
-- public.email_templates — had UNIQUE(name) only
ALTER TABLE public.email_templates
    DROP CONSTRAINT IF EXISTS email_templates_name_key;
-- ERROR:  multiple primary keys for table "email_templates" are not allowed
--ALTER TABLE public.email_templates
--    ADD CONSTRAINT email_templates_pkey PRIMARY KEY (name);

-- public.mid — had UNIQUE(id) only (UNLOGGED table)
ALTER TABLE public.mid
    ADD CONSTRAINT mid_pkey PRIMARY KEY (id);
ALTER TABLE public.mid
    DROP CONSTRAINT IF EXISTS mid_id_key;

-- Update auth.accounts
-- Step 1: expand default to 14 chars for future rows
ALTER TABLE auth.accounts
    ALTER COLUMN user_id SET DEFAULT public.uuid_generate_v7();
-- 1. Drop FKs that depend on accounts_pkey (the email PK index)
ALTER TABLE auth.otp
    DROP CONSTRAINT otp_user_email_fkey;
ALTER TABLE auth.vessels
    DROP CONSTRAINT vessels_owner_email_fkey;  -- verify exact name:
    -- SELECT conname FROM pg_constraint WHERE conrelid='auth.vessels'::regclass AND contype='f';

-- 2. Now drop the old PK (was on email)
ALTER TABLE auth.accounts
    DROP CONSTRAINT accounts_pkey;

-- 3. Drop integer id column
ALTER TABLE auth.accounts
    DROP COLUMN id;

-- 4. Promote user_id to PK
ALTER TABLE auth.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (user_id);

-- 5. accounts_email_unique already exists (added in 0005_0.11) — skip

-- 6. Re-add the FKs (now reference the UNIQUE constraint on email, not the PK)
ALTER TABLE auth.otp
    ADD CONSTRAINT otp_user_email_fkey
    FOREIGN KEY (user_email) REFERENCES auth.accounts(email)
    ON DELETE CASCADE;  -- verify original ON DELETE behaviour
ALTER TABLE auth.vessels
    ADD CONSTRAINT vessels_owner_email_fkey
    FOREIGN KEY (owner_email) REFERENCES auth.accounts(email)
    ON DELETE CASCADE;  -- verify original ON DELETE behaviour

-- 7. drop the now-redundant index on email (superseded by UNIQUE constraint)
DROP INDEX IF EXISTS accounts_email_idx;

-- urlencode_py_fn replacement in pure sql
CREATE OR REPLACE FUNCTION public.urlencode_fn(uri text)
RETURNS text
LANGUAGE sql
IMMUTABLE STRICT
AS $$
    SELECT string_agg(
        CASE
            WHEN ch ~ '[A-Za-z0-9_.~-]' THEN ch
            ELSE '%' || upper(to_hex(ascii(ch)))
        END, ''
    )
    FROM regexp_split_to_table(uri, '') AS ch;
$$;
COMMENT ON FUNCTION public.urlencode_fn(text)
    IS 'RFC 3986 URL encoding — pure SQL replacement for urlencode_py_fn. IMMUTABLE, zero plpython3u dependency.';
 
-- urlescape_py_fn replacement in pure sql
CREATE OR REPLACE FUNCTION public.urlescape_fn(original text)
RETURNS text
LANGUAGE sql
IMMUTABLE STRICT
AS $$
    SELECT string_agg(
        CASE
            WHEN ch ~ '[A-Za-z0-9_.~!*''();:@&=+$,/?#\[\]-]' THEN ch
            ELSE '%' || upper(to_hex(ascii(ch)))
        END, ''
    )
    FROM regexp_split_to_table(original, '') AS ch;
$$;
COMMENT ON FUNCTION public.urlescape_fn(text)
    IS 'URL component escaping — pure SQL replacement for urlescape_py_fn. IMMUTABLE, zero plpython3u dependency.';

DROP FUNCTION IF EXISTS api.pushover_subscribe_link_fn;
-- Update api.pushover_subscribe_link_fn, generate subscription link with SQL urlencode_fn, no plpython3u dependency
CREATE OR REPLACE FUNCTION api.pushover_subscribe_link_fn(OUT pushover_link jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
	DECLARE
        app_url text;
        otp_code text;
        pushover_app_url text;
        success text;
        failure text;
        email text := current_setting('user.email', true);
    BEGIN
--https://pushover.net/api/subscriptions#web
-- "https://pushover.net/subscribe/PostgSail-23uvrho1d5y6n3e"
-- + "?success=" + urlencode("https://beta.openplotter.cloud/api/rpc/pushover_fn?token=" + generate_otp_fn({{email}}))
-- + "&failure=" + urlencode("https://beta.openplotter.cloud/settings");
        -- get app_url
        SELECT
            value INTO app_url
        FROM
            public.app_settings
        WHERE
            name = 'app.url';
        -- get pushover url subscribe
        SELECT
            value INTO pushover_app_url
        FROM
            public.app_settings
        WHERE
            name = 'app.pushover_app_url';
        -- Generate OTP
        otp_code := api.generate_otp_fn(email);
        -- On success: redirect to API endpoint with OTP token
        SELECT CONCAT(
            '?success=',
            public.urlencode_fn(
                CONCAT(rtrim(app_url, '/'), '/pushover?token=', otp_code))
            )
            INTO success;
        -- On failure: redirect to user settings page
        SELECT CONCAT(
            '&failure=',
            public.urlencode_fn(CONCAT(rtrim(app_url, '/'), '/profile'))
            ) INTO failure;
        SELECT jsonb_build_object('link', CONCAT(pushover_app_url, success, failure)) INTO pushover_link;
    END;
$function$
;

COMMENT ON FUNCTION api.pushover_subscribe_link_fn(out jsonb) IS 'Generate Pushover subscription link';

-- Drop redundant urlescape function.
DROP FUNCTION IF EXISTS public.urlencode_py_fn(text);
DROP FUNCTION IF EXISTS public.urlescape_py_fn(text);

-- api.stays — generated duration column
ALTER TABLE api.stays
    ADD COLUMN IF NOT EXISTS duration interval
    GENERATED ALWAYS AS (departed - arrived) STORED;

COMMENT ON COLUMN api.stays.duration
    IS 'Computed stay duration (departed - arrived). GENERATED ALWAYS AS STORED — replaces inline expression in stats views.';

-- Prevent accidental large-payload inserts that would bloat the queue and cause
-- unnecessary TOAST overhead. 2048 chars is generous for all current channel
-- payloads (all are short IDs, emails, or small JSON strings).
-- The max payload identified was 300 chars
ALTER TABLE public.process_queue
    ADD CONSTRAINT process_queue_payload_length
        CHECK (char_length(payload) < 2048);

CREATE OR REPLACE FUNCTION auth.verify_otp_fn(token text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'auth', 'public', 'pg_catalog'
AS $$
DECLARE
    _email TEXT := NULL;
BEGIN
    IF token IS NULL THEN
        RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
    END IF;

    -- Atomically increment tries and return email if valid.
    -- Single UPDATE + RETURNING avoids the SELECT → UPDATE race condition
    -- of the original two-statement approach.
    UPDATE auth.otp
        SET otp_tries = otp_tries + 1
        WHERE otp_timestamp > NOW() AT TIME ZONE 'UTC' - INTERVAL '15 MINUTES'
          AND otp_tries < 3
          AND otp_pass = token
    RETURNING user_email INTO _email;

    RETURN _email;  -- NULL if expired, locked out, or wrong token
END;
$$;
COMMENT ON FUNCTION auth.verify_otp_fn(token text)
    IS 'Verify OTP — increments otp_tries atomically on every call. Returns email on success, NULL on failure. Token expires after 15 min or 3 attempts.';

-- Update api.export_logbook_gpx_trip_fn, avoid duplicate api.logbook scans
CREATE OR REPLACE FUNCTION api.export_logbook_gpx_trip_fn(_id integer)
 RETURNS "text/xml"
 LANGUAGE plpgsql
AS $function$
DECLARE
    app_settings jsonb;
BEGIN
    -- Validate input
    IF _id IS NULL OR _id < 1 THEN
        RAISE WARNING '-> export_logbook_gpx_trip_fn invalid input %', _id;
        RAISE EXCEPTION 'Invalid logbook id: %', _id
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    -- Retrieve application settings
    app_settings := get_app_url_fn();

    -- Generate GPX XML with structured track data
    RETURN xmlelement(name gpx,
                      xmlattributes( '1.1' as version,
                                     'PostgSAIL' as creator,
                                     'http://www.topografix.com/GPX/1/1' as xmlns,
                                     'http://www.opencpn.org' as "xmlns:opencpn",
                                     app_settings->>'app.url' as "xmlns:postgsail",
                                     'http://www.w3.org/2001/XMLSchema-instance' as "xmlns:xsi",
                                     'http://www.garmin.com/xmlschemas/GpxExtensions/v3' as "xmlns:gpxx",
                                     'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/GpxExtensions/v3 http://www8.garmin.com/xmlschemas/GpxExtensionsv3.xsd' as "xsi:schemaLocation"),

        -- Metadata section
        xmlelement(name metadata,
                   xmlelement(name link, xmlattributes(app_settings->>'app.url' as href),
                              xmlelement(name text, 'PostgSail'))),

        -- Track section
        xmlelement(name trk,
                   xmlelement(name name, l.name),
                   xmlelement(name desc, l.notes),
                   xmlelement(name link, xmlattributes(concat(app_settings->>'app.url', '/log/', l.id) as href),
                              xmlelement(name text, l.name)),
                   xmlelement(name extensions,
                              xmlelement(name "postgsail:log_id", l.id),
                              xmlelement(name "postgsail:link", concat(app_settings->>'app.url', '/log/', l.id)),
                              xmlelement(name "opencpn:guid", uuid_generate_v4()),
                              xmlelement(name "opencpn:viz", '1'),
                              xmlelement(name "opencpn:start", l._from_time),
                              xmlelement(name "opencpn:end", l._to_time)),

                   -- Track segments with point data
                   xmlelement(name trkseg, xmlagg(
                               xmlelement(name trkpt,
                                          xmlattributes( ST_Y(getvalue(point)::geometry) as lat, ST_X(getvalue(point)::geometry) as lon ),
                                          xmlelement(name time, getTimestamp(point))
                               )))
        )
    )::pg_catalog.xml
    FROM api.logbook l
    JOIN LATERAL (
        SELECT unnest(instants(l.trip)) AS point
    ) AS points ON true
    WHERE l.id = _id
	GROUP BY l.name, l.notes, l.id;
END;
$function$
;

COMMENT ON FUNCTION api.export_logbook_gpx_trip_fn(int4) IS 'Export a log trip entry to GPX XML format';

-- Update api.moorages_stays_view, remove unused stay_at join
CREATE OR REPLACE VIEW api.moorages_stays_view
WITH (security_invoker = true, security_barrier = true)
AS
    SELECT
        _to.name        AS _to_name,
        _to.id          AS _to_id,
        _to._to_time,
        _from.id        AS _from_id,
        _from.name      AS _from_name,
        _from._from_time,
        s.stay_code,
        s.duration,
        m.id,
        m.name
    FROM api.stays s
    JOIN api.moorages m
        ON m.id = s.moorage_id
    LEFT JOIN api.logbook _from
        ON _from._from_time = s.departed
    LEFT JOIN api.logbook _to
        ON _to._to_time = s.arrived
    WHERE s.departed IS NOT NULL
        AND s.name IS NOT NULL
    ORDER BY _to._to_time DESC;

COMMENT ON VIEW api.moorages_stays_view IS 'Moorages stay listing web view';

-- Update api.status_fn, remove redundant api.stay_at join
CREATE OR REPLACE FUNCTION api.status_fn(OUT status jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    in_route BOOLEAN := false;
BEGIN
    RAISE NOTICE '-> status_fn';

    SELECT EXISTS (
        SELECT 1 FROM api.logbook WHERE active IS TRUE LIMIT 1
    ) INTO in_route;

    IF in_route IS TRUE THEN
        -- In route: vessel is actively sailing/motoring
        SELECT jsonb_build_object(
            'status',   'In route',
            'location', m.name,
            'departed', l._from_time
        ) INTO status
        FROM api.logbook l
        JOIN api.moorages m ON m.id = l._from_moorage_id
        WHERE l.active IS TRUE;

    ELSE
        -- At rest: vessel is moored or anchored
        SELECT jsonb_build_object(
            'status',   (ARRAY['Unknown','Anchor','Mooring Buoy','Dock'])[s.stay_code],
            'location', m.name,
            'arrived',  s.arrived
        ) INTO status
        FROM api.stays s
        JOIN api.moorages m ON m.id = s.moorage_id
        WHERE s.active IS TRUE;
    END IF;
END
$function$;

COMMENT ON FUNCTION api.status_fn(OUT status jsonb) IS
    'Returns current vessel status: in-route with departure info, or at-rest with moorage name and arrival time.';

-- Update api.recover, fix jsonb string concatenation
CREATE OR REPLACE FUNCTION api.recover(email text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
	DECLARE
        _email CITEXT := email;
        _user_id TEXT := NULL;
        otp_pass TEXT := NULL;
        _reset_qs TEXT := NULL;
        user_settings jsonb := NULL;
    BEGIN
        IF _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'Invalid input'
                USING HINT = 'Check your parameter';
        END IF;
        SELECT user_id INTO _user_id FROM auth.accounts a WHERE a.email = _email;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invalid input'
                USING HINT = 'Check your parameter';
        END IF;
        -- Generate OTP
        otp_pass := api.generate_otp_fn(email);
        SELECT CONCAT('uuid=', _user_id, '&token=', otp_pass) INTO _reset_qs;
        -- Enable email_notifications
        PERFORM api.update_user_preferences_fn('{email_notifications}'::TEXT, True::TEXT);
        -- Send email/notifications
        user_settings := jsonb_build_object(
            'email', _email,
            'reset_qs', _reset_qs
        );
        PERFORM send_notification_fn('email_reset'::TEXT, user_settings);
        RETURN TRUE;
    END;
$function$
;

COMMENT ON FUNCTION api.recover(text) IS 'Send recover password email to reset password';

-- Update public.has_vessel_metadata_fn, improve query with direct join
CREATE OR REPLACE FUNCTION public.has_vessel_metadata_fn()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM auth.accounts a
        JOIN auth.vessels v  ON v.owner_email = a.email
        JOIN api.metadata m  ON m.vessel_id   = v.vessel_id
        WHERE a.email = current_setting('user.email', true)::public.citext
    );
END;
$function$;

COMMENT ON FUNCTION public.has_vessel_metadata_fn() IS 'Check if user has a vessel register';

-- Update api.telegram_otp_fn, fix string concatenation and error handling
CREATE OR REPLACE FUNCTION api.telegram_otp_fn(email text, OUT otp_code text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
    DECLARE
        _email CITEXT := email;
        user_settings jsonb := NULL;
    BEGIN
        IF _email IS NULL THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;
        -- Generate token
        otp_code := api.generate_otp_fn(_email);
        IF otp_code IS NOT NULL THEN
            -- Set user email into env to allow RLS update
            PERFORM set_config('user.email', _email, false);
            -- Send Notification
            user_settings := jsonb_build_object(
                'email', _email,
                'otp_code', otp_code
            );
            PERFORM send_notification_fn('telegram_otp'::TEXT, user_settings::JSONB);
        END IF;
    END;
$function$
;

COMMENT ON FUNCTION api.telegram_otp_fn(in text, out text) IS 'Telegram otp generation';

-- Update public.process_account_otp_validation_queue_fn, fix string concatenation and error handling
CREATE OR REPLACE FUNCTION public.process_account_otp_validation_queue_fn(_email text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
    DECLARE
        account_rec record;
        user_settings jsonb;
        app_settings jsonb;
        otp_code text;
    BEGIN
        IF _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        SELECT * INTO account_rec
            FROM auth.accounts
            WHERE email = _email;
        IF account_rec.email IS NULL OR account_rec.email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        -- Gather email and pushover app settings
        app_settings := get_app_settings_fn();
        otp_code := api.generate_otp_fn(_email);
        -- set user email variable
        PERFORM set_config('user.email', account_rec.email, false);
        -- Gather user settings
        user_settings := jsonb_build_object(
            'email', account_rec.email,
            'recipient', account_rec.first,
            'otp_code', otp_code
        );
        -- Send notification email, pushover
        PERFORM send_notification_fn('email_otp'::TEXT, user_settings::JSONB);
    END;
$function$
;

COMMENT ON FUNCTION public.process_account_otp_validation_queue_fn(text) IS 'process new account otp validation notification, deprecated';

-- Update api.monitoring_view, add vessel_id explicit filter
CREATE OR REPLACE VIEW api.monitoring_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT "time",
    ((now() AT TIME ZONE 'UTC'::text)::timestamp with time zone - "time") > 'PT1H10M'::interval AS offline,
    metrics -> 'environment.water.temperature'::text AS watertemperature,
    metrics -> 'environment.inside.temperature'::text AS insidetemperature,
    metrics -> 'environment.outside.temperature'::text AS outsidetemperature,
    metrics -> 'environment.wind.speedTrue'::text AS windspeedoverground,
    metrics -> 'environment.wind.directionTrue'::text AS winddirectiontrue,
    metrics -> 'environment.inside.relativeHumidity'::text AS insidehumidity,
    metrics -> 'environment.outside.relativeHumidity'::text AS outsidehumidity,
    metrics -> 'environment.outside.pressure'::text AS outsidepressure,
    metrics -> 'environment.inside.pressure'::text AS insidepressure,
    metrics -> 'electrical.batteries.House.capacity.stateOfCharge'::text AS batterycharge,
    metrics -> 'electrical.batteries.House.voltage'::text AS batteryvoltage,
    metrics -> 'environment.depth.belowTransducer'::text AS depth,
    jsonb_build_object('type', 'Feature', 'geometry', st_asgeojson(st_makepoint(longitude, latitude))::jsonb, 'properties', jsonb_build_object('name', current_setting('vessel.name'::text, false), 'latitude', latitude, 'longitude', longitude, 'time', "time", 'speedoverground', speedoverground, 'windspeedapparent', windspeedapparent, 'truewindspeed', COALESCE(metrics -> 'environment.wind.speedTrue'::text, NULL::jsonb), 'truewinddirection', COALESCE(metrics -> 'environment.wind.directionTrue'::text, NULL::jsonb), 'status', COALESCE(status, NULL::text))) AS geojson,
    current_setting('vessel.name'::text, false) AS name,
    status,
        CASE
            WHEN status <> 'moored'::text THEN ( SELECT logbook_active_geojson_fn() AS logbook_active_geojson_fn)
            WHEN status = 'moored'::text THEN ( SELECT stay_active_geojson_fn("time") AS stay_active_geojson_fn)
            ELSE NULL::jsonb
        END AS live
   FROM api.metrics m
   WHERE vessel_id = current_setting('vessel.id', false) -- explicit filter
  ORDER BY "time" DESC
 LIMIT 1;

COMMENT ON VIEW api.monitoring_view IS 'Monitoring static web view';

-- Update public.best_24h_distance_fn, rewrite in pure SQL with lateral join for performance
CREATE OR REPLACE FUNCTION public.best_24h_distance_fn(_vessel_id text)
RETURNS TABLE(
    best_distance_nm     numeric,
    window_start         timestamp with time zone,
    window_end           timestamp with time zone,
    anchor_log_id        integer,
    anchor_log_name      text,
    contributing_log_ids integer[],
    route_summary        text
)
LANGUAGE sql
AS $$
/*
  Algorithm (lateral join over sorted logbook):

  For each completed log entry A (the anchor):
    window_start = A._from_time
    window_end   = A._from_time + INTERVAL '24 hours'

    LATERAL subquery finds all legs I where I._from_time ∈ [window_start, window_end)
    and computes prorated distance for legs that extend past window_end:
      full_distance  if I._to_time <= window_end
      distance * (window_end - I._from_time) / (I._to_time - I._from_time)  otherwise

  The anchor with the highest SUM(prorated_distance) is returned.

  Complexity: O(N log N) via index on (vessel_id, _from_time).
  The original PL/pgSQL double FOR loop was O(N²).

  Preserves:
    - Prorated partial-leg distance for legs crossing the 24h boundary
    - contributing_log_ids integer[] for map highlighting
    - route_summary: departure of anchor leg → arrival of last contributing leg
    - window_end: actual _to_time of the last contributing leg (not anchor + 24h)
*/
WITH legs AS (
    -- Materialise the eligible logbook entries once.
    -- The index (vessel_id, _from_time ASC) on api.logbook covers this scan.
    SELECT
        id,
        name,
        _from_time,
        _to_time,
        distance,
        _from,
        _to
    FROM api.logbook
    WHERE vessel_id   = _vessel_id
      AND active      = false
      AND distance    IS NOT NULL
      AND distance    > 0
      AND _from_time  IS NOT NULL
      AND _to_time    IS NOT NULL
    ORDER BY _from_time ASC
),
windows AS (
    -- For each anchor leg A, aggregate all legs I that start within 24h.
    -- The LATERAL subquery replaces the original inner FOR loop.
    SELECT
        a.id            AS anchor_id,
        a.name          AS anchor_name,
        a._from_time    AS wstart,
        a._from         AS departure,

        -- Total prorated distance for this window
        lat.total_nm,

        -- Array of contributing log ids (ordered by start time)
        lat.log_ids,

        -- Last destination in the window (for route summary)
        lat.last_to,

        -- Actual end time: the _to_time of the last contributing leg
        -- (may be after window_end if the leg was prorated)
        lat.last_to_time

    FROM legs a
    CROSS JOIN LATERAL (
        SELECT
            ROUND(
                SUM(
                    CASE
                        -- Leg ends within the 24h window: full distance
                        WHEN i._to_time <= a._from_time + INTERVAL '24 hours'
                            THEN i.distance
                        -- Leg extends past window_end: prorate by time fraction
                        ELSE i.distance
                             * EXTRACT(EPOCH FROM (a._from_time + INTERVAL '24 hours' - i._from_time))
                             / NULLIF(EXTRACT(EPOCH FROM (i._to_time - i._from_time)), 0)
                    END
                )::numeric,
                2
            )                                                 AS total_nm,
            ARRAY_AGG(i.id ORDER BY i._from_time ASC)        AS log_ids,
            -- Last leg's destination and _to_time for window_end + route_summary
            (ARRAY_AGG(i._to       ORDER BY i._from_time DESC))[1] AS last_to,
            (ARRAY_AGG(i._to_time  ORDER BY i._from_time DESC))[1] AS last_to_time
        FROM legs i
        WHERE i._from_time >= a._from_time
          AND i._from_time <  a._from_time + INTERVAL '24 hours'
    ) lat
    WHERE lat.total_nm IS NOT NULL
      AND lat.total_nm > 0
)
-- Return only the single best window
SELECT
    w.total_nm                                    AS best_distance_nm,
    w.wstart                                      AS window_start,
    w.last_to_time                                AS window_end,
    w.anchor_id                                   AS anchor_log_id,
    w.anchor_name                                 AS anchor_log_name,
    w.log_ids                                     AS contributing_log_ids,
    w.departure || ' → ' || w.last_to             AS route_summary
FROM windows w
ORDER BY w.total_nm DESC NULLS LAST
LIMIT 1;
$$;

COMMENT ON FUNCTION public.best_24h_distance_fn(text) IS
    'Computes the best rolling 24-hour distance window for a vessel.
     Sums all completed logbook legs starting within any 24h window, with
     pro-rating for legs that extend past the window boundary.
     Returns: anchor log id, contributing log ids (for map highlighting),
     and route summary (departure → final destination of the window).';

-- Update public.nanoid, only a-z0-9 discard uppercase and default size changed from 12 → 14 to match the target format.
CREATE OR REPLACE FUNCTION public.nanoid(size integer DEFAULT 14)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
    id TEXT := '';
    bytes BYTEA := gen_random_bytes(size);
    alphabet TEXT := '0123456789abcdefghijklmnopqrstuvwxyz';
    byte INT;
BEGIN
    FOR i IN 0..size-1 LOOP
        byte := get_byte(bytes, i);
        id := id || substr(alphabet, (byte % 36) + 1, 1);
    END LOOP;
    RETURN id;
END;
$function$
;

COMMENT ON FUNCTION public.nanoid(int4) IS 'Generate a random alphanumeric ID (0-9a-z) of given length. Default size=14. For numeric-only IDs (e.g. OTP codes) use generate_uid_fn() instead.';

-- Update api.generate_otp_fn, increase OTP length to 8 digits for better security (100M combinations vs 1M for 6 digits), and add input validation.
CREATE OR REPLACE FUNCTION api.generate_otp_fn(email text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $$
DECLARE
    _email        CITEXT      := email;
    _email_check  text        := NULL;
    _otp_pass     VARCHAR(10) := NULL;
BEGIN
    IF email IS NULL OR _email IS NULL OR _email = '' THEN
        RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
    END IF;

    SELECT a.email INTO _email_check
        FROM auth.accounts a
        WHERE a.email = _email;

    IF _email_check IS NULL THEN
        RAISE WARNING '-> generate_otp_fn: unknown email [%]', email;
        RETURN NULL;
    END IF;

    SELECT public.generate_uid_fn(8) INTO _otp_pass;  -- was 6

    INSERT INTO auth.otp (user_email, otp_pass)
        VALUES (_email_check, _otp_pass)
        ON CONFLICT (user_email) DO UPDATE
            SET otp_pass      = EXCLUDED.otp_pass,
                otp_timestamp = NOW(),
                otp_tries     = 0;

    RETURN _otp_pass;
END;
$$;

COMMENT ON FUNCTION api.generate_otp_fn(email text) IS
    'Generate an 8-digit numeric OTP for the given email.
     On conflict resets otp_pass, otp_timestamp, and otp_tries = 0
     so the new token gets a full 3 attempts.
     Entropy: 10^8 = 100M combinations (was 10^6 for 6-digit).';

-- Update public.has_vessel_fn(), improve query with direct join and input validation
CREATE OR REPLACE FUNCTION public.has_vessel_fn() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_catalog'
    AS $$
    BEGIN
        RETURN EXISTS (
            SELECT 1
            FROM auth.vessels v
            JOIN auth.accounts a ON a.email = v.owner_email
            WHERE a.email = current_setting('user.email', true)::public.citext
        );
    END;
$$;
COMMENT ON FUNCTION public.has_vessel_fn() IS 'Check if user has a vessel register';

-- Add api.graph_logs_by_day_fn, count of completed logs by ISO day of week "01" … "07", zero-filled (all 7 days always present)
CREATE OR REPLACE FUNCTION api.graph_logs_by_day_fn(OUT charts jsonb)
RETURNS jsonb
LANGUAGE sql
AS $$
    WITH
    _vessel AS (
        SELECT current_setting('vessel.id', true) AS vessel_id
    ),
    day_counts AS (
        SELECT
            lpad(to_char(l._from_time, 'ID'), 2, '0') AS day,
            count(*)                                    AS count
        FROM api.logbook l, _vessel
        WHERE l.vessel_id  = _vessel.vessel_id
          AND l.active     = false
          AND l._from_time IS NOT NULL
        GROUP BY day
        ORDER BY day
    )
    SELECT
        -- Merge over zero-fill so all 7 days always appear
        '{"01":0,"02":0,"03":0,"04":0,"05":0,"06":0,"07":0}'::jsonb
        || jsonb_object_agg(d.day, d.count)
    FROM day_counts d;
$$;
 
COMMENT ON FUNCTION api.graph_logs_by_day_fn(OUT charts jsonb) IS
    'Count of completed logbook entries by ISO day of week for the current vessel.
     Output: { "01": N, ..., "07": N } (01=Mon, 07=Sun). All 7 days always present.
     FIX: added vessel_id isolation and active=false filter (was scanning all vessels).';
 
-- Add api.graph_logs_by_month_fn, count of completed logs by calendar month "01" … "12", zero-filled (all 12 months always present)
CREATE OR REPLACE FUNCTION api.graph_logs_by_month_fn(OUT charts jsonb)
RETURNS jsonb
LANGUAGE sql
AS $$
    WITH
    _vessel AS (
        SELECT current_setting('vessel.id', true) AS vessel_id
    ),
    month_counts AS (
        SELECT
            to_char(date_trunc('month', l._from_time), 'MM') AS month,
            count(*)                                          AS count
        FROM api.logbook l, _vessel
        WHERE l.vessel_id  = _vessel.vessel_id
          AND l.active     = false
          AND l._from_time IS NOT NULL
        GROUP BY month
        ORDER BY month
    )
    SELECT
        '{"01":0,"02":0,"03":0,"04":0,"05":0,"06":0,"07":0,"08":0,"09":0,"10":0,"11":0,"12":0}'::jsonb
        || jsonb_object_agg(m.month, m.count)
    FROM month_counts m;
$$;
 
COMMENT ON FUNCTION api.graph_logs_by_month_fn(OUT charts jsonb) IS
    'Count of completed logbook entries by calendar month for the current vessel.
     Output: { "01": N, ..., "12": N }. All 12 months always present.
     FIX: added vessel_id isolation and active=false filter (was scanning all vessels).';
 
-- Add api.graph_logs_by_year_fn, count of completed logs by calendar year, no zero-fill (only years with entries appear)
CREATE OR REPLACE FUNCTION api.graph_logs_by_year_fn(OUT charts jsonb)
RETURNS jsonb
LANGUAGE sql
AS $$
    WITH
    _vessel AS (
        SELECT current_setting('vessel.id', true) AS vessel_id
    )
    SELECT jsonb_object_agg(year, count ORDER BY year)
    FROM (
        SELECT
            to_char(l._from_time, 'YYYY') AS year,
            count(*)                       AS count
        FROM api.logbook l, _vessel
        WHERE l.vessel_id  = _vessel.vessel_id
          AND l.active     = false
          AND l._from_time IS NOT NULL
        GROUP BY year
    ) t;
$$;
 
COMMENT ON FUNCTION api.graph_logs_by_year_fn(OUT charts jsonb) IS
    'Count of completed logbook entries by calendar year for the current vessel.
     Output: { "2022": N, "2023": N, ... }. Only years with entries appear.
     FIX: added vessel_id isolation and active=false filter (was scanning all vessels).';
 
-- Update api.graph_logs_by_week_fn, count of completed logs by ISO week number "01" … "53"  (ISO 8601 week, Mon-based)
CREATE OR REPLACE FUNCTION api.graph_logs_by_week_fn(OUT charts jsonb)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
AS $$
    WITH
    _vessel AS (
        SELECT current_setting('vessel.id', true) AS vessel_id
    ),
    weeks AS (
        SELECT lpad(generate_series(1, 52)::text, 2, '0') AS wk
    ),
    raw AS (
        SELECT
            to_char(l._from_time, 'IW') AS wk,
            count(*)::int                AS cnt
        FROM api.logbook l, _vessel
        WHERE l.vessel_id  = _vessel.vessel_id
          AND l.active     = false
          AND l._from_time IS NOT NULL
        GROUP BY 1
    )
    SELECT jsonb_object_agg(w.wk, COALESCE(r.cnt, 0) ORDER BY w.wk)
    FROM weeks w
    LEFT JOIN raw r ON r.wk = w.wk;
$$;

COMMENT ON FUNCTION api.graph_logs_by_week_fn(OUT charts jsonb) IS
    'Count of completed logbook entries by ISO week number for the current vessel.
     Output: {"01":0, "02":3, ..., "52":0}. All 52 weeks always present (zero-filled).
     Uses ISO 8601 week numbering (IW): week 01 contains the first Thursday of January.
     Index: logbook_vessel_time_idx (vessel_id, _from_time DESC).';

-- Add api.graph_logs_by_year_month_fn, count of completed logs by calendar year and month, zero-filled by month (all 12 months always present per year).
CREATE OR REPLACE FUNCTION api.graph_logs_by_year_month_fn(OUT charts jsonb)
RETURNS jsonb
LANGUAGE sql
AS $$
    WITH _vessel AS (
        SELECT current_setting('vessel.id', true) AS id
    ),
    months AS (
        SELECT generate_series(1, 12) AS m
    ),
    raw AS (
        -- Index: logbook_vessel_time_idx (vessel_id, _from_time DESC)
        SELECT
            EXTRACT(year  FROM _from_time)::int AS yr,
            EXTRACT(month FROM _from_time)::int AS mo,
            count(*)::int                        AS cnt
        FROM api.logbook, _vessel
        WHERE vessel_id  = _vessel.id
          AND _from_time IS NOT NULL
          AND active     = false
        GROUP BY yr, mo
    ),
    years AS (
        SELECT DISTINCT yr FROM raw
    ),
    spine AS (
        SELECT
            y.yr,
            m.m,
            COALESCE(r.cnt, 0) AS cnt
        FROM years y
        CROSS JOIN months m
        LEFT JOIN raw r ON r.yr = y.yr AND r.mo = m.m
    ),
    by_year AS (
        SELECT
            yr::text                          AS year,
            jsonb_agg(cnt ORDER BY m)         AS monthly_counts
        FROM spine
        GROUP BY yr
    )
    SELECT jsonb_object_agg(year, monthly_counts)
    FROM by_year;
$$;

COMMENT ON FUNCTION api.graph_logs_by_year_month_fn() IS
    'Logbook counts per month per year. Returns {"2021":[0,...,2],...} (12 elements, Jan=index 0).
     Index: logbook_vessel_time_idx (vessel_id, _from_time DESC).';

-- Add graph_logs_by_year_week_fn, count of completed logs by ISO year and week, zero-filled by week (all 52 or 53 weeks always present per year).
CREATE OR REPLACE FUNCTION api.graph_logs_by_year_week_fn(OUT charts jsonb)
RETURNS jsonb
LANGUAGE sql
AS $$
WITH
_vessel AS (
    SELECT current_setting('vessel.id', true) AS id
),
-- Actual log counts per ISO year + week
raw AS (
    SELECT
        to_char(_from_time, 'IYYY') AS yr,
        to_char(_from_time, 'IW')   AS wk,
        count(*)::int               AS cnt
    FROM api.logbook, _vessel
    WHERE vessel_id  = _vessel.id
      AND _from_time IS NOT NULL
      AND active     = false
    GROUP BY yr, wk
),
-- Year range present in data
years AS (
    SELECT DISTINCT yr FROM raw
),
-- ISO week count per year: a year has 53 ISO weeks when Dec 28 falls in week 53
-- generate_series produces lpad'd week strings matching the 'IW' format
week_spine AS (
    SELECT
        y.yr,
        lpad(w::text, 2, '0') AS wk,
        0                     AS cnt
    FROM years y
    CROSS JOIN LATERAL (
        SELECT generate_series(1,
            -- 53 weeks if Dec 28 of this ISO year is in week 53, else 52
            CASE WHEN to_char(
                    make_date(y.yr::int, 12, 28),
                    'IW') = '53'
                 THEN 53 ELSE 52
            END
        )
    ) AS w(w)
),
-- Merge spine with actuals — actual count wins on conflict
merged AS (
    SELECT yr, wk, cnt FROM raw
    UNION ALL
    SELECT s.yr, s.wk, s.cnt
    FROM week_spine s
    WHERE NOT EXISTS (
        SELECT 1 FROM raw r
        WHERE r.yr = s.yr AND r.wk = s.wk
    )
),
by_year AS (
    SELECT
        yr,
        jsonb_object_agg(wk, cnt ORDER BY wk) AS weekly_counts
    FROM merged
    GROUP BY yr
)
SELECT jsonb_object_agg(yr, weekly_counts ORDER BY yr)
FROM by_year;
$$;

COMMENT ON FUNCTION api.graph_logs_by_year_week_fn() IS
    'Logbook counts per ISO week per year, zero-filled.
     Returns {"2021":{"01":0,"02":0,...,"52":N,...},...}.
     All 52 (or 53 for long ISO years) weeks present per year — weeks with no
     logs show count 0 so heatmap charts render consistent grids.
     ISO year/week (IYYY/IW) avoids calendar-year boundary splits.';

-- Add api.graph_logs_by_month_day_fn, count of completed logs by calendar month and day of week, zero-filled by day (all 7 days always present per month).
CREATE OR REPLACE FUNCTION api.graph_logs_by_month_day_fn(OUT charts jsonb)
RETURNS jsonb
LANGUAGE sql
AS $$
    WITH _vessel AS (
        SELECT current_setting('vessel.id', true) AS id
    ),
    months AS (SELECT generate_series(1, 12) AS m),
    days   AS (SELECT generate_series(1, 7)  AS d),
    raw AS (
        -- Index: logbook_vessel_time_idx (vessel_id, _from_time DESC)
        SELECT
            EXTRACT(month  FROM _from_time)::int AS mo,
            EXTRACT(isodow FROM _from_time)::int AS dow,
            count(*)::int                         AS cnt
        FROM api.logbook, _vessel
        WHERE vessel_id  = _vessel.id
          AND _from_time IS NOT NULL
          AND active     = false
        GROUP BY mo, dow
    ),
    spine AS (
        SELECT
            m.m                AS mo,
            d.d                AS dow,
            COALESCE(r.cnt, 0) AS cnt
        FROM months m
        CROSS JOIN days d
        LEFT JOIN raw r ON r.mo = m.m AND r.dow = d.d
    ),
    by_month AS (
        SELECT
            mo,
            jsonb_object_agg((dow - 1)::text, cnt ORDER BY dow) AS day_counts
        FROM spine
        GROUP BY mo
    )
    SELECT jsonb_agg(day_counts ORDER BY mo)
    FROM by_month;
$$;

COMMENT ON FUNCTION api.graph_logs_by_month_day_fn() IS
    'Logbook heatmap: 12-element array (Jan=0..Dec=11), each element {0:Mon..6:Sun}.
     Index: logbook_vessel_time_idx (vessel_id, _from_time DESC).';

-- Add api.graph_logs_network_fn, pre-aggregated network graph data for route visualisation: nodes (moorages) + edges (routes).
CREATE OR REPLACE FUNCTION api.graph_logs_network_fn(OUT charts jsonb)
RETURNS jsonb
LANGUAGE sql
AS $$
    WITH _vessel AS (
        SELECT current_setting('vessel.id', true) AS id
    ),
    routes AS (
        SELECT
            _from                                AS source,
            _to                                  AS target,
            count(*)::int                        AS trips,
            round(sum(distance)::numeric, 1)     AS total_distance,
            round(
                extract(epoch FROM sum(duration)) / 3600.0
            , 1)                                 AS total_duration_hrs
        FROM api.logbook, _vessel
        WHERE vessel_id  = _vessel.id
          AND active     = false
          AND _from      IS NOT NULL
          AND _to        IS NOT NULL
          AND _from_time IS NOT NULL
        GROUP BY _from, _to
    ),
    node_counts AS (
        SELECT moorage, sum(visits) AS visits
        FROM (
            SELECT source AS moorage, sum(trips) AS visits FROM routes GROUP BY source
            UNION ALL
            SELECT target AS moorage, sum(trips) AS visits FROM routes GROUP BY target
        ) t
        GROUP BY moorage
    ),
    nodes AS (
        SELECT jsonb_agg(
            jsonb_build_object('name', moorage, 'visits', visits)
            ORDER BY visits DESC
        ) AS data
        FROM node_counts
    ),
    edges AS (
        SELECT jsonb_agg(
            jsonb_build_object(
                'source',   source,
                'target',   target,
                'count',    trips,
                'distance', total_distance,
                'duration', total_duration_hrs
            )
            ORDER BY trips DESC
        ) AS data
        FROM routes
    )
    SELECT jsonb_build_object(
        'nodes', COALESCE(nodes.data, '[]'::jsonb),
        'edges', COALESCE(edges.data, '[]'::jsonb)
    )
    FROM nodes, edges;
$$;

COMMENT ON FUNCTION api.graph_logs_network_fn() IS
    'Network graph data for sailing route visualisation.
     Returns all routes pre-aggregated; min_trips and weightBy filtering done client-side.
     nodes:[{name,visits}], edges:[{source,target,count,distance,duration_hrs}].
     Index: logbook_vessel_time_idx (vessel_id, _from_time DESC).';

-- Update api.vessel_activity_fn, add vessel_id filter + active filter (don't count deleted/in-progress)
CREATE OR REPLACE FUNCTION api.vessel_activity_fn()
RETURNS jsonb
LANGUAGE sql
AS $$
    WITH
    _vessel AS (
        -- Resolve once, reuse across all CTEs.
        -- missing_ok=true matches user_role RLS pattern: returns NULL (empty result)
        -- on stale JWT rather than raising an exception.
        SELECT current_setting('vessel.id', true) AS vessel_id
    ),
    log_counts AS (
        SELECT
            COUNT(*)                                             AS total,
            COUNT(*) FILTER (
                WHERE _from_time >= NOW() - INTERVAL '30 days'
            )                                                    AS last_30d,
            COUNT(*) FILTER (
                WHERE _from_time >= NOW() - INTERVAL '60 days'
                  AND _from_time <  NOW() - INTERVAL '30 days'
            )                                                    AS prev_30d
        FROM api.logbook l, _vessel
        WHERE l.active = false
          AND l.vessel_id = _vessel.vessel_id
    ),
    stay_counts AS (
        SELECT
            COUNT(*)                                             AS total,
            COUNT(*) FILTER (
                WHERE arrived >= NOW() - INTERVAL '30 days'
            )                                                    AS last_30d,
            COUNT(*) FILTER (
                WHERE arrived >= NOW() - INTERVAL '60 days'
                  AND arrived <  NOW() - INTERVAL '30 days'
            )                                                    AS prev_30d
        FROM api.stays s, _vessel
        WHERE s.active = false
          AND s.vessel_id = _vessel.vessel_id
    ),
    moorage_counts AS (
        SELECT
            COUNT(*)                                              AS total,
            -- New unique places: moorage whose FIRST ever stay arrived in last 30 days
            -- Uses stays.arrived (actual visit time) not moorages.created_at (row insert time)
            -- created_at reflects when the cron job processed the stay, not when it was visited
            COUNT(*) FILTER (
                WHERE m.id IN (
                    SELECT s.moorage_id
                    FROM api.stays s, _vessel
                    WHERE s.vessel_id    = _vessel.vessel_id
                    AND s.active       = false
                    AND s.moorage_id   IS NOT NULL
                    GROUP BY s.moorage_id
                    HAVING MIN(s.arrived) >= NOW() - INTERVAL '30 days'
                )
            )                                                    AS new_last_30d
        FROM api.moorages m, _vessel
        WHERE m.vessel_id = _vessel.vessel_id
    ),
    moorage_visits AS (
        SELECT
            COUNT(*) FILTER (
                WHERE s.arrived >= NOW() - INTERVAL '30 days'
            )                                                    AS visits_last_30d,
            COUNT(*) FILTER (
                WHERE s.arrived >= NOW() - INTERVAL '60 days'
                  AND s.arrived <  NOW() - INTERVAL '30 days'
            )                                                    AS visits_prev_30d,
            COUNT(DISTINCT m.country) FILTER (
                WHERE s.arrived >= NOW() - INTERVAL '30 days'
                  AND m.country IS NOT NULL
            )                                                    AS countries_last_30d,
            COUNT(DISTINCT m.country) FILTER (
                WHERE m.country IS NOT NULL
            )                                                    AS countries_total
        FROM api.stays s
        JOIN api.moorages m ON m.id = s.moorage_id
        CROSS JOIN _vessel
        WHERE s.active = false
          AND s.vessel_id = _vessel.vessel_id
          AND m.vessel_id = _vessel.vessel_id
    )
    SELECT jsonb_build_object(
        'logs', jsonb_build_object(
            'total',    lc.total,
            'last_30d', lc.last_30d,
            'delta',    lc.last_30d - lc.prev_30d,
            'pct',      CASE
                            WHEN lc.prev_30d = 0 THEN NULL
                            ELSE ROUND(((lc.last_30d - lc.prev_30d)::numeric
                                        / lc.prev_30d) * 100, 1)
                        END
        ),
        'stays', jsonb_build_object(
            'total',    sc.total,
            'last_30d', sc.last_30d,
            'delta',    sc.last_30d - sc.prev_30d,
            'pct',      CASE
                            WHEN sc.prev_30d = 0 THEN NULL
                            ELSE ROUND(((sc.last_30d - sc.prev_30d)::numeric
                                        / sc.prev_30d) * 100, 1)
                        END
        ),
        'moorages', jsonb_build_object(
            'total',              mc.total,
            'new_last_30d',       mc.new_last_30d,
            'visits_last_30d',    mv.visits_last_30d,
            'visits_delta',       mv.visits_last_30d - mv.visits_prev_30d,
            'visits_pct',         CASE
                                      WHEN mv.visits_prev_30d = 0 THEN NULL
                                      ELSE ROUND(
                                          ((mv.visits_last_30d - mv.visits_prev_30d)::numeric
                                           / mv.visits_prev_30d) * 100, 1)
                                  END,
            'countries_last_30d', mv.countries_last_30d,
            'countries_total',    mv.countries_total
        )
    )
    FROM log_counts lc, stay_counts sc, moorage_counts mc, moorage_visits mv;
$$;

COMMENT ON FUNCTION api.vessel_activity_fn() IS
    'Count logbook, stays and moorages for the current vessel with 30-day rolling activity metrics.
     Explicit vessel_id = current_setting(''vessel.id'') filter on all CTEs ensures correct isolation.
     logs/stays: total + last_30d + delta and pct vs prior 30-day window (NULL when prev=0).
     moorages: exploration metrics — new places discovered, visit activity, and country range.';

-- Update api.metrics_explore_view, Optimize query with an explicit vessel_id filter
CREATE OR REPLACE VIEW api.metrics_explore_view
WITH (security_invoker='true', security_barrier='true') AS
    WITH raw_metrics AS (
        SELECT time, metrics
        FROM api.metrics
        WHERE vessel_id = current_setting('vessel.id', true)
        ORDER BY time DESC
        LIMIT 1
    )
    SELECT
        raw_metrics.time,
        kv.key,
        kv.value
    FROM raw_metrics,
        LATERAL jsonb_each_text(raw_metrics.metrics) kv(key, value)
    ORDER BY kv.key;

COMMENT ON VIEW api.metrics_explore_view IS
    'Expands all SignalK keys from the vessel''s latest metric row.
     Used to discover available paths for custom configuration mapping.';

-- Clean up old stats functions
DROP FUNCTION IF EXISTS api.stats_logs_fn();
DROP FUNCTION IF EXISTS api.stats_logs_fn(text, text);
DROP FUNCTION IF EXISTS api.stats_logs_fn(text, text, OUT jsonb);
DROP FUNCTION IF EXISTS api.stats_stays_fn();
DROP FUNCTION IF EXISTS api.stats_stays_fn(text, text);
DROP FUNCTION IF EXISTS api.stats_stays_fn(text, text, OUT jsonb);
DROP FUNCTION IF EXISTS api.stats_fn();
DROP FUNCTION IF EXISTS api.stats_fn(text, text);
DROP FUNCTION IF EXISTS api.stats_fn(text, text, OUT jsonb);

-- Update api.stats_logs_fn, rewrite with index use and explicit filter
CREATE OR REPLACE FUNCTION api.stats_logs_fn(
    start_date  timestamptz DEFAULT NULL,
    end_date    timestamptz DEFAULT NULL,
    OUT stats   jsonb
)
RETURNS jsonb
LANGUAGE sql
AS $$
WITH
-- Resolve vessel once; reused across all CTEs
_vessel AS (
    SELECT current_setting('vessel.id', true) AS vessel_id
),
 
-- -------------------------------------------------------------------------
-- Base scan: completed logs in the requested window
-- Uses logbook_vessel_id_idx (vessel_id) + active=false + time range filter
-- _to_time IS NOT NULL guard: active=false guarantees it in practice but
-- makes the range predicate safe and visible to the planner
-- -------------------------------------------------------------------------
logs_base AS (
    SELECT
        l.id,
        l._from_time,
        l._to_time,
        l.avg_speed,
        l.max_speed,
        l.max_wind_speed,
        l.distance,
        l.duration
    FROM api.logbook l, _vessel
    WHERE l.vessel_id    = _vessel.vessel_id
      AND l.active       = false
      AND l.trip         IS NOT NULL
      AND l._from_time   IS NOT NULL
      AND l._to_time     IS NOT NULL
      AND l._from_time   >= COALESCE(start_date, '-infinity'::timestamptz)
      AND l._to_time     <= COALESCE(end_date,   'infinity'::timestamptz)
),
 
-- -------------------------------------------------------------------------
-- Single aggregation pass — all counts, sums and maxima
-- -------------------------------------------------------------------------
logs_agg AS (
    SELECT
        COUNT(*)                AS count,
        MIN(_from_time)         AS first_date,
        MAX(_to_time)           AS last_date,
        MAX(max_speed)          AS max_speed,
        MAX(max_wind_speed)     AS max_wind_speed,
        MAX(distance)           AS max_distance,
        SUM(distance)           AS sum_distance,
        MAX(duration)           AS max_duration,
        SUM(duration)           AS sum_duration
    FROM logs_base
),
 
-- -------------------------------------------------------------------------
-- Record-holder IDs: two-CTE pattern required because PostgreSQL does not
-- allow window functions inside FILTER clauses.
--   Step 1 — ranked: materialise rank values as plain integer columns
--   Step 2 — max_ids: FILTER on those plain integers (no window fn here)
-- MIN(id) on ties: deterministic (lowest id wins), consistent with original.
-- -------------------------------------------------------------------------
ranked AS (
    SELECT
        id,
        RANK() OVER (ORDER BY max_speed      DESC NULLS LAST) AS rk_speed,
        RANK() OVER (ORDER BY max_wind_speed DESC NULLS LAST) AS rk_wind,
        RANK() OVER (ORDER BY distance       DESC NULLS LAST) AS rk_dist,
        RANK() OVER (ORDER BY duration       DESC NULLS LAST) AS rk_dur
    FROM logs_base
),
max_ids AS (
    SELECT
        MIN(id) FILTER (WHERE rk_speed = 1) AS max_speed_id,
        MIN(id) FILTER (WHERE rk_wind  = 1) AS max_wind_speed_id,
        MIN(id) FILTER (WHERE rk_dist  = 1) AS max_distance_id,
        MIN(id) FILTER (WHERE rk_dur   = 1) AS max_duration_id
    FROM ranked
),
 
-- -------------------------------------------------------------------------
-- Vessel name — PK lookup on metadata (vessel_id is PRIMARY KEY)
-- -------------------------------------------------------------------------
meta AS (
    SELECT m.name
    FROM api.metadata m, _vessel
    WHERE m.vessel_id = _vessel.vessel_id
),
 
-- -------------------------------------------------------------------------
-- SignalK plugin connection bounds — respects the same date window as logs.
-- Returns first/last plugin contact within [start_date, end_date].
-- NULL when no metrics exist in the window (consistent with first_date/last_date).
-- Uses metrics_vessel_id_time_idx (vessel_id, time DESC).
-- -------------------------------------------------------------------------
metrics_bounds AS (
    SELECT
        MIN(m.time) AS metrics_first,
        MAX(m.time) AS metrics_last
    FROM api.metrics m, _vessel
    WHERE m.vessel_id = _vessel.vessel_id
      AND m.time >= COALESCE(start_date, '-infinity'::timestamptz)
      AND m.time <= COALESCE(end_date,   'infinity'::timestamptz)
),
 
-- -------------------------------------------------------------------------
-- Best 24h sailing window — skipped when a date filter is active.
-- best_24h_distance_fn always scans full vessel history regardless of the
-- date range passed here. Returning it inside a filtered call would give a
-- best-24h window that may fall outside the requested date range, which is
-- misleading. The guard uses the raw PARAMETER values (start_date, end_date)
-- not any COALESCEd locals — NULL means "no filter was requested".
-- -------------------------------------------------------------------------
best24h AS (
    SELECT
        b.best_distance_nm,
        b.window_start,
        b.anchor_log_id,
        b.route_summary
    FROM public.best_24h_distance_fn(
        (SELECT vessel_id FROM _vessel)
    ) b
    WHERE start_date IS NULL
      AND end_date   IS NULL
)
 
-- -------------------------------------------------------------------------
-- Assemble result
-- CROSS JOIN is correct: logs_agg, max_ids, meta, metrics_bounds are all
-- guaranteed single-row CTEs. COALESCE to '{}' is a safe fallback for
-- vessels with no logbook data yet.
-- -------------------------------------------------------------------------
SELECT COALESCE(
    jsonb_build_object(
        -- Vessel identity
        'name',                  m.name,
 
        -- Sailing activity time bounds (from logbook)
        'first_date',            a.first_date,
        'last_date',             a.last_date,
 
        -- SignalK plugin connection time bounds (from metrics, always all-time)
        'metrics_first',         mb.metrics_first,
        'metrics_last',          mb.metrics_last,
 
        -- Totals
        'count',                 a.count,
        'sum_distance',          a.sum_distance,
        'sum_duration',          a.sum_duration,
 
        -- Records with deep-link IDs
        'max_speed',             a.max_speed,
        'max_speed_id',          i.max_speed_id,
        'max_wind_speed',        a.max_wind_speed,
        'max_wind_speed_id',     i.max_wind_speed_id,
        'max_distance',          a.max_distance,
        'max_distance_id',       i.max_distance_id,
        'max_duration',          a.max_duration,
        'max_duration_id',       i.max_duration_id,
 
        -- Formatted longest trip summary
        -- FIX 3: CASE prevents CONCAT from producing ' NM,  hours' on empty range
        'longest_nonstop_sail',  CASE
                                     WHEN a.max_distance IS NULL THEN NULL
                                     ELSE CONCAT(
                                         a.max_distance, ' NM, ',
                                         a.max_duration, ' hours'
                                     )
                                 END,
 
        -- Best 24h window — NULL when date filter is active (see best24h CTE)
        'best_24h_distance_nm',  (SELECT best_distance_nm FROM best24h),
        'best_24h_window_start', (SELECT window_start     FROM best24h),
        'best_24h_log_id',       (SELECT anchor_log_id    FROM best24h),
        'best_24h_route',        (SELECT route_summary    FROM best24h)
    ),
    '{}'::jsonb
)
FROM logs_agg     a
CROSS JOIN max_ids       i
CROSS JOIN meta          m
CROSS JOIN metrics_bounds mb;
$$;

COMMENT ON FUNCTION api.stats_logs_fn(timestamptz, timestamptz, OUT jsonb) IS
    'Logbook statistics for the current vessel within an optional date range.
     Pass NULL for both parameters to get all-time statistics (default).
 
     Output fields:
       name                — vessel name from metadata
       first_date          — _from_time of earliest completed log in range
       last_date           — _to_time of latest completed log in range
       metrics_first       — earliest SignalK plugin contact (all-time, not date-filtered)
       metrics_last        — latest SignalK plugin contact (all-time, not date-filtered)
       count               — number of completed logs in range
       sum_distance        — total distance sailed (NM)
       sum_duration        — total time underway (interval)
       max_speed           — highest recorded max_speed, with max_speed_id for deep-link
       max_wind_speed      — highest recorded wind speed, with max_wind_speed_id
       max_distance        — longest single leg, with max_distance_id
       max_duration        — longest single leg by time, with max_duration_id
       longest_nonstop_sail — formatted: "X NM, Y hours" (NULL when no logs in range)
       best_24h_distance_nm — best 24h rolling window distance (NULL when date-filtered)
       best_24h_window_start — start of that window (NULL when date-filtered)
       best_24h_log_id       — anchor log id for map highlight (NULL when date-filtered)
       best_24h_route        — "from → to" summary (NULL when date-filtered)
 
     Replaces api.stats_logs_view (now a deprecated shim over this function).
 
     Design notes:
       - VOLATILE (not STABLE): reads current_setting() which is session state,
         not a parameter; STABLE would allow incorrect cross-user plan caching.
       - Explicit vessel_id filter on all CTEs: correct under admin role where
         RLS is USING(true) and would otherwise return cross-vessel counts.
       - best_24h guards on raw parameter NULLs: callers must pass NULL (not a
         COALESCEd substitute) to receive best_24h data. stats_fn passes the
         original NULLs unchanged for this reason.
       - COALESCE result to ''{}'': safe empty return for new vessels with no logs.';

-- Update api.stats_stays_fn
CREATE OR REPLACE FUNCTION api.stats_stays_fn(
    start_date  timestamptz DEFAULT NULL,
    end_date    timestamptz DEFAULT NULL,
    OUT stats   jsonb
)
RETURNS jsonb
LANGUAGE sql
AS $$
WITH
_vessel AS (
    SELECT current_setting('vessel.id', true) AS vessel_id
),
-- Base: all completed stays in the requested window
stays_base AS (
    SELECT
        s.moorage_id,
        s.duration,
        s.stay_code
    FROM api.stays s, _vessel
    WHERE s.vessel_id = _vessel.vessel_id
      AND s.active    = false
      AND s.arrived   >= COALESCE(start_date, '1970-01-01')
      AND s.departed  <= COALESCE(end_date, NOW()) + INTERVAL '23 hours 59 minutes'
),
-- Moorage-level aggregation — one row per unique moorage visited
moorage_agg AS (
    SELECT
        s.moorage_id,
        SUM(s.duration) AS total_duration,
        COUNT(*)        AS stay_count
    FROM stays_base s
    GROUP BY s.moorage_id
),
-- Enrich with moorage metadata (home_flag, stay_code, country)
moorage_detail AS (
    SELECT
        m.id,
        m.home_flag,
        m.stay_code,
        ma.total_duration
    FROM api.moorages m
    JOIN moorage_agg ma ON ma.moorage_id = m.id
    , _vessel
    WHERE m.vessel_id = _vessel.vessel_id
),
-- Scalar aggregates
agg AS (
    SELECT
        COUNT(*)         FILTER (WHERE home_flag IS TRUE)  AS home_ports,
        COUNT(*)                                           AS unique_moorages,
        COALESCE(SUM(total_duration) FILTER (WHERE home_flag IS TRUE),  '0'::interval) AS time_at_home_ports,
        COALESCE(SUM(total_duration) FILTER (WHERE home_flag IS FALSE), '0'::interval) AS time_spent_away
    FROM moorage_detail
),
-- Stay-type breakdown for away time
-- Avoid join api.stays_at for the canonical description string
-- stay_code 1=Unknown, 2=Anchor, 3=Mooring Buoy, 4=Dock
away_by_type AS (
    SELECT
        (ARRAY['Unknown','Anchor','Mooring Buoy','Dock'])[md.stay_code] AS description,
        SUM(md.total_duration) AS duration
    FROM moorage_detail md
    WHERE md.home_flag IS FALSE
    GROUP BY md.stay_code
    ORDER BY md.stay_code
)
SELECT jsonb_build_object(
    'home_ports',         a.home_ports,
    'unique_moorages',    a.unique_moorages,
    'time_at_home_ports', a.time_at_home_ports,
    'time_spent_away',    a.time_spent_away,
    -- Replaces stats_moorages_away_view (was a separate multi-row endpoint)
    'time_spent_away_by', COALESCE(
        (SELECT jsonb_agg(
            jsonb_build_object(
                'description', t.description,
                'duration',    t.duration
            )
            ORDER BY t.description
        ) FROM away_by_type t),
        '[]'::jsonb
    )
)
FROM agg a;
$$;
 
COMMENT ON FUNCTION api.stats_stays_fn(timestamptz, timestamptz, OUT jsonb) IS
    'Stays and moorage statistics for the current vessel within a date range (NULL = all-time).
     Replaces api.stats_moorages_view and api.stats_moorages_away_view:
       - date range filter
       - time_spent_away_by breakdown by stay type folded in as a JSONB array
         [ { description, duration }, ... ] ordered by stay_code
     Reads api.stays + api.moorages directly — no moorage_view dependency.
     Explicit vessel_id filter on all CTEs.';
 
-- Update api.stats_fn,
CREATE OR REPLACE FUNCTION api.stats_fn(
    start_date  timestamptz DEFAULT NULL,
    end_date    timestamptz DEFAULT NULL,
    OUT stats   jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
/*
  Composite statistics function: delegates to stats_logs_fn + stats_stays_fn
  for the base aggregates, then adds top-5 rankings in a single pass each
  over logbook and stays.
  Both sub-functions are independent PostgREST endpoints and remain callable
  standalone — stats_fn is purely additive.
*/
DECLARE
    _vessel_id  TEXT        := current_setting('vessel.id', true);
    _start      TIMESTAMPTZ := COALESCE(start_date, '1970-01-01');
    _end_incl   TIMESTAMPTZ := COALESCE(end_date, NOW()) + INTERVAL '23 hours 59 minutes';
BEGIN
    RAISE NOTICE '--> stats_fn start[%] end[%]', _start, _end_incl;
 
    -- Base aggregates from the two standalone functions
    stats := jsonb_build_object(
        'stats_logs',     api.stats_logs_fn(start_date, end_date),
        'stats_moorages', api.stats_stays_fn(start_date, end_date)
    );
 
    -- Top-5 rankings — single logbook scan, single stays scan
    WITH
    -- -----------------------------------------------------------------------
    -- Logbook top-5s
    -- -----------------------------------------------------------------------
    logs_base AS (
        SELECT id, avg_speed, max_speed, max_wind_speed, distance, duration
        FROM api.logbook
        WHERE vessel_id  = _vessel_id
          AND active     = false
          AND trip       IS NOT NULL
          AND _from_time >= _start
          AND _to_time   <= _end_incl
    ),
    logs_top_speed AS (
        SELECT id, max_speed
        FROM logs_base
        WHERE max_speed IS NOT NULL
        ORDER BY max_speed DESC NULLS LAST
        LIMIT 5
    ),
    logs_top_avg_speed AS (
        SELECT id, avg_speed
        FROM logs_base
        WHERE avg_speed IS NOT NULL
        ORDER BY avg_speed DESC NULLS LAST
        LIMIT 5
    ),
    logs_top_wind_speed AS (
        SELECT id, max_wind_speed
        FROM logs_base
        WHERE max_wind_speed IS NOT NULL
        ORDER BY max_wind_speed DESC NULLS LAST
        LIMIT 5
    ),
    logs_top_distance AS (
        SELECT id
        FROM logs_base
        WHERE distance IS NOT NULL
        ORDER BY distance DESC NULLS LAST
        LIMIT 5
    ),
    logs_top_duration AS (
        SELECT id
        FROM logs_base
        WHERE duration IS NOT NULL
        ORDER BY duration DESC NULLS LAST
        LIMIT 5
    ),
    -- -----------------------------------------------------------------------
    -- Moorage top-5s — single stays scan, no moorage_view dependency
    -- -----------------------------------------------------------------------
    stays_agg AS (
        SELECT
            s.moorage_id,
            SUM(s.duration) AS total_duration,
            COUNT(s.id)     AS reference_count
        FROM api.stays s
        WHERE s.vessel_id  = _vessel_id
          AND s.active     = false
          AND s.arrived    >= _start
          AND s.departed   <= _end_incl
        GROUP BY s.moorage_id
    ),
    moorages AS (
        SELECT
            m.id,
            m.country,
            sa.total_duration  AS dur,
            sa.reference_count AS ref_count
        FROM api.moorages m
        JOIN stays_agg sa ON sa.moorage_id = m.id
        WHERE m.vessel_id = _vessel_id
    ),
    moorages_top_arrivals AS (
        SELECT id, ref_count
        FROM moorages
        ORDER BY ref_count DESC NULLS LAST
        LIMIT 5
    ),
    moorages_top_duration AS (
        SELECT id, dur
        FROM moorages
        ORDER BY dur DESC NULLS LAST
        LIMIT 5
    ),
    moorages_countries AS (
        SELECT DISTINCT country
        FROM moorages
        WHERE country IS NOT NULL
          AND country <> 'unknown'
        ORDER BY country
        LIMIT 5
    )
    SELECT stats || jsonb_build_object(
        'logs_top_speed',         (SELECT jsonb_agg(t) FROM logs_top_speed         t),
        'logs_top_avg_speed',     (SELECT jsonb_agg(t) FROM logs_top_avg_speed     t),
        'logs_top_wind_speed',    (SELECT jsonb_agg(t) FROM logs_top_wind_speed    t),
        'logs_top_distance',      (SELECT jsonb_agg(t.id) FROM logs_top_distance   t),
        'logs_top_duration',      (SELECT jsonb_agg(t.id) FROM logs_top_duration   t),
        'moorages_top_arrivals',  (SELECT jsonb_agg(t) FROM moorages_top_arrivals  t),
        'moorages_top_duration',  (SELECT jsonb_agg(t) FROM moorages_top_duration  t),
        'moorages_top_countries', (SELECT jsonb_agg(t.country) FROM moorages_countries t)
    ) INTO stats;
END;
$$;
 
COMMENT ON FUNCTION api.stats_fn(timestamptz, timestamptz, OUT jsonb) IS
    'Composite statistics for the current vessel within a date range (NULL = all-time).
     Delegates base aggregates to stats_logs_fn + stats_stays_fn (both remain
     independently callable as PostgREST endpoints), then adds top-5 rankings
     for speed, wind, distance, duration, and moorage arrivals/duration/countries.
     Output keys:
       stats_logs     : full stats_logs_fn output (see that function for field list)
       stats_moorages : full stats_stays_fn output (see that function for field list)
       logs_top_speed / logs_top_avg_speed / logs_top_wind_speed : [{id, value}, ...]
       logs_top_distance / logs_top_duration                     : [id, ...]
       moorages_top_arrivals / moorages_top_duration             : [{id, value}, ...]
       moorages_top_countries                                    : [country, ...]';

-- DROP FUNCTION public.check_jwt();
-- Update public.check_jwt, Default anonymous to 404 on unauthorized access.
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
    IF _path ~ '^(\/|\/rpc\/(login|signup|recover|reset|telegram))$' THEN
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
            ELSIF _ptype ~ '^public_(stats|monitoring)$' AND _pid = 0 THEN
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

DROP FUNCTION IF EXISTS public.process_vessel_queue_fn;
DROP FUNCTION IF EXISTS public.cron_process_grafana_fn;
DROP FUNCTION IF EXISTS public.cron_windy_fn;
DROP FUNCTION IF EXISTS public.windy_pws_py_fn;
DROP FUNCTION IF EXISTS public.logbook_update_geojson_fn;
DROP FUNCTION IF EXISTS api.find_stay_from_moorage_fn;
DROP FUNCTION IF EXISTS api.export_vessel_geojson_fn;
DROP FUNCTION IF EXISTS api.status_fn;
DROP FUNCTION IF EXISTS api.counts_fn;
DROP FUNCTION IF EXISTS api.logs_by_day_fn;
DROP FUNCTION IF EXISTS api.logs_by_week_fn;
DROP FUNCTION IF EXISTS api.logs_by_month_fn;
DROP FUNCTION IF EXISTS api.logs_by_year_fn;
DROP VIEW IF EXISTS api.total_info_view;
DROP VIEW IF EXISTS api.versions_view;
DROP VIEW IF EXISTS api.explore_view;
DROP VIEW IF EXISTS api.stats_logs_view;
DROP VIEW IF EXISTS api.stats_moorages_view;
DROP VIEW IF EXISTS api.stats_moorages_away_view;

-- Refresh permissions user_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
-- Refresh permissions bot_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO bot_role;
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

-- +goose StatementEnd
