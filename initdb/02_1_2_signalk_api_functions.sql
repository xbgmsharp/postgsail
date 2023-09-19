
-- connect to the DB
\c signalk

---------------------------------------------------------------------------
-- API helper functions
--
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Functions API schema
-- Timelapse - replay logs
DROP FUNCTION IF EXISTS api.timelapse_fn;
CREATE OR REPLACE FUNCTION api.timelapse_fn(
    IN start_log INTEGER DEFAULT NULL,
    IN end_log INTEGER DEFAULT NULL,
    IN start_date TEXT DEFAULT NULL,
    IN end_date TEXT DEFAULT NULL,
    OUT geojson JSON) RETURNS JSON AS $timelapse$
    DECLARE
        _geojson jsonb;
    BEGIN
        -- TODO using jsonb pgsql function instead of python
        IF start_log IS NOT NULL AND public.isnumeric(start_log::text) AND public.isnumeric(end_log::text) THEN
            SELECT jsonb_agg(track_geojson->'features') INTO _geojson
                FROM api.logbook
                WHERE id >= start_log
                    AND id <= end_log
                    AND track_geojson IS NOT NULL;
            --raise WARNING 'by log _geojson %' , _geojson;
        ELSIF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            SELECT jsonb_agg(track_geojson->'features') INTO _geojson
                FROM api.logbook
                WHERE _from_time >= start_log::TIMESTAMP WITHOUT TIME ZONE
                    AND _to_time <= end_date::TIMESTAMP WITHOUT TIME ZONE + interval '23 hours 59 minutes'
                    AND track_geojson IS NOT NULL;
            --raise WARNING 'by date _geojson %' , _geojson;
        ELSE
            SELECT jsonb_agg(track_geojson->'features') INTO _geojson
                FROM api.logbook
                WHERE track_geojson IS NOT NULL;
            --raise WARNING 'all result _geojson %' , _geojson;
        END IF;
        -- Return a GeoJSON filter on Point
        -- result _geojson [null, null]
        --raise WARNING 'result _geojson %' , _geojson;
        SELECT json_build_object(
            'type', 'FeatureCollection',
            'features', public.geojson_py_fn(_geojson, 'LineString'::TEXT) ) INTO geojson;
    END;
$timelapse$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.timelapse_fn
    IS 'Export to geojson feature point with Time and courseOverGroundTrue properties';

-- export_logbook_geojson_fn
DROP FUNCTION IF EXISTS api.export_logbook_geojson_fn;
CREATE FUNCTION api.export_logbook_geojson_fn(IN _id integer, OUT geojson JSON) RETURNS JSON AS $export_logbook_geojson$
-- validate with geojson.io
    DECLARE
        logbook_rec record;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> export_logbook_geojson_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Gather log details
        SELECT * INTO logbook_rec
            FROM api.logbook WHERE id = _id;
        -- Ensure the query is successful
        IF logbook_rec.vessel_id IS NULL THEN
            RAISE WARNING '-> export_logbook_geojson_fn invalid logbook %', _id;
            RETURN;
        END IF;
        geojson := logbook_rec.track_geojson;
    END;
$export_logbook_geojson$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.export_logbook_geojson_fn
    IS 'Export a log entry to geojson feature linestring and multipoint';

-- Generate GPX XML file output
-- https://opencpn.org/OpenCPN/info/gpxvalidation.html
--
DROP FUNCTION IF EXISTS api.export_logbook_gpx_fn;
CREATE OR REPLACE FUNCTION api.export_logbook_gpx_fn(IN _id INTEGER, OUT gpx XML) RETURNS pg_catalog.xml
AS $export_logbook_gpx$
    DECLARE
        logbook_rec record;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> export_logbook_gpx_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Gather log details
        SELECT * INTO logbook_rec
            FROM api.logbook WHERE id = _id;
        -- Ensure the query is successful
        IF logbook_rec.vessel_id IS NULL THEN
            RAISE WARNING '-> export_logbook_gpx_fn invalid logbook %', _id;
            RETURN;
        END IF;
        gpx := logbook_rec.track_gpx;
    END;
$export_logbook_gpx$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.export_logbook_gpx_fn
    IS 'Export a log entry to GPX XML format';

-- Find all log from and to moorage geopoint within 100m
DROP FUNCTION IF EXISTS api.find_log_from_moorage_fn;
CREATE OR REPLACE FUNCTION api.find_log_from_moorage_fn(IN _id INTEGER, OUT geojson JSON) RETURNS JSON AS $find_log_from_moorage$
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
        SELECT jsonb_agg(l.track_geojson->'features') INTO _geojson
            FROM api.logbook l
            WHERE ST_DWithin(
                    Geography(ST_MakePoint(l._from_lng, l._from_lat)),
                    moorage_rec.geog,
                    1000 -- in meters ?
                );
        -- Return a GeoJSON filter on LineString
        SELECT json_build_object(
            'type', 'FeatureCollection',
            'features', public.geojson_py_fn(_geojson, 'Point'::TEXT) ) INTO geojson;
    END;
$find_log_from_moorage$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.find_log_from_moorage_fn
    IS 'Find all log from moorage geopoint within 100m';

DROP FUNCTION IF EXISTS api.find_log_to_moorage_fn;
CREATE OR REPLACE FUNCTION api.find_log_to_moorage_fn(IN _id INTEGER, OUT geojson JSON) RETURNS JSON AS $find_log_to_moorage$
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
        SELECT jsonb_agg(l.track_geojson->'features') INTO _geojson
            FROM api.logbook l
            WHERE ST_DWithin(
                    Geography(ST_MakePoint(l._to_lng, l._to_lat)),
                    moorage_rec.geog,
                    1000 -- in meters ?
                );
        -- Return a GeoJSON filter on LineString
        SELECT json_build_object(
            'type', 'FeatureCollection',
            'features', public.geojson_py_fn(_geojson, 'Point'::TEXT) ) INTO geojson;
    END;
$find_log_to_moorage$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.find_log_to_moorage_fn
    IS 'Find all log to moorage geopoint within 100m';

-- Find all stay within 100m of moorage geopoint
DROP FUNCTION IF EXISTS api.find_stay_from_moorage_fn;
CREATE OR REPLACE FUNCTION api.find_stay_from_moorage_fn(IN _id INTEGER) RETURNS void AS $find_stay_from_moorage$
    DECLARE
        moorage_rec record;
        stay_rec record;
    BEGIN
        -- If _id is is not NULL and > 0
        SELECT * INTO moorage_rec
            FROM api.moorages m 
            WHERE m.id = _id;
        -- find all log from and to moorage geopoint within 100m
        --RETURN QUERY
            SELECT s.id,s.arrived,s.departed,s.duration,sa.description
                FROM api.stays s, api.stays_at sa
                WHERE ST_DWithin(
                        s.geog,
                        moorage_rec.geog,
                        100 -- in meters ?
                    )
                    AND departed IS NOT NULL
                    AND s.name IS NOT NULL
                    AND s.stay_code = sa.stay_code
                ORDER BY s.arrived DESC;
    END;
$find_stay_from_moorage$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.find_stay_from_moorage_fn
    IS 'Find all stay within 100m of moorage geopoint';

-- trip_in_progress_fn
DROP FUNCTION IF EXISTS public.trip_in_progress_fn;
CREATE FUNCTION public.trip_in_progress_fn(IN _vessel_id TEXT) RETURNS INT AS $trip_in_progress$
    DECLARE
        logbook_id INT := NULL;
    BEGIN
        SELECT id INTO logbook_id
            FROM api.logbook l
            WHERE l.vessel_id IS NOT NULL
                AND l.vessel_id = _vessel_id
                AND active IS true
            LIMIT 1;
        RETURN logbook_id;
    END;
$trip_in_progress$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.trip_in_progress_fn
    IS 'trip_in_progress';

-- stay_in_progress_fn
DROP FUNCTION IF EXISTS public.stay_in_progress_fn;
CREATE FUNCTION public.stay_in_progress_fn(IN _vessel_id TEXT) RETURNS INT AS $stay_in_progress$
    DECLARE
        stay_id INT := NULL;
    BEGIN
        SELECT id INTO stay_id
                FROM api.stays s
                WHERE s.vessel_id IS NOT NULL
                    AND s.vessel_id = _vessel_id
                    AND active IS true
                LIMIT 1;
        RETURN stay_id;
    END;
$stay_in_progress$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.stay_in_progress_fn
    IS 'stay_in_progress';

-- logs_by_month_fn
DROP FUNCTION IF EXISTS api.logs_by_month_fn;
CREATE FUNCTION api.logs_by_month_fn(OUT charts JSONB) RETURNS JSONB AS $logs_by_month$
    DECLARE
        data JSONB;
    BEGIN
        -- Query logs by month
        SELECT json_object_agg(month,count) INTO data
            FROM (
                    SELECT
                        to_char(date_trunc('month', _from_time), 'MM') as month,
                        count(*) as count
                        FROM api.logbook
                        GROUP BY month
                        ORDER BY month
                ) AS t;
        -- Merge jsonb to get all 12 months
        SELECT '{"01": 0, "02": 0, "03": 0, "04": 0, "05": 0, "06": 0, "07": 0, "08": 0, "09": 0, "10": 0, "11": 0,"12": 0}'::jsonb ||
            data::jsonb INTO charts;
    END;
$logs_by_month$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.logs_by_month_fn
    IS 'logbook by month for web charts';

-- logs_by_day_fn
DROP FUNCTION IF EXISTS api.logs_by_day_fn;
CREATE FUNCTION api.logs_by_day_fn(OUT charts JSONB) RETURNS JSONB AS $logs_by_day$
    DECLARE
        data JSONB;
    BEGIN
        -- Query logs by day
        SELECT json_object_agg(day,count) INTO data
            FROM (
                    SELECT
                        to_char(date_trunc('day', _from_time), 'D') as day,
                        count(*) as count
                        FROM api.logbook
                        GROUP BY day
                        ORDER BY day
                ) AS t;
        -- Merge jsonb to get all 7 days
        SELECT '{"01": 0, "02": 0, "03": 0, "04": 0, "05": 0, "06": 0, "07": 0}'::jsonb ||
            data::jsonb INTO charts;
    END;
$logs_by_day$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.logs_by_day_fn
    IS 'logbook by day for web charts';

-- moorage_geojson_fn
DROP FUNCTION IF EXISTS api.export_moorages_geojson_fn;
CREATE FUNCTION api.export_moorages_geojson_fn(OUT geojson JSONB) RETURNS JSONB AS $export_moorages_geojson$
    DECLARE
    BEGIN
        SELECT json_build_object(
            'type', 'FeatureCollection',
            'features',
                ( SELECT
                    json_agg(ST_AsGeoJSON(m.*)::JSON) as moorages_geojson
                    FROM
                    ( SELECT
                        id,name,
                        EXTRACT(DAY FROM justify_hours ( stay_duration )) AS Total_Stay,
                        geog
                        FROM api.moorages
                        WHERE geog IS NOT NULL
                    ) AS m
                )
            ) INTO geojson;
    END;
$export_moorages_geojson$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.export_moorages_geojson_fn
    IS 'Export moorages as geojson';

DROP FUNCTION IF EXISTS api.export_moorages_gpx_fn;
CREATE FUNCTION api.export_moorages_gpx_fn() RETURNS pg_catalog.xml AS $export_moorages_gpx$
    DECLARE
    BEGIN
        -- Generate XML
        RETURN xmlelement(name gpx,
                    xmlattributes(  '1.1' as version,
                                    'PostgSAIL' as creator,
                                    'http://www.topografix.com/GPX/1/1' as xmlns,
                                    'http://www.opencpn.org' as "xmlns:opencpn",
                                    'https://iot.openplotter.cloud' as "xmlns:postgsail",
                                    'http://www.w3.org/2001/XMLSchema-instance' as "xmlns:xsi",
                                    'http://www.garmin.com/xmlschemas/GpxExtensions/v3' as "xmlns:gpxx",
                                    'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/GpxExtensions/v3 http://www8.garmin.com/xmlschemas/GpxExtensionsv3.xsd' as "xsi:schemaLocation"),
                    xmlagg(
                        xmlelement(name wpt, xmlattributes(m.latitude as lat, m.longitude as lon),
                            xmlelement(name name, m.name),
                            xmlelement(name time, 'TODO first seen'),
                            xmlelement(name desc,
                                concat('Last Stayed On: ', 'TODO last seen',
                                    E'\nTotal Stays: ', m.stay_duration,
                                    E'\nTotal Arrivals and Departures: ', m.reference_count,
                                    E'\nLink: ', concat('https://iot.openplotter.cloud/moorage/', m.id)),
                                    xmlelement(name "opencpn:guid", uuid_generate_v4())),
                            xmlelement(name sym, 'anchor'),
                            xmlelement(name type, 'WPT'),
                            xmlelement(name link, xmlattributes(concat('https://iot.openplotter.cloud/moorage/', m.id) as href),
                                                        xmlelement(name text, m.name)),
                            xmlelement(name extensions, xmlelement(name "postgsail:mooorage_id", 1),
                                                        xmlelement(name "postgsail:link", concat('https://iot.openplotter.cloud/moorage/', m.id)),
                                                        xmlelement(name "opencpn:guid", uuid_generate_v4()),
                                                        xmlelement(name "opencpn:viz", '1'),
                                                        xmlelement(name "opencpn:scale_min_max", xmlattributes(true as UseScale, 30000 as ScaleMin, 0 as ScaleMax)
                                                        ))))
                    )::pg_catalog.xml
            FROM api.moorages m
            WHERE geog IS NOT NULL;
    END;
$export_moorages_gpx$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.export_moorages_gpx_fn
    IS 'Export moorages as gpx';

----------------------------------------------------------------------------------------------
-- Statistics
DROP FUNCTION IF EXISTS api.stats_logs_fn;
CREATE OR REPLACE FUNCTION api.stats_logs_fn(
    IN start_date TEXT DEFAULT NULL,
    IN end_date TEXT DEFAULT NULL,
    OUT stats JSON) RETURNS JSON AS $stats_logs$
    DECLARE
        _start_date TIMESTAMP WITHOUT TIME ZONE DEFAULT '1970-01-01';
        _end_date TIMESTAMP WITHOUT TIME ZONE DEFAULT NOW();
    BEGIN
        IF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            RAISE WARNING '--> stats_fn, filter result stats by date [%]', start_date;
            _start_date := start_date::TIMESTAMP WITHOUT TIME ZONE;
            _end_date := end_date::TIMESTAMP WITHOUT TIME ZONE;
        END IF;
        RAISE NOTICE '--> stats_fn, _start_date [%], _end_date [%]', _start_date, _end_date;
        WITH
            meta AS (
                SELECT m.name FROM api.metadata m ),
            logs_view AS (
                SELECT *
                    FROM api.logbook l
                    WHERE _from_time >= _start_date::TIMESTAMP WITHOUT TIME ZONE
                        AND _to_time <= _end_date::TIMESTAMP WITHOUT TIME ZONE + interval '23 hours 59 minutes'
                ),
            first_date AS (
                SELECT _from_time as first_date from logs_view ORDER BY first_date ASC LIMIT 1
            ),
            last_date AS (
                SELECT _to_time as last_date from logs_view ORDER BY _to_time DESC LIMIT 1
            ),
            max_speed_id AS (
                SELECT id FROM logs_view WHERE max_speed = (SELECT max(max_speed) FROM logs_view) ),
            max_wind_speed_id AS (
                SELECT id FROM logs_view WHERE max_wind_speed = (SELECT max(max_wind_speed) FROM logs_view)),
            max_distance_id AS (
                SELECT id FROM logs_view WHERE distance = (SELECT max(distance) FROM logs_view)),
            max_duration_id AS (
                SELECT id FROM logs_view WHERE duration = (SELECT max(duration) FROM logs_view)),
            logs_stats AS (
                SELECT
                    count(*) AS count,
                    max(max_speed) AS max_speed,
                    max(max_wind_speed) AS max_wind_speed,
                    max(distance) AS max_distance,
                    sum(distance) AS sum_distance,
                    max(duration) AS max_duration,
                    sum(duration) AS sum_duration
                FROM logs_view l )
              --select * from logbook;
        -- Return a JSON
        SELECT jsonb_build_object(
            'name', meta.name,
            'first_date', first_date.first_date,
            'last_date', last_date.last_date,
            'max_speed_id', max_speed_id.id,
            'max_wind_speed_id', max_wind_speed_id.id,
            'max_duration_id', max_duration_id.id,
            'max_distance_id', max_distance_id.id)::jsonb || to_jsonb(logs_stats.*)::jsonb INTO stats
            FROM max_speed_id, max_wind_speed_id, max_distance_id, max_duration_id,
                logs_stats, meta, logs_view, first_date, last_date;
        -- TODO Add moorages
    END;
$stats_logs$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.stats_logs_fn
    IS 'Logs stats by date';

DROP FUNCTION IF EXISTS api.stats_stays_fn;
CREATE OR REPLACE FUNCTION api.stats_stays_fn(
    IN start_date TEXT DEFAULT NULL,
    IN end_date TEXT DEFAULT NULL,
    OUT stats JSON) RETURNS JSON AS $stats_stays$
    DECLARE
        _start_date TIMESTAMP WITHOUT TIME ZONE DEFAULT '1970-01-01';
        _end_date TIMESTAMP WITHOUT TIME ZONE DEFAULT NOW();
    BEGIN
        IF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            RAISE NOTICE '--> stats_stays_fn, custom filter result stats by date [%]', start_date;
            _start_date := start_date::TIMESTAMP WITHOUT TIME ZONE;
            _end_date := end_date::TIMESTAMP WITHOUT TIME ZONE;
        END IF;
        RAISE NOTICE '--> stats_stays_fn, _start_date [%], _end_date [%]', _start_date, _end_date;
        WITH
            moorages_log AS (
                SELECT s.id as stays_id, m.id as moorages_id, *
                    FROM api.stays s, api.moorages m
                    WHERE arrived >= _start_date::TIMESTAMP WITHOUT TIME ZONE
                        AND departed <= _end_date::TIMESTAMP WITHOUT TIME ZONE + interval '23 hours 59 minutes'
                        AND s.id = m.stay_id
                ),
	        home_ports AS (
	            select count(*) as home_ports from moorages_log m where home_flag is true
	        ),
	        unique_moorage AS (
	            select count(*) as unique_moorage from moorages_log m
	        ),
	        time_at_home_ports AS (
	            select sum(m.stay_duration) as time_at_home_ports from moorages_log m where home_flag is true
	        ),
	        sum_stay_duration AS (
	            select sum(m.stay_duration) as sum_stay_duration from moorages_log m where home_flag is false
            ),
            time_spent_away AS (
                select m.stay_code,sum(m.stay_duration) as stay_duration from api.moorages m where home_flag is false group by m.stay_code order by m.stay_code
            ),
            time_spent as (
                select jsonb_agg(t.*) as time_spent_away from time_spent_away t
            )
        -- Return a JSON
        SELECT jsonb_build_object(
            'home_ports', home_ports.home_ports,
            'unique_moorage', unique_moorage.unique_moorage,
            'time_at_home_ports', time_at_home_ports.time_at_home_ports,
            'sum_stay_duration', sum_stay_duration.sum_stay_duration,
            'time_spent_away', time_spent.time_spent_away) INTO stats
            FROM moorages_log, home_ports, unique_moorage,
                        time_at_home_ports, sum_stay_duration, time_spent;
        -- TODO Add moorages
    END;
$stats_stays$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.stats_stays_fn
    IS 'Stays/Moorages stats by date';