---------------------------------------------------------------------------
-- Copyright 2021-2024 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration August 2024
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Update api role SQL connection to 30
ALTER ROLE authenticator WITH NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 30 LOGIN;

-- Remove CONSTRAINT unique email for vessels table
ALTER TABLE auth.vessels DROP CONSTRAINT vessels_pkey;
-- Create new index for vessels table
CREATE INDEX vessels_owner_email_idx ON auth.vessels (owner_email);

-- Update new logbook email template
UPDATE public.email_templates
	SET email_content='Hello __RECIPIENT__,

Here is a recap of your latest trip __LOGBOOK_NAME__ on PostgSail.
__LOGBOOK_STATS__

Check out your timelapse at __APP_URL__/timelapse/__LOGBOOK_LINK__

See more details at __APP_URL__/log/__LOGBOOK_LINK__

Happy sailing!
The PostgSail Team'
	WHERE "name"='logbook';

-- Update deactivated email template
UPDATE public.email_templates
	SET email_content='Hello __RECIPIENT__,

Your account has been deactivated and all your data has been removed from PostgSail system.

Thank you for being a valued user of PostgSail!

Find more details at __APP_URL__
'
	WHERE "name"='deactivated';

-- Update HTML email for new logbook
DROP FUNCTION IF EXISTS public.send_email_py_fn;
CREATE OR REPLACE FUNCTION public.send_email_py_fn(IN email_type TEXT, IN _user JSONB, IN app JSONB) RETURNS void
AS $send_email_py$
    # Import smtplib for the actual sending function
    import smtplib
    import requests

    # Import the email modules we need
    from email.message import EmailMessage
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
        email_content = email_content.replace('__LOGBOOK_NAME__', str(_user['logbook_name']))
    if 'logbook_link' in _user and _user['logbook_link']:
        email_content = email_content.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'logbook_img' in _user and _user['logbook_img']:
        email_content = email_content.replace('__LOGBOOK_IMG__', str(_user['logbook_img']))
    if 'logbook_stats' in _user and _user['logbook_img']:
        email_content = email_content.replace('__LOGBOOK_STATS__', str(_user['logbook_stats']))
    if 'video_link' in _user and _user['video_link']:
        email_content = email_content.replace('__VIDEO_LINK__', str( _user['video_link']))
    if 'recipient' in _user and _user['recipient']:
        email_content = email_content.replace('__RECIPIENT__', _user['recipient'])
    if 'boat' in _user and _user['boat']:
        email_content = email_content.replace('__BOAT__', _user['boat'])
    if 'badge' in _user and _user['badge']:
        email_content = email_content.replace('__BADGE_NAME__', _user['badge'])
    if 'otp_code' in _user and _user['otp_code']:
        email_content = email_content.replace('__OTP_CODE__', _user['otp_code'])
    if 'reset_qs' in _user and _user['reset_qs']:
        email_content = email_content.replace('__RESET_QS__', _user['reset_qs'])
    if 'alert' in _user and _user['alert']:
        email_content = email_content.replace('__ALERT__', _user['alert'])

    if 'app.url' in app and app['app.url']:
        email_content = email_content.replace('__APP_URL__', app['app.url'])

    email_from = 'root@localhost'
    if 'app.email_from' in app and app['app.email_from']:
        email_from = 'PostgSail <' + app['app.email_from'] + '>'
    #plpy.notice('Sending email from [{}] [{}]'.format(email_from, app['app.email_from']))

    email_to = 'root@localhost'
    if 'email' in _user and _user['email']:
        email_to = _user['email']
        #plpy.notice('Sending email to [{}] [{}]'.format(email_to, _user['email']))
    else:
        plpy.error('Error email to')
        return None

    if email_type == 'logbook':
        msg = EmailMessage()
        msg.set_content(email_content)
    else:
        msg = MIMEText(email_content, 'plain', 'utf-8')
    msg["Subject"] = email_subject
    msg["From"] = email_from
    msg["To"] = email_to
    msg["Date"] = formatdate()
    msg["Message-ID"] = make_msgid()

    if email_type == 'logbook' and 'logbook_img' in _user and _user['logbook_img']:
        # Create a Content-ID for the image
        image_cid = make_msgid()
        # Transform HTML template
        logbook_link = "{__APP_URL__}/log/{__LOGBOOK_LINK__}".format( __APP_URL__=app['app.url'], __LOGBOOK_LINK__=str(_user['logbook_link']))
        timelapse_link = "{__APP_URL__}/timelapse/{__LOGBOOK_LINK__}".format( __APP_URL__=app['app.url'], __LOGBOOK_LINK__=str(_user['logbook_link']))
        email_content = email_content.replace('\n', '<br/>')
        email_content = email_content.replace(str(_user['logbook_name']), '<a href="{logbook_link}">{logbook_name}</a>'.format(logbook_link=logbook_link, logbook_name=str(_user['logbook_name'])))
        email_content = email_content.replace(logbook_link, '<a href="{logbook_link}">{logbook_link}</a>'.format(logbook_link=logbook_link))
        email_content = email_content.replace(timelapse_link, '<a href="{timelapse_link}">{timelapse_link}</a>'.format(timelapse_link=timelapse_link))
        # Set an alternative html body
        msg.add_alternative("""\
<html>
    <body>
        <p>{email_content}</p>
        <img src="cid:{image_cid}">
    </body>
</html>
""".format(email_content=email_content, image_cid=image_cid[1:-1]), subtype='html')
        img_url = 'https://gis.openplotter.cloud/{}'.format(str(_user['logbook_img']))
        response = requests.get(img_url, stream=True)
        if response.status_code == 200:
            msg.get_payload()[1].add_related(response.raw.data,
                                            maintype='image', 
                                            subtype='png', 
                                            cid=image_cid)

    server_smtp = 'localhost'
    if 'app.email_server' in app and app['app.email_server']:
        server_smtp = app['app.email_server']
    #plpy.notice('Sending server [{}] [{}]'.format(server_smtp, app['app.email_server']))

    # Send the message via our own SMTP server.
    try:
        # send your message with credentials specified above
        with smtplib.SMTP(server_smtp, 587) as server:
            if 'app.email_user' in app and app['app.email_user'] \
                and 'app.email_pass' in app and app['app.email_pass']:
                server.starttls()
                server.login(app['app.email_user'], app['app.email_pass'])
            #server.send_message(msg)
            server.sendmail(msg["From"], msg["To"], msg.as_string())
            server.quit()
        # tell the script to report if your message was sent or which errors need to be fixed
        plpy.notice('Sent email successfully to [{}] [{}]'.format(msg["To"], msg["Subject"]))
        return None
    except OSError as error:
        plpy.error('OS Error occurred: ' + str(error))
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

-- Set default settings to avoid sql shared session cache for every new HTTP request
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
    SELECT current_setting('request.path', true) ~ '^/(logs_view|log_view|rpc/timelapse_fn|rpc/timelapse2_fn|monitoring_view|stats_logs_view|stats_moorages_view|rpc/stats_logs_fn)$' INTO _ppath;
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

-- Remove DEBUG
-- Only one "new_stay" insert
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
        distance BOOLEAN := False;
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
        SELECT * INTO previous_metric
            FROM api.metrics m 
            WHERE m.vessel_id IS NOT NULL
                AND m.vessel_id = current_setting('vessel.id', true)
            ORDER BY m.time DESC LIMIT 1;
        --RAISE NOTICE 'Metrics Status, New:[%] Previous:[%]', NEW.status, previous_metric.status;
        IF previous_metric.time = NEW.time THEN
            -- Ignore entry if same time
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], duplicate time [%] = [%]', NEW.vessel_id, previous_metric.time, NEW.time;
            RETURN NULL;
        END IF;
        IF previous_metric.time > NEW.time THEN
            -- Ignore entry if new time is later than previous time
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], new time is older than previous_metric.time [%] > [%]', NEW.vessel_id, previous_metric.time, NEW.time;
            RETURN NULL;
        END IF;
        -- Check if latitude or longitude are type double
        --IF public.isdouble(NEW.latitude::TEXT) IS False OR public.isdouble(NEW.longitude::TEXT) IS False THEN
        --    -- Ignore entry if null latitude,longitude
        --    RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], not a double type for latitude or longitude [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
        --    RETURN NULL;
        --END IF;
        -- Check if latitude or longitude are null
        IF NEW.latitude IS NULL OR NEW.longitude IS NULL THEN
            -- Ignore entry if null latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], null latitude or longitude [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        -- Check if valid latitude
        IF NEW.latitude >= 90 OR NEW.latitude <= -90 THEN
            -- Ignore entry if invalid latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid latitude >= 90 OR <= -90 [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        -- Check if valid longitude
        IF NEW.longitude >= 180 OR NEW.longitude <= -180 THEN
            -- Ignore entry if invalid latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid longitude >= 180 OR <= -180 [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        -- Check if valid longitude and latitude not close to -0.0000001 from Victron Cerbo
        IF NEW.latitude = NEW.longitude THEN
            -- Ignore entry if latitude,longitude are equal
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], latitude and longitude are equal [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        -- Check distance with previous point is > 10km
        --SELECT ST_Distance(
        --    ST_MakePoint(NEW.latitude,NEW.longitude)::geography,
        --    ST_MakePoint(previous_metric.latitude,previous_metric.longitude)::geography) > 10000 INTO distance;
        --IF distance IS True THEN
        --    RAISE WARNING 'Metrics Ignoring metric, distance between previous metric and new metric is too large, vessel_id [%] distance[%]', NEW.vessel_id, distance;
        --    RETURN NULL;
        --END IF;
        -- Check if status is null but speed is over 3knots set status to sailing
        IF NEW.status IS NULL AND NEW.speedoverground >= 3 THEN
            RAISE WARNING 'Metrics Unknown NEW.status, vessel_id [%], null status, set to sailing because of speedoverground is +3 from [%]', NEW.vessel_id, NEW.status;
            NEW.status := 'sailing';
        -- Check if status is null then set status to default moored
        ELSIF NEW.status IS NULL THEN
            RAISE WARNING 'Metrics Unknown NEW.status, vessel_id [%], null status, set to default moored from [%]', NEW.vessel_id, NEW.status;
            NEW.status := 'moored';
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
            --    VALUES ('new_stay', stay_id, now(), current_setting('vessel.id', true));
            --RAISE WARNING 'Metrics Insert first stay as no previous metrics exist, stay_id stay_id [%] [%] [%]', stay_id, NEW.status, NEW.time;
        END IF;
        -- Check if status is valid enum
        SELECT NEW.status::name = any(enum_range(null::status_type)::name[]) INTO valid_status;
        IF valid_status IS False THEN
            -- Ignore entry if status is invalid
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid status [%]', NEW.vessel_id, NEW.status;
            RETURN NULL;
        END IF;
        -- Check if speedOverGround is valid value
        IF NEW.speedoverground >= 40 THEN
            -- Ignore entry as speedOverGround is invalid
            RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], speedOverGround is invalid, over 40 < [%]', NEW.vessel_id, NEW.speedoverground;
            RETURN NULL;
        END IF;

        -- Check the state and if any previous/current entry
        -- If change of state and new status is sailing or motoring
        IF previous_metric.status::TEXT <> NEW.status::TEXT AND
            ( (NEW.status::TEXT = 'sailing' AND previous_metric.status::TEXT <> 'motoring')
             OR (NEW.status::TEXT = 'motoring' AND previous_metric.status::TEXT <> 'sailing') ) THEN
            RAISE WARNING 'Metrics Update status, try new logbook, New:[%] Previous:[%]', NEW.status, previous_metric.status;
            -- Start new log
            logbook_id := public.trip_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF logbook_id IS NULL THEN
                INSERT INTO api.logbook
                    (vessel_id, active, _from_time, _from_lat, _from_lng)
                    VALUES (current_setting('vessel.id', true), true, NEW.time, NEW.latitude, NEW.longitude)
                    RETURNING id INTO logbook_id;
                RAISE WARNING 'Metrics Insert new logbook, logbook_id [%] [%] [%]', logbook_id, NEW.status, NEW.time;
            ELSE
                UPDATE api.logbook
                    SET
                        active = false,
                        _to_time = NEW.time,
                        _to_lat = NEW.latitude,
                        _to_lng = NEW.longitude
                    WHERE id = logbook_id;
                RAISE WARNING 'Metrics Existing logbook logbook_id [%] [%] [%]', logbook_id, NEW.status, NEW.time;
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
                RAISE WARNING 'Metrics Updating Stay end current stay_id [%] [%] [%]', stay_id, NEW.status, NEW.time;
            ELSE
                RAISE WARNING 'Metrics Invalid stay_id [%] [%]', stay_id, NEW.time;
            END IF;

        -- If change of state and new status is moored or anchored
        ELSIF previous_metric.status::TEXT <> NEW.status::TEXT AND
            ( (NEW.status::TEXT = 'moored' AND previous_metric.status::TEXT <> 'anchored')
             OR (NEW.status::TEXT = 'anchored' AND previous_metric.status::TEXT <> 'moored') ) THEN
            -- Start new stays
            RAISE WARNING 'Metrics Update status, try new stay, New:[%] Previous:[%]', NEW.status, previous_metric.status;
            stay_id := public.stay_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF stay_id IS NULL THEN
                RAISE WARNING 'Metrics Inserting new stay [%]', NEW.status;
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
                RAISE WARNING 'Metrics Insert new stay, stay_id [%] [%] [%]', stay_id, NEW.status, NEW.time;
            ELSE
                RAISE WARNING 'Metrics Invalid stay_id [%] [%]', stay_id, NEW.time;
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
                RAISE WARNING 'Metrics Updating logbook status [%] [%] [%]', logbook_id, NEW.status, NEW.time;
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
                RAISE WARNING 'Metrics Invalid logbook_id [%] [%] [%]', logbook_id, NEW.status, NEW.time;
            END IF;
        END IF;
        RETURN NEW; -- Finally insert the actual new metric
    END;
$function$
;
-- Description
COMMENT ON FUNCTION
    public.metrics_trigger_fn() IS 'process metrics from vessel, generate pre_logbook and new_stay.';

-- Update alert message. add the date and format the numeric value
DROP FUNCTION IF EXISTS public.cron_alerts_fn();
CREATE OR REPLACE FUNCTION public.cron_alerts_fn() RETURNS void AS $cron_alerts$
DECLARE
    alert_rec record;
    default_last_metric TIMESTAMPTZ := NOW() - interval '1 day';
    last_metric TIMESTAMPTZ;
    metric_rec record;
    app_settings JSONB;
    user_settings JSONB;
    alerting JSONB;
    _alarms JSONB;
    alarms TEXT;
    alert_default JSONB := '{
        "low_pressure_threshold": 990,
        "high_wind_speed_threshold": 30,
        "low_water_depth_threshold": 1,
        "min_notification_interval": 6,
        "high_pressure_drop_threshold": 12,
        "low_battery_charge_threshold": 90,
        "low_battery_voltage_threshold": 12.5,
        "low_water_temperature_threshold": 10,
        "low_indoor_temperature_threshold": 7,
        "low_outdoor_temperature_threshold": 3
    }';
BEGIN
    -- Check for new event notification pending update
    RAISE NOTICE 'cron_alerts_fn';
    FOR alert_rec in
        SELECT
            a.user_id,a.email,v.vessel_id,
            COALESCE((a.preferences->'alert_last_metric')::TEXT, default_last_metric::TEXT) as last_metric,
            (alert_default || (a.preferences->'alerting')::JSONB) as alerting,
            (a.preferences->'alarms')::JSONB as alarms
            FROM auth.accounts a
            LEFT JOIN auth.vessels AS v ON v.owner_email = a.email
            LEFT JOIN api.metadata AS m ON m.vessel_id = v.vessel_id
            WHERE (a.preferences->'alerting'->'enabled')::boolean = True
                AND m.active = True
        LOOP
        RAISE NOTICE '-> cron_alerts_fn for [%]', alert_rec;
        PERFORM set_config('vessel.id', alert_rec.vessel_id, false);
        PERFORM set_config('user.email', alert_rec.email, false);
        --RAISE WARNING 'public.cron_process_alert_rec_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(alert_rec.vessel_id::TEXT);
        RAISE NOTICE '-> cron_alerts_fn checking user_settings [%]', user_settings;
        -- Get all metrics from the last last_metric avg by 5 minutes
        FOR metric_rec in
            SELECT time_bucket('5 minutes', m.time) AS time_bucket,
                    avg((m.metrics->'environment.inside.temperature')::numeric) AS intemp,
                    avg((m.metrics->'environment.outside.temperature')::numeric) AS outtemp,
                    avg((m.metrics->'environment.water.temperature')::numeric) AS wattemp,
                    avg((m.metrics->'environment.depth.belowTransducer')::numeric) AS watdepth,
                    avg((m.metrics->'environment.outside.pressure')::numeric) AS pressure,
                    avg((m.metrics->'environment.wind.speedTrue')::numeric) AS wind,
                    avg((m.metrics->'electrical.batteries.House.voltage')::numeric) AS voltage,
                    avg(coalesce((m.metrics->>'electrical.batteries.House.capacity.stateOfCharge')::numeric, 1)) AS charge
                FROM api.metrics m
                WHERE vessel_id = alert_rec.vessel_id
                    AND m.time >= alert_rec.last_metric::TIMESTAMPTZ
                GROUP BY time_bucket
                ORDER BY time_bucket ASC LIMIT 100
        LOOP
            RAISE NOTICE '-> cron_alerts_fn checking metrics [%]', metric_rec;
            RAISE NOTICE '-> cron_alerts_fn checking alerting [%]', alert_rec.alerting;
            --RAISE NOTICE '-> cron_alerts_fn checking debug [%] [%]', kelvinToCel(metric_rec.intemp), (alert_rec.alerting->'low_indoor_temperature_threshold');
            IF kelvinToCel(metric_rec.intemp) < (alert_rec.alerting->'low_indoor_temperature_threshold')::numeric then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_indoor_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_indoor_temperature_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_indoor_temperature_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_indoor_temperature_threshold": {"value": '|| kelvinToCel(metric_rec.intemp) ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_outdoor_temperature_threshold value:'|| kelvinToCel(metric_rec.intemp) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_indoor_temperature_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_indoor_temperature_threshold';
            END IF;
            IF kelvinToCel(metric_rec.outtemp) < (alert_rec.alerting->'low_outdoor_temperature_threshold')::numeric then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_outdoor_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_outdoor_temperature_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_outdoor_temperature_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_outdoor_temperature_threshold": {"value": '|| kelvinToCel(metric_rec.outtemp) ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_outdoor_temperature_threshold value:'|| kelvinToCel(metric_rec.outtemp) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_outdoor_temperature_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_outdoor_temperature_threshold';
            END IF;
            IF kelvinToCel(metric_rec.wattemp) < (alert_rec.alerting->'low_water_temperature_threshold')::numeric then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_water_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_water_temperature_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_water_temperature_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_water_temperature_threshold": {"value": '|| kelvinToCel(metric_rec.wattemp) ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_water_temperature_threshold value:'|| kelvinToCel(metric_rec.wattemp) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_water_temperature_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_water_temperature_threshold';
            END IF;
            IF metric_rec.watdepth < (alert_rec.alerting->'low_water_depth_threshold')::numeric then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_water_depth_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_water_depth_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_water_depth_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_water_depth_threshold": {"value": '|| metric_rec.watdepth ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_water_depth_threshold value:'|| ROUND(metric_rec.watdepth,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_water_depth_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_water_depth_threshold';
            END IF;
            if metric_rec.pressure < (alert_rec.alerting->'high_pressure_drop_threshold')::numeric then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'high_pressure_drop_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'high_pressure_drop_threshold'->>'date') IS NULL) OR
                    (((_alarms->'high_pressure_drop_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"high_pressure_drop_threshold": {"value": '|| metric_rec.pressure ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "high_pressure_drop_threshold value:'|| ROUND(metric_rec.pressure,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug high_pressure_drop_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug high_pressure_drop_threshold';
            END IF;
            IF metric_rec.wind > (alert_rec.alerting->'high_wind_speed_threshold')::numeric then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'high_wind_speed_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'high_wind_speed_threshold'->>'date') IS NULL) OR
                    (((_alarms->'high_wind_speed_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"high_wind_speed_threshold": {"value": '|| metric_rec.wind ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "high_wind_speed_threshold value:'|| ROUND(metric_rec.wind,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug high_wind_speed_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug high_wind_speed_threshold';
            END IF;
            if metric_rec.voltage < (alert_rec.alerting->'low_battery_voltage_threshold')::numeric then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_battery_voltage_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_battery_voltage_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_battery_voltage_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_battery_voltage_threshold": {"value": '|| metric_rec.voltage ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_battery_voltage_threshold value:'|| ROUND(metric_rec.voltage,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_voltage_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_voltage_threshold';
            END IF;
            if (metric_rec.charge*100) < (alert_rec.alerting->'low_battery_charge_threshold')::numeric then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_battery_charge_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_battery_charge_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_battery_charge_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_battery_charge_threshold": {"value": '|| (metric_rec.charge*100) ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_battery_charge_threshold value:'|| ROUND(metric_rec.charge*100,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_charge_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_charge_threshold';
            END IF;
            -- Record last metrics time
            SELECT metric_rec.time_bucket INTO last_metric;
        END LOOP;
        PERFORM api.update_user_preferences_fn('{alert_last_metric}'::TEXT, last_metric::TEXT);
    END LOOP;
END;
$cron_alerts$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_alerts_fn
    IS 'init by pg_cron to check for alerts';

-- Remove qgis dependency
DROP FUNCTION IF EXISTS public.process_post_logbook_fn;
CREATE OR REPLACE FUNCTION public.process_post_logbook_fn(IN _id integer) RETURNS void AS $process_post_logbook_queue$
    DECLARE
        logbook_rec record;
        log_settings jsonb;
        user_settings jsonb;
        extra_json jsonb;
        log_img_url text;
        --logs_img_url text;
        log_stats text;
        --extent_bbox text;
    BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_post_logbook_fn invalid input %', _id;
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
            RAISE WARNING '-> process_post_logbook_fn invalid logbook %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', logbook_rec.vessel_id, false);
        --RAISE WARNING 'public.process_post_logbook_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);

        -- Generate logbook image map name from QGIS
        SELECT CONCAT('log_', logbook_rec.vessel_id::TEXT, '_', logbook_rec.id, '.png') INTO log_img_url;
        --SELECT ST_Extent(ST_Transform(logbook_rec.track_geom, 3857))::TEXT AS envelope INTO extent_bbox FROM api.logbook WHERE id = logbook_rec.id;
        --PERFORM public.qgis_getmap_py_fn(logbook_rec.vessel_id::TEXT, logbook_rec.id, extent_bbox::TEXT, False);
        -- Generate logs image map name from QGIS
        --WITH merged AS (
        --    SELECT ST_Union(logbook_rec.track_geom) AS merged_geometry
        --        FROM api.logbook WHERE vessel_id = logbook_rec.vessel_id
        --)
        --SELECT ST_Extent(ST_Transform(merged_geometry, 3857))::TEXT AS envelope INTO extent_bbox FROM merged;
        --SELECT CONCAT('logs_', logbook_rec.vessel_id::TEXT, '_', logbook_rec.id, '.png') INTO logs_img_url;
        --PERFORM public.qgis_getmap_py_fn(logbook_rec.vessel_id::TEXT, logbook_rec.id, extent_bbox::TEXT, True);

        -- Add formatted distance and duration for email notification
        SELECT CONCAT(ROUND(logbook_rec.distance, 2), ' NM / ', ROUND(EXTRACT(epoch FROM logbook_rec.duration)/3600,2), 'H') INTO log_stats;

        -- Prepare notification, gather user settings
        SELECT json_build_object('logbook_name', logbook_rec.name,
            'logbook_link', logbook_rec.id,
            'logbook_img', log_img_url,
            'logbook_stats', log_stats) INTO log_settings;
        user_settings := get_user_settings_from_vesselid_fn(logbook_rec.vessel_id::TEXT);
        SELECT user_settings::JSONB || log_settings::JSONB into user_settings;
        RAISE NOTICE '-> debug process_post_logbook_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        RAISE NOTICE '-> debug process_post_logbook_fn log_settings [%]', log_settings;
        -- Send notification
        PERFORM send_notification_fn('logbook'::TEXT, user_settings::JSONB);
        -- Process badges
        RAISE NOTICE '-> debug process_post_logbook_fn user_settings [%]', user_settings->>'email'::TEXT;
        PERFORM set_config('user.email', user_settings->>'email'::TEXT, false);
        PERFORM badges_logbook_fn(logbook_rec.id, logbook_rec._to_time::TEXT);
        PERFORM badges_geom_fn(logbook_rec.id, logbook_rec._to_time::TEXT);
    END;
$process_post_logbook_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_post_logbook_fn
    IS 'Notify user for new logbook.';

-- Add new qgis and video URLs settings
DROP FUNCTION IF EXISTS public.get_app_settings_fn;
CREATE OR REPLACE FUNCTION public.get_app_settings_fn(OUT app_settings jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
BEGIN
    SELECT
        jsonb_object_agg(name, value) INTO app_settings
    FROM
        public.app_settings
    WHERE
        name LIKE 'app.email%'
        OR name LIKE 'app.pushover%'
        OR name LIKE 'app.url'
        OR name LIKE 'app.telegram%'
        OR name LIKE 'app.grafana_admin_uri'
        OR name LIKE 'app.keycloak_uri'
        OR name LIKE 'app.windy_apikey'
        OR name LIKE 'app.%_uri'
        OR name LIKE 'app.%_url';
END;
$function$
;
COMMENT ON FUNCTION public.get_app_settings_fn(out jsonb) IS 'get application settings details, email, pushover, telegram, grafana_admin_uri';

-- Add error handling for invalid argument
DROP FUNCTION IF EXISTS public.qgis_bbox_py_fn;
CREATE OR REPLACE FUNCTION public.qgis_bbox_py_fn(IN vessel_id TEXT DEFAULT NULL, IN log_id NUMERIC DEFAULT NULL, IN width NUMERIC DEFAULT 1080, IN height NUMERIC DEFAULT 566, IN scaleout BOOLEAN DEFAULT True, OUT bbox TEXT)
AS $qgis_bbox_py$
	log_extent = None
	if not vessel_id and not log_id:
	    plpy.error('Error qgis_bbox_py invalid input vessel_id [{}], log_id [{}]'.format(vessel_id, log_id))
	# If we have a vessel_id then it is logs image map
	if vessel_id:
		# Use the shared cache to avoid preparing the log extent
		if vessel_id in SD:
			plan = SD[vessel_id]
		# A prepared statement from Python
		else:
			plan = plpy.prepare("WITH merged AS ( SELECT ST_Union(track_geom) AS merged_geometry FROM api.logbook WHERE vessel_id = $1 ) SELECT ST_Extent(ST_Transform(merged_geometry, 3857))::TEXT FROM merged;", ["text"])
			SD[vessel_id] = plan
		# Execute the statement with the log extent param and limit to 1 result
		rv = plpy.execute(plan, [vessel_id], 1)
		log_extent = rv[0]['st_extent']
    # Else we have a log_id then it is single log image map
	else:
		# Use the shared cache to avoid preparing the log extent
		if log_id in SD:
			plan = SD[log_id]
		# A prepared statement from Python
		else:
			plan = plpy.prepare("SELECT ST_Extent(ST_Transform(track_geom, 3857)) FROM api.logbook WHERE id = $1::NUMERIC", ["text"])
			SD[log_id] = plan
		# Execute the statement with the log extent param and limit to 1 result
		rv = plpy.execute(plan, [log_id], 1)
		log_extent = rv[0]['st_extent']

	# Extract extent
	def parse_extent_from_db(extent_raw):
	    # Parse the extent_raw to extract coordinates
	    extent = extent_raw.replace('BOX(', '').replace(')', '').split(',')
	    min_x, min_y = map(float, extent[0].split())
	    max_x, max_y = map(float, extent[1].split())
	    return min_x, min_y, max_x, max_y
	
	# ZoomOut from linestring extent 
	def apply_scale_factor(extent, scale_factor=1.125):
	    min_x, min_y, max_x, max_y = extent
	    center_x = (min_x + max_x) / 2
	    center_y = (min_y + max_y) / 2
	    width = max_x - min_x
	    height = max_y - min_y
	    new_width = width * scale_factor
	    new_height = height * scale_factor
	    scaled_extent = (
	        round(center_x - new_width / 2),
	        round(center_y - new_height / 2),
	        round(center_x + new_width / 2),
	        round(center_y + new_height / 2),
	    )
	    return scaled_extent

	def adjust_bbox_to_fixed_size(scaled_extent, fixed_width, fixed_height):
	    min_x, min_y, max_x, max_y = scaled_extent
	    bbox_width = float(max_x - min_x)
	    bbox_height = float(max_y - min_y)
	    bbox_aspect_ratio = float(bbox_width / bbox_height)
	    image_aspect_ratio = float(fixed_width / fixed_height)
	
	    if bbox_aspect_ratio > image_aspect_ratio:
	        # Adjust height to match aspect ratio
	        new_bbox_height = bbox_width / image_aspect_ratio
	        height_diff = new_bbox_height - bbox_height
	        min_y -= height_diff / 2
	        max_y += height_diff / 2
	    else:
	        # Adjust width to match aspect ratio
	        new_bbox_width = bbox_height * image_aspect_ratio
	        width_diff = new_bbox_width - bbox_width
	        min_x -= width_diff / 2
	        max_x += width_diff / 2

	    adjusted_extent = (min_x, min_y, max_x, max_y)
	    return adjusted_extent

	if (not vessel_id and not log_id) or not log_extent:
	    plpy.error('Failed to get sql qgis_bbox_py vessel_id [{}], log_id [{}], extent [{}]'.format(vessel_id, log_id, log_extent))
	#plpy.notice('qgis_bbox_py log_id [{}], extent [{}]'.format(log_id, log_extent))
	# Parse extent and apply ZoomOut scale factor
	if scaleout:
		scaled_extent = apply_scale_factor(parse_extent_from_db(log_extent))
	else:
		scaled_extent = parse_extent_from_db(log_extent)
	#plpy.notice('qgis_bbox_py log_id [{}], scaled_extent [{}]'.format(log_id, scaled_extent))
	fixed_width = width # default 1080
	fixed_height = height # default 566
	adjusted_extent = adjust_bbox_to_fixed_size(scaled_extent, fixed_width, fixed_height)
	#plpy.notice('qgis_bbox_py log_id [{}], adjusted_extent [{}]'.format(log_id, adjusted_extent))
	min_x, min_y, max_x, max_y = adjusted_extent
	return f"{min_x},{min_y},{max_x},{max_y}"
$qgis_bbox_py$ LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.qgis_bbox_py_fn
    IS 'Generate the BBOX base on log extent and adapt extent to the image size for QGIS Server';

-- Add error handling for invalid argument
DROP FUNCTION IF EXISTS public.qgis_bbox_trip_py_fn;
CREATE OR REPLACE FUNCTION public.qgis_bbox_trip_py_fn(IN _str_to_parse TEXT DEFAULT NULL, OUT bbox TEXT)
AS $qgis_bbox_trip_py$
	#plpy.notice('qgis_bbox_trip_py_fn _str_to_parse [{}]'.format(_str_to_parse))
	if not _str_to_parse or '_' not in _str_to_parse:
	    plpy.error('Error qgis_bbox_py invalid input _str_to_parse [{}]'.format(_str_to_parse))
	vessel_id, log_id, log_end = _str_to_parse.split('_')
	width = 1080
	height = 566
	scaleout = True
	log_extent = None
	# If we have a vessel_id then it is full logs image map
	if vessel_id and log_end is None:
		# Use the shared cache to avoid preparing the log extent
		if vessel_id in SD:
			plan = SD[vessel_id]
		# A prepared statement from Python
		else:
			plan = plpy.prepare("WITH merged AS ( SELECT ST_Union(track_geom) AS merged_geometry FROM api.logbook WHERE vessel_id = $1 ) SELECT ST_Extent(ST_Transform(merged_geometry, 3857))::TEXT FROM merged;", ["text"])
			SD[vessel_id] = plan
		# Execute the statement with the log extent param and limit to 1 result
		rv = plpy.execute(plan, [vessel_id], 1)
		log_extent = rv[0]['st_extent']
	# If we have a vessel_id and a log_end then it is subset logs image map
	elif vessel_id and log_end:
		# Use the shared cache to avoid preparing the log extent
		shared_cache = vessel_id + str(log_id) + str(log_end)
		if shared_cache in SD:
			plan = SD[shared_cache]
		# A prepared statement from Python
		else:
			plan = plpy.prepare("WITH merged AS ( SELECT ST_Union(track_geom) AS merged_geometry FROM api.logbook WHERE vessel_id = $1 and id >= $2::NUMERIC and id <= $3::NUMERIC) SELECT ST_Extent(ST_Transform(merged_geometry, 3857))::TEXT FROM merged;", ["text","text","text"])
			SD[shared_cache] = plan
		# Execute the statement with the log extent param and limit to 1 result
		rv = plpy.execute(plan, [vessel_id,log_id,log_end], 1)
		log_extent = rv[0]['st_extent']
    # Else we have a log_id then it is single log image map
	else :
		# Use the shared cache to avoid preparing the log extent
		if log_id in SD:
			plan = SD[log_id]
		# A prepared statement from Python
		else:
			plan = plpy.prepare("SELECT ST_Extent(ST_Transform(track_geom, 3857)) FROM api.logbook WHERE id = $1::NUMERIC", ["text"])
			SD[log_id] = plan
		# Execute the statement with the log extent param and limit to 1 result
		rv = plpy.execute(plan, [log_id], 1)
		log_extent = rv[0]['st_extent']

	# Extract extent
	def parse_extent_from_db(extent_raw):
	    # Parse the extent_raw to extract coordinates
	    extent = extent_raw.replace('BOX(', '').replace(')', '').split(',')
	    min_x, min_y = map(float, extent[0].split())
	    max_x, max_y = map(float, extent[1].split())
	    return min_x, min_y, max_x, max_y
	
	# ZoomOut from linestring extent 
	def apply_scale_factor(extent, scale_factor=1.125):
	    min_x, min_y, max_x, max_y = extent
	    center_x = (min_x + max_x) / 2
	    center_y = (min_y + max_y) / 2
	    width = max_x - min_x
	    height = max_y - min_y
	    new_width = width * scale_factor
	    new_height = height * scale_factor
	    scaled_extent = (
	        round(center_x - new_width / 2),
	        round(center_y - new_height / 2),
	        round(center_x + new_width / 2),
	        round(center_y + new_height / 2),
	    )
	    return scaled_extent

	def adjust_bbox_to_fixed_size(scaled_extent, fixed_width, fixed_height):
	    min_x, min_y, max_x, max_y = scaled_extent
	    bbox_width = float(max_x - min_x)
	    bbox_height = float(max_y - min_y)
	    bbox_aspect_ratio = float(bbox_width / bbox_height)
	    image_aspect_ratio = float(fixed_width / fixed_height)
	
	    if bbox_aspect_ratio > image_aspect_ratio:
	        # Adjust height to match aspect ratio
	        new_bbox_height = bbox_width / image_aspect_ratio
	        height_diff = new_bbox_height - bbox_height
	        min_y -= height_diff / 2
	        max_y += height_diff / 2
	    else:
	        # Adjust width to match aspect ratio
	        new_bbox_width = bbox_height * image_aspect_ratio
	        width_diff = new_bbox_width - bbox_width
	        min_x -= width_diff / 2
	        max_x += width_diff / 2

	    adjusted_extent = (min_x, min_y, max_x, max_y)
	    return adjusted_extent

	if not log_extent:
	    plpy.error('Failed to get sql qgis_bbox_trip_py_fn vessel_id [{}], log_id [{}], extent [{}]'.format(vessel_id, log_id, log_extent))
	#plpy.notice('qgis_bbox_trip_py_fn log_id [{}], extent [{}]'.format(log_id, log_extent))
	# Parse extent and apply ZoomOut scale factor
	if scaleout:
		scaled_extent = apply_scale_factor(parse_extent_from_db(log_extent))
	else:
		scaled_extent = parse_extent_from_db(log_extent)
	#plpy.notice('qgis_bbox_trip_py_fn log_id [{}], scaled_extent [{}]'.format(log_id, scaled_extent))
	fixed_width = width # default 1080
	fixed_height = height # default 566
	adjusted_extent = adjust_bbox_to_fixed_size(scaled_extent, fixed_width, fixed_height)
	#plpy.notice('qgis_bbox_trip_py_fn log_id [{}], adjusted_extent [{}]'.format(log_id, adjusted_extent))
	min_x, min_y, max_x, max_y = adjusted_extent
	return f"{min_x},{min_y},{max_x},{max_y}"
$qgis_bbox_trip_py$ LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.qgis_bbox_trip_py_fn
    IS 'Generate the BBOX base on trip extent and adapt extent to the image size for QGIS Server';

-- Ensure name without double quote, Fix issue with when string contains quote
DROP FUNCTION public.process_lat_lon_fn(in numeric, in numeric, out int4, out int4, out text, out text);
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
                (vessel_id, name, country, stay_code, reference_count, latitude, longitude, geog, overpass, nominatim)
                VALUES (
                    current_setting('vessel.id', false),
                    coalesce(replace(moorage_name,'"', ''), null),
                    coalesce(moorage_country, null),
                    moorage_type,
                    1,
                    lat,
                    lon,
                    Geography(ST_MakePoint(lon, lat)),
                    coalesce(overpass, null),
                    coalesce(geo, null)
                ) returning id into moorage_id;
            -- Add moorage entry to process queue for reference
            --INSERT INTO process_queue (channel, payload, stored, ref_id, processed)
            --    VALUES ('new_moorage', moorage_id, now(), current_setting('vessel.id', true), now());
        END IF;
        --return json_build_object(
        --        'id', moorage_id,
        --        'name', moorage_name,
        --        'type', moorage_type
        --        )::jsonb;
    END;
$function$
;

COMMENT ON FUNCTION public.process_lat_lon_fn(in numeric, in numeric, out int4, out int4, out text, out text) IS 'Add or Update moorage base on lat/lon';

-- Refresh permissions for qgis_role
GRANT EXECUTE ON FUNCTION public.qgis_bbox_py_fn(in text, in numeric, in numeric, in numeric, in bool, out text) TO qgis_role;
GRANT EXECUTE ON FUNCTION public.qgis_bbox_trip_py_fn(in text, out text) TO qgis_role;

-- Refresh user_role permissions
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;

-- Update version
UPDATE public.app_settings
	SET value='0.7.6'
	WHERE "name"='app.version';

\c postgres
