---------------------------------------------------------------------------
-- Copyright 2021-2024 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration March 2024
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Force timezone, just in case'
set timezone to 'UTC';

CREATE OR REPLACE FUNCTION public.process_lat_lon_fn(IN lon NUMERIC, IN lat NUMERIC,
    OUT moorage_id INTEGER,
    OUT moorage_type INTEGER,
    OUT moorage_name TEXT,
    OUT moorage_country TEXT
) AS $process_lat_lon$
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
                    coalesce(moorage_name, null),
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
$process_lat_lon$ LANGUAGE plpgsql;

CREATE or replace FUNCTION public.logbook_update_geojson_fn(IN _id integer, IN _start text, IN _end text,
    OUT _track_geojson JSON
 ) AS $logbook_geojson$
    declare
     log_geojson jsonb;
     metrics_geojson jsonb;
     _map jsonb;
    begin
        -- GeoJson Feature Logbook linestring
        SELECT
            ST_AsGeoJSON(log.*) into log_geojson
        FROM
           ( SELECT
                id,name,
                distance,
                duration,
                avg_speed,
                max_speed,
                max_wind_speed,
                _from_time,
                _to_time
                _from_moorage_id,
                _to_moorage_id,
                notes,
                track_geom
                FROM api.logbook
                WHERE id = _id
           ) AS log;
        -- GeoJson Feature Metrics point
        SELECT
            json_agg(ST_AsGeoJSON(t.*)::json) into metrics_geojson
        FROM (
            ( SELECT
                time,
                courseovergroundtrue,
                speedoverground,
                windspeedapparent,
                longitude,latitude,
                '' AS notes,
                coalesce(metersToKnots((metrics->'environment.wind.speedTrue')::NUMERIC), null) as truewindspeed,
                coalesce(radiantToDegrees((metrics->'environment.wind.directionTrue')::NUMERIC), null) as truewinddirection,
                coalesce(status, null) as status,
                st_makepoint(longitude,latitude) AS geo_point
                FROM api.metrics m
                WHERE m.latitude IS NOT NULL
                    AND m.longitude IS NOT NULL
                    AND time >= _start::TIMESTAMPTZ
                    AND time <= _end::TIMESTAMPTZ
                    AND vessel_id = current_setting('vessel.id', false)
                ORDER BY m.time ASC
            )
        ) AS t;

        -- Merge jsonb
        SELECT log_geojson::jsonb || metrics_geojson::jsonb into _map;
        -- output
        SELECT
            json_build_object(
                'type', 'FeatureCollection',
                'features', _map
            ) into _track_geojson;
    END;
$logbook_geojson$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.metersToKnots(IN meters NUMERIC)
RETURNS NUMERIC
AS $$
BEGIN
    RETURN ROUND(((meters * 1.9438445) * 10) / 10, 2);
END
$$
LANGUAGE plpgsql IMMUTABLE;
-- Description
COMMENT ON FUNCTION
    public.metersToKnots
    IS 'convert speed meters/s To Knots';

CREATE OR REPLACE FUNCTION logbook_update_extra_json_fn(IN _id integer, IN _start text, IN _end text,
    OUT _extra_json JSON
    ) AS $logbook_extra_json$
    declare
        obs_json jsonb default '{ "seaState": -1, "cloudCoverage": -1, "visibility": -1}'::jsonb;
        log_json jsonb default '{}'::jsonb;
        runtime_json jsonb default '{}'::jsonb;
        metrics_json jsonb default '{}'::jsonb;
        metric_rec record;
    BEGIN
        -- Calculate 'navigation.log' metrics
        WITH
            start_trip as (
                -- Fetch 'navigation.log' start, first entry
                SELECT key, value
                FROM api.metrics m,
                        jsonb_each_text(m.metrics)
                WHERE key ILIKE 'navigation.log'
                    AND time = _start::TIMESTAMPTZ
                    AND vessel_id = current_setting('vessel.id', false)
            ),
            end_trip as (
                -- Fetch 'navigation.log' end, last entry
                SELECT key, value
                FROM api.metrics m,
                        jsonb_each_text(m.metrics)
                WHERE key ILIKE 'navigation.log'
                    AND time = _end::TIMESTAMPTZ
                    AND vessel_id = current_setting('vessel.id', false)
            ),
            nm as (
                -- calculate distance and convert meter to nautical miles
                SELECT ((end_trip.value::NUMERIC - start_trip.value::numeric) * 0.00053996) as trip from start_trip,end_trip
            )
        -- Generate JSON
        SELECT jsonb_build_object('navigation.log', trip) INTO log_json FROM nm;
        RAISE NOTICE '-> logbook_update_extra_json_fn navigation.log: %', log_json;

        -- Calculate engine hours from propulsion.%.runTime first entry
        FOR metric_rec IN
            SELECT key, value
                FROM api.metrics m,
                        jsonb_each_text(m.metrics)
                WHERE key ILIKE 'propulsion.%.runTime'
                    AND time = _start::TIMESTAMPTZ
                    AND vessel_id = current_setting('vessel.id', false)
        LOOP
            -- Engine Hours in seconds
            RAISE NOTICE '-> logbook_update_extra_json_fn propulsion.*.runTime: %', metric_rec;
            with
            end_runtime AS (
                -- Fetch 'propulsion.*.runTime' last entry
                SELECT key, value
                    FROM api.metrics m,
                            jsonb_each_text(m.metrics)
                    WHERE key ILIKE metric_rec.key
                        AND time = _end::TIMESTAMPTZ
                        AND vessel_id = current_setting('vessel.id', false)
            ),
            runtime AS (
                -- calculate runTime Engine Hours as ISO duration
                --SELECT (end_runtime.value::numeric - metric_rec.value::numeric) AS value FROM end_runtime
                SELECT (((end_runtime.value::numeric - metric_rec.value::numeric) / 3600) * '1 hour'::interval)::interval as value FROM end_runtime
            )
            -- Generate JSON
            SELECT jsonb_build_object(metric_rec.key, runtime.value) INTO runtime_json FROM runtime;
            RAISE NOTICE '-> logbook_update_extra_json_fn key: %, value: %', metric_rec.key, runtime_json;
        END LOOP;

        -- Update logbook with extra value and return json
        SELECT COALESCE(log_json::JSONB, '{}'::jsonb) || COALESCE(runtime_json::JSONB, '{}'::jsonb) INTO metrics_json;
        SELECT jsonb_build_object('metrics', metrics_json, 'observations', obs_json) INTO _extra_json;
        RAISE NOTICE '-> logbook_update_extra_json_fn log_json: %, runtime_json: %, _extra_json: %', log_json, runtime_json, _extra_json;
    END;
$logbook_extra_json$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS public.logbook_update_gpx_fn();

CREATE OR REPLACE FUNCTION metadata_upsert_trigger_fn() RETURNS trigger AS $metadata_upsert$
    DECLARE
        metadata_id integer;
        metadata_active boolean;
    BEGIN
        -- Set client_id to new value to allow RLS
        --PERFORM set_config('vessel.client_id', NEW.client_id, false);
        -- UPSERT - Insert vs Update for Metadata
        --RAISE NOTICE 'metadata_upsert_trigger_fn';
        --PERFORM set_config('vessel.id', NEW.vessel_id, true);
        --RAISE WARNING 'metadata_upsert_trigger_fn [%] [%]', current_setting('vessel.id', true), NEW;
        SELECT m.id,m.active INTO metadata_id, metadata_active
            FROM api.metadata m
            WHERE m.vessel_id IS NOT NULL AND m.vessel_id = current_setting('vessel.id', true);
        --RAISE NOTICE 'metadata_id is [%]', metadata_id;
        IF metadata_id IS NOT NULL THEN
            -- send notification if boat is back online
            IF metadata_active is False THEN
                -- Add monitor online entry to process queue for later notification
                INSERT INTO process_queue (channel, payload, stored, ref_id)
                    VALUES ('monitoring_online', metadata_id, now(), current_setting('vessel.id', true));
            END IF;
            -- Update vessel metadata
            UPDATE api.metadata
                SET
                    name = NEW.name,
                    mmsi = NEW.mmsi,
                    client_id = NEW.client_id,
                    length = NEW.length,
                    beam = NEW.beam,
                    height = NEW.height,
                    ship_type = NEW.ship_type,
                    plugin_version = NEW.plugin_version,
                    signalk_version = NEW.signalk_version,
                    platform = REGEXP_REPLACE(NEW.platform, '[^a-zA-Z0-9\(\) ]', '', 'g'),
                    configuration = NEW.configuration,
                    -- time = NEW.time, ignore the time sent by the vessel as it is out of sync sometimes.
                    time = NOW(), -- overwrite the time sent by the vessel
                    active = true
                WHERE id = metadata_id;
            RETURN NULL; -- Ignore insert
        ELSE
            IF NEW.vessel_id IS NULL THEN
                -- set vessel_id from jwt if not present in INSERT query
                NEW.vessel_id := current_setting('vessel.id');
            END IF;
            -- Ignore and overwrite the time sent by the vessel
            NEW.time := NOW();
            -- Insert new vessel metadata
            RETURN NEW; -- Insert new vessel metadata
        END IF;
    END;
$metadata_upsert$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.cron_windy_fn() RETURNS void AS $$
DECLARE
    windy_rec record;
    default_last_metric TIMESTAMPTZ := NOW() - interval '1 day';
    last_metric TIMESTAMPTZ := NOW();
    metric_rec record;
    windy_metric jsonb;
    app_settings jsonb;
    user_settings jsonb;
    windy_pws jsonb;
BEGIN
    -- Check for new observations pending update
    RAISE NOTICE 'cron_process_windy_fn';
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
        RAISE NOTICE '-> cron_process_windy_fn for [%]', windy_rec;
        PERFORM set_config('vessel.id', windy_rec.vessel_id, false);
        --RAISE WARNING 'public.cron_process_windy_rec_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(windy_rec.vessel_id::TEXT);
        RAISE NOTICE '-> cron_process_windy_fn checking user_settings [%]', user_settings;
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
            RAISE NOTICE '-> cron_process_windy_fn checking metrics [%]', metric_rec;
            IF metric_rec.wind is null or metric_rec.temperature is null THEN
                -- Ignore when there is no metrics.
                -- Send notification
                PERFORM send_notification_fn('windy_error'::TEXT, user_settings::JSONB);
                -- Disable windy
                PERFORM api.update_user_preferences_fn('{public_windy}'::TEXT, 'false'::TEXT);
                RETURN;
            END IF;
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
            RAISE NOTICE '-> cron_process_windy_fn checking windy_metrics [%]', windy_metric;
            SELECT windy_pws_py_fn(windy_metric, user_settings, app_settings) into windy_pws;
            RAISE NOTICE '-> cron_process_windy_fn Windy PWS [%]', ((windy_pws->'header')::JSONB ? 'id');
            IF NOT((user_settings->'settings')::JSONB ? 'windy') and ((windy_pws->'header')::JSONB ? 'id') then
                RAISE NOTICE '-> cron_process_windy_fn new Windy PWS [%]', (windy_pws->'header')::JSONB->>'id';
                -- Send metrics to Windy
                PERFORM api.update_user_preferences_fn('{windy}'::TEXT, ((windy_pws->'header')::JSONB->>'id')::TEXT);
                -- Send notification
                PERFORM send_notification_fn('windy'::TEXT, user_settings::JSONB);
                -- Refresh user settings after first success
                user_settings := get_user_settings_from_vesselid_fn(windy_rec.vessel_id::TEXT);
            END IF;
            -- Record last metrics time
            SELECT metric_rec.time_bucket INTO last_metric;
        END LOOP;
        PERFORM api.update_user_preferences_fn('{windy_last_metric}'::TEXT, last_metric::TEXT);
    END LOOP;
END;
$$ language plpgsql;

DROP FUNCTION public.delete_vessel_fn;
CREATE OR REPLACE FUNCTION public.delete_vessel_fn(IN _vessel_id TEXT) RETURNS JSONB
AS $delete_vessel$
DECLARE
  total_metrics INTEGER;
  del_metrics INTEGER;
  del_logs INTEGER;
  del_stays INTEGER;
  del_moorages INTEGER;
  del_queue INTEGER;
  out_json JSONB;
BEGIN
    select count(*) INTO total_metrics from api.metrics m where vessel_id = _vessel_id;
    WITH deleted AS (delete from api.metrics m where vessel_id = _vessel_id RETURNING *) SELECT count(*) INTO del_metrics FROM deleted;
    WITH deleted AS (delete from api.logbook l where vessel_id = _vessel_id RETURNING *) SELECT count(*) INTO del_logs FROM deleted;
    WITH deleted AS (delete from api.stays s where vessel_id = _vessel_id RETURNING *) SELECT count(*) INTO del_stays FROM deleted;
    WITH deleted AS (delete from api.moorages m where vessel_id = _vessel_id RETURNING *) SELECT count(*) INTO del_moorages FROM deleted;
    WITH deleted AS (delete from public.process_queue m where ref_id = _vessel_id RETURNING *) SELECT count(*) INTO del_queue FROM deleted;
    SELECT jsonb_build_object('total_metrics', total_metrics,
                            'del_metrics', del_metrics,
                            'del_logs', del_logs,
                            'del_stays', del_stays,
                            'del_moorages', del_moorages,
                            'del_queue', del_queue) INTO out_json;
    RETURN out_json;
END
$delete_vessel$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.delete_vessel_fn
    IS 'Delete all vessel data (metrics,logbook,stays,moorages,process_queue) for a vessel_id';

DROP FUNCTION IF EXISTS public.cron_process_no_activity_fn();
CREATE OR REPLACE FUNCTION public.cron_process_no_activity_fn() RETURNS void AS $no_activity$
DECLARE
    no_activity_rec record;
    user_settings jsonb;
    total_metrics INTEGER;
    total_logs INTEGER;
    del_metrics INTEGER;
    out_json JSONB;
BEGIN
    -- Check for vessel with no activity for more than 230 days
    RAISE NOTICE 'cron_process_no_activity_fn';
    FOR no_activity_rec in
        SELECT
            v.owner_email,m.name,m.vessel_id,m.time,a.first
            FROM auth.accounts a
            LEFT JOIN auth.vessels v ON v.owner_email = a.email
            LEFT JOIN api.metadata m ON v.vessel_id = m.vessel_id
            WHERE m.time < NOW() AT TIME ZONE 'UTC' - INTERVAL '230 DAYS'
                AND v.owner_email <> 'demo@openplotter.cloud'
            ORDER BY m.time DESC
    LOOP
        RAISE NOTICE '-> cron_process_no_activity_rec_fn for [%]', no_activity_rec;
        SELECT json_build_object('email', no_activity_rec.owner_email, 'recipient', no_activity_rec.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_no_activity_rec_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('no_activity'::TEXT, user_settings::JSONB);
        SELECT count(*) INTO total_metrics from api.metrics where vessel_id = no_activity_rec.vessel_id;
        WITH deleted AS (delete from api.metrics m where vessel_id = no_activity_rec.vessel_id RETURNING *) SELECT count(*) INTO del_metrics FROM deleted;
        SELECT count(*) INTO total_logs from api.logbook where vessel_id = no_activity_rec.vessel_id;
        SELECT jsonb_build_object('total_metrics', total_metrics, 'total_logs', total_logs, 'del_metrics', del_metrics) INTO out_json;
        RAISE NOTICE '-> debug cron_process_no_activity_rec_fn [%]', out_json;
    END LOOP;
END;
$no_activity$ language plpgsql;

DROP FUNCTION public.delete_account_fn(text,text);
CREATE OR REPLACE FUNCTION public.delete_account_fn(IN _email TEXT, IN _vessel_id TEXT) RETURNS JSONB
AS $delete_account$
DECLARE
    del_vessel_data JSONB;
    del_meta INTEGER;
    del_vessel INTEGER;
    del_account INTEGER;
    out_json JSONB;
BEGIN
    SELECT public.delete_vessel_fn(_vessel_id) INTO del_vessel_data;
    WITH deleted AS (delete from api.metadata where vessel_id = _vessel_id RETURNING *) SELECT count(*) INTO del_meta FROM deleted;
    WITH deleted AS (delete from auth.vessels where vessel_id = _vessel_id RETURNING *) SELECT count(*) INTO del_vessel FROM deleted;
    WITH deleted AS (delete from auth.accounts where email = _email RETURNING *) SELECT count(*) INTO del_account FROM deleted;
    SELECT jsonb_build_object('del_metadata', del_meta,
                            'del_vessel', del_vessel,
                            'del_account', del_account) || del_vessel_data INTO out_json;
    RETURN out_json;
END
$delete_account$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.delete_account_fn
    IS 'Delete all data for a account by email and vessel_id';

-- Update version
UPDATE public.app_settings
	SET value='0.7.1'
	WHERE "name"='app.version';
