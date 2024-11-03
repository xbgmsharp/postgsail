---------------------------------------------------------------------------
-- Copyright 2021-2024 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration October 2024
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Update moorages map, export more properties (notes,reference_count) from moorages tbl
CREATE OR REPLACE FUNCTION api.export_moorages_geojson_fn(OUT geojson jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
    BEGIN
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features',
                ( SELECT
                    json_agg(ST_AsGeoJSON(m.*)::JSON) as moorages_geojson
                    FROM
                    ( SELECT
                        id,name,stay_code,notes,reference_count,
                        EXTRACT(DAY FROM justify_hours ( stay_duration )) AS Total_Stay,
                        geog
                        FROM api.moorages
                        WHERE geog IS NOT NULL
                    ) AS m
                )
            ) INTO geojson;
    END;
$function$
;

COMMENT ON FUNCTION api.export_moorages_geojson_fn(out jsonb) IS 'Export moorages as geojson';

-- Update mapgl_fn, update moorages map sub query to export more properties (notes,reference_count) from moorages tbl
DROP FUNCTION IF EXISTS api.mapgl_fn;
CREATE OR REPLACE FUNCTION api.mapgl_fn(start_log integer DEFAULT NULL::integer, end_log integer DEFAULT NULL::integer, start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT geojson jsonb)
 RETURNS jsonb
AS $mapgl$
    DECLARE
        _geojson jsonb;
    BEGIN
        -- Using sub query to force id order by time
        -- Extract GeoJSON LineString and merge into a new GeoJSON
        --raise WARNING 'input % % %' , start_log, end_log, public.isnumeric(end_log::text);
        IF start_log IS NOT NULL AND end_log IS NULL THEN
            end_log := start_log;
        END IF;
        IF start_date IS NOT NULL AND end_date IS NULL THEN
            end_date := start_date;
        END IF;
        --raise WARNING 'input % % %' , start_log, end_log, public.isnumeric(end_log::text);
        IF start_log IS NOT NULL AND public.isnumeric(start_log::text) AND public.isnumeric(end_log::text) THEN
            SELECT jsonb_agg(
                        jsonb_build_object('type', 'Feature',
                                            'properties', f->'properties',
                                            'geometry', jsonb_build_object( 'coordinates', f->'geometry'->'coordinates', 'type', 'LineString'))
                    ) INTO _geojson
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook l
                    WHERE l.id >= start_log
                        AND l.id <= end_log
                        AND l.track_geojson IS NOT NULL
                    ORDER BY l._from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'LineString';
        ELSIF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            SELECT jsonb_agg(
                        jsonb_build_object('type', 'Feature',
                                            'properties', f->'properties',
                                            'geometry', jsonb_build_object( 'coordinates', f->'geometry'->'coordinates', 'type', 'LineString'))
                    ) INTO _geojson
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook l
                    WHERE l._from_time >= start_date::TIMESTAMPTZ
                        AND l._to_time <= end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
                        AND l.track_geojson IS NOT NULL
                    ORDER BY l._from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'LineString';
        ELSE
            SELECT jsonb_agg(
                        jsonb_build_object('type', 'Feature',
                                            'properties', f->'properties',
                                            'geometry', jsonb_build_object( 'coordinates', f->'geometry'->'coordinates', 'type', 'LineString'))
                    ) INTO _geojson
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook l
                    WHERE l.track_geojson IS NOT NULL
                    ORDER BY l._from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'LineString';
        END IF;
        -- Generate the GeoJSON with all moorages
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', _geojson ||                 ( SELECT
                    jsonb_agg(ST_AsGeoJSON(m.*)::JSONB) as moorages_geojson
                    FROM
                    ( SELECT
                        id,name,stay_code,notes,reference_count,
                        EXTRACT(DAY FROM justify_hours ( stay_duration )) AS Total_Stay,
                        geog
                        FROM api.moorages
                        WHERE geog IS NOT null
                    ) AS m
                ) ) INTO geojson;
    END;
$mapgl$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.mapgl_fn
    IS 'Generate a geojson with all logs as geometry LineString with moorages as geometry Point to be process by DeckGL';

-- Update logbook_update_geojson_fn, fix corrupt linestring properties
CREATE OR REPLACE FUNCTION public.logbook_update_geojson_fn(_id integer, _start text, _end text, OUT _track_geojson json)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
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
                _to_time,
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
$function$
;
COMMENT ON FUNCTION public.logbook_update_geojson_fn(in int4, in text, in text, out json) IS 'Update log details with geojson';

-- Add trigger to update logbook stats from user edit geojson
DROP FUNCTION IF EXISTS public.update_logbook_with_geojson_trigger_fn;
CREATE OR REPLACE FUNCTION public.update_logbook_with_geojson_trigger_fn() RETURNS TRIGGER AS $$
DECLARE
    geojson JSONB;
    feature JSONB;
BEGIN
    -- Parse the incoming GeoJSON data from the track_geojson column
    geojson := NEW.track_geojson::jsonb;

    -- Extract the first feature (assume it is the LineString)
    feature := geojson->'features'->0;

	IF geojson IS NOT NULL AND feature IS NOT NULL AND (feature->'properties' ? 'x-update') THEN

	    -- Get properties from the feature to extract avg_speed, and max_speed
	    NEW.avg_speed := (feature->'properties'->>'avg_speed')::FLOAT;
	    NEW.max_speed := (feature->'properties'->>'max_speed')::FLOAT;
        NEW.max_wind_speed := (feature->'properties'->>'max_wind_speed')::FLOAT;
	    NEW.extra := jsonb_set( NEW.extra,
				      '{avg_wind_speed}',
				      to_jsonb((feature->'properties'->>'avg_wind_speed')::FLOAT),
				      true  -- this flag means it will create the key if it does not exist
				    );

	    -- Calculate the LineString's actual spatial distance
	    NEW.track_geom := ST_GeomFromGeoJSON(feature->'geometry'::text);
	    NEW.distance := TRUNC (ST_Length(NEW.track_geom,false)::INT * 0.0005399568, 4);  -- convert to NM

	END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.update_logbook_with_geojson_trigger_fn
    IS 'Extracts specific properties (distance, duration, avg_speed, max_speed) from a geometry LINESTRING part of a GeoJSON FeatureCollection, and then updates a column in a table named logbook';

-- Add trigger on logbook update to update metrics from track_geojson
CREATE TRIGGER update_logbook_with_geojson_trigger_fn
    BEFORE UPDATE OF track_geojson ON api.logbook
    FOR EACH ROW
    WHEN (NEW.track_geojson IS DISTINCT FROM OLD.track_geojson)
    EXECUTE FUNCTION public.update_logbook_with_geojson_trigger_fn();

-- Refresh user_role permissions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;

-- Update version
UPDATE public.app_settings
	SET value='0.7.8'
	WHERE "name"='app.version';

\c postgres
