
-- connect to the DB
\c signalk

---------------------------------------------------------------------------
-- API helper functions
--
---------------------------------------------------------------------------

-- PostgREST Media Type Handlers
CREATE DOMAIN "text/xml" AS xml;
CREATE DOMAIN "application/geo+json" AS jsonb;
CREATE DOMAIN "application/gpx+xml" AS xml;
CREATE DOMAIN "application/vnd.google-earth.kml+xml" AS xml;

---------------------------------------------------------------------------
-- Functions API schema
-- Timelapse - replay logs
DROP FUNCTION IF EXISTS api.timelapse_fn;
CREATE OR REPLACE FUNCTION api.timelapse_fn(
    IN start_log INTEGER DEFAULT NULL,
    IN end_log INTEGER DEFAULT NULL,
    IN start_date TEXT DEFAULT NULL,
    IN end_date TEXT DEFAULT NULL,
    OUT geojson JSONB) RETURNS JSONB AS $timelapse$
    DECLARE
        _geojson jsonb;
    BEGIN
        -- Using sub query to force id order by
        -- Merge GIS track_geom into a GeoJSON MultiLineString
        IF start_log IS NOT NULL AND public.isnumeric(start_log::text) AND public.isnumeric(end_log::text) THEN
            WITH logbook as (
                SELECT track_geom
                    FROM api.logbook
                    WHERE id >= start_log
                        AND id <= end_log
                        AND track_geom IS NOT NULL
                    ORDER BY _from_time ASC
                )
            SELECT ST_AsGeoJSON(geo.*) INTO _geojson FROM (
                    SELECT ST_Collect(
                        ARRAY(
                            SELECT track_geom FROM logbook))
                ) as geo;
            --raise WARNING 'by log id _geojson %' , _geojson;
        ELSIF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            WITH logbook as (
                SELECT track_geom
                    FROM api.logbook
                    WHERE _from_time >= start_date::TIMESTAMPTZ
                        AND _to_time <= end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
                        AND track_geom IS NOT NULL
                    ORDER BY _from_time ASC
                )
            SELECT ST_AsGeoJSON(geo.*) INTO _geojson FROM (
                    SELECT ST_Collect(
                        ARRAY(
                            SELECT track_geom FROM logbook))
                ) as geo;
            --raise WARNING 'by date _geojson %' , _geojson;
        ELSE
            WITH logbook as (
                SELECT track_geom
                    FROM api.logbook
                    WHERE track_geom IS NOT NULL
                    ORDER BY _from_time ASC
                )
            SELECT ST_AsGeoJSON(geo.*) INTO _geojson FROM (
                    SELECT ST_Collect(
                        ARRAY(
                            SELECT track_geom FROM logbook))
                ) as geo;
            --raise WARNING 'all result _geojson %' , _geojson;
        END IF;
        -- Return a GeoJSON MultiLineString
        -- result _geojson [null, null]
        --raise WARNING 'result _geojson %' , _geojson;
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', ARRAY[_geojson] ) INTO geojson;
    END;
$timelapse$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.timelapse_fn
    IS 'Export all selected logs geometry `track_geom` to a geojson as MultiLineString with empty properties';

DROP FUNCTION IF EXISTS api.timelapse2_fn;
CREATE OR REPLACE FUNCTION api.timelapse2_fn(
    IN start_log INTEGER DEFAULT NULL,
    IN end_log INTEGER DEFAULT NULL,
    IN start_date TEXT DEFAULT NULL,
    IN end_date TEXT DEFAULT NULL,
    OUT geojson JSONB) RETURNS JSONB AS $timelapse2$
    DECLARE
        _geojson jsonb;
    BEGIN
        -- Using sub query to force id order by
        -- Merge GIS track_geom into a GeoJSON Points
        IF start_log IS NOT NULL AND public.isnumeric(start_log::text) AND public.isnumeric(end_log::text) THEN
            SELECT jsonb_agg(
                        jsonb_build_object('type', 'Feature',
                                            'properties', jsonb_build_object( 'notes', f->'properties'->>'notes'),
                                            'geometry', jsonb_build_object( 'coordinates', f->'geometry'->'coordinates', 'type', 'Point'))
                    ) INTO _geojson
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook
                    WHERE id >= start_log
                        AND id <= end_log
                        AND track_geojson IS NOT NULL
                    ORDER BY _from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'Point';
        ELSIF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            SELECT jsonb_agg(
                        jsonb_build_object('type', 'Feature',
                                            'properties', jsonb_build_object( 'notes', f->'properties'->>'notes'),
                                            'geometry', jsonb_build_object( 'coordinates', f->'geometry'->'coordinates', 'type', 'Point'))
                    ) INTO _geojson
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook
                    WHERE _from_time >= start_date::TIMESTAMPTZ
                        AND _to_time <= end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
                        AND track_geojson IS NOT NULL
                    ORDER BY _from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'Point';
        ELSE
            SELECT jsonb_agg(
                        jsonb_build_object('type', 'Feature',
                                            'properties', jsonb_build_object( 'notes', f->'properties'->>'notes'),
                                            'geometry', jsonb_build_object( 'coordinates', f->'geometry'->'coordinates', 'type', 'Point'))
                    ) INTO _geojson
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook
                    WHERE track_geojson IS NOT NULL
                    ORDER BY _from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'Point';
        END IF;
        -- Return a GeoJSON MultiLineString
        -- result _geojson [null, null]
        raise WARNING 'result _geojson %' , _geojson;
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', _geojson ) INTO geojson;
    END;
$timelapse2$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.timelapse2_fn
    IS 'Export all selected logs geometry `track_geom` to a geojson as points with notes properties';

-- export_logbook_geojson_fn
DROP FUNCTION IF EXISTS api.export_logbook_geojson_fn;
CREATE FUNCTION api.export_logbook_geojson_fn(IN _id integer, OUT geojson JSONB) RETURNS JSONB AS $export_logbook_geojson$
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
    IS 'Export a log entry to geojson with features LineString and Point';

-- Generate GPX XML file output
-- https://opencpn.org/OpenCPN/info/gpxvalidation.html
--
DROP FUNCTION IF EXISTS api.export_logbook_gpx_fn;
CREATE OR REPLACE FUNCTION api.export_logbook_gpx_fn(IN _id INTEGER) RETURNS "text/xml"
AS $export_logbook_gpx$
    DECLARE
        app_settings jsonb;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> export_logbook_gpx_fn invalid input %', _id;
            RETURN '';
        END IF;
        -- Gather url from app settings
        app_settings := get_app_url_fn();
        --RAISE DEBUG '-> logbook_update_gpx_fn app_settings %', app_settings;
        -- Generate GPX XML, extract Point features from geojson.
        RETURN xmlelement(name gpx,
                            xmlattributes(  '1.1' as version,
                                            'PostgSAIL' as creator,
                                            'http://www.topografix.com/GPX/1/1' as xmlns,
                                            'http://www.opencpn.org' as "xmlns:opencpn",
                                            app_settings->>'app.url' as "xmlns:postgsail",
                                            'http://www.w3.org/2001/XMLSchema-instance' as "xmlns:xsi",
                                            'http://www.garmin.com/xmlschemas/GpxExtensions/v3' as "xmlns:gpxx",
                                            'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/GpxExtensions/v3 http://www8.garmin.com/xmlschemas/GpxExtensionsv3.xsd' as "xsi:schemaLocation"),
                xmlelement(name metadata,
                    xmlelement(name link, xmlattributes(app_settings->>'app.url' as href),
                        xmlelement(name text, 'PostgSail'))),
                xmlelement(name trk,
                    xmlelement(name name, l.name),
                    xmlelement(name desc, l.notes),
                    xmlelement(name link, xmlattributes(concat(app_settings->>'app.url', '/log/', l.id) as href),
                                                xmlelement(name text, l.name)),
                    xmlelement(name extensions, xmlelement(name "postgsail:log_id", l.id),
                                                xmlelement(name "postgsail:link", concat(app_settings->>'app.url', '/log/', l.id)),
                                                xmlelement(name "opencpn:guid", uuid_generate_v4()),
                                                xmlelement(name "opencpn:viz", '1'),
                                                xmlelement(name "opencpn:start", l._from_time),
                                                xmlelement(name "opencpn:end", l._to_time)
                                                ),
                    xmlelement(name trkseg, xmlagg(
                                                xmlelement(name trkpt,
                                                    xmlattributes(features->'geometry'->'coordinates'->1 as lat, features->'geometry'->'coordinates'->0 as lon),
                                                        xmlelement(name time, features->'properties'->>'time')
                                                )))))::pg_catalog.xml
            FROM api.logbook l, jsonb_array_elements(track_geojson->'features') AS features
            WHERE features->'geometry'->>'type' = 'Point'
                AND l.id = _id
            GROUP BY l.name,l.notes,l.id;
          END;
$export_logbook_gpx$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.export_logbook_gpx_fn
    IS 'Export a log entry to GPX XML format';

-- Generate KML XML file output
-- https://developers.google.com/kml/documentation/kml_tut
-- TODO https://developers.google.com/kml/documentation/time#timespans
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
                                                xmlelement(name name, logbook_rec.name),
                                                xmlelement(name "Placemark",
                                                    xmlelement(name name, logbook_rec.notes),
                                                    ST_AsKML(logbook_rec.track_geom)::pg_catalog.xml)
                            ))::pg_catalog.xml
               FROM api.logbook WHERE id = _id;
    END;
$export_logbook_kml$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.export_logbook_kml_fn
    IS 'Export a log entry to KML XML format';

DROP FUNCTION IF EXISTS api.export_logbooks_gpx_fn;
CREATE OR REPLACE FUNCTION api.export_logbooks_gpx_fn(
    IN start_log INTEGER DEFAULT NULL,
    IN end_log INTEGER DEFAULT NULL) RETURNS "application/gpx+xml"
AS $export_logbooks_gpx$
    declare
        merged_jsonb jsonb;
        app_settings jsonb;
    BEGIN
        -- Merge GIS track_geom of geometry type Point into a jsonb array format
        IF start_log IS NOT NULL AND public.isnumeric(start_log::text) AND public.isnumeric(end_log::text) THEN
            SELECT jsonb_agg(
                        jsonb_build_object('coordinates', f->'geometry'->'coordinates', 'time', f->'properties'->>'time')
                    ) INTO merged_jsonb
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook
                    WHERE id >= start_log
                        AND id <= end_log
                        AND track_geojson IS NOT NULL
                    ORDER BY _from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'Point';
        ELSE
            SELECT jsonb_agg(
                        jsonb_build_object('coordinates', f->'geometry'->'coordinates', 'time', f->'properties'->>'time')
                    ) INTO merged_jsonb
            FROM (
                SELECT jsonb_array_elements(track_geojson->'features') AS f
                    FROM api.logbook
                    WHERE track_geojson IS NOT NULL
                    ORDER BY _from_time ASC
            ) AS sub
            WHERE (f->'geometry'->>'type') = 'Point';
        END IF;
        --RAISE WARNING '-> export_logbooks_gpx_fn _jsonb %' , _jsonb;
        -- Gather url from app settings
        app_settings := get_app_url_fn();
        --RAISE WARNING '-> export_logbooks_gpx_fn app_settings %', app_settings;
        -- Generate GPX XML, extract Point features from geojson.
        RETURN xmlelement(name gpx,
                            xmlattributes(  '1.1' as version,
                                            'PostgSAIL' as creator,
                                            'http://www.topografix.com/GPX/1/1' as xmlns,
                                            'http://www.opencpn.org' as "xmlns:opencpn",
                                            app_settings->>'app.url' as "xmlns:postgsail"),
                xmlelement(name metadata,
                    xmlelement(name link, xmlattributes(app_settings->>'app.url' as href),
                        xmlelement(name text, 'PostgSail'))),
                xmlelement(name trk,
                    xmlelement(name name, 'logbook name'),
                    xmlelement(name trkseg, xmlagg(
                                                xmlelement(name trkpt,
                                                    xmlattributes(features->'coordinates'->1 as lat, features->'coordinates'->0 as lon),
                                                        xmlelement(name time, features->'properties'->>'time')
                                                )))))::pg_catalog.xml
            FROM jsonb_array_elements(merged_jsonb) AS features;
    END;
$export_logbooks_gpx$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.export_logbooks_gpx_fn
    IS 'Export a logs entries to GPX XML format';

DROP FUNCTION IF EXISTS api.export_logbooks_kml_fn;
CREATE OR REPLACE FUNCTION api.export_logbooks_kml_fn(
    IN start_log INTEGER DEFAULT NULL,
    IN end_log INTEGER DEFAULT NULL) RETURNS "text/xml"
AS $export_logbooks_kml$
DECLARE
    _geom geometry;
    app_settings jsonb;
BEGIN
    -- Merge GIS track_geom into a GeoJSON MultiLineString
    IF start_log IS NOT NULL AND public.isnumeric(start_log::text) AND public.isnumeric(end_log::text) THEN
        WITH logbook as (
            SELECT track_geom
            FROM api.logbook
            WHERE id >= start_log
                AND id <= end_log
                AND track_geom IS NOT NULL
            ORDER BY _from_time ASC
        )
        SELECT ST_Collect(
                    ARRAY(
                        SELECT track_geom FROM logbook))
         into _geom;
    ELSE
        WITH logbook as (
            SELECT track_geom
            FROM api.logbook
            WHERE track_geom IS NOT NULL
            ORDER BY _from_time ASC
        )
        SELECT ST_Collect(
                    ARRAY(
                        SELECT track_geom FROM logbook))
         into _geom;
        --raise WARNING 'all result _geojson %' , _geojson;
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
                xmlelement(name name, 'logbook name'),
                xmlelement(name "Placemark",
                    ST_AsKML(_geom)::pg_catalog.xml
                )
            )
        )::pg_catalog.xml;
END;
$export_logbooks_kml$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.export_logbooks_kml_fn
    IS 'Export a logs entries to KML XML format';

-- Find all log from and to moorage geopoint within 100m
DROP FUNCTION IF EXISTS api.find_log_from_moorage_fn;
CREATE OR REPLACE FUNCTION api.find_log_from_moorage_fn(IN _id INTEGER, OUT geojson JSONB) RETURNS JSONB AS $find_log_from_moorage$
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
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', public.geojson_py_fn(_geojson, 'Point'::TEXT) ) INTO geojson;
    END;
$find_log_from_moorage$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.find_log_from_moorage_fn
    IS 'Find all log from moorage geopoint within 100m';

DROP FUNCTION IF EXISTS api.find_log_to_moorage_fn;
CREATE OR REPLACE FUNCTION api.find_log_to_moorage_fn(IN _id INTEGER, OUT geojson JSONB) RETURNS JSONB AS $find_log_to_moorage$
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
        SELECT jsonb_build_object(
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
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features',
                ( SELECT
                    json_agg(ST_AsGeoJSON(m.*)::JSON) as moorages_geojson
                    FROM
                    ( SELECT
                        id,name,stay_code,
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
                            xmlelement(name time, 'TODO first seen'),
                            xmlelement(name desc,
                                concat('Last Stayed On: ', 'TODO last seen',
                                    E'\nTotal Stays: ', m.stay_duration,
                                    E'\nTotal Arrivals and Departures: ', m.reference_count,
                                    E'\nLink: ', concat(app_settings->>'app.url','/moorage/', m.id)),
                                    xmlelement(name "opencpn:guid", uuid_generate_v4())),
                            xmlelement(name sym, 'anchor'),
                            xmlelement(name type, 'WPT'),
                            xmlelement(name link, xmlattributes(concat(app_settings->>'app.url','moorage/', m.id) as href),
                                                        xmlelement(name text, m.name)),
                            xmlelement(name extensions, xmlelement(name "postgsail:mooorage_id", m.id),
                                                        xmlelement(name "postgsail:link", concat(app_settings->>'app.url','/moorage/', m.id)),
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
    OUT stats JSONB) RETURNS JSONB AS $stats_logs$
    DECLARE
        _start_date TIMESTAMPTZ DEFAULT '1970-01-01';
        _end_date TIMESTAMPTZ DEFAULT NOW();
    BEGIN
        IF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            RAISE WARNING '--> stats_fn, filter result stats by date [%]', start_date;
            _start_date := start_date::TIMESTAMPTZ;
            _end_date := end_date::TIMESTAMPTZ;
        END IF;
        RAISE NOTICE '--> stats_fn, _start_date [%], _end_date [%]', _start_date, _end_date;
        WITH
            meta AS (
                SELECT m.name FROM api.metadata m ),
            logs_view AS (
                SELECT *
                    FROM api.logbook l
                    WHERE _from_time >= _start_date::TIMESTAMPTZ
                        AND _to_time <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
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
            moorages_log AS (
                SELECT s.id as stays_id, m.id as moorages_id, *
                    FROM api.stays s, api.moorages m
                    WHERE arrived >= _start_date::TIMESTAMPTZ
                        AND departed <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
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

DROP FUNCTION IF EXISTS api.delete_logbook_fn;
CREATE OR REPLACE FUNCTION api.delete_logbook_fn(IN _id integer) RETURNS BOOLEAN AS $delete_logbook$
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
        SELECT * INTO logbook_rec
            FROM api.logbook l
            WHERE id = _id;
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
        -- Clean up, Subtract (-1) moorages ref count
        UPDATE api.moorages
            SET reference_count = reference_count - 1
            WHERE vessel_id = current_setting('vessel.id', false)
                AND id = previous_stays_id;
        RETURN TRUE;
    END;
$delete_logbook$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.delete_logbook_fn
    IS 'Delete a logbook and dependency stay';

CREATE OR REPLACE FUNCTION api.monitoring_history_fn(IN time_interval TEXT DEFAULT '24', OUT history_metrics JSONB) RETURNS JSONB AS $monitoring_history$
    DECLARE
        bucket_interval interval := '5 minutes';
    BEGIN
        RAISE NOTICE '-> monitoring_history_fn';
        SELECT CASE time_interval
            WHEN '24' THEN '5 minutes'
            WHEN '48' THEN '2 hours'
            WHEN '72' THEN '4 hours'
            WHEN '168' THEN '7 hours'
            ELSE '5 minutes'
            END bucket INTO bucket_interval;
        RAISE NOTICE '-> monitoring_history_fn % %', time_interval, bucket_interval;
        WITH history_table AS (
            SELECT time_bucket(bucket_interval::INTERVAL, time) AS time_bucket,
                avg((metrics->'environment.water.temperature')::numeric) AS waterTemperature,
                avg((metrics->'environment.inside.temperature')::numeric) AS insideTemperature,
                avg((metrics->'environment.outside.temperature')::numeric) AS outsideTemperature,
                avg((metrics->'environment.wind.speedOverGround')::numeric) AS windSpeedOverGround,
                avg((metrics->'environment.inside.relativeHumidity')::numeric) AS insideHumidity,
                avg((metrics->'environment.outside.relativeHumidity')::numeric) AS outsideHumidity,
                avg((metrics->'environment.outside.pressure')::numeric) AS outsidePressure,
                avg((metrics->'environment.inside.pressure')::numeric) AS insidePressure,
                avg((metrics->'electrical.batteries.House.capacity.stateOfCharge')::numeric) AS batteryCharge,
                avg((metrics->'electrical.batteries.House.voltage')::numeric) AS batteryVoltage,
                avg((metrics->'environment.depth.belowTransducer')::numeric) AS depth
                FROM api.metrics
                WHERE time > (NOW() AT TIME ZONE 'UTC' - INTERVAL '1 hours' * time_interval::NUMERIC)
                GROUP BY time_bucket
                ORDER BY time_bucket asc
        )
        SELECT jsonb_agg(history_table) INTO history_metrics FROM history_table;
    END
$monitoring_history$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.monitoring_history_fn
    IS 'Export metrics from a time period 24h, 48h, 72h, 7d';

CREATE OR REPLACE FUNCTION api.status_fn(out status jsonb) RETURNS JSONB AS $status_fn$
    DECLARE
        in_route BOOLEAN := False;
    BEGIN
        RAISE NOTICE '-> status_fn';
        SELECT EXISTS ( SELECT id
                        FROM api.logbook l
                        WHERE active IS True
                        LIMIT 1
                    ) INTO in_route;
        IF in_route IS True THEN
            -- In route from <logbook.from_name> arrived at <>
            SELECT jsonb_build_object('status', sa.description, 'location', m.name, 'departed', l._from_time) INTO status
                from api.logbook l, api.stays_at sa, api.moorages m
                where s.stay_code = sa.stay_code AND l._from_moorage_id = m.id AND l.active IS True;
        ELSE
            -- At <Stat_at.Desc> in <Moorage.name> departed at <>
            SELECT jsonb_build_object('status', sa.description, 'location', m.name, 'arrived', s.arrived) INTO status
                from api.stays s, api.stays_at sa, api.moorages m
                where s.stay_code = sa.stay_code AND s.moorage_id = m.id AND s.active IS True;
        END IF;
    END
$status_fn$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.status_fn
    IS 'generate vessel status';