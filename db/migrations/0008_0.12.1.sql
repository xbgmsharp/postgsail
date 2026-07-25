-- +goose Up
-- +goose StatementBegin

set timezone to 'UTC';

-- Drop unused fuctions
DROP FUNCTION IF EXISTS public.delete_vessel_fn(text);

-- Drop unused indexes
DROP INDEX IF EXISTS api.logbook_vessel_timeline_idx;
DROP INDEX IF EXISTS api.logbook_vessel_active_idx;
--DROP INDEX IF EXISTS api.stays_stay_code_idx;
DROP INDEX IF EXISTS api.stays_vessel_active_idx;
DROP INDEX IF EXISTS api.metrics_vessel_id_time_uq;
DROP INDEX IF EXISTS public.metrics_rejected_vessel_time_idx;
DROP INDEX IF EXISTS public.metrics_anomalies_vessel_idx;
DROP INDEX IF EXISTS public.metrics_anomalies_type_idx;

ALTER TABLE api.metadata
    ADD COLUMN IF NOT EXISTS first_metric timestamptz DEFAULT NULL;

COMMENT ON COLUMN api.metadata.first_metric IS
'Timestamp of the first metric row received from this vessel.
 Insert by autodiscovery process.';

COMMENT ON COLUMN api.metadata.time IS
'Timestamp of the most recent metadata received from this vessel.
 Use as an equivalent to last_metric for stats.';

-- Backfill first_metric for all existing vessels that have metrics.
UPDATE api.metadata md
    SET first_metric = (
        SELECT MIN(time)
        FROM api.metrics m
        WHERE m.vessel_id = md.vessel_id
    )
    WHERE first_metric IS NULL
    AND EXISTS (
        SELECT 1 FROM api.metrics m
        WHERE m.vessel_id = md.vessel_id
        LIMIT 1
    );

--DROP FUNCTION public.cron_process_autodiscovery_fn();
-- Update public.cron_process_autodiscovery_fn, now sets first_metric in api.metadata on successful provisioning of a vessel with valid navigation keys and metrics.
CREATE OR REPLACE FUNCTION public.cron_process_autodiscovery_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    process_rec record;
    data_rec record;
    latest_metrics record;
    app_settings jsonb;
    user_settings jsonb;
    config jsonb;
    config_default jsonb := '{
        "depthKey": "environment.depth.belowTransducer",
        "voltageKey": "electrical.batteries.House.voltage",
        "windSpeedKey": "environment.wind.speedTrue",
        "solarPowerKey": "electrical.solar.Main.panelPower",
        "solarVoltageKey": "electrical.solar.Main.panelVoltage",
        "stateOfChargeKey": "electrical.batteries.House.capacity.stateOfCharge",
        "windDirectionKey": "environment.wind.directionTrue",
        "insideHumidityKey": "environment.outside.humidity",
        "insidePressureKey": "environment.inside.mainCabin.pressure",
        "outsideHumidityKey": "environment.outside.humidity",
        "outsidePressureKey": "environment.outside.pressure",
        "waterTemperatureKey": "environment.water.temperature",
        "insideTemperatureKey": "environment.inside.temperature",
        "outsideTemperatureKey": "environment.outside.temperature"
      }'::JSONB;
    _has_navigation BOOLEAN := FALSE;
BEGIN
    RAISE NOTICE 'cron_process_autodiscovery_fn';
    FOR process_rec in
        SELECT * from process_queue
            where channel = 'autodiscovery' and processed is null
            order by stored asc
    LOOP
        RAISE NOTICE '-> cron_process_autodiscovery_fn [%]', process_rec.payload;
        -- Gather url from app settings
        app_settings := get_app_settings_fn();
        -- Get vessel details base on vessel id
        SELECT
            v.owner_email, coalesce(m.name, v.name) as name, m.vessel_id, m.configuration,
            m.available_keys into data_rec
            FROM auth.vessels v
            LEFT JOIN api.metadata m ON v.vessel_id = m.vessel_id
            WHERE m.vessel_id = process_rec.payload::TEXT;
        IF data_rec.vessel_id IS NULL OR data_rec.name IS NULL THEN
            RAISE WARNING '-> DEBUG cron_process_autodiscovery_fn error unknow vessel_id [%] [%]', process_rec.payload, data_rec;
            CONTINUE; -- Continue to the next vessel
        END IF;
        -- Set vessel.id for the functions that need it
        PERFORM set_config('vessel.id', data_rec.vessel_id::TEXT, false);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(data_rec.vessel_id::TEXT);
        -- Check available_keys contains at least one actionable navigation key
        -- before looking for metrics. Vessels with only design.* / sensors.gps.*
        -- keys have no GPS/AIS source connected and will never produce metrics.
        -- Send a notification so the owner knows what to fix for 1day until marking as processed and removing from the queue to avoid spamming notifications in case the vessel shows up later with valid keys when the GPS/AIS source is properly connected.
        SELECT EXISTS (
            SELECT 1
            FROM jsonb_array_elements(
                CASE
                    WHEN data_rec.available_keys IS NULL THEN '[]'::jsonb
                    ELSE data_rec.available_keys
                END
            ) AS k
            WHERE k->>'key' ~ '^(navigation|environment|propulsion)\.'
        ) INTO _has_navigation;
        IF _has_navigation IS FALSE THEN
            RAISE WARNING '-> cron_process_autodiscovery_fn, vessel_id: [%], no actionable navigation keys in available_keys: [%], sending notification',
                data_rec.vessel_id, data_rec.available_keys;
            -- Notify the owner so they know to check their GPS/AIS source in SignalK
            --user_settings := get_user_settings_from_vesselid_fn(data_rec.vessel_id::TEXT);
            PERFORM send_notification_fn('autodiscovery_no_navigation'::TEXT, user_settings::JSONB);
            -- Mark as processed so this entry does not loop forever.
            -- When the vessel re-registers with valid navigation keys the
            -- metadata insert trigger will queue a new autodiscovery entry.
            UPDATE process_queue
                SET processed = NOW()
                WHERE id = process_rec.id
                AND stored > current_timestamp - interval '3 d'; -- Avoid marking old entries as processed in case the vessel shows up later with valid keys
            RAISE NOTICE '-> cron_process_autodiscovery_fn, No navigation keys  found for vessel_id:[%] process_queue [%]', data_rec.vessel_id, process_rec.id;
            /*
            DELETE FROM api.metadata
                WHERE vessel_id = data_rec.vessel_id::TEXT;
            RAISE NOTICE '-> cron_process_autodiscovery_fn, deleted metadata for vessel_id [%] (no navigation keys)', data_rec.vessel_id;
            */
            CONTINUE; -- No navigation keys, keep waiting for 3 days before marking as processed and notifying about missing navigation keys in case the vessel shows up later with valid keys    
        END IF;
        -- Check for metrics
        SELECT metrics INTO latest_metrics
            FROM api.metrics
            WHERE vessel_id = current_setting('vessel.id', false)
            ORDER BY time DESC
            LIMIT 1;
        IF NOT FOUND THEN
            RAISE WARNING '-> cron_process_autodiscovery_fn, No metrics found for vessel_id:[%] process_queue [%]', current_setting('vessel.id', false), process_rec.id;
            PERFORM send_notification_fn('autodiscovery_no_navigation'::TEXT, user_settings::JSONB);
            UPDATE process_queue
                SET processed = NOW()
                WHERE id = process_rec.id
                AND stored > current_timestamp - interval '3 d'; -- Avoid marking old entries as processed in case the vessel shows up later with valid keys
            CONTINUE; -- No metrics yet, keep waiting for 3 days before marking as processed and notifying about missing navigation keys in case the vessel shows up later with valid keys
        END IF;
        -- We have both navigation keys and metrics: proceed with provisioning
        IF data_rec.configuration IS NULL THEN
            data_rec.configuration := '{}'::JSONB;
        END IF;
        SELECT public.autodiscovery_config_fn(config_default || data_rec.configuration) INTO config;
        IF config IS NULL OR config = '{}'::JSONB THEN
            RAISE WARNING '-> DEBUG cron_process_autodiscovery_fn, vessel.id [%], autodiscovery_config_fn error [%]', current_setting('vessel.id', false), config;
            UPDATE process_queue
                SET processed = NOW()
                WHERE id = process_rec.id;
            RAISE NOTICE '-> cron_process_autodiscovery_fn updated process_queue table [%]', process_rec.id;
            CONTINUE;
        END IF;
        RAISE NOTICE '-> cron_process_autodiscovery_fn, vessel.id [%], update api.metadata configuration', current_setting('vessel.id', false);
        UPDATE api.metadata
            SET configuration = config,
                first_metric = (
                        SELECT MIN(time) FROM api.metrics
                        WHERE vessel_id = current_setting('vessel.id', false)
                    )
            WHERE vessel_id = current_setting('vessel.id', false);
        --user_settings := get_user_settings_from_vesselid_fn(data_rec.vessel_id::TEXT);
        PERFORM send_notification_fn('autodiscovery'::TEXT, user_settings::JSONB);
        UPDATE process_queue
            SET processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_autodiscovery_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$function$
;

COMMENT ON FUNCTION public.cron_process_autodiscovery_fn() IS 'init by pg_cron to check for new vessel pending autodiscovery config provisioning.
Vessels with no actionable navigation/environment/propulsion keys in available_keys
are notified via autodiscovery_no_navigation and remain in the queue for 3 days.
notification so the owner knows to check their GPS/AIS source in SignalK.
Vessels with valid keys but no metrics yet remain in the queue for 3 days.';

CREATE OR REPLACE FUNCTION api.stats_logs_fn(
    start_date timestamp with time zone DEFAULT NULL::timestamp with time zone,
    end_date   timestamp with time zone DEFAULT NULL::timestamp with time zone,
    OUT stats  jsonb
)
RETURNS jsonb
LANGUAGE sql
AS $function$
WITH
_vessel AS (
    SELECT current_setting('vessel.id', true) AS vessel_id
),

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
    WHERE l.vessel_id  = _vessel.vessel_id
      AND l.active     = false
      AND l.trip       IS NOT NULL
      AND l._from_time IS NOT NULL
      AND l._to_time   IS NOT NULL
      AND l._from_time >= COALESCE(start_date, '1980-01-01'::timestamptz)
      AND l._to_time   <= COALESCE(end_date,   NOW()::timestamptz)
),

logs_agg AS (
    SELECT
        COUNT(*)            AS count,
        MIN(_from_time)     AS first_date,
        MAX(_to_time)       AS last_date,
        MAX(max_speed)      AS max_speed,
        MAX(max_wind_speed) AS max_wind_speed,
        MAX(distance)       AS max_distance,
        SUM(distance)       AS sum_distance,
        MAX(duration)       AS max_duration,
        SUM(duration)       AS sum_duration
    FROM logs_base
),

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

-- PK lookup — returns name, metrics_first, metrics_last
meta AS (
    SELECT m.name, m.first_metric, m.time AS metrics_last
    FROM api.metadata m, _vessel
    WHERE m.vessel_id = _vessel.vessel_id
),

/*
-- -------------------------------------------------------------------------
-- SignalK plugin connection bounds — respects the same date window as logs.
-- Returns first/last plugin contact within [start_date, end_date].
-- NULL when no metrics exist in the window (consistent with first_date/last_date).
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
*/

-- metrics_first/metrics_last comes from metadata to avoid hypertable scans
metrics_window AS (
    SELECT
        CASE WHEN (start_date IS NULL OR first_metric >= start_date)
              AND (end_date   IS NULL OR metrics_last  <= end_date)
             THEN first_metric END AS metrics_first,
        CASE WHEN (start_date IS NULL OR first_metric >= start_date)
              AND (end_date   IS NULL OR metrics_last  <= end_date)
             THEN metrics_last END AS metrics_last
    FROM meta
),

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

SELECT COALESCE(
    jsonb_build_object(
        'name',                  m.name,

        'first_date',            a.first_date,
        'last_date',             a.last_date,

        -- first_metric: durable PK lookup, never scans hypertable
        'metrics_first',         mw.metrics_first,
        -- metrics_last: single MAX scan, date-window-aware
        -- metrics_last: durable PK lookup, never scans hypertable
        'metrics_last',          mw.metrics_last,

        'count',                 a.count,
        'sum_distance',          a.sum_distance,
        'sum_duration',          a.sum_duration,

        'max_speed',             a.max_speed,
        'max_speed_id',          i.max_speed_id,
        'max_wind_speed',        a.max_wind_speed,
        'max_wind_speed_id',     i.max_wind_speed_id,
        'max_distance',          a.max_distance,
        'max_distance_id',       i.max_distance_id,
        'max_duration',          a.max_duration,
        'max_duration_id',       i.max_duration_id,

        'longest_nonstop_sail',  CASE
                                     WHEN a.max_distance IS NULL THEN NULL
                                     ELSE CONCAT(
                                         a.max_distance, ' NM, ',
                                         a.max_duration, ' hours'
                                     )
                                 END,

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
CROSS JOIN metrics_window mw
$function$;

COMMENT ON FUNCTION api.stats_logs_fn(in timestamptz, in timestamptz, out jsonb) IS
'Logbook statistics for the current vessel within an optional date range.
 Pass NULL for both parameters to get all-time statistics (default).

 Output fields:
   name                — vessel name from metadata
   first_date          — _from_time of earliest completed log in range
   last_date           — _to_time of latest completed log in range
   metrics_first       — earliest SignalK plugin contact; read from
                         api.metadata.first_metric (durable, PK lookup,
                         survives retention purges of api.metrics)
   metrics_last        — latest plugin contact within the requested window
                         (MAX scan on api.metrics)
   count               — number of completed logs in range
   sum_distance        — total distance sailed (NM)
   sum_duration        — total time underway (interval)
   max_speed           — highest recorded max_speed, with max_speed_id
   max_wind_speed      — highest recorded wind speed, with max_wind_speed_id
   max_distance        — longest single leg, with max_distance_id
   max_duration        — longest single leg by time, with max_duration_id
   longest_nonstop_sail — formatted: "X NM, Y hours" (NULL when no logs)
   best_24h_distance_nm — best 24h rolling window (NULL when date-filtered)
   best_24h_window_start — start of that window (NULL when date-filtered)
   best_24h_log_id       — anchor log id (NULL when date-filtered)
   best_24h_route        — "from → to" summary (NULL when date-filtered)

 Design notes:
   - VOLATILE: reads current_setting() session state.
   - metrics_first sourced from api.metadata.first_metric (written once by
     cron_process_autodiscovery_fn). Eliminates MIN() full hypertable scan.
   - metrics_last still scans api.metrics but only in one direction (MAX).';

-- DROP FUNCTION public.send_telegram_py_fn(text, jsonb, jsonb);
-- Update public.send_telegram_py_fn, fix app settings
CREATE OR REPLACE FUNCTION public.send_telegram_py_fn(message_type text, _user jsonb, app jsonb)
 RETURNS void
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
AS $function$
    """
    https://core.telegram.org/bots/api#sendmessage
    Send a message to a telegram user or group specified on chatId
    chat_id must be a number!
    """
    import requests
    import json
    from urllib.parse import urljoin

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

    def clean_url(base, path):
        base = base.rstrip('/') + '/'
        path = '/' + '/'.join(filter(None, path.split('/')))
        return urljoin(base, path)

    #plpy.notice('Video Debug [{}] [{}] [{}]'.format(clean_url(app['app.videos_url'], str(_user['video_link'])), str(app['app.videos_url']), str(_user['video_link'])))

    # Replace fields using input jsonb obj
    if 'logbook_name' in _user and _user['logbook_name']:
        telegram_message = telegram_message.replace('__LOGBOOK_NAME__', _user['logbook_name'])
    if 'logbook_link' in _user and _user['logbook_link']:
        telegram_message = telegram_message.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'video_link' in _user and _user['video_link'] and 'app.videos_url' in app and app['app.videos_url']:
        telegram_message = telegram_message.replace('__VIDEO_LINK__', clean_url(app['app.videos_url'], str(_user['video_link'])))
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
            'Proxy-Authorization': 'Basic base64',
            'User-Agent': 'PostgSail',
            'From': 'postgsail@localhost'}
    if 'ua' in _user and _user['ua']:
        headers["User-Agent"] = _user['ua']
        headers["From"] = _user['app.email_from']

    data_dict = {'chat_id': telegram_chat_id,
                'text': telegram_message,
                'parse_mode': 'HTML',
                'disable_notification': False}
    data = json.dumps(data_dict)
    url = f'https://api.telegram.org/bot{telegram_token}/sendMessage'
    r = requests.post(url, data=data, headers=headers, timeout=(60, 60))
    if message_type == 'logbook' and 'logbook_img' in _user and _user['logbook_img'] and 'app.gis_url' in app and app['app.gis_url']:
        # Send gis image logbook
        # https://core.telegram.org/bots/api#sendphoto
        data_dict['photo'] = '{}'.format(clean_url(app['app.gis_url'], str(_user['logbook_img'])))
        del data_dict['text']
        data = json.dumps(data_dict)
        url = f'https://api.telegram.org/bot{telegram_token}/sendPhoto'
        r = requests.post(url, data=data, headers=headers, timeout=(60, 60))
        if r.status_code == 200:
            plpy.notice('Sent telegram photo successfully to [{}]'.format(telegram_chat_id))
        else:
            plpy.warning('Failed to send telegram photo [status={}] [body={}] [url={}]'.format(r.status_code, r.text, data_dict['photo']))
            # warning not error — message already sent, photo is non-critical

    #print(r.text)
    # Return something boolean?
    #plpy.notice('Sent telegram successfully to [{}] [{}]'.format(r.text, r.status_code))
    if r.status_code == 200:
        plpy.notice('Sent telegram successfully to [{}] [{}] [{}]'.format(telegram_chat_id, telegram_title, r.text))
    else:
        plpy.error('Failed to send telegram')
    return None
$function$
;

COMMENT ON FUNCTION public.send_telegram_py_fn(text, jsonb, jsonb) IS 'Send a message to a telegram user or group specified on chatId using plpython3u';

-- Update api.monitoring_view, Add a time a bound as a concrete TIMESTAMPTZ constant
CREATE OR REPLACE VIEW api.monitoring_view
WITH (security_invoker = true, security_barrier = true)
AS
WITH
    _vessel AS (
        SELECT current_setting('vessel.id', true) AS vessel_id
    ),
    _bounds AS (
        SELECT NOW() - INTERVAL '7 days' AS time_lower_bound
    )
SELECT
    m."time",
    ((now() AT TIME ZONE 'UTC')::timestamptz - m."time") > 'PT1H10M'::interval AS offline,
    m.metrics -> 'environment.water.temperature'            AS watertemperature,
    m.metrics -> 'environment.inside.temperature'           AS insidetemperature,
    m.metrics -> 'environment.outside.temperature'          AS outsidetemperature,
    m.metrics -> 'environment.wind.speedTrue'               AS windspeedoverground,
    m.metrics -> 'environment.wind.directionTrue'           AS winddirectiontrue,
    m.metrics -> 'environment.inside.relativeHumidity'      AS insidehumidity,
    m.metrics -> 'environment.outside.relativeHumidity'     AS outsidehumidity,
    m.metrics -> 'environment.outside.pressure'             AS outsidepressure,
    m.metrics -> 'environment.inside.pressure'              AS insidepressure,
    m.metrics -> 'electrical.batteries.House.capacity.stateOfCharge' AS batterycharge,
    m.metrics -> 'electrical.batteries.House.voltage'       AS batteryvoltage,
    m.metrics -> 'environment.depth.belowTransducer'        AS depth,
    jsonb_build_object(
        'type', 'Feature',
        'geometry', st_asgeojson(st_makepoint(m.longitude, m.latitude), 9, 8)::jsonb,
        'properties', jsonb_build_object(
            'name',             current_setting('vessel.name', false),
            'latitude',         m.latitude,
            'longitude',        m.longitude,
            'time',             m."time",
            'speedoverground',  m.speedoverground,
            'windspeedapparent',m.windspeedapparent,
            'truewindspeed',    m.metrics -> 'environment.wind.speedTrue',
            'truewinddirection',m.metrics -> 'environment.wind.directionTrue',
            'status',           m.status
        )
    ) AS geojson,
    current_setting('vessel.name', false) AS name,
    m.status,
    CASE
        WHEN (m.status <> 'moored' AND m.status <> 'anchored') THEN (SELECT logbook_active_geojson_fn())
        WHEN (m.status = 'moored' OR m.status = 'anchored') THEN (SELECT stay_active_geojson_fn(m."time"))
        ELSE NULL::jsonb
    END AS live
FROM api.metrics m
CROSS JOIN _vessel
CROSS JOIN _bounds
WHERE m.vessel_id = _vessel.vessel_id
  AND m."time"  > _bounds.time_lower_bound
ORDER BY m."time" DESC
LIMIT 1;

COMMENT ON VIEW api.monitoring_view IS 'Monitoring static web view';

-- Update api.monitoring_live, Add a time a bound as a concrete TIMESTAMPTZ constant
CREATE OR REPLACE VIEW api.monitoring_live
WITH(security_invoker=true,security_barrier=true)
AS
WITH
    _vessel AS (
        SELECT current_setting('vessel.id', true) AS vessel_id
    ),
    _bounds AS (
        SELECT NOW() - INTERVAL '7 days' AS time_lower_bound
    ),
    pressure AS (
         SELECT json_agg(json_build_object('time', sub.time_bucket, 'outsidePressure', sub.outsidepressure) ORDER BY sub.time_bucket) AS outsidepressurehistory
           FROM ( SELECT time_bucket('PT10M'::interval, mt_1."time") AS time_bucket,
                    avg(COALESCE((mt_1.metrics -> 'pressure'::text) ->> 'outside'::text, mt_1.metrics ->> (md_1.configuration ->> 'outsidePressureKey'::text), mt_1.metrics ->> 'environment.outside.pressure'::text)::double precision) AS outsidepressure
                   FROM api.metrics mt_1
                     JOIN api.metadata md_1 ON md_1.vessel_id = mt_1.vessel_id
                  WHERE mt_1.vessel_id = current_setting('vessel.id'::text, false) AND mt_1."time" > ((now() AT TIME ZONE 'UTC'::text) - 'PT6H'::interval)
                  GROUP BY (time_bucket('PT10M'::interval, mt_1."time"))
                 HAVING avg(COALESCE((mt_1.metrics -> 'pressure'::text) ->> 'outside'::text, mt_1.metrics ->> (md_1.configuration ->> 'outsidePressureKey'::text), mt_1.metrics ->> 'environment.outside.pressure'::text)::double precision) IS NOT NULL) sub
        )
    SELECT mt."time",
        ((now() AT TIME ZONE 'UTC'::text)::timestamp with time zone - mt."time") > 'PT1H10M'::interval AS offline,
        mt.metrics AS data,
        jsonb_build_object('type', 'Feature', 'geometry', st_asgeojson(st_makepoint(mt.longitude, mt.latitude))::jsonb, 'properties', jsonb_build_object('name', current_setting('vessel.name'::text, false), 'latitude', mt.latitude, 'longitude', mt.longitude, 'time', mt."time", 'speedoverground', mt.speedoverground, 'windspeedapparent', mt.windspeedapparent, 'truewindspeed', COALESCE((mt.metrics -> 'wind'::text) ->> 'speed'::text, mt.metrics ->> (md.configuration ->> 'windSpeedKey'::text), mt.metrics ->> 'environment.wind.speedTrue'::text)::double precision, 'truewinddirection', COALESCE((mt.metrics -> 'wind'::text) ->> 'direction'::text, mt.metrics ->> (md.configuration ->> 'windDirectionKey'::text), mt.metrics ->> 'environment.wind.directionTrue'::text)::double precision, 'status', COALESCE(mt.status, NULL::text))) AS geojson,
        current_setting('vessel.name'::text, false) AS name,
        mt.status,
        COALESCE((mt.metrics -> 'water'::text) ->> 'temperature'::text, mt.metrics ->> (md.configuration ->> 'waterTemperatureKey'::text), mt.metrics ->> 'environment.water.temperature'::text)::double precision AS watertemperature,
        COALESCE((mt.metrics -> 'temperature'::text) ->> 'inside'::text, mt.metrics ->> (md.configuration ->> 'insideTemperatureKey'::text), mt.metrics ->> 'environment.inside.temperature'::text)::double precision AS insidetemperature,
        COALESCE((mt.metrics -> 'temperature'::text) ->> 'outside'::text, mt.metrics ->> (md.configuration ->> 'outsideTemperatureKey'::text), mt.metrics ->> 'environment.outside.temperature'::text)::double precision AS outsidetemperature,
        COALESCE((mt.metrics -> 'wind'::text) ->> 'speed'::text, mt.metrics ->> (md.configuration ->> 'windSpeedKey'::text), mt.metrics ->> 'environment.wind.speedTrue'::text)::double precision AS windspeedoverground,
        COALESCE((mt.metrics -> 'wind'::text) ->> 'direction'::text, mt.metrics ->> (md.configuration ->> 'windDirectionKey'::text), mt.metrics ->> 'environment.wind.directionTrue'::text)::double precision AS winddirectiontrue,
        COALESCE((mt.metrics -> 'humidity'::text) ->> 'inside'::text, mt.metrics ->> (md.configuration ->> 'insideHumidityKey'::text), mt.metrics ->> 'environment.inside.relativeHumidity'::text, mt.metrics ->> 'environment.inside.humidity'::text)::double precision AS insidehumidity,
        COALESCE((mt.metrics -> 'humidity'::text) ->> 'outside'::text, mt.metrics ->> (md.configuration ->> 'outsideHumidityKey'::text), mt.metrics ->> 'environment.outside.relativeHumidity'::text, mt.metrics ->> 'environment.outside.humidity'::text)::double precision AS outsidehumidity,
        COALESCE((mt.metrics -> 'pressure'::text) ->> 'outside'::text, mt.metrics ->> (md.configuration ->> 'outsidePressureKey'::text), mt.metrics ->> 'environment.outside.pressure'::text)::double precision AS outsidepressure,
        COALESCE((mt.metrics -> 'pressure'::text) ->> 'inside'::text, mt.metrics ->> (md.configuration ->> 'insidePressureKey'::text), mt.metrics ->> 'environment.inside.pressure'::text)::double precision AS insidepressure,
        COALESCE((mt.metrics -> 'battery'::text) ->> 'charge'::text, mt.metrics ->> (md.configuration ->> 'stateOfChargeKey'::text), mt.metrics ->> 'electrical.batteries.House.capacity.stateOfCharge'::text)::double precision AS batterycharge,
        COALESCE((mt.metrics -> 'battery'::text) ->> 'voltage'::text, mt.metrics ->> (md.configuration ->> 'voltageKey'::text), mt.metrics ->> 'electrical.batteries.House.voltage'::text)::double precision AS batteryvoltage,
        COALESCE((mt.metrics -> 'water'::text) ->> 'depth'::text, mt.metrics ->> (md.configuration ->> 'depthKey'::text), mt.metrics ->> 'environment.depth.belowTransducer'::text)::double precision AS depth,
        COALESCE((mt.metrics -> 'solar'::text) ->> 'power'::text, mt.metrics ->> (md.configuration ->> 'solarPowerKey'::text), mt.metrics ->> 'electrical.solar.Main.panelPower'::text)::double precision AS solarpower,
        COALESCE((mt.metrics -> 'solar'::text) ->> 'voltage'::text, mt.metrics ->> (md.configuration ->> 'solarVoltageKey'::text), mt.metrics ->> 'electrical.solar.Main.panelVoltage'::text)::double precision AS solarvoltage,
        COALESCE((mt.metrics -> 'tank'::text) ->> 'level'::text, mt.metrics ->> (md.configuration ->> 'tankLevelKey'::text), mt.metrics ->> 'tanks.fuel.0.currentLevel'::text)::double precision AS tanklevel,
        CASE
            WHEN mt.status <> 'moored'::text AND mt.status <> 'anchored'::text THEN ( SELECT logbook_active_geojson_fn() AS logbook_active_geojson_fn)
            WHEN mt.status = 'moored'::text OR mt.status = 'anchored'::text THEN ( SELECT stay_active_geojson_fn(mt."time") AS stay_active_geojson_fn)
            ELSE NULL::jsonb
        END AS live,
        pressure.outsidepressurehistory
    FROM api.metrics mt
    JOIN api.metadata md ON md.vessel_id = mt.vessel_id
    CROSS JOIN pressure
    CROSS JOIN _vessel
    CROSS JOIN _bounds
    WHERE mt.vessel_id = _vessel.vessel_id
    AND mt."time"  > _bounds.time_lower_bound
    ORDER BY mt."time" DESC
    LIMIT 1;

COMMENT ON VIEW api.monitoring_live IS 'Dynamic Monitoring web view';

-- Update api.monitoring_history_fn, Add explicit vessel_id filter and add a time a bound as a concrete TIMESTAMPTZ constant
CREATE OR REPLACE FUNCTION api.monitoring_history_fn(time_interval text DEFAULT '24'::text, OUT history_metrics jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
        bucket_interval interval := '5 minutes';
        _start TIMESTAMPTZ;
    BEGIN
        RAISE NOTICE '-> monitoring_history_fn';

        SELECT CASE time_interval
            WHEN '24' THEN '5 minutes'
            WHEN '48' THEN '2 hours'
            WHEN '72' THEN '4 hours'
            WHEN '168' THEN '7 hours'
            ELSE '5 minutes'
            END bucket INTO bucket_interval;

        -- Materialise the lower bound as a concrete TIMESTAMPTZ so TimescaleDB
        -- can perform startup chunk exclusion at plan time.
        -- time_interval is '24', '48', '72', or '168' (hours).
        _start := NOW() - (time_interval::NUMERIC * INTERVAL '1 hour');
    
        RAISE NOTICE '-> monitoring_history_fn % % start[%]', time_interval, bucket_interval, _start;
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
                        mt.metrics->>'environment.wind.speedTrue',
                        mt.metrics->>'environment.wind.speedApparent'
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
                WHERE mt.vessel_id = current_setting('vessel.id', false)
                    AND mt.time > _start
                GROUP BY time_bucket
                ORDER BY time_bucket asc
        )
        SELECT jsonb_agg(history_table) INTO history_metrics FROM history_table;
    END
$function$
;

COMMENT ON FUNCTION api.monitoring_history_fn(in text, out jsonb) IS 'Export metrics from a time period 24h, 48h, 72h, 7d';

-- Update public.cron_process_monitor_offline_fn, add a new case to detect vessels with fresh metadata but no recent metrics
CREATE OR REPLACE FUNCTION public.cron_process_monitor_offline_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    metadata_rec  record;
    process_id    integer;
    user_settings jsonb;
    metrics_rec   record;
    _interval      CONSTANT INTERVAL := INTERVAL '70 MINUTES';
    _grace_period  CONSTANT INTERVAL := INTERVAL '30 MINUTES';
    _cooldown      CONSTANT INTERVAL := INTERVAL '25 HOURS';
BEGIN
    RAISE NOTICE 'cron_process_monitor_offline_fn';

    FOR metadata_rec IN
        SELECT
            m.vessel_id,
            m.time                                    AS metadata_time,
            -- Case 2 flag: metadata is fresh but metrics are absent/stale
            -- We compute it here so we can branch on it below without
            -- a second join to api.metadata
            (m.time >= NOW() AT TIME ZONE 'UTC' - _interval) AS metadata_fresh,
            NOW() AT TIME ZONE 'UTC' - _interval      AS threshold
        FROM api.metadata m
        WHERE m.active = True
          AND (
              -- Case 1: plugin fully silent — metadata itself is stale
              m.time < NOW() AT TIME ZONE 'UTC' - _interval
              OR
              -- Case 2: plugin alive but no recent metrics (no GPS fix, etc.)
              NOT EXISTS (
                  SELECT 1
                  FROM api.metrics mx
                  WHERE mx.vessel_id = m.vessel_id
                    AND mx.time >= NOW() AT TIME ZONE 'UTC' - _interval
              )
          )
        ORDER BY m.time DESC
    LOOP
        RAISE NOTICE '-> cron_process_monitor_offline_fn vessel_id [%] metadata_fresh [%]',
            metadata_rec.vessel_id, metadata_rec.metadata_fresh;

        IF metadata_rec.vessel_id IS NULL OR metadata_rec.vessel_id = '' THEN
            RAISE WARNING '-> cron_process_monitor_offline_fn invalid vessel_id [%]', metadata_rec;
            CONTINUE;
        END IF;

        PERFORM set_config('vessel.id', metadata_rec.vessel_id, false);

        -- Point-in-time confirmation (guards race between outer scan and now)
        SELECT
            time,
            (NOW() AT TIME ZONE 'UTC' - time) > _interval AS offline
        INTO metrics_rec
        FROM api.metrics
        WHERE vessel_id = current_setting('vessel.id', false)
        ORDER BY time DESC
        LIMIT 1;

        -- metrics_rec.offline IS False → recent metric just arrived → skip
        IF metrics_rec.offline IS False THEN
            CONTINUE;
        END IF;

        IF metadata_rec.metadata_fresh THEN
            -- ---------------------------------------------------------------
            -- Case 2: plugin is connected but sending no metrics
            --   → do NOT touch active (would cause online/offline flapping
            --     with metadata_upsert_trigger_fn)
            --   → use a distinct notification type so the user understands
            --     the difference ("no GPS" vs "plugin offline")
            -- ---------------------------------------------------------------
            -- Grace period after online transition
            PERFORM 1
                FROM process_queue
                WHERE channel   = 'monitoring_online'
                AND ref_id    = metadata_rec.vessel_id
                AND processed >= NOW() AT TIME ZONE 'UTC' - INTERVAL '30 minutes';

            IF FOUND THEN
                RAISE NOTICE '-> cron_process_monitor_offline_fn vessel [%] grace period active, skipping no_metrics',
                    metadata_rec.vessel_id;
                CONTINUE;
            END IF;

            -- Cooldown: only notify once per N hours to avoid spamming the user
            PERFORM 1
            FROM process_queue
            WHERE channel = 'monitoring_no_metrics'
            AND ref_id = metadata_rec.vessel_id
            AND stored >= NOW() AT TIME ZONE 'UTC' - INTERVAL '25 hours';

            IF FOUND THEN
                RAISE NOTICE '-> cron_process_monitor_offline_fn vessel [%] no_metrics cooldown active, skipping', 
                    metadata_rec.vessel_id;
                CONTINUE;
            END IF;

            -- then proceed with send_notification_fn + INSERT into process_queue

            RAISE NOTICE '-> cron_process_monitor_offline_fn vessel [%] no_metrics (metadata alive, last_metric=[%])',
                current_setting('vessel.id', false), metrics_rec.time;

            user_settings := get_user_settings_from_vesselid_fn(metadata_rec.vessel_id::TEXT);
            PERFORM send_notification_fn('monitor_no_metrics'::TEXT, user_settings::JSONB);

            INSERT INTO process_queue
                (channel, payload, stored, processed, ref_id)
            VALUES
                ('monitoring_no_metrics',
                 metadata_rec.vessel_id::TEXT,
                 metadata_rec.threshold,
                 now(),
                 metadata_rec.vessel_id)
            RETURNING id INTO process_id;

        ELSE
            -- ---------------------------------------------------------------
            -- Case 1: plugin fully offline — metadata is also stale
            --   → set active = FALSE (triggers online notification when
            --     plugin reconnects, which is the correct behaviour)
            -- ---------------------------------------------------------------
            UPDATE api.metadata
                SET active = False
                WHERE vessel_id = current_setting('vessel.id', false);

            RAISE NOTICE '-> cron_process_monitor_offline_fn vessel [%] offline (metadata_time=[%], last_metric=[%])',
                current_setting('vessel.id', false),
                metadata_rec.metadata_time,
                metrics_rec.time;

            user_settings := get_user_settings_from_vesselid_fn(metadata_rec.vessel_id::TEXT);
            PERFORM send_notification_fn('monitor_offline'::TEXT, user_settings::JSONB);

            INSERT INTO process_queue
                (channel, payload, stored, processed, ref_id)
            VALUES
                ('monitoring_offline',
                 metadata_rec.vessel_id::TEXT,
                 metadata_rec.threshold,
                 now(),
                 metadata_rec.vessel_id)
            RETURNING id INTO process_id;
        END IF;

        RAISE NOTICE '-> cron_process_monitor_offline_fn process_queue id [%]', process_id;
    END LOOP;
END;
$function$;

COMMENT ON FUNCTION public.cron_process_monitor_offline_fn() IS
'Scheduled by pg_cron. Detects two distinct vessel offline conditions:

  Case 1 — Plugin fully offline (metadata stale > 70m):
    Sets active = FALSE so that metadata_upsert_trigger_fn correctly fires
    monitoring_online when the plugin reconnects.
    Sends: monitor_offline notification.

  Case 2 — Plugin connected but no metrics (metadata fresh, metrics stale/absent):
    Does NOT touch active — avoids online/offline flapping with
    metadata_upsert_trigger_fn which would re-set active = TRUE on every
    metadata heartbeat.
    Sends: monitor_no_metrics notification (distinct type).

  Both cases skip if a recent metric arrived between the outer scan and the
  inner point-in-time confirmation (race guard).';

-- DROP FUNCTION public.logbook_update_extra_json_fn(in int4, in text, in text, out json);
-- Update public.logbook_update_extra_json_fn, add fuel and tank calculations
CREATE OR REPLACE FUNCTION public.logbook_update_extra_json_fn(_id integer, _start text, _end text, OUT _extra_json json)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    log_json          jsonb DEFAULT '{}'::jsonb;
    runtime_json      jsonb DEFAULT '{}'::jsonb;
    tanks_json        jsonb DEFAULT '{}'::jsonb;
    solar_json        jsonb DEFAULT '{}'::jsonb;
    sail_motor_json   jsonb DEFAULT '{}'::jsonb;
    fuel_json         jsonb DEFAULT '{}'::jsonb;
    metrics_json      jsonb DEFAULT '{}'::jsonb;
    metric_rec        record;
    _avg_solar_w      double precision;
    _duration_h       double precision;
    _solar_wh         double precision;
    _sailing_dur      interval;
    _motoring_dur     interval;
    _sailing_dist_m   double precision;
    _motoring_dist_m  double precision;
    _sail_motor_source text;
    _rpm_label        text;
    _rpm_key          text;
    _avg_rpm          numeric;
    _max_rpm          numeric;
    engine_on_seq     public.tbool;
    new_trip_status   public.ttext;
    _fuel_used_key    text;
    _fuel_start       numeric;
    _fuel_end         numeric;
    _total_fuel_used_m3 numeric;
    _fuel_source      text;
    _volume_key       text;
    _capacity_key     text;
    _tank_start       numeric;
    _tank_end         numeric;
    _capacity         numeric;
    _total_tank_fuel_m3 numeric DEFAULT 0;
    _any_tank_fuel    boolean DEFAULT FALSE;
    _fuel_consumed_l  numeric;
    _fuel_avg_lph     numeric;
    _fuel_avg_lpnm    numeric;
    _trip             public.tgeogpoint;
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
    -- propulsion.%.runTime, propulsion.%.revolutions.avg/.max, engine_on_seq,
    -- propulsion.%.fuel.used (tier 1 fuel source) — all per-engine, in one pass
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
        SELECT runtime_json || jsonb_build_object(metric_rec.key, value)
        INTO runtime_json
        FROM runtime;
        RAISE NOTICE '-> logbook_update_extra_json_fn runtime_json: %', runtime_json;

        -- propulsion.<engine>.revolutions.avg/.max — restricted to revolutions > 0
        -- (whole-window AVG including engine-off zero samples understates true
        -- operating RPM; confirmed on real data: 1079 RPM naive vs 1801 RPM
        -- when correctly restricted to running periods)
        _rpm_key := regexp_replace(metric_rec.key, '\.runTime$', '.revolutions');
        SELECT
            AVG((m.metrics->>_rpm_key)::numeric),
            MAX((m.metrics->>_rpm_key)::numeric)
        INTO _avg_rpm, _max_rpm
        FROM api.metrics m
        WHERE m.metrics ? _rpm_key
          AND (m.metrics->>_rpm_key)::numeric > 0
          AND m.time BETWEEN _start::TIMESTAMPTZ AND _end::TIMESTAMPTZ
          AND m.vessel_id = current_setting('vessel.id', false);

        IF _avg_rpm IS NOT NULL THEN
            -- revolutions is Hz per SignalK spec; x60 for actual RPM.
            -- Key renamed .revolutions -> .rpm so the stored number's unit
            -- doesn't silently disagree with its own key name.
            _rpm_label := regexp_replace(_rpm_key, '\.revolutions$', '.rpm');
            runtime_json := runtime_json || jsonb_build_object(
                _rpm_label || '.avg', ROUND(_avg_rpm * 60, 0),
                _rpm_label || '.max', ROUND(_max_rpm * 60, 0)
            );
            RAISE NOTICE '-> logbook_update_extra_json_fn %.avg/.max: % / % RPM (raw Hz: %/%)',
                _rpm_label, ROUND(_avg_rpm * 60, 0), ROUND(_max_rpm * 60, 0), _avg_rpm, _max_rpm;

            -- -----------------------------------------------------------------------
            -- Engine ON/OFF sequence: true whenever ANY propulsion.%.revolutions > 0
            -- -----------------------------------------------------------------------
            SELECT tboolseq(array_agg(tbool(any_on, ts) ORDER BY ts))
            INTO engine_on_seq
            FROM (
                SELECT m.time AS ts, bool_or((kv.value)::numeric > 0) AS any_on
                FROM api.metrics m, jsonb_each_text(m.metrics) AS kv(key, value)
                WHERE kv.key ILIKE 'propulsion.%.revolutions'
                AND m.time BETWEEN _start::TIMESTAMPTZ AND _end::TIMESTAMPTZ
                AND m.vessel_id = current_setting('vessel.id', false)
                GROUP BY m.time
            ) AS per_ts;
        END IF;

        -- propulsion.<engine>.fuel.used (tier 1) — monotonic counter, same
        -- delta pattern as runTime. Safe to SUM across engines: two engines
        -- running simultaneously really do burn double the fuel.
        _fuel_used_key := regexp_replace(metric_rec.key, '\.runTime$', '.fuel.used');
        SELECT (m.metrics->>_fuel_used_key)::numeric INTO _fuel_start
        FROM api.metrics m
        WHERE m.time = _start::TIMESTAMPTZ
          AND m.vessel_id = current_setting('vessel.id', false)
          AND m.metrics ? _fuel_used_key;
        SELECT (m.metrics->>_fuel_used_key)::numeric INTO _fuel_end
        FROM api.metrics m
        WHERE m.time = _end::TIMESTAMPTZ
          AND m.vessel_id = current_setting('vessel.id', false)
          AND m.metrics ? _fuel_used_key;
        IF _fuel_start IS NOT NULL AND _fuel_end IS NOT NULL THEN
            _total_fuel_used_m3 := COALESCE(_total_fuel_used_m3, 0) + (_fuel_end - _fuel_start);
            _fuel_source := 'propulsion.fuel.used';
            RAISE NOTICE '-> logbook_update_extra_json_fn %: % m3', _fuel_used_key, _fuel_end - _fuel_start;
        END IF;
    END LOOP;
    -- -----------------------------------------------------------------------
    -- tanks.%.currentLevel — level change per tank per trip (all tank types)
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
                SELECT ROUND(
                    (end_level.value::NUMERIC - metric_rec.value::NUMERIC),
                    4
                ) AS value
                FROM end_level
            )
        SELECT tanks_json || jsonb_build_object(metric_rec.key, value)
        INTO tanks_json
        FROM delta;
        RAISE NOTICE '-> logbook_update_extra_json_fn tanks_json: %', tanks_json;
    END LOOP;
    -- -----------------------------------------------------------------------
    -- Fuel tiers 2/3 — ONLY when no engine reported fuel.used above.
    -- Tier 2: tanks.fuel.%.currentVolume delta (m3, direct, no capacity needed)
    -- Tier 3: tanks.fuel.%.currentLevel delta × tanks.fuel.%.capacity (m3)
    -- Still exposed to the duplicate-tank-instance risk observed on real data
    -- (same physical tank reported under two instance numbers) — unresolved
    -- here, isolated to this fallback path only.
    -- -----------------------------------------------------------------------
    IF _total_fuel_used_m3 IS NULL THEN
        FOR metric_rec IN
            SELECT DISTINCT key
            FROM api.metrics m, jsonb_each_text(m.metrics)
            WHERE key ILIKE 'tanks.fuel.%.currentLevel'
              AND time = _start::TIMESTAMPTZ
              AND vessel_id = current_setting('vessel.id', false)
        LOOP
			-- Tier 2: sibling currentVolume key for this same tank instance?
            _volume_key := regexp_replace(metric_rec.key, '\.currentLevel$', '.currentVolume');
            SELECT (m.metrics->>_volume_key)::numeric INTO _tank_start
            FROM api.metrics m
            WHERE m.time = _start::TIMESTAMPTZ AND m.vessel_id = current_setting('vessel.id', false) AND m.metrics ? _volume_key;
            SELECT (m.metrics->>_volume_key)::numeric INTO _tank_end
            FROM api.metrics m
            WHERE m.time = _end::TIMESTAMPTZ AND m.vessel_id = current_setting('vessel.id', false) AND m.metrics ? _volume_key;

            IF _tank_start IS NOT NULL AND _tank_end IS NOT NULL THEN
                IF (_tank_start - _tank_end) > 0 THEN
                    _total_tank_fuel_m3 := _total_tank_fuel_m3 + (_tank_start - _tank_end);
                    _any_tank_fuel := TRUE;
                    _fuel_source := COALESCE(_fuel_source, 'tanks.currentVolume');
                    RAISE NOTICE '-> logbook_update_extra_json_fn %: % m3 (tier2)', _volume_key, _tank_start - _tank_end;
                ELSE
                    RAISE NOTICE '-> logbook_update_extra_json_fn % volume increased mid-trip (refuel/transfer?), excluding from consumption calc: % -> %', _volume_key, _tank_start, _tank_end;
                END IF;
            ELSE
                -- Tier 3: currentLevel ratio x static capacity
                SELECT (m.metrics->>metric_rec.key)::numeric INTO _tank_start
                FROM api.metrics m
                WHERE m.time = _start::TIMESTAMPTZ AND m.vessel_id = current_setting('vessel.id', false) AND m.metrics ? metric_rec.key;
                SELECT (m.metrics->>metric_rec.key)::numeric INTO _tank_end
                FROM api.metrics m
                WHERE m.time = _end::TIMESTAMPTZ AND m.vessel_id = current_setting('vessel.id', false) AND m.metrics ? metric_rec.key;
                _capacity_key := regexp_replace(metric_rec.key, '\.currentLevel$', '.capacity');
                SELECT (m.metrics->>_capacity_key)::numeric INTO _capacity
                FROM api.metrics m
                WHERE m.time = _start::TIMESTAMPTZ AND m.vessel_id = current_setting('vessel.id', false) AND m.metrics ? _capacity_key
                LIMIT 1;
                IF _tank_start IS NOT NULL AND _tank_end IS NOT NULL AND _capacity IS NOT NULL THEN
                    IF (_tank_start - _tank_end) > 0 THEN
                        _total_tank_fuel_m3 := _total_tank_fuel_m3 + ((_tank_start - _tank_end) * _capacity);
                        _any_tank_fuel := TRUE;
                        _fuel_source := COALESCE(_fuel_source, 'tanks.currentLevel');
                        RAISE NOTICE '-> logbook_update_extra_json_fn %: % m3 (tier3, capacity=%)', metric_rec.key, (_tank_start - _tank_end) * _capacity, _capacity;
                    ELSE
                        RAISE NOTICE '-> logbook_update_extra_json_fn % level increased mid-trip (refuel/transfer?), excluding from consumption calc: % -> %', metric_rec.key, _tank_start, _tank_end;
                    END IF;
                END IF;
            END IF;
        END LOOP;
        IF _any_tank_fuel THEN
            _total_fuel_used_m3 := _total_tank_fuel_m3;
        END IF;
    END IF;
    -- -----------------------------------------------------------------------
    -- Solar energy produced per trip (Wh)
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
    -- Sailing vs motoring split — RPM-derived (primary) or navigation.state
    -- (fallback, no engine sensor). Also OVERWRITES api.logbook.trip_status
    -- with the RPM-derived sequence when available, so per-point track
    -- coloring (export_logbook_geojson_point_trip_fn) reflects the same
    -- truth as these stats, not the unreliable navigation.state.
    -- -----------------------------------------------------------------------
    IF engine_on_seq IS NOT NULL THEN
        SELECT trip INTO _trip FROM api.logbook WHERE id = _id;
        _motoring_dur    := duration(atValues(engine_on_seq, true));
        _sailing_dur     := duration(atValues(engine_on_seq, false));
        _motoring_dist_m := length(atTime(_trip, getTime(atValues(engine_on_seq, true))));
        _sailing_dist_m  := length(atTime(_trip, getTime(atValues(engine_on_seq, false))));
        _sail_motor_source := 'propulsion.revolutions';

        SELECT ttextseq(array_agg(
            ttext(CASE WHEN getValue(inst) THEN 'motoring' ELSE 'sailing' END, getTimestamp(inst))
            ORDER BY getTimestamp(inst)
        ))
        INTO new_trip_status
        FROM unnest(instants(engine_on_seq)) AS inst;

        IF new_trip_status IS NOT NULL THEN
            UPDATE api.logbook SET trip_status = new_trip_status WHERE id = _id;
            RAISE NOTICE '-> logbook_update_extra_json_fn trip_status overwritten with RPM-derived sequence';
        END IF;

        RAISE NOTICE '-> logbook_update_extra_json_fn sail/motor via RPM: motoring_dur=% sailing_dur=%',
            _motoring_dur, _sailing_dur;
    ELSE
        SELECT
            duration(atValues(trip_status, 'sailing')),
            duration(atValues(trip_status, 'motoring')),
            length(atTime(trip, getTime(atValues(trip_status, 'sailing')))),
            length(atTime(trip, getTime(atValues(trip_status, 'motoring'))))
        INTO _sailing_dur, _motoring_dur, _sailing_dist_m, _motoring_dist_m
        FROM api.logbook
        WHERE id = _id
          AND trip_status IS NOT NULL;
        IF _sailing_dur IS NOT NULL OR _motoring_dur IS NOT NULL THEN
            _sail_motor_source := 'navigation.state';
            RAISE NOTICE '-> logbook_update_extra_json_fn sail/motor via navigation.state (no RPM sensor): motoring_dur=% sailing_dur=%',
                _motoring_dur, _sailing_dur;
        END IF;
    END IF;
    IF _sail_motor_source IS NOT NULL THEN
        sail_motor_json := jsonb_build_object(
            'sailing.duration',       COALESCE(_sailing_dur, '0'::interval),
            'sailing.distance_nm',    ROUND((COALESCE(_sailing_dist_m, 0) / 1852.0)::NUMERIC, 2),
            'motoring.duration',      COALESCE(_motoring_dur, '0'::interval),
            'motoring.distance_nm',   ROUND((COALESCE(_motoring_dist_m, 0) / 1852.0)::NUMERIC, 2),
            'sailing_motoring.source', _sail_motor_source
        );
    END IF;
    -- -----------------------------------------------------------------------
    -- Fuel: total consumed + derived rates, using motoring-only duration/
    -- distance from the split above as denominators.
    -- -----------------------------------------------------------------------
    IF _total_fuel_used_m3 IS NOT NULL THEN
        _fuel_consumed_l := ROUND((_total_fuel_used_m3 * 1000)::NUMERIC, 2);
        IF _motoring_dur IS NOT NULL AND EXTRACT(EPOCH FROM _motoring_dur) > 0 THEN
            _fuel_avg_lph := ROUND((_fuel_consumed_l / (EXTRACT(EPOCH FROM _motoring_dur) / 3600.0))::NUMERIC, 2);
        END IF;
        IF _motoring_dist_m IS NOT NULL AND _motoring_dist_m > 0 THEN
            _fuel_avg_lpnm := ROUND((_fuel_consumed_l / (_motoring_dist_m / 1852.0))::NUMERIC, 2);
        END IF;
        fuel_json := jsonb_build_object(
            'fuel.consumed_l', _fuel_consumed_l,
            'fuel.avg_lph',    _fuel_avg_lph,
            'fuel.avg_lpnm',   _fuel_avg_lpnm,
            'fuel.source',     _fuel_source
        );
        RAISE NOTICE '-> logbook_update_extra_json_fn fuel_json: %', fuel_json;
    END IF;
    -- -----------------------------------------------------------------------
    -- Assemble final extra JSON
    -- -----------------------------------------------------------------------
    SELECT
        COALESCE(log_json,        '{}'::jsonb)
        || COALESCE(runtime_json,    '{}'::jsonb)
        || COALESCE(tanks_json,      '{}'::jsonb)
        || COALESCE(solar_json,      '{}'::jsonb)
        || COALESCE(sail_motor_json, '{}'::jsonb)
        || COALESCE(fuel_json,       '{}'::jsonb)
    INTO metrics_json;
    SELECT jsonb_build_object('metrics', metrics_json) INTO _extra_json;
    RAISE NOTICE '-> logbook_update_extra_json_fn _extra_json: %', _extra_json;
END;
$function$
;

COMMENT ON FUNCTION public.logbook_update_extra_json_fn(in int4, in text, in text, out json) IS 'Compute per-trip SignalK metric deltas and store in logbook.extra->metrics. navigation.log: trip distance delta. propulsion.%.runTime: engine hours. propulsion.%.revolutions.avg/.max: avg/max RPM restricted to running periods (RPM>0). tanks.%.currentLevel: level change per tank. solar.energy_wh: solar produced. sailing.*/motoring.*: split of trip time/distance, PRIMARY source propulsion.%.revolutions>0 (any engine turning), FALLBACK trip_status (navigation.state). Also OVERWRITES api.logbook.trip_status with the RPM-derived sequence when available — side effect beyond extra_json, deliberate to keep GeoJSON per-point track coloring consistent with these stats. fuel.consumed_l/avg_lph/avg_lpnm: 3-tier fuel source — tier1 propulsion.%.fuel.used (summed across engines, safe since concurrent engines really do burn concurrently), tier2 tanks.fuel.%.currentVolume delta, tier3 tanks.fuel.%.currentLevel x capacity. Rates use motoring-only duration/distance as denominators. fuel.source/sailing_motoring.source record which tier/method was used, silently, for traceability.';

-- DROP FUNCTION public.send_pushover_py_fn(text, jsonb, jsonb);
-- Update public.send_pushover_py_fn, fix app settings, add HTML support
CREATE OR REPLACE FUNCTION public.send_pushover_py_fn(message_type text, _user jsonb, app jsonb)
 RETURNS void
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
AS $function$
    """
    https://pushover.net/api#messages
    Send a notification to a pushover user
    """
    import requests
    from urllib.parse import urljoin

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

    def clean_url(base, path):
        base = base.rstrip('/') + '/'
        path = '/' + '/'.join(filter(None, path.split('/')))
        return urljoin(base, path)

    # Replace fields using input jsonb obj
    if 'logbook_name' in _user and _user['logbook_name']:
        pushover_message = pushover_message.replace('__LOGBOOK_NAME__', _user['logbook_name'])
    if 'logbook_link' in _user and _user['logbook_link']:
        pushover_message = pushover_message.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'video_link' in _user and _user['video_link'] and 'app.videos_url' in app and app['app.videos_url']:
        pushover_message = pushover_message.replace('__VIDEO_LINK__', clean_url(app['app.videos_url'], str(_user['video_link'])))
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

    headers = {"User-Agent": "PostgSail", "From": "postgsail@localhost"}
    if 'ua' in _user and _user['ua']:
        headers["User-Agent"] = _user['ua']
        headers["From"] = _user['app.email_from']

    if message_type == 'logbook' and 'logbook_img' in _user and _user['logbook_img'] and 'app.gis_url' in app and app['app.gis_url']:
        # Send notification with gis image logbook as attachment
        img_url = '{}'.format(clean_url(app['app.gis_url'], str(_user['logbook_img'])))
        response = requests.get(img_url, headers=headers, stream=True, timeout=(5, 60))
        if response.status_code == 200:
            r = requests.post("https://api.pushover.net/1/messages.json", data = {
                "token": pushover_token,
                "user": pushover_user,
                "title": pushover_title,
                "message": pushover_message,
                "html": 1
            }, files = {
                "attachment": (str(_user['logbook_img']), response.raw.data, "image/png")
            }, headers=headers, timeout=(60, 60))
    else:
        r = requests.post("https://api.pushover.net/1/messages.json", data = {
                "token": pushover_token,
                "user": pushover_user,
                "title": pushover_title,
                "message": pushover_message,
                "html": 1
        }, headers=headers, timeout=(60, 60))

    #print(r.text)
    # Return ?? or None if not found
    #plpy.notice('Sent pushover successfully to [{}] [{}]'.format(r.text, r.status_code))
    if r.status_code == 200:
        plpy.notice('Sent pushover successfully to [{}] [{}] [{}]'.format(pushover_user, pushover_title, r.text))
    else:
        plpy.error('Failed to send pushover')
    return None
$function$
;

COMMENT ON FUNCTION public.send_pushover_py_fn(text, jsonb, jsonb) IS 'Send pushover notification using plpython3u';

-- Add public.sanitize_range_fn, a utility function to clamp a raw sensor/derived value to a physically plausible range before it enters a fixed-precision column or a MobilityDB temporal sequence. Returns NULL unchanged (does not manufacture data), otherwise clamps to [_min, _max].
CREATE OR REPLACE FUNCTION public.sanitize_range_fn(_value double precision, _min double precision, _max double precision)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE
AS $$
    SELECT CASE WHEN _value IS NULL THEN NULL
                ELSE LEAST(GREATEST(_value, _min), _max)
           END;
$$;
COMMENT ON FUNCTION public.sanitize_range_fn(double precision, double precision, double precision) IS
    'Clamp a raw sensor/derived value to a physically plausible range before it enters a fixed-precision column or a MobilityDB temporal sequence. Returns NULL unchanged (does not manufacture data), otherwise clamps to [_min, _max].';

-- DROP FUNCTION public.logbook_update_metrics_timebucket_fn(int4, timestamptz, timestamptz);
-- Update public.logbook_update_metrics_timebucket_fn, ignore invalid winspeed metrics
CREATE OR REPLACE FUNCTION public.logbook_update_metrics_timebucket_fn(total_entry integer, start_date timestamp with time zone, end_date timestamp with time zone)
 RETURNS TABLE(trajectory tgeogpoint, courseovergroundtrue tfloat, speedoverground tfloat, windspeedapparent tfloat, windangleapparent tfloat, truewindspeed tfloat, truewinddirection tfloat, notes ttext, status ttext, watertemperature tfloat, depth tfloat, outsidehumidity tfloat, outsidepressure tfloat, outsidetemperature tfloat, stateofcharge tfloat, voltage tfloat, solarpower tfloat, solarvoltage tfloat, tanklevel tfloat, heading tfloat)
 LANGUAGE plpgsql
AS $function$
DECLARE
    bucket_interval INTERVAL;
    trip_duration INTERVAL;
BEGIN
    -- Compute voyage duration
    trip_duration := end_date - start_date;

    -- Choose bucket interval based on trip duration
    -- 1m (<= 6h), 2m (<= 12h), 3m (<= 18h), 5m (<= 24h), 10m (<= 48h), else 15m
    IF trip_duration <= INTERVAL '6 hours' THEN
        bucket_interval := '1 minute';
    ELSIF trip_duration <= INTERVAL '12 hours' THEN
        bucket_interval := '2 minutes';
    ELSIF trip_duration <= INTERVAL '18 hours' THEN
        bucket_interval := '3 minutes';
    ELSIF trip_duration <= INTERVAL '24 hours' THEN
        bucket_interval := '5 minutes';
    ELSIF trip_duration <= INTERVAL '48 hours' THEN
        bucket_interval := '10 minutes';
    ELSE
        bucket_interval := '15 minutes';
    END IF;

    RETURN QUERY
    WITH metrics AS (
        -- Extract metrics base the total of entry ignoring first and last 10 minutes metrics
        SELECT time_bucket(bucket_interval::INTERVAL, mt.time) AS time_bucket,  -- Time-bucketed period
            avg(mt.courseovergroundtrue) as courseovergroundtrue,
            avg(mt.speedoverground) as speedoverground,
            avg(mt.windspeedapparent) as windspeedapparent, -- Wind Speed Apparent in knots from plugin
            avg(mt.anglespeedapparent) as anglespeedapparent, -- Wind Angle Apparent in degrees from plugin
            last(mt.longitude, mt.time) as longitude, last(mt.latitude, mt.time) as latitude,
            '' AS notes,
            last(mt.status, mt.time) as status,
            -- Heading True (converted from radians to degrees)
            COALESCE(
                last(mt.metrics->>'heading', mt.time),
                last(mt.metrics->>'navigation.headingTrue', mt.time)
            )::FLOAT * (180.0 / PI()) AS heading,
			-- Wind Speed True (converted from m/s to knots). Clamped to
            -- [0, 100] kn before conversion: environment.wind.speedTrue has
            -- been observed diverging to 9-digit values from an unstable
            -- upstream true-wind estimator on some vessels/sessions.
            public.sanitize_range_fn(
                COALESCE(
                    last(mt.metrics->'wind'->>'speed', mt.time),
                    last(mt.metrics->>(md.configuration->>'windSpeedKey'), mt.time),
                    last(mt.metrics->>'environment.wind.speedTrue', mt.time)
                )::FLOAT,
                0, 100
            ) * 1.94384 AS truewindspeed,
            -- Wind Direction True (converted from radians to degrees)
            COALESCE(
                last(mt.metrics->'wind'->>'direction', mt.time),
                last(mt.metrics->>(md.configuration->>'windDirectionKey'), mt.time),
                last(mt.metrics->>'environment.wind.directionTrue', mt.time)
            )::FLOAT * (180.0 / PI()) AS truewinddirection,
            -- Water Temperature
            COALESCE(
                last(mt.metrics->'water'->>'temperature', mt.time),
                last(mt.metrics->>(md.configuration->>'waterTemperatureKey'), mt.time),
                last(mt.metrics->>'environment.water.temperature', mt.time)
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                last(mt.metrics->'water'->>'depth', mt.time),
                last(mt.metrics->>(md.configuration->>'depthKey'), mt.time),
                last(mt.metrics->>'environment.depth.belowTransducer', mt.time)
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                last(mt.metrics->'humidity'->>'outside', mt.time),
                last(mt.metrics->>(md.configuration->>'outsideHumidityKey'), mt.time),
                last(mt.metrics->>'environment.outside.relativeHumidity', mt.time),
                last(mt.metrics->>'environment.outside.humidity', mt.time)
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                last(mt.metrics->'pressure'->>'outside', mt.time),
                last(mt.metrics->>(md.configuration->>'outsidePressureKey'), mt.time),
                last(mt.metrics->>'environment.outside.pressure', mt.time)
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                last(mt.metrics->'temperature'->>'outside', mt.time),
                last(mt.metrics->>(md.configuration->>'outsideTemperatureKey'), mt.time),
                last(mt.metrics->>'environment.outside.temperature', mt.time)
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                last(mt.metrics->'battery'->>'charge', mt.time),
                last(mt.metrics->>(md.configuration->>'stateOfChargeKey'), mt.time),
                last(mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge', mt.time)
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                last(mt.metrics->'battery'->>'voltage', mt.time),
                last(mt.metrics->>(md.configuration->>'voltageKey'), mt.time),
                last(mt.metrics->>'electrical.batteries.House.voltage', mt.time)
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                last(mt.metrics->'solar'->>'power', mt.time),
                last(mt.metrics->>(md.configuration->>'solarPowerKey'), mt.time),
                last(mt.metrics->>'electrical.solar.Main.panelPower', mt.time)
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                last(mt.metrics->'solar'->>'voltage', mt.time),
                last(mt.metrics->>(md.configuration->>'solarVoltageKey'), mt.time),
                last(mt.metrics->>'electrical.solar.Main.panelVoltage', mt.time)
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                last(mt.metrics->'tank'->>'level', mt.time),
                last(mt.metrics->>(md.configuration->>'tankLevelKey'), mt.time),
                last(mt.metrics->>'tanks.fuel.0.currentLevel', mt.time)
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(last(mt.longitude, mt.time),last(mt.latitude, mt.time)) AS geo_point
        FROM api.metrics mt
        JOIN api.metadata md ON md.vessel_id = mt.vessel_id
        WHERE mt.latitude IS NOT NULL
            AND mt.longitude IS NOT NULL
            AND mt.time > (start_date + interval '10 minutes')
            AND mt.time < (end_date - interval '10 minutes')
            AND mt.vessel_id = current_setting('vessel.id', false)
        GROUP BY time_bucket
        ORDER BY time_bucket ASC
    ),
    first_metric AS (
        -- Extract first 10 minutes metrics
        SELECT 
            mt.time AS time_bucket,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.anglespeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True (converted from radians to degrees)
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT * (180.0 / PI()) AS heading,
			-- Wind Speed True (converted from m/s to knots). Clamped to
            -- [0, 100] kn before conversion: environment.wind.speedTrue has
            -- been observed diverging to 9-digit values from an unstable
            -- upstream true-wind estimator on some vessels/sessions.
            public.sanitize_range_fn(
                COALESCE(
                    mt.metrics->'wind'->>'speed',
                    mt.metrics->>(md.configuration->>'windSpeedKey'),
                    mt.metrics->>'environment.wind.speedTrue'
                )::FLOAT,
                0, 100
            ) * 1.94384 AS truewindspeed,
            -- Wind Direction True (converted from radians to degrees)
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT * (180.0 / PI()) AS truewinddirection,
            -- Water Temperature
            COALESCE(
                mt.metrics->'water'->>'temperature',
                mt.metrics->>(md.configuration->>'waterTemperatureKey'),
                mt.metrics->>'environment.water.temperature'
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                mt.metrics->'water'->>'depth',
                mt.metrics->>(md.configuration->>'depthKey'),
                mt.metrics->>'environment.depth.belowTransducer'
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                mt.metrics->'humidity'->>'outside',
                mt.metrics->>(md.configuration->>'outsideHumidityKey'),
                mt.metrics->>'environment.outside.relativeHumidity',
                mt.metrics->>'environment.outside.humidity'
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                mt.metrics->'pressure'->>'outside',
                mt.metrics->>(md.configuration->>'outsidePressureKey'),
                mt.metrics->>'environment.outside.pressure'
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                mt.metrics->'temperature'->>'outside',
                mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
                mt.metrics->>'environment.outside.temperature'
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                mt.metrics->'battery'->>'charge',
                mt.metrics->>(md.configuration->>'stateOfChargeKey'),
                mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                mt.metrics->'battery'->>'voltage',
                mt.metrics->>(md.configuration->>'voltageKey'),
                mt.metrics->>'electrical.batteries.House.voltage'
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                mt.metrics->'solar'->>'power',
                mt.metrics->>(md.configuration->>'solarPowerKey'),
                mt.metrics->>'electrical.solar.Main.panelPower'
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                mt.metrics->'solar'->>'voltage',
                mt.metrics->>(md.configuration->>'solarVoltageKey'),
                mt.metrics->>'electrical.solar.Main.panelVoltage'
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                mt.metrics->'tank'->>'level',
                mt.metrics->>(md.configuration->>'tankLevelKey'),
                mt.metrics->>'tanks.fuel.0.currentLevel'
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(mt.longitude, mt.latitude) AS geo_point
        FROM api.metrics mt
        JOIN api.metadata md ON md.vessel_id = mt.vessel_id
        WHERE mt.latitude IS NOT NULL
            AND mt.longitude IS NOT NULL
            AND mt.time > start_date
            AND mt.time < (start_date + interval '10 minutes')
            AND mt.vessel_id = current_setting('vessel.id', false)
        ORDER BY time_bucket ASC
    ),
    last_metric AS (
        -- Extract last 10 minutes metrics
        SELECT 
            mt.time AS time_bucket,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.anglespeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True (converted from radians to degrees)
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT * (180.0 / PI()) AS heading,
            -- Wind Speed True (converted from m/s to knots) Clamped to
            -- [0, 100] kn before conversion: environment.wind.speedTrue has
            -- been observed diverging to 9-digit values from an unstable
            -- upstream true-wind estimator on some vessels/sessions.
            public.sanitize_range_fn(
                COALESCE(
                    mt.metrics->'wind'->>'speed',
                    mt.metrics->>(md.configuration->>'windSpeedKey'),
                    mt.metrics->>'environment.wind.speedTrue'
                )::FLOAT,
                0, 100
            ) * 1.94384 AS truewindspeed,
            -- Wind Direction True (converted from radians to degrees)
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT * (180.0 / PI()) AS truewinddirection,
            -- Water Temperature
            COALESCE(
                mt.metrics->'water'->>'temperature',
                mt.metrics->>(md.configuration->>'waterTemperatureKey'),
                mt.metrics->>'environment.water.temperature'
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                mt.metrics->'water'->>'depth',
                mt.metrics->>(md.configuration->>'depthKey'),
                mt.metrics->>'environment.depth.belowTransducer'
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                mt.metrics->'humidity'->>'outside',
                mt.metrics->>(md.configuration->>'outsideHumidityKey'),
                mt.metrics->>'environment.outside.relativeHumidity',
                mt.metrics->>'environment.outside.humidity'
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                mt.metrics->'pressure'->>'outside',
                mt.metrics->>(md.configuration->>'outsidePressureKey'),
                mt.metrics->>'environment.outside.pressure'
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                mt.metrics->'temperature'->>'outside',
                mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
                mt.metrics->>'environment.outside.temperature'
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                mt.metrics->'battery'->>'charge',
                mt.metrics->>(md.configuration->>'stateOfChargeKey'),
                mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                mt.metrics->'battery'->>'voltage',
                mt.metrics->>(md.configuration->>'voltageKey'),
                mt.metrics->>'electrical.batteries.House.voltage'
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                mt.metrics->'solar'->>'power',
                mt.metrics->>(md.configuration->>'solarPowerKey'),
                mt.metrics->>'electrical.solar.Main.panelPower'
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                mt.metrics->'solar'->>'voltage',
                mt.metrics->>(md.configuration->>'solarVoltageKey'),
                mt.metrics->>'electrical.solar.Main.panelVoltage'
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                mt.metrics->'tank'->>'level',
                mt.metrics->>(md.configuration->>'tankLevelKey'),
                mt.metrics->>'tanks.fuel.0.currentLevel'
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(mt.longitude, mt.latitude) AS geo_point
        FROM api.metrics mt
        JOIN api.metadata md ON md.vessel_id = mt.vessel_id
        WHERE mt.latitude IS NOT NULL
            AND mt.longitude IS NOT NULL
            AND mt.time < end_date
            AND mt.time > (end_date - interval '10 minutes')
            AND mt.vessel_id = current_setting('vessel.id', false)
        ORDER BY time_bucket ASC
    ),
    optimize_metrics AS (
        -- Combine and order the results
        SELECT * FROM first_metric
        UNION ALL
        SELECT * FROM metrics
        UNION ALL
        SELECT * FROM last_metric
        ORDER BY time_bucket ASC
    )
    -- Create mobilitydb temporal sequences
    SELECT 
        tgeogpointseq(array_agg(tgeogpoint(ST_SetSRID(o.geo_point, 4326)::geography, o.time_bucket) ORDER BY o.time_bucket ASC)) AS trajectory,
        tfloatseq(array_agg(tfloat(o.courseovergroundtrue, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.courseovergroundtrue IS NOT NULL)) AS courseovergroundtrue,
        tfloatseq(array_agg(tfloat(o.speedoverground, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.speedoverground IS NOT NULL)) AS speedoverground,
        tfloatseq(array_agg(tfloat(o.windspeedapparent, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.windspeedapparent IS NOT NULL)) AS windspeedapparent,
        tfloatseq(array_agg(tfloat(o.anglespeedapparent, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.anglespeedapparent IS NOT NULL)) AS windangleapparent,
        tfloatseq(array_agg(tfloat(o.truewindspeed, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.truewindspeed IS NOT NULL)) AS truewindspeed,
        tfloatseq(array_agg(tfloat(o.truewinddirection, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.truewinddirection IS NOT NULL)) AS truewinddirection,
        ttextseq(array_agg(ttext(o.notes, o.time_bucket) ORDER BY o.time_bucket ASC)) AS notes,
        ttextseq(array_agg(ttext(o.status, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.status IS NOT NULL)) AS status,
        tfloatseq(array_agg(tfloat(o.watertemperature, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.watertemperature IS NOT NULL)) AS watertemperature,
        tfloatseq(array_agg(tfloat(o.depth, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.depth IS NOT NULL)) AS depth,
        tfloatseq(array_agg(tfloat(o.outsidehumidity, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.outsidehumidity IS NOT NULL)) AS outsidehumidity,
        tfloatseq(array_agg(tfloat(o.outsidepressure, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.outsidepressure IS NOT NULL)) AS outsidepressure,
        tfloatseq(array_agg(tfloat(o.outsidetemperature, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.outsidetemperature IS NOT NULL)) AS outsidetemperature,
        tfloatseq(array_agg(tfloat(o.stateofcharge, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.stateofcharge IS NOT NULL)) AS stateofcharge,
        tfloatseq(array_agg(tfloat(o.voltage, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.voltage IS NOT NULL)) AS voltage,
        tfloatseq(array_agg(tfloat(o.solarPower, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.solarPower IS NOT NULL)) AS solarPower,
        tfloatseq(array_agg(tfloat(o.solarVoltage, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.solarVoltage IS NOT NULL)) AS solarVoltage,
        tfloatseq(array_agg(tfloat(o.tankLevel, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.tankLevel IS NOT NULL)) AS tankLevel,
        tfloatseq(array_agg(tfloat(o.heading, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.heading IS NOT NULL)) AS heading
    FROM optimize_metrics o;
END;
$function$
;

COMMENT ON FUNCTION public.logbook_update_metrics_timebucket_fn(int4, timestamptz, timestamptz) IS 'Optimize logbook metrics base on the aggregate time-series';

-- DROP FUNCTION public.badges_moorages_fn();
-- Update public.badges_moorages_fn, add Traveler badge
CREATE OR REPLACE FUNCTION public.badges_moorages_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
    DECLARE
        _badges jsonb;
        _exist BOOLEAN := false;
        duration integer;
        badge text;
        user_settings jsonb;
        _country integer := 0;
    BEGIN
        -- Check and set environment
        user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
        PERFORM set_config('user.email', user_settings->>'email'::TEXT, false);
        -- Guard against leftover table from a prior iteration or failed run
        DROP TABLE IF EXISTS badges_moorages_tbl;
        -- Get moorages with total duration
        CREATE TEMP TABLE badges_moorages_tbl AS
            SELECT
                m.id,
                m.home_flag,
                m.stay_code                                                          AS default_stay_id,
                COALESCE(SUM(s.duration), INTERVAL 'PT0S')                          AS total_duration,
                EXTRACT(day FROM COALESCE(SUM(s.duration), INTERVAL 'PT0S'))::int   AS total_duration_days
            FROM api.moorages m
            LEFT JOIN api.stays s
                ON  s.moorage_id = m.id
                AND s.active     = false
                AND s.vessel_id  = current_setting('vessel.id', false)
            WHERE m.geog       IS NOT NULL
            AND m.vessel_id   = current_setting('vessel.id', false)
            GROUP BY m.id, m.home_flag, m.stay_code
            ORDER BY total_duration_days DESC;

        -- Explorer = 10 days away from home port
        SELECT (preferences->'badges'->'Explorer') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
            --select sum(m.stay_duration) from api.moorages m where home_flag is false;
            --SELECT extract(day from (select sum(m.stay_duration) INTO duration FROM api.moorages m WHERE home_flag IS false AND vessel_id = current_setting('vessel.id', false) ));
            SELECT total_duration_days INTO duration FROM badges_moorages_tbl WHERE home_flag IS FALSE;
            if duration >= 10 then
                -- Create badge
                badge := '{"Explorer": {"date":"' || NOW()::timestamp || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Explorer"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

        -- Mooring Pro = 10 nights on buoy!
        SELECT (preferences->'badges'->'Mooring Pro') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
            -- select sum(m.stay_duration) from api.moorages m where stay_code = 3;
            --SELECT extract(day from (select sum(m.stay_duration) INTO duration FROM api.moorages m WHERE stay_code = 3 AND vessel_id = current_setting('vessel.id', false) ));
            SELECT total_duration_days INTO duration FROM badges_moorages_tbl WHERE default_stay_id = 3;
            if duration >= 10 then
                -- Create badge
                badge := '{"Mooring Pro": {"date":"' || NOW()::timestamp || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Mooring Pro"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

        -- Anchormaster = 25 days on anchor
        SELECT (preferences->'badges'->'Anchormaster') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
            -- select sum(m.stay_duration) from api.moorages m where stay_code = 2;
            -- SELECT extract(day from (select sum(m.stay_duration) INTO duration FROM api.moorages m WHERE stay_code = 2 AND vessel_id = current_setting('vessel.id', false) ));
            SELECT total_duration_days INTO duration FROM badges_moorages_tbl WHERE default_stay_id = 2;
            if duration >= 25 then
                -- Create badge
                badge := '{"Anchormaster": {"date":"' || NOW()::timestamp || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Anchormaster"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

        -- Traveler more than 1 country
        SELECT (preferences->'badges'->'Traveler') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
			SELECT COUNT(*) INTO _country FROM (
							SELECT DISTINCT m.country 
							FROM api.moorages m
							WHERE country IS NOT NULL
								AND vessel_id = current_setting('vessel.id', false));
            if _country >= 2 then
                -- Create badge
                badge := '{"Traveler": {"date":"' || NOW()::timestamp || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Traveler"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

    -- Drop the temporary table
    DROP TABLE IF EXISTS badges_moorages_tbl;

    END;
$function$
;

COMMENT ON FUNCTION public.badges_moorages_fn() IS 'check moorages for new badges, eg: Explorer, Mooring Pro, Anchormaster';

-- Update public.badges_logbook_fn, update Speed Demon
CREATE OR REPLACE FUNCTION public.badges_logbook_fn(logbook_id integer, logbook_time text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    _badges             jsonb;
    _exist              BOOLEAN := null;
    total               integer;
    max_wind_speed      integer;
    distance            numeric;
    badge               text;
    user_settings       jsonb;
    -- Speed Demon specific
    _current_best_nm    numeric  := 0;
    _new_best_nm        numeric  := 0;
    _new_best_log       integer;
BEGIN
    -- -----------------------------------------------------------------------
    -- Helmsman: first logbook entry
    -- -----------------------------------------------------------------------
    SELECT (preferences->'badges'->'Helmsman') IS NOT NULL INTO _exist
    FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
    IF _exist IS false THEN
        SELECT count(*) INTO total FROM api.logbook l
        WHERE vessel_id = current_setting('vessel.id', false);
        IF total >= 1 THEN
            badge := '{"Helmsman": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
            SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) INTO badge;
            PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
            user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
            SELECT user_settings::JSONB || '{"badge": "Helmsman"}'::JSONB INTO user_settings;
            PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
        END IF;
    END IF;
 
    -- -----------------------------------------------------------------------
    -- Wake Maker: max wind speed ≥ 15 kn
    -- -----------------------------------------------------------------------
    SELECT (preferences->'badges'->'Wake Maker') IS NOT NULL INTO _exist
    FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
    IF _exist IS false THEN
        SELECT l.max_wind_speed INTO max_wind_speed FROM api.logbook l
        WHERE l.id = logbook_id AND l.max_wind_speed >= 15
          AND vessel_id = current_setting('vessel.id', false);
        IF max_wind_speed >= 15 THEN
            badge := '{"Wake Maker": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
            SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) INTO badge;
            PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
            user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
            SELECT user_settings::JSONB || '{"badge": "Wake Maker"}'::JSONB INTO user_settings;
            PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
        END IF;
    END IF;
 
    -- -----------------------------------------------------------------------
    -- Stormtrooper: max wind speed ≥ 30 kn
    -- -----------------------------------------------------------------------
    SELECT (preferences->'badges'->'Stormtrooper') IS NOT NULL INTO _exist
    FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
    IF _exist IS false THEN
        SELECT l.max_wind_speed INTO max_wind_speed FROM api.logbook l
        WHERE l.id = logbook_id AND l.max_wind_speed >= 30
          AND vessel_id = current_setting('vessel.id', false);
        IF max_wind_speed >= 30 THEN
            badge := '{"Stormtrooper": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
            SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) INTO badge;
            PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
            user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
            SELECT user_settings::JSONB || '{"badge": "Stormtrooper"}'::JSONB INTO user_settings;
            PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
        END IF;
    END IF;
 
    -- -----------------------------------------------------------------------
    -- Navigator Award: single leg distance ≥ 100 NM
    -- -----------------------------------------------------------------------
    SELECT (preferences->'badges'->'Navigator Award') IS NOT NULL INTO _exist
    FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
    IF _exist IS false THEN
        SELECT l.distance INTO distance FROM api.logbook l
        WHERE l.id = logbook_id AND l.distance >= 100
          AND vessel_id = current_setting('vessel.id', false);
        IF distance >= 100 THEN
            badge := '{"Navigator Award": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
            SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) INTO badge;
            PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
            user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
            SELECT user_settings::JSONB || '{"badge": "Navigator Award"}'::JSONB INTO user_settings;
            PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
        END IF;
    END IF;
 
    -- -----------------------------------------------------------------------
    -- Captain Award: cumulative distance ≥ 1000 NM
    -- -----------------------------------------------------------------------
    SELECT (preferences->'badges'->'Captain Award') IS NOT NULL INTO _exist
    FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
    IF _exist IS false THEN
        SELECT sum(l.distance) INTO distance FROM api.logbook l
        WHERE vessel_id = current_setting('vessel.id', false);
        IF distance >= 1000 THEN
            badge := '{"Captain Award": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
            SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) INTO badge;
            PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
            user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
            SELECT user_settings::JSONB || '{"badge": "Captain Award"}'::JSONB INTO user_settings;
            PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
        END IF;
    END IF;
 
    -- -----------------------------------------------------------------------
    -- NEW: Speed Demon — best rolling 24-hour distance record
    --
    --  Logic:
    --    1. Compute the current best 24h window including today's newly
    --       completed log (the function re-runs on ALL logs, so it is always
    --       up to date after this log's processing is committed).
    --    2. Compare against the previously stored badge distance (if any).
    --    3a. If no badge exists and new best ≥ 100 NM → award badge + notify.
    --    3b. If badge exists and new best > stored best → update badge + notify
    --        with a "new_record" notification variant so the UI can show a
    --        "🎉 You broke your own record!" toast.
    -- -----------------------------------------------------------------------
    -- Retrieve current best 24h result for this vessel
    SELECT b.best_distance_nm, b.anchor_log_id
    INTO   _new_best_nm, _new_best_log
    FROM   public.best_24h_distance_fn(current_setting('vessel.id', false)) b;
 
    IF _new_best_nm IS NOT NULL AND _new_best_nm >= 100 THEN
        -- Read current stored badge distance (0 if badge not yet awarded)
        SELECT COALESCE(
                   (preferences->'badges'->'Speed Demon'->>'distance_nm')::numeric,
                   0
               )
        INTO   _current_best_nm
        FROM   auth.accounts a
        WHERE  a.email = current_setting('user.email', false);
 
        -- Award or update when the new window beats the stored record
        IF _new_best_nm > _current_best_nm THEN
            badge := json_build_object(
                'Speed Demon', json_build_object(
                    'log',          _new_best_log,
                    'date',         logbook_time,
                    'distance_nm',  _new_best_nm
                )
            )::text;
 
            SELECT preferences->'badges' INTO _badges
            FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            SELECT public.jsonb_recursive_merge(_badges::jsonb, badge::jsonb) INTO badge;
            PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
 
            user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
 
            IF _current_best_nm = 0 THEN
                -- First-time award
                SELECT user_settings::JSONB || '{"badge": "Speed Demon"}'::JSONB INTO user_settings;
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            ELSE
                -- Record beaten — use a dedicated notification so the frontend
                -- can show "🎉 New 24h record: X NM (was Y NM)!"
                SELECT user_settings::JSONB
                    || json_build_object(
                           'badge',           'Speed Demon',
                           'new_distance_nm', _new_best_nm,
                           'old_distance_nm', _current_best_nm,
                           'logbook_link', _new_best_log,
                           'badge_stats', format('🎉 New 24h record: %s NM (was %s NM)!', _new_best_nm, _current_best_nm)
                       )::JSONB
                INTO user_settings;
                PERFORM send_notification_fn('new_24h_record'::TEXT, user_settings::JSONB);
            END IF;
        END IF;
    END IF;

END;
$function$
;

COMMENT ON FUNCTION public.badges_logbook_fn(int4, text) IS 'Check for new logbook-based badges: Helmsman, Wake Maker, Stormtrooper,
Navigator Award, Captain Award, Speed Demon (best 24h rolling distance ≥ 100 NM,
updates badge each time user beats their own record).';

-- DROP FUNCTION public.send_email_py_fn(text, jsonb, jsonb);
-- Update public.send_email_py_fn, fix app settings, add monitor_rejected, add badge stats
CREATE OR REPLACE FUNCTION public.send_email_py_fn(email_type text, _user jsonb, app jsonb)
 RETURNS void
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
AS $function$
    # Import smtplib for the actual sending function
    import smtplib
    import requests

    # Import the email modules we need
    from email.message import EmailMessage
    from email.utils import formatdate,make_msgid
    from email.mime.text import MIMEText

    # url
    from urllib.parse import urljoin

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

    def clean_url(base, path):
        base = base.rstrip('/') + '/'
        path = '/' + '/'.join(filter(None, path.split('/')))
        return urljoin(base, path)

    if 'logbook_name' in _user and _user['logbook_name']:
        email_content = email_content.replace('__LOGBOOK_NAME__', str(_user['logbook_name']))
    if 'logbook_link' in _user and _user['logbook_link']:
        email_content = email_content.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'logbook_stats' in _user and _user['logbook_stats']:
        email_content = email_content.replace('__LOGBOOK_STATS__', str(_user['logbook_stats']))
    if 'video_link' in _user and _user['video_link'] and 'app.videos_url' in app and app['app.videos_url']:
        email_content = email_content.replace('__VIDEO_LINK__', clean_url(app['app.videos_url'], str(_user['video_link'])))
    if 'recipient' in _user and _user['recipient']:
        email_content = email_content.replace('__RECIPIENT__', _user['recipient'])
    if 'boat' in _user and _user['boat']:
        email_content = email_content.replace('__BOAT__', _user['boat'])
    if 'badge' in _user and _user['badge']:
        email_content = email_content.replace('__BADGE_NAME__', _user['badge'])
    if 'badge_stats' in _user and _user['badge_stats']:
        email_content = email_content.replace('__BADGE_STATS__', str(_user['badge_stats']))
    if 'otp_code' in _user and _user['otp_code']:
        email_content = email_content.replace('__OTP_CODE__', _user['otp_code'])
    if 'reset_qs' in _user and _user['reset_qs']:
        email_content = email_content.replace('__RESET_QS__', _user['reset_qs'])
    if 'alert' in _user and _user['alert']:
        email_content = email_content.replace('__ALERT__', _user['alert'])
    if 'rejection_reason' in _user and _user['rejection_reason']:
        email_content = email_content.replace('__REJECTION_REASON__', str(_user['rejection_reason']))
    if 'rejection_count' in _user and _user['rejection_count']:
        email_content = email_content.replace('__REJECTION_COUNT__', str(_user['rejection_count']))

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

    if email_type == 'logbook' and 'logbook_img' in _user and _user['logbook_img'] and 'app.gis_url' in app and app['app.gis_url']:
        # Create a Content-ID for the image
        image_cid = make_msgid()
        # Transform HTML template
        logbook_link = '{__APP_URL__}/log/{__LOGBOOK_LINK__}'.format( __APP_URL__=app['app.url'], __LOGBOOK_LINK__=str(_user['logbook_link']))
        timelapse_link = '{__APP_URL__}/timelapse/{__LOGBOOK_LINK__}'.format( __APP_URL__=app['app.url'], __LOGBOOK_LINK__=str(_user['logbook_link']))
        email_content = email_content.replace('\n', '<br/>')
        email_content = email_content.replace(logbook_link, '<a href="{logbook_link}">{logbook_link}</a>'.format(logbook_link=str(logbook_link)))
        email_content = email_content.replace(timelapse_link, '<a href="{timelapse_link}">{timelapse_link}</a>'.format(timelapse_link=str(timelapse_link)))
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
        # sendMessage via requests
        headers = { 'User-Agent': 'PostgSail', 'From': 'postgsail@localhost'}
        if 'ua' in _user and _user['ua']:
            headers["User-Agent"] = _user['ua']
            headers["From"] = _user['app.email_from']
        img_url = '{}'.format(clean_url(app['app.gis_url'], str(_user['logbook_img'])))
        response = requests.get(img_url, headers=headers, stream=True, timeout=(5, 60))
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
$function$
;

COMMENT ON FUNCTION public.send_email_py_fn(text, jsonb, jsonb) IS 'Send email notification using plpython3u';


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
REVOKE SELECT ON public.app_settings FROM bot_role;

-- +goose StatementEnd
