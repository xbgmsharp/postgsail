---------------------------------------------------------------------------
-- Copyright 2021-2024 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration April 2024
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

UPDATE public.email_templates
	SET email_content='Hello __RECIPIENT__,
Sorry!We could not convert your boat into a Windy Personal Weather Station due to missing data (temperature, wind or pressure).
Windy Personal Weather Station is now disable.'
	WHERE "name"='windy_error';

CREATE OR REPLACE FUNCTION public.cron_windy_fn() RETURNS void AS $$
DECLARE
    windy_rec record;
    default_last_metric TIMESTAMPTZ := NOW() - interval '1 day';
    last_metric TIMESTAMPTZ := NOW();
    metric_rec record;
    windy_metric jsonb;
    app_settings jsonb;
    user_settings jsonb;
    windy_pws jsonb;
BEGIN
    -- Check for new observations pending update
    RAISE NOTICE 'cron_process_windy_fn';
    -- Gather url from app settings
    app_settings := get_app_settings_fn();
    -- Find users with Windy active and with an active vessel
    -- Map account id to Windy Station ID
    FOR windy_rec in
        SELECT
            a.id,a.email,v.vessel_id,v.name,
            COALESCE((a.preferences->'windy_last_metric')::TEXT, default_last_metric::TEXT) as last_metric
            FROM auth.accounts a
            LEFT JOIN auth.vessels AS v ON v.owner_email = a.email
            LEFT JOIN api.metadata AS m ON m.vessel_id = v.vessel_id
            WHERE (a.preferences->'public_windy')::boolean = True
                AND m.active = True
    LOOP
        RAISE NOTICE '-> cron_process_windy_fn for [%]', windy_rec;
        PERFORM set_config('vessel.id', windy_rec.vessel_id, false);
        --RAISE WARNING 'public.cron_process_windy_rec_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(windy_rec.vessel_id::TEXT);
        RAISE NOTICE '-> cron_process_windy_fn checking user_settings [%]', user_settings;
        -- Get all metrics from the last windy_last_metric avg by 5 minutes
        -- TODO json_agg to send all data in once, but issue with py jsonb transformation decimal. 
        FOR metric_rec in
            SELECT time_bucket('5 minutes', m.time) AS time_bucket,
                    avg((m.metrics->'environment.outside.temperature')::numeric) AS temperature,
                    avg((m.metrics->'environment.outside.pressure')::numeric) AS pressure,
                    avg((m.metrics->'environment.outside.relativeHumidity')::numeric) AS rh,
                    avg((m.metrics->'environment.wind.directionTrue')::numeric) AS winddir,
                    avg((m.metrics->'environment.wind.speedTrue')::numeric) AS wind,
                    max((m.metrics->'environment.wind.speedTrue')::numeric) AS gust,
                    last(latitude, time) AS lat,
                    last(longitude, time) AS lng
                FROM api.metrics m
                WHERE vessel_id = windy_rec.vessel_id
                    AND m.time >= windy_rec.last_metric::TIMESTAMPTZ
                GROUP BY time_bucket
                ORDER BY time_bucket ASC LIMIT 100
        LOOP
            RAISE NOTICE '-> cron_process_windy_fn checking metrics [%]', metric_rec;
	        if metric_rec.wind is null or metric_rec.temperature is null 
	        	or metric_rec.pressure is null or metric_rec.rh is null then
	           -- Ignore when there is no metrics.
               -- Send notification
               PERFORM send_notification_fn('windy_error'::TEXT, user_settings::JSONB);
			   -- Disable windy
	           PERFORM api.update_user_preferences_fn('{public_windy}'::TEXT, 'false'::TEXT);
	           RETURN;
	        end if;
            -- https://community.windy.com/topic/8168/report-your-weather-station-data-to-windy
            -- temp from kelvin to Celsius
            -- winddir from radiant to degrees
            -- rh from ratio to percentage
            SELECT jsonb_build_object(
                'dateutc', metric_rec.time_bucket,
                'station', windy_rec.id,
                'name', windy_rec.name,
                'lat', metric_rec.lat,
                'lon', metric_rec.lng,
                'wind', metric_rec.wind,
                'gust', metric_rec.gust,
                'pressure', metric_rec.pressure,
                'winddir', radiantToDegrees(metric_rec.winddir::numeric),
                'temp', kelvinToCel(metric_rec.temperature::numeric),
                'rh', valToPercent(metric_rec.rh::numeric)
                ) INTO windy_metric;
            RAISE NOTICE '-> cron_process_windy_fn checking windy_metrics [%]', windy_metric;
            SELECT windy_pws_py_fn(windy_metric, user_settings, app_settings) into windy_pws;
            RAISE NOTICE '-> cron_process_windy_fn Windy PWS [%]', ((windy_pws->'header')::JSONB ? 'id');
            IF NOT((user_settings->'settings')::JSONB ? 'windy') and ((windy_pws->'header')::JSONB ? 'id') then
                RAISE NOTICE '-> cron_process_windy_fn new Windy PWS [%]', (windy_pws->'header')::JSONB->>'id';
                -- Send metrics to Windy
                PERFORM api.update_user_preferences_fn('{windy}'::TEXT, ((windy_pws->'header')::JSONB->>'id')::TEXT);
                -- Send notification
                PERFORM send_notification_fn('windy'::TEXT, user_settings::JSONB);
                -- Refresh user settings after first success
                user_settings := get_user_settings_from_vesselid_fn(windy_rec.vessel_id::TEXT);
            END IF;
            -- Record last metrics time
            SELECT metric_rec.time_bucket INTO last_metric;
        END LOOP;
        PERFORM api.update_user_preferences_fn('{windy_last_metric}'::TEXT, last_metric::TEXT);
    END LOOP;
END;
$$ language plpgsql;

-- Add security definer, run this function as admin to avoid weird bug
-- ERROR:  variable not found in subplan target list
CREATE OR REPLACE FUNCTION api.delete_logbook_fn(IN _id integer) RETURNS BOOLEAN AS $delete_logbook$
    DECLARE
        logbook_rec record;
        previous_stays_id numeric;
        current_stays_departed text;
        current_stays_id numeric;
        current_stays_active boolean;
       BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> delete_logbook_fn invalid input %', _id;
            RETURN FALSE;
        END IF;
        -- Get the logbook record with all necessary fields exist
        SELECT * INTO logbook_rec
            FROM api.logbook
            WHERE id = _id;
        -- Ensure the query is successful
        IF logbook_rec.vessel_id IS NULL THEN
            RAISE WARNING '-> delete_logbook_fn invalid logbook %', _id;
            RETURN FALSE;
        END IF;
        -- Update logbook
        UPDATE api.logbook l
            SET notes = 'mark for deletion'
            WHERE l.vessel_id = current_setting('vessel.id', false)
                AND id = logbook_rec.id;
        -- Update metrics status to moored
        -- This generate an error when run as user_role "variable not found in subplan target list"
        UPDATE api.metrics
            SET status = 'moored'
            WHERE time >= logbook_rec._from_time
                AND time <= logbook_rec._to_time
                AND vessel_id = current_setting('vessel.id', false);
        -- Get related stays
        SELECT id,departed,active INTO current_stays_id,current_stays_departed,current_stays_active
            FROM api.stays s
            WHERE s.vessel_id = current_setting('vessel.id', false)
                AND s.arrived = logbook_rec._to_time;
        -- Update related stays
        UPDATE api.stays s
            SET notes = 'mark for deletion'
            WHERE s.vessel_id = current_setting('vessel.id', false)
                AND s.arrived = logbook_rec._to_time;
        -- Find previous stays
        SELECT id INTO previous_stays_id
            FROM api.stays s
            WHERE s.vessel_id = current_setting('vessel.id', false)
                AND s.arrived < logbook_rec._to_time
                ORDER BY s.arrived DESC LIMIT 1;
        -- Update previous stays with the departed time from current stays
        --  and set the active state from current stays
        UPDATE api.stays
            SET departed = current_stays_departed::TIMESTAMPTZ,
                active = current_stays_active
            WHERE vessel_id = current_setting('vessel.id', false)
                AND id = previous_stays_id;
        -- Clean up, remove invalid logbook and stay entry
        DELETE FROM api.logbook WHERE id = logbook_rec.id;
        RAISE WARNING '-> delete_logbook_fn delete logbook [%]', logbook_rec.id;
        DELETE FROM api.stays WHERE id = current_stays_id;
        RAISE WARNING '-> delete_logbook_fn delete stays [%]', current_stays_id;
        -- Clean up, Subtract (-1) moorages ref count
        UPDATE api.moorages
            SET reference_count = reference_count - 1
            WHERE vessel_id = current_setting('vessel.id', false)
                AND id = previous_stays_id;
        RETURN TRUE;
    END;
$delete_logbook$ LANGUAGE plpgsql security definer;

-- Allow users to update certain columns on specific TABLES on API schema add reference_count, when deleting a log
GRANT UPDATE (name, notes, stay_code, home_flag, reference_count) ON api.moorages TO user_role;

-- Allow users to update certain columns on specific TABLES on API schema add track_geojson
GRANT UPDATE (name, _from, _to, notes, track_geojson) ON api.logbook TO user_role;

DROP FUNCTION IF EXISTS api.timelapse2_fn;
CREATE OR REPLACE FUNCTION api.timelapse2_fn(
    IN start_log INTEGER DEFAULT NULL,
    IN end_log INTEGER DEFAULT NULL,
    IN start_date TEXT DEFAULT NULL,
    IN end_date TEXT DEFAULT NULL,
    OUT geojson JSONB) RETURNS JSONB AS $timelapse2$
    DECLARE
        _geojson jsonb;
    BEGIN
        -- Using sub query to force id order by time
        -- User can now directly edit the json to add comment or remove track point
        -- Merge json track_geojson with Geometry Point into a single GeoJSON Points
        --raise WARNING 'input % % %' , start_log, end_log, public.isnumeric(end_log::text);
        IF start_log IS NOT NULL AND end_log IS NULL THEN
            end_log := start_log;
        END IF;
        IF start_date IS NOT NULL AND end_date IS NULL THEN
            end_date := start_date;
        END IF;
        --raise WARNING 'input % % %' , start_log, end_log, public.isnumeric(end_log::text);
        IF start_log IS NOT NULL AND public.isnumeric(start_log::text) AND public.isnumeric(end_log::text) THEN
            SELECT jsonb_agg(
                        jsonb_build_object('type', 'Feature',
                                            'properties', f->'properties',
                                            'geometry', jsonb_build_object( 'coordinates', f->'geometry'->'coordinates', 'type', 'Point'))
                    ) INTO _geojson
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook l
                    WHERE l.id >= start_log
                        AND l.id <= end_log
                        AND l.track_geojson IS NOT NULL
                    ORDER BY l._from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'Point';
        ELSIF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            SELECT jsonb_agg(
                        jsonb_build_object('type', 'Feature',
                                            'properties', f->'properties',
                                            'geometry', jsonb_build_object( 'coordinates', f->'geometry'->'coordinates', 'type', 'Point'))
                    ) INTO _geojson
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook l
                    WHERE l._from_time >= start_date::TIMESTAMPTZ
                        AND l._to_time <= end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
                        AND l.track_geojson IS NOT NULL
                    ORDER BY l._from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'Point';
        ELSE
            SELECT jsonb_agg(
                        jsonb_build_object('type', 'Feature',
                                            'properties', f->'properties',
                                            'geometry', jsonb_build_object( 'coordinates', f->'geometry'->'coordinates', 'type', 'Point'))
                    ) INTO _geojson
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook l
                    WHERE l.track_geojson IS NOT NULL
                    ORDER BY l._from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'Point';
        END IF;
        -- Return a GeoJSON MultiLineString
        -- result _geojson [null, null]
        --RAISE WARNING 'result _geojson %' , _geojson;
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', _geojson ) INTO geojson;
    END;
$timelapse2$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.timelapse2_fn
    IS 'Export all selected logs geojson `track_geojson` to a geojson as points including properties';

-- Allow timelapse2_fn execution for user_role and api_anonymous (public replay)
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON FUNCTION api.timelapse2_fn TO api_anonymous;

DROP FUNCTION IF EXISTS public.process_logbook_queue_fn;
CREATE OR REPLACE FUNCTION public.process_logbook_queue_fn(IN _id integer) RETURNS void AS $process_logbook_queue$
    DECLARE
        logbook_rec record;
        from_name text;
        to_name text;
        log_name text;
        from_moorage record;
        to_moorage record;
        avg_rec record;
        geo_rec record;
        log_settings jsonb;
        user_settings jsonb;
        geojson jsonb;
        extra_json jsonb;
        trip_note jsonb;
        from_moorage_note jsonb;
        to_moorage_note jsonb;
    BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_logbook_queue_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Get the logbook record with all necessary fields exist
        SELECT * INTO logbook_rec
            FROM api.logbook
            WHERE active IS false
                AND id = _id
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        -- Ensure the query is successful
        IF logbook_rec.vessel_id IS NULL THEN
            RAISE WARNING '-> process_logbook_queue_fn invalid logbook %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', logbook_rec.vessel_id, false);
        --RAISE WARNING 'public.process_logbook_queue_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);

        -- Calculate logbook data average and geo
        -- Update logbook entry with the latest metric data and calculate data
        avg_rec := logbook_update_avg_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        geo_rec := logbook_update_geom_distance_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);

        -- Do we have an existing moorage within 300m of the new log
        -- generate logbook name, concat _from_location and _to_location from moorage name
        from_moorage := process_lat_lon_fn(logbook_rec._from_lng::NUMERIC, logbook_rec._from_lat::NUMERIC);
        to_moorage := process_lat_lon_fn(logbook_rec._to_lng::NUMERIC, logbook_rec._to_lat::NUMERIC);
        SELECT CONCAT(from_moorage.moorage_name, ' to ' , to_moorage.moorage_name) INTO log_name;

        -- Process `propulsion.*.runTime` and `navigation.log`
        -- Calculate extra json
        extra_json := logbook_update_extra_json_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);

        RAISE NOTICE 'Updating valid logbook entry logbook id:[%] start:[%] end:[%]', logbook_rec.id, logbook_rec._from_time, logbook_rec._to_time;
        UPDATE api.logbook
            SET
                duration = (logbook_rec._to_time::TIMESTAMPTZ - logbook_rec._from_time::TIMESTAMPTZ),
                avg_speed = avg_rec.avg_speed,
                max_speed = avg_rec.max_speed,
                max_wind_speed = avg_rec.max_wind_speed,
                _from = from_moorage.moorage_name,
                _from_moorage_id = from_moorage.moorage_id,
                _to_moorage_id = to_moorage.moorage_id,
                _to = to_moorage.moorage_name,
                name = log_name,
                track_geom = geo_rec._track_geom,
                distance = geo_rec._track_distance,
                extra = extra_json,
                notes = NULL -- reset pre_log process
            WHERE id = logbook_rec.id;

        -- GeoJSON require track_geom field
        geojson := logbook_update_geojson_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        UPDATE api.logbook
            SET
                track_geojson = geojson
            WHERE id = logbook_rec.id;

        -- Add trip details  name as note for the first geometry point entry from the GeoJSON
        SELECT format('{"trip": { "name": "%s", "duration": "%s", "distance": "%s" }}', logbook_rec.name, logbook_rec.duration, logbook_rec.distance) into trip_note;
        -- Update the properties of the first feature
        UPDATE api.logbook
            SET track_geojson = jsonb_set(
                track_geojson,
                '{features, 1, properties}',
                (track_geojson -> 'features' -> 1 -> 'properties' || trip_note)::jsonb
            )
            WHERE id = logbook_rec.id
                and track_geojson -> 'features' -> 1 -> 'geometry' ->> 'type' = 'Point';

        -- Add moorage name as note for the third and last entry of the GeoJSON
        SELECT format('{"notes": "%s"}', from_moorage.moorage_name) into from_moorage_note;
        -- Update the properties of the third feature, the second with geometry point
        UPDATE api.logbook
            SET track_geojson = jsonb_set(
                track_geojson,
                '{features, 2, properties}',
                (track_geojson -> 'features' -> 2 -> 'properties' || from_moorage_note)::jsonb
            )
            WHERE id = logbook_rec.id
                AND track_geojson -> 'features' -> 2 -> 'geometry' ->> 'type' = 'Point';

        -- Update the note properties of the last feature with geometry point
        SELECT format('{"notes": "%s"}', to_moorage.moorage_name) into to_moorage_note;
        UPDATE api.logbook
            SET track_geojson = jsonb_set(
                track_geojson,
                '{features, -1, properties}',
                CASE
                    WHEN COALESCE((track_geojson -> 'features' -> -1 -> 'properties' ->> 'notes'), '') = '' THEN
                        (track_geojson -> 'features' -> -1 -> 'properties' || to_moorage_note)::jsonb
                    ELSE
                        track_geojson -> 'features' -> -1 -> 'properties'
                END
            )
            WHERE id = logbook_rec.id
                AND track_geojson -> 'features' -> -1 -> 'geometry' ->> 'type' = 'Point';

        -- Prepare notification, gather user settings
        SELECT json_build_object('logbook_name', log_name, 'logbook_link', logbook_rec.id) into log_settings;
        user_settings := get_user_settings_from_vesselid_fn(logbook_rec.vessel_id::TEXT);
        SELECT user_settings::JSONB || log_settings::JSONB into user_settings;
        RAISE NOTICE '-> debug process_logbook_queue_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        RAISE NOTICE '-> debug process_logbook_queue_fn log_settings [%]', log_settings;
        -- Send notification
        PERFORM send_notification_fn('logbook'::TEXT, user_settings::JSONB);
        -- Process badges
        RAISE NOTICE '-> debug process_logbook_queue_fn user_settings [%]', user_settings->>'email'::TEXT;
        PERFORM set_config('user.email', user_settings->>'email'::TEXT, false);
        PERFORM badges_logbook_fn(logbook_rec.id, logbook_rec._to_time::TEXT);
        PERFORM badges_geom_fn(logbook_rec.id, logbook_rec._to_time::TEXT);
    END;
$process_logbook_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_logbook_queue_fn
    IS 'Update logbook details when completed, logbook_update_avg_fn, logbook_update_geom_distance_fn, reverse_geocode_py_fn';

-- Update the pre.check for the new timelapse function
CREATE OR REPLACE FUNCTION public.check_jwt() RETURNS void AS $$
-- Prevent unregister user or unregister vessel access
-- Allow anonymous access
-- Need to be refactor and simplify, specially the anonymous part.
DECLARE
  _role name;
  _email text;
  anonymous record;
  _path name;
  _vid text;
  _vname text;
  boat TEXT;
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
  -- Extract email and role from jwt token
  --RAISE WARNING 'check_jwt jwt %', current_setting('request.jwt.claims', true);
  SELECT current_setting('request.jwt.claims', true)::json->>'email' INTO _email;
  PERFORM set_config('user.email', _email, false);
  SELECT current_setting('request.jwt.claims', true)::json->>'role' INTO _role;
  --RAISE WARNING 'jwt email %', current_setting('request.jwt.claims', true)::json->>'email';
  --RAISE WARNING 'jwt role %', current_setting('request.jwt.claims', true)::json->>'role';
  --RAISE WARNING 'cur_user %', current_user;

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
    PERFORM set_config('user.id', account_rec.user_id, false);
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
    PERFORM set_config('vessel.id', vessel_rec.vessel_id, false);
    PERFORM set_config('vessel.name', vessel_rec.name, false);
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
    PERFORM set_config('vessel.id', vessel_rec.vessel_id, false);
    PERFORM set_config('vessel.name', vessel_rec.name, false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.name %', current_setting('vessel.name', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.id %', current_setting('vessel.id', false);
  ELSIF _role = 'api_anonymous' THEN
    --RAISE WARNING 'public.check_jwt() api_anonymous';
    -- Check if path is a valid allow anonymous path
    SELECT current_setting('request.path', true) ~ '^/(logs_view|log_view|rpc/timelapse_fn|rpc/timelapse2_fn|monitoring_view|stats_logs_view|stats_moorages_view|rpc/stats_logs_fn)$' INTO _ppath;
    if _ppath is True then
        -- Check is custom header is present and valid
        SELECT current_setting('request.headers', true)::json->>'x-is-public' into _pheader;
        RAISE WARNING 'public.check_jwt() api_anonymous _pheader [%]', _pheader;
        if _pheader is null then
            RAISE EXCEPTION 'Invalid public_header'
                USING HINT = 'Stop being so evil and maybe you can log in';
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
                SELECT v.vessel_id, v.name into anonymous
                    FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs, log l
                    WHERE v.vessel_id = l.vessel_id
                        AND a.email = v.owner_email
                        AND a.preferences->>'public_vessel'::text ~* boat
                        AND prefs.key = _ptype::TEXT
                        AND prefs.value::BOOLEAN = true;
                RAISE WARNING '-> ispublic_fn public_logs output boat:[%], type:[%], result:[%]', _pvessel, _ptype, anonymous;
                IF anonymous.vessel_id IS NOT NULL THEN
                    PERFORM set_config('vessel.id', anonymous.vessel_id, false);
                    PERFORM set_config('vessel.name', anonymous.name, false);
                    RETURN;
                END IF;
            ELSE
                SELECT v.vessel_id, v.name into anonymous
                        FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs
                        WHERE a.email = v.owner_email
                            AND a.preferences->>'public_vessel'::text ~* boat
                            AND prefs.key = _ptype::TEXT
                            AND prefs.value::BOOLEAN = true;
                RAISE WARNING '-> ispublic_fn output boat:[%], type:[%], result:[%]', _pvessel, _ptype, anonymous;
                IF anonymous.vessel_id IS NOT NULL THEN
                    PERFORM set_config('vessel.id', anonymous.vessel_id, false);
                    PERFORM set_config('vessel.name', anonymous.name, false);
                    RETURN;
                END IF;
            END IF;
            RAISE sqlstate 'PT404' using message = 'unknown resource';
        END IF; -- end anonymous path
    END IF;
  ELSIF _role <> 'api_anonymous' THEN
    RAISE EXCEPTION 'Invalid role'
      USING HINT = 'Stop being so evil and maybe you can log in';
  END IF;
END
$$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    public.check_jwt
    IS 'PostgREST API db-pre-request check, set_config according to role (api_anonymous,vessel_role,user_role)';

GRANT EXECUTE ON FUNCTION public.check_jwt() TO api_anonymous;

-- Update version
UPDATE public.app_settings
	SET value='0.7.2'
	WHERE "name"='app.version';
