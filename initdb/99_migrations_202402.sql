---------------------------------------------------------------------------
-- TODO
--
----------------------------------------
----- TODO --------------
----------------------------------------

-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Update email_templates
--INSERT INTO public.email_templates ("name",email_subject,email_content,pushover_title,pushover_message)
--	VALUES ('windy','PostgSail Windy Weather station',E'Hello __RECIPIENT__,\nCongratulations! Your boat is now a Windy Weather station.\nSee more details at __APP_URL__/windy\nHappy sailing!\nFrancois','PostgSail Windy!',E'Congratulations!\nYour boat is now a Windy Weather station.\nSee more details at __APP_URL__/windy\n');
--INSERT INTO public.email_templates ("name",email_subject,email_content,pushover_title,pushover_message)
--VALUES ('alert','PostgSail Alert',E'Hello __RECIPIENT__,\nWe detected an alert __ALERT__.\nSee more details at __APP_URL__\nStay safe.\nFrancois','PostgSail Alert!',E'Congratulations!\nWe detected an alert __ALERT__.\n');

INSERT INTO public.email_templates ("name",email_subject,email_content,pushover_title,pushover_message)
	VALUES ('windy_error','PostgSail Windy Weather station Error','Hello __RECIPIENT__,\nSorry!We could not convert your boat to a Windy Personal Weather Station.\nWindy Personal Weather Station is now disable.','PostgSail Windy error!','Sorry!\nWe could not convert your boat to a Windy Personal Weather Station.');

-- Update app_settings
CREATE OR REPLACE FUNCTION public.get_app_settings_fn(OUT app_settings jsonb)
    RETURNS jsonb
    AS $get_app_settings$
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
        OR name LIKE 'app.windy_apikey';
END;
$get_app_settings$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.get_user_settings_from_vesselid_fn(
    IN vesselid TEXT,
    OUT user_settings JSONB
    ) RETURNS JSONB
AS $get_user_settings_from_vesselid$
    DECLARE
    BEGIN
        -- If vessel_id is not NULL
        IF vesselid IS NULL OR vesselid = '' THEN
            RAISE WARNING '-> get_user_settings_from_vesselid_fn invalid input %', vesselid;
        END IF;
        SELECT 
            json_build_object( 
                    'boat' , v.name,
                    'recipient', a.first,
                    'email', v.owner_email,
                    'settings', a.preferences
                    ) INTO user_settings
            FROM auth.accounts a, auth.vessels v, api.metadata m
            WHERE m.vessel_id = v.vessel_id
                AND m.vessel_id = vesselid
                AND a.email = v.owner_email;
        PERFORM set_config('user.email', user_settings->>'email'::TEXT, false);
        PERFORM set_config('user.recipient', user_settings->>'recipient'::TEXT, false);
    END;
$get_user_settings_from_vesselid$ LANGUAGE plpgsql;

-- Create Windy PWS integration
CREATE OR REPLACE FUNCTION public.windy_pws_py_fn(IN metric JSONB,
    IN _user JSONB, IN app JSONB) RETURNS JSONB
AS $windy_pws_py$
    """
    Send environment data from boat instruments to Windy as a Personal Weather Station (PWS)
    https://community.windy.com/topic/8168/report-your-weather-station-data-to-windy
    """
    import requests
    import json
    import decimal

    if not 'app.windy_apikey' in app and not app['app.windy_apikey']:
        plpy.error('Error no windy_apikey defined, check app settings')
        return none
    if not 'station' in metric and not metric['station']:
        plpy.error('Error no metrics defined')
        return none
    if not 'temp' in metric and not metric['temp']:
        plpy.error('Error no metrics defined')
        return none
    if not _user:
        plpy.error('Error no user defined, check user settings')
        return none

    _headers = {'User-Agent': 'PostgSail', 'From': 'xbgmsharp@gmail.com', 'Content-Type': 'application/json'}
    _payload = {
        'stations': [
            { 'station': int(decimal.Decimal(metric['station'])),
            'name': metric['name'],
            'shareOption': 'Open',
            'type': 'SignalK PostgSail Plugin',
            'provider': 'PostgSail',
            'url': 'https://iot.openplotter.cloud/{name}/monitoring'.format(name=metric['name']),
            'lat': float(decimal.Decimal(metric['lat'])),
            'lon': float(decimal.Decimal(metric['lon'])),
            'elevation': 1 }
        ],
        'observations': [
            { 'station': int(decimal.Decimal(metric['station'])),
            'temp': float(decimal.Decimal(metric['temp'])),
            'wind': round(float(decimal.Decimal(metric['wind']))),
            'gust': round(float(decimal.Decimal(metric['gust']))),
            'winddir': int(decimal.Decimal(metric['winddir'])),
            'pressure': int(decimal.Decimal(metric['pressure'])),
            'rh': float(decimal.Decimal(metric['rh'])) }
    ]}
    #print(_payload)
    #plpy.notice(_payload)
    data = json.dumps(_payload)
    api_url = 'https://stations.windy.com/pws/update/{api_key}'.format(api_key=app['app.windy_apikey'])
    r = requests.post(api_url, data=data, headers=_headers, timeout=(5, 60))
    #print(r.text)
    #plpy.notice(api_url)
    if r.status_code == 200:
        #print('Data sent successfully!')
        plpy.notice('Data sent successfully to Windy!')
        #plpy.notice(api_url)
        if not 'windy' in _user['settings']:
	        api_url = 'https://stations.windy.com/pws/station/{api_key}/{station}'.format(api_key=app['app.windy_apikey'], station=metric['station'])
		    #print(r.text)
		    #plpy.notice(api_url)
	        r = requests.get(api_url, timeout=(5, 60))
	        if r.status_code == 200:
	            #print('Windy Personal Weather Station created successfully in Windy Stations!')
	            plpy.notice('Windy Personal Weather Station created successfully in Windy Stations!')
	            return r.json()
	        else:
	            plpy.error(f'Failed to gather PWS details. Status code: {r.status_code}')
    else:
        plpy.error(f'Failed to send data. Status code: {r.status_code}')
        #print(f'Failed to send data. Status code: {r.status_code}')
        #print(r.text)
    return {}
$windy_pws_py$ strict TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.windy_pws_py_fn
    IS 'Forward vessel data to Windy as a Personal Weather Station using plpython3u';

CREATE OR REPLACE FUNCTION public.cron_windy_fn() RETURNS void AS $$
DECLARE
    windy_rec record;
    default_last_metric TIMESTAMPTZ := NOW() - interval '1 day';
    last_metric TIMESTAMPTZ;
    metric_rec record;
    windy_metric jsonb;
    app_settings jsonb;
    user_settings jsonb;
    windy_pws jsonb;
BEGIN
    -- Check for new observations pending update
    RAISE NOTICE 'cron_windy_fn';
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
        RAISE NOTICE '-> cron_windy_fn for [%]', windy_rec;
        PERFORM set_config('vessel.id', windy_rec.vessel_id, false);
        --RAISE WARNING 'public.cron_process_windy_rec_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(windy_rec.vessel_id::TEXT);
        RAISE NOTICE '-> cron_windy_fn checking user_settings [%]', user_settings;
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
            RAISE NOTICE '-> cron_windy_fn checking metrics [%]', metric_rec;
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
            RAISE NOTICE '-> cron_windy_fn checking windy_metrics [%]', windy_metric;
            SELECT windy_pws_py_fn(windy_metric, user_settings, app_settings) into windy_pws;
            RAISE NOTICE '-> cron_windy_fn Windy PWS [%]', ((windy_pws->'header')::JSONB ? 'id');
            IF NOT((user_settings->'settings')::JSONB ? 'windy') and ((windy_pws->'header')::JSONB ? 'id') then
                RAISE NOTICE '-> cron_windy_fn new Windy PWS [%]', (windy_pws->'header')::JSONB->>'id';
                -- Send metrics to Windy
                PERFORM api.update_user_preferences_fn('{windy}'::TEXT, ((windy_pws->'header')::JSONB->>'id')::TEXT);
                -- Send notification
                PERFORM send_notification_fn('windy'::TEXT, user_settings::JSONB);
            END IF;
            -- Record last metrics time
            SELECT metric_rec.time_bucket INTO last_metric;
        END LOOP;
        PERFORM api.update_user_preferences_fn('{windy_last_metric}'::TEXT, last_metric::TEXT);
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_windy_fn
    IS 'init by pg_cron to create (or update) station and uploading observations to Windy Personal Weather Station observations';

CREATE OR REPLACE FUNCTION public.cron_alerts_fn() RETURNS void AS $$
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
                    avg((m.metrics->'electrical.batteries.House.capacity.stateOfCharge')::numeric) AS charge
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
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_alerts_fn
    IS 'init by pg_cron to check for alerts';

-- CRON for no vessel notification
CREATE FUNCTION public.cron_no_vessel_fn() RETURNS void AS $no_vessel$
DECLARE
    no_vessel record;
    user_settings jsonb;
BEGIN
    -- Check for user with no vessel register
    RAISE NOTICE 'cron_no_vessel_fn';
    FOR no_vessel in
        SELECT a.user_id,a.email,a.first
            FROM auth.accounts a
            WHERE NOT EXISTS (
                SELECT *
                FROM auth.vessels v
                WHERE v.owner_email = a.email)
    LOOP
        RAISE NOTICE '-> cron_no_vessel_rec_fn for [%]', no_vessel;
        SELECT json_build_object('email', no_vessel.email, 'recipient', no_vessel.first) into user_settings;
        RAISE NOTICE '-> debug cron_no_vessel_rec_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('no_vessel'::TEXT, user_settings::JSONB);
    END LOOP;
END;
$no_vessel$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_no_vessel_fn
    IS 'init by pg_cron, check for user with no vessel register then send notification';

CREATE FUNCTION public.cron_no_metadata_fn() RETURNS void AS $no_metadata$
DECLARE
    no_metadata_rec record;
    user_settings jsonb;
BEGIN
    -- Check for vessel register but with no metadata
    RAISE NOTICE 'cron_no_metadata_fn';
    FOR no_metadata_rec in
        SELECT
            a.user_id,a.email,a.first
            FROM auth.accounts a, auth.vessels v
            WHERE NOT EXISTS (
                SELECT *
                FROM  api.metadata m
                WHERE v.vessel_id = m.vessel_id) AND v.owner_email = a.email
    LOOP
        RAISE NOTICE '-> cron_process_no_metadata_rec_fn for [%]', no_metadata_rec;
        SELECT json_build_object('email', no_metadata_rec.email, 'recipient', no_metadata_rec.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_no_metadata_rec_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('no_metadata'::TEXT, user_settings::JSONB);
    END LOOP;
END;
$no_metadata$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_no_metadata_fn
    IS 'init by pg_cron, check for vessel with no metadata then send notification';

CREATE FUNCTION public.cron_no_activity_fn() RETURNS void AS $no_activity$
DECLARE
    no_activity_rec record;
    user_settings jsonb;
BEGIN
    -- Check for vessel with no activity for more than 230 days
    RAISE NOTICE 'cron_no_activity_fn';
    FOR no_activity_rec in
        SELECT
            v.owner_email,m.name,m.vessel_id,m.time,a.first
            FROM auth.accounts a
            LEFT JOIN auth.vessels v ON v.owner_email = a.email
            LEFT JOIN api.metadata m ON v.vessel_id = m.vessel_id
            WHERE m.time < NOW() AT TIME ZONE 'UTC' - INTERVAL '230 DAYS'
    LOOP
        RAISE NOTICE '-> cron_process_no_activity_rec_fn for [%]', no_activity_rec;
        SELECT json_build_object('email', no_activity_rec.owner_email, 'recipient', no_activity_rec.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_no_activity_rec_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('no_activity'::TEXT, user_settings::JSONB);
    END LOOP;
END;
$no_activity$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_no_activity_fn
    IS 'init by pg_cron, check for vessel with no activity for more than 230 days then send notification';

CREATE FUNCTION public.cron_deactivated_fn() RETURNS void AS $deactivated$
DECLARE
    no_activity_rec record;
    user_settings jsonb;
BEGIN
    RAISE NOTICE 'cron_deactivated_fn';

    -- List accounts with vessel inactivity for more than 1 YEAR
    FOR no_activity_rec in
        SELECT
            v.owner_email,m.name,m.vessel_id,m.time,a.first
            FROM auth.accounts a
            LEFT JOIN auth.vessels v ON v.owner_email = a.email
            LEFT JOIN api.metadata m ON v.vessel_id = m.vessel_id
            WHERE m.time < NOW() AT TIME ZONE 'UTC' - INTERVAL '1 YEAR'
    LOOP
        RAISE NOTICE '-> cron_process_deactivated_rec_fn for inactivity [%]', no_activity_rec;
        SELECT json_build_object('email', no_activity_rec.owner_email, 'recipient', no_activity_rec.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_deactivated_rec_fn inactivity [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('deactivated'::TEXT, user_settings::JSONB);
        --PERFORM public.delete_account_fn(no_activity_rec.owner_email::TEXT, no_activity_rec.vessel_id::TEXT);
    END LOOP;

    -- List accounts with no vessel metadata for more than 1 YEAR
    FOR no_activity_rec in
        SELECT
            a.user_id,a.email,a.first,a.created_at
            FROM auth.accounts a, auth.vessels v
            WHERE NOT EXISTS (
                SELECT *
                FROM  api.metadata m
                WHERE v.vessel_id = m.vessel_id) AND v.owner_email = a.email
            AND v.created_at < NOW() AT TIME ZONE 'UTC' - INTERVAL '1 YEAR'
    LOOP
        RAISE NOTICE '-> cron_process_deactivated_rec_fn for no metadata [%]', no_activity_rec;
        SELECT json_build_object('email', no_activity_rec.owner_email, 'recipient', no_activity_rec.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_deactivated_rec_fn no metadata [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('deactivated'::TEXT, user_settings::JSONB);
        --PERFORM public.delete_account_fn(no_activity_rec.owner_email::TEXT, no_activity_rec.vessel_id::TEXT);
    END LOOP;

    -- List accounts with no vessel created for more than 1 YEAR
    FOR no_activity_rec in
        SELECT a.user_id,a.email,a.first,a.created_at
            FROM auth.accounts a
            WHERE NOT EXISTS (
                SELECT *
                FROM auth.vessels v
                WHERE v.owner_email = a.email)
            AND a.created_at < NOW() AT TIME ZONE 'UTC' - INTERVAL '1 YEAR'
    LOOP
        RAISE NOTICE '-> cron_process_deactivated_rec_fn for no vessel [%]', no_activity_rec;
        SELECT json_build_object('email', no_activity_rec.owner_email, 'recipient', no_activity_rec.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_deactivated_rec_fn no vessel [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('deactivated'::TEXT, user_settings::JSONB);
        --PERFORM public.delete_account_fn(no_activity_rec.owner_email::TEXT, no_activity_rec.vessel_id::TEXT);
    END LOOP;
END;
$deactivated$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_deactivated_fn
    IS 'init by pg_cron, check for vessel with no activity for more than 1 year then send notification and delete data';

DROP FUNCTION IF EXISTS public.cron_process_prune_otp_fn();
DROP FUNCTION IF EXISTS public.cron_process_no_vessel_fn();
DROP FUNCTION IF EXISTS public.cron_process_no_metadata_fn();
DROP FUNCTION IF EXISTS public.cron_process_no_activity_fn();
DROP FUNCTION IF EXISTS public.cron_process_deactivated_fn();
DROP FUNCTION IF EXISTS public.cron_process_windy_fn();
DROP FUNCTION IF EXISTS public.cron_process_alerts_fn();

-- Remove deprecated fn
DROP FUNCTION public.cron_process_new_account_fn();
DROP FUNCTION public.cron_process_new_account_otp_validation_fn();
DROP FUNCTION public.cron_process_new_moorage_fn();
DROP FUNCTION public.cron_process_new_vessel_fn();

-- Update version
UPDATE public.app_settings
	SET value='0.7.0'
	WHERE "name"='app.version';

-- Create a cron job
\c postgres

UPDATE cron.job
	SET command='select public.cron_prune_otp_fn()'
	WHERE jobname = 'cron_prune_otp';
UPDATE cron.job
	SET command='select public.cron_no_vessel_fn()'
	WHERE jobname = 'cron_no_vessel';
UPDATE cron.job
	SET command='select public.cron_no_metadata_fn()'
	WHERE jobname = 'cron_no_metadata';
UPDATE cron.job
	SET command='select public.cron_no_activity_fn()'
	WHERE jobname = 'cron_no_activity';
UPDATE cron.job
	SET command='select public.cron_windy_fn()'
	WHERE jobname = 'cron_windy';
UPDATE cron.job
	SET command='select public.cron_alerts_fn()'
	WHERE jobname = 'cron_alerts';

