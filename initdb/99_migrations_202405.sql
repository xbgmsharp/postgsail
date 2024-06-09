---------------------------------------------------------------------------
-- Copyright 2021-2024 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration May 2024
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

INSERT INTO public.email_templates ("name",email_subject,email_content,pushover_title,pushover_message)
	VALUES ('account_disable','PostgSail Account disable',E'Hello __RECIPIENT__,\nSorry!Your account is disable. Please contact me to solve the issue.','PostgSail Account disable!',E'Sorry!\nYour account is disable. Please contact me to solve the issue.');

-- Check if user is disable due to abuse
-- Track IP per user to avoid abuse
create or replace function
api.login(in email text, in pass text) returns auth.jwt_token as $$
declare
  _role name;
  result auth.jwt_token;
  app_jwt_secret text;
  _email_valid boolean := false;
  _email text := email;
  _user_id text := null;
  _user_disable boolean := false;
  headers   json := current_setting('request.headers', true)::json;
  client_ip text := coalesce(headers->>'x-client-ip', NULL);
begin
  -- check email and password
  select auth.user_role(email, pass) into _role;
  if _role is null then
    -- HTTP/403
    --raise invalid_password using message = 'invalid user or password';
    -- HTTP/401
    raise insufficient_privilege using message = 'invalid user or password';
  end if;

  -- Check if user is disable due to abuse
  SELECT preferences['disable'],user_id INTO _user_disable,_user_id
              FROM auth.accounts a
              WHERE a.email = _email;
  IF _user_disable is True then
  	-- due to the raise, the insert is never committed.
    --INSERT INTO process_queue (channel, payload, stored, ref_id)
    --  VALUES ('account_disable', _email, now(), _user_id);
    RAISE sqlstate 'PT402' using message = 'Account disable, contact us',
            detail = 'Quota exceeded',
            hint = 'Upgrade your plan';
  END IF;

  -- Check email_valid and generate OTP
  SELECT preferences['email_valid'],user_id INTO _email_valid,_user_id
              FROM auth.accounts a
              WHERE a.email = _email;
  IF _email_valid is null or _email_valid is False THEN
    INSERT INTO process_queue (channel, payload, stored, ref_id)
      VALUES ('email_otp', _email, now(), _user_id);
  END IF;

  -- Track IP per user to avoid abuse
  --RAISE WARNING 'api.login debug: [%],[%]', client_ip, login.email;
  IF client_ip IS NOT NULL THEN
    UPDATE auth.accounts a SET preferences = jsonb_recursive_merge(a.preferences, jsonb_build_object('ip', client_ip)) WHERE a.email = login.email;
  END IF;

  -- Get app_jwt_secret
  SELECT value INTO app_jwt_secret
    FROM app_settings
    WHERE name = 'app.jwt_secret';

  --RAISE WARNING 'api.login debug: [%],[%],[%]', app_jwt_secret, _role, login.email;
  -- Generate jwt
  select jwt.sign(
  --    row_to_json(r), ''
  --    row_to_json(r)::json, current_setting('app.jwt_secret')::text
      row_to_json(r)::json, app_jwt_secret
    ) as token
    from (
      select _role as role, login.email as email,  -- TODO replace with user_id
    --  select _role as role, user_id as uid, -- add support in check_jwt
         extract(epoch from now())::integer + 60*60 as exp
    ) r
    into result;
  return result;
end;
$$ language plpgsql security definer;

-- Add moorage name to view
DROP VIEW IF EXISTS api.moorages_stays_view;
CREATE OR REPLACE VIEW api.moorages_stays_view WITH (security_invoker=true,security_barrier=true) AS
    select
        _to.name AS _to_name,
        _to.id AS _to_id,
        _to._to_time,
        _from.id AS _from_id,
        _from.name AS _from_name,
        _from._from_time,
        s.stay_code,s.duration,m.id,m.name
        FROM api.stays_at sa, api.moorages m, api.stays s
        LEFT JOIN api.logbook AS _from ON _from._from_time = s.departed
        LEFT JOIN api.logbook AS _to ON _to._to_time = s.arrived
        WHERE s.departed IS NOT NULL
            AND s.name IS NOT NULL
            AND s.stay_code = sa.stay_code
            AND s.moorage_id = m.id
        ORDER BY _to._to_time DESC;
-- Description
COMMENT ON VIEW
    api.moorages_stays_view
    IS 'Moorages stay listing web view';

-- Create a merge_logbook_fn
CREATE OR REPLACE FUNCTION api.merge_logbook_fn(IN id_start integer, IN id_end integer) RETURNS void AS $merge_logbook$
    DECLARE
        logbook_rec_start record;
        logbook_rec_end record;
        log_name text;
        avg_rec record;
        geo_rec record;
        geojson jsonb;
        extra_json jsonb;
    BEGIN
        -- If id_start or id_end is not NULL
        IF (id_start IS NULL OR id_start < 1) OR (id_end IS NULL OR id_end < 1) THEN
            RAISE WARNING '-> merge_logbook_fn invalid input % %', id_start, id_end;
            RETURN;
        END IF;
        -- If id_end is lower than id_start
        IF id_end <= id_start THEN
            RAISE WARNING '-> merge_logbook_fn invalid input % < %', id_end, id_start;
            RETURN;
        END IF;
        -- Get the start logbook record with all necessary fields exist
        SELECT * INTO logbook_rec_start
            FROM api.logbook
            WHERE active IS false
                AND id = id_start
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        -- Ensure the query is successful
        IF logbook_rec_start.vessel_id IS NULL THEN
            RAISE WARNING '-> merge_logbook_fn invalid logbook %', id_start;
            RETURN;
        END IF;
        -- Get the end logbook record with all necessary fields exist
        SELECT * INTO logbook_rec_end
            FROM api.logbook
            WHERE active IS false
                AND id = id_end
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        -- Ensure the query is successful
        IF logbook_rec_end.vessel_id IS NULL THEN
            RAISE WARNING '-> merge_logbook_fn invalid logbook %', id_end;
            RETURN;
        END IF;

       	RAISE WARNING '-> merge_logbook_fn logbook start:% end:%', id_start, id_end;
        PERFORM set_config('vessel.id', logbook_rec_start.vessel_id, false);
   
        -- Calculate logbook data average and geo
        -- Update logbook entry with the latest metric data and calculate data
        avg_rec := logbook_update_avg_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);
        geo_rec := logbook_update_geom_distance_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);

	    -- Process `propulsion.*.runTime` and `navigation.log`
        -- Calculate extra json
        extra_json := logbook_update_extra_json_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);
        -- add the avg_wind_speed
        extra_json := extra_json || jsonb_build_object('avg_wind_speed', avg_rec.avg_wind_speed);

       	-- generate logbook name, concat _from_location and _to_location from moorage name
       	SELECT CONCAT(logbook_rec_start._from, ' to ', logbook_rec_end._to) INTO log_name;
        RAISE NOTICE 'Updating valid logbook entry logbook id:[%] start:[%] end:[%]', logbook_rec_start.id, logbook_rec_start._from_time, logbook_rec_end._to_time;
        UPDATE api.logbook
            SET
                -- Update the start logbook with the new calculate metrics
            	duration = (logbook_rec_end._to_time::TIMESTAMPTZ - logbook_rec_start._from_time::TIMESTAMPTZ),
                avg_speed = avg_rec.avg_speed,
                max_speed = avg_rec.max_speed,
                max_wind_speed = avg_rec.max_wind_speed,
                name = log_name,
                track_geom = geo_rec._track_geom,
                distance = geo_rec._track_distance,
                extra = extra_json,
                -- Set _to metrics from end logbook
                _to = logbook_rec_end._to,
                _to_moorage_id = logbook_rec_end._to_moorage_id,
                _to_lat = logbook_rec_end._to_lat,
                _to_lng = logbook_rec_end._to_lng,
                _to_time = logbook_rec_end._to_time
            WHERE id = logbook_rec_start.id;

        -- GeoJSON require track_geom field
        geojson := logbook_update_geojson_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);
        UPDATE api.logbook
            SET
                track_geojson = geojson
            WHERE id = logbook_rec_start.id;
 
        -- Update logbook mark for deletion
        UPDATE api.logbook
            SET notes = 'mark for deletion'
            WHERE id = logbook_rec_end.id;
        -- Update related stays mark for deletion
        UPDATE api.stays
            SET notes = 'mark for deletion'
            WHERE arrived = logbook_rec_start._to_time;
       -- Update related moorages mark for deletion
        UPDATE api.moorages
            SET notes = 'mark for deletion'
            WHERE id = logbook_rec_start._to_moorage_id;

        -- Clean up, remove invalid logbook and stay, moorage entry
        DELETE FROM api.logbook WHERE id = logbook_rec_end.id;
        RAISE WARNING '-> merge_logbook_fn delete logbook id [%]', logbook_rec_end.id;
        DELETE FROM api.stays WHERE arrived = logbook_rec_start._to_time;
        RAISE WARNING '-> merge_logbook_fn delete stay arrived [%]', logbook_rec_start._to_time;
        DELETE FROM api.moorages WHERE id = logbook_rec_start._to_moorage_id;
        RAISE WARNING '-> merge_logbook_fn delete moorage id [%]', logbook_rec_start._to_moorage_id;
    END;
$merge_logbook$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.merge_logbook_fn
    IS 'Merge 2 logbook by id, from the start of the lower log id and the end of the higher log id, update the calculate data as well (avg, geojson)';

-- Add tags to view
DROP VIEW IF EXISTS api.logs_view;
CREATE OR REPLACE VIEW api.logs_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT id,
    name,
    _from AS "from",
    _from_time AS started,
    _to AS "to",
    _to_time AS ended,
    distance,
    duration,
    _from_moorage_id,
    _to_moorage_id,
    extra->'tags' AS tags
   FROM api.logbook l
  WHERE name IS NOT NULL AND _to_time IS NOT NULL
  ORDER BY _from_time DESC;
-- Description
COMMENT ON VIEW api.logs_view IS 'Logs web view';

-- Update a logbook with avg wind speed
DROP FUNCTION IF EXISTS public.logbook_update_avg_fn;
CREATE OR REPLACE FUNCTION public.logbook_update_avg_fn(
    IN _id integer, 
    IN _start TEXT, 
    IN _end TEXT,
    OUT avg_speed double precision,
    OUT max_speed double precision,
    OUT max_wind_speed double precision,
    OUT avg_wind_speed double precision,
    OUT count_metric integer
) AS $logbook_update_avg$
    BEGIN
        RAISE NOTICE '-> logbook_update_avg_fn calculate avg for logbook id=%, start:"%", end:"%"', _id, _start, _end;
        SELECT AVG(speedoverground), MAX(speedoverground), MAX(windspeedapparent), AVG(windspeedapparent), COUNT(*) INTO
                avg_speed, max_speed, max_wind_speed, avg_wind_speed, count_metric
            FROM api.metrics m
            WHERE m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.time >= _start::TIMESTAMPTZ
                AND m.time <= _end::TIMESTAMPTZ
                AND vessel_id = current_setting('vessel.id', false);
        RAISE NOTICE '-> logbook_update_avg_fn avg for logbook id=%, avg_speed:%, max_speed:%, avg_wind_speed:%, max_wind_speed:%, count:%', _id, avg_speed, max_speed, avg_wind_speed, max_wind_speed, count_metric;
    END;
$logbook_update_avg$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_avg_fn
    IS 'Update logbook details with calculate average and max data, AVG(speedOverGround), MAX(speedOverGround), MAX(windspeedapparent), count_metric';

-- Update pending new logbook from process queue
DROP FUNCTION IF EXISTS process_logbook_queue_fn;
CREATE OR REPLACE FUNCTION process_logbook_queue_fn(IN _id integer) RETURNS void AS $process_logbook_queue$
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
        -- add the avg_wind_speed
        extra_json := extra_json || jsonb_build_object('avg_wind_speed', avg_rec.avg_wind_speed);

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

        -- GeoJSON require track_geom field geometry linestring
        geojson := logbook_update_geojson_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        UPDATE api.logbook
            SET
                track_geojson = geojson
            WHERE id = logbook_rec.id;

        -- GeoJSON Timelapse require track_geojson geometry point
        -- Add properties to the geojson for timelapse purpose
        PERFORM public.logbook_timelapse_geojson_fn(logbook_rec.id);

        -- Add post logbook entry to process queue for notification and QGIS processing
        -- Require as we need the logbook to be updated with SQL commit
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('post_logbook', logbook_rec.id, NOW(), current_setting('vessel.id', true));

    END;
$process_logbook_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_logbook_queue_fn
    IS 'Update logbook details when completed, logbook_update_avg_fn, logbook_update_geom_distance_fn, reverse_geocode_py_fn';

-- Add avg_wind_speed to logbook geojson
-- Add back truewindspeed and truewinddirection to logbook geojson
DROP FUNCTION IF EXISTS public.logbook_update_geojson_fn;
CREATE FUNCTION public.logbook_update_geojson_fn(IN _id integer, IN _start text, IN _end text,
    OUT _track_geojson JSON
 ) AS $logbook_geojson$
    declare
     log_geojson jsonb;
     metrics_geojson jsonb;
     _map jsonb;
    begin
        -- GeoJson Feature Logbook linestring
        SELECT
            ST_AsGeoJSON(log.*) into log_geojson
        FROM
           ( SELECT
                id,name,
                distance,
                duration,
                avg_speed,
                max_speed,
                max_wind_speed,
                _from_time,
                _to_time
                _from_moorage_id,
                _to_moorage_id,
                notes,
                extra['avg_wind_speed'] as avg_wind_speed,
                track_geom
                FROM api.logbook
                WHERE id = _id
           ) AS log;
        -- GeoJson Feature Metrics point
        SELECT
            json_agg(ST_AsGeoJSON(t.*)::json) into metrics_geojson
        FROM (
            ( SELECT
                time,
                courseovergroundtrue,
                speedoverground,
                windspeedapparent,
                longitude,latitude,
                '' AS notes,
                coalesce(metersToKnots((metrics->'environment.wind.speedTrue')::NUMERIC), null) as truewindspeed,
                coalesce(radiantToDegrees((metrics->'environment.wind.directionTrue')::NUMERIC), null) as truewinddirection,
                coalesce(status, null) as status,
                st_makepoint(longitude,latitude) AS geo_point
                FROM api.metrics m
                WHERE m.latitude IS NOT NULL
                    AND m.longitude IS NOT NULL
                    AND time >= _start::TIMESTAMPTZ
                    AND time <= _end::TIMESTAMPTZ
                    AND vessel_id = current_setting('vessel.id', false)
                ORDER BY m.time ASC
            )
        ) AS t;

        -- Merge jsonb
        SELECT log_geojson::jsonb || metrics_geojson::jsonb into _map;
        -- output
        SELECT
            json_build_object(
                'type', 'FeatureCollection',
                'features', _map
            ) into _track_geojson;
    END;
$logbook_geojson$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_geojson_fn
    IS 'Update log details with geojson';

-- Add properties to the geojson for timelapse purpose
DROP FUNCTION IF EXISTS public.logbook_timelapse_geojson_fn;
CREATE FUNCTION public.logbook_timelapse_geojson_fn(IN _id INT) returns void
AS $logbook_timelapse$
    declare
        first_feature_note JSONB;
        second_feature_note JSONB;
        last_feature_note JSONB;
        logbook_rec record;
    begin
        -- We need to fetch the processed logbook data.
        SELECT name,duration,distance,_from,_to INTO logbook_rec
            FROM api.logbook
            WHERE active IS false
                AND id = _id
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        --raise warning '-> logbook_rec: %', logbook_rec;
        select format('{"trip": { "name": "%s", "duration": "%s", "distance": "%s" }}', logbook_rec.name, logbook_rec.duration, logbook_rec.distance) into first_feature_note;
        select format('{"notes": "%s"}', logbook_rec._from) into second_feature_note;
        select format('{"notes": "%s"}', logbook_rec._to) into last_feature_note;
        --raise warning '-> logbook_rec: % % %', first_feature_note, second_feature_note, last_feature_note;

        -- Update the properties of the first feature, the second with geometry point
        UPDATE api.logbook
            SET track_geojson = jsonb_set(
                track_geojson,
                '{features, 1, properties}',
                (track_geojson -> 'features' -> 1 -> 'properties' || first_feature_note)::jsonb
            )
            WHERE id = _id
                and track_geojson -> 'features' -> 1 -> 'geometry' ->> 'type' = 'Point';

        -- Update the properties of the third feature, the second with geometry point
        UPDATE api.logbook
            SET track_geojson = jsonb_set(
                track_geojson,
                '{features, 2, properties}',
                (track_geojson -> 'features' -> 2 -> 'properties' || second_feature_note)::jsonb
            )
            where id = _id
                and track_geojson -> 'features' -> 2 -> 'geometry' ->> 'type' = 'Point';

        -- Update the properties of the last feature with geometry point
        UPDATE api.logbook
            SET track_geojson = jsonb_set(
                track_geojson,
                '{features, -1, properties}',
                CASE
                    WHEN COALESCE((track_geojson -> 'features' -> -1 -> 'properties' ->> 'notes'), '') = '' THEN
                        (track_geojson -> 'features' -> -1 -> 'properties' || last_feature_note)::jsonb
                    ELSE
                        track_geojson -> 'features' -> -1 -> 'properties'
                END
            )
            WHERE id = _id
                and track_geojson -> 'features' -> -1 -> 'geometry' ->> 'type' = 'Point';
end;
$logbook_timelapse$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_timelapse_geojson_fn
    IS 'Update logbook geojson, Add properties to some geojson features for timelapse purpose';

-- CRON for signalk plugin upgrade
-- The goal is to avoid error from old plugin version by enforcing upgrade.
-- ERROR:  there is no unique or exclusion constraint matching the ON CONFLICT specification
-- "POST /metadata?on_conflict=client_id HTTP/1.1" 400 137 "-" "postgsail.signalk v0.0.9"
DROP FUNCTION IF EXISTS public.cron_process_skplugin_upgrade_fn;
CREATE FUNCTION public.cron_process_skplugin_upgrade_fn() RETURNS void AS $skplugin_upgrade$
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
            WHERE m.plugin_version <= '0.3.0'
    LOOP
        RAISE NOTICE '-> cron_process_skplugin_upgrade_rec_fn for [%]', skplugin_upgrade_rec;
        SELECT json_build_object('email', skplugin_upgrade_rec.owner_email, 'recipient', skplugin_upgrade_rec.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_skplugin_upgrade_rec_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('skplugin_upgrade'::TEXT, user_settings::JSONB);
    END LOOP;
END;
$skplugin_upgrade$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_skplugin_upgrade_fn
    IS 'init by pg_cron, check for signalk plugin version and notify for upgrade';

INSERT INTO public.email_templates ("name",email_subject,email_content,pushover_title,pushover_message)
	VALUES ('skplugin_upgrade','PostgSail Signalk plugin upgrade',E'Hello __RECIPIENT__,\nPlease upgrade your postgsail signalk plugin. Be sure to contact me if you encounter any issue.','PostgSail Signalk plugin upgrade!',E'Please upgrade your postgsail signalk plugin.');

DROP FUNCTION IF EXISTS public.metadata_ip_trigger_fn;
-- Track IP per vessel to avoid abuse
CREATE FUNCTION public.metadata_ip_trigger_fn() RETURNS trigger
AS $metadata_ip_trigger$
    DECLARE
        headers   json := current_setting('request.headers', true)::json;
        client_ip text := coalesce(headers->>'x-client-ip', NULL);
    BEGIN
        RAISE WARNING 'metadata_ip_trigger_fn [%] [%]', current_setting('vessel.id', true), client_ip;
        IF client_ip IS NOT NULL THEN
            UPDATE api.metadata
                SET
                     configuration = NEW.configuration || jsonb_build_object('ip', client_ip)
                WHERE id = NEW.id;
        END IF;
        RETURN NULL;
    END;
$metadata_ip_trigger$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION public.metadata_ip_trigger_fn() IS 'Add IP from vessel in metadata, track abuse';

DROP TRIGGER IF EXISTS metadata_ip_trigger ON api.metadata;
-- Generate an error
--CREATE TRIGGER metadata_ip_trigger BEFORE UPDATE ON api.metadata
--    FOR EACH ROW EXECUTE FUNCTION metadata_ip_trigger_fn();
-- Description
--COMMENT ON TRIGGER
--    metadata_ip_trigger ON api.metadata
--    IS 'AFTER UPDATE ON api.metadata run function metadata_ip_trigger_fn for tracking vessel IP';

DROP FUNCTION IF EXISTS public.logbook_active_geojson_fn;
CREATE FUNCTION public.logbook_active_geojson_fn(
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
                            AND m.time <= l._to_time::TIMESTAMPTZ
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
                    coalesce(metersToKnots((metrics->'environment.wind.speedTrue')::NUMERIC), null) as truewindspeed,
                    coalesce(radiantToDegrees((metrics->'environment.wind.directionTrue')::NUMERIC), null) as truewinddirection,
                    coalesce(status, null) AS status,
                    st_makepoint(longitude,latitude) AS geo_point
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

-- Update monitoring view to support live trip and truewindspeed and truewinddirection to stationary GeoJSON.
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
                'truewindspeed', coalesce(metersToKnots((metrics->'environment.wind.speedTrue')::NUMERIC), null),
                'truewinddirection', coalesce(radiantToDegrees((metrics->'environment.wind.directionTrue')::NUMERIC), null),
                'status', coalesce(m.status, null)
                )::jsonb ) AS geojson,
        current_setting('vessel.name', false) AS name,
        m.status,
        CASE WHEN m.status <> 'moored' THEN (
            SELECT public.logbook_active_geojson_fn() )
        END AS live
    FROM api.metrics m
    ORDER BY time DESC LIMIT 1;
-- Description
COMMENT ON VIEW
    api.monitoring_view
    IS 'Monitoring static web view';

-- Allow to access tables for user_role and grafana and api_anonymous
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO grafana;
GRANT SELECT ON TABLE api.monitoring_view TO user_role;
GRANT SELECT ON TABLE api.monitoring_view TO api_anonymous;
GRANT SELECT ON TABLE api.monitoring_view TO grafana;

-- Allow to execute fn for user_role and grafana and api_anonymous
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO grafana;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO grafana;
GRANT EXECUTE ON FUNCTION public.logbook_active_geojson_fn TO api_anonymous;
GRANT EXECUTE ON FUNCTION public.metersToKnots TO api_anonymous;
GRANT EXECUTE ON FUNCTION public.radiantToDegrees TO api_anonymous;

-- Fix vessel name (Organization) ensure we have a value either from metadata tbl (signalk) or from vessel tbl
DROP FUNCTION IF EXISTS public.cron_process_grafana_fn;
CREATE OR REPLACE FUNCTION public.cron_process_grafana_fn() RETURNS void
AS $cron_process_grafana_fn$
DECLARE
    process_rec record;
    data_rec record;
    app_settings jsonb;
    user_settings jsonb;
BEGIN
    -- We run grafana provisioning only after the first received vessel metadata
    -- Check for new vessel metadata pending grafana provisioning
    RAISE NOTICE 'cron_process_grafana_fn';
    FOR process_rec in
        SELECT * from process_queue
            where channel = 'grafana' and processed is null
            order by stored asc
    LOOP
        RAISE NOTICE '-> cron_process_grafana_fn [%]', process_rec.payload;
        -- Gather url from app settings
        app_settings := get_app_settings_fn();
        -- Get vessel details base on metadata id
        SELECT
            v.owner_email,coalesce(m.name,v.name) as name,m.vessel_id into data_rec
            FROM auth.vessels v
            LEFT JOIN api.metadata m ON v.vessel_id = m.vessel_id
            WHERE m.id = process_rec.payload::INTEGER;
        IF data_rec.vessel_id IS NULL OR data_rec.name IS NULL THEN
            RAISE WARNING '-> DEBUG cron_process_grafana_fn grafana_py_fn error [%]', data_rec;
            RETURN;
        END IF;
        -- as we got data from the vessel we can do the grafana provisioning.
        RAISE DEBUG '-> DEBUG cron_process_grafana_fn grafana_py_fn provisioning [%]', data_rec;
        PERFORM grafana_py_fn(data_rec.name, data_rec.vessel_id, data_rec.owner_email, app_settings);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(data_rec.vessel_id::TEXT);
        RAISE DEBUG '-> DEBUG cron_process_grafana_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        -- add user in keycloak
        PERFORM keycloak_auth_py_fn(data_rec.vessel_id, user_settings, app_settings);
        -- Send notification
        PERFORM send_notification_fn('grafana'::TEXT, user_settings::JSONB);
        -- update process_queue entry as processed
        UPDATE process_queue
            SET
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_grafana_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$cron_process_grafana_fn$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_grafana_fn
    IS 'init by pg_cron to check for new vessel pending grafana provisioning, if so perform grafana_py_fn';

-- Update version
UPDATE public.app_settings
	SET value='0.7.3'
	WHERE "name"='app.version';

\c postgres

-- Notifications/Reminders for old signalk plugin
-- At 08:06 on Sunday.
-- At 08:06 on every 4th day-of-month if it's on Sunday.
SELECT cron.schedule('cron_skplugin_upgrade', '6 8 */4 * 0', 'select public.cron_process_skplugin_upgrade_fn()');
UPDATE cron.job	SET database = 'postgres' WHERE jobname = 'cron_skplugin_upgrade';
