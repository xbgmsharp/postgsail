---------------------------------------------------------------------------
-- Copyright 2021-2024 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration November 2024
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Add MobilityDB support
CREATE EXTENSION IF NOT EXISTS mobilitydb;
-- Update logbook tbl, add trip from mobilitydb
ALTER TABLE api.logbook ADD COLUMN trip tgeogpoint NULL;
ALTER TABLE api.logbook ADD COLUMN trip_cog tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_sog tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_twa tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_tws tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_twd tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_notes ttext NULL;
ALTER TABLE api.logbook ADD COLUMN trip_status ttext NULL;
CREATE INDEX ON api.logbook USING GIST (trip);

COMMENT ON COLUMN api.logbook.trip_cog IS 'courseovergroundtrue';
COMMENT ON COLUMN api.logbook.trip_sog IS 'speedoverground';
COMMENT ON COLUMN api.logbook.trip_twa IS 'windspeedapparent';
COMMENT ON COLUMN api.logbook.trip_tws IS 'truewindspeed';
COMMENT ON COLUMN api.logbook.trip_twd IS 'truewinddirection';
COMMENT ON COLUMN api.logbook.trip IS 'MobilityDB trajectory';

CREATE OR REPLACE FUNCTION logbook_update_metrics_short_fn(
    total_entry INT,
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ
)
RETURNS TABLE (
    trajectory tgeogpoint,
    courseovergroundtrue tfloat,
    speedoverground tfloat,
    windspeedapparent tfloat,
    truewindspeed tfloat,
    truewinddirection tfloat,
    notes ttext,
    status ttext
) AS $$
DECLARE
    modulo_divisor INT;
BEGIN
    RETURN QUERY
    WITH metrics AS (
        -- Extract metrics
        SELECT m.time,
            m.courseovergroundtrue,
            m.speedoverground,
            m.windspeedapparent,
            m.longitude,
            m.latitude,
            '' AS notes,
            m.status,
            COALESCE(metersToKnots((m.metrics->'environment.wind.speedTrue')::NUMERIC), NULL) AS truewindspeed,
            COALESCE(radiantToDegrees((m.metrics->'environment.wind.directionTrue')::NUMERIC), NULL) AS truewinddirection,
            ST_MakePoint(m.longitude, m.latitude) AS geo_point
        FROM api.metrics m
        WHERE m.latitude IS NOT NULL
            AND m.longitude IS NOT NULL
            AND m.time >= start_date
            AND m.time <= end_date
            AND vessel_id = current_setting('vessel.id', false)
            ORDER BY m.time ASC
    )
    -- Create mobilitydb temporal sequences
    SELECT 
        tgeogpointseq(array_agg(tgeogpoint(ST_SetSRID(o.geo_point, 4326)::geography, o.time) ORDER BY o.time ASC)) AS trajectory,
        tfloatseq(array_agg(tfloat(o.courseovergroundtrue, o.time) ORDER BY o.time ASC) FILTER (WHERE o.courseovergroundtrue IS NOT NULL)) AS courseovergroundtrue,
        tfloatseq(array_agg(tfloat(o.speedoverground, o.time) ORDER BY o.time ASC) FILTER (WHERE o.speedoverground IS NOT NULL)) AS speedoverground,
        tfloatseq(array_agg(tfloat(o.windspeedapparent, o.time) ORDER BY o.time ASC) FILTER (WHERE o.windspeedapparent IS NOT NULL)) AS windspeedapparent,
        tfloatseq(array_agg(tfloat(o.truewindspeed, o.time) ORDER BY o.time ASC) FILTER (WHERE o.truewindspeed IS NOT NULL)) AS truewindspeed,
        tfloatseq(array_agg(tfloat(o.truewinddirection, o.time) ORDER BY o.time ASC) FILTER (WHERE o.truewinddirection IS NOT NULL)) AS truewinddirection,
        ttextseq(array_agg(ttext(o.notes, o.time) ORDER BY o.time ASC)) AS notes,
        ttextseq(array_agg(ttext(o.status, o.time) ORDER BY o.time ASC) FILTER (WHERE o.status IS NOT NULL)) AS status
    FROM metrics o;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_metrics_short_fn
    IS 'Optimize logbook metrics for short metrics';

DROP FUNCTION IF EXISTS public.logbook_update_metrics_fn;
CREATE OR REPLACE FUNCTION logbook_update_metrics_fn(
    total_entry INT,
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ
)
RETURNS TABLE (
    trajectory tgeogpoint,
    courseovergroundtrue tfloat,
    speedoverground tfloat,
    windspeedapparent tfloat,
    truewindspeed tfloat,
    truewinddirection tfloat,
    notes ttext,
    status ttext
) AS $$
DECLARE
    modulo_divisor INT;
BEGIN
    -- Determine modulo based on total_entry
    IF total_entry <= 500 THEN
        modulo_divisor := 1;
    ELSIF total_entry > 500 AND total_entry <= 1000 THEN
        modulo_divisor := 2;
    ELSIF total_entry > 1000 AND total_entry <= 2000 THEN
        modulo_divisor := 3;
    ELSIF total_entry > 2000 AND total_entry <= 3000 THEN
        modulo_divisor := 4;
    ELSE
        modulo_divisor := 5;
    END IF;

    RETURN QUERY
    WITH metrics AS (
        -- Extract metrics base the total of entry ignoring first and last 10 minutes metrics
        SELECT t.time,
            t.courseovergroundtrue,
            t.speedoverground,
            t.windspeedapparent,
            t.longitude,
            t.latitude,
            '' AS notes,
            t.status,
            COALESCE(metersToKnots((t.metrics->'environment.wind.speedTrue')::NUMERIC), NULL) AS truewindspeed,
            COALESCE(radiantToDegrees((t.metrics->'environment.wind.directionTrue')::NUMERIC), NULL) AS truewinddirection,
            ST_MakePoint(t.longitude, t.latitude) AS geo_point
        FROM (
            SELECT *, row_number() OVER() AS row
            FROM api.metrics m
            WHERE m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.time > (start_date + interval '10 minutes')
                AND m.time < (end_date - interval '10 minutes')
                AND vessel_id = current_setting('vessel.id', false)
				ORDER BY m.time ASC
        ) t
        WHERE t.row % modulo_divisor = 0
    ),
    first_metric AS (
        -- Extract first 10 minutes metrics
        SELECT 
            m.time,
            m.courseovergroundtrue,
            m.speedoverground,
            m.windspeedapparent,
            m.longitude,
            m.latitude,
            '' AS notes,
            m.status,
            COALESCE(metersToKnots((m.metrics->'environment.wind.speedTrue')::NUMERIC), NULL) AS truewindspeed,
            COALESCE(radiantToDegrees((m.metrics->'environment.wind.directionTrue')::NUMERIC), NULL) AS truewinddirection,
            ST_MakePoint(m.longitude, m.latitude) AS geo_point
        FROM api.metrics m
        WHERE m.latitude IS NOT NULL
            AND m.longitude IS NOT NULL
            AND m.time >= start_date
            AND m.time < (start_date + interval '10 minutes')
            AND vessel_id = current_setting('vessel.id', false)
        ORDER BY m.time ASC
    ),
    last_metric AS (
        -- Extract last 10 minutes metrics
        SELECT 
            m.time,
            m.courseovergroundtrue,
            m.speedoverground,
            m.windspeedapparent,
            m.longitude,
            m.latitude,
            '' AS notes,
            m.status,
            COALESCE(metersToKnots((m.metrics->'environment.wind.speedTrue')::NUMERIC), NULL) AS truewindspeed,
            COALESCE(radiantToDegrees((m.metrics->'environment.wind.directionTrue')::NUMERIC), NULL) AS truewinddirection,
            ST_MakePoint(m.longitude, m.latitude) AS geo_point
        FROM api.metrics m
        WHERE m.latitude IS NOT NULL
            AND m.longitude IS NOT NULL
            AND m.time <= end_date
            AND m.time > (end_date - interval '10 minutes')
            AND vessel_id = current_setting('vessel.id', false)
        ORDER BY m.time ASC
    ),
    optimize_metrics AS (
        -- Combine and order the results
        SELECT * FROM first_metric
        UNION ALL
        SELECT * FROM metrics
        UNION ALL
        SELECT * FROM last_metric
        ORDER BY time ASC
    )
    -- Create mobilitydb temporal sequences
    SELECT 
        tgeogpointseq(array_agg(tgeogpoint(ST_SetSRID(o.geo_point, 4326)::geography, o.time) ORDER BY o.time ASC)) AS trajectory,
        tfloatseq(array_agg(tfloat(o.courseovergroundtrue, o.time) ORDER BY o.time ASC) FILTER (WHERE o.courseovergroundtrue IS NOT NULL)) AS courseovergroundtrue,
        tfloatseq(array_agg(tfloat(o.speedoverground, o.time) ORDER BY o.time ASC) FILTER (WHERE o.speedoverground IS NOT NULL)) AS speedoverground,
        tfloatseq(array_agg(tfloat(o.windspeedapparent, o.time) ORDER BY o.time ASC) FILTER (WHERE o.windspeedapparent IS NOT NULL)) AS windspeedapparent,
        tfloatseq(array_agg(tfloat(o.truewindspeed, o.time) ORDER BY o.time ASC) FILTER (WHERE o.truewindspeed IS NOT NULL)) AS truewindspeed,
        tfloatseq(array_agg(tfloat(o.truewinddirection, o.time) ORDER BY o.time ASC) FILTER (WHERE o.truewinddirection IS NOT NULL)) AS truewinddirection,
        ttextseq(array_agg(ttext(o.notes, o.time) ORDER BY o.time ASC)) AS notes,
        ttextseq(array_agg(ttext(o.status, o.time) ORDER BY o.time ASC) FILTER (WHERE o.status IS NOT NULL)) AS status
    FROM optimize_metrics o;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_metrics_fn
    IS 'Optimize logbook metrics base on the total metrics';

DROP FUNCTION IF EXISTS public.logbook_update_metrics_timebucket_fn;
CREATE OR REPLACE FUNCTION public.logbook_update_metrics_timebucket_fn(
    total_entry INT,
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ
)
RETURNS TABLE (
    trajectory tgeogpoint,
    courseovergroundtrue tfloat,
    speedoverground tfloat,
    windspeedapparent tfloat,
    truewindspeed tfloat,
    truewinddirection tfloat,
    notes ttext,
    status ttext
) AS $$
DECLARE
    bucket_interval INTERVAL;
BEGIN
    -- Determine modulo based on total_entry
    IF total_entry <= 500 THEN
        bucket_interval := '2 minutes';
    ELSIF total_entry > 500 AND total_entry <= 1000 THEN
        bucket_interval := '3 minutes';
    ELSIF total_entry > 1000 AND total_entry <= 2000 THEN
        bucket_interval := '5 minutes';
    ELSIF total_entry > 2000 AND total_entry <= 3000 THEN
        bucket_interval := '10 minutes';
    ELSE
        bucket_interval := '15 minutes';
    END IF;

    RETURN QUERY
    WITH metrics AS (
        -- Extract metrics base the total of entry ignoring first and last 10 minutes metrics
        SELECT  time_bucket(bucket_interval::INTERVAL, m.time) AS time_bucket,  -- Time-bucketed period
            avg(m.courseovergroundtrue) as courseovergroundtrue,
            avg(m.speedoverground) as speedoverground,
            avg(m.windspeedapparent) as windspeedapparent,
            --last(m.longitude, m.time) as longitude, last(m.latitude, m.time) as latitude,
            '' AS notes,
            last(m.status, m.time) as status,
            COALESCE(metersToKnots(avg((m.metrics->'environment.wind.speedTrue')::NUMERIC)), NULL) as truewindspeed,
            COALESCE(radiantToDegrees(avg((m.metrics->'environment.wind.directionTrue')::NUMERIC)), NULL) as truewinddirection,
            ST_MakePoint(last(m.longitude, m.time),last(m.latitude, m.time)) AS geo_point
        FROM api.metrics m
        WHERE m.latitude IS NOT NULL
            AND m.longitude IS NOT NULL
            AND m.time > (start_date + interval '10 minutes')
            AND m.time < (end_date - interval '10 minutes')
            AND vessel_id = current_setting('vessel.id', false)
        GROUP BY time_bucket
        ORDER BY time_bucket ASC
    ),
    first_metric AS (
        -- Extract first 10 minutes metrics
        SELECT 
            m.time AS time_bucket,
            m.courseovergroundtrue,
            m.speedoverground,
            m.windspeedapparent,
            m.longitude,
            m.latitude,
            '' AS notes,
            m.status,
            COALESCE(metersToKnots((m.metrics->'environment.wind.speedTrue')::NUMERIC), NULL) AS truewindspeed,
            COALESCE(radiantToDegrees((m.metrics->'environment.wind.directionTrue')::NUMERIC), NULL) AS truewinddirection,
            ST_MakePoint(m.longitude, m.latitude) AS geo_point
        FROM api.metrics m
        WHERE m.latitude IS NOT NULL
            AND m.longitude IS NOT NULL
            AND m.time >= start_date
            AND m.time < (start_date + interval '10 minutes')
            AND vessel_id = current_setting('vessel.id', false)
        ORDER BY time_bucket ASC
    ),
    last_metric AS (
        -- Extract last 10 minutes metrics
        SELECT 
            m.time AS time_bucket,
            m.courseovergroundtrue,
            m.speedoverground,
            m.windspeedapparent,
            m.longitude,
            m.latitude,
            '' AS notes,
            m.status,
            COALESCE(metersToKnots((m.metrics->'environment.wind.speedTrue')::NUMERIC), NULL) AS truewindspeed,
            COALESCE(radiantToDegrees((m.metrics->'environment.wind.directionTrue')::NUMERIC), NULL) AS truewinddirection,
            ST_MakePoint(m.longitude, m.latitude) AS geo_point
        FROM api.metrics m
        WHERE m.latitude IS NOT NULL
            AND m.longitude IS NOT NULL
            AND m.time <= end_date
            AND m.time > (end_date - interval '10 minutes')
            AND vessel_id = current_setting('vessel.id', false)
        ORDER BY time_bucket ASC
    ),
    optimize_metrics AS (
        -- Combine and order the results
        SELECT * FROM first_metric
        UNION ALL
        SELECT * FROM metrics
        UNION ALL
        SELECT * FROM last_metric
        ORDER BY time ASC
    )
    -- Create mobilitydb temporal sequences
    SELECT 
        tgeogpointseq(array_agg(tgeogpoint(ST_SetSRID(o.geo_point, 4326)::geography, o.time_bucket) ORDER BY o.time ASC)) AS trajectory,
        tfloatseq(array_agg(tfloat(o.courseovergroundtrue, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.courseovergroundtrue IS NOT NULL)) AS courseovergroundtrue,
        tfloatseq(array_agg(tfloat(o.speedoverground, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.speedoverground IS NOT NULL)) AS speedoverground,
        tfloatseq(array_agg(tfloat(o.windspeedapparent, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.windspeedapparent IS NOT NULL)) AS windspeedapparent,
        tfloatseq(array_agg(tfloat(o.truewindspeed, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.truewindspeed IS NOT NULL)) AS truewindspeed,
        tfloatseq(array_agg(tfloat(o.truewinddirection, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.truewinddirection IS NOT NULL)) AS truewinddirection,
        ttextseq(array_agg(ttext(o.notes, o.time_bucket) ORDER BY o.time_bucket ASC)) AS notes,
        ttextseq(array_agg(ttext(o.status, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.status IS NOT NULL)) AS status
    FROM optimize_metrics o;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_metrics_timebucket_fn
    IS 'Optimize logbook metrics base on the aggregate time-series';

-- Update logbook table, add support for mobility temporal type   
CREATE OR REPLACE FUNCTION public.process_logbook_queue_fn(_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
    DECLARE
        logbook_rec record;
        from_name text;
        to_name text;
        log_name text;
        from_moorage record;
        to_moorage record;
        avg_rec record;
        geo_rec record;
        t_rec record;
        log_settings jsonb;
        user_settings jsonb;
        geojson jsonb;
        extra_json jsonb;
    BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_logbook_queue_fn invalid input %', _id;
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
            RAISE WARNING '-> process_logbook_queue_fn invalid logbook %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', logbook_rec.vessel_id, false);
        --RAISE WARNING 'public.process_logbook_queue_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);

        -- Calculate logbook data average and geo
        -- Update logbook entry with the latest metric data and calculate data
        avg_rec := public.logbook_update_avg_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        geo_rec := public.logbook_update_geom_distance_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);

        -- Do we have an existing moorage within 300m of the new log
        -- generate logbook name, concat _from_location and _to_location from moorage name
        from_moorage := public.process_lat_lon_fn(logbook_rec._from_lng::NUMERIC, logbook_rec._from_lat::NUMERIC);
        to_moorage := public.process_lat_lon_fn(logbook_rec._to_lng::NUMERIC, logbook_rec._to_lat::NUMERIC);
        SELECT CONCAT(from_moorage.moorage_name, ' to ' , to_moorage.moorage_name) INTO log_name;

        -- Process `propulsion.*.runTime` and `navigation.log`
        -- Calculate extra json
        extra_json := public.logbook_update_extra_json_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        -- add the avg_wind_speed
        extra_json := extra_json || jsonb_build_object('avg_wind_speed', avg_rec.avg_wind_speed);

        -- mobilitydb, add spaciotemporal sequence
        -- reduce the numbers of metrics by skipping row or aggregate time-series
        -- By default the signalk PostgSail plugin report one entry every minute.
        IF avg_rec.count_metric < 30 THEN -- if less ~20min trip we keep it all data
            t_rec := public.logbook_update_metrics_short_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        ELSIF avg_rec.count_metric < 2000 THEN -- if less ~33h trip we skip data
            t_rec := public.logbook_update_metrics_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        ELSE -- As we have too many data, we time-series aggregate data
            t_rec := public.logbook_update_metrics_timebucket_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        END IF;
        --RAISE NOTICE 'mobilitydb [%]', t_rec;
        IF t_rec.trajectory IS NULL THEN
            RAISE WARNING '-> process_logbook_queue_fn, vessel_id [%], invalid mobilitydb data [%] [%]', logbook_rec.vessel_id, _id, t_rec;
            RETURN;
        END IF;

        RAISE NOTICE 'Updating valid logbook, vessel_id [%], entry logbook id:[%] start:[%] end:[%]', logbook_rec.vessel_id, logbook_rec.id, logbook_rec._from_time, logbook_rec._to_time;
        UPDATE api.logbook
            SET
                duration = (logbook_rec._to_time::TIMESTAMPTZ - logbook_rec._from_time::TIMESTAMPTZ),
                avg_speed = avg_rec.avg_speed,
                max_speed = avg_rec.max_speed,
                max_wind_speed = avg_rec.max_wind_speed,
                _from = from_moorage.moorage_name,
                _from_moorage_id = from_moorage.moorage_id,
                _to_moorage_id = to_moorage.moorage_id,
                _to = to_moorage.moorage_name,
                name = log_name,
                distance = geo_rec._track_distance,
                extra = extra_json,
                notes = NULL, -- reset pre_log process
                trip = t_rec.trajectory,
                trip_cog = t_rec.courseovergroundtrue,
                trip_sog = t_rec.speedoverground,
                trip_twa = t_rec.windspeedapparent,
                trip_tws = t_rec.truewindspeed,
                trip_twd = t_rec.truewinddirection,
                trip_notes = t_rec.notes,
                trip_status = t_rec.status
            WHERE id = logbook_rec.id;

        -- GeoJSON require track_geom field geometry linestring
        --geojson := logbook_update_geojson_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        -- GeoJSON require trip* columns
        geojson := api.logbook_update_geojson_trip_fn(logbook_rec.id);
        UPDATE api.logbook
            SET -- Update the data even it should be generate dynamically on request
                track_geojson = geojson,
                track_geog = trajectory(t_rec.trajectory)
                --track_geom = trajectory(t_rec.trajectory)::geometry
            WHERE id = logbook_rec.id;

        -- GeoJSON Timelapse require track_geojson geometry point
        -- Add properties to the geojson for timelapse purpose
        PERFORM public.logbook_timelapse_geojson_fn(logbook_rec.id);

        -- Add post logbook entry to process queue for notification and QGIS processing
        -- Require as we need the logbook to be updated with SQL commit
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('post_logbook', logbook_rec.id, NOW(), current_setting('vessel.id', true));

    END;
$function$
;
COMMENT ON FUNCTION public.process_logbook_queue_fn IS 'Update logbook details when completed, logbook_update_avg_fn, logbook_update_geom_distance_fn, reverse_geocode_py_fn';

-- Create api.export_logbook_geojson_linestring_trip_fn, transform spatiotemporal trip into a geojson with the corresponding properties
CREATE OR REPLACE FUNCTION api.export_logbook_geojson_linestring_trip_fn(_id integer)
RETURNS jsonb AS $$
DECLARE
BEGIN
    -- Return a geojson with a geometry linestring and the corresponding properties
    RETURN
            json_build_object(
            'type', 'FeatureCollection',
            'features', json_agg(ST_AsGeoJSON(log.*)::json))
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
            trajectory(trip), -- extract trip to geography
            timestamps(trip) as times -- extract timestamps to array
            FROM api.logbook
            WHERE id = _id
           ) AS log;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION api.export_logbook_geojson_linestring_trip_fn IS 'Generate geojson geometry LineString from trip with the corresponding properties';

-- Create api.export_logbook_geojson_point_trip_fn, transform spatiotemporal trip into a geojson with the corresponding properties
CREATE OR REPLACE FUNCTION api.export_logbook_geojson_point_trip_fn(_id integer)
RETURNS jsonb AS $$
DECLARE
BEGIN
    -- Return a geojson with each geometry point and the corresponding properties
    RETURN
            json_build_object(
                'type', 'FeatureCollection',
                'features', json_agg(ST_AsGeoJSON(t.*)::json))
        FROM (
            SELECT 
                geometry(getvalue(log.point)) AS point_geometry,
                getTimestamp(log.point) AS time,
                valueAtTimestamp(log.trip_cog, getTimestamp(log.point)) AS cog,
                valueAtTimestamp(log.trip_sog, getTimestamp(log.point)) AS sog,
                valueAtTimestamp(log.trip_twa, getTimestamp(log.point)) AS twa,
                valueAtTimestamp(log.trip_tws, getTimestamp(log.point)) AS tws,
                valueAtTimestamp(log.trip_twd, getTimestamp(log.point)) AS twd,
                valueAtTimestamp(log.trip_notes, getTimestamp(log.point)) AS notes,
                valueAtTimestamp(log.trip_status, getTimestamp(log.point)) AS status
            FROM 
            (
                SELECT 
                    unnest(instants(trip)) AS point,
                    trip_cog,
                    trip_sog,
                    trip_twa,
                    trip_tws,
                    trip_twd,
                    trip_notes,
                    trip_status
                FROM api.logbook
                WHERE id = _id
            ) AS log
        ) AS t;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION api.export_logbook_geojson_point_trip_fn IS 'Generate geojson geometry Point from trip with the corresponding properties';

-- Add logbook_update_geojson_trip_fn, update geojson from trip to geojson
CREATE OR REPLACE FUNCTION api.logbook_update_geojson_trip_fn(_id integer)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    logbook_rec RECORD;
    log_geojson JSONB;
    metrics_geojson JSONB;
    first_feature_obj JSONB;
    second_feature_note JSONB;
    last_feature_note JSONB;
BEGIN
    -- Validate input
    IF _id IS NULL OR _id < 1 THEN
        RAISE WARNING '-> logbook_update_geojson_trip_fn invalid input %', _id;
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

    -- GeoJSON Features for Metrics Points
    SELECT jsonb_agg(ST_AsGeoJSON(t.*)::jsonb) INTO metrics_geojson
    FROM (
        SELECT 
            geometry(getvalue(points.point)) AS point_geometry,
            getTimestamp(points.point) AS time,
            valueAtTimestamp(points.trip_cog, getTimestamp(points.point)) AS cog,
            valueAtTimestamp(points.trip_sog, getTimestamp(points.point)) AS sog,
            valueAtTimestamp(points.trip_twa, getTimestamp(points.point)) AS twa,
            valueAtTimestamp(points.trip_tws, getTimestamp(points.point)) AS tws,
            valueAtTimestamp(points.trip_twd, getTimestamp(points.point)) AS twd,
            valueAtTimestamp(points.trip_notes, getTimestamp(points.point)) AS notes,
            valueAtTimestamp(points.trip_status, getTimestamp(points.point)) AS status
        FROM (
            SELECT unnest(instants(trip)) AS point,
                    trip_cog,
                    trip_sog,
                    trip_twa,
                    trip_tws,
                    trip_twd,
                    trip_notes,
                    trip_status
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
            WHEN (metrics_geojson->1->'properties'->>'notes') IS NULL THEN 
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
            WHEN (metrics_geojson->-1->'properties'->>'notes') IS NULL THEN
                (metrics_geojson->-1->'properties' || last_feature_note)::jsonb
            ELSE
                metrics_geojson->-1->'properties'
        END,
        true
    );

    -- Combine Logbook and Metrics GeoJSON
    RETURN jsonb_build_object('type', 'FeatureCollection', 'features', log_geojson || metrics_geojson);

END;
$function$
;
-- Description
COMMENT ON FUNCTION
    api.logbook_update_geojson_trip_fn
    IS 'Export a log trip entry to GEOJSON format with custom properties for timelapse replay';

-- Update log_view with dynamic GeoJSON
CREATE OR REPLACE VIEW api.log_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT id,
    name,
    _from AS "from",
    _from_time AS started,
    _to AS "to",
    _to_time AS ended,
    distance,
    duration,
    notes,
    api.logbook_update_geojson_trip_fn(id) AS geojson,
    avg_speed,
    max_speed,
    max_wind_speed,
    extra,
    _from_moorage_id AS from_moorage_id,
    _to_moorage_id AS to_moorage_id
   FROM api.logbook l
  WHERE _to_time IS NOT NULL
  ORDER BY _from_time DESC;
-- Description
COMMENT ON VIEW api.log_view IS 'Log web view';

CREATE OR REPLACE FUNCTION api.export_logbook_gpx_trip_fn(_id integer)
RETURNS "text/xml"
LANGUAGE plpgsql
AS $function$
DECLARE
    app_settings jsonb;
BEGIN
    -- Validate input
    IF _id IS NULL OR _id < 1 THEN
        RAISE WARNING '-> export_logbook_gpx_trip_fn invalid input %', _id;
        RETURN '';
    END IF;

    -- Retrieve application settings
    app_settings := get_app_url_fn();

    -- Generate GPX XML with structured track data
    RETURN xmlelement(name gpx,
                      xmlattributes( '1.1' as version,
                                     'PostgSAIL' as creator,
                                     'http://www.topografix.com/GPX/1/1' as xmlns,
                                     'http://www.opencpn.org' as "xmlns:opencpn",
                                     app_settings->>'app.url' as "xmlns:postgsail",
                                     'http://www.w3.org/2001/XMLSchema-instance' as "xmlns:xsi",
                                     'http://www.garmin.com/xmlschemas/GpxExtensions/v3' as "xmlns:gpxx",
                                     'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/GpxExtensions/v3 http://www8.garmin.com/xmlschemas/GpxExtensionsv3.xsd' as "xsi:schemaLocation"),

        -- Metadata section
        xmlelement(name metadata,
                   xmlelement(name link, xmlattributes(app_settings->>'app.url' as href),
                              xmlelement(name text, 'PostgSail'))),

        -- Track section
        xmlelement(name trk,
                   xmlelement(name name, l.name),
                   xmlelement(name desc, l.notes),
                   xmlelement(name link, xmlattributes(concat(app_settings->>'app.url', '/log/', l.id) as href),
                              xmlelement(name text, l.name)),
                   xmlelement(name extensions,
                              xmlelement(name "postgsail:log_id", l.id),
                              xmlelement(name "postgsail:link", concat(app_settings->>'app.url', '/log/', l.id)),
                              xmlelement(name "opencpn:guid", uuid_generate_v4()),
                              xmlelement(name "opencpn:viz", '1'),
                              xmlelement(name "opencpn:start", l._from_time),
                              xmlelement(name "opencpn:end", l._to_time)),

                   -- Track segments with point data
                   xmlelement(name trkseg, xmlagg(
                               xmlelement(name trkpt,
                                          xmlattributes( ST_Y(getvalue(point)::geometry) as lat, ST_X(getvalue(point)::geometry) as lon ),
                                          xmlelement(name time, getTimestamp(point))
                               )))
        )
    )::pg_catalog.xml
    FROM api.logbook l
    JOIN LATERAL (
        SELECT unnest(instants(trip)) AS point
        FROM api.logbook WHERE id = _id
    ) AS points ON true
    WHERE l.id = _id
	GROUP BY l.name, l.notes, l.id;
END;
$function$;
-- Description
COMMENT ON FUNCTION
    api.export_logbook_gpx_trip_fn
    IS 'Export a log trip entry to GPX XML format';

CREATE OR REPLACE FUNCTION api.export_logbook_kml_trip_fn(_id integer)
RETURNS "text/xml"
LANGUAGE plpgsql
AS $function$
DECLARE
    logbook_rec RECORD;
BEGIN
    -- Validate input ID
    IF _id IS NULL OR _id < 1 THEN
        RAISE WARNING '-> export_logbook_kml_trip_fn invalid input %', _id;
        RETURN '';
    END IF;

    -- Fetch logbook details including the track geometry
    SELECT id, name, notes, vessel_id, ST_AsKML(trajectory(trip)) AS track_kml INTO logbook_rec
        FROM api.logbook 
        WHERE id = _id;

    -- Check if the logbook record is found
    IF logbook_rec.vessel_id IS NULL THEN
        RAISE WARNING '-> export_logbook_kml_trip_fn invalid logbook %', _id;
        RETURN '';
    END IF;

    -- Generate KML XML document
    RETURN xmlelement(
        name kml,
        xmlattributes(
            '1.0' as version,
            'PostgSAIL' as creator,
            'http://www.w3.org/2005/Atom' as "xmlns:atom",
            'http://www.opengis.net/kml/2.2' as "xmlns",
            'http://www.google.com/kml/ext/2.2' as "xmlns:gx",
            'http://www.opengis.net/kml/2.2' as "xmlns:kml"
        ),
        xmlelement(
            name "Document",
            xmlelement(name "name", logbook_rec.name),
            xmlelement(name "description", logbook_rec.notes),
            xmlelement(
                name "Placemark",
                logbook_rec.track_kml::pg_catalog.xml
            )
        )
    )::pg_catalog.xml;
END;
$function$;
-- Description
COMMENT ON FUNCTION
    api.export_logbook_kml_trip_fn
    IS 'Export a log trip entry to KML XML format';

-- Create api.export_logbook_geojson_linestring_trip_fn, replace timelapse_fn, transform spatiotemporal trip into a geojson with the corresponding properties
CREATE OR REPLACE FUNCTION api.export_logbooks_geojson_linestring_trips_fn(
    start_log integer DEFAULT NULL::integer,
    end_log integer DEFAULT NULL::integer,
    start_date text DEFAULT NULL::text,
    end_date text DEFAULT NULL::text,
    OUT geojson jsonb
) RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    logs_geojson jsonb;
BEGIN
    -- Normalize start and end values
    IF start_log IS NOT NULL AND end_log IS NULL THEN end_log := start_log; END IF;
    IF start_date IS NOT NULL AND end_date IS NULL THEN end_date := start_date; END IF;

    WITH logbook_data AS (
        -- get the logbook data, an array for each log
        SELECT
            trajectory(l.trip)::geometry as track_geog -- extract trip to geography
        FROM api.logbook l
        WHERE (start_log IS NULL OR l.id >= start_log) AND
              (end_log IS NULL OR l.id <= end_log) AND
              (start_date IS NULL OR l._from_time >= start_date::TIMESTAMPTZ) AND
              (end_date IS NULL OR l._to_time <= end_date::TIMESTAMPTZ + interval '23 hours 59 minutes') AND
              l.trip IS NOT NULL
        ORDER BY l._from_time ASC
    ),
    collect as (
        SELECT ST_Collect(
                        ARRAY(
                            SELECT track_geog FROM logbook_data))
    )
    -- Create the GeoJSON response
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', json_agg(ST_AsGeoJSON(logs.*)::json)) INTO geojson FROM logbook_data logs;
END;
$function$;
COMMENT ON FUNCTION api.export_logbooks_geojson_linestring_trips_fn IS 'Generate geojson geometry LineString from trip with the corresponding properties';

-- Add export_logbooks_geojson_point_trips_fn, replace timelapse2_fn, Generate the GeoJSON from the time sequence value 
CREATE OR REPLACE FUNCTION api.export_logbooks_geojson_point_trips_fn(
    start_log integer DEFAULT NULL::integer,
    end_log integer DEFAULT NULL::integer,
    start_date text DEFAULT NULL::text,
    end_date text DEFAULT NULL::text,
    OUT geojson jsonb
) RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    metrics_geojson jsonb;
BEGIN
    -- Normalize start and end values
    IF start_log IS NOT NULL AND end_log IS NULL THEN end_log := start_log; END IF;
    IF start_date IS NOT NULL AND end_date IS NULL THEN end_date := start_date; END IF;

    WITH logbook_data AS (
        -- get the logbook data, an array for each log
        SELECT api.export_logbook_geojson_trip_fn(l.id) as log_geojson
        FROM api.logbook l
        WHERE (start_log IS NULL OR l.id >= start_log) AND
              (end_log IS NULL OR l.id <= end_log) AND
              (start_date IS NULL OR l._from_time >= start_date::TIMESTAMPTZ) AND
              (end_date IS NULL OR l._to_time <= end_date::TIMESTAMPTZ + interval '23 hours 59 minutes') AND
              l.trip IS NOT NULL
        ORDER BY l._from_time ASC
    )
    -- Create the GeoJSON response
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', jsonb_agg(feature_element)) INTO geojson
        FROM logbook_data l,
            LATERAL json_array_elements(l.log_geojson) AS feature_element; -- Flatten the arrays and create a GeoJSON FeatureCollection
END;
$function$;
COMMENT ON FUNCTION api.export_logbooks_geojson_point_trips_fn IS 'Export all selected logs into a geojson `trip` to a geojson as points including properties';

-- Add export_logbook_geojson_trip_fn, update geojson from trip to geojson
CREATE OR REPLACE FUNCTION api.export_logbook_geojson_trip_fn(_id integer)
RETURNS json
LANGUAGE plpgsql
AS $function$
DECLARE
    logbook_rec RECORD;
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
    SELECT id, name, distance, duration, _from, _to
    INTO logbook_rec
    FROM api.logbook
    WHERE id = _id;

    -- Create JSON notes for feature properties
    first_feature_obj := jsonb_build_object('trip', jsonb_build_object('name', logbook_rec.name, 'duration', logbook_rec.duration, 'distance', logbook_rec.distance));
    second_feature_note := jsonb_build_object('notes', COALESCE(logbook_rec._from, ''));
    last_feature_note := jsonb_build_object('notes', COALESCE(logbook_rec._to, ''));

    -- GeoJSON Features for Metrics Points
    SELECT jsonb_agg(ST_AsGeoJSON(t.*)::jsonb) INTO metrics_geojson
    FROM (
        SELECT 
            geometry(getvalue(points.point)) AS point_geometry,
            getTimestamp(points.point) AS time,
            valueAtTimestamp(points.trip_cog, getTimestamp(points.point)) AS cog,
            valueAtTimestamp(points.trip_sog, getTimestamp(points.point)) AS sog,
            valueAtTimestamp(points.trip_twa, getTimestamp(points.point)) AS twa,
            valueAtTimestamp(points.trip_tws, getTimestamp(points.point)) AS tws,
            valueAtTimestamp(points.trip_twd, getTimestamp(points.point)) AS twd,
            valueAtTimestamp(points.trip_notes, getTimestamp(points.point)) AS notes,
            valueAtTimestamp(points.trip_status, getTimestamp(points.point)) AS status
        FROM (
            SELECT unnest(instants(trip)) AS point,
                    trip_cog,
                    trip_sog,
                    trip_twa,
                    trip_tws,
                    trip_twd,
                    trip_notes,
                    trip_status
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
            WHEN (metrics_geojson->1->'properties'->>'notes') IS NULL THEN -- it is not null but empty??
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
            WHEN (metrics_geojson->-1->'properties'->>'notes') IS NULL THEN -- it is not null but empty??
                (metrics_geojson->-1->'properties' || last_feature_note)::jsonb
            ELSE
                metrics_geojson->-1->'properties'
        END,
        true
    );

    -- Set output
    RETURN metrics_geojson;

END;
$function$
;
COMMENT ON FUNCTION api.export_logbook_geojson_trip_fn IS 'Export a logs entries to GeoJSON format of geometry point';

CREATE OR REPLACE FUNCTION api.export_logbooks_gpx_trips_fn(start_log integer DEFAULT NULL::integer, end_log integer DEFAULT NULL::integer)
 RETURNS "text/xml"
 LANGUAGE plpgsql
AS $function$
    declare
        merged_xml XML;
        app_settings jsonb;
    BEGIN
        -- Merge GIS track_geom of geometry type Point into a jsonb array format
        -- Normalize start and end values
        IF start_log IS NOT NULL AND end_log IS NULL THEN end_log := start_log; END IF;

        -- Gather url from app settings
        app_settings := get_app_url_fn();

        WITH logbook_data AS (
            -- get the logbook data, an array for each log
            SELECT 
                ST_Y(getvalue(point)::geometry) as lat,
                ST_X(getvalue(point)::geometry) as lon,
                getTimestamp(point) as time
            FROM (
                SELECT unnest(instants(trip)) AS point
                FROM api.logbook l
                WHERE (start_log IS NULL OR l.id >= start_log) AND
                    (end_log IS NULL OR l.id <= end_log) AND
                    l.trip IS NOT NULL
                ORDER BY l._from_time ASC
            ) AS points
        )

        --RAISE WARNING '-> export_logbooks_gpx_fn app_settings %', app_settings;
        -- Generate GPX XML, extract Point features from trip.
        SELECT xmlelement(name "gpx",
                            xmlattributes(  '1.1' as version,
                                            'PostgSAIL' as creator,
                                            'http://www.topografix.com/GPX/1/1' as xmlns,
                                            'http://www.opencpn.org' as "xmlns:opencpn",
                                            app_settings->>'app.url' as "xmlns:postgsail"),
                xmlelement(name "metadata",
                    xmlelement(name "link", xmlattributes(app_settings->>'app.url' as href),
                        xmlelement(name "text", 'PostgSail'))),
                xmlelement(name "trk",
                    xmlelement(name "name", 'trip name'),
                    xmlelement(name "trkseg", xmlagg(
                                                xmlelement(name "trkpt",
                                                    xmlattributes(lat, lon),
                                                        xmlelement(name "time", time)
                                                )))))::pg_catalog.xml
            INTO merged_xml
            FROM logbook_data;
            return merged_xml;
    END;
$function$
;
COMMENT ON FUNCTION api.export_logbooks_gpx_trips_fn IS 'Export a logs entries to GPX XML format';

CREATE OR REPLACE FUNCTION api.export_logbooks_kml_trips_fn(start_log integer DEFAULT NULL::integer, end_log integer DEFAULT NULL::integer)
 RETURNS "text/xml"
 LANGUAGE plpgsql
AS $function$
DECLARE
    _geom geometry;
    app_settings jsonb;
BEGIN
    -- Normalize start and end values
    IF start_log IS NOT NULL AND end_log IS NULL THEN end_log := start_log; END IF;

    WITH logbook_data AS (
        -- get the logbook data, an array for each log
        SELECT
            trajectory(trip)::geometry as track_geog -- extract trip to geography
        FROM api.logbook l
        WHERE (start_log IS NULL OR l.id >= start_log) AND
              (end_log IS NULL OR l.id <= end_log) AND
              l.trip IS NOT NULL
        ORDER BY l._from_time ASC
    )
    SELECT ST_Collect(
                        ARRAY(
                            SELECT track_geog FROM logbook_data)
            ) INTO _geom;

    -- Extract POINT from LINESTRING to generate KML XML
    RETURN xmlelement(name kml,
            xmlattributes(  '1.0' as version,
                            'PostgSAIL' as creator,
                            'http://www.w3.org/2005/Atom' as "xmlns:atom",
                            'http://www.opengis.net/kml/2.2' as "xmlns",
                            'http://www.google.com/kml/ext/2.2' as "xmlns:gx",
                            'http://www.opengis.net/kml/2.2' as "xmlns:kml"),
            xmlelement(name "Document",
                xmlelement(name "name", 'trip name'),
                xmlelement(name "Placemark",
                    ST_AsKML(_geom)::pg_catalog.xml
                )
            )
        )::pg_catalog.xml;
END;
$function$;
COMMENT ON FUNCTION api.export_logbooks_kml_trips_fn IS 'Export a logs entries to KML XML format';

-- Add update_trip_notes_fn, add temporal sequence into a trip notes
CREATE OR REPLACE FUNCTION api.update_trip_notes_fn(
    _id INT,
    update_string TTEXT -- ttext '["notes"@2024-11-07T18:40:45+00, ""@2024-11-07T18:41:45+00]'
)
RETURNS VOID AS $$
BEGIN
    UPDATE api.logbook l
    SET trip_notes = update(l.trip_notes, update_string)
    WHERE id = _id;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION api.update_trip_notes_fn IS 'Update trip note at a specific time for a temporal sequence';

CREATE OR REPLACE FUNCTION api.delete_trip_entry_fn(
    _id INT,
    update_string tstzspan -- tstzspan '[2024-11-07T18:40:45+00, 2024-11-07T18:41:45+00]'
)
RETURNS VOID AS $$
BEGIN
    UPDATE api.logbook l
        SET
            trip = deleteTime(l.trip, update_string),
            trip_cog = deleteTime(l.trip_cog, update_string),
            trip_sog = deleteTime(l.trip_sog, update_string),
            trip_twa = deleteTime(l.trip_twa, update_string),
            trip_tws = deleteTime(l.trip_tws, update_string),
            trip_twd = deleteTime(l.trip_twd, update_string),
            trip_notes = deleteTime(l.trip_notes, update_string),
            trip_status = deleteTime(l.trip_status, update_string)
        WHERE id = _id;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION api.delete_trip_entry_fn IS 'Delete at a specific time a temporal sequence for all trip_* column from a logbook';

DROP VIEW IF EXISTS api.vessels_view;
CREATE OR REPLACE VIEW api.vessels_view WITH (security_invoker=true,security_barrier=true) AS
    WITH metrics AS (
        SELECT COALESCE(
            (SELECT  m.time
                FROM api.metrics m
                WHERE m.vessel_id = current_setting('vessel.id')
                ORDER BY m.time DESC LIMIT 1
            )::TEXT ,
            NULL ) as last_metrics
    ),
    metadata AS (
        SELECT COALESCE(
            (SELECT  m.time
                FROM api.metadata m
                WHERE m.vessel_id = current_setting('vessel.id')
            )::TEXT ,
            NULL ) as last_contact
    )
    SELECT
        v.name as name,
        v.mmsi as mmsi,
        v.created_at as created_at,
        metadata.last_contact as last_contact,
        ((NOW() AT TIME ZONE 'UTC' - metadata.last_contact::TIMESTAMPTZ) > INTERVAL '70 MINUTES') as offline,
        (NOW() AT TIME ZONE 'UTC' - metadata.last_contact::TIMESTAMPTZ) as duration,
        metrics.last_metrics as last_metrics,
        ((NOW() AT TIME ZONE 'UTC' - metrics.last_metrics::TIMESTAMPTZ) > INTERVAL '70 MINUTES') as metrics_offline,
        (NOW() AT TIME ZONE 'UTC' - metrics.last_metrics::TIMESTAMPTZ) as duration_last_metrics
    FROM auth.vessels v, metadata, metrics
    WHERE v.owner_email = current_setting('user.email');
-- Description
COMMENT ON VIEW
    api.vessels_view
    IS 'Expose vessels listing to web api';

-- Update api.versions_fn(), add mobilitydb
CREATE OR REPLACE FUNCTION api.versions_fn()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
    DECLARE
        _appv TEXT;
        _sysv TEXT;
    BEGIN
        SELECT
            value, rtrim(substring(version(), 0, 17)) AS sys_version into _appv,_sysv
            FROM app_settings
            WHERE name = 'app.version';
        RETURN json_build_object('api_version', _appv,
                           'sys_version', _sysv,
						   'mobilitydb', (SELECT extversion as mobilitydb FROM pg_extension WHERE extname='mobilitydb'),
                           'timescaledb', (SELECT extversion as timescaledb FROM pg_extension WHERE extname='timescaledb'),
                           'postgis', (SELECT extversion as postgis FROM pg_extension WHERE extname='postgis'),
                           'postgrest', (SELECT rtrim(substring(application_name from 'PostgREST [0-9.]+')) as postgrest FROM pg_stat_activity WHERE application_name ilike '%postgrest%' LIMIT 1));
    END;
$function$
;
COMMENT ON FUNCTION api.versions_fn() IS 'Expose as a function, app and system version to API';

-- Update metrics_trigger_fn, Ignore entry if new time is in the future.
CREATE OR REPLACE FUNCTION public.metrics_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
    DECLARE
        previous_metric record;
        stay_code INTEGER;
        logbook_id INTEGER;
        stay_id INTEGER;
        valid_status BOOLEAN := False;
        _vessel_id TEXT;
        distance BOOLEAN := False;
    BEGIN
        --RAISE NOTICE 'metrics_trigger_fn';
        --RAISE WARNING 'metrics_trigger_fn [%] [%]', current_setting('vessel.id', true), NEW;
        -- Ensure vessel.id to new value to allow RLS
        IF NEW.vessel_id IS NULL THEN
            -- set vessel_id from jwt if not present in INSERT query
            NEW.vessel_id := current_setting('vessel.id');
        END IF;
        -- Boat metadata are check using api.metrics REFERENCES to api.metadata
        -- Fetch the latest entry to compare status against the new status to be insert
        SELECT * INTO previous_metric
            FROM api.metrics m 
            WHERE m.vessel_id IS NOT NULL
                AND m.vessel_id = current_setting('vessel.id', true)
            ORDER BY m.time DESC LIMIT 1;
        --RAISE NOTICE 'Metrics Status, New:[%] Previous:[%]', NEW.status, previous_metric.status;
        IF previous_metric.time = NEW.time THEN
            -- Ignore entry if same time
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], duplicate time [%] = [%]', NEW.vessel_id, previous_metric.time, NEW.time;
            RETURN NULL;
        END IF;
        IF previous_metric.time > NEW.time THEN
            -- Ignore entry if new time is later than previous time
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], new time is older than previous_metric.time [%] > [%]', NEW.vessel_id, previous_metric.time, NEW.time;
            RETURN NULL;
        END IF;
        IF NEW.time > NOW() THEN
            -- Ignore entry if new time is in the future.
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], new time is in the future [%] > [%]', NEW.vessel_id, NEW.time, NOW();
            RETURN NULL;
        END IF;
        -- Check if latitude or longitude are not type double
        --IF public.isdouble(NEW.latitude::TEXT) IS False OR public.isdouble(NEW.longitude::TEXT) IS False THEN
        --    -- Ignore entry if null latitude,longitude
        --    RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], not a double type for latitude or longitude [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
        --    RETURN NULL;
        --END IF;
        -- Check if latitude or longitude are null
        IF NEW.latitude IS NULL OR NEW.longitude IS NULL THEN
            -- Ignore entry if null latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], null latitude or longitude [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        -- Check if valid latitude
        IF NEW.latitude >= 90 OR NEW.latitude <= -90 THEN
            -- Ignore entry if invalid latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid latitude >= 90 OR <= -90 [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        -- Check if valid longitude
        IF NEW.longitude >= 180 OR NEW.longitude <= -180 THEN
            -- Ignore entry if invalid latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid longitude >= 180 OR <= -180 [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        IF NEW.latitude = NEW.longitude THEN
            -- Ignore entry if latitude,longitude are equal
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], latitude and longitude are equal [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        -- Check distance with previous point is > 10km
        --IF ST_Distance(
        --    ST_MakePoint(NEW.latitude,NEW.longitude)::geography,
        --    ST_MakePoint(previous_metric.latitude,previous_metric.longitude)::geography) > 10000 THEN
        --    RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], distance between previous metric and new metric is too long >10km, distance[%]', NEW.vessel_id, distance;
        --    RETURN NULL;
        --END IF;
        -- Check if status is null but speed is over 3knots set status to sailing
        IF NEW.status IS NULL AND NEW.speedoverground >= 3 THEN
            RAISE WARNING 'Metrics Unknown NEW.status from vessel_id [%], null status, set to sailing because of speedoverground is +3 from [%]', NEW.vessel_id, NEW.status;
            NEW.status := 'sailing';
        -- Check if status is null then set status to default moored
        ELSIF NEW.status IS NULL THEN
            RAISE WARNING 'Metrics Unknown NEW.status from vessel_id [%], null status, set to default moored from [%]', NEW.vessel_id, NEW.status;
            NEW.status := 'moored';
        END IF;
        IF previous_metric.status IS NULL THEN
            IF NEW.status = 'anchored' THEN
                RAISE WARNING 'Metrics Unknown previous_metric.status from vessel_id [%], [%] set to default current status [%]', NEW.vessel_id, previous_metric.status, NEW.status;
                previous_metric.status := NEW.status;
            ELSE
                RAISE WARNING 'Metrics Unknown previous_metric.status from vessel_id [%], [%] set to default status moored vs [%]', NEW.vessel_id, previous_metric.status, NEW.status;
                previous_metric.status := 'moored';
            END IF;
            -- Add new stay as no previous entry exist
            INSERT INTO api.stays 
                (vessel_id, active, arrived, latitude, longitude, stay_code)
                VALUES (current_setting('vessel.id', true), true, NEW.time, NEW.latitude, NEW.longitude, 1)
                RETURNING id INTO stay_id;
            -- Add stay entry to process queue for further processing
            --INSERT INTO process_queue (channel, payload, stored, ref_id)
            --    VALUES ('new_stay', stay_id, now(), current_setting('vessel.id', true));
            --RAISE WARNING 'Metrics Insert first stay as no previous metrics exist, stay_id stay_id [%] [%] [%]', stay_id, NEW.status, NEW.time;
        END IF;
        -- Check if status is valid enum
        SELECT NEW.status::name = any(enum_range(null::status_type)::name[]) INTO valid_status;
        IF valid_status IS False THEN
            -- Ignore entry if status is invalid
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid status [%]', NEW.vessel_id, NEW.status;
            RETURN NULL;
        END IF;
        -- Check if speedOverGround is valid value
        IF NEW.speedoverground >= 40 THEN
            -- Ignore entry as speedOverGround is invalid
            RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], speedOverGround is invalid, over 40 < [%]', NEW.vessel_id, NEW.speedoverground;
            RETURN NULL;
        END IF;

        -- Check the state and if any previous/current entry
        -- If change of state and new status is sailing or motoring
        IF previous_metric.status::TEXT <> NEW.status::TEXT AND
            ( (NEW.status::TEXT = 'sailing' AND previous_metric.status::TEXT <> 'motoring')
             OR (NEW.status::TEXT = 'motoring' AND previous_metric.status::TEXT <> 'sailing') ) THEN
            RAISE WARNING 'Metrics Update status, vessel_id [%], try new logbook, New:[%] Previous:[%]', NEW.vessel_id, NEW.status, previous_metric.status;
            -- Start new log
            logbook_id := public.trip_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF logbook_id IS NULL THEN
                INSERT INTO api.logbook
                    (vessel_id, active, _from_time, _from_lat, _from_lng)
                    VALUES (current_setting('vessel.id', true), true, NEW.time, NEW.latitude, NEW.longitude)
                    RETURNING id INTO logbook_id;
                RAISE WARNING 'Metrics Insert new logbook, vessel_id [%], logbook_id [%] [%] [%]', NEW.vessel_id, logbook_id, NEW.status, NEW.time;
            ELSE
                UPDATE api.logbook
                    SET
                        active = false,
                        _to_time = NEW.time,
                        _to_lat = NEW.latitude,
                        _to_lng = NEW.longitude
                    WHERE id = logbook_id;
                RAISE WARNING 'Metrics Existing logbook, vessel_id [%], logbook_id [%] [%] [%]', NEW.vessel_id, logbook_id, NEW.status, NEW.time;
            END IF;

            -- End current stay
            stay_id := public.stay_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF stay_id IS NOT NULL THEN
                UPDATE api.stays
                    SET
                        active = false,
                        departed = NEW.time
                    WHERE id = stay_id;
                -- Add stay entry to process queue for further processing
                INSERT INTO process_queue (channel, payload, stored, ref_id)
                    VALUES ('new_stay', stay_id, NOW(), current_setting('vessel.id', true));
                RAISE WARNING 'Metrics Updating, vessel_id [%], Stay end current stay_id [%] [%] [%]', NEW.vessel_id, stay_id, NEW.status, NEW.time;
            ELSE
                RAISE WARNING 'Metrics Invalid, vessel_id [%], stay_id [%] [%]', NEW.vessel_id, stay_id, NEW.time;
            END IF;

        -- If change of state and new status is moored or anchored
        ELSIF previous_metric.status::TEXT <> NEW.status::TEXT AND
            ( (NEW.status::TEXT = 'moored' AND previous_metric.status::TEXT <> 'anchored')
             OR (NEW.status::TEXT = 'anchored' AND previous_metric.status::TEXT <> 'moored') ) THEN
            -- Start new stays
            RAISE WARNING 'Metrics Update status, vessel_id [%], try new stay, New:[%] Previous:[%]', NEW.vessel_id, NEW.status, previous_metric.status;
            stay_id := public.stay_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF stay_id IS NULL THEN
                RAISE WARNING 'Metrics Inserting, vessel_id [%], new stay [%]', NEW.vessel_id, NEW.status;
                -- If metric status is anchored set stay_code accordingly
                stay_code = 1;
                IF NEW.status = 'anchored' THEN
                    stay_code = 2;
                END IF;
                -- Add new stay
                INSERT INTO api.stays
                    (vessel_id, active, arrived, latitude, longitude, stay_code)
                    VALUES (current_setting('vessel.id', true), true, NEW.time, NEW.latitude, NEW.longitude, stay_code)
                    RETURNING id INTO stay_id;
                RAISE WARNING 'Metrics Insert, vessel_id [%], new stay, stay_id [%] [%] [%]', NEW.vessel_id, stay_id, NEW.status, NEW.time;
            ELSE
                RAISE WARNING 'Metrics Invalid, vessel_id [%], stay_id [%] [%]', NEW.vessel_id, stay_id, NEW.time;
                UPDATE api.stays
                    SET
                        active = false,
                        departed = NEW.time,
                        notes = 'Invalid stay?'
                    WHERE id = stay_id;
            END IF;

            -- End current log/trip
            -- Fetch logbook_id by vessel_id
            logbook_id := public.trip_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF logbook_id IS NOT NULL THEN
                -- todo check on time start vs end
                RAISE WARNING 'Metrics Updating, vessel_id [%], logbook status [%] [%] [%]', NEW.vessel_id, logbook_id, NEW.status, NEW.time;
                UPDATE api.logbook 
                    SET 
                        active = false, 
                        _to_time = NEW.time,
                        _to_lat = NEW.latitude,
                        _to_lng = NEW.longitude
                    WHERE id = logbook_id;
                -- Add logbook entry to process queue for later processing
                INSERT INTO process_queue (channel, payload, stored, ref_id)
                    VALUES ('pre_logbook', logbook_id, NOW(), current_setting('vessel.id', true));
            ELSE
                RAISE WARNING 'Metrics Invalid, vessel_id [%], logbook_id [%] [%] [%]', NEW.vessel_id, logbook_id, NEW.status, NEW.time;
            END IF;
        END IF;
        RETURN NEW; -- Finally insert the actual new metric
    END;
$function$
;
-- Description
COMMENT ON FUNCTION
    public.metrics_trigger_fn() IS 'process metrics from vessel, generate pre_logbook and new_stay.';

DROP FUNCTION IF EXISTS public.cron_process_monitor_offline_fn;
-- Update Monitor offline to check metadata tbl and metrics tbl
CREATE FUNCTION public.cron_process_monitor_offline_fn() RETURNS void AS $$
declare
    metadata_rec record;
    process_id integer;
    user_settings jsonb;
    app_settings jsonb;
    metrics_rec record;
begin
    -- Check metadata last_update > 1h + cron_time(10m)
    RAISE NOTICE 'cron_process_monitor_offline_fn';
    FOR metadata_rec in 
        SELECT
            *, 
            NOW() AT TIME ZONE 'UTC' as now, 
            NOW() AT TIME ZONE 'UTC' - INTERVAL '70 MINUTES' as interval
        FROM api.metadata m
        WHERE 
            m.time < NOW() AT TIME ZONE 'UTC' - INTERVAL '70 MINUTES'
            AND active = True
        ORDER BY m.time DESC
    LOOP
        RAISE NOTICE '-> cron_process_monitor_offline_fn metadata_id [%]', metadata_rec.id;

        IF metadata_rec.vessel_id IS NULL OR metadata_rec.vessel_id = '' THEN
            RAISE WARNING '-> cron_process_monitor_offline_fn invalid metadata record vessel_id %', vessel_id;
            RAISE EXCEPTION 'Invalid metadata'
                USING HINT = 'Unknown vessel_id';
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', metadata_rec.vessel_id, false);
        RAISE NOTICE 'cron_process_monitor_offline_fn, vessel.id [%], updated api.metadata table to inactive for [%] [%]', current_setting('vessel.id', false), metadata_rec.id, metadata_rec.vessel_id;

        -- Ensure we don't have any metrics for the same period.
        SELECT time AS "time",
                (NOW() AT TIME ZONE 'UTC' - time) > INTERVAL '70 MINUTES' as offline
                INTO metrics_rec
            FROM api.metrics m 
            WHERE vessel_id = current_setting('vessel.id', false)
            ORDER BY time DESC LIMIT 1;
        IF metrics_rec.offline IS False THEN
            RETURN;
        END IF;

        -- update api.metadata table, set active to bool false
        UPDATE api.metadata
            SET 
                active = False
            WHERE id = metadata_rec.id;
        
        -- Gather email and pushover app settings
        --app_settings = get_app_settings_fn();
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(metadata_rec.vessel_id::TEXT);
        RAISE DEBUG '-> cron_process_monitor_offline_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('monitor_offline'::TEXT, user_settings::JSONB);
        -- log/insert/update process_queue table with processed
        INSERT INTO process_queue
            (channel, payload, stored, processed, ref_id)
            VALUES 
                ('monitoring_offline', metadata_rec.id, metadata_rec.interval, now(), metadata_rec.vessel_id)
            RETURNING id INTO process_id;
        RAISE NOTICE '-> cron_process_monitor_offline_fn updated process_queue table [%]', process_id;
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_monitor_offline_fn
    IS 'init by pg_cron to monitor offline pending notification, if so perform send_email o send_pushover base on user preferences';

DROP VIEW IF EXISTS api.moorages_view;
-- Update moorages_view, make arrivals&departure and total_duration computed data
CREATE OR REPLACE VIEW api.moorages_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT 
    m.id,
    m.name AS moorage,
    sa.description AS default_stay,
    sa.stay_code AS default_stay_id,
    --EXTRACT(day FROM justify_hours(m.stay_duration)) AS total_stay,
    --m.stay_duration AS total_duration,
    --m.reference_count AS arrivals_departures,
    COALESCE(COUNT(distinct l.id), 0) AS arrivals_departures,
    --COALESCE(COUNT(distinct s.id), 0) AS visits,
    COALESCE(SUM(distinct s.duration), INTERVAL 'PT0S') AS total_duration -- Summing the stay durations
FROM 
    api.moorages m
JOIN
    api.stays_at sa 
    ON m.stay_code = sa.stay_code
LEFT JOIN
    api.stays s 
    ON m.id = s.moorage_id
	AND s.active = False -- exclude active stays
LEFT JOIN
	api.logbook l 
	ON m.id = l._from_moorage_id OR m.id = l._to_moorage_id
	AND l.active = False -- exclude active logs
WHERE 
    --m.stay_duration <> 'PT0S'
    m.geog IS NOT NULL 
    AND m.stay_code = sa.stay_code
GROUP BY 
    m.id, m.name, sa.description, sa.stay_code
ORDER BY 
    total_duration DESC;

COMMENT ON VIEW api.moorages_view IS 'Moorages listing web view';

-- Update moorage_view, make arrivals&departure and total_duration computed data, add total visits
DROP VIEW IF EXISTS api.moorage_view;
CREATE OR REPLACE VIEW api.moorage_view
WITH(security_invoker=true,security_barrier=true)
AS WITH stay_details AS (
    SELECT 
        moorage_id,
        arrived,
        departed,
        duration,
        id AS stay_id,
        FIRST_VALUE(id) OVER (PARTITION BY moorage_id ORDER BY arrived ASC) AS first_seen_id,
        FIRST_VALUE(id) OVER (PARTITION BY moorage_id ORDER BY departed DESC) AS last_seen_id
    FROM api.stays s
    WHERE active = false
),
stay_summary AS (
    SELECT 
        moorage_id,
        MIN(arrived) AS first_seen,
        MAX(departed) AS last_seen,
        SUM(duration) AS total_duration,
        COUNT(*) AS stay_count,
        MAX(first_seen_id) AS first_seen_id, -- Pick the calculated first_seen_id
        MAX(last_seen_id) AS last_seen_id   -- Pick the calculated last_seen_id
    FROM stay_details
    GROUP BY moorage_id
),
log_summary AS (
    SELECT 
        moorage_id,
        COUNT(DISTINCT id) AS log_count
    FROM (
        SELECT _from_moorage_id AS moorage_id, id FROM api.logbook l WHERE active = false
        UNION ALL
        SELECT _to_moorage_id AS moorage_id, id FROM api.logbook l WHERE active = false
    ) logs
    GROUP BY moorage_id
)
SELECT 
    m.id,
    m.name,
    sa.description AS default_stay,
    sa.stay_code AS default_stay_id,
    m.notes,
    m.home_flag AS home,
    m.geog, -- use for GeoJSON
    m.latitude, -- use for GPX
    m.longitude, -- use for GPX
    COALESCE(l.log_count, 0) AS logs_count, -- Counting the number of logs, arrivals and departures
    COALESCE(ss.stay_count, 0) AS stays_count, -- Counting the number of stays, visits
    COALESCE(ss.total_duration, INTERVAL 'PT0S') AS stays_sum_duration, -- Summing the stay durations
    ss.first_seen AS stay_first_seen, -- First stay observed
    ss.last_seen AS stay_last_seen, -- Last stay observed
    ss.first_seen_id AS stay_first_seen_id,
    ss.last_seen_id AS stay_last_seen_id
FROM 
    api.moorages m
JOIN
    api.stays_at sa 
    ON m.stay_code = sa.stay_code
LEFT JOIN
    stay_summary ss 
    ON m.id = ss.moorage_id
LEFT JOIN
    log_summary l 
    ON m.id = l.moorage_id
WHERE 
    m.stay_duration <> 'PT0S'
    AND m.geog IS NOT NULL
ORDER BY 
    m.stay_duration DESC;

COMMENT ON VIEW api.moorage_view IS 'Moorage details web view';

DROP FUNCTION api.export_moorages_geojson_fn(out jsonb);
-- Update moorages map, use api.moorage_view as source table
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
                        m.id,
                        m.name,
                        m.default_stay,
                        m.default_stay_id,
                        m.home,
                        m.notes,
                        m.geog,
                        logs_count, -- Counting the number of logs
                        stays_count, -- Counting the number of stays
                        stays_sum_duration, -- Summing the stay durations
                        stay_first_seen, -- First stay observed
                        stay_last_seen,  -- Last stay observed
                        stay_first_seen_id, -- First stay id observed
                        stay_last_seen_id  -- Last stay id observed
                        FROM api.moorage_view m
                        WHERE geog IS NOT null
                    ) AS m
                )
            ) INTO geojson;
    END;
$function$;
COMMENT ON FUNCTION api.export_moorages_geojson_fn(out jsonb) IS 'Export moorages as geojson';

-- Update mapgl_fn, refactor function using existing function
DROP FUNCTION IF EXISTS api.mapgl_fn;
CREATE OR REPLACE FUNCTION api.mapgl_fn(start_log integer DEFAULT NULL::integer, end_log integer DEFAULT NULL::integer, start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT geojson jsonb)
 RETURNS jsonb
AS $mapgl$
    DECLARE
        logs_geojson jsonb;
        moorages_geojson jsonb;
        merged_features jsonb;
    BEGIN
        -- Normalize start and end values
        IF start_log IS NOT NULL AND end_log IS NULL THEN end_log := start_log; END IF;
        IF start_date IS NOT NULL AND end_date IS NULL THEN end_date := start_date; END IF;

        -- Get logs_geojson based on input criteria
        --RAISE WARNING 'input % % %' , start_log, end_log, public.isnumeric(end_log::text);
        IF start_log IS NOT NULL AND public.isnumeric(start_log::text) AND public.isnumeric(end_log::text) THEN
            SELECT api.export_logbooks_geojson_linestring_trips_fn(start_log, end_log) INTO logs_geojson;
        ELSIF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            SELECT api.export_logbooks_geojson_linestring_trips_fn(NULL, NULL, start_date, end_date) INTO logs_geojson;
        ELSE
            SELECT api.export_logbooks_geojson_linestring_trips_fn() INTO logs_geojson;
        END IF;

        -- Debugging logs
        --RAISE WARNING 'Logs GeoJSON: [%]', logs_geojson->'features';

        -- Get moorages_geojson
        SELECT api.export_moorages_geojson_fn() INTO moorages_geojson;

        -- Debugging logs
        --RAISE WARNING 'Moorages GeoJSON: [%]', moorages_geojson->'features';

        -- Ensure proper merging of 'features' arrays
        merged_features := jsonb_build_array() 
                            || COALESCE(logs_geojson->'features', '[]'::jsonb) 
                            || COALESCE(moorages_geojson->'features', '[]'::jsonb);

        -- Generate the GeoJSON with all moorages and logs
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', merged_features
        ) INTO geojson;
    END;
$mapgl$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.mapgl_fn
    IS 'Generate a geojson with all logs as geometry LineString with moorages as geometry Point to be process by DeckGL';

-- Update api.export_moorages_gpx_fn, use moorage_view as source to include computed data
DROP FUNCTION IF EXISTS api.export_moorages_gpx_fn;
CREATE FUNCTION api.export_moorages_gpx_fn() RETURNS "text/xml" AS $export_moorages_gpx$
    DECLARE
        app_settings jsonb;
    BEGIN
        -- Gather url from app settings
        app_settings := get_app_url_fn();
        -- Generate XML
        RETURN xmlelement(name gpx,
                    xmlattributes(  '1.1' as version,
                                    'PostgSAIL' as creator,
                                    'http://www.topografix.com/GPX/1/1' as xmlns,
                                    'http://www.opencpn.org' as "xmlns:opencpn",
                                    app_settings->>'app.url' as "xmlns:postgsail",
                                    'http://www.w3.org/2001/XMLSchema-instance' as "xmlns:xsi",
                                    'http://www.garmin.com/xmlschemas/GpxExtensions/v3' as "xmlns:gpxx",
                                    'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/GpxExtensions/v3 http://www8.garmin.com/xmlschemas/GpxExtensionsv3.xsd' as "xsi:schemaLocation"),
                    xmlagg(
                        xmlelement(name wpt, xmlattributes(m.latitude as lat, m.longitude as lon),
                            xmlelement(name name, m.name),
                            xmlelement(name time, m.stay_first_seen),
                            xmlelement(name desc,
                                concat(E'First Stayed On: ',  m.stay_first_seen,
                                    E'\nLast Stayed On: ',  m.stay_last_seen,
                                    E'\nTotal Stays Visits: ', m.stays_count,
                                    E'\nTotal Stays Duration: ', m.stays_sum_duration,
                                    E'\nTotal Logs, Arrivals and Departures: ', m.logs_count,
                                    E'\nNotes: ', m.notes,
                                    E'\nLink: ', concat(app_settings->>'app.url','/moorage/', m.id)),
                                    xmlelement(name "opencpn:guid", uuid_generate_v4())),
                            xmlelement(name sym, 'anchor'),
                            xmlelement(name type, 'WPT'),
                            xmlelement(name link, xmlattributes(concat(app_settings->>'app.url','/moorage/', m.id) as href),
                                                        xmlelement(name text, m.name)),
                            xmlelement(name extensions, xmlelement(name "postgsail:mooorage_id", m.id),
                                                        xmlelement(name "postgsail:link", concat(app_settings->>'app.url','/moorage/', m.id)),
                                                        xmlelement(name "opencpn:guid", uuid_generate_v4()),
                                                        xmlelement(name "opencpn:viz", '1'),
                                                        xmlelement(name "opencpn:scale_min_max", xmlattributes(true as UseScale, 30000 as ScaleMin, 0 as ScaleMax)
                                                        ))))
                    )::pg_catalog.xml
            FROM api.moorage_view m
            WHERE geog IS NOT NULL;
    END;
$export_moorages_gpx$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.export_moorages_gpx_fn
    IS 'Export moorages as gpx';

-- Add api.export_moorages_kml_fn, export all moorages as kml
DROP FUNCTION IF EXISTS api.export_moorages_kml_fn;
CREATE FUNCTION api.export_moorages_kml_fn() RETURNS "text/xml" AS $export_moorages_kml$
    DECLARE
        app_settings jsonb;
    BEGIN
        -- Gather url from app settings
        app_settings := get_app_url_fn();
        -- Generate XML
        RETURN xmlelement(name kml,
                    xmlattributes(  '1.0' as version,
                                    'PostgSAIL' as creator,
                                    'http://www.w3.org/2005/Atom' as "xmlns:atom",
                                    'http://www.opengis.net/kml/2.2' as "xmlns",
                                    'http://www.google.com/kml/ext/2.2' as "xmlns:gx",
                                    'http://www.opengis.net/kml/2.2' as "xmlns:kml"),
                    xmlelement(name "Document",
                        xmlagg(
                            xmlelement(name "Placemark",
                                xmlelement(name "name", m.name),
                                xmlelement(name "description",
                                    concat(E'First Stayed On: ', m.stay_first_seen,
                                        E'\nLast Stayed On: ', m.stay_last_seen,
                                        E'\nTotal Stays Visits: ', m.stays_count,
                                        E'\nTotal Stays Duration: ', m.stays_sum_duration,
                                        E'\nTotal Logs, Arrivals and Departures: ', m.logs_count,
                                        E'\nNotes: ', m.notes,
                                        E'\nLink: ', concat(app_settings->>'app.url','/moorage/', m.id))),
                                ST_AsKml(m.geog)::XML)
                        )
                    )
                )::pg_catalog.xml
            FROM api.moorage_view m
            WHERE geog IS NOT NULL;
    END;
$export_moorages_kml$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.export_moorages_kml_fn
    IS 'Export moorages as kml';

-- Update public.process_pre_logbook_fn, update stationary detection, if we have less than 20 metrics or less than 0.5NM or less than avg 0.5knts
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
                    AND s.arrived = logbook_rec._to_time;
            -- Update related stays
            UPDATE api.stays s
                SET notes = 'invalid stays data, stationary need to fix metrics?'
                WHERE vessel_id = current_setting('vessel.id', false)
                    AND arrived = logbook_rec._to_time;
            -- Find previous stays
            SELECT id INTO previous_stays_id
				FROM api.stays s
                WHERE s.vessel_id = current_setting('vessel.id', false)
                    AND s.arrived < logbook_rec._to_time
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

DROP FUNCTION IF EXISTS api.export_logbook_kml_fn;
CREATE OR REPLACE FUNCTION api.export_logbook_kml_fn(IN _id INTEGER) RETURNS "text/xml"
AS $export_logbook_kml$
    DECLARE
        logbook_rec record;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> export_logbook_kml_fn invalid input %', _id;
            return '';
        END IF;
        -- Gather log details
        SELECT * INTO logbook_rec
            FROM api.logbook WHERE id = _id;
        -- Ensure the query is successful
        IF logbook_rec.vessel_id IS NULL THEN
            RAISE WARNING '-> export_logbook_kml_fn invalid logbook %', _id;
            return '';
        END IF;
        -- Extract POINT from LINESTRING to generate KML XML
        RETURN xmlelement(name kml,
                                xmlattributes(  '1.0' as version,
                                                'PostgSAIL' as creator,
                                                'http://www.w3.org/2005/Atom' as "xmlns:atom",
                                                'http://www.opengis.net/kml/2.2' as "xmlns",
                                                'http://www.google.com/kml/ext/2.2' as "xmlns:gx",
                                                'http://www.opengis.net/kml/2.2' as "xmlns:kml"),
                                xmlelement(name "Document",
                                                xmlelement(name "Placemark",
                                                    xmlelement(name "name", logbook_rec.name),
                                                    xmlelement(name "description", logbook_rec.notes),
                                                    ST_AsKML(logbook_rec.track_geog)::pg_catalog.xml)
                            ))::pg_catalog.xml
               FROM api.logbook WHERE id = _id;
    END;
$export_logbook_kml$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.export_logbook_kml_fn
    IS 'Export a log entry to KML XML format';

-- Allow users to update certain columns on specific TABLES on API schema
GRANT UPDATE (name, _from, _to, notes, trip_notes, trip, trip_cog, trip_sog, trip_twa, trip_tws, trip_twd, trip_status) ON api.logbook TO user_role;

-- Refresh user_role permissions
GRANT SELECT ON TABLE api.log_view TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.logbook_update_geojson_trip_fn to api_anonymous;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO api_anonymous;
GRANT SELECT ON TABLE api.moorages_view TO grafana;
GRANT SELECT ON TABLE api.moorage_view TO grafana;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;

-- Update version
UPDATE public.app_settings
	SET value='0.7.8'
	WHERE "name"='app.version';

CREATE INDEX ON "api"."stays" ("stay_code");
CREATE INDEX ON "api"."moorages" ("stay_code");
ALTER TABLE "api"."metadata" FORCE ROW LEVEL SECURITY;
ALTER TABLE "api"."metrics" FORCE ROW LEVEL SECURITY;
ALTER TABLE "api"."logbook" FORCE ROW LEVEL SECURITY;
ALTER TABLE "api"."stays" FORCE ROW LEVEL SECURITY;
ALTER TABLE "api"."moorages" FORCE ROW LEVEL SECURITY;
ALTER TABLE "api"."stays_at" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "api"."stays_at" FORCE ROW LEVEL SECURITY;
ALTER TABLE "auth"."accounts" FORCE ROW LEVEL SECURITY;
ALTER TABLE "auth"."vessels" FORCE ROW LEVEL SECURITY;
ALTER TABLE "auth"."users" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "auth"."users" FORCE ROW LEVEL SECURITY;
ALTER TABLE "auth"."otp" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "auth"."otp" FORCE ROW LEVEL SECURITY;

\c postgres
