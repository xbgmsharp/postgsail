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
    RAISE NOTICE '-> update_metadata_userdata_fn userdata:[%]', userdata;
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

-- Index optimizations for cron_alerts_fn queries on metadata.user_data
-- Partial index on api.metadata.user_data after preferences migration ships
-- After the preferences migration, 
-- cron_alerts_fn will filter WHERE (m.user_data->'alerting'->>'enabled')::boolean IS TRUE across all metadata rows. At 154 rows this is negligible.
-- At SaaS scale (1000+ vessels) a partial index eliminates the full metadata scan on every cron tick.
-- Create AFTER preferences migration ships (user_data.alerting populated):
CREATE INDEX metadata_alerting_enabled_idx
    ON api.metadata ((user_data->'alerting'->>'enabled'))
    WHERE (user_data->'alerting'->>'enabled') = 'true';

-- Similarly for Windy cron after public_windy moves to user_data:
CREATE INDEX metadata_windy_station_idx
    ON api.metadata ((user_data->'windy'->>'station_id'))
    WHERE (user_data->'windy'->>'station_id') IS NOT NULL;

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
                              || ROUND(metric_rec.voltage, 2)
                              || ', "date":"' || metric_rec.time_bucket || '"}}';
                    _alarms := public.jsonb_recursive_merge(_alarms, alarms::jsonb);
                    PERFORM api.update_metadata_userdata_fn(jsonb_build_object('alarms', _alarms)::TEXT);
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    user_settings := user_settings || ('{"alert": "low_battery_voltage_threshold value:'
                        || ROUND(metric_rec.voltage, 2)
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

-- Add api.update_vessel_settings_fn, Mirrors the key/value pattern of api.update_user_preferences_fn but
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
--DROP FUNCTION IF EXISTS api.vessel_fn;
--DROP FUNCTION IF EXISTS api.vessel_extended_fn;
--DROP FUNCTION IF EXISTS api.vessel_details_fn;

-- Add api.vessel_view, replace multiple vessel function and align design.
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

-- Update api.stats_fn, include name and expose moorage name, plus add top countries for moorages.
CREATE OR REPLACE FUNCTION api.stats_fn(
    start_date  TIMESTAMPTZ DEFAULT NULL,
    end_date    TIMESTAMPTZ DEFAULT NULL,
    OUT stats   JSONB
) RETURNS JSONB
LANGUAGE plpgsql AS $$
DECLARE
    _vessel_id  TEXT        := current_setting('vessel.id', true);
    _start      TIMESTAMPTZ := COALESCE(start_date, '1970-01-01');
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
        'logs_top_speed',         (SELECT jsonb_agg(t ORDER BY t.max_speed    DESC) FROM logs_top_speed         t),
        'logs_top_avg_speed',     (SELECT jsonb_agg(t ORDER BY t.avg_speed    DESC) FROM logs_top_avg_speed     t),
        'logs_top_wind_speed',    (SELECT jsonb_agg(t ORDER BY t.max_wind_speed DESC) FROM logs_top_wind_speed  t),
        'logs_top_distance',      (SELECT jsonb_agg(t ORDER BY t.distance     DESC) FROM logs_top_distance      t),
        'logs_top_duration',      (SELECT jsonb_agg(t ORDER BY t.duration     DESC) FROM logs_top_duration      t),
        'moorages_top_arrivals',  (SELECT jsonb_agg(t ORDER BY t.ref_count    DESC) FROM moorages_top_arrivals  t),
        'moorages_top_duration',  (SELECT jsonb_agg(t ORDER BY t.dur          DESC) FROM moorages_top_duration  t),
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
-- Refresh permissions bot_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO bot_role;

REVOKE EXECUTE ON FUNCTION api.settings_fn() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api.settings_fn() TO user_role;

-- Restrict app_settings access to sql users
REVOKE SELECT ON public.app_settings FROM grafana;
REVOKE SELECT ON public.app_settings FROM scheduler;

CREATE POLICY api_bot_role ON auth.accounts TO bot_role
    USING ((email)::text = current_setting('user.email'::text, true))
    WITH CHECK (false);
CREATE POLICY api_bot_role ON auth.vessels TO bot_role
    USING ((owner_email)::text = current_setting('user.email'::text, true))
    WITH CHECK (false);

-- +goose StatementEnd
