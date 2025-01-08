---------------------------------------------------------------------------
-- Copyright 2021-2024 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration December 2024
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Add new mobilityDB support
ALTER TABLE api.logbook ADD COLUMN trip_depth tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_batt_charge tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_batt_voltage tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_temp_water tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_temp_out tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_pres_out tfloat NULL;
ALTER TABLE api.logbook ADD COLUMN trip_hum_out tfloat NULL;

-- Remove deprecated column from api.logbook
DROP VIEW IF EXISTS public.trip_in_progress; -- CASCADE
DROP TRIGGER IF EXISTS update_logbook_with_geojson_trigger_fn ON api.logbook; -- CASCADE
ALTER TABLE api.logbook DROP COLUMN track_geog;
ALTER TABLE api.logbook DROP COLUMN track_geom;
ALTER TABLE api.logbook DROP COLUMN track_geojson;

-- Remove deprecated column from api.moorages
ALTER TABLE api.moorages DROP COLUMN reference_count;
DROP VIEW IF EXISTS api.stats_moorages_view; -- CASCADE
DROP VIEW IF EXISTS api.stats_moorages_away_view; -- CASCADE
DROP VIEW IF EXISTS api.moorage_view; -- CASCADE
ALTER TABLE api.moorages DROP COLUMN stay_duration;

-- Restore cascade drop column
CREATE VIEW public.trip_in_progress AS
    SELECT * 
        FROM api.logbook 
        WHERE active IS true;

-- Update api.moorage_view, due to stay_duration column removal
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
    m.geog IS NOT NULL
ORDER BY 
    ss.total_duration DESC;

COMMENT ON VIEW api.moorage_view IS 'Moorage details web view';

-- Update stats_moorages_view, due to stay_duration column removal
CREATE OR REPLACE VIEW api.stats_moorages_view
WITH(security_invoker=true,security_barrier=true)
AS WITH home_ports AS (
         SELECT count(*) AS home_ports
           FROM api.moorage_view m
          WHERE m.home IS TRUE
        ), unique_moorage AS (
         SELECT count(*) AS unique_moorage
           FROM api.moorage_view m
        ), time_at_home_ports AS (
         SELECT sum(m.stays_sum_duration) AS time_at_home_ports
           FROM api.moorage_view m
          WHERE m.home IS TRUE
        ), time_spent_away AS (
         SELECT sum(m.stays_sum_duration) AS time_spent_away
           FROM api.moorage_view m
          WHERE m.home IS FALSE
        )
 SELECT home_ports.home_ports,
    unique_moorage.unique_moorage AS unique_moorages,
    time_at_home_ports.time_at_home_ports AS "time_spent_at_home_port(s)",
    time_spent_away.time_spent_away
   FROM home_ports,
    unique_moorage,
    time_at_home_ports,
    time_spent_away;

COMMENT ON VIEW api.stats_moorages_view IS 'Statistics Moorages web view';

-- Update stats_moorages_away_view, due to stay_duration column removal
CREATE OR REPLACE VIEW api.stats_moorages_away_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT sa.description,
    sum(m.stays_sum_duration) AS time_spent_away_by
   FROM api.moorage_view m,
    api.stays_at sa
  WHERE m.home IS FALSE AND m.default_stay_id = sa.stay_code
  GROUP BY m.default_stay_id, sa.description
  ORDER BY m.default_stay_id;

COMMENT ON VIEW api.stats_moorages_away_view IS 'Statistics Moorages Time Spent Away web view';

-- Comments
COMMENT ON TABLE api.logbook IS 'Stores generated logbook';
COMMENT ON COLUMN api.logbook.distance IS 'Distance in nautical miles (NM)';
COMMENT ON COLUMN api.logbook.duration IS 'Duration in ISO 8601 format';
COMMENT ON COLUMN api.logbook.extra IS 'Computed SignalK metrics such as runtime, current level, etc.';
COMMENT ON COLUMN api.logbook.trip_depth IS 'Depth';
COMMENT ON COLUMN api.logbook.trip_batt_charge IS 'Battery Charge';
COMMENT ON COLUMN api.logbook.trip_batt_voltage IS 'Battery Voltage';
COMMENT ON COLUMN api.logbook.trip_temp_water IS 'Temperature water';
COMMENT ON COLUMN api.logbook.trip_temp_out IS 'Temperature outside';
COMMENT ON COLUMN api.logbook.trip_pres_out IS 'Pressure outside';
COMMENT ON COLUMN api.logbook.trip_hum_out IS 'Humidity outside';

-- Deprecated function
COMMENT ON FUNCTION api.export_logbook_gpx_fn IS 'DEPRECATED, Export a log entry to GPX XML format';
COMMENT ON FUNCTION api.export_logbook_kml_fn IS 'DEPRECATED, Export a log entry to KML XML format';
COMMENT ON FUNCTION api.export_logbooks_gpx_fn IS 'DEPRECATED, Export a logs entries to GPX XML format';
COMMENT ON FUNCTION api.export_logbooks_kml_fn IS 'DEPRECATED, Export a logs entries to KML XML format';
COMMENT ON FUNCTION api.timelapse_fn IS 'DEPRECATED, Export all selected logs geometry `track_geom` to a geojson as MultiLineString with empty properties';
COMMENT ON FUNCTION api.timelapse2_fn IS 'DEPRECATED, Export all selected logs geojson `track_geojson` to a geojson as points including properties';

-- Add the moorage id foreign key
ALTER TABLE api.logbook
	ADD CONSTRAINT fk_from_moorage
	FOREIGN KEY (_from_moorage_id)
	REFERENCES api.moorages (id)
	ON DELETE SET NULL;
ALTER TABLE api.logbook
	ADD CONSTRAINT fk_to_moorage
	FOREIGN KEY (_to_moorage_id)
	REFERENCES api.moorages (id)
	ON DELETE SET NULL;

-- Update index for stays
CREATE INDEX stays_arrived_idx ON api.stays (arrived);
CREATE INDEX stays_departed_id_idx ON api.stays (departed);

-- Update index for logbook
CREATE INDEX logbook_active_idx ON api.logbook USING btree (active);

-- Create index
CREATE INDEX stays_stay_code_idx ON api.stays ("stay_code");
CREATE INDEX moorages_stay_code_idx ON api.moorages ("stay_code");

-- Permissions ROW LEVEL SECURITY
ALTER TABLE public.process_queue FORCE ROW LEVEL SECURITY;
ALTER TABLE api.metadata FORCE ROW LEVEL SECURITY;
ALTER TABLE api.metrics FORCE ROW LEVEL SECURITY;
ALTER TABLE api.logbook FORCE ROW LEVEL SECURITY;
ALTER TABLE api.stays FORCE ROW LEVEL SECURITY;
ALTER TABLE api.moorages FORCE ROW LEVEL SECURITY;
ALTER TABLE auth.accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE auth.vessels FORCE ROW LEVEL SECURITY;
ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE auth.users FORCE ROW LEVEL SECURITY;

-- Defined Primary Key
ALTER TABLE api.stays_at ADD PRIMARY KEY ("stay_code");
ALTER TABLE auth.vessels ADD PRIMARY KEY ("vessel_id");

-- Update public.logbook_update_metrics_short_fn, aggregate more metrics
DROP FUNCTION IF EXISTS public.logbook_update_metrics_short_fn;
CREATE OR REPLACE FUNCTION public.logbook_update_metrics_short_fn(
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
    status ttext,
    watertemperature tfloat,
    depth tfloat,
    outsidehumidity tfloat,
    outsidepressure tfloat,
    outsidetemperature tfloat,
    stateofcharge tfloat,
    voltage tfloat
) AS $$
DECLARE
BEGIN
    -- Aggregate all metrics as trip ios short.
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
            COALESCE((m.metrics->'environment.water.temperature')::NUMERIC, NULL) as watertemperature,
            COALESCE((m.metrics->'environment.depth.belowTransducer')::NUMERIC, NULL) as depth,
            COALESCE((m.metrics->'environment.outside.relativeHumidity')::NUMERIC, NULL) as outsidehumidity,
            COALESCE((m.metrics->'environment.outside.pressure')::NUMERIC, NULL) as outsidepressure,
            COALESCE((m.metrics->'environment.outside.temperature')::NUMERIC, NULL) as outsidetemperature,
            COALESCE((m.metrics->'electrical.batteries.House.capacity.stateOfCharge')::NUMERIC, NULL) as stateofcharge,
            COALESCE((m.metrics->'electrical.batteries.House.voltage')::NUMERIC, NULL) as voltage,
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
        ttextseq(array_agg(ttext(o.status, o.time) ORDER BY o.time ASC) FILTER (WHERE o.status IS NOT NULL)) AS status,
        tfloatseq(array_agg(tfloat(o.watertemperature, o.time) ORDER BY o.time ASC) FILTER (WHERE o.watertemperature IS NOT NULL)) AS watertemperature,
        tfloatseq(array_agg(tfloat(o.depth, o.time) ORDER BY o.time ASC) FILTER (WHERE o.depth IS NOT NULL)) AS depth,
        tfloatseq(array_agg(tfloat(o.outsidehumidity, o.time) ORDER BY o.time ASC) FILTER (WHERE o.outsidehumidity IS NOT NULL)) AS outsidehumidity,
        tfloatseq(array_agg(tfloat(o.outsidepressure, o.time) ORDER BY o.time ASC) FILTER (WHERE o.outsidepressure IS NOT NULL)) AS outsidepressure,
        tfloatseq(array_agg(tfloat(o.outsidetemperature, o.time) ORDER BY o.time ASC) FILTER (WHERE o.outsidetemperature IS NOT NULL)) AS outsidetemperature,
        tfloatseq(array_agg(tfloat(o.stateofcharge, o.time) ORDER BY o.time ASC) FILTER (WHERE o.stateofcharge IS NOT NULL)) AS stateofcharge,
        tfloatseq(array_agg(tfloat(o.voltage, o.time) ORDER BY o.time ASC) FILTER (WHERE o.voltage IS NOT NULL)) AS voltage
    FROM metrics o;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_metrics_short_fn
    IS 'Optimize logbook metrics for short metrics';

-- Update public.logbook_update_metrics_fn, aggregate more metrics
DROP FUNCTION IF EXISTS public.logbook_update_metrics_fn;
CREATE OR REPLACE FUNCTION public.logbook_update_metrics_fn(
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
    status ttext,
    watertemperature tfloat,
    depth tfloat,
    outsidehumidity tfloat,
    outsidepressure tfloat,
    outsidetemperature tfloat,
    stateofcharge tfloat,
    voltage tfloat
) AS $$
DECLARE
    modulo_divisor INT;
BEGIN
    -- Aggregate data to reduce size by skipping row.
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
            COALESCE((t.metrics->'environment.water.temperature')::NUMERIC, NULL) as watertemperature,
            COALESCE((t.metrics->'environment.depth.belowTransducer')::NUMERIC, NULL) as depth,
            COALESCE((t.metrics->'environment.outside.relativeHumidity')::NUMERIC, NULL) as outsidehumidity,
            COALESCE((t.metrics->'environment.outside.pressure')::NUMERIC, NULL) as outsidepressure,
            COALESCE((t.metrics->'environment.outside.temperature')::NUMERIC, NULL) as outsidetemperature,
            COALESCE((t.metrics->'electrical.batteries.House.capacity.stateOfCharge')::NUMERIC, NULL) as stateofcharge,
            COALESCE((t.metrics->'electrical.batteries.House.voltage')::NUMERIC, NULL) as voltage,
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
            COALESCE((m.metrics->'environment.water.temperature')::NUMERIC, NULL) as watertemperature,
            COALESCE((m.metrics->'environment.depth.belowTransducer')::NUMERIC, NULL) as depth,
            COALESCE((m.metrics->'environment.outside.relativeHumidity')::NUMERIC, NULL) as outsidehumidity,
            COALESCE((m.metrics->'environment.outside.pressure')::NUMERIC, NULL) as outsidepressure,
            COALESCE((m.metrics->'environment.outside.temperature')::NUMERIC, NULL) as outsidetemperature,
            COALESCE((m.metrics->'electrical.batteries.House.capacity.stateOfCharge')::NUMERIC, NULL) as stateofcharge,
            COALESCE((m.metrics->'electrical.batteries.House.voltage')::NUMERIC, NULL) as voltage,
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
            COALESCE((m.metrics->'environment.water.temperature')::NUMERIC, NULL) as watertemperature,
            COALESCE((m.metrics->'environment.depth.belowTransducer')::NUMERIC, NULL) as depth,
            COALESCE((m.metrics->'environment.outside.relativeHumidity')::NUMERIC, NULL) as outsidehumidity,
            COALESCE((m.metrics->'environment.outside.pressure')::NUMERIC, NULL) as outsidepressure,
            COALESCE((m.metrics->'environment.outside.temperature')::NUMERIC, NULL) as outsidetemperature,
            COALESCE((m.metrics->'electrical.batteries.House.capacity.stateOfCharge')::NUMERIC, NULL) as stateofcharge,
            COALESCE((m.metrics->'electrical.batteries.House.voltage')::NUMERIC, NULL) as voltage,
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
        ttextseq(array_agg(ttext(o.status, o.time) ORDER BY o.time ASC) FILTER (WHERE o.status IS NOT NULL)) AS status,
        tfloatseq(array_agg(tfloat(o.watertemperature, o.time) ORDER BY o.time ASC) FILTER (WHERE o.watertemperature IS NOT NULL)) AS watertemperature,
        tfloatseq(array_agg(tfloat(o.depth, o.time) ORDER BY o.time ASC) FILTER (WHERE o.depth IS NOT NULL)) AS depth,
        tfloatseq(array_agg(tfloat(o.outsidehumidity, o.time) ORDER BY o.time ASC) FILTER (WHERE o.outsidehumidity IS NOT NULL)) AS outsidehumidity,
        tfloatseq(array_agg(tfloat(o.outsidepressure, o.time) ORDER BY o.time ASC) FILTER (WHERE o.outsidepressure IS NOT NULL)) AS outsidepressure,
        tfloatseq(array_agg(tfloat(o.outsidetemperature, o.time) ORDER BY o.time ASC) FILTER (WHERE o.outsidetemperature IS NOT NULL)) AS outsidetemperature,
        tfloatseq(array_agg(tfloat(o.stateofcharge, o.time) ORDER BY o.time ASC) FILTER (WHERE o.stateofcharge IS NOT NULL)) AS stateofcharge,
        tfloatseq(array_agg(tfloat(o.voltage, o.time) ORDER BY o.time ASC) FILTER (WHERE o.voltage IS NOT NULL)) AS voltage
    FROM optimize_metrics o;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_metrics_fn
    IS 'Optimize logbook metrics base on the total metrics';

-- Update public.logbook_update_metrics_timebucket_fn, aggregate more metrics
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
    status ttext,
    watertemperature tfloat,
    depth tfloat,
    outsidehumidity tfloat,
    outsidepressure tfloat,
    outsidetemperature tfloat,
    stateofcharge tfloat,
    voltage tfloat
) AS $$
DECLARE
    bucket_interval INTERVAL;
BEGIN
    -- Aggregate metrics by time-series to reduce size
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
            last(m.longitude, m.time) as longitude, last(m.latitude, m.time) as latitude,
            '' AS notes,
            last(m.status, m.time) as status,
            COALESCE(metersToKnots(avg((m.metrics->'environment.wind.speedTrue')::NUMERIC)), NULL) as truewindspeed,
            COALESCE(radiantToDegrees(avg((m.metrics->'environment.wind.directionTrue')::NUMERIC)), NULL) as truewinddirection,
            COALESCE(avg((m.metrics->'environment.water.temperature')::NUMERIC), NULL) as watertemperature,
            COALESCE(avg((m.metrics->'environment.depth.belowTransducer')::NUMERIC), NULL) as depth,
            COALESCE(avg((m.metrics->'environment.outside.relativeHumidity')::NUMERIC), NULL) as outsidehumidity,
            COALESCE(avg((m.metrics->'environment.outside.pressure')::NUMERIC), NULL) as outsidepressure,
            COALESCE(avg((m.metrics->'environment.outside.temperature')::NUMERIC), NULL) as outsidetemperature,
            COALESCE(avg((m.metrics->'electrical.batteries.House.capacity.stateOfCharge')::NUMERIC), NULL) as stateofcharge,
            COALESCE(avg((m.metrics->'electrical.batteries.House.voltage')::NUMERIC), NULL) as voltage,
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
            COALESCE(avg((m.metrics->'environment.water.temperature')::NUMERIC), NULL) as watertemperature,
            COALESCE(avg((m.metrics->'environment.depth.belowTransducer')::NUMERIC), NULL) as depth,
            COALESCE(avg((m.metrics->'environment.outside.relativeHumidity')::NUMERIC), NULL) as outsidehumidity,
            COALESCE(avg((m.metrics->'environment.outside.pressure')::NUMERIC), NULL) as outsidepressure,
            COALESCE(avg((m.metrics->'environment.outside.temperature')::NUMERIC), NULL) as outsidetemperature,
            COALESCE(avg((m.metrics->'electrical.batteries.House.capacity.stateOfCharge')::NUMERIC), NULL) as stateofcharge,
            COALESCE(avg((m.metrics->'electrical.batteries.House.voltage')::NUMERIC), NULL) as voltage,
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
            COALESCE(avg((m.metrics->'environment.water.temperature')::NUMERIC), NULL) as watertemperature,
            COALESCE(avg((m.metrics->'environment.depth.belowTransducer')::NUMERIC), NULL) as depth,
            COALESCE(avg((m.metrics->'environment.outside.relativeHumidity')::NUMERIC), NULL) as outsidehumidity,
            COALESCE(avg((m.metrics->'environment.outside.pressure')::NUMERIC), NULL) as outsidepressure,
            COALESCE(avg((m.metrics->'environment.outside.temperature')::NUMERIC), NULL) as outsidetemperature,
            COALESCE(avg((m.metrics->'electrical.batteries.House.capacity.stateOfCharge')::NUMERIC), NULL) as stateofcharge,
            COALESCE(avg((m.metrics->'electrical.batteries.House.voltage')::NUMERIC), NULL) as voltage,
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
        ORDER BY time_bucket ASC
    )
    -- Create mobilitydb temporal sequences
    SELECT 
        tgeogpointseq(array_agg(tgeogpoint(ST_SetSRID(o.geo_point, 4326)::geography, o.time_bucket) ORDER BY o.time_bucket ASC)) AS trajectory,
        tfloatseq(array_agg(tfloat(o.courseovergroundtrue, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.courseovergroundtrue IS NOT NULL)) AS courseovergroundtrue,
        tfloatseq(array_agg(tfloat(o.speedoverground, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.speedoverground IS NOT NULL)) AS speedoverground,
        tfloatseq(array_agg(tfloat(o.windspeedapparent, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.windspeedapparent IS NOT NULL)) AS windspeedapparent,
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
        tfloatseq(array_agg(tfloat(o.voltage, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.voltage IS NOT NULL)) AS voltage
    FROM optimize_metrics o;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_metrics_timebucket_fn
    IS 'Optimize logbook metrics base on the aggregate time-series';

-- Update api.merge_logbook_fn, add support for mobility temporal type
CREATE OR REPLACE FUNCTION api.merge_logbook_fn(IN id_start integer, IN id_end integer) RETURNS void AS $merge_logbook$
    DECLARE
        logbook_rec_start record;
        logbook_rec_end record;
        log_name text;
        avg_rec record;
        geo_rec record;
        geojson jsonb;
        extra_json jsonb;
        t_rec record;
    BEGIN
        -- If id_start or id_end is not NULL
        IF (id_start IS NULL OR id_start < 1) OR (id_end IS NULL OR id_end < 1) THEN
            RAISE WARNING '-> merge_logbook_fn invalid input % %', id_start, id_end;
            RETURN;
        END IF;
        -- If id_end is lower than id_start
        IF id_end <= id_start THEN
            RAISE WARNING '-> merge_logbook_fn invalid input % < %', id_end, id_start;
            RETURN;
        END IF;
        -- Get the start logbook record with all necessary fields exist
        SELECT * INTO logbook_rec_start
            FROM api.logbook
            WHERE active IS false
                AND id = id_start
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        -- Ensure the query is successful
        IF logbook_rec_start.vessel_id IS NULL THEN
            RAISE WARNING '-> merge_logbook_fn invalid logbook %', id_start;
            RETURN;
        END IF;
        -- Get the end logbook record with all necessary fields exist
        SELECT * INTO logbook_rec_end
            FROM api.logbook
            WHERE active IS false
                AND id = id_end
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        -- Ensure the query is successful
        IF logbook_rec_end.vessel_id IS NULL THEN
            RAISE WARNING '-> merge_logbook_fn invalid logbook %', id_end;
            RETURN;
        END IF;

       	RAISE WARNING '-> merge_logbook_fn logbook start:% end:%', id_start, id_end;
        PERFORM set_config('vessel.id', logbook_rec_start.vessel_id, false);
   
        -- Calculate logbook data average and geo
        -- Update logbook entry with the latest metric data and calculate data
        avg_rec := logbook_update_avg_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);
        geo_rec := logbook_update_geom_distance_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);

	    -- Process `propulsion.*.runTime` and `navigation.log`
        -- Calculate extra json
        extra_json := logbook_update_extra_json_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);
        -- add the avg_wind_speed
        extra_json := extra_json || jsonb_build_object('avg_wind_speed', avg_rec.avg_wind_speed);

       	-- generate logbook name, concat _from_location and _to_location from moorage name
       	SELECT CONCAT(logbook_rec_start._from, ' to ', logbook_rec_end._to) INTO log_name;

        -- mobilitydb, add spaciotemporal sequence
        -- reduce the numbers of metrics by skipping row or aggregate time-series
        -- By default the signalk PostgSail plugin report one entry every minute.
        IF avg_rec.count_metric < 30 THEN -- if less ~20min trip we keep it all data
            t_rec := public.logbook_update_metrics_short_fn(avg_rec.count_metric, logbook_rec_start._from_time, logbook_rec_end._to_time);
        ELSIF avg_rec.count_metric < 2000 THEN -- if less ~33h trip we skip data
            t_rec := public.logbook_update_metrics_fn(avg_rec.count_metric, logbook_rec_start._from_time, logbook_rec_end._to_time);
        ELSE -- As we have too many data, we time-series aggregate data
            t_rec := public.logbook_update_metrics_timebucket_fn(avg_rec.count_metric, logbook_rec_start._from_time, logbook_rec_end._to_time);
        END IF;
        --RAISE NOTICE 'mobilitydb [%]', t_rec;
        IF t_rec.trajectory IS NULL THEN
            RAISE WARNING '-> process_logbook_queue_fn, vessel_id [%], invalid mobilitydb data [%] [%]', logbook_rec_start.vessel_id, logbook_rec_start.id, t_rec;
            RETURN;
        END IF;

        RAISE NOTICE 'Updating valid logbook entry logbook id:[%] start:[%] end:[%]', logbook_rec_start.id, logbook_rec_start._from_time, logbook_rec_end._to_time;
        UPDATE api.logbook
            SET
                duration = (logbook_rec_end._to_time::TIMESTAMPTZ - logbook_rec_start._from_time::TIMESTAMPTZ),
                avg_speed = avg_rec.avg_speed,
                max_speed = avg_rec.max_speed,
                max_wind_speed = avg_rec.max_wind_speed,
                -- Set _to metrics from end logbook
                _to = logbook_rec_end._to,
                _to_moorage_id = logbook_rec_end._to_moorage_id,
                _to_lat = logbook_rec_end._to_lat,
                _to_lng = logbook_rec_end._to_lng,
                _to_time = logbook_rec_end._to_time,
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
                trip_status = t_rec.status,
                trip_depth = t_rec.depth,
                trip_batt_charge = t_rec.stateofcharge,
                trip_batt_voltage = t_rec.voltage,
                trip_temp_water = t_rec.watertemperature,
                trip_temp_out = t_rec.outsidetemperature,
                trip_pres_out = t_rec.outsidepressure,
                trip_hum_out = t_rec.outsidehumidity
            WHERE id = logbook_rec_start.id;

        /*** Deprecated removed column
        -- GeoJSON require track_geom field geometry linestring
        --geojson := logbook_update_geojson_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        -- GeoJSON require trip* columns
        geojson := api.logbook_update_geojson_trip_fn(logbook_rec_start.id);
        UPDATE api.logbook
            SET -- Update the data column, it should be generate dynamically on request
                -- However there is a lot of dependencies to consider for a larger cleanup
                -- badges, qgis etc... depends on track_geom
                -- many export and others functions depends on track_geojson
                track_geojson = geojson,
                track_geog = trajectory(t_rec.trajectory),
                track_geom = trajectory(t_rec.trajectory)::geometry
         --       embedding = NULL,
         --       spatial_embedding = NULL
            WHERE id = logbook_rec_start.id;

        -- GeoJSON Timelapse require track_geojson geometry point
        -- Add properties to the geojson for timelapse purpose
        PERFORM public.logbook_timelapse_geojson_fn(logbook_rec_start.id);
         */
        -- Update logbook mark for deletion
        UPDATE api.logbook
            SET notes = 'mark for deletion'
            WHERE id = logbook_rec_end.id;
        -- Update related stays mark for deletion
        UPDATE api.stays
            SET notes = 'mark for deletion'
            WHERE arrived = logbook_rec_start._to_time;
       -- Update related moorages mark for deletion
        UPDATE api.moorages
            SET notes = 'mark for deletion'
            WHERE id = logbook_rec_start._to_moorage_id;

        -- Clean up, remove invalid logbook and stay, moorage entry
        DELETE FROM api.logbook WHERE id = logbook_rec_end.id;
        RAISE WARNING '-> merge_logbook_fn delete logbook id [%]', logbook_rec_end.id;
        DELETE FROM api.stays WHERE arrived = logbook_rec_start._to_time;
        RAISE WARNING '-> merge_logbook_fn delete stay arrived [%]', logbook_rec_start._to_time;
        DELETE FROM api.moorages WHERE id = logbook_rec_start._to_moorage_id;
        RAISE WARNING '-> merge_logbook_fn delete moorage id [%]', logbook_rec_start._to_moorage_id;
    END;
$merge_logbook$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.merge_logbook_fn
    IS 'Merge 2 logbook by id, from the start of the lower log id and the end of the higher log id, update the calculate data as well (avg, geojson)';

-- Update export_logbook_geojson_trip_fn, update geojson from trip to geojson
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
            valueAtTimestamp(points.trip_cog, getTimestamp(points.point)) AS courseovergroundtrue,
            valueAtTimestamp(points.trip_sog, getTimestamp(points.point)) AS speedoverground,
            valueAtTimestamp(points.trip_twa, getTimestamp(points.point)) AS windspeedapparent,
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
            valueAtTimestamp(points.trip_hum_out, getTimestamp(points.point)) AS outsidehumidity
        FROM (
            SELECT unnest(instants(trip)) AS point,
                    trip_cog,
                    trip_sog,
                    trip_twa,
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
                    trip_hum_out
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
            WHEN (metrics_geojson->1->'properties'->>'notes') IS "" THEN -- it is not null but empty??
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
            WHEN (metrics_geojson->-1->'properties'->>'notes') IS "" THEN -- it is not null but empty??
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
                geometry(getvalue(points.point)) AS point_geometry,
                getTimestamp(points.point) AS time,
                valueAtTimestamp(points.trip_cog, getTimestamp(points.point)) AS courseovergroundtrue,
                valueAtTimestamp(points.trip_sog, getTimestamp(points.point)) AS speedoverground,
                valueAtTimestamp(points.trip_twa, getTimestamp(points.point)) AS windspeedapparent,
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
                valueAtTimestamp(points.trip_hum_out, getTimestamp(points.point)) AS outsidehumidity
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
                    trip_status,
                    trip_depth,
                    trip_batt_charge,
                    trip_batt_voltage,
                    trip_temp_water,
                    trip_temp_out,
                    trip_pres_out,
                    trip_hum_out
                FROM api.logbook
                WHERE id = _id
            ) AS points
        ) AS t;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION api.export_logbook_geojson_point_trip_fn IS 'Generate geojson geometry Point from trip with the corresponding properties';

-- DROP FUNCTION public.process_lat_lon_fn(in numeric, in numeric, out int4, out int4, out text, out text);
-- Update public.process_lat_lon_fn remove deprecated moorages columns
CREATE OR REPLACE FUNCTION public.process_lat_lon_fn(lon numeric, lat numeric, OUT moorage_id integer, OUT moorage_type integer, OUT moorage_name text, OUT moorage_country text)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
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
                (vessel_id, name, country, stay_code, latitude, longitude, geog, overpass, nominatim)
                VALUES (
                    current_setting('vessel.id', false),
                    coalesce(replace(moorage_name,'"', ''), null),
                    coalesce(moorage_country, null),
                    moorage_type,
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
$function$
;

COMMENT ON FUNCTION public.process_lat_lon_fn(in numeric, in numeric, out int4, out int4, out text, out text) IS 'Add or Update moorage base on lat/lon';


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
                trip_status = t_rec.status,
                trip_depth = t_rec.depth,
                trip_batt_charge = t_rec.stateofcharge,
                trip_batt_voltage = t_rec.voltage,
                trip_temp_water = t_rec.watertemperature,
                trip_temp_out = t_rec.outsidetemperature,
                trip_pres_out = t_rec.outsidepressure,
                trip_hum_out = t_rec.outsidehumidity
            WHERE id = logbook_rec.id;

        /*** Deprecated removed column
        -- GeoJSON require track_geom field geometry linestring
        --geojson := logbook_update_geojson_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        -- GeoJSON require trip* columns
        geojson := api.logbook_update_geojson_trip_fn(logbook_rec.id);
        UPDATE api.logbook
            SET -- Update the data column, it should be generate dynamically on request
                -- However there is a lot of dependencies to concider for a larger cleanup
                -- badges, qgis etc... depends on track_geom
                -- many export and others functions depends on track_geojson
                track_geojson = geojson,
                track_geog = trajectory(t_rec.trajectory),
                track_geom = trajectory(t_rec.trajectory)::geometry
            WHERE id = logbook_rec.id;

        -- GeoJSON Timelapse require track_geojson geometry point
        -- Add properties to the geojson for timelapse purpose
        PERFORM public.logbook_timelapse_geojson_fn(logbook_rec.id);
        */
        -- Add post logbook entry to process queue for notification and QGIS processing
        -- Require as we need the logbook to be updated with SQL commit
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('post_logbook', logbook_rec.id, NOW(), current_setting('vessel.id', true));

    END;
$function$
;
COMMENT ON FUNCTION public.process_logbook_queue_fn IS 'Update logbook details when completed, logbook_update_avg_fn, logbook_update_geom_distance_fn, reverse_geocode_py_fn';

-- DROP FUNCTION public.badges_geom_fn(int4, text);
-- Update public.badges_geom_fn remove track_geom and use mobilitydb trajectory
CREATE OR REPLACE FUNCTION public.badges_geom_fn(logbook_id integer, logbook_time text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
    DECLARE
        _badges jsonb;
        _exist BOOLEAN := false;
        badge text;
        marine_rec record;
        user_settings jsonb;
        badge_tmp text;
    begin
	    --RAISE NOTICE '--> public.badges_geom_fn user.email [%], vessel.id [%]', current_setting('user.email', false), current_setting('vessel.id', false);
        -- Tropical & Alaska zone manually add into ne_10m_geography_marine_polys
        -- Check if each geographic marine zone exist as a badge
	    FOR marine_rec IN
	        WITH log AS (
		            SELECT trajectory(l.trip)::geometry AS track_geom FROM api.logbook l
                        WHERE l.id = logbook_id AND vessel_id = current_setting('vessel.id', false)
		            )
	        SELECT name from log, public.ne_10m_geography_marine_polys
                WHERE ST_Intersects(
		                ST_SetSRID(geom,4326),
                        log.track_geom
		            )
	    LOOP
            -- If not generate and insert the new badge
            --RAISE WARNING 'geography_marine [%]', marine_rec.name;
            SELECT jsonb_extract_path(a.preferences, 'badges', marine_rec.name) IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            --RAISE WARNING 'geography_marine [%]', _exist;
            if _exist is false then
                -- Create badge
                badge := '{"' || marine_rec.name || '": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) INTO badge;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                --RAISE WARNING '--> badges_geom_fn [%]', badge;
                -- Gather user settings
                badge_tmp := '{"badge": "' || marine_rec.name || '"}';
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || badge_tmp::JSONB INTO user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
	    END LOOP;
    END;
$function$
;

COMMENT ON FUNCTION public.badges_geom_fn(int4, text) IS 'check geometry logbook for new badges, eg: Tropic, Alaska, Geographic zone';

-- DROP FUNCTION public.process_stay_queue_fn(int4);
-- Update public.process_stay_queue_fn remove calculation of stay duration and count
CREATE OR REPLACE FUNCTION public.process_stay_queue_fn(_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
    DECLARE
        stay_rec record;
        moorage record;
    BEGIN
        RAISE NOTICE 'process_stay_queue_fn';
        -- If _id is valid, not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_stay_queue_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Get the stay record with all necessary fields exist
        SELECT * INTO stay_rec
            FROM api.stays
            WHERE active IS false
                AND departed IS NOT NULL
                AND arrived IS NOT NULL
                AND longitude IS NOT NULL
                AND latitude IS NOT NULL
                AND id = _id;
        -- Ensure the query is successful
        IF stay_rec.vessel_id IS NULL THEN
            RAISE WARNING '-> process_stay_queue_fn invalid stay %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', stay_rec.vessel_id, false);

        -- Do we have an existing moorage within 300m of the new stay
        moorage := process_lat_lon_fn(stay_rec.longitude::NUMERIC, stay_rec.latitude::NUMERIC);

        RAISE NOTICE '-> process_stay_queue_fn Updating stay entry [%]', stay_rec.id;
        UPDATE api.stays
            SET
                name = concat(
                            ROUND( EXTRACT(epoch from (stay_rec.departed::TIMESTAMPTZ - stay_rec.arrived::TIMESTAMPTZ)::INTERVAL / 86400) ),
                            ' days stay at ',
                            moorage.moorage_name,
                            ' in ',
                            RTRIM(TO_CHAR(stay_rec.departed, 'Month')),
                            ' ',
                            TO_CHAR(stay_rec.departed, 'YYYY')
                        ),
                moorage_id = moorage.moorage_id,
                duration = (stay_rec.departed::TIMESTAMPTZ - stay_rec.arrived::TIMESTAMPTZ)::INTERVAL,
                stay_code = moorage.moorage_type,
                geog = Geography(ST_MakePoint(stay_rec.longitude, stay_rec.latitude))
            WHERE id = stay_rec.id;

        RAISE NOTICE '-> process_stay_queue_fn Updating moorage entry [%]', moorage.moorage_id;
        /* reference_count and stay_duration are dynamically calculated
        UPDATE api.moorages
            SET
                reference_count = (
                    with _from as (select count(*) from api.logbook where _from_moorage_id = moorage.moorage_id),
                        _to as (select count(*) from api.logbook where _to_moorage_id = moorage.moorage_id)
                        select _from.count+_to.count from _from,_to
                ),
                stay_duration = (
                    select sum(departed-arrived) from api.stays where moorage_id = moorage.moorage_id
                )
            WHERE id = moorage.moorage_id;
        */
        -- Process badges
        PERFORM badges_moorages_fn();
    END;
$function$
;

COMMENT ON FUNCTION public.process_stay_queue_fn(int4) IS 'Update stay details, reverse_geocode_py_fn';

-- DROP FUNCTION public.badges_moorages_fn();
-- Update public.badges_moorages_fn remove calculation of stay duration and count
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
    BEGIN
        -- Check and set environment
        user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
        PERFORM set_config('user.email', user_settings->>'email'::TEXT, false);
        -- Get moorages with total duration
        CREATE TEMP TABLE badges_moorages_tbl AS
        SELECT 
            m.id,
            m.home_flag,
            sa.stay_code AS default_stay_id,
            EXTRACT(day FROM (COALESCE(SUM(distinct s.duration), INTERVAL 'PT0S'))) AS total_duration_days,
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
            AND s.vessel_id = current_setting('vessel.id', false)
        WHERE 
            --m.stay_duration <> 'PT0S'
            m.geog IS NOT NULL 
            AND m.stay_code = sa.stay_code
            AND m.vessel_id = current_setting('vessel.id', false)
        GROUP BY 
            m.id, sa.stay_code
        ORDER BY 
            total_duration_days DESC;

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

    -- Drop the temporary table
    DROP TABLE IF EXISTS badges_moorages_tbl;

    END;
$function$
;

COMMENT ON FUNCTION public.badges_moorages_fn() IS 'check moorages for new badges, eg: Explorer, Mooring Pro, Anchormaster';

-- DROP FUNCTION api.find_log_from_moorage_fn(in int4, out jsonb);
-- Update api.find_log_from_moorage_fn using the mobilitydb trajectory
CREATE OR REPLACE FUNCTION api.find_log_from_moorage_fn(_id integer, OUT geojson jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
        moorage_rec record;
        _geojson jsonb;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> find_log_from_moorage_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Gather moorage details
        SELECT * INTO moorage_rec
            FROM api.moorages m
            WHERE m.id = _id;
        -- Find all log from and to moorage geopoint within 100m
        SELECT jsonb_agg(api.export_logbook_geojson_linestring_trip_fn(id)::JSON->'features') INTO _geojson
            FROM api.logbook l
            WHERE ST_DWithin(
                    Geography(ST_MakePoint(l._from_lng, l._from_lat)),
                    moorage_rec.geog,
                    1000 -- in meters ?
                );
        -- Return a GeoJSON filter on LineString
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', _geojson ) INTO geojson;
    END;
$function$
;

COMMENT ON FUNCTION api.find_log_from_moorage_fn(in int4, out jsonb) IS 'Find all log from moorage geopoint within 100m';

-- DROP FUNCTION api.find_log_to_moorage_fn(in int4, out jsonb);
-- Update api.find_log_to_moorage_fn using the mobilitydb trajectory
CREATE OR REPLACE FUNCTION api.find_log_to_moorage_fn(_id integer, OUT geojson jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
        moorage_rec record;
        _geojson jsonb;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> find_log_from_moorage_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Gather moorage details
        SELECT * INTO moorage_rec
            FROM api.moorages m
            WHERE m.id = _id;
        -- Find all log from and to moorage geopoint within 100m
        SELECT jsonb_agg(api.export_logbook_geojson_linestring_trip_fn(id)::JSON->'features') INTO _geojson
            FROM api.logbook l
            WHERE ST_DWithin(
                    Geography(ST_MakePoint(l._to_lng, l._to_lat)),
                    moorage_rec.geog,
                    1000 -- in meters ?
                );
        -- Return a GeoJSON filter on LineString
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', _geojson ) INTO geojson;
    END;
$function$
;

COMMENT ON FUNCTION api.find_log_to_moorage_fn(in int4, out jsonb) IS 'Find all log to moorage geopoint within 100m';

-- DROP FUNCTION api.delete_logbook_fn(int4);
-- Update api.delete_logbook_fn to delete moorage dependency using mobilitydb
CREATE OR REPLACE FUNCTION api.delete_logbook_fn(_id integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
    DECLARE
        logbook_rec record;
        previous_stays_id numeric;
        current_stays_departed text;
        current_stays_id numeric;
        current_stays_active boolean;
       BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> delete_logbook_fn invalid input %', _id;
            RETURN FALSE;
        END IF;
        -- Get the logbook record with all necessary fields exist
        SELECT * INTO logbook_rec
            FROM api.logbook
            WHERE id = _id;
        -- Ensure the query is successful
        IF logbook_rec.vessel_id IS NULL THEN
            RAISE WARNING '-> delete_logbook_fn invalid logbook %', _id;
            RETURN FALSE;
        END IF;
        -- Update logbook
        UPDATE api.logbook l
            SET notes = 'mark for deletion'
            WHERE l.vessel_id = current_setting('vessel.id', false)
                AND id = logbook_rec.id;
        -- Update metrics status to moored
        UPDATE api.metrics
            SET status = 'moored'
            WHERE time >= logbook_rec._from_time::TIMESTAMPTZ
                AND time <= logbook_rec._to_time::TIMESTAMPTZ
                AND vessel_id = current_setting('vessel.id', false);
        -- Get related stays
        SELECT id,departed,active INTO current_stays_id,current_stays_departed,current_stays_active
            FROM api.stays s
            WHERE s.vessel_id = current_setting('vessel.id', false)
                AND s.arrived = logbook_rec._to_time;
        -- Update related stays
        UPDATE api.stays s
            SET notes = 'mark for deletion'
            WHERE s.vessel_id = current_setting('vessel.id', false)
                AND s.arrived = logbook_rec._to_time;
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
        RAISE WARNING '-> delete_logbook_fn delete logbook [%]', logbook_rec.id;
        DELETE FROM api.stays WHERE id = current_stays_id;
        RAISE WARNING '-> delete_logbook_fn delete stays [%]', current_stays_id;
        /* Deprecated, remove moorage reference
        -- Clean up, Subtract (-1) moorages ref count
        UPDATE api.moorages
            SET reference_count = reference_count - 1
            WHERE vessel_id = current_setting('vessel.id', false)
                AND id = previous_stays_id;
        */
        RETURN TRUE;
    END;
$function$
;

COMMENT ON FUNCTION api.delete_logbook_fn(int4) IS 'Delete a logbook and dependency stay';

-- DROP FUNCTION public.qgis_bbox_py_fn(in text, in numeric, in numeric, in numeric, in bool, out text);
-- Update public.qgis_bbox_py_fn to use mobilitydb trajectory
CREATE OR REPLACE FUNCTION public.qgis_bbox_py_fn(vessel_id text DEFAULT NULL::text, log_id numeric DEFAULT NULL::numeric, width numeric DEFAULT 1080, height numeric DEFAULT 566, scaleout boolean DEFAULT true, OUT bbox text)
 RETURNS text
 LANGUAGE plpython3u
AS $function$
	log_extent = None
	if not vessel_id and not log_id:
	    plpy.error('Error qgis_bbox_py invalid input vessel_id [{}], log_id [{}]'.format(vessel_id, log_id))
	# If we have a vessel_id then it is logs image map
	if vessel_id:
		# Use the shared cache to avoid preparing the log extent
		if vessel_id in SD:
			plan = SD[vessel_id]
		# A prepared statement from Python
		else:
			plan = plpy.prepare("WITH merged AS ( SELECT ST_Union(trajectory(trip)::geometry) AS merged_geometry FROM api.logbook WHERE vessel_id = $1 ) SELECT ST_Extent(ST_Transform(merged_geometry, 3857))::TEXT FROM merged;", ["text"])
			SD[vessel_id] = plan
		# Execute the statement with the log extent param and limit to 1 result
		rv = plpy.execute(plan, [vessel_id], 1)
		log_extent = rv[0]['st_extent']
    # Else we have a log_id then it is single log image map
	else:
		# Use the shared cache to avoid preparing the log extent
		if log_id in SD:
			plan = SD[log_id]
		# A prepared statement from Python
		else:
			plan = plpy.prepare("SELECT ST_Extent(ST_Transform(trajectory(trip)::geometry, 3857)) FROM api.logbook WHERE id = $1::NUMERIC", ["text"])
			SD[log_id] = plan
		# Execute the statement with the log extent param and limit to 1 result
		rv = plpy.execute(plan, [log_id], 1)
		log_extent = rv[0]['st_extent']

	# Extract extent
	def parse_extent_from_db(extent_raw):
	    # Parse the extent_raw to extract coordinates
	    extent = extent_raw.replace('BOX(', '').replace(')', '').split(',')
	    min_x, min_y = map(float, extent[0].split())
	    max_x, max_y = map(float, extent[1].split())
	    return min_x, min_y, max_x, max_y
	
	# ZoomOut from linestring extent 
	def apply_scale_factor(extent, scale_factor=1.125):
	    min_x, min_y, max_x, max_y = extent
	    center_x = (min_x + max_x) / 2
	    center_y = (min_y + max_y) / 2
	    width = max_x - min_x
	    height = max_y - min_y
	    new_width = width * scale_factor
	    new_height = height * scale_factor
	    scaled_extent = (
	        round(center_x - new_width / 2),
	        round(center_y - new_height / 2),
	        round(center_x + new_width / 2),
	        round(center_y + new_height / 2),
	    )
	    return scaled_extent

	def adjust_bbox_to_fixed_size(scaled_extent, fixed_width, fixed_height):
	    min_x, min_y, max_x, max_y = scaled_extent
	    bbox_width = float(max_x - min_x)
	    bbox_height = float(max_y - min_y)
	    bbox_aspect_ratio = float(bbox_width / bbox_height)
	    image_aspect_ratio = float(fixed_width / fixed_height)
	
	    if bbox_aspect_ratio > image_aspect_ratio:
	        # Adjust height to match aspect ratio
	        new_bbox_height = bbox_width / image_aspect_ratio
	        height_diff = new_bbox_height - bbox_height
	        min_y -= height_diff / 2
	        max_y += height_diff / 2
	    else:
	        # Adjust width to match aspect ratio
	        new_bbox_width = bbox_height * image_aspect_ratio
	        width_diff = new_bbox_width - bbox_width
	        min_x -= width_diff / 2
	        max_x += width_diff / 2

	    adjusted_extent = (min_x, min_y, max_x, max_y)
	    return adjusted_extent

	if (not vessel_id and not log_id) or not log_extent:
	    plpy.error('Failed to get sql qgis_bbox_py vessel_id [{}], log_id [{}], extent [{}]'.format(vessel_id, log_id, log_extent))
	#plpy.notice('qgis_bbox_py log_id [{}], extent [{}]'.format(log_id, log_extent))
	# Parse extent and apply ZoomOut scale factor
	if scaleout:
		scaled_extent = apply_scale_factor(parse_extent_from_db(log_extent))
	else:
		scaled_extent = parse_extent_from_db(log_extent)
	#plpy.notice('qgis_bbox_py log_id [{}], scaled_extent [{}]'.format(log_id, scaled_extent))
	fixed_width = width # default 1080
	fixed_height = height # default 566
	adjusted_extent = adjust_bbox_to_fixed_size(scaled_extent, fixed_width, fixed_height)
	#plpy.notice('qgis_bbox_py log_id [{}], adjusted_extent [{}]'.format(log_id, adjusted_extent))
	min_x, min_y, max_x, max_y = adjusted_extent
	return f"{min_x},{min_y},{max_x},{max_y}"
$function$
;

COMMENT ON FUNCTION public.qgis_bbox_py_fn(in text, in numeric, in numeric, in numeric, in bool, out text) IS 'Generate the BBOX base on log extent and adapt extent to the image size for QGIS Server';

-- DROP FUNCTION public.qgis_bbox_trip_py_fn(in text, out text);
-- Update public.qgis_bbox_trip_py_fn to use mobilitydb trajectory
CREATE OR REPLACE FUNCTION public.qgis_bbox_trip_py_fn(_str_to_parse text DEFAULT NULL::text, OUT bbox text)
 RETURNS text
 LANGUAGE plpython3u
AS $function$
	#plpy.notice('qgis_bbox_trip_py_fn _str_to_parse [{}]'.format(_str_to_parse))
	if not _str_to_parse or '_' not in _str_to_parse:
	    plpy.error('Error qgis_bbox_py invalid input _str_to_parse [{}]'.format(_str_to_parse))
	vessel_id, log_id, log_end = _str_to_parse.split('_')
	width = 1080
	height = 566
	scaleout = True
	log_extent = None
	# If we have a vessel_id then it is full logs image map
	if vessel_id and log_end is None:
		# Use the shared cache to avoid preparing the log extent
		if vessel_id in SD:
			plan = SD[vessel_id]
		# A prepared statement from Python
		else:
			plan = plpy.prepare("WITH merged AS ( SELECT ST_Union(trajectory(trip)::geometry) AS merged_geometry FROM api.logbook WHERE vessel_id = $1 ) SELECT ST_Extent(ST_Transform(merged_geometry, 3857))::TEXT FROM merged;", ["text"])
			SD[vessel_id] = plan
		# Execute the statement with the log extent param and limit to 1 result
		rv = plpy.execute(plan, [vessel_id], 1)
		log_extent = rv[0]['st_extent']
	# If we have a vessel_id and a log_end then it is subset logs image map
	elif vessel_id and log_end:
		# Use the shared cache to avoid preparing the log extent
		shared_cache = vessel_id + str(log_id) + str(log_end)
		if shared_cache in SD:
			plan = SD[shared_cache]
		# A prepared statement from Python
		else:
			plan = plpy.prepare("WITH merged AS ( SELECT ST_Union(trajectory(trip)::geometry) AS merged_geometry FROM api.logbook WHERE vessel_id = $1 and id >= $2::NUMERIC and id <= $3::NUMERIC) SELECT ST_Extent(ST_Transform(merged_geometry, 3857))::TEXT FROM merged;", ["text","text","text"])
			SD[shared_cache] = plan
		# Execute the statement with the log extent param and limit to 1 result
		rv = plpy.execute(plan, [vessel_id,log_id,log_end], 1)
		log_extent = rv[0]['st_extent']
    # Else we have a log_id then it is single log image map
	else :
		# Use the shared cache to avoid preparing the log extent
		if log_id in SD:
			plan = SD[log_id]
		# A prepared statement from Python
		else:
			plan = plpy.prepare("SELECT ST_Extent(ST_Transform(trajectory(trip)::geometry, 3857)) FROM api.logbook WHERE id = $1::NUMERIC", ["text"])
			SD[log_id] = plan
		# Execute the statement with the log extent param and limit to 1 result
		rv = plpy.execute(plan, [log_id], 1)
		log_extent = rv[0]['st_extent']

	# Extract extent
	def parse_extent_from_db(extent_raw):
	    # Parse the extent_raw to extract coordinates
	    extent = extent_raw.replace('BOX(', '').replace(')', '').split(',')
	    min_x, min_y = map(float, extent[0].split())
	    max_x, max_y = map(float, extent[1].split())
	    return min_x, min_y, max_x, max_y
	
	# ZoomOut from linestring extent 
	def apply_scale_factor(extent, scale_factor=1.125):
	    min_x, min_y, max_x, max_y = extent
	    center_x = (min_x + max_x) / 2
	    center_y = (min_y + max_y) / 2
	    width = max_x - min_x
	    height = max_y - min_y
	    new_width = width * scale_factor
	    new_height = height * scale_factor
	    scaled_extent = (
	        round(center_x - new_width / 2),
	        round(center_y - new_height / 2),
	        round(center_x + new_width / 2),
	        round(center_y + new_height / 2),
	    )
	    return scaled_extent

	def adjust_bbox_to_fixed_size(scaled_extent, fixed_width, fixed_height):
	    min_x, min_y, max_x, max_y = scaled_extent
	    bbox_width = float(max_x - min_x)
	    bbox_height = float(max_y - min_y)
	    bbox_aspect_ratio = float(bbox_width / bbox_height)
	    image_aspect_ratio = float(fixed_width / fixed_height)
	
	    if bbox_aspect_ratio > image_aspect_ratio:
	        # Adjust height to match aspect ratio
	        new_bbox_height = bbox_width / image_aspect_ratio
	        height_diff = new_bbox_height - bbox_height
	        min_y -= height_diff / 2
	        max_y += height_diff / 2
	    else:
	        # Adjust width to match aspect ratio
	        new_bbox_width = bbox_height * image_aspect_ratio
	        width_diff = new_bbox_width - bbox_width
	        min_x -= width_diff / 2
	        max_x += width_diff / 2

	    adjusted_extent = (min_x, min_y, max_x, max_y)
	    return adjusted_extent

	if not log_extent:
	    plpy.error('Failed to get sql qgis_bbox_trip_py_fn vessel_id [{}], log_id [{}], extent [{}]'.format(vessel_id, log_id, log_extent))
	#plpy.notice('qgis_bbox_trip_py_fn log_id [{}], extent [{}]'.format(log_id, log_extent))
	# Parse extent and apply ZoomOut scale factor
	if scaleout:
		scaled_extent = apply_scale_factor(parse_extent_from_db(log_extent))
	else:
		scaled_extent = parse_extent_from_db(log_extent)
	#plpy.notice('qgis_bbox_trip_py_fn log_id [{}], scaled_extent [{}]'.format(log_id, scaled_extent))
	fixed_width = width # default 1080
	fixed_height = height # default 566
	adjusted_extent = adjust_bbox_to_fixed_size(scaled_extent, fixed_width, fixed_height)
	#plpy.notice('qgis_bbox_trip_py_fn log_id [{}], adjusted_extent [{}]'.format(log_id, adjusted_extent))
	min_x, min_y, max_x, max_y = adjusted_extent
	return f"{min_x},{min_y},{max_x},{max_y}"
$function$
;

COMMENT ON FUNCTION public.qgis_bbox_trip_py_fn(in text, out text) IS 'Generate the BBOX base on trip extent and adapt extent to the image size for QGIS Server';

-- DROP FUNCTION api.stats_stays_fn(in text, in text, out json);
-- Update api.stats_stays_fn, due to reference_count and stay_duration columns removal
CREATE OR REPLACE FUNCTION api.stats_stays_fn(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT stats json)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
    DECLARE
        _start_date TIMESTAMPTZ DEFAULT '1970-01-01';
        _end_date TIMESTAMPTZ DEFAULT NOW();
    BEGIN
        IF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            RAISE NOTICE '--> stats_stays_fn, custom filter result stats by date [%]', start_date;
            _start_date := start_date::TIMESTAMPTZ;
            _end_date := end_date::TIMESTAMPTZ;
        END IF;
        RAISE NOTICE '--> stats_stays_fn, _start_date [%], _end_date [%]', _start_date, _end_date;
        WITH
            stays AS (
                SELECT distinct(moorage_id) as moorage_id, sum(duration) as duration, count(id) as reference_count
                    FROM api.stays s
                    WHERE arrived >= _start_date::TIMESTAMPTZ
                        AND departed <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
                    group by moorage_id
                    order by moorage_id
            ),
            moorages AS (
                SELECT m.id, m.home_flag, mv.stays_count, mv.stays_sum_duration, m.stay_code, m.country, s.duration, s.reference_count
                    FROM api.moorages m, stays s, api.moorage_view mv
                    WHERE s.moorage_id = m.id
                    and mv.id = m.id
                    order by moorage_id
            ),
            home_ports AS (
                select count(*) as home_ports from api.moorages m where home_flag is true
            ),
            unique_moorages AS (
                select count(*) as unique_moorages from api.moorages m
            ),
            time_at_home_ports AS (
                select sum(m.stays_sum_duration) as time_at_home_ports from api.moorage_view m where home is true
            ),
            sum_stay_duration AS (
                select sum(m.stays_sum_duration) as sum_stay_duration from api.moorage_view m where home is false
            ),
            time_spent_away_arr AS (
                select m.default_stay_id as stay_code,sum(m.stays_sum_duration) as stay_duration from api.moorage_view m where home is false group by m.default_stay_id order by m.default_stay_id
            ),
            time_spent_arr as (
                select jsonb_agg(t.*) as time_spent_away_arr from time_spent_away_arr t
            ),
            time_spent_away AS (
                select sum(m.stays_sum_duration) as time_spent_away from api.moorage_view m where home is false
            ),
            time_spent as (
                select jsonb_agg(t.*) as time_spent_away from time_spent_away t
            )
        -- Return a JSON
        SELECT jsonb_build_object(
            'home_ports', home_ports.home_ports,
            'unique_moorages', unique_moorages.unique_moorages,
            'time_at_home_ports', time_at_home_ports.time_at_home_ports,
            'time_spent_away', time_spent_away.time_spent_away,
            'time_spent_away_arr', time_spent_arr.time_spent_away_arr) INTO stats
            FROM home_ports, unique_moorages,
                        time_at_home_ports, sum_stay_duration, time_spent_away, time_spent_arr;
    END;
$function$
;

COMMENT ON FUNCTION api.stats_stays_fn(in text, in text, out json) IS 'Stays/Moorages stats by date';

-- DROP FUNCTION api.stats_fn(in text, in text, out jsonb);
-- Update api.stats_fn, due to reference_count and stay_duration columns removal
CREATE OR REPLACE FUNCTION api.stats_fn(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT stats jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
        _start_date TIMESTAMPTZ DEFAULT '1970-01-01';
        _end_date TIMESTAMPTZ DEFAULT NOW();
        stats_logs JSONB;
        stats_moorages JSONB;
        stats_logs_topby JSONB;
        stats_moorages_topby JSONB;
    BEGIN
        IF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            RAISE WARNING '--> stats_fn, filter result stats by date [%]', start_date;
            _start_date := start_date::TIMESTAMPTZ;
            _end_date := end_date::TIMESTAMPTZ;
        END IF;
        RAISE NOTICE '--> stats_fn, _start_date [%], _end_date [%]', _start_date, _end_date;
        -- Get global logs statistics
        SELECT api.stats_logs_fn(_start_date::TEXT, _end_date::TEXT) INTO stats_logs;
        -- Get global stays/moorages statistics
        SELECT api.stats_stays_fn(_start_date::TEXT, _end_date::TEXT) INTO stats_moorages;
        -- Get Top 5 trips statistics
        WITH
            logs_view AS (
                SELECT id,avg_speed,max_speed,max_wind_speed,distance,duration
                    FROM api.logbook l
                    WHERE _from_time >= _start_date::TIMESTAMPTZ
                        AND _to_time <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
            ),
            logs_top_avg_speed AS (
                SELECT id,avg_speed FROM logs_view
                GROUP BY id,avg_speed
                ORDER BY avg_speed DESC
                LIMIT 5),
            logs_top_speed AS (
                SELECT id,max_speed FROM logs_view
                WHERE max_speed IS NOT NULL
                GROUP BY id,max_speed
                ORDER BY max_speed DESC
                LIMIT 5),
            logs_top_wind_speed AS (
                SELECT id,max_wind_speed FROM logs_view
				WHERE max_wind_speed IS NOT NULL
                GROUP BY id,max_wind_speed
                ORDER BY max_wind_speed DESC
                LIMIT 5),
            logs_top_distance AS (
                SELECT id FROM logs_view
                GROUP BY id,distance
                ORDER BY distance DESC
                LIMIT 5),
            logs_top_duration AS (
                SELECT id FROM logs_view
                GROUP BY id,duration
                ORDER BY duration DESC
                LIMIT 5)
		-- Stats Top Logs
        SELECT jsonb_build_object(
            'stats_logs', stats_logs,
            'stats_moorages', stats_moorages,
            'logs_top_speed', (SELECT jsonb_agg(logs_top_speed.*) FROM logs_top_speed),
            'logs_top_avg_speed', (SELECT jsonb_agg(logs_top_avg_speed.*) FROM logs_top_avg_speed),
            'logs_top_wind_speed', (SELECT jsonb_agg(logs_top_wind_speed.*) FROM logs_top_wind_speed),
            'logs_top_distance', (SELECT jsonb_agg(logs_top_distance.id) FROM logs_top_distance),
            'logs_top_duration', (SELECT jsonb_agg(logs_top_duration.id) FROM logs_top_duration)
         ) INTO stats;
		-- Stats top 5 moorages statistics
        WITH
            stays AS (
                SELECT distinct(moorage_id) as moorage_id, sum(duration) as duration, count(id) as reference_count
                    FROM api.stays s
                    WHERE s.arrived >= _start_date::TIMESTAMPTZ
                        AND s.departed <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
                    group by s.moorage_id
                    order by s.moorage_id
            ),
            moorages AS (
                SELECT m.id, m.home_flag, mv.stays_count, mv.stays_sum_duration, m.stay_code, m.country, s.duration as dur, s.reference_count as ref_count
                    FROM api.moorages m, stays s, api.moorage_view mv
                    WHERE s.moorage_id = m.id
                        AND mv.id = m.id
                    order by s.moorage_id
            ),
            moorages_top_arrivals AS (
                SELECT id,ref_count FROM moorages
                GROUP BY id,ref_count
                ORDER BY ref_count DESC
                LIMIT 5),
            moorages_top_duration AS (
                SELECT id,dur FROM moorages
                GROUP BY id,dur
                ORDER BY dur DESC
                LIMIT 5),
            moorages_countries AS (
                SELECT DISTINCT(country) FROM moorages
                WHERE country IS NOT NULL AND country <> 'unknown'
                GROUP BY country
                ORDER BY country DESC
                LIMIT 5)
		SELECT stats || jsonb_build_object(
		    'moorages_top_arrivals', (SELECT jsonb_agg(moorages_top_arrivals) FROM moorages_top_arrivals),
		    'moorages_top_duration', (SELECT jsonb_agg(moorages_top_duration) FROM moorages_top_duration),
		    'moorages_top_countries', (SELECT jsonb_agg(moorages_countries.country) FROM moorages_countries)
		 ) INTO stats;
    END;
$function$
;

COMMENT ON FUNCTION api.stats_fn(in text, in text, out jsonb) IS 'Statistic by date for Logs and Moorages and Stays';

DROP VIEW IF EXISTS api.log_view;
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
    api.export_logbook_geojson_trip_fn(id) AS geojson,
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

-- Update delete_trip_entry_fn, delete temporal sequence into a trip
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
            trip_status = deleteTime(l.trip_status, update_string),
            trip_depth = deleteTime(l.trip_depth, update_string),
            trip_batt_charge = deleteTime(l.trip_batt_charge, update_string),
            trip_batt_voltage = deleteTime(l.trip_batt_voltage, update_string),
            trip_temp_water = deleteTime(l.trip_temp_water, update_string),
            trip_temp_out = deleteTime(l.trip_temp_out, update_string),
            trip_pres_out = deleteTime(l.trip_pres_out, update_string),
            trip_hum_out = deleteTime(l.trip_hum_out, update_string)
        WHERE id = _id;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION api.delete_trip_entry_fn IS 'Delete at a specific time a temporal sequence for all trip_* column from a logbook';

-- Update api role SQL connection to 40
ALTER ROLE authenticator WITH NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 40 LOGIN;
ALTER ROLE api_anonymous WITH NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 40 LOGIN;

-- Allow users to update certain columns on specific TABLES on API schema
GRANT UPDATE (name, _from, _to, notes, trip_notes, trip, trip_cog, trip_sog, trip_twa, trip_tws, trip_twd, trip_status, trip_depth, trip_batt_charge, trip_batt_voltage, trip_temp_water, trip_temp_out, trip_pres_out, trip_hum_out) ON api.logbook TO user_role;

-- Refresh user_role permissions
GRANT SELECT ON TABLE api.log_view TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.export_logbooks_geojson_linestring_trips_fn to api_anonymous;
GRANT EXECUTE ON FUNCTION api.export_logbooks_geojson_point_trips_fn to api_anonymous;
--GRANT EXECUTE ON FUNCTION api.logbook_update_geojson_trip_fn to api_anonymous;
GRANT EXECUTE ON FUNCTION api.export_logbook_geojson_trip_fn to api_anonymous;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO api_anonymous;
GRANT SELECT ON TABLE api.log_view TO grafana;
GRANT SELECT ON TABLE api.moorages_view TO grafana;
GRANT SELECT ON TABLE api.moorage_view TO grafana;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO qgis_role;

-- Update version
UPDATE public.app_settings
	SET value='0.8.1'
	WHERE "name"='app.version';

\c postgres
UPDATE cron.job SET username = 'scheduler'; --  Update to scheduler, pending process_queue update
UPDATE cron.job SET username = 'username' WHERE jobname = 'cron_vacuum'; -- Update to superuser for vacuum permissions
UPDATE cron.job SET username = 'username' WHERE jobname = 'job_run_details_cleanup';
