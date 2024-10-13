---------------------------------------------------------------------------
-- Copyright 2021-2024 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration August 2024
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Timeseries GeoJson Feature Metrics points
DROP FUNCTION IF EXISTS public.logbook_update_geojson_fn;
CREATE FUNCTION public.logbook_update_geojson_fn(IN _id integer, IN _start text, IN _end text,
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
                extra['avg_wind_speed'] as avg_wind_speed,
                track_geom
                FROM api.logbook
                WHERE id = _id
           ) AS log;
        -- GeoJson Feature Metrics point
        SELECT
            json_agg(ST_AsGeoJSON(t.*)::json) into metrics_geojson
        FROM (
            ( SELECT
                time_bucket('5 minutes'::TEXT::INTERVAL, m.time) AS time_bucket,
                avg(m.courseovergroundtrue) as courseovergroundtrue,
                avg(m.speedoverground) as speedoverground,
                avg(m.windspeedapparent) as windspeedapparent,
                last(m.longitude, time) as longitude, last(m.latitude, time) as latitude,
                '' AS notes,
                coalesce(metersToKnots(m.metrics->'environment.wind.speedTrue'::NUMERIC), null) as truewindspeed,
                coalesce(radiantToDegrees(m.metrics->'environment.wind.directionTrue'::NUMERIC), null) as truewinddirection,
                coalesce(m.status, null) as status,
                st_makepoint(last(m.longitude, m.time),last(m.latitude, m.time)) AS geo_point
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
-- Description
COMMENT ON FUNCTION
    public.logbook_update_geojson_fn
    IS 'Update log details with geojson';

-- Update version
UPDATE public.app_settings
	SET value='0.7.6'
	WHERE "name"='app.version';

\c postgres
