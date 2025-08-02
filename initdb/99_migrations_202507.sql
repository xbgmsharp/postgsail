---------------------------------------------------------------------------
-- Copyright 2021-2025 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration June/July 2025
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Update plugin upgrade message
UPDATE public.email_templates
	SET email_content='Hello __RECIPIENT__,
Please upgrade your postgsail signalk plugin. Make sure you restart your Signalk instance after upgrading. Be sure to contact me if you encounter any issue.'
	WHERE "name"='skplugin_upgrade';

-- DROP FUNCTION api.login(text, text);
-- Update api.login, update the connected_at field to the current time
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
COMMENT ON FUNCTION api.login IS 'Handle user login, returns a JWT token with user role and email.';

-- DROP FUNCTION api.monitoring_history_fn(in text, out jsonb);
-- Update monitoring_history_fn to use custom user settings for metrics
CREATE OR REPLACE FUNCTION api.monitoring_history_fn(time_interval text DEFAULT '24'::text, OUT history_metrics jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
        bucket_interval interval := '5 minutes';
    BEGIN
        RAISE NOTICE '-> monitoring_history_fn';
        SELECT CASE time_interval
            WHEN '24' THEN '5 minutes'
            WHEN '48' THEN '2 hours'
            WHEN '72' THEN '4 hours'
            WHEN '168' THEN '7 hours'
            ELSE '5 minutes'
            END bucket INTO bucket_interval;
        RAISE NOTICE '-> monitoring_history_fn % %', time_interval, bucket_interval;
        WITH history_table AS (
            SELECT time_bucket(bucket_interval::INTERVAL, mt.time) AS time_bucket,
                avg(-- Water Temperature
                    COALESCE(
                        mt.metrics->'water'->>'temperature',
                        mt.metrics->>(md.configuration->>'waterTemperatureKey'),
                        mt.metrics->>'environment.water.temperature'
                    )::FLOAT) AS waterTemperature,
                avg(-- Inside Temperature
                    COALESCE(
                        mt.metrics->'temperature'->>'inside',
                        mt.metrics->>(md.configuration->>'insideTemperatureKey'),
                        mt.metrics->>'environment.inside.temperature'
                    )::FLOAT) AS insideTemperature,
                avg(-- Outside Temperature
                    COALESCE(
                        mt.metrics->'temperature'->>'outside',
                        mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
                        mt.metrics->>'environment.outside.temperature'
                    )::FLOAT) AS outsideTemperature,
                avg(-- Wind Speed True
                    COALESCE(
                        mt.metrics->'wind'->>'speed',
                        mt.metrics->>(md.configuration->>'windSpeedKey'),
                        mt.metrics->>'environment.wind.speedTrue'
                    )::FLOAT) AS windSpeedOverGround,
                avg(-- Inside Humidity
                    COALESCE(
                        mt.metrics->'humidity'->>'inside',
                        mt.metrics->>(md.configuration->>'insideHumidityKey'),
                        mt.metrics->>'environment.inside.relativeHumidity',
                        mt.metrics->>'environment.inside.humidity'
                    )::FLOAT) AS insideHumidity,
                avg(-- Outside Humidity
                    COALESCE(
                        mt.metrics->'humidity'->>'outside',
                        mt.metrics->>(md.configuration->>'outsideHumidityKey'),
                        mt.metrics->>'environment.outside.relativeHumidity',
                        mt.metrics->>'environment.outside.humidity'
                    )::FLOAT) AS outsideHumidity,
                avg(-- Outside Pressure
                    COALESCE(
                        mt.metrics->'pressure'->>'outside',
                        mt.metrics->>(md.configuration->>'outsidePressureKey'),
                        mt.metrics->>'environment.outside.pressure'
                    )::FLOAT) AS outsidePressure,
                avg(--Inside Pressure
                    COALESCE(
                        mt.metrics->'pressure'->>'inside',
                        mt.metrics->>(md.configuration->>'insidePressureKey'),
                        mt.metrics->>'environment.inside.pressure'
                    )::FLOAT) AS insidePressure,
                avg(-- Battery Charge (State of Charge)
                    COALESCE(
                        mt.metrics->'battery'->>'charge',
                        mt.metrics->>(md.configuration->>'stateOfChargeKey'),
                        mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
                    )::FLOAT) AS batteryCharge,
                avg(-- Battery Voltage
                    COALESCE(
                        mt.metrics->'battery'->>'voltage',
                        mt.metrics->>(md.configuration->>'voltageKey'),
                        mt.metrics->>'electrical.batteries.House.voltage'
                    )::FLOAT) AS batteryVoltage,
                avg(-- Water Depth
                    COALESCE(
                        mt.metrics->'water'->>'depth',
                        mt.metrics->>(md.configuration->>'depthKey'),
                        mt.metrics->>'environment.depth.belowTransducer'
                    )::FLOAT) AS depth
                FROM api.metrics mt
				JOIN api.metadata md ON md.vessel_id = mt.vessel_id
                WHERE mt.time > (NOW() AT TIME ZONE 'UTC' - INTERVAL '1 hours' * time_interval::NUMERIC)
                GROUP BY time_bucket
                ORDER BY time_bucket asc
        )
        SELECT jsonb_agg(history_table) INTO history_metrics FROM history_table;
    END
$function$
;
-- Description
COMMENT ON FUNCTION api.monitoring_history_fn(in text, out jsonb) IS 'Export metrics from a time period 24h, 48h, 72h, 7d';

-- DROP FUNCTION public.cron_alerts_fn();
-- Update cron_alerts_fn to check for alerts, filters out empty strings (""), so they are not included in the result.
CREATE OR REPLACE FUNCTION public.cron_alerts_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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
            (alert_default || ( -- Filters out empty strings (""), so they are not included in the result.
							    SELECT jsonb_object_agg(key, value)
							    FROM jsonb_each(a.preferences->'alerting') 
							    WHERE value <> '""'
							  )) as alerting,
            (a.preferences->'alarms')::JSONB as alarms,
            m.configuration as config
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
                    avg(-- Inside Temperature
                        COALESCE(
                            mt.metrics->'temperature'->>'inside',
                            mt.metrics->>(md.configuration->>'insideTemperatureKey'),
                            mt.metrics->>'environment.inside.temperature'
                        )::FLOAT) AS intemp,
                    avg(-- Wind Speed True
                        COALESCE(
                            mt.metrics->'wind'->>'speed',
                            mt.metrics->>(md.configuration->>'windSpeedKey'),
                            mt.metrics->>'environment.wind.speedTrue'
                        )::FLOAT) AS wind,
                    avg(-- Water Depth
                        COALESCE(
                            mt.metrics->'water'->>'depth',
                            mt.metrics->>(md.configuration->>'depthKey'),
                            mt.metrics->>'environment.depth.belowTransducer'
                        )::FLOAT) AS watdepth,
                    avg(-- Outside Temperature
                        COALESCE(
                            m.metrics->'temperature'->>'outside',
                            m.metrics->>(alert_rec.config->>'outsideTemperatureKey'),
                            m.metrics->>'environment.outside.temperature'
                        )::NUMERIC) AS outtemp,
                    avg(-- Water Temperature
                        COALESCE(
                            m.metrics->'water'->>'temperature',
                            m.metrics->>(alert_rec.config->>'waterTemperatureKey'),
                            m.metrics->>'environment.water.temperature'
                        )::NUMERIC) AS wattemp,
                    avg(-- Outside Pressure
                        COALESCE(
                            m.metrics->'pressure'->>'outside',
                            m.metrics->>(alert_rec.config->>'outsidePressureKey'),
                            m.metrics->>'environment.outside.pressure'
                        )::NUMERIC) AS pressure,
                    avg(-- Battery Voltage
                        COALESCE(
                            m.metrics->'battery'->>'voltage',
                            m.metrics->>(alert_rec.config->>'voltageKey'),
                            m.metrics->>'electrical.batteries.House.voltage'
                        )::NUMERIC) AS voltage,
                    avg(-- Battery Charge (State of Charge)
                        COALESCE(
                            m.metrics->'battery'->>'charge',
                            m.metrics->>(alert_rec.config->>'stateOfChargeKey'),
                            m.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
                        )::NUMERIC) AS charge
                FROM api.metrics m
                WHERE vessel_id = alert_rec.vessel_id
                    AND m.time >= alert_rec.last_metric::TIMESTAMPTZ
                GROUP BY time_bucket
                ORDER BY time_bucket ASC LIMIT 100
        LOOP
            RAISE NOTICE '-> cron_alerts_fn checking metrics [%]', metric_rec;
            RAISE NOTICE '-> cron_alerts_fn checking alerting [%]', alert_rec.alerting;
            --RAISE NOTICE '-> cron_alerts_fn checking debug [%] [%]', kelvinToCel(metric_rec.intemp), (alert_rec.alerting->'low_indoor_temperature_threshold');
            IF metric_rec.intemp IS NOT NULL AND public.kelvintocel(metric_rec.intemp::NUMERIC) < (alert_rec.alerting->'low_indoor_temperature_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug indoor_temp [%]', (alert_rec.alarms->'low_indoor_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug indoor_temp [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
            IF metric_rec.outtemp IS NOT NULL AND public.kelvintocel(metric_rec.outtemp::NUMERIC) < (alert_rec.alerting->>'low_outdoor_temperature_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug outdoor_temp [%]', (alert_rec.alarms->'low_outdoor_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug outdoor_temp [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
            IF metric_rec.wattemp IS NOT NULL AND public.kelvintocel(metric_rec.wattemp::NUMERIC) < (alert_rec.alerting->>'low_water_temperature_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug water_temp [%]', (alert_rec.alarms->'low_water_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug water_temp [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
            IF metric_rec.watdepth IS NOT NULL AND metric_rec.watdepth::NUMERIC < (alert_rec.alerting->'low_water_depth_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug water_depth [%]', (alert_rec.alarms->'low_water_depth_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug water_depth [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
            if metric_rec.pressure IS NOT NULL AND metric_rec.pressure::NUMERIC < (alert_rec.alerting->'high_pressure_drop_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug pressure [%]', (alert_rec.alarms->'high_pressure_drop_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug pressure [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
            IF metric_rec.wind IS NOT NULL AND metric_rec.wind::NUMERIC > (alert_rec.alerting->'high_wind_speed_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug wind [%]', (alert_rec.alarms->'high_wind_speed_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug wind [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
            IF metric_rec.voltage IS NOT NULL AND metric_rec.voltage::NUMERIC < (alert_rec.alerting->'low_battery_voltage_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug voltage [%]', (alert_rec.alarms->'low_battery_voltage_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug voltage [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
            IF metric_rec.charge IS NOT NULL AND (metric_rec.charge::NUMERIC*100) < (alert_rec.alerting->'low_battery_charge_threshold')::NUMERIC then
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
                    SELECT user_settings::JSONB || ('{"alert": "low_battery_charge_threshold value:'|| ROUND(metric_rec.charge::NUMERIC*100,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
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
$function$
;
-- Description
COMMENT ON FUNCTION public.cron_alerts_fn() IS 'init by pg_cron to check for alerts';

-- DROP FUNCTION public.process_pre_logbook_fn(int4);
-- Update process_pre_logbook_fn to detect and avoid logbook we more than 1000NM in less 15h
CREATE OR REPLACE FUNCTION public.process_pre_logbook_fn(_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
    DECLARE
        logbook_rec record;
        avg_rec record;
        geo_rec record;
        _invalid_time boolean;
        _invalid_interval boolean;
        _invalid_distance boolean;
        _invalid_ratio boolean;
        count_metric numeric;
        previous_stays_id numeric;
        current_stays_departed text;
        current_stays_id numeric;
        current_stays_active boolean;
        timebucket boolean;
    BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_pre_logbook_fn invalid input %', _id;
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
            RAISE WARNING '-> process_pre_logbook_fn invalid logbook %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', logbook_rec.vessel_id, false);
        --RAISE WARNING 'public.process_logbook_queue_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);

        -- Check if all metrics are within 50meters base on geo loc
        count_metric := logbook_metrics_dwithin_fn(logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT, logbook_rec._from_lng::NUMERIC, logbook_rec._from_lat::NUMERIC);
        RAISE NOTICE '-> process_pre_logbook_fn logbook_metrics_dwithin_fn count:[%]', count_metric;

        -- Calculate logbook data average and geo
        -- Update logbook entry with the latest metric data and calculate data
        avg_rec := logbook_update_avg_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        geo_rec := logbook_update_geom_distance_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);

        -- Avoid/ignore/delete logbook stationary movement or time sync issue
        -- Check time start vs end
        SELECT logbook_rec._to_time::TIMESTAMPTZ < logbook_rec._from_time::TIMESTAMPTZ INTO _invalid_time;
        -- Is distance is less than 0.010
        SELECT geo_rec._track_distance < 0.010 INTO _invalid_distance;
        -- Is duration is less than 100sec
        SELECT (logbook_rec._to_time::TIMESTAMPTZ - logbook_rec._from_time::TIMESTAMPTZ) < (100::text||' secs')::interval INTO _invalid_interval;
        -- If we have more than 800NM in less 15h
        IF geo_rec._track_distance >= 800 AND (logbook_rec._to_time::TIMESTAMPTZ - logbook_rec._from_time::TIMESTAMPTZ) < (15::text||' hours')::interval THEN
            _invalid_distance := True;
            _invalid_interval := True;
            --RAISE NOTICE '-> process_pre_logbook_fn invalid logbook data id [%], _invalid_distance [%], _invalid_interval [%]', logbook_rec.id, _invalid_distance, _invalid_interval;
        END IF;
        -- If we have less than 20 metrics or less than 0.5NM or less than avg 0.5knts
        -- Is within metrics represent more or equal than 60% of the total entry
        IF count_metric::NUMERIC <= 20 OR geo_rec._track_distance < 0.5 OR avg_rec.avg_speed < 0.5 THEN
            SELECT (count_metric::NUMERIC / avg_rec.count_metric::NUMERIC) >= 0.60 INTO _invalid_ratio;
        END IF;
        -- if stationary fix data metrics,logbook,stays,moorage
        IF _invalid_time IS True OR _invalid_distance IS True
            OR _invalid_interval IS True OR count_metric = avg_rec.count_metric
            OR _invalid_ratio IS True
            OR avg_rec.count_metric <= 3 THEN
            RAISE NOTICE '-> process_pre_logbook_fn invalid logbook data id [%], _invalid_time [%], _invalid_distance [%], _invalid_interval [%], count_metric_in_zone [%], count_metric_log [%], _invalid_ratio [%]',
                logbook_rec.id, _invalid_time, _invalid_distance, _invalid_interval, count_metric, avg_rec.count_metric, _invalid_ratio;
            -- Update metrics status to moored
            UPDATE api.metrics
                SET status = 'moored'
                WHERE time >= logbook_rec._from_time::TIMESTAMPTZ
                    AND time <= logbook_rec._to_time::TIMESTAMPTZ
                    AND vessel_id = current_setting('vessel.id', false);
            -- Update logbook
            UPDATE api.logbook
                SET notes = 'invalid logbook data, stationary need to fix metrics?'
                WHERE vessel_id = current_setting('vessel.id', false)
                    AND id = logbook_rec.id;
            -- Get related stays
            SELECT id,departed,active INTO current_stays_id,current_stays_departed,current_stays_active
                FROM api.stays s
                WHERE s.vessel_id = current_setting('vessel.id', false)
                    AND s.arrived = logbook_rec._to_time::TIMESTAMPTZ;
            -- Update related stays
            UPDATE api.stays s
                SET notes = 'invalid stays data, stationary need to fix metrics?'
                WHERE vessel_id = current_setting('vessel.id', false)
                    AND arrived = logbook_rec._to_time::TIMESTAMPTZ;
            -- Find previous stays
            SELECT id INTO previous_stays_id
				FROM api.stays s
                WHERE s.vessel_id = current_setting('vessel.id', false)
                    AND s.arrived < logbook_rec._to_time::TIMESTAMPTZ
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
            RAISE WARNING '-> process_pre_logbook_fn delete invalid logbook [%]', logbook_rec.id;
            DELETE FROM api.stays WHERE id = current_stays_id;
            RAISE WARNING '-> process_pre_logbook_fn delete invalid stays [%]', current_stays_id;
            RETURN;
        END IF;

        --IF (logbook_rec.notes IS NULL) THEN -- run one time only
        --    -- If duration is over 24h or number of entry is over 400, check for stays and potential multiple logs with stationary location
        --    IF (logbook_rec._to_time::TIMESTAMPTZ - logbook_rec._from_time::TIMESTAMPTZ) > INTERVAL '24 hours'
        --        OR avg_rec.count_metric > 400 THEN
        --        timebucket := public.logbook_metrics_timebucket_fn('15 minutes'::TEXT, logbook_rec.id, logbook_rec._from_time::TIMESTAMPTZ, logbook_rec._to_time::TIMESTAMPTZ);
        --        -- If true exit current process as the current logbook need to be re-process.
        --        IF timebucket IS True THEN
        --            RETURN;
        --        END IF;
        --    ELSE
        --        timebucket := public.logbook_metrics_timebucket_fn('5 minutes'::TEXT, logbook_rec.id, logbook_rec._from_time::TIMESTAMPTZ, logbook_rec._to_time::TIMESTAMPTZ);
        --        -- If true exit current process as the current logbook need to be re-process.
        --        IF timebucket IS True THEN
        --            RETURN;
        --        END IF;
        --    END IF;
        --END IF;

        -- Add logbook entry to process queue for later processing
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('new_logbook', logbook_rec.id, NOW(), current_setting('vessel.id', true));

    END;
$function$
;

COMMENT ON FUNCTION public.process_pre_logbook_fn(int4) IS 'Detect/Avoid/ignore/delete logbook stationary movement or time sync issue';

-- Revoke security definer
--ALTER FUNCTION api.update_logbook_observations_fn(_id integer, observations text) SECURITY INVOKER;
--ALTER FUNCTION api.delete_logbook_fn(_id integer) SECURITY INVOKER;
ALTER FUNCTION api.merge_logbook_fn(_id integer, _id integer) SECURITY INVOKER;

GRANT DELETE ON TABLE public.process_queue TO user_role;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;

GRANT UPDATE (status) ON api.metrics TO user_role;
GRANT UPDATE ON api.logbook TO user_role;

DROP POLICY IF EXISTS api_user_role ON api.metrics;
CREATE POLICY api_user_role ON api.metrics TO user_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));

-- Update version
UPDATE public.app_settings
	SET value='0.9.3'
	WHERE "name"='app.version';

--\c postgres
--UPDATE cron.job SET username = 'scheduler'; --  Update to scheduler
--UPDATE cron.job SET username = current_user WHERE jobname = 'cron_vacuum'; -- Update to superuser for vacuum permissions
--UPDATE cron.job SET username = current_user WHERE jobname = 'job_run_details_cleanup';
