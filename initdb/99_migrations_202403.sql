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

CREATE FUNCTION metadata_upsert_trigger_fn() RETURNS trigger AS $metadata_upsert$
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

-- Update version
UPDATE public.app_settings
	SET value='0.7.1'
	WHERE "name"='app.version';
