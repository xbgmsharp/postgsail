---------------------------------------------------------------------------
-- Copyright 2021-2024 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration July 2024
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Add video error notification message
INSERT INTO public.email_templates ("name",email_subject,email_content,pushover_title,pushover_message)
	VALUES ('video_error','PostgSail Video Error',E'Hey,\nSorry we could not generate your video.\nPlease reach out to debug and solve the issue.','PostgSail Video Error!',E'There has been an error with your video.');

-- CRON for new video notification
DROP FUNCTION IF EXISTS public.cron_process_new_video_fn;
CREATE FUNCTION public.cron_process_video_fn() RETURNS void AS $cron_process_video$
DECLARE
    process_rec record;
    metadata_rec record;
    video_settings jsonb;
    user_settings jsonb;
BEGIN
    -- Check for new event notification pending update
    RAISE NOTICE 'cron_process_video_fn';
    FOR process_rec in
        SELECT * FROM process_queue
            WHERE (channel = 'new_video' OR channel = 'error_video')
                AND processed IS NULL
            ORDER BY stored ASC
    LOOP
        RAISE NOTICE '-> cron_process_video_fn for [%]', process_rec.payload;
        SELECT * INTO metadata_rec
            FROM api.metadata
            WHERE vessel_id = process_rec.ref_id::TEXT;

        IF metadata_rec.vessel_id IS NULL OR metadata_rec.vessel_id = '' THEN
            RAISE WARNING '-> cron_process_video_fn invalid metadata record vessel_id %', vessel_id;
            RAISE EXCEPTION 'Invalid metadata'
                USING HINT = 'Unknown vessel_id';
            RETURN;
        END IF;
        PERFORM set_config('vessel.id', metadata_rec.vessel_id, false);
        RAISE DEBUG '-> DEBUG cron_process_video_fn vessel_id %', current_setting('vessel.id', false);
        -- Prepare notification, gather user settings
        SELECT json_build_object('video_link', CONCAT('https://videos.openplotter.cloud/', process_rec.payload)) into video_settings;
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(metadata_rec.vessel_id::TEXT);
        SELECT user_settings::JSONB || video_settings::JSONB into user_settings;
        RAISE DEBUG '-> DEBUG cron_process_video_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        -- Send notification
        IF process_rec.channel = 'new_video' THEN
            PERFORM send_notification_fn('video_ready'::TEXT, user_settings::JSONB);
        ELSE
            PERFORM send_notification_fn('video_error'::TEXT, user_settings::JSONB);
        END IF;
        -- update process_queue entry as processed
        UPDATE process_queue
            SET
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_video_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$cron_process_video$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_video_fn
    IS 'init by pg_cron to check for new video event pending notifications, if so perform process_notification_queue_fn';

-- Fix error when stateOfCharge is null. Make stateOfCharge null value assume to be charge 1.
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
                    SELECT user_settings::JSONB || ('{"alert": "low_outdoor_temperature_threshold value:'|| kelvinToCel(metric_rec.intemp) ||'"}'::text)::JSONB into user_settings;
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
                    SELECT user_settings::JSONB || ('{"alert": "low_outdoor_temperature_threshold value:'|| kelvinToCel(metric_rec.outtemp) ||'"}'::text)::JSONB into user_settings;
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
                    SELECT user_settings::JSONB || ('{"alert": "low_water_temperature_threshold value:'|| kelvinToCel(metric_rec.wattemp) ||'"}'::text)::JSONB into user_settings;
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
                    SELECT user_settings::JSONB || ('{"alert": "low_water_depth_threshold value:'|| metric_rec.watdepth ||'"}'::text)::JSONB into user_settings;
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
                    SELECT user_settings::JSONB || ('{"alert": "high_pressure_drop_threshold value:'|| metric_rec.pressure ||'"}'::text)::JSONB into user_settings;
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
                    SELECT user_settings::JSONB || ('{"alert": "high_wind_speed_threshold value:'|| metric_rec.wind ||'"}'::text)::JSONB into user_settings;
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
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = 'lacroix.francois@gmail.com';
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
                    SELECT user_settings::JSONB || ('{"alert": "low_battery_voltage_threshold value:'|| metric_rec.voltage ||'"}'::text)::JSONB into user_settings;
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
                    SELECT user_settings::JSONB || ('{"alert": "low_battery_charge_threshold value:'|| (metric_rec.charge*100) ||'"}'::text)::JSONB into user_settings;
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

-- Fix error: None of these media types are available: text/xml
DROP FUNCTION IF EXISTS api.export_logbooks_gpx_fn;
CREATE OR REPLACE FUNCTION api.export_logbooks_gpx_fn(
    IN start_log INTEGER DEFAULT NULL,
    IN end_log INTEGER DEFAULT NULL) RETURNS "text/xml"
AS $export_logbooks_gpx$
    declare
        merged_jsonb jsonb;
        app_settings jsonb;
    BEGIN
        -- Merge GIS track_geom of geometry type Point into a jsonb array format
        IF start_log IS NOT NULL AND public.isnumeric(start_log::text) AND public.isnumeric(end_log::text) THEN
            SELECT jsonb_agg(
                        jsonb_build_object('coordinates', f->'geometry'->'coordinates', 'time', f->'properties'->>'time')
                    ) INTO merged_jsonb
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook
                    WHERE id >= start_log
                        AND id <= end_log
                        AND track_geojson IS NOT NULL
                    ORDER BY _from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'Point';
        ELSE
            SELECT jsonb_agg(
                        jsonb_build_object('coordinates', f->'geometry'->'coordinates', 'time', f->'properties'->>'time')
                    ) INTO merged_jsonb
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook
                    WHERE track_geojson IS NOT NULL
                    ORDER BY _from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'Point';
        END IF;
        --RAISE WARNING '-> export_logbooks_gpx_fn _jsonb %' , _jsonb;
        -- Gather url from app settings
        app_settings := get_app_url_fn();
        --RAISE WARNING '-> export_logbooks_gpx_fn app_settings %', app_settings;
        -- Generate GPX XML, extract Point features from geojson.
        RETURN xmlelement(name gpx,
                            xmlattributes(  '1.1' as version,
                                            'PostgSAIL' as creator,
                                            'http://www.topografix.com/GPX/1/1' as xmlns,
                                            'http://www.opencpn.org' as "xmlns:opencpn",
                                            app_settings->>'app.url' as "xmlns:postgsail"),
                xmlelement(name metadata,
                    xmlelement(name link, xmlattributes(app_settings->>'app.url' as href),
                        xmlelement(name text, 'PostgSail'))),
                xmlelement(name trk,
                    xmlelement(name name, 'logbook name'),
                    xmlelement(name trkseg, xmlagg(
                                                xmlelement(name trkpt,
                                                    xmlattributes(features->'coordinates'->1 as lat, features->'coordinates'->0 as lon),
                                                        xmlelement(name time, features->'properties'->>'time')
                                                )))))::pg_catalog.xml
            FROM jsonb_array_elements(merged_jsonb) AS features;
    END;
$export_logbooks_gpx$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.export_logbooks_gpx_fn
    IS 'Export a logs entries to GPX XML format';

-- Add export logbooks as png
DROP FUNCTION IF EXISTS public.qgis_bbox_trip_py_fn;
CREATE OR REPLACE FUNCTION public.qgis_bbox_trip_py_fn(IN _str_to_parse TEXT DEFAULT NULL, OUT bbox TEXT)
AS $qgis_bbox_trip_py$
	plpy.notice('qgis_bbox_trip_py_fn _str_to_parse [{}]'.format(_str_to_parse))
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
	    plpy.warning('Failed to get sql qgis_bbox_trip_py_fn log_id [{}], extent [{}]'.format(log_id, log_extent))
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

DROP FUNCTION IF EXISTS public.grafana_py_fn;
-- Update grafana provisioning, ERROR:  KeyError: 'secureJsonFields'
CREATE OR REPLACE FUNCTION public.grafana_py_fn(_v_name text, _v_id text, _u_email text, app jsonb)
 RETURNS void
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
AS $function$
	"""
	https://grafana.com/docs/grafana/latest/developers/http_api/
	Create organization base on vessel name
	Create user base on user email
	Add user to organization
	Add data_source to organization
	Add dashboard to organization
    Update organization preferences
	"""
	import requests
	import json
	import re

	grafana_uri = None
	if 'app.grafana_admin_uri' in app and app['app.grafana_admin_uri']:
		grafana_uri = app['app.grafana_admin_uri']
	else:
		plpy.error('Error no grafana_admin_uri defined, check app settings')
		return None

	b_name = None
	if not _v_name:
		b_name = _v_id
	else:
		b_name = _v_name

	# add vessel org
	headers = {'User-Agent': 'PostgSail', 'From': 'xbgmsharp@gmail.com',
	'Accept': 'application/json', 'Content-Type': 'application/json'}
	path = 'api/orgs'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	data_dict = {'name':b_name}
	data = json.dumps(data_dict)
	r = requests.post(url, data=data, headers=headers)
	#print(r.text)
	plpy.notice(r.json())
	if r.status_code == 200 and "orgId" in r.json():
		org_id = r.json()['orgId']
	else:
		plpy.error('Error grafana add vessel org {req} - {res}'.format(req=data_dict,res=r.json()))
		return none

	# add user to vessel org
	path = 'api/admin/users'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	data_dict = {'orgId':org_id, 'email':_u_email, 'password':'asupersecretpassword'}
	data = json.dumps(data_dict)
	r = requests.post(url, data=data, headers=headers)
	#print(r.text)
	plpy.notice(r.json())
	if r.status_code == 200 and "id" in r.json():
		user_id = r.json()['id']
	else:
		plpy.error('Error grafana add user to vessel org')
		return

	# read data_source
	path = 'api/datasources/1'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	r = requests.get(url, headers=headers)
	#print(r.text)
	plpy.notice(r.json())
	data_source = r.json()
	data_source['id'] = 0
	data_source['orgId'] = org_id
	data_source['uid'] = "ds_" + _v_id
	data_source['name'] = "ds_" + _v_id
	data_source['secureJsonData'] = {}
	data_source['secureJsonData']['password'] = 'mysecretpassword'
	data_source['readOnly'] = True
	if "secureJsonFields" in data_source:
		del data_source['secureJsonFields']

	# add data_source to vessel org
	path = 'api/datasources'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	data = json.dumps(data_source)
	headers['X-Grafana-Org-Id'] = str(org_id)
	r = requests.post(url, data=data, headers=headers)
	plpy.notice(r.json())
	del headers['X-Grafana-Org-Id']
	if r.status_code != 200 and "id" not in r.json():
		plpy.error('Error grafana add data_source to vessel org')
		return

	dashboards_tpl = [ 'pgsail_tpl_electrical', 'pgsail_tpl_logbook', 'pgsail_tpl_monitor', 'pgsail_tpl_rpi', 'pgsail_tpl_solar', 'pgsail_tpl_weather', 'pgsail_tpl_home']
	for dashboard in dashboards_tpl:
		# read dashboard template by uid
		path = 'api/dashboards/uid'
		url = f'{grafana_uri}/{path}/{dashboard}'.format(grafana_uri,path,dashboard)
		if 'X-Grafana-Org-Id' in headers:
			del headers['X-Grafana-Org-Id']
		r = requests.get(url, headers=headers)
		plpy.notice(r.json())
		if r.status_code != 200 and "id" not in r.json():
			plpy.error('Error grafana read dashboard template')
			return
		new_dashboard = r.json()
		del new_dashboard['meta']
		new_dashboard['dashboard']['version'] = 0
		new_dashboard['dashboard']['id'] = 0
		new_uid = re.sub(r'pgsail_tpl_(.*)', r'postgsail_\1', new_dashboard['dashboard']['uid'])
		new_dashboard['dashboard']['uid'] = f'{new_uid}_{_v_id}'.format(new_uid,_v_id)
		# add dashboard to vessel org
		path = 'api/dashboards/db'
		url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
		data = json.dumps(new_dashboard)
		new_data = data.replace('PCC52D03280B7034C', data_source['uid'])
		headers['X-Grafana-Org-Id'] = str(org_id)
		r = requests.post(url, data=new_data, headers=headers)
		plpy.notice(r.json())
		if r.status_code != 200 and "id" not in r.json():
			plpy.error('Error grafana add dashboard to vessel org')
			return

	# Update Org Prefs
	path = 'api/org/preferences'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	home_dashboard = {}
	home_dashboard['timezone'] = 'utc'
	home_dashboard['homeDashboardUID'] = f'postgsail_home_{_v_id}'.format(_v_id)
	data = json.dumps(home_dashboard)
	headers['X-Grafana-Org-Id'] = str(org_id)
	r = requests.patch(url, data=data, headers=headers)
	plpy.notice(r.json())
	if r.status_code != 200:
		plpy.error('Error grafana update org preferences')
		return

	plpy.notice('Done')
$function$
;
COMMENT ON FUNCTION public.grafana_py_fn(text, text, text, jsonb) IS 'Grafana Organization,User,data_source,dashboards provisioning via HTTP API using plpython3u';

-- Add missing comment on function cron_process_no_activity_fn
COMMENT ON FUNCTION
    public.cron_process_no_activity_fn
    IS 'init by pg_cron, check for vessel with no activity for more than 230 days then send notification';

-- Update grafana,qgis,api role SQL connection to 30
ALTER ROLE grafana WITH NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 30 LOGIN;
ALTER ROLE api_anonymous WITH NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 30 LOGIN;
ALTER ROLE qgis_role WITH NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 30 LOGIN;

-- Create qgis schema for qgis projects
CREATE SCHEMA IF NOT EXISTS qgis;
COMMENT ON SCHEMA qgis IS 'Hold qgis_projects';
GRANT USAGE ON SCHEMA qgis TO qgis_role;
CREATE TABLE qgis.qgis_projects (
	"name" text NOT NULL,
	metadata jsonb NULL,
	"content" bytea NULL,
	CONSTRAINT qgis_projects_pkey PRIMARY KEY (name)
);
-- Description
COMMENT ON TABLE
    qgis.qgis_projects
    IS 'Store qgis projects using QGIS-Server or QGIS-Desktop from https://qgis.org/';
GRANT SELECT,INSERT,UPDATE,DELETE ON TABLE qgis.qgis_projects TO qgis_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO qgis_role;

-- allow anonymous access to tbl and views
GRANT SELECT ON ALL TABLES IN SCHEMA api TO api_anonymous;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO api_anonymous;
-- Allow EXECUTE on all FUNCTIONS on API and public schema to user_role
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
-- Allow EXECUTE on all FUNCTIONS on public schema to vessel_role
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO vessel_role;

-- Update version
UPDATE public.app_settings
	SET value='0.7.5'
	WHERE "name"='app.version';

\c postgres

-- Update video cronjob
UPDATE cron.job
	SET command='select public.cron_process_video_fn()'
	WHERE jobname = 'cron_new_video';
UPDATE cron.job
	SET jobname='cron_video'
	WHERE command='select public.cron_process_video_fn()';