---------------------------------------------------------------------------
-- singalk db public schema
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

CREATE SCHEMA IF NOT EXISTS public;
COMMENT ON SCHEMA public IS 'backend functions';

---------------------------------------------------------------------------
-- python reverse_geocode
--
-- https://github.com/CartoDB/labs-postgresql/blob/master/workshop/plpython.md
--
CREATE TABLE IF NOT EXISTS geocoders(
    name TEXT UNIQUE, 
    url TEXT, 
    reverse_url TEXT
);
-- Description
COMMENT ON TABLE
    public.geocoders
    IS 'geo service nominatim url';

INSERT INTO geocoders VALUES
('nominatim',
    NULL,
    'https://nominatim.openstreetmap.org/reverse');

DROP FUNCTION IF EXISTS reverse_geocode_py_fn; 
CREATE OR REPLACE FUNCTION reverse_geocode_py_fn(IN geocoder TEXT, IN lon NUMERIC, IN lat NUMERIC,
    OUT geo_name TEXT)
AS $reverse_geocode_py$
    import requests

    # Use the shared cache to avoid preparing the geocoder metadata
    if geocoder in SD:
        plan = SD[geocoder]
    # A prepared statement from Python
    else:
        plan = plpy.prepare("SELECT reverse_url AS url FROM geocoders WHERE name = $1", ["text"])
        SD[geocoder] = plan

    # Execute the statement with the geocoder param and limit to 1 result
    rv = plpy.execute(plan, [geocoder], 1)
    url = rv[0]['url']

    # Make the request to the geocoder API
    payload = {"lon": lon, "lat": lat, "format": "jsonv2", "zoom": 18}
    r = requests.get(url, params=payload)

    # Return the full address or nothing if not found
    if r.status_code == 200 and "name" in r.json():
      return r.json()["name"]
    else:
      plpy.error('Failed to received a geo full address %s', r.json())
      return 'unknow'
$reverse_geocode_py$ LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION 
    public.reverse_geocode_py_fn
    IS 'query reverse geo service to return location name';

---------------------------------------------------------------------------
-- python template email/pushover
--
CREATE TABLE IF NOT EXISTS email_templates(
    name TEXT UNIQUE, 
    email_subject TEXT,
    email_content TEXT,
    pushover_title TEXT,
    pushover_message TEXT
);
-- Description
COMMENT ON TABLE
    public.email_templates
    IS 'email/message templates for notifications';

-- with escape value, eg: E'A\nB\r\nC'
-- https://stackoverflow.com/questions/26638615/insert-line-break-in-postgresql-when-updating-text-field
-- TODO Update notification subject for log entry to 'logbook #NB ...'
INSERT INTO email_templates VALUES
('logbook',
    'New Logbook Entry',
    E'Hello __RECIPIENT__,\n\nWe just wanted to let you know that you have a new entry on openplotter.cloud: "__LOGBOOK_NAME__"\r\n\r\nSee more details at __APP_URL__/log/__LOGBOOK_LINK__\n\nHappy sailing!\nThe PostgSail Team',
    'New Logbook Entry',
    E'We just wanted to let you know that you have a new entry on openplotter.cloud: "__LOGBOOK_NAME__"\r\n\r\nSee more details at __APP_URL__/log/__LOGBOOK_LINK__\n\nHappy sailing!\nThe PostgSail Team'),
('user',
    'Welcome',
    E'Hello __RECIPIENT__,\nCongratulations!\nYou successfully created an account.\nKeep in mind to register your vessel.\nHappy sailing!',
    'Welcome',
    E'Hi!\nYou successfully created an account\nKeep in mind to register your vessel.\nHappy sailing!'),
('vessel',
    'New vessel',
    E'Hi!\nHow are you?\n__BOAT__ is now linked to your account.',
    'New vessel',
    E'Hi!\nHow are you?\n__BOAT__ is now linked to your account.'),
('monitor_offline',
    'Offline',
    E'__BOAT__ has been offline for more than an hour\r\nFind more details at __APP_URL__/boats/\n',
    'Offline',
    E'__BOAT__ has been offline for more than an hour\r\nFind more details at __APP_URL__/boats/\n'),
('monitor_online',
    'Online',
    E'__BOAT__ just came online\nFind more details at __APP_URL__/boats/\n',
    'Online',
    E'__BOAT__ just came online\nFind more details at __APP_URL__/boats/\n'),
('badge',
    'New Badge!',
    E'Hello __RECIPIENT__,\nCongratulations! You have just unlocked a new badge: __BADGE_NAME__\nSee more details at __APP_URL__/badges\nHappy sailing!\nThe PostgSail Team',
    'New Badge!',
    E'Congratulations!\nYou have just unlocked a new badge: __BADGE_NAME__\nSee more details at __APP_URL__/badges\nHappy sailing!\nThe PostgSail Team');

---------------------------------------------------------------------------
-- python send email
--
-- TODO read table from python or send email data as params?
-- https://www.programcreek.com/python/example/3684/email.utils.formatdate
DROP FUNCTION IF EXISTS send_email_py_fn;
CREATE OR REPLACE FUNCTION send_email_py_fn(IN email_type TEXT, IN _user JSONB, IN app JSONB) RETURNS void
AS $send_email_py$
    # Import smtplib for the actual sending function
    import smtplib
    
    # Import the email modules we need
    #from email.message import EmailMessage
    from email.utils import formatdate,make_msgid
    from email.mime.text import MIMEText
    
    # Use the shared cache to avoid preparing the email metadata
    if email_type in SD:
        plan = SD[email_type]
    # A prepared statement from Python
    else:
        plan = plpy.prepare("SELECT * FROM email_templates WHERE name = $1", ["text"])
        SD[email_type] = plan

    # Execute the statement with the email_type param and limit to 1 result
    rv = plpy.execute(plan, [email_type], 1)
    email_subject = rv[0]['email_subject']
    email_content = rv[0]['email_content']

    # Replace fields using input jsonb obj
    if not _user or not app:
        plpy.notice('send_email_py_fn Parameters [{}] [{}]'.format(_user, app))
        plpy.error('Error missing parameters')
        return None
    if 'logbook_name' in _user and _user['logbook_name']:
        email_content = email_content.replace('__LOGBOOK_NAME__', _user['logbook_name'])
    if 'logbook_link' in _user and _user['logbook_link']:
        email_content = email_content.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'recipient' in _user and _user['recipient']:
        email_content = email_content.replace('__RECIPIENT__', _user['recipient'])
    if 'boat' in _user and _user['boat']:
        email_content = email_content.replace('__BOAT__', _user['boat'])
    if 'badge' in _user and _user['badge']:
        email_content = email_content.replace('__BADGE_NAME__', _user['badge'])

    if 'app.url' in app and app['app.url']:
        email_content = email_content.replace('__APP_URL__', app['app.url'])

    email_from = 'root@localhost'
    if 'app.email_from' in app and app['app.email_from']:
        email_from = app['app.email_from']
    #plpy.notice('Sending email from [{}] [{}]'.format(email_from, app['app.email_from']))

    email_to = 'root@localhost'
    if 'email' in _user and _user['email']:
        email_to = _user['email']
        #plpy.notice('Sending email to [{}] [{}]'.format(email_to, _user['email']))
    else:
        plpy.error('Error email to')
        return None

    msg = MIMEText(email_content, 'plain', 'utf-8')
    msg["Subject"] = email_subject
    msg["From"] = email_from
    msg["To"] = email_to
    msg["Date"] = formatdate()
    msg["Message-ID"] = make_msgid()

    server_smtp = 'localhost'
    if 'app.email_server' in app and app['app.email_server']:
        server_smtp = app['app.email_server']

    # Send the message via our own SMTP server.
    try:
        # send your message with credentials specified above
        with smtplib.SMTP(server_smtp, 25) as server:
            if 'app.email_user' in app and app['app.email_user'] \
                and 'app.email_pass' in app and app['app.email_pass']:
                server.starttls()
                server.login(app['app.email_user'], app['app.email_pass'])
            #server.send_message(msg)
            server.sendmail(msg["To"], msg["From"], msg.as_string())
            server.quit()
        # tell the script to report if your message was sent or which errors need to be fixed
        plpy.notice('Sent email successfully to [{}] [{}]'.format(msg["To"], msg["Subject"]))
        return None
    except OSError as error :
        plpy.error(error)
    except smtplib.SMTPConnectError:
        plpy.error('Failed to connect to the server. Bad connection settings?')
    except smtplib.SMTPServerDisconnected:
        plpy.error('Failed to connect to the server. Wrong user/password?')
    except smtplib.SMTPException as e:
        plpy.error('SMTP error occurred: ' + str(e))
$send_email_py$ TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.send_email_py_fn
    IS 'Send email notification using plpython3u';

---------------------------------------------------------------------------
-- python send pushover
--
-- TODO read app and user key from table?
-- https://pushover.net/
DROP FUNCTION IF EXISTS send_pushover_py_fn;
CREATE OR REPLACE FUNCTION send_pushover_py_fn(IN message_type TEXT, IN _user JSONB, IN app JSONB) RETURNS void
AS $send_pushover_py$
    import requests

    # Use the shared cache to avoid preparing the email metadata
    if message_type in SD:
        plan = SD[message_type]
    # A prepared statement from Python
    else:
        plan = plpy.prepare("SELECT * FROM email_templates WHERE name = $1", ["text"])
        SD[message_type] = plan

    # Execute the statement with the message_type param and limit to 1 result
    rv = plpy.execute(plan, [message_type], 1)
    pushover_title = rv[0]['pushover_title']
    pushover_message = rv[0]['pushover_message']

    # Replace fields using input jsonb obj
    if 'logbook_name' in _user and _user['logbook_name']:
        pushover_message = pushover_message.replace('__LOGBOOK_NAME__', _user['logbook_name'])
    if 'logbook_link' in _user and _user['logbook_link']:
        pushover_message = pushover_message.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'recipient' in _user and _user['recipient']:
        pushover_message = pushover_message.replace('__RECIPIENT__', _user['recipient'])
    if 'boat' in _user and _user['boat']:
        pushover_message = pushover_message.replace('__BOAT__', _user['boat'])
    if 'badge' in _user and _user['badge']:
        pushover_message = pushover_message.replace('__BADGE_NAME__', _user['badge'])

    if 'app.url' in app and app['app.url']:
        pushover_message = pushover_message.replace('__APP_URL__', app['app.url'])

    pushover_token = None
    if 'app.pushover_token' in app and app['app.pushover_token']:
        pushover_token = app['app.pushover_token']
    else:
        plpy.error('Error no pushover token defined, check app settings')
        return None
    pushover_user = None
    if 'pushover_key' in _user and _user['pushover_key']:
        pushover_user = _user['pushover_key']
    else:
        plpy.error('Error no pushover user token defined, check user settings')
        return None

    # requests
    r = requests.post("https://api.pushover.net/1/messages.json", data = {
        "token": pushover_token,
        "user": pushover_user,
        "title": pushover_title,
        "message": pushover_message
    })

    #print(r.text)
    # Return the full address or None if not found
    plpy.notice('Sent pushover successfully to [{}] [{}]'.format(r.text, r.status_code))
    if r.status_code == 200:
        plpy.notice('Sent pushover successfully to [{}] [{}] [{}]'.format("__USER__", pushover_title, r.text))
    else:
        plpy.error('Failed to send pushover')
    return None
$send_pushover_py$ TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.send_pushover_py_fn
    IS 'Send pushover notification using plpython3u';

---------------------------------------------------------------------------
-- Functions public schema
--

-- Update a logbook with avg data 
-- TODO using timescale function
CREATE OR REPLACE FUNCTION logbook_update_avg_fn(
    IN _id integer, 
    IN _start TEXT, 
    IN _end TEXT,
    OUT avg_speed double precision,
    OUT max_speed double precision,
    OUT max_wind_speed double precision
) AS $logbook_update_avg$
    BEGIN
        RAISE NOTICE '-> Updating avg for logbook id=%, start: "%", end: "%"', _id, _start, _end;
        SELECT AVG(speedOverGround), MAX(speedOverGround), MAX(windspeedapparent) INTO
                avg_speed, max_speed, max_wind_speed
            FROM api.metrics 
            WHERE time >= _start::TIMESTAMP WITHOUT TIME ZONE
                    AND time <= _end::TIMESTAMP WITHOUT TIME ZONE
                    AND client_id = current_setting('vessel.client_id', false);
        RAISE NOTICE '-> Updated avg for logbook id=%, avg_speed:%, max_speed:%, max_wind_speed:%', _id, avg_speed, max_speed, max_wind_speed;
    END;
$logbook_update_avg$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_avg_fn
    IS 'Update logbook details with calculate average and max data, AVG(speedOverGround), MAX(speedOverGround), MAX(windspeedapparent)';

-- Create a LINESTRING for Geometry
-- Todo validate st_length unit?
-- https://postgis.net/docs/ST_Length.html
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
        -- SELECT TRUNC (st_length(st_transform(track_geom,4326)::geography)::INT / 1.852) from logbook where id = 209; -- in NM
        SELECT TRUNC (ST_Length(_track_geom,false)::INT / 1.852) INTO _track_distance; -- in NM
        RAISE NOTICE '-> GIS Length %', _track_distance;
    END;
$logbook_geo_distance$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_geom_distance_fn
    IS 'Update logbook details with geometry data an distance, ST_Length';

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
		  ST_AsGeoJSON(l.*) into log_geojson
		FROM
		  api.logbook l
		WHERE l.id = _id;
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
		    ORDER BY m.time asc
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
        app_settings jsonb;
        vessel_settings jsonb;
        geojson jsonb;
    BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_logbook_queue_fn invalid input %', _id;
        END IF;
        SELECT * INTO logbook_rec
            FROM api.logbook
            WHERE active IS false
                AND id = _id;

        PERFORM set_config('vessel.client_id', logbook_rec.client_id, false);
        RAISE WARNING 'public.process_logbook_queue_fn() scheduler vessel.client_id %', current_setting('vessel.client_id', false);

        -- geo reverse _from_lng _from_lat
        -- geo reverse _to_lng _to_lat
        from_name := reverse_geocode_py_fn('nominatim', logbook_rec._from_lng::NUMERIC, logbook_rec._from_lat::NUMERIC);
        to_name := reverse_geocode_py_fn('nominatim', logbook_rec._to_lng::NUMERIC, logbook_rec._to_lat::NUMERIC);
        SELECT CONCAT(from_name, ' to ' , to_name) INTO log_name;
        -- SELECT CONCAT("_from" , ' to ' ,"_to") from api.logbook where id = 1;

        -- Generate logbook name, concat _from_location and to _to_locacion 
        -- Update logbook entry with the latest metric data and calculate data
        avg_rec := logbook_update_avg_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        geo_rec := logbook_update_geom_distance_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        --geojson := logbook_update_geojson_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        -- todo check on time start vs end
        RAISE NOTICE 'Updating logbook entry [%] [%] [%]', logbook_rec.id, logbook_rec._from_time, logbook_rec._to_time;
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

        -- GeoJSON
        geojson := logbook_update_geojson_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        UPDATE api.logbook
            SET
               track_geojson = geojson
            WHERE id = logbook_rec.id;
        -- Gather email and pushover app settings
        app_settings := get_app_settings_fn();
        -- Gather user settings
        SELECT json_build_object('logbook_name', log_name,  'logbook_link', logbook_rec.id) into log_settings;
        user_settings := get_user_settings_from_clientid_fn(logbook_rec.client_id::TEXT);
        SELECT user_settings::JSONB || log_settings::JSONB into user_settings;
        RAISE DEBUG '-> debug process_logbook_queue_fn get_user_settings_from_clientid_fn [%]', user_settings;
        --user_settings := get_user_settings_from_log_fn(logbook_rec::RECORD);
        --user_settings := '{"logbook_name": "' || log_name || '"}, "{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '}';
        --user_settings := '{"logbook_name": "' || log_name || '"}';
        -- Send notification email, pushover
        --PERFORM send_notification('logbook'::TEXT, logbook_rec::RECORD);
        PERFORM send_email_py_fn('logbook'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('logbook'::TEXT, user_settings::JSONB, app_settings::JSONB);
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
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_stay_queue_fn invalid input %', _id;
        END IF;
        SELECT * INTO stay_rec
            FROM api.stays
            WHERE id = _id;

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
        END IF;
        SELECT * INTO stay_rec
            FROM api.stays
            WHERE active IS false 
                AND departed IS NOT NULL
                AND id = _id;

	    FOR moorage_rec in 
	        SELECT
	            *
	        FROM api.moorages
	        WHERE 
	            latitude IS NOT NULL
	            AND longitude IS NOT NULL
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
		else
			RAISE NOTICE 'Insert new moorage entry from stay %', stay_rec;
            -- Ensure the stay as a name
            IF stay_rec.name IS NULL THEN
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
                USING HINT = 'Unkown email';
            RETURN;
        END IF;
        SELECT * INTO account_rec
            FROM auth.accounts
            WHERE email = _email;
        IF account_rec.email IS NULL OR account_rec.email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unkown email';
            RETURN;
        END IF;
        -- Gather email and pushover app settings
        app_settings := get_app_settings_fn();
        -- Gather user settings
        user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '"}';
        -- Send notification email, pushover
        --PERFORM send_notification_fn('user'::TEXT, account_rec::RECORD);
        PERFORM send_email_py_fn('user'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('user'::TEXT, user_settings::JSONB, app_settings::JSONB);
    END;
$process_account_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_account_queue_fn
    IS 'process new account notification';

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
                USING HINT = 'Unkown email';
            RETURN;
        END IF;
        SELECT * INTO vessel_rec
            FROM auth.vessels
            WHERE owner_email = _email;
        IF vessel_rec.owner_email IS NULL OR vessel_rec.owner_email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unkown email';
            RETURN;
        END IF;
        -- Gather user_settings from 
        -- if notification email
        -- -- Send email
        --
        -- Gather email and pushover app settings
        app_settings := get_app_settings_fn();
        -- Gather user settings
        user_settings := '{"email": "' || vessel_rec.owner_email || '", "boat": "' || vessel_rec.name || '"}';
        --user_settings := get_user_settings_from_clientid_fn();
        -- Send notification email, pushover
        --PERFORM send_notification_fn('vessel'::TEXT, vessel_rec::RECORD);
        PERFORM send_email_py_fn('vessel'::TEXT, user_settings::JSONB, app_settings::JSONB);
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
        OR name LIKE '%app.url';
END;
$get_app_settings$
LANGUAGE plpgsql;

-- Description
COMMENT ON FUNCTION
    public.get_app_settings_fn
    IS 'get app settings details, email, pushover';

-- Send notifications
DROP FUNCTION IF EXISTS send_notification_fn;
CREATE OR REPLACE FUNCTION send_notification_fn(
    IN email_type TEXT,
    IN user_settings JSONB) RETURNS VOID
AS $send_notification$
    DECLARE
        app_settings JSONB;
    BEGIN
        -- Gather email and pushover app settings
        app_settings := get_app_settings_fn();
        -- Gather user settings
        --user_settings := '{"email": "' || vessel_rec.owner_email || '", "boat": "' || vessel_rec.name || '}';
        --user_settings := get_user_settings_from_clientid_fn();
        --user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '}';
        --user_settings := get_user_settings_from_metadata_fn();
        --user_settings := '{"logbook_name": "' || log_name || '"}';
        --user_settings := get_user_settings_from_log_fn();
        -- Send notification email
        PERFORM send_email_py_fn(email_type::TEXT, user_settings::JSONB, app_settings::JSONB);
        -- Send notification pushover
        --PERFORM send_pushover_py_fn(email_type::TEXT, user_settings::JSONB, app_settings::JSONB);
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
                    'email', v.owner_email ,
                    'settings', a.preferences,
                    'pushover_key', a.preferences->'pushover_key',
                    'badges', a.preferences->'badges'
                    ) INTO user_settings
            FROM auth.accounts a, auth.vessels v, api.metadata m
            WHERE m.mmsi = v.mmsi
                AND m.client_id = clientid;
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


---------------------------------------------------------------------------
-- Queue handling
--
-- https://gist.github.com/kissgyorgy/beccba1291de962702ea9c237a900c79
-- https://www.depesz.com/2012/06/13/how-to-send-mail-from-database/

-- Listen/Notify way
--create function new_logbook_entry() returns trigger as $$
--begin
--    perform pg_notify('new_logbook_entry', NEW.id::text);
--    return NEW;
--END;
--$$ language plpgsql;

-- table way
CREATE TABLE IF NOT EXISTS public.process_queue (
    id SERIAL PRIMARY KEY,
    channel TEXT NOT NULL,
    payload TEXT NOT NULL,
    stored timestamptz NOT NULL,
    processed timestamptz
);
COMMENT ON TABLE
    public.process_queue
    IS 'process queue for async job';

CREATE INDEX ON public.process_queue (channel);
CREATE INDEX ON public.process_queue (processed);

create function new_account_entry_fn() returns trigger as $new_account_entry$
begin
    insert into process_queue (channel, payload, stored) values ('new_account', NEW.email, now());
    return NEW;
END;
$new_account_entry$ language plpgsql;

create function new_vessel_entry_fn() returns trigger as $new_vessel_entry$
begin
    insert into process_queue (channel, payload, stored) values ('new_vessel', NEW.owner_email, now());
    return NEW;
END;
$new_vessel_entry$ language plpgsql;

---------------------------------------------------------------------------
-- App settings
-- https://dba.stackexchange.com/questions/27296/storing-application-settings-with-different-datatypes#27297
-- https://stackoverflow.com/questions/6893780/how-to-store-site-wide-settings-in-a-database
-- http://cvs.savannah.gnu.org/viewvc/*checkout*/gnumed/gnumed/gnumed/server/sql/gmconfiguration.sql

CREATE TABLE IF NOT EXISTS public.app_settings (
  name TEXT NOT NULL UNIQUE,
  value TEXT NOT NULL
);
COMMENT ON TABLE public.app_settings IS 'application settings';
COMMENT ON COLUMN public.app_settings.name IS 'application settings name key';
COMMENT ON COLUMN public.app_settings.value IS 'application settings value';

---------------------------------------------------------------------------
-- Badges descriptions
-- TODO add contiditions
--
CREATE TABLE IF NOT EXISTS badges(
    name TEXT UNIQUE, 
    description TEXT
);
-- Description
COMMENT ON TABLE
    public.badges
    IS 'Badges descriptions';

INSERT INTO badges VALUES
('Helmsman',
    'Nice work logging your first sail! You are officially a helmsman now!'),
('Wake Maker',
    'Yowzers! Welcome to the 15 knot+ club ya speed demon skipper!'),
('Explorer',
    'It looks like home is where the helm is. Cheers to 10 days away from home port!'),
('Mooring Pro',
    'It takes a lot of skill to "thread that floating needle" but seems like you have mastered mooring with 10 nights on buoy!'),
('Anchormaster',
    'Hook, line and sinker, you have this anchoring thing down! 25 days on the hook for you!'),
('Traveler',
    'Who needs to fly when one can sail! You are an international sailor. À votre santé!'),
('Stormtrooper',
    'Just like the elite defenders of the Empire, here you are, our braving your own hydro-empire in windspeeds above 30kts. Nice work trooper! '),
('Club Alaska',
    'Home to the bears, glaciers, midnight sun and high adventure. Welcome to the Club Alaska Captain!'),
('Tropical Traveler',
    'Look at you with your suntan, tropical drink and southern latitude!'), 
('Aloha Award',
    'Ticking off over 2300 NM across the great blue Pacific makes you the rare recipient of the Aloha Award. Well done and Aloha sailor!'), 
('Tyee',
    'You made it to the Tyee Outstation, the friendliest dock in Pacific Northwest!'), 
-- TODO the sea is big and the world is not limited to the US
('Mediterranean Traveler',
    'You made it trought the Mediterranean!');

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
-- TODO db-pre-request = "public.check_jwt"
-- Prevent unregister user or unregister vessel access
CREATE OR REPLACE FUNCTION public.check_jwt() RETURNS void AS $$
DECLARE
  _role name;
  _email name;
  _mmsi name;
  _path name;
  account_rec record;
  vessel_rec record;
BEGIN
  RAISE WARNING 'jwt %', current_setting('request.jwt.claims', true);
  SELECT current_setting('request.jwt.claims', true)::json->>'email' INTO _email;
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
            USING HINT = 'Unkown user or password';
    END IF;
    RAISE WARNING 'req path %', current_setting('request.path', true);
    -- Function allow without defined vessel
    -- openapi doc, user settings and vessel registration
    SELECT current_setting('request.path', true) into _path;
    IF _path = '/rpc/settings_fn'
        OR _path = '/rpc/register_vessel'
        OR _path = '/' THEN
        RETURN;
    END IF;
    -- Check a vessel and user exist
    SELECT * INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = _email
            AND auth.accounts.email = _email;
    -- check if boat exist yet?
    IF vessel_rec.owner_email IS NULL THEN
        -- Return http status code 551 with message
		RAISE sqlstate 'PT551' using
		  message = 'Vessel Required',
		  detail = 'Invalid vessel',
		  hint = 'Unkown vessel';
        --RETURN; -- ignore if not exist
    END IF;
    IF vessel_rec.mmsi IS NULL THEN
        RAISE EXCEPTION 'Invalid vessel'
            USING HINT = 'Unkown vessel mmsi';
    END IF;
    PERFORM set_config('vessel.mmsi', vessel_rec.mmsi, false);
    PERFORM set_config('vessel.name', vessel_rec.name, false);
    RAISE WARNING 'public.check_jwt() user_role vessel.mmsi %', current_setting('vessel.mmsi', false);
    RAISE WARNING 'public.check_jwt() user_role vessel.name %', current_setting('vessel.name', false);
  ELSIF _role = 'vessel_role' THEN
    -- Check the vessel and user exist
    SELECT * INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = _email
            AND auth.accounts.email = _email;
    IF vessel_rec.owner_email IS NULL THEN
        RAISE EXCEPTION 'Invalid vessel'
            USING HINT = 'Unkown vessel owner_email';
    END IF;
    SELECT current_setting('request.jwt.claims', true)::json->>'mmsi' INTO _mmsi;
    IF vessel_rec.mmsi IS NULL OR vessel_rec.mmsi <> _mmsi THEN
        RAISE EXCEPTION 'Invalid vessel'
            USING HINT = 'Unkown vessel mmsi';
    END IF;
    PERFORM set_config('vessel.mmsi', vessel_rec.mmsi, false);
    --RAISE WARNING 'vessel.mmsi %', current_setting('vessel.mmsi', false);
    PERFORM set_config('vessel.name', vessel_rec.name, false);
  ELSIF _role <> 'api_anonymous' THEN
    RAISE EXCEPTION 'Invalid role'
      USING HINT = 'Stop being so evil and maybe you can log in';
  END IF;
END
$$ language plpgsql security definer;

-- Function to trigger cron_jobs using API for tests.
-- Todo limit access and permision
-- Run con jobs
CREATE OR REPLACE FUNCTION api.run_cron_jobs() RETURNS void AS $$
BEGIN
    -- In correct order
    select public.cron_process_new_account_fn();
    select public.cron_process_new_vessel_fn();
    select public.cron_process_monitor_online_fn();
    select public.cron_process_new_logbook_fn();
    select public.cron_process_new_stay_fn();
    select public.cron_process_new_moorage_fn();
    select public.cron_process_monitor_offline_fn();
END
$$ language plpgsql security definer;