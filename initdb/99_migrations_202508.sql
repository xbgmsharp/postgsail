---------------------------------------------------------------------------
-- Copyright 2021-2025 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration August 2025
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Lint fix
CREATE INDEX ON api.stays_ext (vessel_id);
ALTER TABLE api.stays_ext FORCE ROW LEVEL SECURITY;
ALTER TABLE api.metadata_ext FORCE ROW LEVEL SECURITY;
ALTER TABLE api.metadata ADD PRIMARY KEY (vessel_id);
COMMENT ON CONSTRAINT metadata_vessel_id_fkey ON api.metadata IS 'Link api.metadata with auth.vessels via vessel_id using FOREIGN KEY and REFERENCES';
COMMENT ON CONSTRAINT metrics_vessel_id_fkey ON api.metrics IS 'Link api.metrics api.metadata via vessel_id using FOREIGN KEY and REFERENCES';
COMMENT ON CONSTRAINT logbook_vessel_id_fkey ON api.logbook IS 'Link api.stays with api.metadata via vessel_id using FOREIGN KEY and REFERENCES';
COMMENT ON CONSTRAINT moorages_vessel_id_fkey ON api.moorages IS 'Link api.stays with api.metadata via vessel_id using FOREIGN KEY and REFERENCES';
COMMENT ON CONSTRAINT stays_vessel_id_fkey ON api.stays IS 'Link api.stays with api.metadata via vessel_id using FOREIGN KEY and REFERENCES';
COMMENT ON COLUMN api.logbook._from IS 'Name of the location where the log started, usually a moorage name';
COMMENT ON COLUMN api.logbook._to IS 'Name of the location where the log ended, usually a moorage name';
COMMENT ON COLUMN api.logbook.vessel_id IS 'Unique identifier for the vessel associated with the api.metadata entry';
COMMENT ON COLUMN api.metrics.vessel_id IS 'Unique identifier for the vessel associated with the api.metadata entry';
COMMENT ON COLUMN api.moorages.vessel_id IS 'Unique identifier for the vessel associated with the api.metadata entry';
COMMENT ON COLUMN api.moorages.nominatim IS 'Output of the nominatim reverse geocoding service, see https://nominatim.org/release-docs/develop/api/Reverse/';
COMMENT ON COLUMN api.moorages.overpass IS 'Output of the overpass API, see https://wiki.openstreetmap.org/wiki/Overpass_API';
COMMENT ON COLUMN api.stays.vessel_id IS 'Unique identifier for the vessel associated with the api.metadata entry';
COMMENT ON COLUMN api.stays_ext.vessel_id IS 'Unique identifier for the vessel associated with the api.metadata entry';
COMMENT ON COLUMN api.metadata_ext.vessel_id IS 'Unique identifier for the vessel associated with the api.metadata entry';
COMMENT ON COLUMN api.metadata.mmsi IS 'Maritime Mobile Service Identity (MMSI) number associated with the vessel, link to public.mid';
COMMENT ON COLUMN api.metadata.ship_type IS 'Type of ship associated with the vessel, link to public.aistypes';
--COMMENT ON TRIGGER ts_insert_blocker ON api.metrics IS 'manage by timescaledb, prevent direct insert on hypertable api.metrics';
COMMENT ON TRIGGER ensure_vessel_role_exists ON auth.vessels IS 'ensure vessel role exists';
COMMENT ON TRIGGER encrypt_pass ON auth.accounts IS 'execute function auth.encrypt_pass()';

-- Fix typo in comment
COMMENT ON FUNCTION public.new_account_entry_fn() IS 'trigger process_queue on INSERT for new account';
-- Update missing comment on trigger
COMMENT ON TRIGGER encrypt_pass ON auth.accounts IS 'execute function auth.encrypt_pass()';

-- Update new account email subject
UPDATE public.email_templates
	SET email_subject='Welcome aboard!',
    email_content='Welcome aboard __RECIPIENT__,
Congratulations!
You successfully created an account.
Keep in mind to register your vessel.
Happy sailing!'
	WHERE "name"='new_account';

-- Update deactivated email subject
UPDATE public.email_templates
	SET email_subject='We hate to see you go'
	WHERE "name"='deactivated';

-- Update first badge message
UPDATE public.badges
	SET description='Nice work logging your first sail! You’re officially a helmsman now!
While you’re at it, why not spread the word about Postgsail? ⭐
If you found it useful, consider starring the project on GitHub, contributing, or even sponsoring the project to help steer it forward.
Happy sailing! 🌊
https://github.com/xbgmsharp/postgsail
https://github.com/sponsors/xbgmsharp/'
	WHERE "name"='Helmsman';

-- DROP FUNCTION public.stays_delete_trigger_fn();
-- Add public.stay_delete_trigger_fn trigger function to delete stays_ext and process_queue entries
CREATE OR REPLACE FUNCTION public.stay_delete_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE NOTICE 'stay_delete_trigger_fn [%]', OLD;
    -- If api.stays is deleted, deleted entry in api.stays_ext table as well.
    IF EXISTS (SELECT FROM information_schema.tables 
                WHERE table_schema = 'api' 
                AND table_name = 'stays_ext') THEN
        -- Delete stays_ext
        DELETE FROM api.stays_ext s
            WHERE s.stay_id = OLD.id;
    END IF;
    -- Delete process_queue references
    DELETE FROM public.process_queue p
        WHERE p.payload = OLD.id::TEXT
            AND p.ref_id = OLD.vessel_id
            AND p.channel LIKE '%_stays';
    RETURN OLD;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.stay_delete_trigger_fn() IS 'When stays is delete, stays_ext need to deleted as well.';

-- Create trigger to delete stays_ext and process_queue entries
create trigger stay_delete_trigger before
delete
    on
    api.stays for each row execute function stay_delete_trigger_fn();

COMMENT ON TRIGGER stay_delete_trigger ON api.stays IS 'BEFORE DELETE ON api.stays run function public.stay_delete_trigger_fn to delete reference and stay_ext need to deleted.';

-- Remove trigger that duplicate the OTP validation entry on insert for new account, it is handle by api.login
DROP TRIGGER new_account_otp_validation_entry ON auth.accounts;

-- DEBUG
DROP TRIGGER IF EXISTS debug_trigger ON public.process_queue;
DROP FUNCTION IF EXISTS debug_trigger_fn;
CREATE FUNCTION debug_trigger_fn() RETURNS trigger AS $debug$
    DECLARE
    BEGIN
        --RAISE NOTICE 'debug_trigger_fn [%]', NEW;
        IF NEW.channel = 'email_otp' THEN
            RAISE WARNING 'debug_trigger_fn: channel is email_otp [%]', NEW;
        END IF;
        RETURN NEW;
    END;
$debug$ LANGUAGE plpgsql;
CREATE TRIGGER debug_trigger AFTER INSERT ON public.process_queue
    FOR EACH ROW EXECUTE FUNCTION debug_trigger_fn();
-- Description
COMMENT ON TRIGGER debug_trigger ON public.process_queue IS 'Log debug information.';
DROP TRIGGER debug_trigger ON public.process_queue;

-- DROP FUNCTION api.login(text, text);
-- Update api.login function to handle user disable and email verification, update error code with invalid_email_or_password
CREATE OR REPLACE FUNCTION api.login(email text, pass text)
 RETURNS auth.jwt_token
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
    --raise insufficient_privilege using message = 'invalid user or password';
    -- HTTP/402 - to distinguish with JWT Expiration token
    RAISE sqlstate 'PT402' using message = 'invalid email or password',
            detail = 'invalid auth specification',
            hint = 'Use a valid email and password';
  end if;

  -- Gather user information
  SELECT preferences['disable'], preferences['email_valid'], user_id 
        INTO _user_disable,_email_valid,_user_id
        FROM auth.accounts a
        WHERE a.email = _email;

  -- Check if user is disable due to abuse
  IF _user_disable::BOOLEAN IS TRUE THEN
  	-- due to the raise, the insert is never committed.
    --INSERT INTO process_queue (channel, payload, stored, ref_id)
    --  VALUES ('account_disable', _email, now(), _user_id);
    RAISE sqlstate 'PT402' using message = 'Account disable, contact us',
            detail = 'Quota exceeded',
            hint = 'Upgrade your plan';
  END IF;

  -- Check if email has been verified, if not generate OTP
  IF _email_valid::BOOLEAN IS NOT True THEN
    INSERT INTO process_queue (channel, payload, stored, ref_id)
      VALUES ('email_otp', _email, now(), _user_id);
  END IF;

  -- Track IP per user to avoid abuse
  --RAISE WARNING 'api.login debug: [%],[%]', client_ip, login.email;
  IF client_ip IS NOT NULL THEN
    UPDATE auth.accounts a SET 
        preferences = jsonb_recursive_merge(a.preferences, jsonb_build_object('ip', client_ip)),
        connected_at = NOW()
        WHERE a.email = login.email;
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
$function$
;
-- Description
COMMENT ON FUNCTION api.login(text, text) IS 'Handle user login, returns a JWT token with user role and email.';

-- DROP FUNCTION public.cron_windy_fn();
-- Update cron_windy_fn to support custom user metrics
CREATE OR REPLACE FUNCTION public.cron_windy_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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
            SELECT time_bucket('5 minutes', mt.time) AS time_bucket,
                    avg(-- Outside Temperature
                        COALESCE(
                            mt.metrics->'temperature'->>'outside',
                            mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
                            mt.metrics->>'environment.outside.temperature'
                        )::FLOAT) AS temperature,
                    avg(-- Outside Pressure
                        COALESCE(
                            mt.metrics->'pressure'->>'outside',
                            mt.metrics->>(md.configuration->>'outsidePressureKey'),
                            mt.metrics->>'environment.outside.pressure'
                        )::FLOAT) AS pressure,
                    avg(-- Outside Humidity
                        COALESCE(
                            mt.metrics->'humidity'->>'outside',
                            mt.metrics->>(md.configuration->>'outsideHumidityKey'),
                            mt.metrics->>'environment.outside.relativeHumidity',
                            mt.metrics->>'environment.outside.humidity'
                        )::FLOAT) AS rh,
                    avg(-- Wind Direction True
                        COALESCE(
                            mt.metrics->'wind'->>'direction',
                            mt.metrics->>(md.configuration->>'windDirectionKey'),
                            mt.metrics->>'environment.wind.directionTrue'
                        )::FLOAT) AS winddir,
                    avg(-- Wind Speed True
                        COALESCE(
                            mt.metrics->'wind'->>'speed',
                            mt.metrics->>(md.configuration->>'windSpeedKey'),
                            mt.metrics->>'environment.wind.speedTrue',
                            mt.metrics->>'environment.wind.speedApparent'
                        )::FLOAT) AS wind,
                    max(-- Max Wind Speed True
                        COALESCE(
                            mt.metrics->'wind'->>'speed',
                            mt.metrics->>(md.configuration->>'windSpeedKey'),
                            mt.metrics->>'environment.wind.speedTrue',
                            mt.metrics->>'environment.wind.speedApparent'
                        )::FLOAT) AS gust,
                    last(latitude, mt.time) AS lat,
                    last(longitude, mt.time) AS lng
                FROM api.metrics mt
                JOIN api.metadata md ON md.vessel_id = mt.vessel_id
                WHERE md.vessel_id = windy_rec.vessel_id
                    AND mt.time >= windy_rec.last_metric::TIMESTAMPTZ
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
            -- temp from kelvin to celcuis
            -- winddir from radiant to degres
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
$function$
;
-- Description
COMMENT ON FUNCTION public.cron_windy_fn() IS 'init by pg_cron to create (or update) station and uploading observations to Windy Personal Weather Station observations';

-- DROP FUNCTION api.merge_logbook_fn(int4, int4);
-- Update merge_logbook_fn to handle more metrics and limit moorage deletion
CREATE OR REPLACE FUNCTION api.merge_logbook_fn(id_start integer, id_end integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
    DECLARE
        logbook_rec_start record;
        logbook_rec_end record;
        log_name text;
        avg_rec record;
        geo_rec record;
        geojson jsonb;
        extra_json jsonb;
        t_rec record;
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

        -- mobilitydb, add spaciotemporal sequence
        -- reduce the numbers of metrics by skipping row or aggregate time-series
        -- By default the signalk PostgSail plugin report one entry every minute.
        IF avg_rec.count_metric < 30 THEN -- if less ~20min trip we keep it all data
            t_rec := public.logbook_update_metrics_short_fn(avg_rec.count_metric, logbook_rec_start._from_time, logbook_rec_end._to_time);
        ELSIF avg_rec.count_metric < 2000 THEN -- if less ~33h trip we skip data
            t_rec := public.logbook_update_metrics_fn(avg_rec.count_metric, logbook_rec_start._from_time, logbook_rec_end._to_time);
        ELSE -- As we have too many data, we time-series aggregate data
            t_rec := public.logbook_update_metrics_timebucket_fn(avg_rec.count_metric, logbook_rec_start._from_time, logbook_rec_end._to_time);
        END IF;
        --RAISE NOTICE 'mobilitydb [%]', t_rec;
        IF t_rec.trajectory IS NULL THEN
            RAISE WARNING '-> process_logbook_queue_fn, vessel_id [%], invalid mobilitydb data [%] [%]', logbook_rec_start.vessel_id, logbook_rec_start.id, t_rec;
            RETURN;
        END IF;

        RAISE NOTICE 'Updating valid logbook entry logbook id:[%] start:[%] end:[%]', logbook_rec_start.id, logbook_rec_start._from_time, logbook_rec_end._to_time;
        UPDATE api.logbook
            SET
                duration = (logbook_rec_end._to_time::TIMESTAMPTZ - logbook_rec_start._from_time::TIMESTAMPTZ),
                avg_speed = avg_rec.avg_speed,
                max_speed = avg_rec.max_speed,
                max_wind_speed = avg_rec.max_wind_speed,
                -- Set _to metrics from end logbook
                _to = logbook_rec_end._to,
                _to_moorage_id = logbook_rec_end._to_moorage_id,
                _to_lat = logbook_rec_end._to_lat,
                _to_lng = logbook_rec_end._to_lng,
                _to_time = logbook_rec_end._to_time,
                name = log_name,
                distance = geo_rec._track_distance,
                extra = extra_json,
                notes = NULL, -- reset pre_log process
                trip = t_rec.trajectory,
                trip_cog = t_rec.courseovergroundtrue,
                trip_sog = t_rec.speedoverground,
                trip_twa = t_rec.windspeedapparent,
                trip_tws = t_rec.truewindspeed,
                trip_twd = t_rec.truewinddirection,
                trip_notes = t_rec.notes,
                trip_status = t_rec.status,
                trip_depth = t_rec.depth,
                trip_batt_charge = t_rec.stateofcharge,
                trip_batt_voltage = t_rec.voltage,
                trip_temp_water = t_rec.watertemperature,
                trip_temp_out = t_rec.outsidetemperature,
                trip_pres_out = t_rec.outsidepressure,
                trip_hum_out = t_rec.outsidehumidity,
                trip_tank_level = t_rec.tankLevel,
                trip_solar_voltage = t_rec.solarVoltage,
                trip_solar_power = t_rec.solarPower,
                trip_heading = t_rec.heading
            WHERE id = logbook_rec_start.id;

        /*** Deprecated removed column
        -- GeoJSON require track_geom field geometry linestring
        --geojson := logbook_update_geojson_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        -- GeoJSON require trip* columns
        geojson := api.logbook_update_geojson_trip_fn(logbook_rec_start.id);
        UPDATE api.logbook
            SET -- Update the data column, it should be generate dynamically on request
                -- However there is a lot of dependencies to consider for a larger cleanup
                -- badges, qgis etc... depends on track_geom
                -- many export and others functions depends on track_geojson
                track_geojson = geojson,
                track_geog = trajectory(t_rec.trajectory),
                track_geom = trajectory(t_rec.trajectory)::geometry
         --       embedding = NULL,
         --       spatial_embedding = NULL
            WHERE id = logbook_rec_start.id;

        -- GeoJSON Timelapse require track_geojson geometry point
        -- Add properties to the geojson for timelapse purpose
        PERFORM public.logbook_timelapse_geojson_fn(logbook_rec_start.id);
        ***/
        -- Update logbook mark for deletion
        UPDATE api.logbook
            SET notes = 'mark for deletion'
            WHERE id = logbook_rec_end.id;
        -- Update related stays mark for deletion
        UPDATE api.stays
            SET notes = 'mark for deletion'
            WHERE arrived = logbook_rec_start._to_time;
        -- Update related moorages mark for deletion
        -- We can't delete the stays and moorages as it might expand to other previous logs and stays
        --UPDATE api.moorages
        --    SET notes = 'mark for deletion'
        --    WHERE id = logbook_rec_start._to_moorage_id;

        -- Clean up, remove invalid logbook and stay, moorage entry
        DELETE FROM api.logbook WHERE id = logbook_rec_end.id;
        RAISE WARNING '-> merge_logbook_fn delete logbook id [%]', logbook_rec_end.id;
        DELETE FROM api.stays WHERE arrived = logbook_rec_start._to_time;
        RAISE WARNING '-> merge_logbook_fn delete stay arrived [%]', logbook_rec_start._to_time;
        -- We can't delete the stays and moorages as it might expand to other previous logs and stays
		-- Delete the moorage only if exactly one record exists with that id.
        DELETE FROM api.moorages
			WHERE id = logbook_rec_start._to_moorage_id
			  AND (
			    SELECT COUNT(*) 
			    FROM api.logbook
    			WHERE _from_moorage_id = logbook_rec_start._to_moorage_id
					OR _to_moorage_id = logbook_rec_start._to_moorage_id
			  ) = 1;
        RAISE WARNING '-> merge_logbook_fn delete moorage id [%]', logbook_rec_start._to_moorage_id;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION api.merge_logbook_fn(int4, int4) IS 'Merge 2 logbook by id, from the start of the lower log id and the end of the higher log id, update the calculate data as well (avg, geojson)';

-- Add api.counts_fn to count logbook, moorages and stays entries
CREATE OR REPLACE FUNCTION api.counts_fn()
RETURNS jsonb
LANGUAGE sql
AS $function$
    SELECT jsonb_build_object(
        'logs', (SELECT COUNT(*) FROM api.logbook),
        'moorages', (SELECT COUNT(*) FROM api.moorages),
        'stays', (SELECT COUNT(*) FROM api.stays)
    );
$function$;
-- Description
COMMENT ON FUNCTION api.counts_fn() IS 'count logbook, moorages and stays entries';

-- allow user_role to delete on api.stays_ext
GRANT DELETE ON TABLE api.stays_ext TO user_role;

-- refresh permissions
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;

-- Update version
UPDATE public.app_settings
	SET value='0.9.4'
	WHERE "name"='app.version';

\c postgres
-- Add cron job for vacuum and cleanup the public tables
INSERT INTO cron.job (schedule,command,nodename,nodeport,database,username,active,jobname)
	VALUES ('1 1 * * 0','VACUUM (FULL, VERBOSE, ANALYZE, INDEX_CLEANUP) public.process_queue,public.app_settings,public.email_templates;','/var/run/postgresql/',5432,'signalk','username',false,'cron_vacuum_public');

--UPDATE cron.job SET username = 'scheduler'; --  Update to scheduler
--UPDATE cron.job SET username = current_user WHERE jobname = 'cron_vacuum'; -- Update to superuser for vacuum permissions
--UPDATE cron.job SET username = current_user WHERE jobname = 'job_run_details_cleanup';
