---------------------------------------------------------------------------
-- Copyright 2021-2024 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration September 2024
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Add new email template account_inactivity
INSERT INTO public.email_templates ("name",email_subject,email_content,pushover_title,pushover_message)
	VALUES ('inactivity','We Haven''t Seen You in a While!','Hi __RECIPIENT__,

You''re busy. We understand.

You haven''t logged into PostgSail for a considerable period. Since we last saw you, we have continued to add new and exciting features to help you explorer your navigation journey.

Meanwhile, we have cleanup your data. If you wish to maintain an up-to-date overview of your sail journey in PostgSail''''s dashboard, kindly log in to your account within the next seven days.

Please note that your account will be permanently deleted if it remains inactive for seven more days.

If you have any questions or concerns or if you believe this to be an error, please do not hesitate to reach out at info@openplotter.cloud.

Sincerely,
Francois','We Haven''t Seen You in a While!','You haven''t logged into PostgSail for a considerable period. Login to check what''s new!.');

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
    if 'logbook_stats' in _user and _user['logbook_stats']:
        email_content = email_content.replace('__LOGBOOK_STATS__', str(_user['logbook_stats']))
    if 'video_link' in _user and _user['video_link']:
        email_content = email_content.replace('__VIDEO_LINK__', str(_user['video_link']))
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
        # Transform to HTML template, replace text by HTML link
        logbook_link = "{__APP_URL__}/log/{__LOGBOOK_LINK__}".format( __APP_URL__=app['app.url'], __LOGBOOK_LINK__=str(_user['logbook_link']))
        timelapse_link = "{__APP_URL__}/timelapse/{__LOGBOOK_LINK__}".format( __APP_URL__=app['app.url'], __LOGBOOK_LINK__=str(_user['logbook_link']))
        email_content = email_content.replace('\n', '<br/>')
        email_content = email_content.replace(logbook_link, '<a href="{logbook_link}">{logbook_link}</a>'.format(logbook_link=str(logbook_link)))
        email_content = email_content.replace(timelapse_link, '<a href="{timelapse_link}">{timelapse_link}</a>'.format(timelapse_link=str(logbook_link)))
        email_content = email_content.replace(str(_user['logbook_name']), '<a href="{logbook_link}">{logbook_name}</a>'.format(logbook_link=str(logbook_link), logbook_name=str(_user['logbook_name'])))
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

-- Update stats_logs_fn, update debug
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
        --RAISE NOTICE '--> stats_logs_fn, _start_date [%], _end_date [%]', _start_date, _end_date;
        WITH
            meta AS (
                SELECT m.name FROM api.metadata m ),
            logs_view AS (
                SELECT *
                    FROM api.logbook l
                    WHERE _from_time >= _start_date::TIMESTAMPTZ
                        AND _to_time <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
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

-- Fix stays and moorage statistics for user by date
CREATE OR REPLACE FUNCTION api.stats_stays_fn(
    IN start_date TEXT DEFAULT NULL,
    IN end_date TEXT DEFAULT NULL,
    OUT stats JSON) RETURNS JSON AS $stats_stays$
    DECLARE
        _start_date TIMESTAMPTZ DEFAULT '1970-01-01';
        _end_date TIMESTAMPTZ DEFAULT NOW();
    BEGIN
        IF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            RAISE NOTICE '--> stats_stays_fn, custom filter result stats by date [%]', start_date;
            _start_date := start_date::TIMESTAMPTZ;
            _end_date := end_date::TIMESTAMPTZ;
        END IF;
        --RAISE NOTICE '--> stats_stays_fn, _start_date [%], _end_date [%]', _start_date, _end_date;
        WITH
            stays as (
                select distinct(moorage_id) as moorage_id, sum(duration) as duration, count(id) as reference_count
                    from api.stays s
                    WHERE arrived >= _start_date::TIMESTAMPTZ
                        AND departed <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
                    group by moorage_id
                    order by moorage_id
            ),
            moorages AS (
                SELECT m.id, m.home_flag, m.reference_count, m.stay_duration, m.stay_code, m.country, s.duration, s.reference_count
                    from api.moorages m, stays s
                    where s.moorage_id = m.id
                    order by moorage_id
            ),
            home_ports AS (
                select count(*) as home_ports from moorages m where home_flag is true
            ),
            unique_moorages AS (
                select count(*) as unique_moorages from moorages m
            ),
            time_at_home_ports AS (
                select sum(m.stay_duration) as time_at_home_ports from moorages m where home_flag is true
            ),
            sum_stay_duration AS (
                select sum(m.stay_duration) as sum_stay_duration from moorages m where home_flag is false
            ),
            time_spent_away_arr AS (
                select m.stay_code,sum(m.stay_duration) as stay_duration from moorages m where home_flag is false group by m.stay_code order by m.stay_code
            ),
            time_spent_arr as (
                select jsonb_agg(t.*) as time_spent_away_arr from time_spent_away_arr t
            ),
            time_spent_away AS (
                select sum(m.stay_duration) as time_spent_away from moorages m where home_flag is false
            ),
            time_spent as (
                select jsonb_agg(t.*) as time_spent_away from time_spent_away t
            )
        -- Return a JSON
        SELECT jsonb_build_object(
            'home_ports', home_ports.home_ports,
            'unique_moorages', unique_moorages.unique_moorages,
            'time_at_home_ports', time_at_home_ports.time_at_home_ports,
            'sum_stay_duration', sum_stay_duration.sum_stay_duration,
            'time_spent_away', time_spent_away.time_spent_away,
            'time_spent_away_arr', time_spent_arr.time_spent_away_arr) INTO stats
            FROM home_ports, unique_moorages,
                        time_at_home_ports, sum_stay_duration, time_spent_away, time_spent_arr;
    END;
$stats_stays$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.stats_stays_fn
    IS 'Stays/Moorages stats by date';

-- Update api.stats_moorages_view, fix time_spent_at_home_port
CREATE OR REPLACE VIEW api.stats_moorages_view WITH (security_invoker=true,security_barrier=true) AS
    WITH
        home_ports AS (
            select count(*) as home_ports from api.moorages m where home_flag is true
        ),
        unique_moorage AS (
            select count(*) as unique_moorage from api.moorages m
        ),
        time_at_home_ports AS (
            select sum(m.stay_duration) as time_at_home_ports from api.moorages m where home_flag is true
        ),
        time_spent_away AS (
            select sum(m.stay_duration) as time_spent_away from api.moorages m where home_flag is false
        )
    SELECT
        home_ports.home_ports as "home_ports",
        unique_moorage.unique_moorage as "unique_moorages",
        time_at_home_ports.time_at_home_ports as "time_spent_at_home_port(s)",
        time_spent_away.time_spent_away as "time_spent_away"
    FROM home_ports, unique_moorage, time_at_home_ports, time_spent_away;

-- Add stats_fn, user statistics by date
DROP FUNCTION IF EXISTS api.stats_fn;
CREATE OR REPLACE FUNCTION api.stats_fn(
    IN start_date TEXT DEFAULT NULL,
    IN end_date TEXT DEFAULT NULL,
    OUT stats JSONB) RETURNS JSONB AS $stats_global$
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
            stays as (
                select distinct(moorage_id) as moorage_id, sum(duration) as duration, count(id) as reference_count
                    from api.stays s
                    WHERE s.arrived >= _start_date::TIMESTAMPTZ
                        AND s.departed <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
                    group by s.moorage_id
                    order by s.moorage_id
            ),
            moorages AS (
                SELECT m.id, m.home_flag, m.reference_count, m.stay_duration, m.stay_code, m.country, s.duration as dur, s.reference_count as ref_count
                    from api.moorages m, stays s
                    where s.moorage_id = m.id
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
$stats_global$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.stats_fn
    IS 'Stats logbook and moorages by date';

-- Add mapgl_fn, generate a geojson with all linestring
DROP FUNCTION IF EXISTS api.mapgl_fn;
CREATE OR REPLACE FUNCTION api.mapgl_fn(start_log integer DEFAULT NULL::integer, end_log integer DEFAULT NULL::integer, start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT geojson jsonb)
 RETURNS jsonb
AS $mapgl$
    DECLARE
        _geojson jsonb;
    BEGIN
        -- Using sub query to force id order by time
        -- Extract GeoJSON LineString and merge into a new GeoJSON
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
                                            'geometry', jsonb_build_object( 'coordinates', f->'geometry'->'coordinates', 'type', 'LineString'))
                    ) INTO _geojson
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook l
                    WHERE l.id >= start_log
                        AND l.id <= end_log
                        AND l.track_geojson IS NOT NULL
                    ORDER BY l._from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'LineString';
        ELSIF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            SELECT jsonb_agg(
                        jsonb_build_object('type', 'Feature',
                                            'properties', f->'properties',
                                            'geometry', jsonb_build_object( 'coordinates', f->'geometry'->'coordinates', 'type', 'LineString'))
                    ) INTO _geojson
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook l
                    WHERE l._from_time >= start_date::TIMESTAMPTZ
                        AND l._to_time <= end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
                        AND l.track_geojson IS NOT NULL
                    ORDER BY l._from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'LineString';
        ELSE
            SELECT jsonb_agg(
                        jsonb_build_object('type', 'Feature',
                                            'properties', f->'properties',
                                            'geometry', jsonb_build_object( 'coordinates', f->'geometry'->'coordinates', 'type', 'LineString'))
                    ) INTO _geojson
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook l
                    WHERE l.track_geojson IS NOT NULL
                    ORDER BY l._from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'LineString';
        END IF;
        -- Generate the GeoJSON with all moorages
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', _geojson ||                 ( SELECT
                    jsonb_agg(ST_AsGeoJSON(m.*)::JSONB) as moorages_geojson
                    FROM
                    ( SELECT
                        id,name,stay_code,
                        EXTRACT(DAY FROM justify_hours ( stay_duration )) AS Total_Stay,
                        geog
                        FROM api.moorages
                        WHERE geog IS NOT null
                    ) AS m
                ) ) INTO geojson;
    END;
$mapgl$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.mapgl_fn
    IS 'Get all logbook LineString alone with all moorages into a geojson to be process by DeckGL';

-- Refresh user_role permissions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;

-- Add cron_inactivity_fn, cleanup all data for inactive users and vessels
CREATE OR REPLACE FUNCTION public.cron_inactivity_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    no_activity_rec record;
    user_settings jsonb;
    total_metrics INTEGER;
    del_metrics INTEGER;
    out_json JSONB;
BEGIN
    -- List accounts with vessel inactivity for more than 200 DAYS
    -- List accounts with no vessel created for more than 200 DAYS
    -- List accounts with no vessel metadata for more than 200 DAYS
    -- Check for users and vessels with no activity for more than 200 days
    -- remove data and notify user
    RAISE NOTICE 'cron_inactivity_fn';
    FOR no_activity_rec in
        with accounts as (
            SELECT a.email,a.first,a.last,
            (a.updated_at < NOW() AT TIME ZONE 'UTC' - INTERVAL '200 DAYS') as no_account_activity,
            COALESCE((m.time < NOW() AT TIME ZONE 'UTC' - INTERVAL '200 DAYS'),true) as no_metadata_activity,
            m.vessel_id IS null as no_metadata_vesssel_id,
            m.time IS null as no_metadata_time,
            v.vessel_id IS null as no_vessel_vesssel_id,
            a.preferences->>'ip' as ip,v.name as user_vesssel,
            m.name as sk_vesssel,v.vessel_id as v_vessel_id,m.vessel_id as m_vessel_id,
            a.created_at as account_created,m.time as metadata_updated_at,
            v.created_at as vessel_created,v.updated_at as vessel_updated_at
            FROM auth.accounts a
            LEFT JOIN auth.vessels v ON v.owner_email = a.email
            LEFT JOIN api.metadata m ON v.vessel_id = m.vessel_id
            order by a.created_at asc
        )
        select * from accounts a where
            (no_account_activity is true
            or no_vessel_vesssel_id is true
            or no_metadata_activity is true
            or no_metadata_vesssel_id is true
            or no_metadata_time is true )
            ORDER BY a.account_created asc
    LOOP
        RAISE NOTICE '-> cron_inactivity_fn for [%]', no_activity_rec;
        SELECT json_build_object('email', no_activity_rec.email, 'recipient', no_activity_rec.first) into user_settings;
        RAISE NOTICE '-> debug cron_inactivity_fn user_settings [%]', user_settings;
        IF no_activity_rec.no_vessel_vesssel_id is true then
            PERFORM send_notification_fn('no_vessel'::TEXT, user_settings::JSONB);
        ELSIF no_activity_rec.no_metadata_vesssel_id is true then
            PERFORM send_notification_fn('no_metadata'::TEXT, user_settings::JSONB);
        ELSIF no_activity_rec.no_metadata_activity is true then
            PERFORM send_notification_fn('no_activity'::TEXT, user_settings::JSONB);
        ELSIF no_activity_rec.no_account_activity is true then
            PERFORM send_notification_fn('no_activity'::TEXT, user_settings::JSONB);
        END IF;
        -- Send notification
        PERFORM send_notification_fn('inactivity'::TEXT, user_settings::JSONB);
        -- Delete vessel metrics
        IF no_activity_rec.v_vessel_id IS NOT NULL THEN
            SELECT count(*) INTO total_metrics from api.metrics where vessel_id = no_activity_rec.v_vessel_id;
            WITH deleted AS (delete from api.metrics m where vessel_id = no_activity_rec.v_vessel_id RETURNING *) SELECT count(*) INTO del_metrics FROM deleted;
            SELECT jsonb_build_object('total_metrics', total_metrics, 'del_metrics', del_metrics) INTO out_json;
            RAISE NOTICE '-> debug cron_inactivity_fn [%]', out_json;
        END IF;
    END LOOP;
END;
$function$
;

COMMENT ON FUNCTION public.cron_inactivity_fn() IS 'init by pg_cron, check for vessel with no activity for more than 230 days then send notification';

-- Add cron_deactivated_fn, delete all data for inactive users and vessels
CREATE OR REPLACE FUNCTION public.cron_deactivated_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    no_activity_rec record;
    user_settings jsonb;
    del_vessel_data JSONB;
    del_meta INTEGER;
    del_vessel INTEGER;
    del_account INTEGER;
    out_json JSONB;
BEGIN
    RAISE NOTICE 'cron_deactivated_fn';
    -- List accounts with vessel inactivity for more than 230 DAYS
    -- List accounts with no vessel created for more than 230 DAYS
    -- List accounts with no vessel metadata for more than 230 DAYS
    -- Remove data and remove user and notify user
    FOR no_activity_rec in
        with accounts as (
            SELECT a.email,a.first,a.last,
            (a.updated_at < NOW() AT TIME ZONE 'UTC' - INTERVAL '230 DAYS') as no_account_activity,
            COALESCE((m.time < NOW() AT TIME ZONE 'UTC' - INTERVAL '230 DAYS'),true) as no_metadata_activity,
            m.vessel_id IS null as no_metadata_vesssel_id,
            m.time IS null as no_metadata_time,
            v.vessel_id IS null as no_vessel_vesssel_id,
            a.preferences->>'ip' as ip,v.name as user_vesssel,
            m.name as sk_vesssel,v.vessel_id as v_vessel_id,m.vessel_id as m_vessel_id,
            a.created_at as account_created,m.time as metadata_updated_at,
            v.created_at as vessel_created,v.updated_at as vessel_updated_at
            FROM auth.accounts a
            LEFT JOIN auth.vessels v ON v.owner_email = a.email
            LEFT JOIN api.metadata m ON v.vessel_id = m.vessel_id
            order by a.created_at asc
        )
        select * from accounts a where
            (no_account_activity is true
            or no_vessel_vesssel_id is true
            or no_metadata_activity is true
            or no_metadata_vesssel_id is true
            or no_metadata_time is true )
            ORDER BY a.account_created asc
    LOOP
        RAISE NOTICE '-> cron_deactivated_fn for [%]', no_activity_rec;
        SELECT json_build_object('email', no_activity_rec.email, 'recipient', no_activity_rec.first) into user_settings;
        RAISE NOTICE '-> debug cron_deactivated_fn user_settings [%]', user_settings;
        IF no_activity_rec.no_vessel_vesssel_id is true then
            PERFORM send_notification_fn('no_vessel'::TEXT, user_settings::JSONB);
        ELSIF no_activity_rec.no_metadata_vesssel_id is true then
            PERFORM send_notification_fn('no_metadata'::TEXT, user_settings::JSONB);
        ELSIF no_activity_rec.no_metadata_activity is true then
            PERFORM send_notification_fn('no_activity'::TEXT, user_settings::JSONB);
        ELSIF no_activity_rec.no_account_activity is true then
            PERFORM send_notification_fn('no_activity'::TEXT, user_settings::JSONB);
        END IF;
        -- Send notification
        PERFORM send_notification_fn('deactivated'::TEXT, user_settings::JSONB);
        -- Delete vessel data
        IF no_activity_rec.v_vessel_id IS NOT NULL THEN
            SELECT public.delete_vessel_fn(no_activity_rec.v_vessel_id) INTO del_vessel_data;
            WITH deleted AS (delete from api.metadata where vessel_id = no_activity_rec.v_vessel_id RETURNING *) SELECT count(*) INTO del_meta FROM deleted;
            SELECT jsonb_build_object('del_metadata', del_meta) || del_vessel_data INTO del_vessel_data;
            RAISE NOTICE '-> debug cron_deactivated_fn [%]', del_vessel_data;
        END IF;
        -- Delete account data
        WITH deleted AS (delete from auth.vessels where owner_email = no_activity_rec.email RETURNING *) SELECT count(*) INTO del_vessel FROM deleted;
        WITH deleted AS (delete from auth.accounts where email = no_activity_rec.email RETURNING *) SELECT count(*) INTO del_account FROM deleted;
        SELECT jsonb_build_object('del_account', del_account, 'del_vessel', del_vessel) || del_vessel_data INTO out_json;
        RAISE NOTICE '-> debug cron_deactivated_fn [%]', out_json;
        -- TODO remove keycloak and grafana provisioning
    END LOOP;
END;
$function$
;

COMMENT ON FUNCTION public.cron_deactivated_fn() IS 'init by pg_cron, check for vessel with no activity for more than 230 then send notification and delete account and vessel data';

-- Remove unused and duplicate function
DROP FUNCTION IF EXISTS public.cron_process_no_activity_fn;
DROP FUNCTION IF EXISTS public.cron_process_inactivity_fn;
DROP FUNCTION IF EXISTS public.cron_process_deactivated_fn;

-- Update version
UPDATE public.app_settings
	SET value='0.7.7'
	WHERE "name"='app.version';

\c postgres
