-- +goose Up
-- +goose StatementBegin

set timezone to 'UTC';

-- preferences.monitoring → metadata.configuration
UPDATE api.metadata md
SET configuration = (
    SELECT a.preferences -> 'monitoring'
    FROM auth.vessels v
    JOIN auth.accounts a ON a.email = v.owner_email
    WHERE v.vessel_id = md.vessel_id
      AND a.preferences ? 'monitoring'
)
WHERE md.configuration IS NULL
  AND EXISTS (
    SELECT 1
    FROM auth.vessels v
    JOIN auth.accounts a ON a.email = v.owner_email
    WHERE v.vessel_id = md.vessel_id
      AND a.preferences ? 'monitoring'
);

UPDATE auth.accounts
SET preferences = preferences - 'monitoring'
WHERE preferences ? 'monitoring';

-- alarms + alert_last_metric + alerting → metadata.user_data
UPDATE api.metadata md
SET user_data = jsonb_strip_nulls(
    COALESCE(md.user_data, '{}') ||
    jsonb_build_object(
        'alarms',            (SELECT a.preferences -> 'alarms'
                              FROM auth.vessels v
                              JOIN auth.accounts a ON a.email = v.owner_email
                              WHERE v.vessel_id = md.vessel_id),
        'alert_last_metric', (SELECT a.preferences ->> 'alert_last_metric'
                              FROM auth.vessels v
                              JOIN auth.accounts a ON a.email = v.owner_email
                              WHERE v.vessel_id = md.vessel_id),
        'alerting',          (SELECT a.preferences -> 'alerting'
                              FROM auth.vessels v
                              JOIN auth.accounts a ON a.email = v.owner_email
                              WHERE v.vessel_id = md.vessel_id)
    )
)
WHERE EXISTS (
    SELECT 1
    FROM auth.vessels v
    JOIN auth.accounts a ON a.email = v.owner_email
    WHERE v.vessel_id = md.vessel_id
      AND a.preferences ?| ARRAY['alarms', 'alert_last_metric', 'alerting']
);

-- Remove ALL three keys from preferences.
-- alerting is now vessel-scoped in user_data; web UI reads/writes via vessel_settings_fn.
UPDATE auth.accounts
SET preferences = preferences - 'alarms' - 'alert_last_metric' - 'alerting'
WHERE preferences ?| ARRAY['alarms', 'alert_last_metric', 'alerting'];

-- windy* keys → metadata.user_data.windy (consolidated object)
UPDATE api.metadata md
SET user_data = jsonb_set(
    COALESCE(md.user_data, '{}'),
    '{windy}',
    jsonb_strip_nulls(jsonb_build_object(
        'station_id',  (SELECT a.preferences ->> 'windy'
                        FROM auth.vessels v
                        JOIN auth.accounts a ON a.email = v.owner_email
                        WHERE v.vessel_id = md.vessel_id),
        'password',    (SELECT a.preferences ->> 'windy_password_station'
                        FROM auth.vessels v
                        JOIN auth.accounts a ON a.email = v.owner_email
                        WHERE v.vessel_id = md.vessel_id),
        'last_metric', (SELECT a.preferences ->> 'windy_last_metric'
                        FROM auth.vessels v
                        JOIN auth.accounts a ON a.email = v.owner_email
                        WHERE v.vessel_id = md.vessel_id)
    ))
)
WHERE EXISTS (
    SELECT 1
    FROM auth.vessels v
    JOIN auth.accounts a ON a.email = v.owner_email
    WHERE v.vessel_id = md.vessel_id
      AND a.preferences ?| ARRAY['windy', 'windy_password_station', 'windy_last_metric']
);

UPDATE auth.accounts
SET preferences = preferences
    - 'windy'
    - 'windy_password_station'
    - 'windy_last_metric'
    -- public_windy intentionally KEPT
WHERE preferences ?| ARRAY['windy', 'windy_password_station', 'windy_last_metric'];

-- add language default 'gb' to all existing accounts
UPDATE auth.accounts
SET preferences = jsonb_set(
    COALESCE(preferences, '{}'),
    '{language}',
    '"gb"'
)
WHERE preferences ->> 'language' IS NULL;

ALTER TABLE auth.accounts
    ALTER COLUMN preferences
    SET DEFAULT '{"email_notifications": true, "language": "gb"}'::jsonb;

COMMENT ON COLUMN auth.accounts.preferences IS
    'User-identity preferences. Always-present keys: email_notifications (bool),
     language (ISO 639-1, default "gb").
     public_windy (bool) as user-controlled toggle.
     public_* visibility fields kept temporarily pending web UI rework.
     badges per account
     telegram, pushover_user_key, phone_notifications: user-identity notification
     credentials.';

COMMENT ON COLUMN api.metadata.user_data IS
    'User-defined data for the vessel.
    Include vessel polar (theoretical performance), make/model, and 
    Vessel-scoped operational state (alarms, alert_last_metric, alerting,
     windy.*)';

-- replace generic moddatetime trigger with conditional version
CREATE OR REPLACE FUNCTION api.metadata_moddatetime_fn()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- Refresh updated_at only on genuine vessel-contact changes.
    --
    -- Excluded (must NOT update the timestamp):
    --   configuration  — edited by user_role via the web UI settings page,
    --                    and by cron_process_autodiscovery_fn (scheduler).
    --   user_data      — written exclusively by cron functions
    --                    (cron_alerts_fn, cron_windy_fn, badges_*_fn)
    --                    and by api.update_vessel_settings_fn (user edits).
    --
    -- Included (vessel-originated signals):
    --   time, name, mmsi, plugin_version, signalk_version, platform, ip
    --   available_keys, active
    IF (NEW.name, NEW.mmsi, NEW.time,
        NEW.plugin_version, NEW.signalk_version,
        NEW.platform, NEW.ip, NEW.available_keys, NEW.active)
       IS DISTINCT FROM
       (OLD.name, OLD.mmsi, OLD.time,
        OLD.plugin_version, OLD.signalk_version,
        OLD.platform, OLD.ip, OLD.available_keys, OLD.active)
    THEN
        NEW.updated_at = now();
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION api.metadata_moddatetime_fn() IS
    'Conditional updated_at refresh for api.metadata.
     Stamps updated_at only when a vessel-heartbeat column changed.
     Excluded: configuration (user/autodiscovery writes) and user_data
     (cron writes and user vessel-settings writes).
     Included: name, mmsi, time, plugin_version, signalk_version, platform,
               ip, available_keys, active.';

DROP TRIGGER IF EXISTS metadata_moddatetime ON api.metadata;

CREATE TRIGGER metadata_moddatetime
    BEFORE UPDATE ON api.metadata
    FOR EACH ROW EXECUTE FUNCTION api.metadata_moddatetime_fn();
COMMENT ON TRIGGER metadata_moddatetime ON api.metadata IS
    'Conditional updated_at refresh — skips user_data-only writes (cron/windy/vessel-settings).';

-- optimise update_metadata_userdata_added_at_trigger_fn
CREATE OR REPLACE FUNCTION public.update_metadata_userdata_added_at_trigger_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.user_data IS NULL
       OR NEW.user_data IS NOT DISTINCT FROM OLD.user_data
       OR jsonb_typeof(NEW.user_data) <> 'object' THEN
        RETURN NEW;
    END IF;

    -- Short-circuit: skip all timestamp checks if neither polar nor images changed.
    -- This avoids unnecessary work on every cron alarm/windy/badge/vessel-settings write.
    IF (NEW.user_data->'polar')  IS NOT DISTINCT FROM (OLD.user_data->'polar')
   AND (NEW.user_data->'images') IS NOT DISTINCT FROM (OLD.user_data->'images') THEN
        RETURN NEW;
    END IF;

    IF (NEW.user_data->'polar') IS DISTINCT FROM (OLD.user_data->'polar') THEN
        NEW.user_data := jsonb_set(
            NEW.user_data,
            '{polar_updated_at}',
            to_jsonb(to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
        );
    END IF;

    IF (NEW.user_data->'images') IS DISTINCT FROM (OLD.user_data->'images') THEN
        NEW.user_data := jsonb_set(
            NEW.user_data,
            '{image_updated_at}',
            to_jsonb(to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
        );
    END IF;

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.update_metadata_userdata_added_at_trigger_fn() IS
    'Stamp polar_updated_at / image_updated_at when those keys change.
     Short-circuits immediately if neither polar nor images changed —
     avoids unnecessary work on frequent cron writes (alarms, windy, badges)
     and user vessel-settings writes.';

-- Update get_user_settings_from_vesselid_fn
CREATE OR REPLACE FUNCTION public.get_user_settings_from_vesselid_fn(
    vesselid text,
    OUT user_settings jsonb
)
RETURNS jsonb
LANGUAGE plpgsql AS $$
BEGIN
    IF vesselid IS NULL OR vesselid = '' THEN
        RAISE WARNING '-> get_user_settings_from_vesselid_fn invalid input %', vesselid;
    END IF;

    SELECT
        jsonb_build_object(
            'boat',      v.name,
            'recipient', a.first,
            'email',     v.owner_email,
            'settings',  a.preferences || jsonb_strip_nulls(jsonb_build_object(
                             'windy',                  m.user_data->'windy'->>'station_id',
                             'windy_password_station', m.user_data->'windy'->>'password'
                         ))
        ) INTO user_settings
    FROM auth.accounts a
    JOIN auth.vessels v  ON a.email = v.owner_email
    JOIN api.metadata m  ON m.vessel_id = v.vessel_id
    WHERE m.vessel_id = vesselid;

    PERFORM set_config('user.email',     user_settings->>'email',     false);
    PERFORM set_config('user.recipient', user_settings->>'recipient', false);
END;
$$;
COMMENT ON FUNCTION public.get_user_settings_from_vesselid_fn(text) IS
    'Build user_settings JSONB for notification and cron functions.
     Returns: boat, recipient, email, settings (accounts.preferences merged with
     vessel-scoped windy.station_id and windy.password from metadata.user_data).
     The windy credential merge ensures windy_pws_py_fn can detect an existing
     station via settings.windy / settings.windy_password_station after those
     keys were migrated out of accounts.preferences.';

-- Add api.update_metadata_userdata_fn for merging updates into metadata.user_data from cron functions and user vessel-settings edits.
CREATE OR REPLACE FUNCTION api.update_metadata_userdata_fn(userdata text)
RETURNS boolean
LANGUAGE plpgsql
AS $function$
BEGIN
    --RAISE NOTICE '-> update_metadata_userdata_fn userdata:[%]', userdata;
    -- example: '{"alerting": {"enabled": true}}'
    UPDATE api.metadata
        SET user_data = public.jsonb_recursive_merge(user_data, userdata::jsonb)
        WHERE vessel_id = current_setting('vessel.id', false);
    RETURN FOUND;
END;
$function$;

COMMENT ON FUNCTION api.update_metadata_userdata_fn(text) IS
    'Merge userdata JSONB into api.metadata.user_data for the current vessel.
     Scoped to current_setting(vessel.id) — always set before calling.
     Uses jsonb_recursive_merge to preserve existing keys not in the update.
     FIX: added WHERE vessel_id clause — original had no WHERE, relying solely
     on RLS which is bypassed in SECURITY DEFINER context.';

-- Update cron_alerts_fn, alerting thresholds: read from metadata.user_data (moved from preferences)
-- alarms + alert_last_metric: read/write via api.update_metadata_userdata_fn
CREATE OR REPLACE FUNCTION public.cron_alerts_fn()
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    alert_rec           record;
    default_last_metric TIMESTAMPTZ := NOW() - interval '1 day';
    last_metric         TIMESTAMPTZ;
    metric_rec          record;
    user_settings       JSONB;
    _alarms             JSONB;
    alarms              TEXT;
    alert_default       JSONB := '{
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
    FOR alert_rec IN
        SELECT
            a.user_id, a.email, v.vessel_id,
            COALESCE(
                m.user_data->>'alert_last_metric',
                default_last_metric::TEXT
            ) AS last_metric,
            -- alerting thresholds now read from metadata.user_data (vessel-scoped)
            COALESCE(
                alert_default || (
                    SELECT jsonb_object_agg(key, value)
                    FROM jsonb_each(m.user_data->'alerting')
                    WHERE value <> '""'
                ),
                alert_default
            ) AS alerting,
            COALESCE(m.user_data->'alarms', '{}'::jsonb) AS alarms,
            m.configuration AS config
        FROM auth.accounts a
        LEFT JOIN auth.vessels v ON v.owner_email = a.email
        LEFT JOIN api.metadata m ON m.vessel_id = v.vessel_id
        -- alerting enabled flag now read from metadata.user_data (vessel-scoped)
        WHERE (m.user_data->'alerting'->>'enabled')::boolean IS TRUE
          AND m.active IS TRUE
    LOOP
        PERFORM set_config('vessel.id', alert_rec.vessel_id, false);
        PERFORM set_config('user.email', alert_rec.email, false);
        user_settings := get_user_settings_from_vesselid_fn(alert_rec.vessel_id::TEXT);

        FOR metric_rec IN
            SELECT
                time_bucket('5 minutes', m.time) AS time_bucket,
                AVG(COALESCE(
                    (m.metrics->'temperature'->>'inside')::FLOAT,
                    (m.metrics->>(alert_rec.config->>'insideTemperatureKey'))::FLOAT,
                    (m.metrics->>'environment.inside.temperature')::FLOAT
                )) AS intemp,
                AVG(COALESCE(
                    (m.metrics->'temperature'->>'outside')::FLOAT,
                    (m.metrics->>(alert_rec.config->>'outsideTemperatureKey'))::FLOAT,
                    (m.metrics->>'environment.outside.temperature')::FLOAT
                )) AS outtemp,
                AVG(COALESCE(
                    (m.metrics->'water'->>'temperature')::FLOAT,
                    (m.metrics->>(alert_rec.config->>'waterTemperatureKey'))::FLOAT,
                    (m.metrics->>'environment.water.temperature')::FLOAT
                )) AS wattemp,
                AVG(COALESCE(
                    (m.metrics->'pressure'->>'outside')::FLOAT,
                    (m.metrics->>(alert_rec.config->>'outsidePressureKey'))::FLOAT,
                    (m.metrics->>'environment.outside.pressure')::FLOAT
                )) AS pressure,
                AVG(COALESCE(
                    (m.metrics->'wind'->>'speed')::FLOAT,
                    (m.metrics->>(alert_rec.config->>'windSpeedKey'))::FLOAT,
                    (m.metrics->>'environment.wind.speedTrue')::FLOAT
                ) * 1.94384)::NUMERIC AS wind,
                AVG(COALESCE(
                    (m.metrics->'water'->>'depth')::FLOAT,
                    (m.metrics->>(alert_rec.config->>'depthKey'))::FLOAT,
                    (m.metrics->>'environment.depth.belowTransducer')::FLOAT
                )) AS watdepth,
                AVG(COALESCE(
                    (m.metrics->'battery'->>'voltage')::FLOAT,
                    (m.metrics->>(alert_rec.config->>'voltageKey'))::FLOAT,
                    (m.metrics->>'electrical.batteries.House.voltage')::FLOAT
                )) AS voltage,
                AVG(COALESCE(
                    (m.metrics->'battery'->>'charge')::FLOAT,
                    (m.metrics->>(alert_rec.config->>'stateOfChargeKey'))::FLOAT,
                    (m.metrics->>'electrical.batteries.House.capacity.stateOfCharge')::FLOAT
                )) AS charge
            FROM api.metrics m
            JOIN api.metadata md ON md.vessel_id = m.vessel_id
            WHERE m.vessel_id = alert_rec.vessel_id
              AND m.time >= alert_rec.last_metric::TIMESTAMPTZ
            GROUP BY time_bucket
            ORDER BY time_bucket ASC
            LIMIT 100
        LOOP
            -- Re-read alarms from metadata each iteration so that writes from
            -- earlier thresholds in this same loop are visible.
            SELECT COALESCE(user_data->'alarms', '{}'::jsonb) INTO _alarms
            FROM api.metadata
            WHERE vessel_id = current_setting('vessel.id', false);

            IF metric_rec.intemp IS NOT NULL
               AND public.kelvintocel(metric_rec.intemp::NUMERIC)
                   < (alert_rec.alerting->>'low_indoor_temperature_threshold')::NUMERIC THEN
                IF (_alarms->'low_indoor_temperature_threshold'->>'date' IS NULL) OR
                   ((_alarms->'low_indoor_temperature_threshold'->>'date')::TIMESTAMPTZ
                    + interval '1 hour' * (alert_rec.alerting->>'min_notification_interval')::NUMERIC
                    < metric_rec.time_bucket) THEN
                    alarms := '{"low_indoor_temperature_threshold": {"value": '
                              || public.kelvintocel(metric_rec.intemp)
                              || ', "date":"' || metric_rec.time_bucket || '"}}';
                    _alarms := public.jsonb_recursive_merge(_alarms, alarms::jsonb);
                    PERFORM api.update_metadata_userdata_fn(jsonb_build_object('alarms', _alarms)::TEXT);
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    user_settings := user_settings || ('{"alert": "low_indoor_temperature_threshold value:'
                        || ROUND(public.kelvintocel(metric_rec.intemp), 2)
                        || ' date:' || metric_rec.time_bucket || ' "}')::jsonb;
                    PERFORM send_notification_fn('alert'::TEXT, user_settings);
                END IF;
            END IF;

            IF metric_rec.outtemp IS NOT NULL
               AND public.kelvintocel(metric_rec.outtemp::NUMERIC)
                   < (alert_rec.alerting->>'low_outdoor_temperature_threshold')::NUMERIC THEN
                IF (_alarms->'low_outdoor_temperature_threshold'->>'date' IS NULL) OR
                   ((_alarms->'low_outdoor_temperature_threshold'->>'date')::TIMESTAMPTZ
                    + interval '1 hour' * (alert_rec.alerting->>'min_notification_interval')::NUMERIC
                    < metric_rec.time_bucket) THEN
                    alarms := '{"low_outdoor_temperature_threshold": {"value": '
                              || public.kelvintocel(metric_rec.outtemp)
                              || ', "date":"' || metric_rec.time_bucket || '"}}';
                    _alarms := public.jsonb_recursive_merge(_alarms, alarms::jsonb);
                    PERFORM api.update_metadata_userdata_fn(jsonb_build_object('alarms', _alarms)::TEXT);
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    user_settings := user_settings || ('{"alert": "low_outdoor_temperature_threshold value:'
                        || ROUND(public.kelvintocel(metric_rec.outtemp), 2)
                        || ' date:' || metric_rec.time_bucket || ' "}')::jsonb;
                    PERFORM send_notification_fn('alert'::TEXT, user_settings);
                END IF;
            END IF;

            IF metric_rec.wattemp IS NOT NULL
               AND public.kelvintocel(metric_rec.wattemp::NUMERIC)
                   < (alert_rec.alerting->>'low_water_temperature_threshold')::NUMERIC THEN
                IF (_alarms->'low_water_temperature_threshold'->>'date' IS NULL) OR
                   ((_alarms->'low_water_temperature_threshold'->>'date')::TIMESTAMPTZ
                    + interval '1 hour' * (alert_rec.alerting->>'min_notification_interval')::NUMERIC
                    < metric_rec.time_bucket) THEN
                    alarms := '{"low_water_temperature_threshold": {"value": '
                              || public.kelvintocel(metric_rec.wattemp)
                              || ', "date":"' || metric_rec.time_bucket || '"}}';
                    _alarms := public.jsonb_recursive_merge(_alarms, alarms::jsonb);
                    PERFORM api.update_metadata_userdata_fn(jsonb_build_object('alarms', _alarms)::TEXT);
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    user_settings := user_settings || ('{"alert": "low_water_temperature_threshold value:'
                        || ROUND(public.kelvintocel(metric_rec.wattemp), 2)
                        || ' date:' || metric_rec.time_bucket || ' "}')::jsonb;
                    PERFORM send_notification_fn('alert'::TEXT, user_settings);
                END IF;
            END IF;

            IF metric_rec.pressure IS NOT NULL
               AND metric_rec.pressure::NUMERIC
                   < (alert_rec.alerting->>'low_pressure_threshold')::NUMERIC THEN
                IF (_alarms->'low_pressure_threshold'->>'date' IS NULL) OR
                   ((_alarms->'low_pressure_threshold'->>'date')::TIMESTAMPTZ
                    + interval '1 hour' * (alert_rec.alerting->>'min_notification_interval')::NUMERIC
                    < metric_rec.time_bucket) THEN
                    alarms := '{"low_pressure_threshold": {"value": '
                              || ROUND(metric_rec.pressure, 2)
                              || ', "date":"' || metric_rec.time_bucket || '"}}';
                    _alarms := public.jsonb_recursive_merge(_alarms, alarms::jsonb);
                    PERFORM api.update_metadata_userdata_fn(jsonb_build_object('alarms', _alarms)::TEXT);
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    user_settings := user_settings || ('{"alert": "low_pressure_threshold value:'
                        || ROUND(metric_rec.pressure, 2)
                        || ' date:' || metric_rec.time_bucket || ' "}')::jsonb;
                    PERFORM send_notification_fn('alert'::TEXT, user_settings);
                END IF;
            END IF;

            /*
            -- Rapid pressure drop: current pressure dropped > threshold vs 1 hours ago
            IF metric_rec.pressure IS NOT NULL
            AND metric_rec.pressure_1h_ago IS NOT NULL
            AND (metric_rec.pressure_1h_ago - metric_rec.pressure)::NUMERIC
                > (alert_rec.alerting->>'high_pressure_drop_threshold')::NUMERIC THEN
                IF (_alarms->'high_pressure_drop_threshold'->>'date' IS NULL) OR
                ((_alarms->'high_pressure_drop_threshold'->>'date')::TIMESTAMPTZ
                    + interval '1 hour' * (alert_rec.alerting->>'min_notification_interval')::NUMERIC
                    < metric_rec.time_bucket) THEN
                    alarms := '{"high_pressure_drop_threshold": {"value": '
                            || ROUND((metric_rec.pressure_1h_ago - metric_rec.pressure)::NUMERIC, 2)
                            -- store the DROP value, not the absolute pressure
                            || ', "date":"' || metric_rec.time_bucket || '"}}';
                    _alarms := public.jsonb_recursive_merge(_alarms, alarms::jsonb);
                    PERFORM api.update_metadata_userdata_fn(jsonb_build_object('alarms', _alarms)::TEXT);
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    user_settings := user_settings || ('{"alert": "high_pressure_drop_threshold value:'
                        || ROUND((metric_rec.pressure_1h_ago - metric_rec.pressure)::NUMERIC, 2)
                        || ' date:' || metric_rec.time_bucket || ' "}')::jsonb;
                    PERFORM send_notification_fn('alert'::TEXT, user_settings);
                END IF;
            END IF;
            */

            IF metric_rec.wind IS NOT NULL
               AND metric_rec.wind::NUMERIC
                   > (alert_rec.alerting->>'high_wind_speed_threshold')::NUMERIC THEN
                IF (_alarms->'high_wind_speed_threshold'->>'date' IS NULL) OR
                   ((_alarms->'high_wind_speed_threshold'->>'date')::TIMESTAMPTZ
                    + interval '1 hour' * (alert_rec.alerting->>'min_notification_interval')::NUMERIC
                    < metric_rec.time_bucket) THEN
                    alarms := '{"high_wind_speed_threshold": {"value": '
                              || ROUND(metric_rec.wind, 2)
                              || ', "date":"' || metric_rec.time_bucket || '"}}';
                    _alarms := public.jsonb_recursive_merge(_alarms, alarms::jsonb);
                    PERFORM api.update_metadata_userdata_fn(jsonb_build_object('alarms', _alarms)::TEXT);
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    user_settings := user_settings || ('{"alert": "high_wind_speed_threshold value:'
                        || ROUND(metric_rec.wind, 2)
                        || ' date:' || metric_rec.time_bucket || ' "}')::jsonb;
                    PERFORM send_notification_fn('alert'::TEXT, user_settings);
                END IF;
            END IF;

            IF metric_rec.watdepth IS NOT NULL
               AND metric_rec.watdepth::NUMERIC
                   < (alert_rec.alerting->>'low_water_depth_threshold')::NUMERIC THEN
                IF (_alarms->'low_water_depth_threshold'->>'date' IS NULL) OR
                   ((_alarms->'low_water_depth_threshold'->>'date')::TIMESTAMPTZ
                    + interval '1 hour' * (alert_rec.alerting->>'min_notification_interval')::NUMERIC
                    < metric_rec.time_bucket) THEN
                    alarms := '{"low_water_depth_threshold": {"value": '
                              || ROUND(metric_rec.watdepth::NUMERIC, 2)
                              || ', "date":"' || metric_rec.time_bucket || '"}}';
                    _alarms := public.jsonb_recursive_merge(_alarms, alarms::jsonb);
                    PERFORM api.update_metadata_userdata_fn(jsonb_build_object('alarms', _alarms)::TEXT);
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    user_settings := user_settings || ('{"alert": "low_water_depth_threshold value:'
                        || ROUND(metric_rec.watdepth::NUMERIC, 2)
                        || ' date:' || metric_rec.time_bucket || ' "}')::jsonb;
                    PERFORM send_notification_fn('alert'::TEXT, user_settings);
                END IF;
            END IF;

            IF metric_rec.voltage IS NOT NULL
               AND metric_rec.voltage::NUMERIC
                   < (alert_rec.alerting->>'low_battery_voltage_threshold')::NUMERIC THEN
                IF (_alarms->'low_battery_voltage_threshold'->>'date' IS NULL) OR
                   ((_alarms->'low_battery_voltage_threshold'->>'date')::TIMESTAMPTZ
                    + interval '1 hour' * (alert_rec.alerting->>'min_notification_interval')::NUMERIC
                    < metric_rec.time_bucket) THEN
                    alarms := '{"low_battery_voltage_threshold": {"value": '
                              || ROUND(metric_rec.voltage::NUMERIC, 2)
                              || ', "date":"' || metric_rec.time_bucket || '"}}';
                    _alarms := public.jsonb_recursive_merge(_alarms, alarms::jsonb);
                    PERFORM api.update_metadata_userdata_fn(jsonb_build_object('alarms', _alarms)::TEXT);
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    user_settings := user_settings || ('{"alert": "low_battery_voltage_threshold value:'
                        || ROUND(metric_rec.voltage::NUMERIC, 2)
                        || ' date:' || metric_rec.time_bucket || ' "}')::jsonb;
                    PERFORM send_notification_fn('alert'::TEXT, user_settings);
                END IF;
            END IF;

            IF metric_rec.charge IS NOT NULL
               AND (metric_rec.charge::NUMERIC * 100)
                   < (alert_rec.alerting->>'low_battery_charge_threshold')::NUMERIC THEN
                IF (_alarms->'low_battery_charge_threshold'->>'date' IS NULL) OR
                   ((_alarms->'low_battery_charge_threshold'->>'date')::TIMESTAMPTZ
                    + interval '1 hour' * (alert_rec.alerting->>'min_notification_interval')::NUMERIC
                    < metric_rec.time_bucket) THEN
                    alarms := '{"low_battery_charge_threshold": {"value": '
                              || ROUND(metric_rec.charge::NUMERIC * 100, 2)
                              || ', "date":"' || metric_rec.time_bucket || '"}}';
                    _alarms := public.jsonb_recursive_merge(_alarms, alarms::jsonb);
                    PERFORM api.update_metadata_userdata_fn(jsonb_build_object('alarms', _alarms)::TEXT);
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    user_settings := user_settings || ('{"alert": "low_battery_charge_threshold value:'
                        || ROUND(metric_rec.charge::NUMERIC * 100, 2)
                        || ' date:' || metric_rec.time_bucket || ' "}')::jsonb;
                    PERFORM send_notification_fn('alert'::TEXT, user_settings);
                END IF;
            END IF;

            last_metric := metric_rec.time_bucket;
        END LOOP;

        PERFORM api.update_metadata_userdata_fn(
            jsonb_build_object('alert_last_metric', last_metric)::TEXT
        );
    END LOOP;
END;
$$;
COMMENT ON FUNCTION public.cron_alerts_fn() IS
    'Check vessel alert thresholds against recent metrics.
     alerting thresholds: read from api.metadata.user_data.alerting (vessel-scoped).
     alarms state + alert_last_metric: read/write via api.update_metadata_userdata_fn
     into api.metadata.user_data (vessel-scoped, no updated_at churn on accounts).
     init by pg_cron';

-- Update api.settings_fn, simplified to account-level identity only
DROP FUNCTION IF EXISTS api.settings_fn;
CREATE OR REPLACE FUNCTION api.settings_fn(OUT settings jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog'
AS $function$
BEGIN
    -- Returns account-level identity and preferences only.
    -- Vessel-scoped config (alerting, alarms, windy, polar, images)
    -- is available via api.vessel_settings_fn.
    -- NOTE: public_* visibility fields remain in preferences temporarily
    -- pending web UI rework to move them to vessel_settings.
    SELECT to_jsonb(row) INTO settings
    FROM (
        SELECT
            a.email,
            a.first,
            a.last,
            a.preferences,
            a.created_at,
            INITCAP(CONCAT(LEFT(a.first, 1), ' ', a.last)) AS username,
            public.has_vessel_fn() AS has_vessel
        FROM auth.accounts a
        WHERE a.email = current_setting('user.email')
    ) row;
END;
$function$;

COMMENT ON FUNCTION api.settings_fn(out jsonb) IS
    'Expose account-level user identity and preferences to the API.
     Returns: email, first, last, preferences (account-level keys only after
     preferences migration), created_at, username, has_vessel.
     Vessel-scoped config (alerting thresholds, alarms state, windy credentials,
     polar, images) is returned by api.vessel_settings_fn instead.';

-- Add api.vessel_settings_fn, Returns vessel-scoped configuration and operational state for the vessel
CREATE OR REPLACE FUNCTION api.vessel_settings_fn(OUT vessel_settings jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
BEGIN
    SELECT to_jsonb(row) INTO vessel_settings
    FROM (
        SELECT
            m.vessel_id,
            m.name,
            m.user_data,
            m.configuration
        FROM api.metadata m
        WHERE m.vessel_id = current_setting('vessel.id', false)
    ) row;
END;
$function$;

COMMENT ON FUNCTION api.vessel_settings_fn(out jsonb) IS
    'Expose vessel-scoped configuration and operational state to the API.
     Returns: vessel_id, name, user_data (alerting thresholds, alarms state,
     alert_last_metric cursor, windy credentials, polar, images,
     make_model), configuration (SignalK key mappings from autodiscovery).
     Companion to api.settings_fn which returns account-level identity.
     Web UI reads alerting thresholds from user_data.alerting via this function.';

-- Add api.update_vessel_settings_fn, Mirrors the key/value pattern of api.update_user_preferences_fn
CREATE OR REPLACE FUNCTION api.update_vessel_settings_fn(key text, value text)
RETURNS boolean
LANGUAGE plpgsql
AS $function$
DECLARE
    first_c TEXT;
    last_c  TEXT;
    _value  TEXT := value;
BEGIN
    IF key IS NULL OR value IS NULL THEN
        RAISE EXCEPTION 'invalid input' USING HINT = 'key and value are required';
    END IF;

    -- Mirror type-detection logic from update_user_preferences_fn:
    -- pass through JSON objects, integers, and booleans as-is;
    -- wrap plain strings in to_jsonb() to produce a valid JSON string literal.
    SELECT SUBSTRING(value, 1, 1), RIGHT(value, 1) INTO first_c, last_c;
    IF first_c <> '{' AND last_c <> '}'
       AND public.isnumeric(value) IS FALSE
       AND public.isboolean(value) IS FALSE THEN
        _value := to_jsonb(value)::text;
    END IF;

    UPDATE api.metadata
        SET user_data = jsonb_set(
            COALESCE(user_data, '{}'),
            key::text[],
            _value::jsonb
        )
        WHERE vessel_id = current_setting('vessel.id', false);

    RETURN FOUND;
END;
$function$;

COMMENT ON FUNCTION api.update_vessel_settings_fn(text, text) IS
    'Write a vessel-scoped setting to api.metadata.user_data for the current vessel.
     key:   jsonb path array as text, e.g. ''{alerting,enabled}''
            or ''{alerting,low_water_depth_threshold}''.
     value: the new value — JSON objects, numbers, and booleans passed through;
            plain strings wrapped in to_jsonb() automatically.
     Scoped to current_setting(vessel.id) — safe for user_role via RLS.
     Companion write function to api.vessel_settings_fn.
     Mirrors the key/value pattern of api.update_user_preferences_fn.';

DROP FUNCTION IF EXISTS api.profile_fn;
-- Update api.profile_fn, only expose relevant data to MCP or bot
CREATE OR REPLACE FUNCTION api.profile_fn(OUT profile jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
BEGIN                                                                                                                                                                                                                             
    SELECT to_jsonb(row) INTO profile                                                                                                                                                                                            
    FROM (
        SELECT a.first, a.last, a.created_at,
                INITCAP(CONCAT(LEFT(first, 1), ' ', last)) AS username,                                                                                                                                                                      
                public.has_vessel_fn() AS has_vessel,                                                                                                                                                                                        
                (a.preferences::jsonb - ARRAY[
                    'ip',
                    'telegram',
                    'public_password',
                    'pushover_user_key'
                ])::jsonb AS preferences                                                                                                                                                                                                      
        FROM auth.accounts a
        WHERE email = current_setting('user.email')
        ) row;
END;
$function$
;

COMMENT ON FUNCTION api.profile_fn(out jsonb) IS 'Return user profile information based on current user email';

-- Update api.signup, enforce new preferences defaults
CREATE OR REPLACE FUNCTION api.signup(email text, pass text, firstname text, lastname text)
 RETURNS auth.jwt_token
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
declare
  _role name;
begin
  IF email IS NULL OR email = ''
	 OR pass IS NULL OR pass = '' THEN
    RAISE EXCEPTION 'Invalid input'
        USING HINT = 'Check your parameter';
  END IF;
  -- check email and password
  select auth.user_role(email, pass) into _role;
  if _role is null then
	  RAISE WARNING 'Register new account email:[%]', email;
	  INSERT INTO auth.accounts ( email, pass, first, last, role)
	    VALUES (email, pass, firstname, lastname, 'user_role');
  end if;
  return ( api.login(email, pass) );
end;
$function$
;

COMMENT ON FUNCTION api.signup(text, text, text, text) IS 'Register a user, return user JWT token';

DROP FUNCTION IF EXISTS api.export_logbook_geojson_fn;
DROP FUNCTION IF EXISTS public.logbook_get_extra_json_fn;
--DROP FUNCTION IF EXISTS api.vessel_fn;
--DROP FUNCTION IF EXISTS api.vessel_extended_fn;
--DROP FUNCTION IF EXISTS api.vessel_details_fn;

DROP VIEW IF EXISTS api.vessel_view;
-- Add api.vessel_view, replace multiple vessel function and align design
CREATE VIEW api.vessel_view
WITH (security_invoker = 'true', security_barrier = 'true')
AS
WITH latest_position AS (
    SELECT
        vessel_id,
        time,
        courseovergroundtrue,
        speedoverground,
        anglespeedapparent,
        longitude,
        latitude,
        st_makepoint(longitude, latitude) AS geo_point
    FROM api.metrics
    WHERE
        latitude IS NOT NULL
        AND longitude IS NOT NULL
        AND vessel_id = current_setting('vessel.id', false)
    ORDER BY time DESC
    LIMIT 1
)
SELECT
    -- Identity
    m.vessel_id,
    m.name,
    m.mmsi,
    v.created_at,
    m.created_at                                    AS first_contact,
    m.time                                          AS last_contact,
    (NOW() AT TIME ZONE 'UTC' - m.time)
        > INTERVAL '70 MINUTES'                     AS offline,
    -- AIS / physical
    ais.description                                 AS ship_type,
    mid.country,
    iso.alpha_2,
    m.length,
    m.beam,
    m.height,
    -- Plugin / platform
    m.plugin_version,
    m.platform,
    m.configuration IS NOT NULL                     AS has_config,
    -- Extended (make_model, polar, images)
    m.user_data -> 'make_model'                     AS make_model,
    m.user_data -> 'polar' IS NOT NULL              AS has_polar,
    jsonb_array_length(
        COALESCE(m.user_data -> 'images', '[]'::jsonb)
    ) > 0                                           AS has_images,
    m.user_data -> 'images' -> 0 ->> 'url'         AS image_url,
    m.user_data -> 'images' -> 0 ->> 'updated_at'  AS image_updated_at,
    m.user_data -> 'images'                         AS images,
    m.user_data -> 'specs'                          AS specs,
    -- Live position as GeoJSON
    jsonb_build_object(
        'type',     'Feature',
        'geometry', ST_AsGeoJSON(
                        ST_MakePoint(p.longitude, p.latitude)
                    )::jsonb,
        'properties', jsonb_build_object(
            'name',                 m.name,
            'time',                 p.time,
            'longitude',            p.longitude,
            'latitude',             p.latitude,
            'make_model',           m.user_data -> 'make_model',
            'image_url',            m.user_data -> 'images' -> 0 ->> 'url'
        )
    ) AS geojson
FROM auth.vessels v
JOIN api.metadata  m   ON m.vessel_id = v.vessel_id
LEFT JOIN aistypes ais ON ais.id = m.ship_type
LEFT JOIN mid          ON LEFT(m.mmsi, 3)::numeric = mid.id
LEFT JOIN iso3166 iso  ON iso.id = mid.country_id
LEFT JOIN latest_position p ON p.vessel_id = m.vessel_id
WHERE m.vessel_id = current_setting('vessel.id', false);

COMMENT ON VIEW api.vessel_view IS
    'Primary vessel resource view. Exposes identity, AIS metadata, physical
     dimensions, plugin info, extended profile (make/model, polar, images),
     and live GeoJSON position. Replaces api.vessel_fn(). RLS-equivalent via
     vessel.id session config. One row per authenticated vessel session.';

-- Update api.graph_logs_by_year_week_fn, update output to an array
CREATE OR REPLACE FUNCTION api.graph_logs_by_year_week_fn(OUT charts jsonb)
RETURNS jsonb
LANGUAGE sql
AS $$
WITH
_vessel AS (
    SELECT current_setting('vessel.id', true) AS id
),
raw AS (
    SELECT
        to_char(_from_time, 'IYYY')::int AS yr,
        to_char(_from_time, 'IW')::int   AS wk,
        count(*)::int                    AS cnt
    FROM api.logbook, _vessel
    WHERE vessel_id  = _vessel.id
      AND _from_time IS NOT NULL
      AND active     = false
    GROUP BY yr, wk
),
years AS (
    SELECT DISTINCT yr FROM raw
),
week_spine AS (
    SELECT
        y.yr,
        w.w AS wk,
        0   AS cnt
    FROM years y
    CROSS JOIN LATERAL (
        SELECT generate_series(1,
            CASE WHEN to_char(make_date(y.yr, 12, 28), 'IW') = '53'
                 THEN 53 ELSE 52
            END
        ) AS w
    ) w
),
merged AS (
    SELECT yr, wk, cnt FROM raw
    UNION ALL
    SELECT s.yr, s.wk, s.cnt
    FROM week_spine s
    WHERE NOT EXISTS (
        SELECT 1 FROM raw r
        WHERE r.yr = s.yr AND r.wk = s.wk
    )
),
by_year AS (
    SELECT
        yr::text                       AS year,
        jsonb_agg(cnt ORDER BY wk)     AS weekly_counts   -- array, index 0 = week 1
    FROM merged
    GROUP BY yr
)
SELECT jsonb_object_agg(year, weekly_counts ORDER BY year)
FROM by_year;
$$;

COMMENT ON FUNCTION api.graph_logs_by_year_week_fn(OUT charts jsonb) IS
'Logbook counts per ISO week per year, zero-filled.
 Returns {"2021":[0,0,...,N],...} — array with 52 or 53 elements, index 0 = ISO week 1.
 Matches the array format of graph_logs_by_year_month_fn (12 elements, index 0 = Jan).
 ISO year/week (IYYY/IW) avoids calendar-year boundary splits.
 Index: logbook_vessel_time_idx (vessel_id, _from_time DESC).';

-- DROP FUNCTION api.vessel_activity_fn();
-- Update api.vessel_activity_fn, align output with pct.
CREATE OR REPLACE FUNCTION api.vessel_activity_fn()
 RETURNS jsonb
 LANGUAGE sql
AS $function$
    WITH
    _vessel AS (
        -- Resolve once, reuse across all CTEs.
        -- missing_ok=true matches user_role RLS pattern: returns NULL (empty result)
        -- on stale JWT rather than raising an exception.
        SELECT current_setting('vessel.id', true) AS vessel_id
    ),
    log_counts AS (
        SELECT
            COUNT(*)                                             AS total,
            COUNT(*) FILTER (
                WHERE _from_time >= NOW() - INTERVAL '30 days'
            )                                                    AS last_30d,
            COUNT(*) FILTER (
                WHERE _from_time >= NOW() - INTERVAL '60 days'
                  AND _from_time <  NOW() - INTERVAL '30 days'
            )                                                    AS prev_30d
        FROM api.logbook l, _vessel
        WHERE l.active = false
          AND l.vessel_id = _vessel.vessel_id
    ),
    stay_counts AS (
        SELECT
            COUNT(*)                                             AS total,
            COUNT(*) FILTER (
                WHERE arrived >= NOW() - INTERVAL '30 days'
            )                                                    AS last_30d,
            COUNT(*) FILTER (
                WHERE arrived >= NOW() - INTERVAL '60 days'
                  AND arrived <  NOW() - INTERVAL '30 days'
            )                                                    AS prev_30d
        FROM api.stays s, _vessel
        WHERE s.active = false
          AND s.vessel_id = _vessel.vessel_id
    ),
    moorage_counts AS (
        SELECT
            COUNT(*)                                              AS total,
            -- New unique places: moorage whose FIRST ever stay arrived in last 30 days
            -- Uses stays.arrived (actual visit time) not moorages.created_at (row insert time)
            -- created_at reflects when the cron job processed the stay, not when it was visited
            COUNT(*) FILTER (
                WHERE m.id IN (
                    SELECT s.moorage_id
                    FROM api.stays s, _vessel
                    WHERE s.vessel_id    = _vessel.vessel_id
                    AND s.active       = false
                    AND s.moorage_id   IS NOT NULL
                    GROUP BY s.moorage_id
                    HAVING MIN(s.arrived) >= NOW() - INTERVAL '30 days'
                )
            )                                                    AS new_last_30d
        FROM api.moorages m, _vessel
        WHERE m.vessel_id = _vessel.vessel_id
    ),
    moorage_visits AS (
        SELECT
            COUNT(*) FILTER (
                WHERE s.arrived >= NOW() - INTERVAL '30 days'
            )                                                    AS visits_last_30d,
            COUNT(*) FILTER (
                WHERE s.arrived >= NOW() - INTERVAL '60 days'
                  AND s.arrived <  NOW() - INTERVAL '30 days'
            )                                                    AS visits_prev_30d,
            COUNT(DISTINCT m.country) FILTER (
                WHERE s.arrived >= NOW() - INTERVAL '30 days'
                  AND m.country IS NOT NULL
            )                                                    AS countries_last_30d,
            COUNT(DISTINCT m.country) FILTER (
                WHERE m.country IS NOT NULL
            )                                                    AS countries_total
        FROM api.stays s
        JOIN api.moorages m ON m.id = s.moorage_id
        CROSS JOIN _vessel
        WHERE s.active = false
          AND s.vessel_id = _vessel.vessel_id
          AND m.vessel_id = _vessel.vessel_id
    )
    SELECT jsonb_build_object(
        'logs', jsonb_build_object(
            'total',    lc.total,
            'last_30d', lc.last_30d,
            'delta',    lc.last_30d - lc.prev_30d,
            'pct',      CASE
                            WHEN lc.prev_30d = 0 THEN NULL
                            ELSE ROUND(((lc.last_30d - lc.prev_30d)::numeric
                                        / lc.prev_30d) * 100, 1)
                        END
        ),
        'stays', jsonb_build_object(
            'total',    sc.total,
            'last_30d', sc.last_30d,
            'delta',    sc.last_30d - sc.prev_30d,
            'pct',      CASE
                            WHEN sc.prev_30d = 0 THEN NULL
                            ELSE ROUND(((sc.last_30d - sc.prev_30d)::numeric
                                        / sc.prev_30d) * 100, 1)
                        END
        ),
        'moorages', jsonb_build_object(
            'total',              mc.total,
            'new_last_30d',       mc.new_last_30d,
            'visits_last_30d',    mv.visits_last_30d,
            'visits_delta',       mv.visits_last_30d - mv.visits_prev_30d,
            'pct',                CASE
                                      WHEN mv.visits_prev_30d = 0 THEN NULL
                                      ELSE ROUND(
                                          ((mv.visits_last_30d - mv.visits_prev_30d)::numeric
                                           / mv.visits_prev_30d) * 100, 1)
                                  END,
            'countries_last_30d', mv.countries_last_30d,
            'countries_total',    mv.countries_total
        )
    )
    FROM log_counts lc, stay_counts sc, moorage_counts mc, moorage_visits mv;
$function$
;

COMMENT ON FUNCTION api.vessel_activity_fn() IS 'Count logbook, stays and moorages for the current vessel with 30-day rolling activity metrics.
     Explicit vessel_id = current_setting(''vessel.id'') filter on all CTEs ensures correct isolation.
     logs/stays: total + last_30d + delta and pct vs prior 30-day window (NULL when prev=0).
     moorages: exploration metrics — new places discovered, visit activity, and country range.';

-- Add api.logs_tags_fn, sorted list of distinct tags across all completed log entries for the current vessel
CREATE OR REPLACE FUNCTION api.logs_tags_fn()
RETURNS TEXT[]
LANGUAGE sql
STABLE
SET search_path = api, public, pg_catalog
AS $$
    SELECT COALESCE(
        ARRAY(
            SELECT DISTINCT tag
            FROM api.logs_view lv,
                 jsonb_array_elements_text(lv.tags) AS tag
            WHERE lv.tags IS NOT NULL
              AND lv.tags != 'null'::jsonb
              AND jsonb_typeof(lv.tags) = 'array'
            ORDER BY tag
        ),
        ARRAY[]::TEXT[]
    )
$$;

COMMENT ON FUNCTION api.logs_tags_fn() IS
'Returns a sorted TEXT[] of all distinct log tags for the current vessel.
 NULL tags rows are skipped; returns empty array when no tags exist.';

-- Update api.stats_stays_fn, add safe start and end.
CREATE OR REPLACE FUNCTION api.stats_stays_fn(start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, end_date timestamp with time zone DEFAULT NULL::timestamp with time zone, OUT stats jsonb)
 RETURNS jsonb
 LANGUAGE sql
AS $function$
WITH
_vessel AS (
    SELECT current_setting('vessel.id', true) AS vessel_id
),
-- Base: all completed stays in the requested window
stays_base AS (
    SELECT
        s.moorage_id,
        s.duration,
        s.stay_code
    FROM api.stays s, _vessel
    WHERE s.vessel_id = _vessel.vessel_id
      AND s.active    = false
      AND s.arrived   >= COALESCE(start_date, '1980-01-01'::timestamptz)
      AND s.departed  <= COALESCE(end_date, NOW()) + INTERVAL '23 hours 59 minutes'
),
-- Moorage-level aggregation — one row per unique moorage visited
moorage_agg AS (
    SELECT
        s.moorage_id,
        SUM(s.duration) AS total_duration,
        COUNT(*)        AS stay_count
    FROM stays_base s
    GROUP BY s.moorage_id
),
-- Enrich with moorage metadata (home_flag, stay_code, country)
moorage_detail AS (
    SELECT
        m.id,
        m.home_flag,
        m.stay_code,
        ma.total_duration
    FROM api.moorages m
    JOIN moorage_agg ma ON ma.moorage_id = m.id
    , _vessel
    WHERE m.vessel_id = _vessel.vessel_id
),
-- Scalar aggregates
agg AS (
    SELECT
        COUNT(*)         FILTER (WHERE home_flag IS TRUE)  AS home_ports,
        COUNT(*)                                           AS unique_moorages,
        COALESCE(SUM(total_duration) FILTER (WHERE home_flag IS TRUE),  '0'::interval) AS time_at_home_ports,
        COALESCE(SUM(total_duration) FILTER (WHERE home_flag IS FALSE), '0'::interval) AS time_spent_away
    FROM moorage_detail
),
-- Stay-type breakdown for away time
-- Avoid join api.stays_at for the canonical description string
-- stay_code 1=Unknown, 2=Anchor, 3=Mooring Buoy, 4=Dock
away_by_type AS (
    SELECT
        (ARRAY['Unknown','Anchor','Mooring Buoy','Dock'])[md.stay_code] AS description,
        SUM(md.total_duration) AS duration
    FROM moorage_detail md
    WHERE md.home_flag IS FALSE
    GROUP BY md.stay_code
    ORDER BY md.stay_code
)
SELECT jsonb_build_object(
    'home_ports',         a.home_ports,
    'unique_moorages',    a.unique_moorages,
    'time_at_home_ports', a.time_at_home_ports,
    'time_spent_away',    a.time_spent_away,
    -- Replaces stats_moorages_away_view (was a separate multi-row endpoint)
    'time_spent_away_by', COALESCE(
        (SELECT jsonb_agg(
            jsonb_build_object(
                'description', t.description,
                'duration',    t.duration
            )
            ORDER BY t.description
        ) FROM away_by_type t),
        '[]'::jsonb
    )
)
FROM agg a;
$function$
;

COMMENT ON FUNCTION api.stats_stays_fn(in timestamptz, in timestamptz, out jsonb) IS 'Stays and moorage statistics for the current vessel within a date range (NULL = all-time).
     Replaces api.stats_moorages_view and api.stats_moorages_away_view:
       - date range filter
       - time_spent_away_by breakdown by stay type folded in as a JSONB array
         [ { description, duration }, ... ] ordered by stay_code
     Reads api.stays + api.moorages directly — no moorage_view dependency.
     Explicit vessel_id filter on all CTEs.';

-- Update api.stats_logs_fn, add safe start and end.
CREATE OR REPLACE FUNCTION api.stats_logs_fn(start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, end_date timestamp with time zone DEFAULT NULL::timestamp with time zone, OUT stats jsonb)
 RETURNS jsonb
 LANGUAGE sql
AS $function$
WITH
-- Resolve vessel once; reused across all CTEs
_vessel AS (
    SELECT current_setting('vessel.id', true) AS vessel_id
),

-- -------------------------------------------------------------------------
-- Base scan: completed logs in the requested window
-- Uses logbook_vessel_id_idx (vessel_id) + active=false + time range filter
-- _to_time IS NOT NULL guard: active=false guarantees it in practice but
-- makes the range predicate safe and visible to the planner
-- -------------------------------------------------------------------------
logs_base AS (
    SELECT
        l.id,
        l._from_time,
        l._to_time,
        l.avg_speed,
        l.max_speed,
        l.max_wind_speed,
        l.distance,
        l.duration
    FROM api.logbook l, _vessel
    WHERE l.vessel_id    = _vessel.vessel_id
      AND l.active       = false
      AND l.trip         IS NOT NULL
      AND l._from_time   IS NOT NULL
      AND l._to_time     IS NOT NULL
      AND l._from_time   >= COALESCE(start_date, '1980-01-01'::timestamptz)
      AND l._to_time     <= COALESCE(end_date,   NOW()::timestamptz)
),

-- -------------------------------------------------------------------------
-- Single aggregation pass — all counts, sums and maxima
-- -------------------------------------------------------------------------
logs_agg AS (
    SELECT
        COUNT(*)                AS count,
        MIN(_from_time)         AS first_date,
        MAX(_to_time)           AS last_date,
        MAX(max_speed)          AS max_speed,
        MAX(max_wind_speed)     AS max_wind_speed,
        MAX(distance)           AS max_distance,
        SUM(distance)           AS sum_distance,
        MAX(duration)           AS max_duration,
        SUM(duration)           AS sum_duration
    FROM logs_base
),

-- -------------------------------------------------------------------------
-- Record-holder IDs: two-CTE pattern required because PostgreSQL does not
-- allow window functions inside FILTER clauses.
--   Step 1 — ranked: materialise rank values as plain integer columns
--   Step 2 — max_ids: FILTER on those plain integers (no window fn here)
-- MIN(id) on ties: deterministic (lowest id wins), consistent with original.
-- -------------------------------------------------------------------------
ranked AS (
    SELECT
        id,
        RANK() OVER (ORDER BY max_speed      DESC NULLS LAST) AS rk_speed,
        RANK() OVER (ORDER BY max_wind_speed DESC NULLS LAST) AS rk_wind,
        RANK() OVER (ORDER BY distance       DESC NULLS LAST) AS rk_dist,
        RANK() OVER (ORDER BY duration       DESC NULLS LAST) AS rk_dur
    FROM logs_base
),
max_ids AS (
    SELECT
        MIN(id) FILTER (WHERE rk_speed = 1) AS max_speed_id,
        MIN(id) FILTER (WHERE rk_wind  = 1) AS max_wind_speed_id,
        MIN(id) FILTER (WHERE rk_dist  = 1) AS max_distance_id,
        MIN(id) FILTER (WHERE rk_dur   = 1) AS max_duration_id
    FROM ranked
),

-- -------------------------------------------------------------------------
-- Vessel name — PK lookup on metadata (vessel_id is PRIMARY KEY)
-- -------------------------------------------------------------------------
meta AS (
    SELECT m.name
    FROM api.metadata m, _vessel
    WHERE m.vessel_id = _vessel.vessel_id
),

-- -------------------------------------------------------------------------
-- SignalK plugin connection bounds — respects the same date window as logs.
-- Returns first/last plugin contact within [start_date, end_date].
-- NULL when no metrics exist in the window (consistent with first_date/last_date).
-- Uses metrics_vessel_id_time_idx (vessel_id, time DESC).
-- -------------------------------------------------------------------------
metrics_bounds AS (
    SELECT
        MIN(m.time) AS metrics_first,
        MAX(m.time) AS metrics_last
    FROM api.metrics m, _vessel
    WHERE m.vessel_id = _vessel.vessel_id
      AND (start_date IS NULL OR m.time >= start_date)
      AND (end_date   IS NULL OR m.time <= end_date)
      --AND m.time >= COALESCE(start_date, '1980-01-01'::timestamptz)
      --AND m.time <= COALESCE(end_date,   NOW()::timestamptz)
),

-- -------------------------------------------------------------------------
-- Best 24h sailing window — skipped when a date filter is active.
-- best_24h_distance_fn always scans full vessel history regardless of the
-- date range passed here. Returning it inside a filtered call would give a
-- best-24h window that may fall outside the requested date range, which is
-- misleading. The guard uses the raw PARAMETER values (start_date, end_date)
-- not any COALESCEd locals — NULL means "no filter was requested".
-- -------------------------------------------------------------------------
best24h AS (
    SELECT
        b.best_distance_nm,
        b.window_start,
        b.anchor_log_id,
        b.route_summary
    FROM public.best_24h_distance_fn(
        (SELECT vessel_id FROM _vessel)
    ) b
    WHERE start_date IS NULL
      AND end_date   IS NULL
)

-- -------------------------------------------------------------------------
-- Assemble result
-- CROSS JOIN is correct: logs_agg, max_ids, meta, metrics_bounds are all
-- guaranteed single-row CTEs. COALESCE to '{}' is a safe fallback for
-- vessels with no logbook data yet.
-- -------------------------------------------------------------------------
SELECT COALESCE(
    jsonb_build_object(
        -- Vessel identity
        'name',                  m.name,

        -- Sailing activity time bounds (from logbook)
        'first_date',            a.first_date,
        'last_date',             a.last_date,

        -- SignalK plugin connection time bounds (from metrics, always all-time)
        'metrics_first',         mb.metrics_first,
        'metrics_last',          mb.metrics_last,

        -- Totals
        'count',                 a.count,
        'sum_distance',          a.sum_distance,
        'sum_duration',          a.sum_duration,

        -- Records with deep-link IDs
        'max_speed',             a.max_speed,
        'max_speed_id',          i.max_speed_id,
        'max_wind_speed',        a.max_wind_speed,
        'max_wind_speed_id',     i.max_wind_speed_id,
        'max_distance',          a.max_distance,
        'max_distance_id',       i.max_distance_id,
        'max_duration',          a.max_duration,
        'max_duration_id',       i.max_duration_id,

        -- Formatted longest trip summary
        -- FIX 3: CASE prevents CONCAT from producing ' NM,  hours' on empty range
        'longest_nonstop_sail',  CASE
                                     WHEN a.max_distance IS NULL THEN NULL
                                     ELSE CONCAT(
                                         a.max_distance, ' NM, ',
                                         a.max_duration, ' hours'
                                     )
                                 END,

        -- Best 24h window — NULL when date filter is active (see best24h CTE)
        'best_24h_distance_nm',  (SELECT best_distance_nm FROM best24h),
        'best_24h_window_start', (SELECT window_start     FROM best24h),
        'best_24h_log_id',       (SELECT anchor_log_id    FROM best24h),
        'best_24h_route',        (SELECT route_summary    FROM best24h)
    ),
    '{}'::jsonb
)
FROM logs_agg     a
CROSS JOIN max_ids       i
CROSS JOIN meta          m
CROSS JOIN metrics_bounds mb;
$function$
;

COMMENT ON FUNCTION api.stats_logs_fn(in timestamptz, in timestamptz, out jsonb) IS 'Logbook statistics for the current vessel within an optional date range.
     Pass NULL for both parameters to get all-time statistics (default).

     Output fields:
       name                — vessel name from metadata
       first_date          — _from_time of earliest completed log in range
       last_date           — _to_time of latest completed log in range
       metrics_first       — earliest SignalK plugin contact (all-time, not date-filtered)
       metrics_last        — latest SignalK plugin contact (all-time, not date-filtered)
       count               — number of completed logs in range
       sum_distance        — total distance sailed (NM)
       sum_duration        — total time underway (interval)
       max_speed           — highest recorded max_speed, with max_speed_id for deep-link
       max_wind_speed      — highest recorded wind speed, with max_wind_speed_id
       max_distance        — longest single leg, with max_distance_id
       max_duration        — longest single leg by time, with max_duration_id
       longest_nonstop_sail — formatted: "X NM, Y hours" (NULL when no logs in range)
       best_24h_distance_nm — best 24h rolling window distance (NULL when date-filtered)
       best_24h_window_start — start of that window (NULL when date-filtered)
       best_24h_log_id       — anchor log id for map highlight (NULL when date-filtered)
       best_24h_route        — "from → to" summary (NULL when date-filtered)

     Replaces api.stats_logs_view (now a deprecated shim over this function).

     Design notes:
       - VOLATILE (not STABLE): reads current_setting() which is session state,
         not a parameter; STABLE would allow incorrect cross-user plan caching.
       - Explicit vessel_id filter on all CTEs: correct under admin role where
         RLS is USING(true) and would otherwise return cross-vessel counts.
       - best_24h guards on raw parameter NULLs: callers must pass NULL (not a
         COALESCEd substitute) to receive best_24h data. stats_fn passes the
         original NULLs unchanged for this reason.
       - COALESCE result to ''{}'': safe empty return for new vessels with no logs.';

-- Update api.stats_fn, include name and expose moorage name, plus add top countries for moorages.
CREATE OR REPLACE FUNCTION api.stats_fn(
    start_date  TIMESTAMPTZ DEFAULT NULL,
    end_date    TIMESTAMPTZ DEFAULT NULL,
    OUT stats   JSONB
) RETURNS JSONB
LANGUAGE plpgsql AS $$
DECLARE
    _vessel_id  TEXT        := current_setting('vessel.id', true);
    _start      TIMESTAMPTZ := COALESCE(start_date, '1980-01-01'); -- GPS week 0 epoch
    _end_incl   TIMESTAMPTZ := COALESCE(end_date, NOW()) + INTERVAL '23 hours 59 minutes';
BEGIN
    RAISE NOTICE '--> stats_fn start[%] end[%]', _start, _end_incl;

    stats := jsonb_build_object(
        'stats_logs',     api.stats_logs_fn(start_date, end_date),
        'stats_moorages', api.stats_stays_fn(start_date, end_date)
    );

    WITH
    -- -----------------------------------------------------------------------
    -- Logbook top-5s
    -- -----------------------------------------------------------------------
    logs_base AS (
        SELECT id, name, avg_speed, max_speed, max_wind_speed, distance, duration
        FROM api.logbook                          -- ← add name here
        WHERE vessel_id  = _vessel_id
          AND active     = false
          AND trip       IS NOT NULL
          AND _from_time >= _start
          AND _to_time   <= _end_incl
    ),
    logs_top_speed AS (
        SELECT id, name, max_speed
        FROM logs_base
        WHERE max_speed IS NOT NULL
        ORDER BY max_speed DESC NULLS LAST
        LIMIT 5
    ),
    logs_top_avg_speed AS (
        SELECT id, name, avg_speed
        FROM logs_base
        WHERE avg_speed IS NOT NULL
        ORDER BY avg_speed DESC NULLS LAST
        LIMIT 5
    ),
    logs_top_wind_speed AS (
        SELECT id, name, max_wind_speed
        FROM logs_base
        WHERE max_wind_speed IS NOT NULL
        ORDER BY max_wind_speed DESC NULLS LAST
        LIMIT 5
    ),
    logs_top_distance AS (
        SELECT id, name, distance               -- ← was bare id only
        FROM logs_base
        WHERE distance IS NOT NULL
        ORDER BY distance DESC NULLS LAST
        LIMIT 5
    ),
    logs_top_duration AS (
        SELECT id, name, duration               -- ← was bare id only
        FROM logs_base
        WHERE duration IS NOT NULL
        ORDER BY duration DESC NULLS LAST
        LIMIT 5
    ),
    -- -----------------------------------------------------------------------
    -- Moorage top-5s
    -- -----------------------------------------------------------------------
    stays_agg AS (
        SELECT
            s.moorage_id,
            SUM(s.duration) AS total_duration,
            COUNT(s.id)     AS reference_count
        FROM api.stays s
        WHERE s.vessel_id = _vessel_id
          AND s.active    = false
          AND s.arrived   >= _start
          AND s.departed  <= _end_incl
        GROUP BY s.moorage_id
    ),
    moorages AS (
        SELECT
            m.id,
            m.name      AS moorage,              -- ← expose the name here
            m.country,
            sa.total_duration  AS dur,
            sa.reference_count AS ref_count
        FROM api.moorages m
        JOIN stays_agg sa ON sa.moorage_id = m.id
        WHERE m.vessel_id = _vessel_id
    ),
    moorages_top_arrivals AS (
        SELECT id, moorage, ref_count           -- ← add moorage
        FROM moorages
        ORDER BY ref_count DESC NULLS LAST
        LIMIT 5
    ),
    moorages_top_duration AS (
        SELECT id, moorage, dur                 -- ← add moorage
        FROM moorages
        ORDER BY dur DESC NULLS LAST
        LIMIT 5
    ),
    moorages_countries AS (
        SELECT DISTINCT country
        FROM moorages
        WHERE country IS NOT NULL
          AND country <> 'unknown'
        ORDER BY country
        LIMIT 5
    )
    SELECT stats || jsonb_build_object(
        'logs_top_speed',         (SELECT jsonb_agg(t ORDER BY t.max_speed       DESC, t.id ASC) FROM logs_top_speed         t),
        'logs_top_avg_speed',     (SELECT jsonb_agg(t ORDER BY t.avg_speed       DESC, t.id ASC) FROM logs_top_avg_speed     t),
        'logs_top_wind_speed',    (SELECT jsonb_agg(t ORDER BY t.max_wind_speed  DESC, t.id ASC) FROM logs_top_wind_speed    t),
        'logs_top_distance',      (SELECT jsonb_agg(t ORDER BY t.distance        DESC, t.id ASC) FROM logs_top_distance      t),
        'logs_top_duration',      (SELECT jsonb_agg(t ORDER BY t.duration        DESC, t.id ASC) FROM logs_top_duration      t),
        'moorages_top_arrivals',  (SELECT jsonb_agg(t ORDER BY t.ref_count       DESC, t.id ASC) FROM moorages_top_arrivals  t),
        'moorages_top_duration',  (SELECT jsonb_agg(t ORDER BY t.dur             DESC, t.id ASC) FROM moorages_top_duration  t),
        'moorages_top_countries', (SELECT jsonb_agg(t.country) FROM moorages_countries t)
    ) INTO stats;
END;
$$;
COMMENT ON FUNCTION api.stats_fn IS 'Composite statistics for the current vessel within a date range (NULL = all-time).
     Delegates base aggregates to stats_logs_fn + stats_stays_fn (both remain
     independently callable as PostgREST endpoints), then adds top-5 rankings
     for speed, wind, distance, duration, and moorage arrivals/duration/countries.
     Output keys:
       stats_logs     : full stats_logs_fn output (see that function for field list)
       stats_moorages : full stats_stays_fn output (see that function for field list)
       logs_top_speed      : [{id, name, max_speed}, ...]
       logs_top_avg_speed  : [{id, name, avg_speed}, ...]
       logs_top_wind_speed : [{id, name, max_wind_speed}, ...]
       logs_top_distance   : [{id, name, distance}, ...]
       logs_top_duration   : [{id, name, duration}, ...]
       moorages_top_arrivals : [{id, moorage, ref_count}, ...]
       moorages_top_duration : [{id, moorage, dur}, ...]
       moorages_top_countries: [country, ...]';

DROP FUNCTION IF EXISTS api.badges_fn;
-- Update api.badges_fn, rewrite in JSONB
CREATE OR REPLACE FUNCTION api.badges_fn(OUT badges jsonb)
    RETURNS jsonb
    LANGUAGE sql
    SECURITY DEFINER
    SET search_path TO 'public', 'pg_catalog'
AS $$
    SELECT jsonb_agg(
        jsonb_build_object(
            'name',        b.name,
            'description', b.description,
            'earned_at',   (e.value->>'date')::timestamptz,
            'logbook_id',  (e.value->>'log')::int
        )
        ORDER BY (e.value->>'date')::timestamptz
    )
    FROM auth.accounts a
    JOIN LATERAL jsonb_each(a.preferences->'badges') e ON true
    JOIN public.badges b ON b.name = e.key
    WHERE a.email = current_setting('user.email');
$$;

COMMENT ON FUNCTION api.badges_fn(OUT badges jsonb) IS
'Return earned badges for the current user.
 Rewritten from plpgsql to sql (inlinable by planner).
 Explicit LATERAL join replaces comma-join to eliminate operator precedence ambiguity.
 jsonb_agg + jsonb_build_object replaces json_agg(row_to_json()) for consistent jsonb output type.
 STABLE declared: no side effects, result is repeatable within a transaction.';

-- Update api.graph_logs_by_week_fn, reduce security definer surface
CREATE OR REPLACE FUNCTION api.graph_logs_by_week_fn(OUT charts jsonb)
 RETURNS jsonb
 LANGUAGE sql
AS $function$
    WITH
    _vessel AS (
        SELECT current_setting('vessel.id', true) AS vessel_id
    ),
    weeks AS (
        SELECT lpad(generate_series(1, 52)::text, 2, '0') AS wk
    ),
    raw AS (
        SELECT
            to_char(l._from_time, 'IW') AS wk,
            count(*)::int                AS cnt
        FROM api.logbook l, _vessel
        WHERE l.vessel_id  = _vessel.vessel_id
          AND l.active     = false
          AND l._from_time IS NOT NULL
        GROUP BY 1
    )
    SELECT jsonb_object_agg(w.wk, COALESCE(r.cnt, 0) ORDER BY w.wk)
    FROM weeks w
    LEFT JOIN raw r ON r.wk = w.wk;
$function$
;

COMMENT ON FUNCTION api.graph_logs_by_week_fn(out jsonb) IS 'Count of completed logbook entries by ISO week number for the current vessel.
     Output: {"01":0, "02":3, ..., "52":0}. All 52 weeks always present (zero-filled).
     Uses ISO 8601 week numbering (IW): week 01 contains the first Thursday of January.
     Index: logbook_vessel_time_idx (vessel_id, _from_time DESC).';

COMMENT ON TABLE api.stays_at IS
  'Stay type lookup table (1=Unknown, 2=Anchor, 3=Mooring Buoy, 4=Dock).
   Static reference data, no RLS required or enabled.
   All authenticated roles have SELECT access via role GRANTs.';

CREATE OR REPLACE FUNCTION public.stay_in_progress_fn(_vessel_id text)
RETURNS integer
LANGUAGE sql
STABLE                          -- reads DB, same result within transaction
PARALLEL SAFE
SET search_path = 'api', 'public', 'pg_catalog'
AS $$
    SELECT id
    FROM api.stays
    WHERE vessel_id = _vessel_id
      AND active IS true
    LIMIT 1;
$$;
COMMENT ON FUNCTION public.stay_in_progress_fn(text) IS
'Returns the id of the active stay for _vessel_id, or NULL if none.
 Called by metrics_trigger_fn on status transitions.';

CREATE OR REPLACE FUNCTION public.trip_in_progress_fn(_vessel_id text)
RETURNS integer
LANGUAGE sql
STABLE
PARALLEL SAFE
SET search_path = 'api', 'public', 'pg_catalog'
AS $$
    SELECT id
    FROM api.logbook
    WHERE vessel_id = _vessel_id
      AND active IS true
    LIMIT 1;
$$;
COMMENT ON FUNCTION public.trip_in_progress_fn(text) IS
'Returns the id of the active logbook entry for _vessel_id, or NULL if none.
 Called by metrics_trigger_fn on status transitions.';

-- Update api.vessel_extended_fn, add vessel specs
CREATE OR REPLACE FUNCTION api.vessel_extended_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id text := current_setting('vessel.id', false);
    result jsonb;
BEGIN
    SELECT jsonb_build_object(
          'make_model', m.user_data->'make_model',
          'has_polar', m.user_data->'polar' IS NOT NULL,
          'has_images',
            CASE
              WHEN jsonb_array_length(m.user_data->'images') > 0 THEN true
              ELSE false
            END,
          'image_url', m.user_data->'images'->0->>'url',
          'image_updated_at', m.user_data->'images'->0->>'updated_at',
          'images', m.user_data->'images',
          'spec', m.user_data->'spec'
      )
      INTO result
      FROM api.metadata m
      WHERE vessel_id = v_id;

    IF result IS NULL THEN
        result := jsonb_build_object(
            'make_model', NULL,
            'has_polar', false,
            'has_image', false,
            'image_url', NULL,
            'image_updated_at', NULL
        );
    END IF;

    RETURN result;
END;
$function$
;

COMMENT ON FUNCTION api.vessel_extended_fn() IS 'Return vessel details from metadata_ext (polar csv,image url, make model)';

-- Update public.logbook_update_extra_json_fn, add tank level deltas and refactor to reduce redundant code
CREATE OR REPLACE FUNCTION public.logbook_update_extra_json_fn(
    _id    integer,
    _start text,
    _end   text,
    OUT _extra_json json
)
RETURNS json
LANGUAGE plpgsql
AS $function$
DECLARE
    log_json      jsonb DEFAULT '{}'::jsonb;
    runtime_json  jsonb DEFAULT '{}'::jsonb;
    tanks_json    jsonb DEFAULT '{}'::jsonb;
    solar_json    jsonb DEFAULT '{}'::jsonb;
    metrics_json  jsonb DEFAULT '{}'::jsonb;
    metric_rec    record;
    _avg_solar_w  double precision;
    _duration_h   double precision;
    _solar_wh     double precision;
BEGIN
    -- -----------------------------------------------------------------------
    -- navigation.log — trip distance delta (meters → nautical miles)
    -- -----------------------------------------------------------------------
    WITH
        start_trip AS (
            SELECT key, value
            FROM api.metrics m, jsonb_each_text(m.metrics)
            WHERE key ILIKE 'navigation.log'
              AND time = _start::TIMESTAMPTZ
              AND vessel_id = current_setting('vessel.id', false)
        ),
        end_trip AS (
            SELECT key, value
            FROM api.metrics m, jsonb_each_text(m.metrics)
            WHERE key ILIKE 'navigation.log'
              AND time = _end::TIMESTAMPTZ
              AND vessel_id = current_setting('vessel.id', false)
        ),
        nm AS (
            SELECT ((end_trip.value::NUMERIC - start_trip.value::NUMERIC) * 0.00053996) AS trip
            FROM start_trip, end_trip
        )
    SELECT jsonb_build_object('navigation.log', trip) INTO log_json FROM nm;
    RAISE NOTICE '-> logbook_update_extra_json_fn navigation.log: %', log_json;

    -- -----------------------------------------------------------------------
    -- propulsion.%.runTime — engine hours per trip as ISO 8601 duration
    -- Delta: end - start seconds, converted to interval
    -- Accumulated across multiple engines (port, main, starboard…)
    -- -----------------------------------------------------------------------
    FOR metric_rec IN
        SELECT key, value
        FROM api.metrics m, jsonb_each_text(m.metrics)
        WHERE key ILIKE 'propulsion.%.runTime'
          AND time = _start::TIMESTAMPTZ
          AND vessel_id = current_setting('vessel.id', false)
    LOOP
        RAISE NOTICE '-> logbook_update_extra_json_fn propulsion.runTime start: %', metric_rec;
        WITH
            end_runtime AS (
                SELECT value
                FROM api.metrics m, jsonb_each_text(m.metrics)
                WHERE key ILIKE metric_rec.key
                  AND time = _end::TIMESTAMPTZ
                  AND vessel_id = current_setting('vessel.id', false)
            ),
            runtime AS (
                SELECT (((end_runtime.value::NUMERIC - metric_rec.value::NUMERIC) / 3600)
                        * '1 hour'::interval)::interval AS value
                FROM end_runtime
            )
        -- Accumulate: || merges all engine keys into one object
        SELECT runtime_json || jsonb_build_object(metric_rec.key, value)
        INTO runtime_json
        FROM runtime;
        RAISE NOTICE '-> logbook_update_extra_json_fn runtime_json: %', runtime_json;
    END LOOP;

    -- -----------------------------------------------------------------------
    -- tanks.%.currentLevel — level change per tank per trip
    -- SignalK unit: ratio [0-1]
    -- Delta: end - start (negative = consumed, positive = refilled/refuelled)
    -- Covers all tank types: fuel, freshWater, blackWater, liveWell, etc.
    -- Accumulated across multiple tanks of the same type
    -- -----------------------------------------------------------------------
    FOR metric_rec IN
        SELECT key, value
        FROM api.metrics m, jsonb_each_text(m.metrics)
        WHERE key ILIKE 'tanks.%.currentLevel'
          AND time = _start::TIMESTAMPTZ
          AND vessel_id = current_setting('vessel.id', false)
    LOOP
        RAISE NOTICE '-> logbook_update_extra_json_fn tanks.currentLevel start: %', metric_rec;
        WITH
            end_level AS (
                SELECT value
                FROM api.metrics m, jsonb_each_text(m.metrics)
                WHERE key ILIKE metric_rec.key
                  AND time = _end::TIMESTAMPTZ
                  AND vessel_id = current_setting('vessel.id', false)
            ),
            delta AS (
                -- negative = level dropped (consumed)
                -- positive = level rose (refuelled/refilled underway)
                SELECT ROUND(
                    (end_level.value::NUMERIC - metric_rec.value::NUMERIC),
                    4
                ) AS value
                FROM end_level
            )
        -- Accumulate: || merges all tank keys into one object
        SELECT tanks_json || jsonb_build_object(metric_rec.key, value)
        INTO tanks_json
        FROM delta;
        RAISE NOTICE '-> logbook_update_extra_json_fn tanks_json: %', tanks_json;
    END LOOP;

    -- -----------------------------------------------------------------------
    -- Solar energy produced per trip (Wh)
    -- Uses trip_solar_power (MobilityDB tfloatseq, W) already on the logbook row.
    -- twAvg = time-weighted average power (W) × trip duration (h) = Wh produced.
    -- No api.metrics scan — computed from the MobilityDB sequence directly.
    -- NULL when vessel has no solar sensor (trip_solar_power IS NULL).
    -- Compare with tanks.%.currentLevel delta for motor vs solar balance.
    -- -----------------------------------------------------------------------
    SELECT
        twAvg(trip_solar_power),
        EXTRACT(EPOCH FROM duration) / 3600.0
    INTO _avg_solar_w, _duration_h
    FROM api.logbook
    WHERE id = _id;

    IF _avg_solar_w IS NOT NULL AND _avg_solar_w > 0 AND _duration_h IS NOT NULL AND _duration_h > 0 THEN
        _solar_wh := ROUND((_avg_solar_w * _duration_h)::NUMERIC, 1);
        solar_json := jsonb_build_object('solar.energy_wh', _solar_wh);
        RAISE NOTICE '-> logbook_update_extra_json_fn solar_json: % (avg_w=%, duration_h=%)',
            solar_json, _avg_solar_w, _duration_h;
    END IF;

    -- -----------------------------------------------------------------------
    -- Assemble final extra JSON
    -- All sub-objects merged into metrics key
    -- -----------------------------------------------------------------------
    SELECT
        COALESCE(log_json,     '{}'::jsonb)
        || COALESCE(runtime_json, '{}'::jsonb)
        || COALESCE(tanks_json,   '{}'::jsonb)
        || COALESCE(solar_json,   '{}'::jsonb)
    INTO metrics_json;

    SELECT jsonb_build_object('metrics', metrics_json) INTO _extra_json;
    RAISE NOTICE '-> logbook_update_extra_json_fn _extra_json: %', _extra_json;
END;
$function$;

COMMENT ON FUNCTION public.logbook_update_extra_json_fn(int4, text, text, OUT json) IS
    'Compute per-trip SignalK metric deltas and store in logbook.extra->metrics. '
    'navigation.log: trip distance delta (meters → NM). '
    'propulsion.%.runTime: engine hours as ISO 8601 duration per engine (end - start). '
    'tanks.%.currentLevel: level change ratio per tank [-1..1] '
    '(negative = consumed, positive = refilled). Covers fuel/freshWater/blackWater/liveWell. '
    'solar.energy_wh: total solar energy produced (Wh) = twAvg(trip_solar_power) × duration_h. '
    'Computed from MobilityDB trip_solar_power sequence — no api.metrics scan. '
    'Multiple engines and multiple tanks handled via ILIKE loop accumulation.';

-- DROP FUNCTION public.overpass_py_fn(in numeric, in numeric, in bool, out jsonb);
-- Update public.overpass_py_fn, increase timeout
CREATE OR REPLACE FUNCTION public.overpass_py_fn(lon numeric, lat numeric, retry boolean DEFAULT false, OUT geo jsonb)
 RETURNS jsonb
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
 IMMUTABLE STRICT
 SET statement_timeout TO '0'
AS $function$
    """
    Return https://overpass-turbo.eu seamark details within 400m
    https://overpass-turbo.eu/s/1EaG
    https://wiki.openstreetmap.org/wiki/Key:seamark:type
    """
    import requests
    import json
    import urllib.parse

    headers = {'User-Agent': 'PostgSail', 'From': 'postgsail@localhost'}
    payload = """
[out:json][timeout:20];
is_in({0},{1})->.result_areas;
(
  area.result_areas["seamark:type"~"(mooring|harbour)"][~"^seamark:.*:category$"~"."][~"name"~"."];
  area.result_areas["seamark:type"~"(anchorage|anchor_berth|berth)"][~"name"~"."];
  area.result_areas["leisure"="marina"][~"name"~"."];
);
out tags;
nwr(around:400.0,{0},{1})->.all;
(
  nwr.all["seamark:type"~"(mooring|harbour)"][~"^seamark:.*:category$"~"."][~"name"~"."];
  nwr.all["seamark:type"~"(anchorage|anchor_berth|berth)"][~"name"~"."];
  nwr.all["leisure"="marina"][~"name"~"."];
  nwr.all["natural"~"(bay|beach)"][~"name"~"."];
  //nwr.all["waterway"="fuel"];
);
out tags;
    """.format(lat, lon)
    data = urllib.parse.quote(payload, safe="");
    url = f'https://overpass.private.coffee/api/interpreter?data={data}'.format(data)
    if retry:
        plpy.notice('overpass-api Retrying overpass-api.de API call')
        url = f'https://overpass-api.de/api/interpreter?data={data}'.format(data)
    
    try:
        # Add reasonable timeout: 60 seconds for connection, 120 seconds for read
        r = requests.get(url, headers=headers, timeout=(60, 120))
        #print(r.text)
        #plpy.notice(url)
        plpy.notice('overpass-api coord lon[{}] lat[{}] [{}]'.format(lon, lat, r.status_code))
        if r.status_code == 200:
            try:
                r_dict = r.json()
            except ValueError as e:
                plpy.notice('overpass-api Failed to decode JSON: {}'.format(e))
                #plpy.notice('Response text: {}'.format(r.text))
                return { "error": "invalid_json" };
            r_dict = r.json()
            #plpy.notice('overpass-api Got [{}]'.format(r_dict["elements"]))
            if "elements" in r_dict and r_dict["elements"]:
                if "tags" in r_dict["elements"][0] and r_dict["elements"][0]["tags"]:
                    return r_dict["elements"][0]["tags"]; # return the first element
            return { "error": "empty" };
        else:
            #plpy.notice('overpass-api Failed to get overpass-api details')
            plpy.notice('overpass-api Failed to get overpass-api details with status code: {}'.format(r.status_code))
            #plpy.notice('overpass-api Failed Response text: {}'.format(r.text))
            return { "error": "failed_request" };

    except requests.exceptions.Timeout:
        plpy.warning('overpass-api Request timed out after 120s')
        return {"error": "timeout"}
        
    except requests.exceptions.RequestException as e:
        plpy.warning('overpass-api Request exception: {}'.format(str(e)))
        return {"error": "request_exception"}
        
    except Exception as e:
        plpy.error('overpass-api Unexpected exception: {}'.format(str(e)))
        return {"error": "unexpected_exception"}
$function$
;

COMMENT ON FUNCTION public.overpass_py_fn(in numeric, in numeric, in bool, out jsonb) IS 'Return https://overpass-turbo.eu seamark details within 400m using plpython3u';

CREATE OR REPLACE FUNCTION public.wikipedia_py_fn(
    lat double precision,
    lon double precision,
    _radius_m integer DEFAULT 5000,
    _limit   integer DEFAULT 10
)
RETURNS jsonb
LANGUAGE plpython3u
AS $$
    import requests, json

    headers = {
        "User-Agent": "PostgSail/1.0 (https://github.com/xbgmsharp/postgsail; postgsail@localhost)",
        "Accept": "application/json"
    }

    # Step 1: GeoSearch to get pageids near the coordinate
    geo_params = {
        "action":    "query",
        "list":      "geosearch",
        "gscoord":   f"{lat}|{lon}",
        "gsradius":  min(_radius_m, 10000),   # API hard cap
        "gslimit":   min(_limit, 50),
        "format":    "json"
    }
    try:
        r = requests.get(
            "https://en.wikipedia.org/w/api.php",
            headers=headers,
            params=geo_params,
            timeout=(30, 60)
        )
        r.raise_for_status()
        geo_data = r.json()
    except Exception as e:
        plpy.warning(f"wikipedia_py_fn geosearch error: {e}")
        return json.dumps({"error": str(e)})

    pages = geo_data.get("query", {}).get("geosearch", [])
    if not pages:
        return json.dumps([])

    pageids = "|".join(str(p["pageid"]) for p in pages)
    dist_map = {p["pageid"]: p["dist"] for p in pages}

    # Step 2: Fetch extracts + coordinates for all pageids in one call
    prop_params = {
        "action":       "query",
        "pageids":      pageids,
        "prop":         "extracts|coordinates|info",
        "exintro":      "1",
        "explaintext":  "1",
        "exsentences":  "3",     # limit extract length
        "inprop":       "url",
        "format":       "json"
    }
    try:
        r2 = requests.get(
            "https://en.wikipedia.org/w/api.php",
            headers=headers,
            params=prop_params,
            timeout=(30, 60)
        )
        r2.raise_for_status()
        prop_data = r2.json()
    except Exception as e:
        plpy.warning(f"wikipedia_py_fn props error: {e}")
        return json.dumps({"error": str(e)})

    result = []
    for pid_str, page in prop_data.get("query", {}).get("pages", {}).items():
        pid = int(pid_str)
        coords = page.get("coordinates", [{}])
        result.append({
            "name":        page.get("title", ""),
            "description": (page.get("extract", "") or "").strip(),
            "url":         page.get("fullurl", f"https://en.wikipedia.org/?curid={pid}"),
            "latitude":    coords[0].get("lat") if coords else None,
            "longitude":   coords[0].get("lon") if coords else None,
            "distance":    dist_map.get(pid),
            "icon":        "wikipedia"
        })

    # Sort by distance ascending
    result.sort(key=lambda x: x["distance"] or 9999999)
    return json.dumps(result)
$$;
COMMENT ON FUNCTION public.wikipedia_py_fn IS
    'Fetch Wikipedia POIs near a coordinate using the MediaWiki GeoSearch API.
     Returns JSON array sorted by distance (meters).
     Radius capped at 10000m (API limit). Calls 2 Wikipedia endpoints per invocation.
     Results stored in moorages.user_data->wikipedia for caching.';

-- Public API endpoint: GET /rpc/pois_fn?latitude=47.6&longitude=-122.3&radius_m=2000
CREATE OR REPLACE FUNCTION api.pois_fn(
    latitude  double precision,
    longitude double precision,
    radius_m  integer DEFAULT 5000
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE                          -- reads current_setting('vessel.id')
SECURITY DEFINER
SET search_path = api, public, pg_catalog
AS $$
DECLARE
    _result     jsonb;
BEGIN

    _result := public.wikipedia_py_fn(latitude, longitude, radius_m, 15)::jsonb;

    RETURN COALESCE(_result, '[]'::jsonb);
END;
$$;
COMMENT ON FUNCTION api.pois_fn IS
    'Return Wikipedia POIs near a coordinate.
     Serves from moorages.user_data->wikipedia cache when available for this vessel.
     Falls back to live Wikipedia API fetch otherwise.
     Parameters: latitude, longitude (decimal degrees), radius_m (default 5000m).
     Returns: JSON array [{name, description, url, latitude, longitude, distance, icon}]';

-- Update public.reverse_geocode_py_fn, add OSM identifiers
CREATE OR REPLACE FUNCTION public.reverse_geocode_py_fn(
    geocoder text,
    lon numeric,
    lat numeric,
    OUT geo jsonb
)
RETURNS jsonb
TRANSFORM FOR TYPE jsonb
LANGUAGE plpython3u
AS $function$
    import requests

    if geocoder in SD:
        plan = SD[geocoder]
    else:
        plan = plpy.prepare("SELECT reverse_url AS url FROM geocoders WHERE name = $1", ["text"])
        SD[geocoder] = plan

    rv = plpy.execute(plan, [geocoder], 1)
    if not rv or len(rv) == 0:
        plpy.error(f'Error fetching url from geocoders table for name [{geocoder}]')
        return None

    url = rv[0]['url']

    if not lon or not lat:
        plpy.notice('reverse_geocode_py_fn Parameters [{}] [{}]'.format(lon, lat))
        plpy.error('Error missing parameters')
        return None

    def georeverse(geocoder, lon, lat, zoom="18"):
        headers = {"Accept-Language": "en-US,en;q=0.5", "User-Agent": "PostgSail", "From": "postgsail@localhost"}
        payload = {"lon": lon, "lat": lat, "format": "jsonv2", "zoom": zoom, "accept-language": "en"}
        r = requests.get(url, headers=headers, params=payload, timeout=(60, 60))

        if r.status_code == 200 and "name" in r.json():
            r_dict = r.json()

            # --- NEW: extract OSM identifiers ---
            osm_type  = r_dict.get("osm_type")   # "node" | "way" | "relation"
            osm_id    = r_dict.get("osm_id")      # integer
            #place_id  = r_dict.get("place_id")    # Nominatim internal id
            #category  = r_dict.get("category")    # "leisure", "seamark", etc.
            #osm_class = r_dict.get("type")        # "marina", "harbour", etc.
            # ------------------------------------

            country_code = None
            addr = r_dict.get("address", {})
            if addr.get("country_code"):
                country_code = addr["country_code"]

            def build_result(name):
                result = {
                    "name":         name,
                    "country_code": country_code,
                }
                # Only add OSM fields when present — keeps backward compat
                if osm_type: result["osm_type"]  = osm_type
                if osm_id:   result["osm_id"]    = osm_id
                #if place_id: result["place_id"]  = place_id
                #if category: result["category"]  = category
                #if osm_class:result["osm_class"] = osm_class
                return result

            if r_dict.get("name"):
                return build_result(r_dict["name"])
            elif addr:
                for field in ("neighbourhood", "hamlet", "suburb", "residential",
                              "village", "town", "amenity"):
                    if addr.get(field):
                        return build_result(addr[field])
                if zoom == 15:
                    plpy.notice('georeverse recursive retry exhausted zoom:[{}]'.format(zoom))
                    return build_result("n/a")
                else:
                    plpy.notice('georeverse recursive retry with lower zoom:[{}]'.format(zoom))
                    return georeverse(geocoder, lon, lat, 15)
            else:
                return build_result("n/a")
        else:
            plpy.warning('Failed to received a geo full address %s', r.json())
            return {"name": "unknown", "country_code": "unknown"}

    return georeverse(geocoder, lon, lat)
$function$;

COMMENT ON FUNCTION public.reverse_geocode_py_fn(text, numeric, numeric, OUT jsonb) IS
    'Reverse geocode via Nominatim. Returns name, country_code, osm_type, osm_id, place_id, category, osm_class.
     osm_type + osm_id can be used to build https://www.openstreetmap.org/{osm_type}/{osm_id} links.
     Stores full result in moorages.nominatim for downstream use.';

-- Update api.log_view, includes bbox (WGS84 [W,S,E,N] array)
CREATE OR REPLACE VIEW api.log_view
WITH (security_invoker='true', security_barrier='true') AS
SELECT
    id,
    vessel_id,
    name,
    _from          AS "from",
    _from_time     AS started,
    _to            AS "to",
    _to_time       AS ended,
    distance,
    duration,
    notes,
    api.export_logbook_geojson_trip_fn(id) AS geojson,
    avg_speed,
    max_speed,
    max_wind_speed,
    extra - 'polar' AS extra,
    _from_moorage_id  AS from_moorage_id,
    _to_moorage_id    AS to_moorage_id,
    (extra -> 'polar'::text)             AS polar,
    (user_data -> 'images'::text)        AS images,
    (user_data -> 'tags'::text)          AS tags,
    (user_data -> 'observations'::text)  AS observations,
    CASE
        WHEN jsonb_array_length(user_data -> 'images') > 0 THEN true
        ELSE false
    END AS has_images,
    -- Bounding box from MobilityDB trajectory (WGS84)
    CASE WHEN trip IS NOT NULL THEN
        ST_Envelope(trajectory(trip)::geometry)
    END AS bbox_geom,
    -- As [minLng, minLat, maxLng, maxLat] array — convenient for map clients
    CASE WHEN trip IS NOT NULL THEN
        ARRAY[
            ST_XMin(trajectory(trip)::geometry),  -- west  (min lng)
            ST_YMin(trajectory(trip)::geometry),  -- south (min lat)
            ST_XMax(trajectory(trip)::geometry),  -- east  (max lng)
            ST_YMax(trajectory(trip)::geometry)   -- north (max lat)
        ]
    END AS bbox
FROM api.logbook l
WHERE _to_time IS NOT NULL
  AND trip IS NOT NULL
ORDER BY _from_time DESC;

COMMENT ON VIEW api.log_view IS 'Log web view — includes bbox (WGS84 [W,S,E,N] array) and bbox_geom polygon from MobilityDB trajectory';

-- Update moorage_view with refactored user_data logic, enforce vessel_id in query vs RLS. avoid join on stays_at (static reference data). Add stay first/last seen and log count. Add has_images boolean. Add stay_count and total_duration. Add stay_first_seen_id and stay_last_seen_id for linking to stays_at.
CREATE OR REPLACE VIEW api.moorage_view
WITH(security_invoker=true,security_barrier=true)
AS WITH stay_details AS (
         SELECT s.moorage_id,
            s.arrived,
            s.departed,
            s.duration,
            s.id AS stay_id,
            first_value(s.id) OVER (PARTITION BY s.moorage_id ORDER BY s.arrived) AS first_seen_id,
            first_value(s.id) OVER (PARTITION BY s.moorage_id ORDER BY s.departed DESC) AS last_seen_id
           FROM api.stays s
          WHERE s.vessel_id = current_setting('vessel.id', true)
            AND s.active = false
        ), stay_summary AS (
         SELECT stay_details.moorage_id,
            min(stay_details.arrived) AS first_seen,
            max(stay_details.departed) AS last_seen,
            sum(stay_details.duration) AS total_duration,
            count(*) AS stay_count,
            max(stay_details.first_seen_id) AS first_seen_id,
            max(stay_details.last_seen_id) AS last_seen_id
           FROM stay_details
          GROUP BY stay_details.moorage_id
        ), log_summary AS (
         SELECT logs.moorage_id,
            count(DISTINCT logs.id) AS log_count
           FROM ( SELECT l._from_moorage_id AS moorage_id,
                    l.id
                   FROM api.logbook l
                  WHERE l.vessel_id = current_setting('vessel.id', true)
                  AND l.active = false
                UNION ALL
                 SELECT l._to_moorage_id AS moorage_id,
                    l.id
                   FROM api.logbook l
                  WHERE l.vessel_id = current_setting('vessel.id', true)
                  AND l.active = false) logs
          GROUP BY logs.moorage_id
        )
 SELECT m.id,
    m.name,
    (ARRAY['Unknown','Anchor','Mooring Buoy','Dock'])[m.stay_code] AS default_stay,
    m.stay_code AS default_stay_id,
    m.notes,
    m.home_flag AS home,
    m.geog,
    m.latitude,
    m.longitude,
    COALESCE(l.log_count, 0::bigint) AS logs_count,
    COALESCE(ss.stay_count, 0::bigint) AS stays_count,
    COALESCE(ss.total_duration, 'PT0S'::interval) AS stays_sum_duration,
    ss.first_seen AS stay_first_seen,
    ss.last_seen AS stay_last_seen,
    ss.first_seen_id AS stay_first_seen_id,
    ss.last_seen_id AS stay_last_seen_id,
    CASE
        WHEN jsonb_array_length(m.user_data->'images') > 0 THEN true
        ELSE false
    END AS has_images,
    m.user_data->'images' AS images
   FROM api.moorages m
     --JOIN api.stays_at sa ON m.stay_code = sa.stay_code
     LEFT JOIN stay_summary ss ON m.id = ss.moorage_id
     LEFT JOIN log_summary l ON m.id = l.moorage_id
  WHERE m.vessel_id = current_setting('vessel.id', true)
    AND m.geog IS NOT NULL
  ORDER BY ss.total_duration DESC;
-- Description
COMMENT ON VIEW api.moorage_view IS 'Moorage details web view';

-- Update public.check_jwt, fix anonymous access
CREATE OR REPLACE FUNCTION public.check_jwt()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
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
  _headers json := NULL;
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
  --RAISE WARNING 'jwt email %', current_setting('request.jwt.claims.email', true);
  --RAISE WARNING 'jwt role %', current_setting('request.jwt.claims', true)::json->>'role';
  --RAISE WARNING 'cur_user %', current_user;
  --RAISE WARNING 'user.id [%], user.email [%]', current_setting('user.id', true), current_setting('user.email', true);
  --RAISE WARNING 'vessel.id [%], vessel.name [%]', current_setting('vessel.id', true), current_setting('vessel.name', true);

  --TODO SELECT current_setting('request.jwt.uid', true)::json->>'uid' INTO _user_id;
  --TODO RAISE WARNING 'jwt user_id %', current_setting('request.jwt.uid', true)::json->>'uid';
  --TODO SELECT current_setting('request.jwt.vid', true)::json->>'vid' INTO _vessel_id;
  --TODO RAISE WARNING 'jwt vessel_id %', current_setting('request.jwt.vid', true)::json->>'vid';

  IF _role = 'user_role' OR _role = 'bot_role' OR _role = 'mcp_role' THEN
    -- Check the user exist in the accounts table
    SELECT * INTO account_rec
        FROM auth.accounts
        WHERE auth.accounts.email = _email;
    IF account_rec.email IS NULL THEN
        RAISE WARNING 'public.check_jwt() Invalid user Unknown user or password [%]', _email;
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
    /*-- Check a vessel and user exist
    SELECT auth.vessels.* INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = auth.accounts.email
            AND auth.accounts.email = _email;
    */
    SELECT * INTO vessel_rec
        FROM auth.vessels
        WHERE owner_email = _email;
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
    /*
    -- Check the vessel and user exist
    SELECT auth.vessels.* INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = auth.accounts.email
            AND auth.accounts.email = _email
            AND auth.vessels.vessel_id = _vid;
    */
    -- vessel_role vessel lookup
    SELECT * INTO vessel_rec
        FROM auth.vessels
        WHERE owner_email = _email
            AND vessel_id = _vid;
    IF vessel_rec.owner_email IS NULL THEN
        RAISE WARNING 'public.check_jwt() Invalid vessel Unknown vessel owner_email [%]', _email;
        RAISE EXCEPTION 'Invalid vessel'
            USING HINT = 'Unknown vessel owner_email';
    END IF;
    PERFORM set_config('vessel.id', vessel_rec.vessel_id, true);
    PERFORM set_config('vessel.name', vessel_rec.name, true);
    --RAISE WARNING 'public.check_jwt() user_role vessel.name %', current_setting('vessel.name', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.id %', current_setting('vessel.id', false);
  ELSIF _role = 'api_anonymous' THEN
    SELECT current_setting('request.path', true) into _path;
    -- Function allow for anonymous role
    IF _path ~ '^(\/|\/rpc\/(login|signup|recover|reset|telegram|ispublic_fn|telemetry_fn))$' THEN
        RETURN;
    END IF;
    --RAISE WARNING 'public.check_jwt() api_anonymous path[%] vid:[%]', current_setting('request.path', true), current_setting('vessel.id', false); 
    -- Check if path is the a valid allow anonymous path
    SELECT _path ~ '^/(logs_view|log_view|rpc/timelapse_fn|rpc/timelapse2_fn|monitoring_live|monitoring_view|rpc/stats_fn|rpc/export_logbooks_geojson_point_trips_fn|rpc/export_logbooks_geojson_linestring_trips_fn|rpc/vessel_fn)$' INTO _ppath;
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
            ELSIF _ptype ~ '^public_(logs_list|stats|monitoring|timelapse)$' AND _pid = 0 THEN
                /*
                    SELECT v.vessel_id, v.name into anonymous_rec
                        FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs
                        WHERE a.email = v.owner_email
                            AND a.preferences->>'public_vessel'::text ~* boat
                            AND prefs.key = _ptype::TEXT
                            AND prefs.value::BOOLEAN = true;
                */
                -- Replace the ELSE branch anonymous lookup with:
                SELECT v.vessel_id, v.name INTO anonymous_rec
                    FROM auth.vessels v
                    JOIN auth.accounts a ON a.email = v.owner_email
                    WHERE a.preferences->>'public_vessel' = _pvessel   -- exact match, index-able
                    AND a.preferences->>_ptype::TEXT = 'true'
                    LIMIT 1;
                RAISE WARNING '-> ispublic_fn output boat:[%], type:[%], result:[%]', _pvessel, _ptype, anonymous_rec;
                IF anonymous_rec.vessel_id IS NOT NULL THEN
                    PERFORM set_config('vessel.id', anonymous_rec.vessel_id, true);
                    PERFORM set_config('vessel.name', anonymous_rec.name, true);
                    RETURN;
                END IF;
            END IF;
            --RAISE sqlstate 'PT404' using message = 'unknown resource';
        END IF; -- end anonymous path
    ELSE -- If path is not allow for anonymous role, block access
        RAISE sqlstate 'PT404' using message = 'unknown resource';
    END IF;
  ELSIF _role <> 'api_anonymous' THEN
    RAISE EXCEPTION 'Invalid role'
      USING HINT = 'Stop being so evil and maybe you can log in';
  END IF;
END
$function$
;

COMMENT ON FUNCTION public.check_jwt() IS 'PostgREST API db-pre-request check, set_config according to role (api_anonymous,vessel_role,user_role)';

-- Drop unused Views
DROP VIEW IF EXISTS public.stay_in_progress;
DROP VIEW IF EXISTS public.trip_in_progress;

-- Drop unused Indexes
DROP INDEX IF EXISTS api.metadata_alerting_enabled_idx;
DROP INDEX IF EXISTS api.metadata_windy_station_idx;
DROP INDEX IF EXISTS api.metrics_status_time_idx;
DROP INDEX IF EXISTS api.logbook_vessel_timeline_names_idx;
DROP INDEX IF EXISTS api.stays_moorage_vessel_idx;
DROP INDEX IF EXISTS auth.accounts_email_idx;
DROP INDEX IF EXISTS public.process_queue_new_priority_idx;
DROP INDEX IF EXISTS public.process_queue_pending_idx;

-- Remove Deprecated functions
DROP FUNCTION IF EXISTS public.process_moorage_queue_fn;
DROP FUNCTION IF EXISTS public.process_account_otp_validation_queue_fn;

-- Refresh permissions user_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO user_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
-- Refresh permissions bot_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO bot_role;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO bot_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO bot_role;
-- Refresh permissions grafana
GRANT SELECT ON ALL TABLES IN SCHEMA api TO grafana;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO grafana;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO grafana;
-- Refresh permissions api_anonymous
GRANT SELECT ON ALL TABLES IN SCHEMA api TO api_anonymous;

GRANT EXECUTE ON FUNCTION api.stats_logs_fn TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.stats_stays_fn TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.stats_fn TO api_anonymous;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO api_anonymous;

REVOKE EXECUTE ON FUNCTION api.settings_fn() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api.settings_fn() TO user_role;

-- Restrict app_settings access to sql users
REVOKE SELECT ON public.app_settings FROM grafana;
REVOKE SELECT ON public.app_settings FROM scheduler;
REVOKE SELECT ON public.app_settings FROM bot_role;

CREATE POLICY api_bot_role ON auth.accounts TO bot_role
    USING ((email)::text = current_setting('user.email'::text, true))
    WITH CHECK (false);
CREATE POLICY api_bot_role ON auth.vessels TO bot_role
    USING ((owner_email)::text = current_setting('user.email'::text, true))
    WITH CHECK (false);

-- +goose StatementEnd
