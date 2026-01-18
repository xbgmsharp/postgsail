---------------------------------------------------------------------------
-- Copyright 2021-2025 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration November 2025
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- DROP FUNCTION IF EXISTS public.cron_windy_fn;
-- Update public.cron_windy_fn, to use Windy Stations API v2
CREATE OR REPLACE FUNCTION public.cron_windy_fn()
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    windy_rec RECORD;
    default_last_metric TIMESTAMPTZ := NOW() - INTERVAL '1 day';
    last_metric TIMESTAMPTZ := NOW();
    metric_rec RECORD;
    windy_metric JSONB;
    app_settings JSONB;
    user_settings JSONB;
    windy_pws JSONB;
    error_message TEXT;
BEGIN
    RAISE NOTICE 'cron_process_windy_fn: Starting Windy data upload process.';

    -- Fetch app settings
    app_settings := get_app_settings_fn();
    RAISE NOTICE '-> cron_process_windy_fn: app settings: %', app_settings;

    -- Iterate over users with Windy enabled
    FOR windy_rec IN
        SELECT
            a.id,
            a.email,
            v.vessel_id,
            v.name,
            COALESCE((a.preferences->'windy_last_metric')::TEXT, default_last_metric::TEXT) AS last_metric
        FROM auth.accounts a
        LEFT JOIN auth.vessels v ON v.owner_email = a.email
        LEFT JOIN api.metadata m ON m.vessel_id = v.vessel_id
        WHERE (a.preferences->'public_windy')::BOOLEAN = TRUE
        AND m.active = TRUE
        ORDER BY COALESCE((a.preferences->>'windy_last_metric')::TIMESTAMP, default_last_metric::TIMESTAMP) ASC
    LOOP
        RAISE NOTICE '-> cron_process_windy_fn: Processing vessel: [%]', windy_rec.name;

        -- Set vessel context
        PERFORM set_config('vessel.id', windy_rec.vessel_id, FALSE);

        -- Fetch user settings
        user_settings := get_user_settings_from_vesselid_fn(windy_rec.vessel_id::TEXT);
        RAISE NOTICE '-> cron_process_windy_fn: windy_rec: [%]', windy_rec;
        RAISE NOTICE '-> cron_process_windy_fn: checking user_settings [%]', user_settings;

        -- Fetch 5-minute aggregated metrics
        FOR metric_rec IN
            SELECT
                time_bucket('5 minutes', mt.time) AS time_bucket,
                AVG(COALESCE(
                    (mt.metrics->'temperature'->>'outside')::FLOAT,
                    (mt.metrics->>(md.configuration->>'outsideTemperatureKey'))::FLOAT,
                    (mt.metrics->>'environment.outside.temperature')::FLOAT
                )) AS temperature,
                AVG(COALESCE(
                    (mt.metrics->'pressure'->>'outside')::FLOAT,
                    (mt.metrics->>(md.configuration->>'outsidePressureKey'))::FLOAT,
                    (mt.metrics->>'environment.outside.pressure')::FLOAT
                )) AS pressure,
                AVG(COALESCE(
                    (mt.metrics->'humidity'->>'outside')::FLOAT,
                    (mt.metrics->>(md.configuration->>'outsideHumidityKey'))::FLOAT,
                    (mt.metrics->>'environment.outside.relativeHumidity')::FLOAT,
                    (mt.metrics->>'environment.outside.humidity')::FLOAT
                )) AS rh,
                AVG(COALESCE(
                    (mt.metrics->'wind'->>'direction')::FLOAT,
                    (mt.metrics->>(md.configuration->>'windDirectionKey'))::FLOAT,
                    (mt.metrics->>'environment.wind.directionTrue')::FLOAT
                )) AS winddir,
                AVG(COALESCE(
                    (mt.metrics->'wind'->>'speed')::FLOAT,
                    (mt.metrics->>(md.configuration->>'windSpeedKey'))::FLOAT,
                    (mt.metrics->>'environment.wind.speedTrue')::FLOAT,
                    (mt.metrics->>'environment.wind.speedApparent')::FLOAT
                )) AS wind,
                MAX(COALESCE(
                    (mt.metrics->'wind'->>'speed')::FLOAT,
                    (mt.metrics->>(md.configuration->>'windSpeedKey'))::FLOAT,
                    (mt.metrics->>'environment.wind.speedTrue')::FLOAT,
                    (mt.metrics->>'environment.wind.speedApparent')::FLOAT
                )) AS gust,
                LAST(latitude, mt.time) AS lat,
                LAST(longitude, mt.time) AS lng
            FROM api.metrics mt
            JOIN api.metadata md ON md.vessel_id = mt.vessel_id
            WHERE md.vessel_id = windy_rec.vessel_id
              AND mt.time >= windy_rec.last_metric::TIMESTAMPTZ
            GROUP BY time_bucket
            ORDER BY time_bucket ASC
            LIMIT 100
        LOOP
            RAISE NOTICE '-> cron_process_windy_fn: metric_rec: [%]', metric_rec;
            -- Skip invalid metrics
            IF metric_rec.temperature IS NULL
               OR metric_rec.pressure IS NULL
               OR metric_rec.rh IS NULL
               OR metric_rec.wind IS NULL
               OR metric_rec.winddir IS NULL
               OR metric_rec.time_bucket < NOW() - INTERVAL '2 days' THEN
                CONTINUE;
            END IF;

            -- Build Windy metric payload
            windy_metric := jsonb_build_object(
                'dateutc', metric_rec.time_bucket,
                'station', user_settings['settings']['windy'],
                'name', windy_rec.name,
                'lat', metric_rec.lat,
                'lon', metric_rec.lng,
                'temp', public.kelvintocel(metric_rec.temperature::NUMERIC),
                'wind', metric_rec.wind,
                'gust', metric_rec.gust,
                'winddir', metric_rec.winddir::NUMERIC,
                'pressure', metric_rec.pressure,
                'rh', public.valToPercent(metric_rec.rh::NUMERIC)
            );

            RAISE NOTICE '-> cron_process_windy_fn: Sending metric at % to Windy: %', metric_rec.time_bucket, windy_metric;
            BEGIN
                -- Send to Windy
                windy_pws := public.windy_pws_py_fn(windy_metric, user_settings, app_settings);

                IF windy_pws ? 'password' THEN
                    -- Save Station ID
                    PERFORM api.update_user_preferences_fn(
                            '{windy}'::TEXT,
                            windy_pws->>'id'::TEXT);
                    -- Save Station password token
                    PERFORM api.update_user_preferences_fn(
                            '{windy_password_station}'::TEXT,
                            windy_pws->>'password'::TEXT);
                    -- Send notification
                    PERFORM send_notification_fn('windy'::TEXT, user_settings::JSONB);
                ELSIF windy_pws ? 'status' THEN
                    PERFORM api.update_user_preferences_fn(
                            '{windy_last_metric}'::TEXT,
                            metric_rec.time_bucket::TEXT);
                END IF;

                -- Update last_metric time
                last_metric := metric_rec.time_bucket;
                -- Windy is rate limiting the requests
                PERFORM pg_sleep(1);

            EXCEPTION WHEN OTHERS THEN
                error_message := 'Error processing vessel ' || windy_rec.name || ': ' || SQLERRM;
                RAISE NOTICE '%', error_message;
            END;
        END LOOP;

        -- Update last metric time in user preferences
        PERFORM api.update_user_preferences_fn(
            '{windy_last_metric}'::TEXT,
            last_metric::TEXT
        );
        -- Windy is rate limiting the requests
        PERFORM pg_sleep(2);
    END LOOP;

    RAISE NOTICE '-> cron_process_windy_fn: Windy data upload process completed.';
END;
$function$;
-- Description
COMMENT ON FUNCTION public.cron_windy_fn() IS 'init by pg_cron to create (or update) station and uploading observations to Windy Personal Weather Station observations';

-- DROP FUNCTION IF EXISTS public.windy_pws_py_fn;
-- Update windy_pws_py_fn to use Windy Stations API v2
CREATE OR REPLACE FUNCTION public.windy_pws_py_fn(metric jsonb, _user jsonb, app jsonb)
RETURNS jsonb
TRANSFORM FOR TYPE jsonb
LANGUAGE plpython3u
STRICT
AS $function$
    """
    Send environment data from boat instruments to Windy as a Personal Weather Station (PWS).
    Supports station creation and observation updates using Windy Stations API v2.
    Uses API key for authentication and supports historical data via dateutc.
    """
    import requests
    import json
    import decimal
    from datetime import datetime, timedelta

    # Validate inputs
    if not 'app.windy_apikey' in app or not app['app.windy_apikey']:
        plpy.error('Error: No Windy API key defined. Check app settings.')
        return None

    if not 'station' in metric or not metric['station']:
        plpy.error('Error: No station ID defined in metrics.')
        return None

    if not _user:
        plpy.error('Error: No user defined. Check user settings.')
        return None

    # Check if station exists in user settings
    station_exists = 'settings' in _user and 'windy' in _user['settings'] and 'windy_password_station' in _user['settings']

    if not station_exists:
        # Create station using API key
        station_data = {
            "name": metric['name'],
            "share_option": "public",
            "lat": float(decimal.Decimal(metric['lat'])),
            "lon": float(decimal.Decimal(metric['lon'])),
            "elev_m": 1,
            "agl_wind": 10,
            "station_type": "SignalK PostgSail Plugin",
            "operator_text": f"Maintained by {metric['name']} via PostgSail",
            "operator_url": f"https://iot.openplotter.cloud/{metric['name']}/monitoring"
        }
        plpy.notice(f'Windy Personal Weather Station create station: {station_data}')
        headers = {
            'User-Agent': 'PostgSail',
            'From': 'xbgmsharp@gmail.com',
            'windy-api-key': app['app.windy_apikey'],
            'Content-Type': 'application/json'
        }

        api_url = 'https://stations.windy.com/api/v2/pws'

        try:
            r = requests.post(api_url, json=station_data, headers=headers, timeout=(5, 60))
            if r.status_code == 200:
                plpy.notice(f'Windy Personal Weather Station created successfully: {r.text}')
                return r.json()
            else:
                plpy.error(f'Failed to create station. Status code: {r.status_code}, Response: {r.text}')
                return None
        except Exception as e:
            plpy.error(f'Error creating station: {str(e)}')
            return None
    else:
        # Send observation update using API key
        params = {
            'id': metric['station'],
            'time': metric['dateutc'],
            'softwaretype': 'PostgSail',
        }

        # Add observation parameters
        if 'temp' in metric and metric['temp']:
            params['temp'] = float(decimal.Decimal(metric['temp']))

        if 'wind' in metric and metric['wind']:
            params['wind'] = round(float(decimal.Decimal(metric['wind'])), 1)

        if 'gust' in metric and metric['gust']:
            params['gust'] = round(float(decimal.Decimal(metric['gust'])), 1)

        if 'winddir' in metric and metric['winddir']:
            params['winddir'] = int(decimal.Decimal(metric['winddir']))

        if 'pressure' in metric and metric['pressure']:
            params['pressure'] = int(decimal.Decimal(metric['pressure']))

        if 'rh' in metric and metric['rh']:
            params['humidity'] = float(decimal.Decimal(metric['rh']))

        params['softwaretype'] = f"Vessel {metric['name']} via PostgSail"
        plpy.notice(f'Windy Personal Weather Station update observation: {params}')

        headers = {
            'User-Agent': 'PostgSail',
            'From': 'xbgmsharp@gmail.com',
            'Authorization': f"Bearer {_user['settings']['windy_password_station']}"
        }

        api_url = 'https://stations.windy.com/api/v2/observation/update'

        try:
            r = requests.get(api_url, params=params, headers=headers, timeout=(5, 60))
            if r.status_code == 200:
                plpy.notice(f'Data sent successfully to Windy')
                return json.dumps({
                    'status': 'success',
                    'last_sent': metric['dateutc']
                })
            else:
                plpy.error(f'Failed to send data. Status code: {r.status_code}, Response: {r.text}')
                return None
        except Exception as e:
            plpy.error(f'Error sending data to Windy: {str(e)}')
            return None
$function$;
-- Description
COMMENT ON FUNCTION public.windy_pws_py_fn(jsonb, jsonb, jsonb) IS 'Forward vessel data to Windy as a Personal Weather Station using plpython3u';

DROP FUNCTION IF EXISTS public.split_logbook_by24h_fn;
-- Update split_logbook_by24h_fn to split logbook into 24h segments
CREATE OR REPLACE FUNCTION public.split_logbook_by24h_fn(_id integer)
RETURNS TABLE (
    id integer,
    name text,
    segment_num integer,
    period_start timestamptz,
    period_end timestamptz,
    duration interval,
    distance numeric(10,2),
    avg_speed numeric(6,2),
    max_speed numeric(6,2),
    avg_tws numeric(6,2),
    max_tws numeric(6,2),
    avg_aws numeric(6,2),
    max_aws numeric(6,2),
    trajectory geometry,
    geojson jsonb
)
LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE time_splits AS (
        SELECT
            l.id,
            l.trip,
            l.trip_tws,
            l.trip_twd,
            l.trip_aws,
            startTimestamp(l.trip) AS period_start,
            LEAST(startTimestamp(l.trip) + interval '24 hours', endTimestamp(l.trip)) AS period_end,
            0 AS segment_num
        FROM api.logbook l
        WHERE l.id = _id

        UNION ALL

        SELECT
            ts.id,
            ts.trip,
            ts.trip_tws,
            ts.trip_twd,
            ts.trip_aws,
            ts.period_end,
            LEAST(ts.period_end + interval '24 hours', endTimestamp(ts.trip)),
            ts.segment_num + 1
        FROM time_splits ts
        WHERE ts.period_end < endTimestamp(ts.trip)
    ),
    segmented_trajectories AS (
        SELECT
            l.id,
            l.name,
            ts.segment_num,
            ts.period_start,
            ts.period_end,
            atTime(l.trip, span(ts.period_start, ts.period_end, true, true)) AS segment_trip,
            atTime(l.trip_tws, span(ts.period_start, ts.period_end, true, true)) AS segment_tws,
            atTime(l.trip_twd, span(ts.period_start, ts.period_end, true, true)) AS segment_twd,
            atTime(l.trip_aws, span(ts.period_start, ts.period_end, true, true)) AS segment_aws
        FROM time_splits ts
        JOIN api.logbook l ON l.id = ts.id
    )
    SELECT
        st.id,
        st.name,
        st.segment_num,
        st.period_start,
        st.period_end,
        (st.period_end - st.period_start) AS duration,
        (length(st.segment_trip) / 1852)::numeric(10,2) AS distance,
        (twavg(speed(st.segment_trip)) * 1.94384)::numeric(6,2) AS avg_speed,
        (maxValue(speed(st.segment_trip)) * 1.94384)::numeric(6,2) AS max_speed,
        twavg(st.segment_tws)::numeric(6,2) AS avg_tws,
        maxValue(st.segment_tws)::numeric(6,2) AS max_tws,
        twavg(st.segment_aws)::numeric(6,2) AS avg_aws,
        maxValue(st.segment_aws)::numeric(6,2) AS max_aws,
        trajectory(st.segment_trip)::geometry,
        ST_AsGeoJSON(trajectory(st.segment_trip))::jsonb
    FROM segmented_trajectories st
    WHERE st.segment_trip IS NOT NULL;
END;
$function$;
-- Description
COMMENT ON FUNCTION public.split_logbook_by24h_fn(int4) IS 'Split a logbook trip into multiple segments of maximum 24 hours each';

DROP FUNCTION public.split_logbook_by24h_geojson_fn;
-- Update split_logbook_by24h_geojson_fn to split logbook into 24h segments and return GeoJSON FeatureCollection
CREATE OR REPLACE FUNCTION public.split_logbook_by24h_geojson_fn(_id integer)
 RETURNS JSONB
 LANGUAGE plpgsql
AS $function$
BEGIN
	RETURN (
    WITH RECURSIVE time_splits AS (
        SELECT
            l.id,
            l.trip,
            l.trip_tws,
            l.trip_aws,
            startTimestamp(l.trip) AS period_start,
            LEAST(startTimestamp(l.trip) + interval '24 hours', endTimestamp(l.trip)) AS period_end,
            0 AS segment_num
        FROM api.logbook l
        WHERE l.id = _id

        UNION ALL

        SELECT
            id,
            trip,
            trip_tws,
            trip_aws,
            period_end,
            LEAST(period_end + interval '24 hours', endTimestamp(trip)),
            segment_num + 1
        FROM time_splits
        WHERE period_end < endTimestamp(trip)
    ),
    segmented_trajectories AS (
        SELECT
            l.id,
            l.name,
            ts.segment_num,
            ts.period_start,
            ts.period_end,
            atTime(l.trip, span(ts.period_start, ts.period_end, true, true)) AS segment_trip,
            atTime(l.trip_tws, span(ts.period_start, ts.period_end, true, true)) AS segment_tws,
            atTime(l.trip_aws, span(ts.period_start, ts.period_end, true, true)) AS segment_aws
        FROM time_splits ts
        JOIN api.logbook l ON l.id = ts.id
    ),
    segment_stats AS (
        SELECT
            id,
            name,
            segment_num,
            period_start,
            period_end,
            (period_end - period_start) AS duration,
            (length(segment_trip)/1852)::NUMERIC(10,2) AS distance,
            (twavg(speed(segment_trip)) * 1.94384)::NUMERIC(6,2) AS avg_speed,
            (maxValue(speed(segment_trip)) * 1.94384)::NUMERIC(6,2) AS max_speed,
            -- True Wind Speed stats (already in knots)
            twavg(segment_tws)::NUMERIC(6,2) AS avg_tws,
            maxValue(segment_tws)::NUMERIC(6,2) AS max_tws,
            -- Apparent Wind Speed stats (already in knots)
            twavg(segment_aws)::NUMERIC(6,2) AS avg_aws,
            maxValue(segment_aws)::NUMERIC(6,2) AS max_aws,
            ST_AsGeoJSON(trajectory(segment_trip))::jsonb AS geojson
        FROM segmented_trajectories
        WHERE segment_trip IS NOT NULL
    )
    SELECT
        jsonb_build_object(
            'type', 'FeatureCollection',
            'features', jsonb_agg(
                jsonb_build_object(
                    'type', 'Feature',
                    'properties', jsonb_build_object(
                        'id', id,
                        'name', name,
                        'segment_num', segment_num,
                        'period_start', period_start,
                        'period_end', period_end,
                        'duration', duration,
                        'distance', distance,
                        'avg_speed', avg_speed,
                        'max_speed', max_speed,
                        'avg_tws', avg_tws,
                        'max_tws', max_tws,
                        'avg_aws', avg_aws,
                        'max_aws', max_aws
                    ),
                    'geometry', geojson
                ) ORDER BY segment_num
            )
        ) AS geojson_output
    FROM segment_stats
	);
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.split_logbook_by24h_geojson_fn(int4) IS 'Split a logbook trip into multiple segments of maximum 24 hours each, return a GeoJSON FeatureCollection';

-- DROP FUNCTION api.export_logbook_geojson_trip_fn(int4);
-- Update export_logbook_geojson_trip_fn to include logbook split into 24h segments
CREATE OR REPLACE FUNCTION api.export_logbook_geojson_trip_fn(_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    logbook_rec RECORD;
    log_geojson JSONB;
    log_legs_geojson JSONB := '{}'::JSONB;
    metrics_geojson JSONB;
    first_feature_obj JSONB;
    second_feature_note JSONB;
    last_feature_note JSONB;
BEGIN
    -- Validate input
    IF _id IS NULL OR _id < 1 THEN
        RAISE WARNING '-> export_logbook_geojson_trip_fn invalid input %', _id;
        RETURN NULL;
    END IF;

    -- Fetch the processed logbook data.
    SELECT id, name, distance, duration, avg_speed, max_speed, max_wind_speed, extra->>'avg_wind_speed' AS avg_wind_speed,
           _from, _to, _from_time, _to_time, _from_moorage_id, _to_moorage_id, notes,
           trajectory(trip) AS trajectory,
           timestamps(trip) AS times
    INTO logbook_rec
    FROM api.logbook
    WHERE id = _id;

    -- Create JSON notes for feature properties
    first_feature_obj := jsonb_build_object('trip', jsonb_build_object('name', logbook_rec.name, 'duration', logbook_rec.duration, 'distance', logbook_rec.distance));
    second_feature_note := jsonb_build_object('notes', COALESCE(logbook_rec._from, ''));
    last_feature_note := jsonb_build_object('notes', COALESCE(logbook_rec._to, ''));

    -- GeoJSON Feature for Logbook linestring
    SELECT ST_AsGeoJSON(logbook_rec.*)::jsonb INTO log_geojson;
	-- GeoJSON Feature Logbook split log into 24h linestring if larger than 24h
    IF logbook_rec.duration > interval '24 hours' THEN
        log_legs_geojson := public.split_logbook_by24h_geojson_fn(logbook_rec.id);
    END IF;

    -- GeoJSON Features for Metrics Points
    SELECT jsonb_agg(ST_AsGeoJSON(t.*)::jsonb) INTO metrics_geojson
    FROM ( -- Extract points from trip and their corresponding metrics
        SELECT
            geometry(getvalue(points.point)) AS point_geometry,
            getTimestamp(points.point) AS time,
            valueAtTimestamp(points.trip_cog, getTimestamp(points.point)) AS courseovergroundtrue,
            valueAtTimestamp(points.trip_sog, getTimestamp(points.point)) AS speedoverground,
            valueAtTimestamp(points.trip_aws, getTimestamp(points.point)) AS windspeedapparent,
            valueAtTimestamp(points.trip_awa, getTimestamp(points.point)) AS windangleapparent,
            valueAtTimestamp(points.trip_tws, getTimestamp(points.point)) AS truewindspeed,
            valueAtTimestamp(points.trip_twd, getTimestamp(points.point)) AS truewinddirection,
            valueAtTimestamp(points.trip_notes, getTimestamp(points.point)) AS notes,
            valueAtTimestamp(points.trip_status, getTimestamp(points.point)) AS status,
            valueAtTimestamp(points.trip_depth, getTimestamp(points.point)) AS depth,
            valueAtTimestamp(points.trip_batt_charge, getTimestamp(points.point)) AS stateofcharge,
            valueAtTimestamp(points.trip_batt_voltage, getTimestamp(points.point)) AS voltage,
            valueAtTimestamp(points.trip_temp_water, getTimestamp(points.point)) AS watertemperature,
            valueAtTimestamp(points.trip_temp_out, getTimestamp(points.point)) AS outsidetemperature,
            valueAtTimestamp(points.trip_pres_out, getTimestamp(points.point)) AS outsidepressure,
            valueAtTimestamp(points.trip_hum_out, getTimestamp(points.point)) AS outsidehumidity,
            valueAtTimestamp(points.trip_solar_voltage, getTimestamp(points.point)) AS solarvoltage,
            valueAtTimestamp(points.trip_solar_power, getTimestamp(points.point)) AS solarpower,
            valueAtTimestamp(points.trip_tank_level, getTimestamp(points.point)) AS tanklevel,
            valueAtTimestamp(points.trip_heading, getTimestamp(points.point)) AS heading
        FROM (
            SELECT unnest(instants(trip)) AS point,
                    trip_cog,
                    trip_sog,
                    trip_aws,
                    trip_awa,
                    trip_tws,
                    trip_twd,
                    trip_notes,
                    trip_status,
                    trip_depth,
                    trip_batt_charge,
                    trip_batt_voltage,
                    trip_temp_water,
                    trip_temp_out,
                    trip_pres_out,
                    trip_hum_out,
                    trip_solar_voltage,
                    trip_solar_power,
                    trip_tank_level,
                    trip_heading
            FROM api.logbook
            WHERE id = _id
                AND trip IS NOT NULL
        ) AS points
    ) AS t;

    -- Update the properties of the first feature
    metrics_geojson := jsonb_set(
        metrics_geojson,
        '{0, properties}',
        (metrics_geojson->0->'properties' || first_feature_obj)::jsonb,
        true
    );
    -- Update the properties of the third feature
    metrics_geojson := jsonb_set(
        metrics_geojson,
        '{1, properties}',
        CASE
            WHEN (metrics_geojson->1->'properties'->>'notes') = '' THEN
                (metrics_geojson->1->'properties' || second_feature_note)::jsonb
            ELSE
                metrics_geojson->1->'properties'
        END,
        true
    );
    -- Update the properties of the last feature
    metrics_geojson := jsonb_set(
        metrics_geojson,
        '{-1, properties}',
        CASE
            WHEN (metrics_geojson->-1->'properties'->>'notes') = '' THEN
                (metrics_geojson->-1->'properties' || last_feature_note)::jsonb
            ELSE
                metrics_geojson->-1->'properties'
        END,
        true
    );

    -- Combine Logbook and Metrics GeoJSON and the log legs FeatureCollection
    RETURN jsonb_build_object('type', 'FeatureCollection', 'features', log_geojson || COALESCE(metrics_geojson, '[]'::jsonb) || COALESCE(log_legs_geojson->'features', '[]'::jsonb));

END;
$function$
;
-- Description
COMMENT ON FUNCTION api.export_logbook_geojson_trip_fn(int4) IS 'Export a log trip entry to GEOJSON format with custom properties for timelapse replay';
