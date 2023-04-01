---------------------------------------------------------------------------
-- singalk db public schema
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

CREATE SCHEMA IF NOT EXISTS public;

---------------------------------------------------------------------------
-- Functions public schema
-- process single cron event, process_[logbook|stay|moorage|badge]_queue_fn()
--

CREATE OR REPLACE FUNCTION logbook_metrics_dwithin_fn(
    IN _start text,
    IN _end text,
    IN lgn float,
    IN lat float,
    OUT count_metric numeric) AS $logbook_metrics_dwithin$
    BEGIN
        SELECT count(*) INTO count_metric
            FROM api.metrics m
            WHERE
                m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.time >= _start::TIMESTAMP WITHOUT TIME ZONE
                AND m.time <= _end::TIMESTAMP WITHOUT TIME ZONE
                AND client_id = current_setting('vessel.client_id', false)
                AND ST_DWithin(
                    Geography(ST_MakePoint(m.longitude, m.latitude)),
                    Geography(ST_MakePoint(lgn, lat)),
                    10
                );
    END;
$logbook_metrics_dwithin$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_metrics_dwithin_fn
    IS 'Check if all entries for a logbook are in stationary movement with 10 meters';

-- Update a logbook with avg data 
-- TODO using timescale function
CREATE OR REPLACE FUNCTION logbook_update_avg_fn(
    IN _id integer, 
    IN _start TEXT, 
    IN _end TEXT,
    OUT avg_speed double precision,
    OUT max_speed double precision,
    OUT max_wind_speed double precision,
    OUT count_metric double precision
) AS $logbook_update_avg$
    BEGIN
        RAISE NOTICE '-> Updating avg for logbook id=%, start:"%", end:"%"', _id, _start, _end;
        SELECT AVG(speedoverground), MAX(speedoverground), MAX(windspeedapparent), COUNT(*) INTO
                avg_speed, max_speed, max_wind_speed, count_metric
            FROM api.metrics m
            WHERE m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.time >= _start::TIMESTAMP WITHOUT TIME ZONE
                AND m.time <= _end::TIMESTAMP WITHOUT TIME ZONE
                AND client_id = current_setting('vessel.client_id', false);
        RAISE NOTICE '-> Updated avg for logbook id=%, avg_speed:%, max_speed:%, max_wind_speed:%, count:%', _id, avg_speed, max_speed, max_wind_speed, count_metric;
    END;
$logbook_update_avg$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_avg_fn
    IS 'Update logbook details with calculate average and max data, AVG(speedOverGround), MAX(speedOverGround), MAX(windspeedapparent), count_metric';

-- Create a LINESTRING for Geometry
-- Todo validate st_length unit?
-- https://postgis.net/docs/ST_Length.html
DROP FUNCTION IF EXISTS logbook_update_geom_distance_fn;
CREATE FUNCTION logbook_update_geom_distance_fn(IN _id integer, IN _start text, IN _end text,
    OUT _track_geom Geometry(LINESTRING),
    OUT _track_distance double precision
 ) AS $logbook_geo_distance$
    BEGIN
        SELECT ST_MakeLine( 
            ARRAY(
                --SELECT ST_SetSRID(ST_MakePoint(longitude,latitude),4326) as geo_point
                SELECT st_makepoint(longitude,latitude) AS geo_point
                    FROM api.metrics m
                    WHERE m.latitude IS NOT NULL
                        AND m.longitude IS NOT NULL
                        AND m.time >= _start::TIMESTAMP WITHOUT TIME ZONE
                        AND m.time <= _end::TIMESTAMP WITHOUT TIME ZONE
                        AND client_id = current_setting('vessel.client_id', false)
                    ORDER BY m.time ASC
            )
        ) INTO _track_geom;
        RAISE NOTICE '-> GIS LINESTRING %', _track_geom;
        -- SELECT ST_Length(_track_geom,false) INTO _track_distance;
        -- Meter to Nautical Mile (international) Conversion
        -- SELECT TRUNC (st_length(st_transform(track_geom,4326)::geography)::INT / 1.852) from logbook where id = 209; -- in NM
        -- SELECT (st_length(st_transform(track_geom,4326)::geography)::INT * 0.0005399568) from api.logbook where id = 1; -- in NM
        --SELECT TRUNC (ST_Length(_track_geom,false)::INT / 1.852) INTO _track_distance; -- in NM
        SELECT TRUNC (ST_Length(_track_geom,false)::INT * 0.0005399568, 4) INTO _track_distance; -- in NM
        RAISE NOTICE '-> GIS Length %', _track_distance;
    END;
$logbook_geo_distance$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_geom_distance_fn
    IS 'Update logbook details with geometry data an distance, ST_Length in Nautical Mile (international)';

-- Create GeoJSON for api consum.
CREATE FUNCTION logbook_update_geojson_fn(IN _id integer, IN _start text, IN _end text,
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
           ( select
            id,name,
            distance,
            duration,
            avg_speed,
            avg_speed,
            max_wind_speed,
            _from_time,
            notes,
            track_geom
            FROM api.logbook
            WHERE id = _id
           ) AS log;
		-- GeoJson Feature Metrics point
		SELECT
		  json_agg(ST_AsGeoJSON(t.*)::json) into metrics_geojson
		FROM (
		  ( select
		  	time,
		  	courseovergroundtrue,
		    speedoverground,
		    anglespeedapparent,
		    longitude,latitude,
		    st_makepoint(longitude,latitude) AS geo_point
		    FROM api.metrics m
		    WHERE m.latitude IS NOT NULL
		        AND m.longitude IS NOT NULL
                AND time >= _start::TIMESTAMP WITHOUT TIME ZONE
                AND time <= _end::TIMESTAMP WITHOUT TIME ZONE
                AND client_id = current_setting('vessel.client_id', false)
		    ORDER BY m.time ASC
		   )  
		) AS t;

		-- Merge jsonb
		select log_geojson::jsonb || metrics_geojson::jsonb into _map;
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

-- Update pending new logbook from process queue
DROP FUNCTION IF EXISTS process_logbook_queue_fn;
CREATE OR REPLACE FUNCTION process_logbook_queue_fn(IN _id integer) RETURNS void AS $process_logbook_queue$
    DECLARE
        logbook_rec record;
        from_name varchar;
        to_name varchar;
        log_name varchar;
        avg_rec record;
        geo_rec record;
        log_settings jsonb;
        user_settings jsonb;
        geojson jsonb;
        _invalid_time boolean;
        _invalid_interval boolean;
        _invalid_distance boolean;
        count_metric numeric;
        previous_stays_id numeric;
        current_stays_departed text;
        current_stays_id numeric;
        current_stays_active boolean;
    BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_logbook_queue_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Get the logbook record with all necesary fields exist
        SELECT * INTO logbook_rec
            FROM api.logbook
            WHERE active IS false
                AND id = _id
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        -- Ensure the query is successful
        IF logbook_rec.client_id IS NULL THEN
            RAISE WARNING '-> process_logbook_queue_fn invalid logbook %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.client_id', logbook_rec.client_id, false);
        --RAISE WARNING 'public.process_logbook_queue_fn() scheduler vessel.client_id %', current_setting('vessel.client_id', false);

        -- Check if all metrics are within 10meters base on geo loc
        count_metric := logbook_metrics_dwithin_fn(logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT, logbook_rec._from_lng::NUMERIC, logbook_rec._from_lat::NUMERIC);
        RAISE NOTICE '-> process_logbook_queue_fn logbook_metrics_dwithin_fn count:[%]', count_metric;

        -- Calculate logbook data average and geo
        -- Update logbook entry with the latest metric data and calculate data
        avg_rec := logbook_update_avg_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        geo_rec := logbook_update_geom_distance_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);

        -- Avoid/ignore/delete logbook stationary movement or time sync issue
        -- Check time start vs end
        SELECT logbook_rec._to_time::timestamp without time zone < logbook_rec._from_time::timestamp without time zone INTO _invalid_time;
        -- Is distance is less than 0.010
        SELECT geo_rec._track_distance < 0.010 INTO _invalid_distance;
        -- Is duration is less than 100sec
        SELECT (logbook_rec._to_time::timestamp without time zone - logbook_rec._from_time::timestamp without time zone) < (100::text||' secs')::interval INTO _invalid_interval;
        -- if stationnary fix data metrics,logbook,stays,moorage
        IF _invalid_time IS True OR _invalid_distance IS True
            OR _invalid_distance IS True OR count_metric = avg_rec.count_metric THEN
            RAISE WARNING '-> process_logbook_queue_fn invalid logbook data [%]', logbook_rec.id;
            -- Update metrics status to moored
            UPDATE api.metrics
                SET status = 'moored'
                WHERE time >= logbook_rec._from_time::TIMESTAMP WITHOUT TIME ZONE
                    AND time <= logbook_rec._to_time::TIMESTAMP WITHOUT TIME ZONE
                    AND client_id = current_setting('vessel.client_id', false);
            -- Update logbook
            UPDATE api.logbook
                SET notes = 'invalid logbook data, stationary need to fix metrics?'
                WHERE id = logbook_rec.id;
            -- Get related stays
            SELECT id,departed,active INTO current_stays_id,current_stays_departed,current_stays_active
                FROM api.stays s
                WHERE s.client_id = current_setting('vessel.client_id', false)
                    AND s.arrived = logbook_rec._to_time;
            -- Update related stays
            UPDATE api.stays
                SET notes = 'invalid stays data, stationary need to fix metrics?'
                WHERE client_id = current_setting('vessel.client_id', false)
                    AND arrived = logbook_rec._to_time;
            -- Find previous stays
            SELECT id INTO previous_stays_id
				FROM api.stays s
                WHERE s.client_id = current_setting('vessel.client_id', false)
                    AND s.arrived < logbook_rec._to_time
                    ORDER BY s.arrived DESC LIMIT 1;
            -- Update previous stays with the departed time from current stays
            --  and set the active state from current stays
            UPDATE api.stays
                SET departed = current_stays_departed::timestamp without time zone,
                    active = current_stays_active
                WHERE client_id = current_setting('vessel.client_id', false)
                    AND id = previous_stays_id;
            -- Clean u, remove invalid logbook and stay entry
            DELETE FROM api.logbook WHERE id = logbook_rec.id;
            RAISE WARNING '-> process_logbook_queue_fn delete invalid logbook [%]', logbook_rec.id;
            DELETE FROM api.stays WHERE id = current_stays_id;
            RAISE WARNING '-> process_logbook_queue_fn delete invalid stays [%]', current_stays_id;
            -- TODO should we substract (-1) moorages ref count or reprocess it?!?
            RETURN;
        END IF;

        -- Generate logbook name, concat _from_location and _to_locacion
        -- geo reverse _from_lng _from_lat
        -- geo reverse _to_lng _to_lat
        from_name := reverse_geocode_py_fn('nominatim', logbook_rec._from_lng::NUMERIC, logbook_rec._from_lat::NUMERIC);
        to_name := reverse_geocode_py_fn('nominatim', logbook_rec._to_lng::NUMERIC, logbook_rec._to_lat::NUMERIC);
        SELECT CONCAT(from_name, ' to ' , to_name) INTO log_name;

        RAISE NOTICE 'Updating valid logbook entry [%] [%] [%]', logbook_rec.id, logbook_rec._from_time, logbook_rec._to_time;
        UPDATE api.logbook
            SET
                duration = (logbook_rec._to_time::timestamp without time zone - logbook_rec._from_time::timestamp without time zone),
                avg_speed = avg_rec.avg_speed,
                max_speed = avg_rec.max_speed,
                max_wind_speed = avg_rec.max_wind_speed,
                _from = from_name,
                _to = to_name,
                name = log_name,
                track_geom = geo_rec._track_geom,
                distance = geo_rec._track_distance
            WHERE id = logbook_rec.id;

        -- GeoJSON require track_geom field
        geojson := logbook_update_geojson_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        UPDATE api.logbook
            SET
                track_geojson = geojson
            WHERE id = logbook_rec.id;

        -- Prepare notification, gather user settings
        SELECT json_build_object('logbook_name', log_name, 'logbook_link', logbook_rec.id) into log_settings;
        user_settings := get_user_settings_from_clientid_fn(logbook_rec.client_id::TEXT);
        SELECT user_settings::JSONB || log_settings::JSONB into user_settings;
        RAISE DEBUG '-> debug process_logbook_queue_fn get_user_settings_from_clientid_fn [%]', user_settings;
        RAISE DEBUG '-> debug process_logbook_queue_fn log_settings [%]', log_settings;
        -- Send notification
        PERFORM send_notification_fn('logbook'::TEXT, user_settings::JSONB);
    END;
$process_logbook_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_logbook_queue_fn
    IS 'Update logbook details when completed, logbook_update_avg_fn, logbook_update_geom_distance_fn, reverse_geocode_py_fn';

-- Update pending new stay from process queue
DROP FUNCTION IF EXISTS process_stay_queue_fn;
CREATE OR REPLACE FUNCTION process_stay_queue_fn(IN _id integer) RETURNS void AS $process_stay_queue$
    DECLARE
        stay_rec record;
        _name varchar;
    BEGIN
        RAISE NOTICE 'process_stay_queue_fn';
        -- If _id is valid, not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_stay_queue_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Get the stay record with all necesary fields exist
        SELECT * INTO stay_rec
            FROM api.stays
            WHERE id = _id
                AND longitude IS NOT NULL
                AND latitude IS NOT NULL;
        -- Ensure the query is successful
        IF stay_rec.client_id IS NULL THEN
            RAISE WARNING '-> process_stay_queue_fn invalid stay %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.client_id', stay_rec.client_id, false);
        -- geo reverse _lng _lat
        _name := reverse_geocode_py_fn('nominatim', stay_rec.longitude::NUMERIC, stay_rec.latitude::NUMERIC);

        RAISE NOTICE 'Updating stay entry [%]', stay_rec.id;
        UPDATE api.stays
            SET
                name = _name,
                geog = Geography(ST_MakePoint(stay_rec.longitude, stay_rec.latitude))
            WHERE id = stay_rec.id;

        -- Notification email/pushover?
    END;
$process_stay_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_stay_queue_fn
    IS 'Update stay details, reverse_geocode_py_fn';

-- Handle moorage insert or update from stays
-- todo valide geography unit
-- https://postgis.net/docs/ST_DWithin.html
DROP FUNCTION IF EXISTS process_moorage_queue_fn;
CREATE OR REPLACE FUNCTION process_moorage_queue_fn(IN _id integer) RETURNS void AS $process_moorage_queue$
    DECLARE
       	stay_rec record;
        moorage_rec record;
    BEGIN
        RAISE NOTICE 'process_moorage_queue_fn';
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_moorage_queue_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Get the stay record with all necesary fields exist
        SELECT * INTO stay_rec
            FROM api.stays
            WHERE active IS false 
                AND departed IS NOT NULL
                AND arrived IS NOT NULL
                AND longitude IS NOT NULL
                AND latitude IS NOT NULL
                AND id = _id;
        -- Ensure the query is successful
        IF stay_rec.client_id IS NULL THEN
            RAISE WARNING '-> process_moorage_queue_fn invalid stay %', _id;
            RETURN;
        END IF;

        -- Do we have an existing stay within 100m of the new moorage
	    FOR moorage_rec in 
	        SELECT
	            *
	        FROM api.moorages
	        WHERE 
	            latitude IS NOT NULL
	            AND longitude IS NOT NULL
                AND geog IS NOT NULL
	            AND ST_DWithin(
				    -- Geography(ST_MakePoint(stay_rec._lng, stay_rec._lat)),
                    stay_rec.geog,
				    -- Geography(ST_MakePoint(longitude, latitude)),
                    geog,
				    100 -- in meters ?
				  )
			ORDER BY id ASC
	    LOOP
		    -- found previous stay within 100m of the new moorage
			 IF moorage_rec.id IS NOT NULL AND moorage_rec.id > 0 THEN
			 	RAISE NOTICE 'Found previous stay within 100m of moorage %', moorage_rec;
			 	EXIT; -- exit loop
			 END IF;
	    END LOOP;

		-- if with in 100m update reference count and stay duration
		-- else insert new entry
		IF moorage_rec.id IS NOT NULL AND moorage_rec.id > 0 THEN
		 	RAISE NOTICE 'Update moorage %', moorage_rec;
		 	UPDATE api.moorages 
		 		SET 
		 			reference_count = moorage_rec.reference_count + 1,
		 			stay_duration = 
                        moorage_rec.stay_duration + 
                        (stay_rec.departed::timestamp without time zone - stay_rec.arrived::timestamp without time zone)
		 		WHERE id = moorage_rec.id;
		ELSE
			RAISE NOTICE 'Insert new moorage entry from stay %', stay_rec;
            -- Ensure the stay as a name if lat,lon
            IF stay_rec.name IS NULL AND stay_rec.longitude IS NOT NULL AND stay_rec.latitude IS NOT NULL THEN
                stay_rec.name := reverse_geocode_py_fn('nominatim', stay_rec.longitude::NUMERIC, stay_rec.latitude::NUMERIC);
            END IF;
            -- Insert new moorage from stay
	        INSERT INTO api.moorages
	                (client_id, name, stay_id, stay_code, stay_duration, reference_count, latitude, longitude, geog)
	                VALUES (
                        stay_rec.client_id,
	               		stay_rec.name,
						stay_rec.id,
						stay_rec.stay_code,
						(stay_rec.departed::timestamp without time zone - stay_rec.arrived::timestamp without time zone),
						1, -- default reference_count
						stay_rec.latitude,
						stay_rec.longitude,
                        Geography(ST_MakePoint(stay_rec.longitude, stay_rec.latitude))
                    );
		END IF;
    END;
$process_moorage_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_moorage_queue_fn
    IS 'Handle moorage insert or update from stays';

-- process new account notification
DROP FUNCTION IF EXISTS process_account_queue_fn;
CREATE OR REPLACE FUNCTION process_account_queue_fn(IN _email TEXT) RETURNS void AS $process_account_queue$
    DECLARE
       	account_rec record;
        user_settings jsonb;
        app_settings jsonb;
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
        -- set user email variable
        PERFORM set_config('user.email', account_rec.email, false);
        -- Gather user settings
        user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '"}';
        -- Send notification email, pushover
        PERFORM send_notification_fn('new_account'::TEXT, user_settings::JSONB);
        --PERFORM send_email_py_fn('user'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('user'::TEXT, user_settings::JSONB, app_settings::JSONB);
    END;
$process_account_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_account_queue_fn
    IS 'process new account notification';

-- process new account otp validation notification
DROP FUNCTION IF EXISTS process_account_otp_validation_queue_fn;
CREATE OR REPLACE FUNCTION process_account_otp_validation_queue_fn(IN _email TEXT) RETURNS void AS $process_account_otp_validation_queue$
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
        user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '", "otp_code": "' || otp_code || '"}';
        -- Send notification email, pushover
        PERFORM send_notification_fn('email_otp'::TEXT, user_settings::JSONB);
        --PERFORM send_email_py_fn('email_otp'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('user'::TEXT, user_settings::JSONB, app_settings::JSONB);
    END;
$process_account_otp_validation_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_account_otp_validation_queue_fn
    IS 'process new account otp validation notification';

-- process new event notification
DROP FUNCTION IF EXISTS process_notification_queue_fn;
CREATE OR REPLACE FUNCTION process_notification_queue_fn(IN _email TEXT, IN message_type TEXT) RETURNS void
AS $process_notification_queue$
    DECLARE
        account_rec record;
        vessel_rec record;
        user_settings jsonb := null;
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

        RAISE NOTICE '--> process_notification_queue_fn type [%] [%]', _email,message_type;
        -- set user email variable
        PERFORM set_config('user.email', account_rec.email, false);
        -- Generate user_settings user settings
        IF message_type = 'new_account' THEN
            user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '"}';
        ELSEIF message_type = 'new_vessel' THEN
            -- Gather vessel data
            SELECT * INTO vessel_rec
                FROM auth.vessels
                WHERE owner_email = _email;
            IF vessel_rec.owner_email IS NULL OR vessel_rec.owner_email = '' THEN
                RAISE EXCEPTION 'Invalid email'
                    USING HINT = 'Unknown email';
                RETURN;
            END IF;
            user_settings := '{"email": "' || vessel_rec.owner_email || '", "boat": "' || vessel_rec.name || '"}';
        ELSEIF message_type = 'email_otp' THEN
            otp_code := api.generate_otp_fn(_email);
            user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '", "otp_code": "' || otp_code || '"}';
        END IF;
        PERFORM send_notification_fn(message_type::TEXT, user_settings::JSONB);
    END;
$process_notification_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_notification_queue_fn
    IS 'process new event type notification';

-- process new vessel notification
DROP FUNCTION IF EXISTS process_vessel_queue_fn;
CREATE OR REPLACE FUNCTION process_vessel_queue_fn(IN _email TEXT) RETURNS void AS $process_vessel_queue$
    DECLARE
       	vessel_rec record;
        user_settings jsonb;
        app_settings jsonb;
    BEGIN
        IF _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        SELECT * INTO vessel_rec
            FROM auth.vessels
            WHERE owner_email = _email;
        IF vessel_rec.owner_email IS NULL OR vessel_rec.owner_email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        -- Gather email and pushover app settings
        app_settings := get_app_settings_fn();
        -- set user email variable
        PERFORM set_config('user.email', vessel_rec.owner_email, false);
        -- Gather user settings
        user_settings := '{"email": "' || vessel_rec.owner_email || '", "boat": "' || vessel_rec.name || '"}';
        --user_settings := get_user_settings_from_clientid_fn();
        -- Send notification email, pushover
        --PERFORM send_notification_fn('vessel'::TEXT, vessel_rec::RECORD);
        PERFORM send_email_py_fn('new_vessel'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('vessel'::TEXT, user_settings::JSONB, app_settings::JSONB);
    END;
$process_vessel_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_vessel_queue_fn
    IS 'process new vessel notification';

-- Get user settings details from a log entry
DROP FUNCTION IF EXISTS get_app_settings_fn;
CREATE OR REPLACE FUNCTION get_app_settings_fn (OUT app_settings jsonb)
    RETURNS jsonb
    AS $get_app_settings$
DECLARE
BEGIN
    SELECT
        jsonb_object_agg(name, value) INTO app_settings
    FROM
        public.app_settings
    WHERE
        name LIKE '%app.email%'
        OR name LIKE '%app.pushover%'
        OR name LIKE '%app.url'
        OR name LIKE '%app.telegram%';
END;
$get_app_settings$
LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.get_app_settings_fn
    IS 'get app settings details, email, pushover, telegram';

CREATE FUNCTION jsonb_key_exists(some_json jsonb, outer_key text)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN (some_json->outer_key) IS NOT NULL;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.jsonb_key_exists
    IS 'function that checks if an outer key exists in some_json and returns a boolean';

-- Send notifications
DROP FUNCTION IF EXISTS send_notification_fn;
CREATE OR REPLACE FUNCTION send_notification_fn(
    IN email_type TEXT,
    IN user_settings JSONB) RETURNS VOID
AS $send_notification$
    DECLARE
        app_settings JSONB;
        _email_notifications BOOLEAN := False;
        _phone_notifications BOOLEAN := False;
        _pushover_user_key TEXT := NULL;
        pushover_settings JSONB := NULL;
        _telegram_notifications BOOLEAN := False;
        _telegram_chat_id TEXT := NULL;
        telegram_settings JSONB := NULL;
		_email TEXT := NULL;
    BEGIN
        -- TODO input check
        --RAISE NOTICE '--> send_notification_fn type [%]', email_type;
        -- Gather notification app settings, eg: email, pushover, telegram
        app_settings := get_app_settings_fn();
        --RAISE NOTICE '--> send_notification_fn app_settings [%]', app_settings;
        --RAISE NOTICE '--> user_settings [%]', user_settings->>'email'::TEXT;

        -- Gather notifications settings and merge with user settings
        -- Send notification email
        SELECT preferences['email_notifications'] INTO _email_notifications
            FROM auth.accounts a
            WHERE a.email = user_settings->>'email'::TEXT;
        RAISE NOTICE '--> send_notification_fn email_notifications [%]', _email_notifications;
        -- If email server app settings set and if email user settings set
        IF app_settings['app.email_server'] IS NOT NULL AND _email_notifications IS True THEN
            PERFORM send_email_py_fn(email_type::TEXT, user_settings::JSONB, app_settings::JSONB);
        END IF;

        -- Send notification pushover
        SELECT preferences['phone_notifications'],preferences->>'pushover_user_key' INTO _phone_notifications,_pushover_user_key
            FROM auth.accounts a
            WHERE a.email = user_settings->>'email'::TEXT;
        RAISE NOTICE '--> send_notification_fn phone_notifications [%]', _phone_notifications;
        -- If pushover app settings set and if pushover user settings set
        IF app_settings['app.pushover_app_token'] IS NOT NULL AND _phone_notifications IS True THEN
            SELECT json_build_object('pushover_user_key', _pushover_user_key) into pushover_settings;
            SELECT user_settings::JSONB || pushover_settings::JSONB into user_settings;
            --RAISE NOTICE '--> send_notification_fn user_settings + pushover [%]', user_settings;
            PERFORM send_pushover_py_fn(email_type::TEXT, user_settings::JSONB, app_settings::JSONB);
        END IF;

        -- Send notification telegram
        SELECT (preferences->'telegram'->'from'->'id') IS NOT NULL,preferences['telegram']['from']['id'] INTO _telegram_notifications,_telegram_chat_id
            FROM auth.accounts a
            WHERE a.email = user_settings->>'email'::TEXT;
        RAISE NOTICE '--> send_notification_fn telegram_notifications [%]', _telegram_notifications;
        -- If telegram app settings set and if telegram user settings set
        IF app_settings['app.telegram_bot_token'] IS NOT NULL AND _telegram_notifications IS True THEN
            SELECT json_build_object('telegram_chat_id', _telegram_chat_id) into telegram_settings;
            SELECT user_settings::JSONB || telegram_settings::JSONB into user_settings;
            --RAISE NOTICE '--> send_notification_fn user_settings + telegram [%]', user_settings;
            PERFORM send_telegram_py_fn(email_type::TEXT, user_settings::JSONB, app_settings::JSONB);
        END IF;
    END;
$send_notification$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.send_notification_fn
    IS 'TODO Send notifications';

DROP FUNCTION IF EXISTS get_user_settings_from_clientid_fn;
CREATE OR REPLACE FUNCTION get_user_settings_from_clientid_fn(
    IN clientid TEXT,
    OUT user_settings JSONB
    ) RETURNS JSONB
AS $get_user_settings_from_clientid$
    DECLARE
    BEGIN
        -- If client_id is not NULL
        IF clientid IS NULL OR clientid = '' THEN
            RAISE WARNING '-> get_user_settings_from_clientid_fn invalid input %', clientid;
        END IF;
        SELECT 
            json_build_object( 
                    'boat' , v.name,
                    'recipient', a.first,
                    'email', v.owner_email,
                    'settings', a.preferences,
                    'pushover_key', a.preferences->'pushover_key',
                    'badges', a.preferences->'badges'
                    ) INTO user_settings
            FROM auth.accounts a, auth.vessels v, api.metadata m
            WHERE m.mmsi = v.mmsi
                AND m.client_id = clientid
                AND lower(a.email) = lower(v.owner_email);
    END;
$get_user_settings_from_clientid$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.get_user_settings_from_clientid_fn
    IS 'get user settings details from a clientid, initiate for notifications';

DROP FUNCTION IF EXISTS set_vessel_settings_from_clientid_fn;
CREATE OR REPLACE FUNCTION set_vessel_settings_from_clientid_fn(
    IN clientid TEXT,
    OUT vessel_settings JSONB
    ) RETURNS JSONB
AS $set_vessel_settings_from_clientid$
    DECLARE
    BEGIN
        -- If client_id is not NULL
        IF clientid IS NULL OR clientid = '' THEN
            RAISE WARNING '-> set_vessel_settings_from_clientid_fn invalid input %', clientid;
        END IF;
        SELECT
            json_build_object(
                    'name' , v.name,
                    'mmsi', v.mmsi,
                    'client_id', m.client_id
                    ) INTO vessel_settings
            FROM auth.accounts a, auth.vessels v, api.metadata m
            WHERE m.mmsi = v.mmsi
                AND m.client_id = clientid;
        PERFORM set_config('vessel.mmsi', vessel_rec.mmsi, false);
        PERFORM set_config('vessel.name', vessel_rec.name, false);
        PERFORM set_config('vessel.client_id', vessel_rec.client_id, false);
    END;
$set_vessel_settings_from_clientid$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.set_vessel_settings_from_clientid_fn
    IS 'set_vessel settings details from a clientid, initiate for process queue functions';

create function public.process_badge_queue_fn() RETURNS void AS $process_badge_queue$
declare
    badge_rec record;
    badges_arr record;
begin
    SELECT json_array_elements_text((a.preferences->'badges')::json) from auth.accounts a;
    FOR badge_rec in 
        SELECT
            name
        FROM badges
    LOOP
        -- found previous stay within 100m of the new moorage
            IF moorage_rec.id IS NOT NULL AND moorage_rec.id > 0 THEN
            RAISE NOTICE 'Found previous stay within 100m of moorage %', moorage_rec;
            EXIT; -- exit loop
            END IF;
    END LOOP;
    -- Helmsman
    -- select count(l.id) api.logbook l where count(l.id) = 1;
    -- Wake Maker
    -- select max(l.max_wind_speed) api.logbook l where l.max_wind_speed >= 15;
    -- Explorer
    -- select sum(m.stay_duration) api.stays s where home_flag is false;
    -- Mooring Pro
    -- select sum(m.stay_duration) api.stays s where stay_code = 3;
    -- Anchormaster
    -- select sum(m.stay_duration) api.stays s where stay_code = 2;
    -- Traveler
    -- todo country to country.
    -- Stormtrooper
    -- select max(l.max_wind_speed) api.logbook l where l.max_wind_speed >= 30;
    -- Club Alaska
    -- todo country zone
    -- Tropical Traveler
    -- todo country zone
    -- Aloha Award
    -- todo pacific zone
    -- TODO the sea is big and the world is not limited to the US
END
$process_badge_queue$ language plpgsql;

---------------------------------------------------------------------------
-- TODO add alert monitoring for Battery

---------------------------------------------------------------------------
-- PostgREST API pre-request check
-- TODO db-pre-request = "public.check_jwt"
-- Prevent unregister user or unregister vessel access
CREATE OR REPLACE FUNCTION public.check_jwt() RETURNS void AS $$
DECLARE
  _role name;
  _email text;
  _mmsi name;
  _path name;
  _clientid text;
  _vid text;
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
  IF _role = 'user_role' THEN
    -- Check the user exist in the accounts table
    SELECT * INTO account_rec
        FROM auth.accounts
        WHERE auth.accounts.email = _email;
    IF account_rec.email IS NULL THEN
        RAISE EXCEPTION 'Invalid user'
            USING HINT = 'Unknown user or password';
    END IF;
    --RAISE WARNING 'req path %', current_setting('request.path', true);
    -- Function allow without defined vessel
    -- openapi doc, user settings, otp code and vessel registration
    SELECT current_setting('request.path', true) into _path;
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
    -- ensure vessel is connected
    SELECT coalesce(m.client_id, null) INTO _clientid
        FROM auth.vessels v, api.metadata m
        WHERE
            m.vessel_id = current_setting('vessel.id')
            AND m.vessel_id = v.vessel_id
            AND v.owner_email =_email;
    -- Set session variables
    PERFORM set_config('vessel.client_id', _clientid, false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.client_id [%]', current_setting('vessel.client_id', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.id [%]', current_setting('vessel.id', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.name [%]', current_setting('vessel.name', false);
  ELSIF _role = 'vessel_role' THEN
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
    -- TODO add client_id
    --PERFORM set_config('vessel.client_id', vessel_rec.client_id, false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.mmsi %', current_setting('vessel.mmsi', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.name %', current_setting('vessel.name', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.client_id %', current_setting('vessel.client_id', false);
  ELSIF _role <> 'api_anonymous' THEN
    RAISE EXCEPTION 'Invalid role'
      USING HINT = 'Stop being so evil and maybe you can log in';
  END IF;
END
$$ language plpgsql security definer;

---------------------------------------------------------------------------
-- Function to trigger cron_jobs using API for tests.
-- Todo limit access and permision
-- Run con jobs
CREATE OR REPLACE FUNCTION public.run_cron_jobs() RETURNS void AS $$
BEGIN
    -- In correct order
    perform public.cron_process_new_notification_fn();
    perform public.cron_process_monitor_online_fn();
    perform public.cron_process_new_logbook_fn();
    perform public.cron_process_new_stay_fn();
    perform public.cron_process_new_moorage_fn();
    perform public.cron_process_monitor_offline_fn();
END
$$ language plpgsql security definer;
