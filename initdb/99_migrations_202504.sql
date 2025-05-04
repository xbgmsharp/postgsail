---------------------------------------------------------------------------
-- Copyright 2021-2025 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration April 2025
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Install and update TimescaleDB Toolkit
CREATE EXTENSION timescaledb_toolkit;

-- Remove deprecated client_id
ALTER TABLE api.metadata DROP COLUMN IF EXISTS client_id;
-- 'attribute 3 of type _timescaledb_internal._hyper_1_1_chunk has wrong type'
-- ALTER TABLE api.metrics DROP COLUMN IF EXISTS client_id;

-- Remove index from logbook columns
DROP INDEX IF EXISTS api.image_embedding_idx;
DROP INDEX IF EXISTS api.embedding_idx;
DROP INDEX IF EXISTS api.spatial_embedding_idx;

-- Remove deprecated column from api.logbook
DROP VIEW IF EXISTS public.trip_in_progress; -- CASCADE
ALTER TABLE api.logbook DROP COLUMN IF EXISTS embedding;
ALTER TABLE api.logbook DROP COLUMN IF EXISTS spatial_embedding;
ALTER TABLE api.logbook DROP COLUMN IF EXISTS image_embedding;

-- Add new mobilityDB support
ALTER TABLE api.logbook ADD COLUMN trip_heading tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_tank_level tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_solar_voltage tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_solar_power tfloat NULL;

-- Comments
COMMENT ON COLUMN api.logbook.trip_heading IS 'heading True';
COMMENT ON COLUMN api.logbook.trip_tank_level IS 'Tank currentLevel';
COMMENT ON COLUMN api.logbook.trip_solar_voltage IS 'solar voltage';
COMMENT ON COLUMN api.logbook.trip_solar_power IS 'solar powerPanel';

-- Restore cascade drop column
CREATE VIEW public.trip_in_progress AS
    SELECT * 
        FROM api.logbook 
        WHERE active IS true;

-- Update api.export_logbook_geojson_linestring_trip_fn, add more metadata properties
CREATE OR REPLACE FUNCTION api.export_logbooks_geojson_linestring_trips_fn(
    start_log integer DEFAULT NULL::integer,
    end_log integer DEFAULT NULL::integer,
    start_date text DEFAULT NULL::text,
    end_date text DEFAULT NULL::text,
    OUT geojson jsonb
) RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    logs_geojson jsonb;
BEGIN
    -- Normalize start and end values
    IF start_log IS NOT NULL AND end_log IS NULL THEN end_log := start_log; END IF;
    IF start_date IS NOT NULL AND end_date IS NULL THEN end_date := start_date; END IF;

    WITH logbook_data AS (
        -- get the logbook geometry and metadata, an array for each log
        SELECT id, name,
            starttimestamp(trip),
            endtimestamp(trip),
            --speed(trip_sog),
            duration(trip),
            --length(trip) as length, -- Meters
            (length(trip) * 0.0005399568)::numeric as distance, -- NM
            maxValue(trip_sog) as max_sog, -- SOG
            maxValue(trip_tws) as max_tws, -- Wind
            maxValue(trip_twd) as max_twd, -- Wind
            maxValue(trip_depth) as max_depth, -- Depth
            maxValue(trip_temp_water) as max_temp_water, -- Temperature water
            maxValue(trip_temp_out) as max_temp_out, -- Temperature outside
            maxValue(trip_pres_out) as max_pres_out, -- Pressure outside
            maxValue(trip_hum_out) as max_hum_out, -- Humidity outside
            maxValue(trip_batt_charge) as max_stateofcharge, -- stateofcharge
            maxValue(trip_batt_voltage) as max_voltage, -- voltage
            twavg(trip_sog) as avg_sog, -- SOG
            twavg(trip_tws) as avg_tws, -- Wind
            twavg(trip_twd) as avg_twd, -- Wind
            twavg(trip_depth) as avg_depth, -- Depth
            twavg(trip_temp_water) as avg_temp_water, -- Temperature water
            twavg(trip_temp_out) as avg_temp_out, -- Temperature outside
            twavg(trip_pres_out) as avg_pres_out, -- Pressure outside
            twavg(trip_hum_out) as avg_hum_out, -- Humidity outside
            twavg(trip_batt_charge) as avg_stateofcharge, -- stateofcharge
            twavg(trip_batt_voltage) as avg_voltage, -- stateofcharge
            trajectory(l.trip)::geometry as track_geog -- extract trip to geography
        FROM api.logbook l
        WHERE (start_log IS NULL OR l.id >= start_log) AND
              (end_log IS NULL OR l.id <= end_log) AND
              (start_date IS NULL OR l._from_time >= start_date::TIMESTAMPTZ) AND
              (end_date IS NULL OR l._to_time <= end_date::TIMESTAMPTZ + interval '23 hours 59 minutes') AND
              l.trip IS NOT NULL
        ORDER BY l._from_time ASC
    ),
    collect as (
        SELECT ST_Collect(
                        ARRAY(
                            SELECT track_geog FROM logbook_data))
    )
    -- Create the GeoJSON response
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', json_agg(ST_AsGeoJSON(logs.*)::json)) INTO geojson FROM logbook_data logs;
END;
$function$;
-- Description
COMMENT ON FUNCTION api.export_logbooks_geojson_linestring_trips_fn IS 'Generate geojson geometry LineString from trip with the corresponding properties';

-- Updaste public.check_jwt, Make new mobilitydb export geojson function anonymous access
CREATE OR REPLACE FUNCTION public.check_jwt()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
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
  --RAISE WARNING 'jwt role %', current_setting('request.jwt.claims', true)::json->>'role';
  --RAISE WARNING 'cur_user %', current_user;
  --RAISE WARNING 'user.id [%], user.email [%]', current_setting('user.id', true), current_setting('user.email', true);
  --RAISE WARNING 'vessel.id [%], vessel.name [%]', current_setting('vessel.id', true), current_setting('vessel.name', true);

  --TODO SELECT current_setting('request.jwt.uid', true)::json->>'uid' INTO _user_id;
  --TODO RAISE WARNING 'jwt user_id %', current_setting('request.jwt.uid', true)::json->>'uid';
  --TODO SELECT current_setting('request.jwt.vid', true)::json->>'vid' INTO _vessel_id;
  --TODO RAISE WARNING 'jwt vessel_id %', current_setting('request.jwt.vid', true)::json->>'vid';
  IF _role = 'user_role' THEN
    -- Check the user exist in the accounts table
    SELECT * INTO account_rec
        FROM auth.accounts
        WHERE auth.accounts.email = _email;
    IF account_rec.email IS NULL THEN
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
    -- Check a vessel and user exist
    SELECT auth.vessels.* INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = auth.accounts.email
            AND auth.accounts.email = _email;
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
    -- Check the vessel and user exist
    SELECT auth.vessels.* INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = auth.accounts.email
            AND auth.accounts.email = _email
            AND auth.vessels.vessel_id = _vid;
    IF vessel_rec.owner_email IS NULL THEN
        RAISE EXCEPTION 'Invalid vessel'
            USING HINT = 'Unknown vessel owner_email';
    END IF;
    PERFORM set_config('vessel.id', vessel_rec.vessel_id, true);
    PERFORM set_config('vessel.name', vessel_rec.name, true);
    --RAISE WARNING 'public.check_jwt() user_role vessel.name %', current_setting('vessel.name', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.id %', current_setting('vessel.id', false);
  ELSIF _role = 'api_anonymous' THEN
    --RAISE WARNING 'public.check_jwt() api_anonymous path[%] vid:[%]', current_setting('request.path', true), current_setting('vessel.id', false); 
    -- Check if path is the a valid allow anonymous path
    SELECT current_setting('request.path', true) ~ '^/(logs_view|log_view|rpc/timelapse_fn|rpc/timelapse2_fn|monitoring_view|stats_logs_view|stats_moorages_view|rpc/stats_logs_fn|rpc/export_logbooks_geojson_point_trips_fn|rpc/export_logbooks_geojson_linestring_trips_fn)$' INTO _ppath;
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
            ELSE
                SELECT v.vessel_id, v.name into anonymous_rec
                        FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs
                        WHERE a.email = v.owner_email
                            AND a.preferences->>'public_vessel'::text ~* boat
                            AND prefs.key = _ptype::TEXT
                            AND prefs.value::BOOLEAN = true;
                RAISE WARNING '-> ispublic_fn output boat:[%], type:[%], result:[%]', _pvessel, _ptype, anonymous_rec;
                IF anonymous_rec.vessel_id IS NOT NULL THEN
                    PERFORM set_config('vessel.id', anonymous_rec.vessel_id, true);
                    PERFORM set_config('vessel.name', anonymous_rec.name, true);
                    RETURN;
                END IF;
            END IF;
            --RAISE sqlstate 'PT404' using message = 'unknown resource';
        END IF; -- end anonymous path
    END IF;
  ELSIF _role <> 'api_anonymous' THEN
    RAISE EXCEPTION 'Invalid role'
      USING HINT = 'Stop being so evil and maybe you can log in';
  END IF;
END
$function$
;
-- Description
COMMENT ON FUNCTION
    public.check_jwt() IS 'PostgREST API db-pre-request check, set_config according to role (api_anonymous,vessel_role,user_role)';

-- Create api.monitoring_upsert_fn, the function that update api.metadata monitoring configuration
CREATE OR REPLACE FUNCTION api.monitoring_upsert_fn(
  patch jsonb
)
RETURNS void AS $$
BEGIN
    WITH vessels AS (
        SELECT vessel_id, owner_email
        FROM auth.vessels
        WHERE vessel_id = current_setting('vessel.id', true)
    )
    UPDATE api.metadata
        SET configuration = patch
        FROM vessels
        WHERE api.metadata.vessel_id = vessels.vessel_id;
END;
$$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.monitoring_upsert_fn IS 'Update api.metadata monitoring configuration by user_role';

-- DROP FUNCTION public.cron_process_skplugin_upgrade_fn();
-- Update cron_process_skplugin_upgrade_fn, update check for signalk plugin version
CREATE OR REPLACE FUNCTION public.cron_process_skplugin_upgrade_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    skplugin_upgrade_rec record;
    user_settings jsonb;
BEGIN
    -- Check for signalk plugin version
    RAISE NOTICE 'cron_process_plugin_upgrade_fn';
    FOR skplugin_upgrade_rec in
        SELECT
            v.owner_email,m.name,m.vessel_id,m.plugin_version,a.first
            FROM api.metadata m
            LEFT JOIN auth.vessels v ON v.vessel_id = m.vessel_id
            LEFT JOIN auth.accounts a ON v.owner_email = a.email
            WHERE m.plugin_version <> '0.4.0'
    LOOP
        RAISE NOTICE '-> cron_process_skplugin_upgrade_rec_fn for [%]', skplugin_upgrade_rec;
        SELECT json_build_object('email', skplugin_upgrade_rec.owner_email, 'recipient', skplugin_upgrade_rec.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_skplugin_upgrade_rec_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('skplugin_upgrade'::TEXT, user_settings::JSONB);
    END LOOP;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.cron_process_skplugin_upgrade_fn() IS 'init by pg_cron, check for signalk plugin version and notify for upgrade';

-- DROP FUNCTION api.find_log_from_moorage_fn(in int4, out jsonb);
-- Update api.find_log_from_moorage_fn using the mobilitydb trajectory
CREATE OR REPLACE FUNCTION api.find_log_from_moorage_fn(_id integer, OUT geojson jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
        moorage_rec record;
        _geojson jsonb;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> find_log_from_moorage_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Gather moorage details
        SELECT * INTO moorage_rec
            FROM api.moorages m
            WHERE m.id = _id;
        -- Find all log from and to moorage geopoint within 100m
        SELECT api.export_logbook_geojson_linestring_trip_fn(id)::JSON->'features' INTO _geojson
            FROM api.logbook l
            WHERE ST_DWithin(
                    Geography(ST_MakePoint(l._from_lng, l._from_lat)),
                    moorage_rec.geog,
                    1000 -- in meters ?
                );
        -- Return a GeoJSON filter on LineString
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', _geojson ) INTO geojson;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION api.find_log_from_moorage_fn(in int4, out jsonb) IS 'Find all log from moorage geopoint within 100m';

-- DROP FUNCTION api.find_log_to_moorage_fn(in int4, out jsonb);
-- Update api.find_log_to_moorage_fn using the mobilitydb trajectory
CREATE OR REPLACE FUNCTION api.find_log_to_moorage_fn(_id integer, OUT geojson jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
        moorage_rec record;
        _geojson jsonb;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> find_log_from_moorage_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Gather moorage details
        SELECT * INTO moorage_rec
            FROM api.moorages m
            WHERE m.id = _id;
        -- Find all log from and to moorage geopoint within 100m
        SELECT api.export_logbook_geojson_linestring_trip_fn(id)::JSON->'features' INTO _geojson
            FROM api.logbook l
            WHERE ST_DWithin(
                    Geography(ST_MakePoint(l._to_lng, l._to_lat)),
                    moorage_rec.geog,
                    1000 -- in meters ?
                );
        -- Return a GeoJSON filter on LineString
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', _geojson ) INTO geojson;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION api.find_log_to_moorage_fn(in int4, out jsonb) IS 'Find all log to moorage geopoint within 100m';

-- Update api.eventlogs_view to fetch the events logs backwards and skip the new_stay
CREATE OR REPLACE VIEW api.eventlogs_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT id,
    channel,
    payload,
    ref_id,
    stored,
    processed
   FROM process_queue pq
  WHERE processed IS NOT NULL
        AND channel <> 'new_stay'::text
        AND channel <> 'pre_logbook'::text
        AND channel <> 'post_logbook'::text
        AND (ref_id = current_setting('user.id', false) OR ref_id = current_setting('vessel.id', true))
  ORDER BY id DESC;
-- Description
COMMENT ON VIEW api.eventlogs_view IS 'Event logs view';

-- DROP FUNCTION api.stats_logs_fn(in text, in text, out jsonb);
-- Update api.stats_logs_fn, ensure the trip is completed
CREATE OR REPLACE FUNCTION api.stats_logs_fn(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT stats jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
        _start_date TIMESTAMPTZ DEFAULT '1970-01-01';
        _end_date TIMESTAMPTZ DEFAULT NOW();
    BEGIN
        IF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            RAISE WARNING '--> stats_logs_fn, filter result stats by date [%]', start_date;
            _start_date := start_date::TIMESTAMPTZ;
            _end_date := end_date::TIMESTAMPTZ;
        END IF;
        RAISE NOTICE '--> stats_logs_fn, _start_date [%], _end_date [%]', _start_date, _end_date;
        WITH
            meta AS (
                SELECT m.name FROM api.metadata m ),
            logs_view AS (
                SELECT *
                    FROM api.logbook l
                    WHERE _from_time >= _start_date::TIMESTAMPTZ
                        AND _to_time <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
						AND trip IS NOT NULL
                ),
            first_date AS (
                SELECT _from_time as first_date from logs_view ORDER BY first_date ASC LIMIT 1
            ),
            last_date AS (
                SELECT _to_time as last_date from logs_view ORDER BY _to_time DESC LIMIT 1
            ),
            max_speed_id AS (
                SELECT id FROM logs_view WHERE max_speed = (SELECT max(max_speed) FROM logs_view) ),
            max_wind_speed_id AS (
                SELECT id FROM logs_view WHERE max_wind_speed = (SELECT max(max_wind_speed) FROM logs_view)),
            max_distance_id AS (
                SELECT id FROM logs_view WHERE distance = (SELECT max(distance) FROM logs_view)),
            max_duration_id AS (
                SELECT id FROM logs_view WHERE duration = (SELECT max(duration) FROM logs_view)),
            logs_stats AS (
                SELECT
                    count(*) AS count,
                    max(max_speed) AS max_speed,
                    max(max_wind_speed) AS max_wind_speed,
                    max(distance) AS max_distance,
                    sum(distance) AS sum_distance,
                    max(duration) AS max_duration,
                    sum(duration) AS sum_duration
                FROM logs_view l )
              --select * from logbook;
        -- Return a JSON
        SELECT jsonb_build_object(
            'name', meta.name,
            'first_date', first_date.first_date,
            'last_date', last_date.last_date,
            'max_speed_id', max_speed_id.id,
            'max_wind_speed_id', max_wind_speed_id.id,
            'max_duration_id', max_duration_id.id,
            'max_distance_id', max_distance_id.id)::jsonb || to_jsonb(logs_stats.*)::jsonb INTO stats
            FROM max_speed_id, max_wind_speed_id, max_distance_id, max_duration_id,
                logs_stats, meta, logs_view, first_date, last_date;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION api.stats_logs_fn(in text, in text, out jsonb) IS 'Logs stats by date';

-- DROP FUNCTION api.stats_fn(in text, in text, out jsonb);
-- Update api.stats_fn, ensure the trip is completed
CREATE OR REPLACE FUNCTION api.stats_fn(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT stats jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
        _start_date TIMESTAMPTZ DEFAULT '1970-01-01';
        _end_date TIMESTAMPTZ DEFAULT NOW();
        stats_logs JSONB;
        stats_moorages JSONB;
        stats_logs_topby JSONB;
        stats_moorages_topby JSONB;
    BEGIN
        IF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            RAISE WARNING '--> stats_fn, filter result stats by date [%]', start_date;
            _start_date := start_date::TIMESTAMPTZ;
            _end_date := end_date::TIMESTAMPTZ;
        END IF;
        RAISE NOTICE '--> stats_fn, _start_date [%], _end_date [%]', _start_date, _end_date;
        -- Get global logs statistics
        SELECT api.stats_logs_fn(_start_date::TEXT, _end_date::TEXT) INTO stats_logs;
        -- Get global stays/moorages statistics
        SELECT api.stats_stays_fn(_start_date::TEXT, _end_date::TEXT) INTO stats_moorages;
        -- Get Top 5 trips statistics
        WITH
            logs_view AS (
                SELECT id,avg_speed,max_speed,max_wind_speed,distance,duration
                    FROM api.logbook l
                    WHERE _from_time >= _start_date::TIMESTAMPTZ
                        AND _to_time <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
						AND trip IS NOT NULL
            ),
            logs_top_avg_speed AS (
                SELECT id,avg_speed FROM logs_view
                GROUP BY id,avg_speed
                ORDER BY avg_speed DESC
                LIMIT 5),
            logs_top_speed AS (
                SELECT id,max_speed FROM logs_view
                WHERE max_speed IS NOT NULL
                GROUP BY id,max_speed
                ORDER BY max_speed DESC
                LIMIT 5),
            logs_top_wind_speed AS (
                SELECT id,max_wind_speed FROM logs_view
				WHERE max_wind_speed IS NOT NULL
                GROUP BY id,max_wind_speed
                ORDER BY max_wind_speed DESC
                LIMIT 5),
            logs_top_distance AS (
                SELECT id FROM logs_view
                GROUP BY id,distance
                ORDER BY distance DESC
                LIMIT 5),
            logs_top_duration AS (
                SELECT id FROM logs_view
                GROUP BY id,duration
                ORDER BY duration DESC
                LIMIT 5)
		-- Stats Top Logs
        SELECT jsonb_build_object(
            'stats_logs', stats_logs,
            'stats_moorages', stats_moorages,
            'logs_top_speed', (SELECT jsonb_agg(logs_top_speed.*) FROM logs_top_speed),
            'logs_top_avg_speed', (SELECT jsonb_agg(logs_top_avg_speed.*) FROM logs_top_avg_speed),
            'logs_top_wind_speed', (SELECT jsonb_agg(logs_top_wind_speed.*) FROM logs_top_wind_speed),
            'logs_top_distance', (SELECT jsonb_agg(logs_top_distance.id) FROM logs_top_distance),
            'logs_top_duration', (SELECT jsonb_agg(logs_top_duration.id) FROM logs_top_duration)
         ) INTO stats;
		-- Stats top 5 moorages statistics
        WITH
            stays AS (
                SELECT distinct(moorage_id) as moorage_id, sum(duration) as duration, count(id) as reference_count
                    FROM api.stays s
                    WHERE s.arrived >= _start_date::TIMESTAMPTZ
                        AND s.departed <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
                    group by s.moorage_id
                    order by s.moorage_id
            ),
            moorages AS (
                SELECT m.id, m.home_flag, mv.stays_count, mv.stays_sum_duration, m.stay_code, m.country, s.duration as dur, s.reference_count as ref_count
                    FROM api.moorages m, stays s, api.moorage_view mv
                    WHERE s.moorage_id = m.id
                        AND mv.id = m.id
                    order by s.moorage_id
            ),
            moorages_top_arrivals AS (
                SELECT id,ref_count FROM moorages
                GROUP BY id,ref_count
                ORDER BY ref_count DESC
                LIMIT 5),
            moorages_top_duration AS (
                SELECT id,dur FROM moorages
                GROUP BY id,dur
                ORDER BY dur DESC
                LIMIT 5),
            moorages_countries AS (
                SELECT DISTINCT(country) FROM moorages
                WHERE country IS NOT NULL AND country <> 'unknown'
                GROUP BY country
                ORDER BY country DESC
                LIMIT 5)
		SELECT stats || jsonb_build_object(
		    'moorages_top_arrivals', (SELECT jsonb_agg(moorages_top_arrivals) FROM moorages_top_arrivals),
		    'moorages_top_duration', (SELECT jsonb_agg(moorages_top_duration) FROM moorages_top_duration),
		    'moorages_top_countries', (SELECT jsonb_agg(moorages_countries.country) FROM moorages_countries)
		 ) INTO stats;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION api.stats_fn(in text, in text, out jsonb) IS 'Statistic by date for Logs and Moorages and Stays';

-- DROP FUNCTION public.moorage_delete_trigger_fn();
-- Update moorage_delete_trigger_fn, When morrage is deleted, delete process_queue references as well.
CREATE OR REPLACE FUNCTION public.moorage_delete_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
    DECLARE
    BEGIN
        RAISE NOTICE 'moorages_delete_trigger_fn [%]', OLD;
        DELETE FROM api.stays WHERE moorage_id = OLD.id;
        DELETE FROM api.logbook WHERE _from_moorage_id = OLD.id;
        DELETE FROM api.logbook WHERE _to_moorage_id = OLD.id;
        -- Delete process_queue references
        DELETE FROM public.process_queue p
            WHERE p.payload = OLD.id::TEXT
                AND p.ref_id = OLD.vessel_id
                AND p.channel = 'new_moorage';
        RETURN OLD; -- result is ignored since this is an AFTER trigger
    END;
$function$
;
-- Description
COMMENT ON FUNCTION public.moorage_delete_trigger_fn() IS 'Automatic delete logbook and stays reference when delete a moorage';

-- DROP FUNCTION public.logbook_delete_trigger_fn();
-- Create public.logbook_delete_trigger_fn, When logbook is deleted, logbook_ext need to deleted as well.
CREATE OR REPLACE FUNCTION public.logbook_delete_trigger_fn()
RETURNS TRIGGER AS $$
BEGIN
    RAISE NOTICE 'logbook_delete_trigger_fn [%]', OLD;
    -- If api.logbook is deleted, deleted entry in api.logbook_ext table as well.
    IF EXISTS (SELECT FROM information_schema.tables 
                WHERE table_schema = 'public' 
                AND table_name = 'logbook_ext') THEN
        -- Delete logbook_ext
        DELETE FROM public.logbook_ext l
            WHERE logbook_id = OLD.id;
    END IF;
    -- Delete process_queue references
    DELETE FROM public.process_queue p
        WHERE p.payload = OLD.id::TEXT
            AND p.ref_id = OLD.vessel_id
            AND p.channel LIKE '%_logbook';
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION public.logbook_delete_trigger_fn() IS 'When logbook is delete, logbook_ext need to deleted as well.';

DROP TRIGGER IF EXISTS logbook_delete_trigger ON api.logbook;
-- Create the trigger
CREATE TRIGGER logbook_delete_trigger
    BEFORE DELETE ON api.logbook
        FOR EACH ROW
        EXECUTE FUNCTION public.logbook_delete_trigger_fn();
-- Description
COMMENT ON TRIGGER logbook_delete_trigger ON api.logbook IS 'BEFORE DELETE ON api.logbook run function public.logbook_delete_trigger_fn to delete reference and logbook_ext need to deleted.';

-- Update metadata table, mark client_id as deprecated
CREATE OR REPLACE FUNCTION api.update_metadata_configuration()
RETURNS TRIGGER AS $$
BEGIN
    -- Only update configuration if it's a JSONB object and has changed
    IF NEW.configuration IS NOT NULL 
       AND NEW.configuration IS DISTINCT FROM OLD.configuration
       AND jsonb_typeof(NEW.configuration) = 'object' THEN

        NEW.configuration := jsonb_set(
            NEW.configuration,
            '{update_at}',
            to_jsonb(to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION api.update_metadata_configuration() IS 'Update the configuration field with current date in ISO format';

-- DROP FUNCTION public.process_lat_lon_fn(in numeric, in numeric, out int4, out int4, out text, out text);
-- Update public.process_lat_lon_fn, Add new moorage refrence in public.process_queue for event logs review
CREATE OR REPLACE FUNCTION public.process_lat_lon_fn(lon numeric, lat numeric, OUT moorage_id integer, OUT moorage_type integer, OUT moorage_name text, OUT moorage_country text)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
    DECLARE
        stay_rec record;
        --moorage_id INTEGER := NULL;
        --moorage_type INTEGER := 1; -- Unknown
        --moorage_name TEXT := NULL;
        --moorage_country TEXT := NULL;
        existing_rec record;
        geo jsonb;
        overpass jsonb;
    BEGIN
        RAISE NOTICE '-> process_lat_lon_fn';
        IF lon IS NULL OR lat IS NULL THEN
            RAISE WARNING '-> process_lat_lon_fn invalid input lon %, lat %', lon, lat;
            --return NULL;
        END IF;

        -- Do we have an existing moorages within 300m of the new stay
        FOR existing_rec in
            SELECT
                *
            FROM api.moorages m
            WHERE
                m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.geog IS NOT NULL
                AND ST_DWithin(
                    Geography(ST_MakePoint(m.longitude, m.latitude)),
                    Geography(ST_MakePoint(lon, lat)),
                    300 -- in meters
                    )
                AND m.vessel_id = current_setting('vessel.id', false)
            ORDER BY id ASC
        LOOP
            -- found previous stay within 300m of the new moorage
            IF existing_rec.id IS NOT NULL AND existing_rec.id > 0 THEN
                RAISE NOTICE '-> process_lat_lon_fn found previous moorages within 300m %', existing_rec;
                EXIT; -- exit loop
            END IF;
        END LOOP;

        -- if with in 300m use existing name and stay_code
        -- else insert new entry
        IF existing_rec.id IS NOT NULL AND existing_rec.id > 0 THEN
            RAISE NOTICE '-> process_lat_lon_fn found close by moorage using existing name and stay_code %', existing_rec;
            moorage_id := existing_rec.id;
            moorage_name := existing_rec.name;
            moorage_type := existing_rec.stay_code;
        ELSE
            RAISE NOTICE '-> process_lat_lon_fn create new moorage';
            -- query overpass api to guess moorage type
            overpass := overpass_py_fn(lon::NUMERIC, lat::NUMERIC);
            RAISE NOTICE '-> process_lat_lon_fn overpass name:[%] seamark:type:[%]', overpass->'name', overpass->'seamark:type';
            moorage_type = 1; -- Unknown
            IF overpass->>'seamark:type' = 'harbour' AND overpass->>'seamark:harbour:category' = 'marina' then
                moorage_type = 4; -- Dock
            ELSIF overpass->>'seamark:type' = 'mooring' AND overpass->>'seamark:mooring:category' = 'buoy' then
                moorage_type = 3; -- Mooring Buoy
            ELSIF overpass->>'seamark:type' ~ '(anchorage|anchor_berth|berth)' OR overpass->>'natural' ~ '(bay|beach)' then
                moorage_type = 2; -- Anchor
            ELSIF overpass->>'seamark:type' = 'mooring' then
                moorage_type = 3; -- Mooring Buoy
            ELSIF overpass->>'leisure' = 'marina' then
                moorage_type = 4; -- Dock
            END IF;
            -- geo reverse _lng _lat
            geo := reverse_geocode_py_fn('nominatim', lon::NUMERIC, lat::NUMERIC);
            moorage_country := geo->>'country_code';
            IF overpass->>'name:en' IS NOT NULL then
                moorage_name = overpass->>'name:en';
            ELSIF overpass->>'name' IS NOT NULL then
                moorage_name = overpass->>'name';
            ELSE
                moorage_name := geo->>'name';
            END IF;
            RAISE NOTICE '-> process_lat_lon_fn output name:[%] type:[%]', moorage_name, moorage_type;
            RAISE NOTICE '-> process_lat_lon_fn insert new moorage for [%] name:[%] type:[%]', current_setting('vessel.id', false), moorage_name, moorage_type;
            -- Insert new moorage from stay
            INSERT INTO api.moorages
                (vessel_id, name, country, stay_code, latitude, longitude, geog, overpass, nominatim)
                VALUES (
                    current_setting('vessel.id', false),
                    coalesce(replace(moorage_name,'"', ''), null),
                    coalesce(moorage_country, null),
                    moorage_type,
                    lat,
                    lon,
                    Geography(ST_MakePoint(lon, lat)),
                    coalesce(overpass, null),
                    coalesce(geo, null)
                ) returning id into moorage_id;
            -- Add moorage entry to process queue for reference
            INSERT INTO process_queue (channel, payload, stored, ref_id, processed)
                VALUES ('new_moorage', moorage_id, now(), current_setting('vessel.id', true), now());
        END IF;
        --return json_build_object(
        --        'id', moorage_id,
        --        'name', moorage_name,
        --        'type', moorage_type
        --        )::jsonb;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION public.process_lat_lon_fn(in numeric, in numeric, out int4, out int4, out text, out text) IS 'Add or Update moorage base on lat/lon';

-- Description on missing trigger
COMMENT ON TRIGGER metadata_update_configuration_trigger ON api.metadata IS 'BEFORE UPDATE ON api.metadata run function api.update_metadata_configuration tp update the configuration field with current date in ISO format';

-- Remove unused and duplicate function
DROP FUNCTION IF EXISTS public.delete_account_fn(text, text);
DROP FUNCTION IF EXISTS public.cron_deactivated_fn();
DROP FUNCTION IF EXISTS public.cron_inactivity_fn();

--DROP FUNCTION IF EXISTS public.logbook_active_geojson_fn;
-- Update public.logbook_active_geojson_fn, fix log_gis_line as there is no end time yet
CREATE OR REPLACE FUNCTION public.logbook_active_geojson_fn(
    OUT _track_geojson jsonb
 ) AS $logbook_active_geojson$
BEGIN
    WITH log_active AS (
        SELECT * FROM api.logbook WHERE active IS True
    ),
    log_gis_line AS (
        SELECT ST_MakeLine(
            ARRAY(
                SELECT st_makepoint(longitude,latitude) AS geo_point
                    FROM api.metrics m, log_active l
                    WHERE m.latitude IS NOT NULL
                        AND m.longitude IS NOT NULL
                        AND m.time >= l._from_time::TIMESTAMPTZ
                    ORDER BY m.time ASC
            )
        )
    ),
    log_gis_point AS (
        SELECT
            ST_AsGeoJSON(t.*)::json AS GeoJSONPoint
        FROM (
            ( SELECT
                time,
                courseovergroundtrue,
                speedoverground,
                windspeedapparent,
                longitude,latitude,
                '' AS notes,
                coalesce(metrics->>'environment.wind.speedTrue', null) as truewindspeed,
                coalesce(metrics->>'environment.wind.directionTrue', null) as truewinddirection,
                coalesce(status, null) AS status,
                ST_MakePoint(longitude,latitude) AS geo_point
                FROM api.metrics m
                WHERE m.latitude IS NOT NULL
                    AND m.longitude IS NOT NULL
                ORDER BY m.time DESC LIMIT 1
            )
        ) as t
    ),
    log_agg as (
        SELECT
            CASE WHEN log_gis_line.st_makeline IS NOT NULL THEN
                ( SELECT jsonb_agg(ST_AsGeoJSON(log_gis_line.*)::json)::jsonb AS GeoJSONLine FROM log_gis_line )
            ELSE
                ( SELECT '[]'::json AS GeoJSONLine )::jsonb
            END
        FROM log_gis_line
    )
    SELECT
            jsonb_build_object(
                'type', 'FeatureCollection',
                'features', log_agg.GeoJSONLine::jsonb || log_gis_point.GeoJSONPoint::jsonb
                ) INTO _track_geojson FROM log_agg, log_gis_point;
END;
$logbook_active_geojson$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_active_geojson_fn
    IS 'Create a GeoJSON with 2 features, LineString with a current active log and Point with the last position';

DROP FUNCTION IF EXISTS public.stay_active_geojson_fn;
-- Create public.stay_active_geojson_fn function to produce a GeoJSON with the last position and stay details
CREATE or replace FUNCTION public.stay_active_geojson_fn(
    OUT _track_geojson jsonb
 ) AS $stay_active_geojson_fn$
BEGIN
    WITH stay_active AS (
        SELECT * FROM api.stays WHERE active IS true
    ),
    stay_gis_point AS (
        SELECT
            ST_AsGeoJSON(t.*)::jsonb AS GeoJSONPoint
        FROM (
            SELECT
                m.name,
                NOW() as time,
                s.stay_code,
                ST_MakePoint(s.longitude, s.latitude) AS geo_point,
                s.arrived,
                s.latitude,
                s.longitude
            FROM stay_active s
            LEFT JOIN api.moorages m ON m.id = s.moorage_id
        ) as t
    )
    SELECT stay_gis_point.GeoJSONPoint::jsonb INTO _track_geojson FROM stay_gis_point;
END;
$stay_active_geojson_fn$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.stay_active_geojson_fn
    IS 'Create a GeoJSON with a feature Point with the last position and stay details';

-- Update monitoring view to support live moorage in GeoJSON
DROP VIEW IF EXISTS api.monitoring_view;
CREATE VIEW api.monitoring_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT
        time AS "time",
        (NOW() AT TIME ZONE 'UTC' - time) > INTERVAL '70 MINUTES' as offline,
        metrics-> 'environment.water.temperature' AS waterTemperature,
        metrics-> 'environment.inside.temperature' AS insideTemperature,
        metrics-> 'environment.outside.temperature' AS outsideTemperature,
        metrics-> 'environment.wind.speedOverGround' AS windSpeedOverGround,
        metrics-> 'environment.wind.directionTrue' AS windDirectionTrue,
        metrics-> 'environment.inside.relativeHumidity' AS insideHumidity,
        metrics-> 'environment.outside.relativeHumidity' AS outsideHumidity,
        metrics-> 'environment.outside.pressure' AS outsidePressure,
        metrics-> 'environment.inside.pressure' AS insidePressure,
        metrics-> 'electrical.batteries.House.capacity.stateOfCharge' AS batteryCharge,
        metrics-> 'electrical.batteries.House.voltage' AS batteryVoltage,
        metrics-> 'environment.depth.belowTransducer' AS depth,
        jsonb_build_object(
            'type', 'Feature',
            'geometry', ST_AsGeoJSON(st_makepoint(longitude,latitude))::jsonb,
            'properties', jsonb_build_object(
                'name', current_setting('vessel.name', false),
                'latitude', m.latitude,
                'longitude', m.longitude,
                'time', m.time,
                'speedoverground', m.speedoverground,
                'windspeedapparent', m.windspeedapparent,
                'truewindspeed', COALESCE(metrics->'environment.wind.speedTrue', null),
                'truewinddirection', COALESCE(metrics->'environment.wind.directionTrue', null),
                'status', coalesce(m.status, null)
                )::jsonb ) AS geojson,
        current_setting('vessel.name', false) AS name,
        m.status,
        CASE
            WHEN m.status <> 'moored' THEN (
                SELECT public.logbook_active_geojson_fn() )
            WHEN m.status = 'moored' THEN (
                SELECT public.stay_active_geojson_fn() )
        END AS live
    FROM api.metrics m
    ORDER BY time DESC LIMIT 1;
-- Description
COMMENT ON VIEW
    api.monitoring_view
    IS 'Monitoring static web view';

-- api.monitoring_live view, the live tracking view
DROP VIEW IF EXISTS api.monitoring_live;
CREATE or replace VIEW api.monitoring_live WITH (security_invoker=true,security_barrier=true) AS
    SELECT
        mt.time AS "time",
        (NOW() AT TIME ZONE 'UTC' - mt.time) > INTERVAL '70 MINUTES' as offline,
        mt.metrics AS data,
        current_setting('vessel.name', false) AS name,
        mt.status,
        -- Water Temperature
        COALESCE(
            mt.metrics->'water'->>'temperature',
            mt.metrics->>(md.configuration->>'waterTemperatureKey'),
            mt.metrics->>'environment.water.temperature'
        )::FLOAT AS waterTemperature,

        -- Inside Temperature
        COALESCE(
            mt.metrics->'temperature'->>'inside',
            mt.metrics->>(md.configuration->>'insideTemperatureKey'),
            mt.metrics->>'environment.inside.temperature'
        )::FLOAT AS insideTemperature,

        -- Outside Temperature
        COALESCE(
            mt.metrics->'temperature'->>'outside',
            mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
            mt.metrics->>'environment.outside.temperature'
        )::FLOAT AS outsideTemperature,

        -- Wind Speed Over Ground
        COALESCE(
            mt.metrics->'wind'->>'speed',
            mt.metrics->>(md.configuration->>'windSpeedKey'),
            mt.metrics->>'environment.wind.speedTrue'
        )::FLOAT AS windSpeedOverGround,

        -- Wind Direction True
        COALESCE(
            mt.metrics->'wind'->>'direction',
            mt.metrics->>(md.configuration->>'windDirectionKey'),
            mt.metrics->>'environment.wind.directionTrue'
        )::FLOAT AS windDirectionTrue,

        -- Inside Humidity
        COALESCE(
            mt.metrics->'humidity'->>'inside',
            mt.metrics->>(md.configuration->>'insideHumidityKey'),
            mt.metrics->>'environment.inside.relativeHumidity',
            mt.metrics->>'environment.inside.humidity'
        )::FLOAT AS insideHumidity,

        -- Outside Humidity
        COALESCE(
            mt.metrics->'humidity'->>'outside',
            mt.metrics->>(md.configuration->>'outsideHumidityKey'),
            mt.metrics->>'environment.outside.relativeHumidity',
            mt.metrics->>'environment.inside.humidity'
        )::FLOAT AS outsideHumidity,

        -- Outside Pressure
        COALESCE(
            mt.metrics->'pressure'->>'outside',
            mt.metrics->>(md.configuration->>'outsidePressureKey'),
            mt.metrics->>'environment.outside.pressure'
        )::FLOAT AS outsidePressure,

        -- Inside Pressure
        COALESCE(
            mt.metrics->'pressure'->>'inside',
            mt.metrics->>(md.configuration->>'insidePressureKey'),
            mt.metrics->>'environment.inside.pressure'
        )::FLOAT AS insidePressure,

        -- Battery Charge (State of Charge)
        COALESCE(
            mt.metrics->'battery'->>'charge',
            mt.metrics->>(md.configuration->>'stateOfChargeKey'),
            mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
        )::FLOAT AS batteryCharge,

        -- Battery Voltage
        COALESCE(
            nullif(mt.metrics->'battery'->>'voltage', NULL),
            mt.metrics->>(md.configuration->>'voltageKey'),
            mt.metrics->>'electrical.batteries.House.voltage'
        )::FLOAT AS batteryVoltage,

        -- Water Depth
        COALESCE(
            mt.metrics->'water'->>'depth',
            mt.metrics->>(md.configuration->>'depthKey'),
            mt.metrics->>'environment.depth.belowTransducer'
        )::FLOAT AS depth,

        -- Solar Power
        COALESCE(
            mt.metrics->'solar'->>'power',
            mt.metrics->>(md.configuration->>'solarPowerKey'),
            mt.metrics->>'electrical.solar.Main.panelPower'
        )::FLOAT AS solarPower,

        -- Solar Voltage
        COALESCE(
            mt.metrics->'solar'->>'voltage',
            mt.metrics->>(md.configuration->>'solarVoltageKey'),
            mt.metrics->>'electrical.solar.Main.panelVoltage'
        )::FLOAT AS solarVoltage,

        -- Tank Level
        COALESCE(
            mt.metrics->'tank'->>'level',
            mt.metrics->>(md.configuration->>'tankLevelKey'),
            mt.metrics->>'tanks.fuel.0.currentLevel'
        )::FLOAT AS tankLevel,

        CASE
            WHEN mt.status <> 'moored' THEN (
                SELECT public.logbook_active_geojson_fn() )
            WHEN mt.status = 'moored' THEN (
                SELECT public.stay_active_geojson_fn() )
        END AS live
    FROM api.metrics mt
    JOIN api.metadata md ON md.vessel_id = mt.vessel_id
    ORDER BY time DESC LIMIT 1;
-- Description
COMMENT ON VIEW
    api.monitoring_view
    IS 'Dynamic Monitoring web view';

-- Refresh permissions
GRANT DELETE ON TABLE public.process_queue TO user_role;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
GRANT SELECT ON TABLE api.monitoring_view TO user_role;
GRANT SELECT ON TABLE api.monitoring_view TO api_anonymous;
GRANT SELECT ON TABLE api.monitoring_view TO grafana;
GRANT EXECUTE ON FUNCTION public.stay_active_geojson_fn to api_anonymous;
GRANT EXECUTE ON FUNCTION public.logbook_active_geojson_fn to api_anonymous;
GRANT EXECUTE ON FUNCTION public.stay_active_geojson_fn to grafana;
GRANT EXECUTE ON FUNCTION public.logbook_active_geojson_fn to grafana;

-- TODO 
-- DELETE all unused public.logbook_backup column to keep id, vessel_id, trip and embeding_*
-- UPDATE Delete/desactivated function accordingly
-- Run 99_migrations_202504.sql full to update version get new trigger
-- Run this migration 99_migrations_202505.sql full to update version.
-- Solve issue with update trip trigger

-- Update version
UPDATE public.app_settings
	SET value='0.9.1'
	WHERE "name"='app.version';

\c postgres
