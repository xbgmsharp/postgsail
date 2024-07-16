---------------------------------------------------------------------------
-- Copyright 2021-2024 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration June 2024
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Add video timelapse notification message
INSERT INTO public.email_templates ("name",email_subject,email_content,pushover_title,pushover_message)
	VALUES ('video_ready','PostgSail Video ready',E'Hey,\nYour video is available at __VIDEO_LINK__.\nPlease make sure you download your video as it will delete in 7 days.','PostgSail Video ready!',E'Your video is ready __VIDEO_LINK__.');

-- Generate and request the logbook image url to be cache on QGIS server.
DROP FUNCTION IF EXISTS public.qgis_getmap_py_fn;
CREATE OR REPLACE FUNCTION public.qgis_getmap_py_fn(IN vessel_id TEXT DEFAULT NULL, IN log_id NUMERIC DEFAULT NULL, IN extent TEXT DEFAULT NULL, IN logs_url BOOLEAN DEFAULT False) RETURNS VOID
AS $qgis_getmap_py$
	import requests

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

	def adjust_image_size_to_bbox(extent, width, height):
	    min_x, min_y, max_x, max_y = extent
	    bbox_aspect_ratio = (max_x - min_x) / (max_y - min_y)
	    image_aspect_ratio = width / height
	
	    if bbox_aspect_ratio > image_aspect_ratio:
	        # Adjust height to match aspect ratio
	        height = width / bbox_aspect_ratio
	    else:
	        # Adjust width to match aspect ratio
	        width = height * bbox_aspect_ratio
	
	    return int(width), int(height)

	def calculate_width(extent, fixed_height):
	    min_x, min_y, max_x, max_y = extent
	    bbox_aspect_ratio = (max_x - min_x) / (max_y - min_y)
	    width = fixed_height * bbox_aspect_ratio
	    return int(width)

	def adjust_bbox_to_fixed_size(scaled_extent, fixed_width, fixed_height):
	    min_x, min_y, max_x, max_y = scaled_extent
	    bbox_width = max_x - min_x
	    bbox_height = max_y - min_y
	    bbox_aspect_ratio = bbox_width / bbox_height
	    image_aspect_ratio = fixed_width / fixed_height
	
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

	def generate_getmap_url(server_url, project_path, layer_name, extent, width=1080, height=566, crs="EPSG:3857", format="image/png"):
	    min_x, min_y, max_x, max_y = extent
	    bbox = f"{min_x},{min_y},{max_x},{max_y}"

	    # Adjust image size to match BBOX aspect ratio
	    #width, height = adjust_image_size_to_bbox(extent, width, height)

	    # Calculate width to maintain aspect ratio with fixed height
	    #width = calculate_width(extent, height)

	    url = (
	        f"{server_url}?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&FORMAT={format}&CRS={crs}"
	        f"&BBOX={bbox}&WIDTH={width}&HEIGHT={height}&LAYERS={layer_name}&MAP={project_path}"
	    )
	    return url

	if logs_url == False:
		server_url = f"https://gis.openplotter.cloud/log_{vessel_id}_{log_id}.png".format(vessel_id, log_id)
	else:
		server_url = f"https://gis.openplotter.cloud/logs_{vessel_id}_{log_id}.png".format(vessel_id, log_id)
	project_path = "/projects/postgsail5.qgz"
	layer_name = "OpenStreetMap,SQLLayer"
	#plpy.notice('qgis_getmap_py vessel_id [{}], log_id [{}], extent [{}]'.format(vessel_id, log_id, extent))

	# Parse extent and scale factor
	scaled_extent = apply_scale_factor(parse_extent_from_db(extent))
	#plpy.notice('qgis_getmap_py scaled_extent [{}]'.format(scaled_extent))

	fixed_width = 1080
	fixed_height = 566
	adjusted_extent = adjust_bbox_to_fixed_size(scaled_extent, fixed_width, fixed_height)
	#plpy.notice('qgis_getmap_py adjusted_extent [{}]'.format(adjusted_extent))

	getmap_url = generate_getmap_url(server_url, project_path, layer_name, adjusted_extent)
	if logs_url == False:
		filter_url = f"{getmap_url}&FILTER=SQLLayer:\"vessel_id\" = '{vessel_id}' AND \"id\" = {log_id}".format(getmap_url, vessel_id, log_id)
	else:
		filter_url = f"{getmap_url}&FILTER=SQLLayer:\"vessel_id\" = '{vessel_id}'".format(getmap_url, vessel_id)
	#plpy.notice('qgis_getmap_py getmap_url [{}]'.format(filter_url))

	# Fetch image to be cache in qgis server
	headers = {"User-Agent": "PostgSail", "From": "xbgmsharp@gmail.com"}
	r = requests.get(filter_url, headers=headers, timeout=100)
	# Parse response
	if r.status_code != 200:
		plpy.warning('Failed to get WMS image, url[{}]'.format(filter_url))
$qgis_getmap_py$ LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.qgis_getmap_py_fn
    IS 'Generate a log map, to generate the cache data for faster access later';

-- Generate the logbook extent for the logbook image to access the QGIS server.
DROP FUNCTION IF EXISTS public.qgis_bbox_py_fn;
CREATE OR REPLACE FUNCTION public.qgis_bbox_py_fn(IN vessel_id TEXT DEFAULT NULL, IN log_id NUMERIC DEFAULT NULL, IN width NUMERIC DEFAULT 1080, IN height NUMERIC DEFAULT 566, IN scaleout BOOLEAN DEFAULT True, OUT bbox TEXT)
AS $qgis_bbox_py$
	log_extent = None
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

	if not log_extent:
	    plpy.warning('Failed to get sql qgis_bbox_py log_id [{}], extent [{}]'.format(log_id, log_extent))
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

-- qgis_role user and role with login, read-only on auth.accounts, limit 20 connections
CREATE ROLE qgis_role WITH NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 20 LOGIN PASSWORD 'mysecretpassword';
COMMENT ON ROLE qgis_role IS
    'Role use by QGIS server and Apache to connect and lookup the logbook table.';
-- Allow read on VIEWS on API schema
GRANT USAGE ON SCHEMA api TO qgis_role;
GRANT SELECT ON TABLE api.logbook TO qgis_role;
GRANT USAGE ON SCHEMA public TO qgis_role;
-- For all postgis fn, st_extent, st_transform
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO qgis_role;
-- Allow qgis_role to select all logbook records
CREATE POLICY logbook_qgis_role ON api.logbook TO qgis_role
    USING (true)
    WITH CHECK (false);

-- Add support for HTML email with image inline for logbook
-- Add support for video link for maplapse
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
        email_content = email_content.replace('__LOGBOOK_NAME__', _user['logbook_name'])
    if 'logbook_link' in _user and _user['logbook_link']:
        email_content = email_content.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'logbook_img' in _user and _user['logbook_img']:
        email_content = email_content.replace('__LOGBOOK_IMG__', str(_user['logbook_img']))
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

-- Add vessel_id key, expose vessel_id
DROP FUNCTION IF EXISTS api.vessel_fn;
CREATE OR REPLACE FUNCTION api.vessel_fn(OUT vessel JSON) RETURNS JSON
AS $vessel$
    DECLARE
    BEGIN
        SELECT
            jsonb_build_object(
                'name', coalesce(m.name, null),
                'mmsi', coalesce(m.mmsi, null),
                'vessel_id', m.vessel_id,
                'created_at', v.created_at,
                'first_contact', coalesce(m.created_at, null),
                'last_contact', coalesce(m.time, null),
                'geojson', coalesce(ST_AsGeoJSON(geojson_t.*)::json, null)
            )::jsonb || api.vessel_details_fn()::jsonb
            INTO vessel
            FROM auth.vessels v, api.metadata m, 
                (	select
                        current_setting('vessel.name') as name,
                        time,
                        courseovergroundtrue,
                        speedoverground,
                        anglespeedapparent,
                        longitude,latitude,
                        st_makepoint(longitude,latitude) AS geo_point
                        FROM api.metrics
                        WHERE
                            latitude IS NOT NULL
                            AND longitude IS NOT NULL
                            AND vessel_id = current_setting('vessel.id', false)
                        ORDER BY time DESC LIMIT 1
                ) AS geojson_t
            WHERE
                m.vessel_id = current_setting('vessel.id')
                AND m.vessel_id = v.vessel_id;
        --RAISE notice 'api.vessel_fn %', obj;
    END;
$vessel$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.vessel_fn
    IS 'Expose vessel details to API';

-- Update pending new logbook from process queue
DROP FUNCTION IF EXISTS public.process_post_logbook_fn;
CREATE OR REPLACE FUNCTION public.process_post_logbook_fn(IN _id integer) RETURNS void AS $process_post_logbook_queue$
    DECLARE
        logbook_rec record;
        log_settings jsonb;
        user_settings jsonb;
        extra_json jsonb;
        log_img_url text;
        logs_img_url text;
        extent_bbox text;
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
        SELECT ST_Extent(ST_Transform(logbook_rec.track_geom, 3857))::TEXT AS envelope INTO extent_bbox FROM api.logbook WHERE id = logbook_rec.id;
        PERFORM public.qgis_getmap_py_fn(logbook_rec.vessel_id::TEXT, logbook_rec.id, extent_bbox::TEXT, False);
        -- Generate logs image map name from QGIS
        WITH merged AS (
            SELECT ST_Union(logbook_rec.track_geom) AS merged_geometry
                FROM api.logbook WHERE vessel_id = logbook_rec.vessel_id
        )
        SELECT ST_Extent(ST_Transform(merged_geometry, 3857))::TEXT AS envelope INTO extent_bbox FROM merged;
        SELECT CONCAT('logs_', logbook_rec.vessel_id::TEXT, '_', logbook_rec.id, '.png') INTO logs_img_url;
        PERFORM public.qgis_getmap_py_fn(logbook_rec.vessel_id::TEXT, logbook_rec.id, extent_bbox::TEXT, True);

        -- Prepare notification, gather user settings
        SELECT json_build_object('logbook_name', logbook_rec.name, 'logbook_link', logbook_rec.id, 'logbook_img', log_img_url) INTO log_settings;
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
    IS 'Generate QGIS image and Notify user for new logbook.';

-- Check for new logbook pending notification
DROP FUNCTION IF EXISTS public.cron_process_post_logbook_fn;
CREATE FUNCTION public.cron_process_post_logbook_fn() RETURNS void AS $$
DECLARE
    process_rec record;
BEGIN
    -- Check for new logbook pending update
    RAISE NOTICE 'cron_process_post_logbook_fn init loop';
    FOR process_rec in
        SELECT * FROM process_queue
            WHERE channel = 'post_logbook' AND processed IS NULL
            ORDER BY stored ASC LIMIT 100
    LOOP
        RAISE NOTICE 'cron_process_post_logbook_fn processing queue [%] for logbook id [%]', process_rec.id, process_rec.payload;
        -- update logbook
        PERFORM process_post_logbook_fn(process_rec.payload::INTEGER);
        -- update process_queue table , processed
        UPDATE process_queue
            SET
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE 'cron_process_post_logbook_fn processed queue [%] for logbook id [%]', process_rec.id, process_rec.payload;
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_post_logbook_fn
    IS 'init by pg_cron to check for new logbook pending qgis and notification, after process_new_logbook_fn';

DROP FUNCTION IF EXISTS public.run_cron_jobs;
CREATE FUNCTION public.run_cron_jobs() RETURNS void AS $$
BEGIN
    -- In correct order
    perform public.cron_process_new_notification_fn();
    perform public.cron_process_monitor_online_fn();
    --perform public.cron_process_grafana_fn();
    perform public.cron_process_pre_logbook_fn();
    perform public.cron_process_new_logbook_fn();
    perform public.cron_process_post_logbook_fn();
    perform public.cron_process_new_stay_fn();
    --perform public.cron_process_new_moorage_fn();
    perform public.cron_process_monitor_offline_fn();
END
$$ language plpgsql;

DROP VIEW IF EXISTS api.eventlogs_view;
CREATE VIEW api.eventlogs_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT pq.*
        FROM public.process_queue pq
        WHERE channel <> 'pre_logbook' 
            AND channel <> 'post_logbook'
            AND (ref_id = current_setting('user.id', true)
            OR ref_id = current_setting('vessel.id', true))
        ORDER BY id ASC;
-- Description
COMMENT ON VIEW
    api.eventlogs_view
    IS 'Event logs view';

-- CRON for new video notification
DROP FUNCTION IF EXISTS public.cron_process_new_video_fn;
CREATE FUNCTION public.cron_process_new_video_fn() RETURNS void AS $$
declare
    process_rec record;
    metadata_rec record;
    video_settings jsonb;
    user_settings jsonb;
begin
    -- Check for new event notification pending update
    RAISE NOTICE 'cron_process_new_video_fn';
    FOR process_rec in
        SELECT * FROM process_queue
            WHERE channel = 'new_video'
                AND processed IS NULL
            ORDER BY stored ASC
    LOOP
        RAISE NOTICE '-> cron_process_new_video_fn for [%]', process_rec.payload;
        SELECT * INTO metadata_rec
            FROM api.metadata
            WHERE vessel_id = process_rec.ref_id::TEXT;

        IF metadata_rec.vessel_id IS NULL OR metadata_rec.vessel_id = '' THEN
            RAISE WARNING '-> cron_process_new_video_fn invalid metadata record vessel_id %', vessel_id;
            RAISE EXCEPTION 'Invalid metadata'
                USING HINT = 'Unknown vessel_id';
            RETURN;
        END IF;
        PERFORM set_config('vessel.id', metadata_rec.vessel_id, false);
        RAISE DEBUG '-> DEBUG cron_process_new_video_fn vessel_id %', current_setting('vessel.id', false);
        -- Prepare notification, gather user settings
        SELECT json_build_object('video_link', CONCAT('https://videos.openplotter.cloud/', process_rec.payload)) into video_settings;
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(metadata_rec.vessel_id::TEXT);
        SELECT user_settings::JSONB || video_settings::JSONB into user_settings;
        RAISE DEBUG '-> DEBUG cron_process_new_video_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('video_ready'::TEXT, user_settings::JSONB);
        -- update process_queue entry as processed
        UPDATE process_queue
            SET
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_new_video_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_new_video_fn
    IS 'init by pg_cron to check for new video event pending notifications, if so perform process_notification_queue_fn';

-- Add support for video link for maplapse
DROP FUNCTION IF EXISTS public.send_pushover_py_fn;
CREATE OR REPLACE FUNCTION public.send_pushover_py_fn(IN message_type TEXT, IN _user JSONB, IN app JSONB) RETURNS void
AS $send_pushover_py$
    """
    https://pushover.net/api#messages
    Send a notification to a pushover user
    """
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
    if 'video_link' in _user and _user['video_link']:
        pushover_message = pushover_message.replace('__VIDEO_LINK__', str( _user['video_link']))
    if 'recipient' in _user and _user['recipient']:
        pushover_message = pushover_message.replace('__RECIPIENT__', _user['recipient'])
    if 'boat' in _user and _user['boat']:
        pushover_message = pushover_message.replace('__BOAT__', _user['boat'])
    if 'badge' in _user and _user['badge']:
        pushover_message = pushover_message.replace('__BADGE_NAME__', _user['badge'])
    if 'alert' in _user and _user['alert']:
        pushover_message = pushover_message.replace('__ALERT__', _user['alert'])

    if 'app.url' in app and app['app.url']:
        pushover_message = pushover_message.replace('__APP_URL__', app['app.url'])

    pushover_token = None
    if 'app.pushover_app_token' in app and app['app.pushover_app_token']:
        pushover_token = app['app.pushover_app_token']
    else:
        plpy.error('Error no pushover token defined, check app settings')
        return None
    pushover_user = None
    if 'pushover_user_key' in _user and _user['pushover_user_key']:
        pushover_user = _user['pushover_user_key']
    else:
        plpy.error('Error no pushover user token defined, check user settings')
        return None

    if message_type == 'logbook' and 'logbook_img' in _user and _user['logbook_img']:
        # Send notification with gis image logbook as attachment
        img_url = 'https://gis.openplotter.cloud/{}'.format(str(_user['logbook_img']))
        response = requests.get(img_url, stream=True)
        if response.status_code == 200:
            r = requests.post("https://api.pushover.net/1/messages.json", data = {
                "token": pushover_token,
                "user": pushover_user,
                "title": pushover_title,
                "message": pushover_message
            }, files = {
                "attachment": (str(_user['logbook_img']), response.raw.data, "image/png")
            })
    else:
        r = requests.post("https://api.pushover.net/1/messages.json", data = {
                "token": pushover_token,
                "user": pushover_user,
                "title": pushover_title,
                "message": pushover_message
        })

    #print(r.text)
    # Return ?? or None if not found
    #plpy.notice('Sent pushover successfully to [{}] [{}]'.format(r.text, r.status_code))
    if r.status_code == 200:
        plpy.notice('Sent pushover successfully to [{}] [{}] [{}]'.format(pushover_user, pushover_title, r.text))
    else:
        plpy.error('Failed to send pushover')
    return None
$send_pushover_py$ TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.send_pushover_py_fn
    IS 'Send pushover notification using plpython3u';

-- Add support for video link for maplapse
DROP FUNCTION IF EXISTS public.send_telegram_py_fn;
CREATE OR REPLACE FUNCTION public.send_telegram_py_fn(IN message_type TEXT, IN _user JSONB, IN app JSONB) RETURNS void
AS $send_telegram_py$
    """
    https://core.telegram.org/bots/api#sendmessage
    Send a message to a telegram user or group specified on chatId
    chat_id must be a number!
    """
    import requests
    import json

    # Use the shared cache to avoid preparing the email metadata
    if message_type in SD:
        plan = SD[message_type]
    # A prepared statement from Python
    else:
        plan = plpy.prepare("SELECT * FROM email_templates WHERE name = $1", ["text"])
        SD[message_type] = plan

    # Execute the statement with the message_type param and limit to 1 result
    rv = plpy.execute(plan, [message_type], 1)
    telegram_title = rv[0]['pushover_title']
    telegram_message = rv[0]['pushover_message']

    # Replace fields using input jsonb obj
    if 'logbook_name' in _user and _user['logbook_name']:
        telegram_message = telegram_message.replace('__LOGBOOK_NAME__', _user['logbook_name'])
    if 'logbook_link' in _user and _user['logbook_link']:
        telegram_message = telegram_message.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'video_link' in _user and _user['video_link']:
        telegram_message = telegram_message.replace('__VIDEO_LINK__', str( _user['video_link']))
    if 'recipient' in _user and _user['recipient']:
        telegram_message = telegram_message.replace('__RECIPIENT__', _user['recipient'])
    if 'boat' in _user and _user['boat']:
        telegram_message = telegram_message.replace('__BOAT__', _user['boat'])
    if 'badge' in _user and _user['badge']:
        telegram_message = telegram_message.replace('__BADGE_NAME__', _user['badge'])
    if 'alert' in _user and _user['alert']:
        telegram_message = telegram_message.replace('__ALERT__', _user['alert'])

    if 'app.url' in app and app['app.url']:
        telegram_message = telegram_message.replace('__APP_URL__', app['app.url'])

    telegram_token = None
    if 'app.telegram_bot_token' in app and app['app.telegram_bot_token']:
        telegram_token = app['app.telegram_bot_token']
    else:
        plpy.error('Error no telegram token defined, check app settings')
        return None
    telegram_chat_id = None
    if 'telegram_chat_id' in _user and _user['telegram_chat_id']:
        telegram_chat_id = _user['telegram_chat_id']
    else:
        plpy.error('Error no telegram user token defined, check user settings')
        return None

    # sendMessage via requests
    headers = {'Content-Type': 'application/json',
            'Proxy-Authorization': 'Basic base64'}
    data_dict = {'chat_id': telegram_chat_id,
                'text': telegram_message,
                'parse_mode': 'HTML',
                'disable_notification': False}
    data = json.dumps(data_dict)
    url = f'https://api.telegram.org/bot{telegram_token}/sendMessage'
    r = requests.post(url, data=data, headers=headers)
    if message_type == 'logbook' and 'logbook_img' in _user and _user['logbook_img']:
        # Send gis image logbook
        # https://core.telegram.org/bots/api#sendphoto
        data_dict['photo'] = 'https://gis.openplotter.cloud/{}'.format(str(_user['logbook_img']))
        del data_dict['text']
        data = json.dumps(data_dict)
        url = f'https://api.telegram.org/bot{telegram_token}/sendPhoto'
        r = requests.post(url, data=data, headers=headers)

    #print(r.text)
    # Return something boolean?
    #plpy.notice('Sent telegram successfully to [{}] [{}]'.format(r.text, r.status_code))
    if r.status_code == 200:
        plpy.notice('Sent telegram successfully to [{}] [{}] [{}]'.format(telegram_chat_id, telegram_title, r.text))
    else:
        plpy.error('Failed to send telegram')
    return None
$send_telegram_py$ TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.send_telegram_py_fn
    IS 'Send a message to a telegram user or group specified on chatId using plpython3u';

-- Add maplapse video record in queue
DROP FUNCTION IF EXISTS api.maplapse_record_fn;
CREATE OR REPLACE FUNCTION api.maplapse_record_fn(IN maplapse TEXT) RETURNS BOOLEAN
AS $maplapse_record$
    BEGIN
        -- payload: 'Bromera,?start_log=8430&end_log=8491&height=100vh'
        IF maplapse ~ '^(\w+)\,\?(start_log=\d+).*$' then
            INSERT INTO process_queue (channel, payload, stored, ref_id)
                VALUES ('maplapse_video', maplapse, NOW(), current_setting('vessel.id', true));
            RETURN True;
        ELSE
            RETURN False;
        END IF;
    END;
$maplapse_record$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.maplapse_record_fn
    IS 'Add maplapse video record in queue';

CREATE ROLE maplapse_role WITH NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 10 LOGIN PASSWORD 'mysecretpassword';
COMMENT ON ROLE maplapse_role IS
    'Role use by maplapse external cronjob to connect and lookup the process_queue table.';
GRANT USAGE ON SCHEMA public TO maplapse_role;
GRANT SELECT,UPDATE,INSERT ON TABLE public.process_queue TO maplapse_role;
GRANT USAGE, SELECT ON SEQUENCE public.process_queue_id_seq TO maplapse_role;
-- Allow maplapse_role to select,update,insert on tbl process_queue
CREATE POLICY public_maplapse_role ON public.process_queue TO maplapse_role
    USING (true)
    WITH CHECK (true);

-- Allow to execute fn for user_role and grafana
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO grafana;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO grafana;
GRANT SELECT ON TABLE api.eventlogs_view TO user_role;

-- Update grafana role SQl connection to 30
ALTER ROLE grafana WITH NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 30 LOGIN;

-- Alter moorages table with default duration of 0.
ALTER TABLE api.moorages ALTER COLUMN stay_duration SET DEFAULT 'PT0S';
-- Update moorage_view to default with duration of 0
DROP VIEW IF EXISTS api.moorage_view;
CREATE OR REPLACE VIEW api.moorage_view WITH (security_invoker=true,security_barrier=true) AS -- TODO
    SELECT id,
        m.name AS Name,
        sa.description AS Default_Stay,
        sa.stay_code AS Default_Stay_Id,
        m.home_flag AS Home,
        EXTRACT(DAY FROM justify_hours ( COALESCE(m.stay_duration, 'PT0S') )) AS Total_Stay,
        COALESCE(m.stay_duration, 'PT0S') AS Total_Duration,
        m.reference_count AS Arrivals_Departures,
        m.notes
--        m.geog
    FROM api.moorages m, api.stays_at sa
-- m.stay_duration is only process on a stay
-- default with duration of 0sec
    WHERE geog IS NOT NULL
        AND m.stay_code = sa.stay_code;
-- Description
COMMENT ON VIEW
    api.moorage_view
    IS 'Moorage details web view';

-- Update version
UPDATE public.app_settings
	SET value='0.7.3'
	WHERE "name"='app.version';

\c postgres

-- Create a every 7 minutes for cron_process_post_logbook_fn
SELECT cron.schedule('cron_post_logbook', '*/7 * * * *', 'select public.cron_process_post_logbook_fn()');
UPDATE cron.job SET database = 'signalk' where jobname = 'cron_post_logbook';
-- Create a every 15 minutes for cron_process_post_logbook_fn
SELECT cron.schedule('cron_new_video', '*/15 * * * *', 'select public.cron_process_new_video_fn()');
UPDATE cron.job SET database = 'signalk' where jobname = 'cron_new_video';
