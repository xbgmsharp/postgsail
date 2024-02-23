---------------------------------------------------------------------------
-- singalk db public schema
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

CREATE SCHEMA IF NOT EXISTS public;

---------------------------------------------------------------------------
-- Functions public schema
-- process single cron event, process_[logbook|stay|moorage]_queue_fn()
--
CREATE OR REPLACE FUNCTION public.logbook_metrics_dwithin_fn(
    IN _start text,
    IN _end text,
    IN lgn float,
    IN lat float,
    OUT count_metric numeric) AS $logbook_metrics_dwithin$
    BEGIN
        SELECT count(*) INTO count_metric
            FROM api.metrics m
            WHERE
                m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.time >= _start::TIMESTAMPTZ
                AND m.time <= _end::TIMESTAMPTZ
                AND vessel_id = current_setting('vessel.id', false)
                AND ST_DWithin(
                    Geography(ST_MakePoint(m.longitude, m.latitude)),
                    Geography(ST_MakePoint(lgn, lat)),
                    50
                );
    END;
$logbook_metrics_dwithin$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_metrics_dwithin_fn
    IS 'Check if all entries for a logbook are in stationary movement with 50 meters';

-- Update a logbook with avg data 
-- TODO using timescale function
CREATE OR REPLACE FUNCTION public.logbook_update_avg_fn(
    IN _id integer, 
    IN _start TEXT, 
    IN _end TEXT,
    OUT avg_speed double precision,
    OUT max_speed double precision,
    OUT max_wind_speed double precision,
    OUT count_metric integer
) AS $logbook_update_avg$
    BEGIN
        RAISE NOTICE '-> logbook_update_avg_fn calculate avg for logbook id=%, start:"%", end:"%"', _id, _start, _end;
        SELECT AVG(speedoverground), MAX(speedoverground), MAX(windspeedapparent), COUNT(*) INTO
                avg_speed, max_speed, max_wind_speed, count_metric
            FROM api.metrics m
            WHERE m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.time >= _start::TIMESTAMPTZ
                AND m.time <= _end::TIMESTAMPTZ
                AND vessel_id = current_setting('vessel.id', false);
        RAISE NOTICE '-> logbook_update_avg_fn avg for logbook id=%, avg_speed:%, max_speed:%, max_wind_speed:%, count:%', _id, avg_speed, max_speed, max_wind_speed, count_metric;
    END;
$logbook_update_avg$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_avg_fn
    IS 'Update logbook details with calculate average and max data, AVG(speedOverGround), MAX(speedOverGround), MAX(windspeedapparent), count_metric';

-- Create a LINESTRING for Geometry
-- Todo validate st_length unit?
-- https://postgis.net/docs/ST_Length.html
DROP FUNCTION IF EXISTS public.logbook_update_geom_distance_fn;
CREATE FUNCTION public.logbook_update_geom_distance_fn(IN _id integer, IN _start text, IN _end text,
    OUT _track_geom Geometry(LINESTRING),
    OUT _track_distance double precision
 ) AS $logbook_geo_distance$
    BEGIN
        SELECT ST_MakeLine( 
            ARRAY(
                --SELECT ST_SetSRID(ST_MakePoint(longitude,latitude),4326) as geo_point
                SELECT st_makepoint(longitude,latitude) AS geo_point
                    FROM api.metrics m
                    WHERE m.latitude IS NOT NULL
                        AND m.longitude IS NOT NULL
                        AND m.time >= _start::TIMESTAMPTZ
                        AND m.time <= _end::TIMESTAMPTZ
                        AND vessel_id = current_setting('vessel.id', false)
                    ORDER BY m.time ASC
            )
        ) INTO _track_geom;
        --RAISE NOTICE '-> GIS LINESTRING %', _track_geom;
        -- SELECT ST_Length(_track_geom,false) INTO _track_distance;
        -- Meter to Nautical Mile (international) Conversion
        -- SELECT TRUNC (st_length(st_transform(track_geom,4326)::geography)::INT / 1.852) from logbook where id = 209; -- in NM
        -- SELECT (st_length(st_transform(track_geom,4326)::geography)::INT * 0.0005399568) from api.logbook where id = 1; -- in NM
        --SELECT TRUNC (ST_Length(_track_geom,false)::INT / 1.852) INTO _track_distance; -- in NM
        SELECT TRUNC (ST_Length(_track_geom,false)::INT * 0.0005399568, 4) INTO _track_distance; -- in NM
        RAISE NOTICE '-> logbook_update_geom_distance_fn GIS Length %', _track_distance;
    END;
$logbook_geo_distance$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_geom_distance_fn
    IS 'Update logbook details with geometry data an distance, ST_Length in Nautical Mile (international)';

-- Create GeoJSON for api consume.
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
-- Description
COMMENT ON FUNCTION
    public.logbook_update_geojson_fn
    IS 'Update log details with geojson';

-- Generate GPX XML file output
-- https://opencpn.org/OpenCPN/info/gpxvalidation.html
--
CREATE OR REPLACE FUNCTION public.logbook_update_gpx_fn(IN _id INTEGER, IN _start text, IN _end text,
    OUT _track_gpx XML) RETURNS pg_catalog.xml
AS $logbook_update_gpx$
    DECLARE
        log_rec record;
        app_settings jsonb;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> logbook_update_gpx_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Gather log details _from_time and _to_time
        SELECT * INTO log_rec
            FROM
            api.logbook l
            WHERE l.id = _id;
        -- Ensure the query is successful
        IF log_rec.vessel_id IS NULL THEN
            RAISE WARNING '-> logbook_update_gpx_fn invalid logbook %', _id;
            RETURN;
        END IF;
        -- Gather url from app settings
        app_settings := get_app_settings_fn();
        --RAISE DEBUG '-> logbook_update_gpx_fn app_settings %', app_settings;
        -- Generate XML
        SELECT xmlelement(name gpx,
                            xmlattributes(  '1.1' as version,
                                            'PostgSAIL' as creator,
                                            'http://www.topografix.com/GPX/1/1' as xmlns,
                                            'http://www.opencpn.org' as "xmlns:opencpn",
                                            app_settings->>'app.url' as "xmlns:postgsail",
                                            'http://www.w3.org/2001/XMLSchema-instance' as "xmlns:xsi",
                                            'http://www.garmin.com/xmlschemas/GpxExtensions/v3' as "xmlns:gpxx",
                                            'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/GpxExtensions/v3 http://www8.garmin.com/xmlschemas/GpxExtensionsv3.xsd' as "xsi:schemaLocation"),
                xmlelement(name trk,
                    xmlelement(name name, log_rec.name),
                    xmlelement(name desc, log_rec.notes),
                    xmlelement(name link, xmlattributes(concat(app_settings->>'app.url', '/log/', log_rec.id) as href),
                                                xmlelement(name text, log_rec.name)),
                    xmlelement(name extensions, xmlelement(name "postgsail:log_id", log_rec.id),
                                                xmlelement(name "postgsail:link", concat(app_settings->>'app.url','/log/', log_rec.id)),
                                                xmlelement(name "opencpn:guid", uuid_generate_v4()),
                                                xmlelement(name "opencpn:viz", '1'),
                                                xmlelement(name "opencpn:start", log_rec._from_time),
                                                xmlelement(name "opencpn:end", log_rec._to_time)
                                                ),
                    xmlelement(name trkseg, xmlagg(
                                                xmlelement(name trkpt,
                                                    xmlattributes(latitude as lat, longitude as lon),
                                                        xmlelement(name time, time)
                                                )))))::pg_catalog.xml INTO _track_gpx
            FROM api.metrics m
            WHERE m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.time >= log_rec._from_time::TIMESTAMPTZ
                AND m.time <= log_rec._to_time::TIMESTAMPTZ
                AND vessel_id = log_rec.vessel_id
            GROUP BY m.time
            ORDER BY m.time ASC;
    END;
$logbook_update_gpx$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_gpx_fn
    IS 'Update log details with gpx xml, deprecated';

CREATE FUNCTION logbook_get_extra_json_fn(IN search TEXT, OUT output_json JSON)
AS $logbook_get_extra_json$
    declare
     metric_json jsonb default '{}'::jsonb;
     metric_rec record;
    BEGIN
    -- TODO
		-- Calculate 'search' first entry
        FOR metric_rec IN
			SELECT key, value
				FROM api.metrics m,
				     jsonb_each_text(m.metrics)
                WHERE key ILIKE search
                 AND time = _start::TIMESTAMPTZ
                 AND vessel_id = current_setting('vessel.id', false)
        LOOP
            -- Engine Hours in seconds
            RAISE NOTICE '-> logbook_get_extra_json_fn metric: %', metric_rec;
            WITH
                end_metric AS (
                    -- Fetch 'tanks.%.currentVolume' last entry
                    SELECT key, value
                        FROM api.metrics m,
                            jsonb_each_text(m.metrics)
                        WHERE key ILIKE metric_rec.key
                            AND time = _end::TIMESTAMPTZ
                            AND vessel_id = current_setting('vessel.id', false)
                ),
                metric AS (
                    -- Subtract
                    SELECT (end_metric.value::numeric - metric_rec.value::numeric) AS value FROM end_metric
                )
            -- Generate JSON
            SELECT jsonb_build_object(metric_rec.key, metric.value) INTO metric_json FROM metrics;
            RAISE NOTICE '-> logbook_get_extra_json_fn key: %, value: %', metric_rec.key, metric_json;
        END LOOP;
    END;
$logbook_get_extra_json$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_get_extra_json_fn
    IS 'TODO';

CREATE FUNCTION logbook_update_extra_json_fn(IN _id integer, IN _start text, IN _end text,
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
				-- calculate distance and convert to nautical miles
				SELECT ((end_trip.value::NUMERIC - start_trip.value::numeric) / 1.852) as trip from start_trip,end_trip
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
				-- calculate runTime Engine Hours in seconds
				SELECT (end_runtime.value::numeric - metric_rec.value::numeric) AS value FROM end_runtime
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
-- Description
COMMENT ON FUNCTION
    public.logbook_update_extra_json_fn
    IS 'Update log details with extra_json using `propulsion.*.runTime` and `navigation.log`';

-- Update pending new logbook from process queue
DROP FUNCTION IF EXISTS process_logbook_queue_fn;
CREATE OR REPLACE FUNCTION process_logbook_queue_fn(IN _id integer) RETURNS void AS $process_logbook_queue$
    DECLARE
        logbook_rec record;
        from_name text;
        to_name text;
        log_name text;
        from_moorage record;
        to_moorage record;
        avg_rec record;
        geo_rec record;
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
        avg_rec := logbook_update_avg_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        geo_rec := logbook_update_geom_distance_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);

        -- Do we have an existing moorage within 300m of the new log
        -- generate logbook name, concat _from_location and _to_location from moorage name
        from_moorage := process_lat_lon_fn(logbook_rec._from_lng::NUMERIC, logbook_rec._from_lat::NUMERIC);
        to_moorage := process_lat_lon_fn(logbook_rec._to_lng::NUMERIC, logbook_rec._to_lat::NUMERIC);
        SELECT CONCAT(from_moorage.moorage_name, ' to ' , to_moorage.moorage_name) INTO log_name;

        -- Process `propulsion.*.runTime` and `navigation.log`
        -- Calculate extra json
        extra_json := logbook_update_extra_json_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);

        RAISE NOTICE 'Updating valid logbook entry logbook id:[%] start:[%] end:[%]', logbook_rec.id, logbook_rec._from_time, logbook_rec._to_time;
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
                track_geom = geo_rec._track_geom,
                distance = geo_rec._track_distance,
                extra = extra_json,
                notes = NULL -- reset pre_log process
            WHERE id = logbook_rec.id;

        -- GeoJSON require track_geom field
        geojson := logbook_update_geojson_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        UPDATE api.logbook
            SET
                track_geojson = geojson
            WHERE id = logbook_rec.id;

        -- Prepare notification, gather user settings
        SELECT json_build_object('logbook_name', log_name, 'logbook_link', logbook_rec.id) into log_settings;
        user_settings := get_user_settings_from_vesselid_fn(logbook_rec.vessel_id::TEXT);
        SELECT user_settings::JSONB || log_settings::JSONB into user_settings;
        RAISE NOTICE '-> debug process_logbook_queue_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        RAISE NOTICE '-> debug process_logbook_queue_fn log_settings [%]', log_settings;
        -- Send notification
        PERFORM send_notification_fn('logbook'::TEXT, user_settings::JSONB);
        -- Process badges
        RAISE NOTICE '-> debug process_logbook_queue_fn user_settings [%]', user_settings->>'email'::TEXT;
        PERFORM set_config('user.email', user_settings->>'email'::TEXT, false);
        PERFORM badges_logbook_fn(logbook_rec.id, logbook_rec._to_time::TEXT);
        PERFORM badges_geom_fn(logbook_rec.id, logbook_rec._to_time::TEXT);
    END;
$process_logbook_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_logbook_queue_fn
    IS 'Update logbook details when completed, logbook_update_avg_fn, logbook_update_geom_distance_fn, reverse_geocode_py_fn';

-- Update pending new stay from process queue
DROP FUNCTION IF EXISTS process_stay_queue_fn;
CREATE OR REPLACE FUNCTION process_stay_queue_fn(IN _id integer) RETURNS void AS $process_stay_queue$
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

        -- Process badges
        PERFORM badges_moorages_fn();
    END;
$process_stay_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_stay_queue_fn
    IS 'Update stay details, reverse_geocode_py_fn';

-- Handle moorage insert or update from stays
-- todo validate geography unit
-- https://postgis.net/docs/ST_DWithin.html
DROP FUNCTION IF EXISTS process_moorage_queue_fn;
CREATE OR REPLACE FUNCTION process_moorage_queue_fn(IN _id integer) RETURNS void AS $process_moorage_queue$
    DECLARE
       	stay_rec record;
        moorage_rec record;
        user_settings jsonb;
        geo jsonb;
    BEGIN
        RAISE NOTICE 'process_moorage_queue_fn';
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_moorage_queue_fn invalid input %', _id;
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
            RAISE WARNING '-> process_moorage_queue_fn invalid stay %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', stay_rec.vessel_id, false);

        -- Do we have an existing stay within 200m of the new moorage
        FOR moorage_rec in
            SELECT
                *
            FROM api.moorages
            WHERE
                latitude IS NOT NULL
                AND longitude IS NOT NULL
                AND geog IS NOT NULL
                AND ST_DWithin(
                    -- Geography(ST_MakePoint(stay_rec._lng, stay_rec._lat)),
                    stay_rec.geog,
                    -- Geography(ST_MakePoint(longitude, latitude)),
                    geog,
                    200 -- in meters ?
                    )
            ORDER BY id ASC
        LOOP
            -- found previous stay within 200m of the new moorage
            IF moorage_rec.id IS NOT NULL AND moorage_rec.id > 0 THEN
                RAISE NOTICE 'Found previous stay within 200m of moorage %', moorage_rec;
                EXIT; -- exit loop
            END IF;
        END LOOP;

        -- if with in 200m update reference count and stay duration
        -- else insert new entry
        IF moorage_rec.id IS NOT NULL AND moorage_rec.id > 0 THEN
            RAISE NOTICE 'Update moorage %', moorage_rec;
            UPDATE api.moorages
                SET
                    reference_count = moorage_rec.reference_count + 1,
                    stay_duration =
                        moorage_rec.stay_duration + 
                        (stay_rec.departed::TIMESTAMPTZ - stay_rec.arrived::TIMESTAMPTZ)
                WHERE id = moorage_rec.id;
        ELSE
            RAISE NOTICE 'Insert new moorage entry from stay %', stay_rec;
            -- Set the moorage name and country if lat,lon
            IF stay_rec.longitude IS NOT NULL AND stay_rec.latitude IS NOT NULL THEN
                geo := reverse_geocode_py_fn('nominatim', stay_rec.longitude::NUMERIC, stay_rec.latitude::NUMERIC);
                moorage_rec.name = geo->>'name';
                moorage_rec.country = geo->>'country_code';
            END IF;
            -- Insert new moorage from stay
            INSERT INTO api.moorages
                    (vessel_id, name, country, stay_id, stay_code, stay_duration, reference_count, latitude, longitude, geog)
                    VALUES (
                        stay_rec.vessel_id,
                        coalesce(moorage_rec.name, null),
                        coalesce(moorage_rec.country, null),
                        stay_rec.id,
                        stay_rec.stay_code,
                        (stay_rec.departed::TIMESTAMPTZ - stay_rec.arrived::TIMESTAMPTZ),
                        1, -- default reference_count
                        stay_rec.latitude,
                        stay_rec.longitude,
                        Geography(ST_MakePoint(stay_rec.longitude, stay_rec.latitude))
                    );
        END IF;

        -- Process badges
        PERFORM badges_moorages_fn();
    END;
$process_moorage_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_moorage_queue_fn
    IS 'Handle moorage insert or update from stays, deprecated';

-- process new account notification
DROP FUNCTION IF EXISTS process_account_queue_fn;
CREATE OR REPLACE FUNCTION process_account_queue_fn(IN _email TEXT) RETURNS void AS $process_account_queue$
    DECLARE
       	account_rec record;
        user_settings jsonb;
        app_settings jsonb;
    BEGIN
        IF _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        SELECT * INTO account_rec
            FROM auth.accounts
            WHERE email = _email;
        IF account_rec.email IS NULL OR account_rec.email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        -- Gather email and pushover app settings
        app_settings := get_app_settings_fn();
        -- set user email variable
        PERFORM set_config('user.email', account_rec.email, false);
        -- Gather user settings
        user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '"}';
        -- Send notification email, pushover
        PERFORM send_notification_fn('new_account'::TEXT, user_settings::JSONB);
        --PERFORM send_email_py_fn('user'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('user'::TEXT, user_settings::JSONB, app_settings::JSONB);
    END;
$process_account_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_account_queue_fn
    IS 'process new account notification, deprecated';

-- process new account otp validation notification
DROP FUNCTION IF EXISTS process_account_otp_validation_queue_fn;
CREATE OR REPLACE FUNCTION process_account_otp_validation_queue_fn(IN _email TEXT) RETURNS void AS $process_account_otp_validation_queue$
    DECLARE
        account_rec record;
        user_settings jsonb;
        app_settings jsonb;
        otp_code text;
    BEGIN
        IF _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        SELECT * INTO account_rec
            FROM auth.accounts
            WHERE email = _email;
        IF account_rec.email IS NULL OR account_rec.email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        -- Gather email and pushover app settings
        app_settings := get_app_settings_fn();
        otp_code := api.generate_otp_fn(_email);
        -- set user email variable
        PERFORM set_config('user.email', account_rec.email, false);
        -- Gather user settings
        user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '", "otp_code": "' || otp_code || '"}';
        -- Send notification email, pushover
        PERFORM send_notification_fn('email_otp'::TEXT, user_settings::JSONB);
        --PERFORM send_email_py_fn('email_otp'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('user'::TEXT, user_settings::JSONB, app_settings::JSONB);
    END;
$process_account_otp_validation_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_account_otp_validation_queue_fn
    IS 'process new account otp validation notification, deprecated';

-- process new event notification
DROP FUNCTION IF EXISTS process_notification_queue_fn;
CREATE OR REPLACE FUNCTION process_notification_queue_fn(IN _email TEXT, IN message_type TEXT) RETURNS void
AS $process_notification_queue$
    DECLARE
        account_rec record;
        vessel_rec record;
        user_settings jsonb := null;
        otp_code text;
    BEGIN
        IF _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        SELECT * INTO account_rec
            FROM auth.accounts
            WHERE email = _email;
        IF account_rec.email IS NULL OR account_rec.email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;

        RAISE NOTICE '--> process_notification_queue_fn type [%] [%]', _email, message_type;
        -- set user email variable
        PERFORM set_config('user.email', account_rec.email, false);
        -- Generate user_settings user settings
        IF message_type = 'new_account' THEN
            user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '"}';
        ELSEIF message_type = 'new_vessel' THEN
            -- Gather vessel data
            SELECT * INTO vessel_rec
                FROM auth.vessels
                WHERE owner_email = _email;
            IF vessel_rec.owner_email IS NULL OR vessel_rec.owner_email = '' THEN
                RAISE EXCEPTION 'Invalid email'
                    USING HINT = 'Unknown email';
                RETURN;
            END IF;
            user_settings := '{"email": "' || vessel_rec.owner_email || '", "boat": "' || vessel_rec.name || '"}';
        ELSEIF message_type = 'email_otp' THEN
            otp_code := api.generate_otp_fn(_email);
            user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '", "otp_code": "' || otp_code || '"}';
        END IF;
        PERFORM send_notification_fn(message_type::TEXT, user_settings::JSONB);
    END;
$process_notification_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_notification_queue_fn
    IS 'process new event type notification, new_account, new_vessel, email_otp';

-- process new vessel notification
DROP FUNCTION IF EXISTS process_vessel_queue_fn;
CREATE OR REPLACE FUNCTION process_vessel_queue_fn(IN _email TEXT) RETURNS void AS $process_vessel_queue$
    DECLARE
       	vessel_rec record;
        user_settings jsonb;
        app_settings jsonb;
    BEGIN
        IF _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        SELECT * INTO vessel_rec
            FROM auth.vessels
            WHERE owner_email = _email;
        IF vessel_rec.owner_email IS NULL OR vessel_rec.owner_email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        -- Gather email and pushover app settings
        app_settings := get_app_settings_fn();
        -- set user email variable
        PERFORM set_config('user.email', vessel_rec.owner_email, false);
        -- Gather user settings
        user_settings := '{"email": "' || vessel_rec.owner_email || '", "boat": "' || vessel_rec.name || '"}';
        --user_settings := get_user_settings_from_vesselid_fn();
        -- Send notification email, pushover
        --PERFORM send_notification_fn('vessel'::TEXT, vessel_rec::RECORD);
        PERFORM send_email_py_fn('new_vessel'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('vessel'::TEXT, user_settings::JSONB, app_settings::JSONB);
    END;
$process_vessel_queue$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_vessel_queue_fn
    IS 'process new vessel notification, deprecated';

-- Get application settings details from a log entry
DROP FUNCTION IF EXISTS get_app_settings_fn;
CREATE OR REPLACE FUNCTION get_app_settings_fn(OUT app_settings jsonb)
    RETURNS jsonb
    AS $get_app_settings$
DECLARE
BEGIN
    SELECT
        jsonb_object_agg(name, value) INTO app_settings
    FROM
        public.app_settings
    WHERE
        name LIKE 'app.email%'
        OR name LIKE 'app.pushover%'
        OR name LIKE 'app.url'
        OR name LIKE 'app.telegram%'
        OR name LIKE 'app.grafana_admin_uri'
        OR name LIKE 'app.keycloak_uri'
        OR name LIKE 'app.windy_apikey';
END;
$get_app_settings$
LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.get_app_settings_fn
    IS 'get application settings details, email, pushover, telegram, grafana_admin_uri';

DROP FUNCTION IF EXISTS get_app_url_fn;
CREATE OR REPLACE FUNCTION get_app_url_fn(OUT app_settings jsonb)
    RETURNS jsonb
    AS $get_app_url$
DECLARE
BEGIN
    SELECT
        jsonb_object_agg(name, value) INTO app_settings
    FROM
        public.app_settings
    WHERE
        name = 'app.url';
END;
$get_app_url$
LANGUAGE plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    public.get_app_url_fn
    IS 'get application url security definer';

-- Send notifications
DROP FUNCTION IF EXISTS send_notification_fn;
CREATE OR REPLACE FUNCTION send_notification_fn(
    IN email_type TEXT,
    IN user_settings JSONB) RETURNS VOID
AS $send_notification$
    DECLARE
        app_settings JSONB;
        _email_notifications BOOLEAN := False;
        _phone_notifications BOOLEAN := False;
        _pushover_user_key TEXT := NULL;
        pushover_settings JSONB := NULL;
        _telegram_notifications BOOLEAN := False;
        _telegram_chat_id TEXT := NULL;
        telegram_settings JSONB := NULL;
		_email TEXT := NULL;
    BEGIN
        -- TODO input check
        --RAISE NOTICE '--> send_notification_fn type [%]', email_type;
        -- Gather notification app settings, eg: email, pushover, telegram
        app_settings := get_app_settings_fn();
        --RAISE NOTICE '--> send_notification_fn app_settings [%]', app_settings;
        --RAISE NOTICE '--> user_settings [%]', user_settings->>'email'::TEXT;

        -- Gather notifications settings and merge with user settings
        -- Send notification email
        SELECT preferences['email_notifications'] INTO _email_notifications
            FROM auth.accounts a
            WHERE a.email = user_settings->>'email'::TEXT;
        RAISE NOTICE '--> send_notification_fn email_notifications [%]', _email_notifications;
        -- If email server app settings set and if email user settings set
        IF app_settings['app.email_server'] IS NOT NULL AND _email_notifications IS True THEN
            PERFORM send_email_py_fn(email_type::TEXT, user_settings::JSONB, app_settings::JSONB);
        END IF;

        -- Send notification pushover
        SELECT preferences['phone_notifications'],preferences->>'pushover_user_key' INTO _phone_notifications,_pushover_user_key
            FROM auth.accounts a
            WHERE a.email = user_settings->>'email'::TEXT;
        RAISE NOTICE '--> send_notification_fn phone_notifications [%]', _phone_notifications;
        -- If pushover app settings set and if pushover user settings set
        IF app_settings['app.pushover_app_token'] IS NOT NULL AND _phone_notifications IS True THEN
            SELECT json_build_object('pushover_user_key', _pushover_user_key) into pushover_settings;
            SELECT user_settings::JSONB || pushover_settings::JSONB into user_settings;
            --RAISE NOTICE '--> send_notification_fn user_settings + pushover [%]', user_settings;
            PERFORM send_pushover_py_fn(email_type::TEXT, user_settings::JSONB, app_settings::JSONB);
        END IF;

        -- Send notification telegram
        SELECT (preferences->'telegram'->'chat'->'id') IS NOT NULL,preferences['telegram']['chat']['id'] INTO _telegram_notifications,_telegram_chat_id
            FROM auth.accounts a
            WHERE a.email = user_settings->>'email'::TEXT;
        RAISE NOTICE '--> send_notification_fn telegram_notifications [%]', _telegram_notifications;
        -- If telegram app settings set and if telegram user settings set
        IF app_settings['app.telegram_bot_token'] IS NOT NULL AND _telegram_notifications IS True AND _phone_notifications IS True THEN
            SELECT json_build_object('telegram_chat_id', _telegram_chat_id) into telegram_settings;
            SELECT user_settings::JSONB || telegram_settings::JSONB into user_settings;
            --RAISE NOTICE '--> send_notification_fn user_settings + telegram [%]', user_settings;
            PERFORM send_telegram_py_fn(email_type::TEXT, user_settings::JSONB, app_settings::JSONB);
        END IF;
    END;
$send_notification$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.send_notification_fn
    IS 'Send notifications via email, pushover, telegram to user base on user preferences';

DROP FUNCTION IF EXISTS get_user_settings_from_vesselid_fn;
CREATE OR REPLACE FUNCTION get_user_settings_from_vesselid_fn(
    IN vesselid TEXT,
    OUT user_settings JSONB
    ) RETURNS JSONB
AS $get_user_settings_from_vesselid$
    DECLARE
    BEGIN
        -- If vessel_id is not NULL
        IF vesselid IS NULL OR vesselid = '' THEN
            RAISE WARNING '-> get_user_settings_from_vesselid_fn invalid input %', vesselid;
        END IF;
        SELECT 
            json_build_object( 
                    'boat' , v.name,
                    'recipient', a.first,
                    'email', v.owner_email,
                    'settings', a.preferences
                    ) INTO user_settings
            FROM auth.accounts a, auth.vessels v, api.metadata m
            WHERE m.vessel_id = v.vessel_id
                AND m.vessel_id = vesselid
                AND a.email = v.owner_email;
        PERFORM set_config('user.email', user_settings->>'email'::TEXT, false);
        PERFORM set_config('user.recipient', user_settings->>'recipient'::TEXT, false);
    END;
$get_user_settings_from_vesselid$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.get_user_settings_from_vesselid_fn
    IS 'get user settings details from a vesselid initiate for notifications';

DROP FUNCTION IF EXISTS set_vessel_settings_from_vesselid_fn;
CREATE OR REPLACE FUNCTION set_vessel_settings_from_vesselid_fn(
    IN vesselid TEXT,
    OUT vessel_settings JSONB
    ) RETURNS JSONB
AS $set_vessel_settings_from_vesselid$
    DECLARE
    BEGIN
        -- If vessel_id is not NULL
        IF vesselid IS NULL OR vesselid = '' THEN
            RAISE WARNING '-> set_vessel_settings_from_vesselid_fn invalid input %', vesselid;
        END IF;
        SELECT
            json_build_object(
                    'name' , v.name,
                    'vessel_id', v.vesselid,
                    'client_id', m.client_id
                    ) INTO vessel_settings
            FROM auth.accounts a, auth.vessels v, api.metadata m
            WHERE m.vessel_id = v.vessel_id
                AND m.vessel_id = vesselid;
        PERFORM set_config('vessel.name', vessel_settings->>'name'::TEXT, false);
        PERFORM set_config('vessel.client_id', vessel_settings->>'client_id'::TEXT, false);
        PERFORM set_config('vessel.id', vessel_settings->>'vessel_id'::TEXT, false);
    END;
$set_vessel_settings_from_vesselid$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.set_vessel_settings_from_vesselid_fn
    IS 'set_vessel settings details from a vesselid, initiate for process queue functions';

---------------------------------------------------------------------------
-- Badges
--
CREATE OR REPLACE FUNCTION public.badges_logbook_fn(IN logbook_id INTEGER, IN logbook_time TEXT) RETURNS VOID AS $badges_logbook$
    DECLARE
        _badges jsonb;
        _exist BOOLEAN := null;
        total integer;
        max_wind_speed integer;
        distance integer;
        badge text;
        user_settings jsonb;
    BEGIN

        -- Helmsman = first log entry
        SELECT (preferences->'badges'->'Helmsman') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false THEN
            -- is first logbook?
            select count(*) into total from api.logbook l where vessel_id = current_setting('vessel.id', false);
            if total >= 1 then
                -- Add badge
                badge := '{"Helmsman": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- Update badges
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Helmsman"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

        -- Wake Maker = windspeeds above 15kts
        SELECT (preferences->'badges'->'Wake Maker') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        --RAISE WARNING '-> Wake Maker %', _exist;
        if _exist is false then
            -- is 15 knot+ logbook?
            select l.max_wind_speed into max_wind_speed from api.logbook l where l.id = logbook_id AND l.max_wind_speed >= 15 and vessel_id = current_setting('vessel.id', false);
            --RAISE WARNING '-> Wake Maker max_wind_speed %', max_wind_speed;
           if max_wind_speed >= 15 then
                -- Create badge
                badge := '{"Wake Maker": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
                --RAISE WARNING '-> Wake Maker max_wind_speed badge %', badge;
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                --RAISE WARNING '-> Wake Maker max_wind_speed badge % %', badge, _badges;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Wake Maker"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

        -- Stormtrooper = windspeeds above 30kts
        SELECT (preferences->'badges'->'Stormtrooper') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
            --RAISE WARNING '-> Stormtrooper %', _exist;
            select l.max_wind_speed into max_wind_speed from api.logbook l where l.id = logbook_id AND l.max_wind_speed >= 30 and vessel_id = current_setting('vessel.id', false);
            --RAISE WARNING '-> Stormtrooper max_wind_speed %', max_wind_speed;
            if max_wind_speed >= 30 then
                -- Create badge
                badge := '{"Stormtrooper": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
                --RAISE WARNING '-> Stormtrooper max_wind_speed badge %', badge;
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- RAISE WARNING '-> Wake Maker max_wind_speed badge % %', badge, _badges;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Stormtrooper"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

        -- Navigator Award = one logbook with distance over 100NM
        SELECT (preferences->'badges'->'Navigator Award') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
            select l.distance into distance from api.logbook l where l.id = logbook_id AND l.distance >= 100 and vessel_id = current_setting('vessel.id', false);
            if distance >= 100 then
                -- Create badge
                badge := '{"Navigator Award": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Navigator Award"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

        -- Captain Award = total logbook distance over 1000NM
        SELECT (preferences->'badges'->'Captain Award') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
            select sum(l.distance) into distance from api.logbook l where vessel_id = current_setting('vessel.id', false);
            if distance >= 1000 then
                -- Create badge
                badge := '{"Captain Award": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Captain Award"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

    END;
$badges_logbook$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.badges_logbook_fn
    IS 'check for new badges, eg: Helmsman, Wake Maker, Stormtrooper';

CREATE OR REPLACE FUNCTION public.badges_moorages_fn() RETURNS VOID AS $badges_moorages$
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

        -- Explorer = 10 days away from home port
        SELECT (preferences->'badges'->'Explorer') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
            --select sum(m.stay_duration) from api.moorages m where home_flag is false;
            SELECT extract(day from (select sum(m.stay_duration) INTO duration FROM api.moorages m WHERE home_flag IS false AND vessel_id = current_setting('vessel.id', false) ));
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
            SELECT extract(day from (select sum(m.stay_duration) INTO duration FROM api.moorages m WHERE stay_code = 3 AND vessel_id = current_setting('vessel.id', false) ));
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
            SELECT extract(day from (select sum(m.stay_duration) INTO duration FROM api.moorages m WHERE stay_code = 2 AND vessel_id = current_setting('vessel.id', false) ));
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

    END;
$badges_moorages$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.badges_moorages_fn
    IS 'check moorages for new badges, eg: Explorer, Mooring Pro, Anchormaster';

CREATE OR REPLACE FUNCTION public.badges_geom_fn(IN logbook_id INTEGER, IN logbook_time TEXT) RETURNS VOID AS $badges_geom$
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
		            SELECT l.track_geom AS track_geom FROM api.logbook l
                        WHERE l.id = logbook_id AND vessel_id = current_setting('vessel.id', false)
		            )
	        SELECT name from log, public.ne_10m_geography_marine_polys
                WHERE ST_Intersects(
		                geom, -- ST_SetSRID(geom,4326),
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
$badges_geom$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.badges_geom_fn
    IS 'check geometry logbook for new badges, eg: Tropic, Alaska, Geographic zone';

DROP FUNCTION IF EXISTS public.process_pre_logbook_fn;
CREATE OR REPLACE FUNCTION public.process_pre_logbook_fn(IN _id integer) RETURNS void AS $process_pre_logbook$
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
        -- If we have less than 15 metrics
        -- Is within metrics represent more or equal than 60% of the total entry
        IF count_metric::NUMERIC <= 15 THEN
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
$process_pre_logbook$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.process_pre_logbook_fn
    IS 'Detect/Avoid/ignore/delete logbook stationary movement or time sync issue';

DROP FUNCTION IF EXISTS process_lat_lon_fn;
CREATE OR REPLACE FUNCTION process_lat_lon_fn(IN lon NUMERIC, IN lat NUMERIC,
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
            IF overpass->>'name:en' IS NOT NULL then
                moorage_name = overpass->>'name:en';
            ELSIF overpass->>'name' IS NOT NULL then
                moorage_name = overpass->>'name';
            ELSE
                -- geo reverse _lng _lat
                geo := reverse_geocode_py_fn('nominatim', lon::NUMERIC, lat::NUMERIC);
                moorage_name := geo->>'name';
                moorage_country := geo->>'country_code';
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
-- Description
COMMENT ON FUNCTION
    public.process_lat_lon_fn
    IS 'Add or Update moorage base on lat/lon';

CREATE OR REPLACE FUNCTION public.logbook_metrics_timebucket_fn(
    IN bucket_interval TEXT,
    IN _id INTEGER,
    IN _start TIMESTAMPTZ,
    IN _end TIMESTAMPTZ,
    OUT timebucket boolean) AS $logbook_metrics_timebucket$
DECLARE
    time_rec record;
    stay_rec record;
    log_rec record;
    geo_rec record;
    ref_time timestamptz;
    stay_id integer;
    stay_lat DOUBLE PRECISION;
    stay_lng DOUBLE PRECISION;
    stay_arv timestamptz;
    in_interval boolean := False;
    log_id integer;
    log_lat DOUBLE PRECISION;
    log_lng DOUBLE PRECISION;
    log_start timestamptz;
    in_log boolean := False;
BEGIN
    timebucket := False;
    -- Agg metrics over a bucket_interval
    RAISE NOTICE '-> logbook_metrics_timebucket_fn Starting loop by [%], _start[%], _end[%]', bucket_interval, _start, _end;
    for time_rec in
        WITH tbl_bucket AS (
            SELECT time_bucket(bucket_interval::INTERVAL, time) AS time_bucket,
                    avg(speedoverground) AS speed,
                    last(latitude, time) AS lat,
                    last(longitude, time) AS lng,
                    st_makepoint(avg(longitude),avg(latitude)) AS geo_point
                FROM api.metrics m
                WHERE
                    m.latitude IS NOT NULL
                    AND m.longitude IS NOT NULL
                    AND m.time >= _start::TIMESTAMPTZ
                    AND m.time <= _end::TIMESTAMPTZ
                    AND m.vessel_id = current_setting('vessel.id', false)
                GROUP BY time_bucket
                ORDER BY time_bucket asc
            ),
        tbl_bucket2 AS (
                SELECT time_bucket,
                    speed,
                    geo_point,lat,lng,
                    LEAD(time_bucket,1) OVER (
                        ORDER BY time_bucket asc
                    ) time_interval,
                    LEAD(geo_point,1) OVER (
                        ORDER BY time_bucket asc
                    ) geo_interval
                FROM tbl_bucket
                WHERE speed <= 0.5
            )
        SELECT time_bucket,
                speed,
                geo_point,lat,lng,
                time_interval,
                bucket_interval,
                (bucket_interval::interval * 2) AS min_interval,
                (time_bucket - time_interval) AS diff_interval,
                (time_bucket - time_interval)::INTERVAL < (bucket_interval::interval * 2)::INTERVAL AS to_be_process
        FROM tbl_bucket2
        WHERE (time_bucket - time_interval)::INTERVAL < (bucket_interval::interval * 2)::INTERVAL
    loop
        RAISE NOTICE '-> logbook_metrics_timebucket_fn ref_time [%] interval [%] bucket_interval[%]', ref_time, time_rec.time_bucket, bucket_interval;
        select ref_time + bucket_interval::interval * 1 >= time_rec.time_bucket into in_interval;
        RAISE NOTICE '-> logbook_metrics_timebucket_fn ref_time+inverval[%] interval [%], in_interval [%]', ref_time + bucket_interval::interval * 1, time_rec.time_bucket, in_interval;
        if ST_DWithin(Geography(ST_MakePoint(stay_lng, stay_lat)), Geography(ST_MakePoint(time_rec.lng, time_rec.lat)), 50) IS True then
            in_interval := True;
        end if;
        if ST_DWithin(Geography(ST_MakePoint(log_lng, log_lat)), Geography(ST_MakePoint(time_rec.lng, time_rec.lat)), 50) IS False then
            in_interval := False;
        end if;
        if in_interval is true then
            ref_time := time_rec.time_bucket;
        end if;
        RAISE NOTICE '-> logbook_metrics_timebucket_fn ref_time is stay within of next point %', ST_DWithin(Geography(ST_MakePoint(stay_lng, stay_lat)), Geography(ST_MakePoint(time_rec.lng, time_rec.lat)), 50);
        RAISE NOTICE '-> logbook_metrics_timebucket_fn ref_time is NOT log within of next point %', ST_DWithin(Geography(ST_MakePoint(log_lng, log_lat)), Geography(ST_MakePoint(time_rec.lng, time_rec.lat)), 50);
        if time_rec.time_bucket::TIMESTAMPTZ < _start::TIMESTAMPTZ + bucket_interval::interval * 1 then
            in_interval := True;
        end if;
        RAISE NOTICE '-> logbook_metrics_timebucket_fn ref_time is NOT before start[%] or +interval[%]', (time_rec.time_bucket::TIMESTAMPTZ < _start::TIMESTAMPTZ), (time_rec.time_bucket::TIMESTAMPTZ < _start::TIMESTAMPTZ + bucket_interval::interval * 1);
        continue when in_interval is True;

        RAISE NOTICE '-> logbook_metrics_timebucket_fn after continue stay_id[%], in_log[%]', stay_id, in_log;
        if stay_id is null THEN
            RAISE NOTICE '-> Close current logbook logbook_id ref_time [%] time_rec.time_bucket [%]', ref_time, time_rec.time_bucket;
            -- Close current logbook
            geo_rec := logbook_update_geom_distance_fn(_id, _start::TEXT, time_rec.time_bucket::TEXT);
            UPDATE api.logbook
                SET
                    active = false,
                    _to_time = time_rec.time_bucket,
                    _to_lat = time_rec.lat,
                    _to_lng = time_rec.lng,
                    track_geom = geo_rec._track_geom,
                    notes = 'updated time_bucket'
                WHERE id = _id;
            -- Add logbook entry to process queue for later processing
            INSERT INTO process_queue (channel, payload, stored, ref_id)
                VALUES ('pre_logbook', _id, NOW(), current_setting('vessel.id', true));
            RAISE WARNING '-> Updated existing logbook logbook_id [%] [%] and add to process_queue', _id, time_rec.time_bucket;
            -- Add new stay
            INSERT INTO api.stays
                (vessel_id, active, arrived, latitude, longitude, notes)
                VALUES (current_setting('vessel.id', false), false, time_rec.time_bucket, time_rec.lat, time_rec.lng, 'autogenerated time_bucket')
                RETURNING id, latitude, longitude, arrived INTO stay_id, stay_lat, stay_lng, stay_arv;
            RAISE WARNING '-> Add new stay stay_id [%] [%]', stay_id, time_rec.time_bucket;
            timebucket := True;
        elsif in_log is false THEN
            -- Close current stays
            UPDATE api.stays
                SET
                    active = false,
                    departed = ref_time,
                    notes = 'autogenerated time_bucket'
                WHERE id = stay_id;
            -- Add stay entry to process queue for further processing
            INSERT INTO process_queue (channel, payload, stored, ref_id)
                VALUES ('new_stay', stay_id, now(), current_setting('vessel.id', true));
            RAISE WARNING '-> Updated existing stays stay_id [%] departed [%] and add to process_queue', stay_id, ref_time;
            -- Add new logbook
            INSERT INTO api.logbook
                (vessel_id, active, _from_time, _from_lat, _from_lng, notes)
                VALUES (current_setting('vessel.id', false), false, ref_time, stay_lat, stay_lng, 'autogenerated time_bucket')
                RETURNING id, _from_lat, _from_lng, _from_time INTO log_id, log_lat, log_lng, log_start;
            RAISE WARNING '-> Add new logbook, logbook_id [%] [%]', log_id, ref_time;
            in_log := true;
            stay_id := 0;
            stay_lat := null;
            stay_lng := null;
            timebucket := True;
        elsif in_log is true THEN
            RAISE NOTICE '-> Close current logbook logbook_id [%], ref_time [%], time_rec.time_bucket [%]', log_id, ref_time, time_rec.time_bucket;
            -- Close current logbook
            geo_rec := logbook_update_geom_distance_fn(_id, log_start::TEXT, time_rec.time_bucket::TEXT);
            UPDATE api.logbook
                SET
                    active = false,
                    _to_time = time_rec.time_bucket,
                    _to_lat = time_rec.lat,
                    _to_lng = time_rec.lng,
                    track_geom = geo_rec._track_geom,
                    notes = 'autogenerated time_bucket'
                WHERE id = log_id;
            -- Add logbook entry to process queue for later processing
            INSERT INTO process_queue (channel, payload, stored, ref_id)
                VALUES ('pre_logbook', log_id, NOW(), current_setting('vessel.id', true));
            RAISE WARNING '-> Update Existing logbook logbook_id [%] [%] and add to process_queue', log_id, time_rec.time_bucket;
            -- Add new stay
            INSERT INTO api.stays
                (vessel_id, active, arrived, latitude, longitude, notes)
                VALUES (current_setting('vessel.id', false), false, time_rec.time_bucket, time_rec.lat, time_rec.lng, 'autogenerated time_bucket')
                RETURNING id, latitude, longitude, arrived INTO stay_id, stay_lat, stay_lng, stay_arv;
            RAISE WARNING '-> Add new stay stay_id [%] [%]', stay_id, time_rec.time_bucket;
            in_log := false;
            log_id := null;
            log_lat := null;
            log_lng := null;
            timebucket := True;
        end if;
        RAISE WARNING '-> Update new ref_time [%]', ref_time;
        ref_time := time_rec.time_bucket;
    end loop;

    RAISE NOTICE '-> logbook_metrics_timebucket_fn Ending loop stay_id[%], in_log[%]', stay_id, in_log;
    if in_log is true then
        RAISE NOTICE '-> Ending log ref_time [%] interval [%]', ref_time, time_rec.time_bucket;
    end if;
    if stay_id > 0 then
        RAISE NOTICE '-> Ending stay ref_time [%] interval [%]', ref_time, time_rec.time_bucket;
        select * into stay_rec from api.stays s where arrived = _end;
        -- Close current stays
        UPDATE api.stays
            SET
                active = false,
                arrived = stay_arv,
                notes = 'updated time_bucket'
            WHERE id = stay_rec.id;
        -- Add stay entry to process queue for further processing
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('new_stay', stay_rec.id, now(), current_setting('vessel.id', true));
        RAISE WARNING '-> Ending Update Existing stays stay_id [%] arrived [%] and add to process_queue', stay_rec.id, stay_arv;
        delete from api.stays where id = stay_id;
        RAISE WARNING '-> Ending Delete Existing stays stay_id [%]', stay_id;
        stay_arv := null;
        stay_id := null;
        stay_lat := null;
        stay_lng := null;
        timebucket := True;
    end if;
END;
$logbook_metrics_timebucket$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_metrics_timebucket_fn
    IS 'Check if all entries for a logbook are in stationary movement per time bucket of 15 or 5 min, speed < 0.6knot, d_within 50m of the stay point';

---------------------------------------------------------------------------
-- TODO add alert monitoring for Battery

---------------------------------------------------------------------------
-- PostgREST API pre-request check
-- require to set in configuration, eg: db-pre-request = "public.check_jwt"
CREATE OR REPLACE FUNCTION public.check_jwt() RETURNS void AS $$
-- Prevent unregister user or unregister vessel access
-- Allow anonymous access
DECLARE
  _role name;
  _email text;
  anonymous record;
  _path name;
  _vid text;
  _vname text;
  boat TEXT;
  _pid INTEGER := 0; -- public_id
  _pvessel TEXT := NULL; -- public_type
  _ptype TEXT := NULL; -- public_type
  _ppath BOOLEAN := False; -- public_path
  _pvalid BOOLEAN := False; -- public_valid
  _pheader text := NULL; -- public_header
  valid_public_type BOOLEAN := False;
  account_rec record;
  vessel_rec record;
BEGIN
  -- Extract email and role from jwt token
  --RAISE WARNING 'check_jwt jwt %', current_setting('request.jwt.claims', true);
  SELECT current_setting('request.jwt.claims', true)::json->>'email' INTO _email;
  PERFORM set_config('user.email', _email, false);
  SELECT current_setting('request.jwt.claims', true)::json->>'role' INTO _role;
  --RAISE WARNING 'jwt email %', current_setting('request.jwt.claims', true)::json->>'email';
  --RAISE WARNING 'jwt role %', current_setting('request.jwt.claims', true)::json->>'role';
  --RAISE WARNING 'cur_user %', current_user;

  --TODO SELECT current_setting('request.jwt.uid', true)::json->>'uid' INTO _user_id;
  --TODO RAISE WARNING 'jwt user_id %', current_setting('request.jwt.uid', true)::json->>'uid';
  --TODO SELECT current_setting('request.jwt.vid', true)::json->>'vid' INTO _vessel_id;
  --TODO RAISE WARNING 'jwt vessel_id %', current_setting('request.jwt.vid', true)::json->>'vid';
  IF _role = 'user_role' THEN
    -- Check the user exist in the accounts table
    SELECT * INTO account_rec
        FROM auth.accounts
        WHERE auth.accounts.email = _email;
    IF account_rec.email IS NULL THEN
        RAISE EXCEPTION 'Invalid user'
            USING HINT = 'Unknown user or password';
    END IF;
    -- Set session variables
    PERFORM set_config('user.id', account_rec.user_id, false);
    SELECT current_setting('request.path', true) into _path;
    --RAISE WARNING 'req path %', current_setting('request.path', true);
    -- Function allow without defined vessel like for anonymous role
    IF _path ~ '^\/rpc\/(login|signup|recover|reset)$' THEN
        RETURN;
    END IF;
    -- Function allow without defined vessel as user role
    -- openapi doc, user settings, otp code and vessel registration
    IF _path = '/rpc/settings_fn'
        OR _path = '/rpc/register_vessel'
        OR _path = '/rpc/update_user_preferences_fn'
        OR _path = '/rpc/versions_fn'
        OR _path = '/rpc/email_fn'
        OR _path = '/' THEN
        RETURN;
    END IF;
    -- Check a vessel and user exist
    SELECT auth.vessels.* INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = auth.accounts.email
            AND auth.accounts.email = _email;
    -- check if boat exist yet?
    IF vessel_rec.owner_email IS NULL THEN
        -- Return http status code 551 with message
        RAISE sqlstate 'PT551' using
            message = 'Vessel Required',
            detail = 'Invalid vessel',
            hint = 'Unknown vessel';
        --RETURN; -- ignore if not exist
    END IF;
    -- Redundant?
    IF vessel_rec.vessel_id IS NULL THEN
        RAISE EXCEPTION 'Invalid vessel'
            USING HINT = 'Unknown vessel id';
    END IF;
    -- Set session variables
    PERFORM set_config('vessel.id', vessel_rec.vessel_id, false);
    PERFORM set_config('vessel.name', vessel_rec.name, false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.id [%]', current_setting('vessel.id', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.name [%]', current_setting('vessel.name', false);
  ELSIF _role = 'vessel_role' THEN
    SELECT current_setting('request.path', true) into _path;
    --RAISE WARNING 'req path %', current_setting('request.path', true);
    -- Function allow without defined vessel like for anonymous role
    IF _path ~ '^\/rpc\/(oauth_\w+)$' THEN
        RETURN;
    END IF;
    -- Extract vessel_id from jwt token
    SELECT current_setting('request.jwt.claims', true)::json->>'vid' INTO _vid;
    -- Check the vessel and user exist
    SELECT auth.vessels.* INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = auth.accounts.email
            AND auth.accounts.email = _email
            AND auth.vessels.vessel_id = _vid;
    IF vessel_rec.owner_email IS NULL THEN
        RAISE EXCEPTION 'Invalid vessel'
            USING HINT = 'Unknown vessel owner_email';
    END IF;
    PERFORM set_config('vessel.id', vessel_rec.vessel_id, false);
    PERFORM set_config('vessel.name', vessel_rec.name, false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.name %', current_setting('vessel.name', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.id %', current_setting('vessel.id', false);
  ELSIF _role = 'api_anonymous' THEN
    --RAISE WARNING 'public.check_jwt() api_anonymous';
    -- Check if path is the a valid allow anonymous path
    SELECT current_setting('request.path', true) ~ '^/(logs_view|log_view|rpc/timelapse_fn|monitoring_view|stats_logs_view|stats_moorages_view|rpc/stats_logs_fn)$' INTO _ppath;
    if _ppath is True then
        -- Check is custom header is present and valid
        SELECT current_setting('request.headers', true)::json->>'x-is-public' into _pheader;
        RAISE WARNING 'public.check_jwt() api_anonymous _pheader [%]', _pheader;
        if _pheader is null then
            RAISE EXCEPTION 'Invalid public_header'
                USING HINT = 'Stop being so evil and maybe you can log in';
        end if;
        SELECT convert_from(decode(_pheader, 'base64'), 'utf-8')
                            ~ '\w+,public_(logs|logs_list|stats|timelapse|monitoring),\d+$' into _pvalid;
        RAISE WARNING 'public.check_jwt() api_anonymous _pvalid [%]', _pvalid;
        if _pvalid is null or _pvalid is False then
            RAISE EXCEPTION 'Invalid public_valid'
                USING HINT = 'Stop being so evil and maybe you can log in';
        end if;
        WITH regex AS (
            SELECT regexp_match(
                        convert_from(
                            decode(_pheader, 'base64'), 'utf-8'),
                        '(\w+),(public_(logs|logs_list|stats|timelapse|monitoring)),(\d+)$') AS match
            )
        SELECT match[1], match[2], match[4] into _pvessel, _ptype, _pid
            FROM regex;
        RAISE WARNING 'public.check_jwt() api_anonymous [%] [%] [%]', _pvessel, _ptype, _pid;
        if _pvessel is not null and _ptype is not null then
            -- Everything seem fine, get the vessel_id base on the vessel name.
            SELECT _ptype::name = any(enum_range(null::public_type)::name[]) INTO valid_public_type;
            IF valid_public_type IS False THEN
                -- Ignore entry if type is invalid
                RAISE EXCEPTION 'Invalid public_type'
                    USING HINT = 'Stop being so evil and maybe you can log in';
            END IF;
            -- Check if boat name match public_vessel name
            boat := '^' || _pvessel || '$';
            IF _ptype ~ '^public_(logs|timelapse)$' AND _pid > 0 THEN
                WITH log as (
                    SELECT vessel_id from api.logbook l where l.id = _pid
                )
                SELECT v.vessel_id, v.name into anonymous
                    FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs, log l
                    WHERE v.vessel_id = l.vessel_id
                        AND a.email = v.owner_email
                        AND a.preferences->>'public_vessel'::text ~* boat
                        AND prefs.key = _ptype::TEXT
                        AND prefs.value::BOOLEAN = true;
                RAISE WARNING '-> ispublic_fn public_logs output boat:[%], type:[%], result:[%]', _pvessel, _ptype, anonymous;
                IF anonymous.vessel_id IS NOT NULL THEN
                    PERFORM set_config('vessel.id', anonymous.vessel_id, false);
                    PERFORM set_config('vessel.name', anonymous.name, false);
                    RETURN;
                END IF;
            ELSE
                SELECT v.vessel_id, v.name into anonymous
                        FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs
                        WHERE a.email = v.owner_email
                            AND a.preferences->>'public_vessel'::text ~* boat
                            AND prefs.key = _ptype::TEXT
                            AND prefs.value::BOOLEAN = true;
                RAISE WARNING '-> ispublic_fn output boat:[%], type:[%], result:[%]', _pvessel, _ptype, anonymous;
                IF anonymous.vessel_id IS NOT NULL THEN
                    PERFORM set_config('vessel.id', anonymous.vessel_id, false);
                    PERFORM set_config('vessel.name', anonymous.name, false);
                    RETURN;
                END IF;
            END IF;
            RAISE sqlstate 'PT404' using message = 'unknown resource';
        END IF; -- end anonymous path
    END IF;
  ELSIF _role <> 'api_anonymous' THEN
    RAISE EXCEPTION 'Invalid role'
      USING HINT = 'Stop being so evil and maybe you can log in';
  END IF;
END
$$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    public.check_jwt
    IS 'PostgREST API db-pre-request check, set_config according to role (api_anonymous,vessel_role,user_role)';

---------------------------------------------------------------------------
-- Function to trigger cron_jobs using API for tests.
-- Todo limit access and permission
-- Run con jobs
CREATE OR REPLACE FUNCTION public.run_cron_jobs() RETURNS void AS $$
BEGIN
    -- In correct order
    perform public.cron_process_new_notification_fn();
    perform public.cron_process_monitor_online_fn();
    --perform public.cron_process_grafana_fn();
    perform public.cron_process_pre_logbook_fn();
    perform public.cron_process_new_logbook_fn();
    perform public.cron_process_new_stay_fn();
    --perform public.cron_process_new_moorage_fn();
    perform public.cron_process_monitor_offline_fn();
END
$$ language plpgsql;

---------------------------------------------------------------------------
-- Delete all data for a account by email and vessel_id
CREATE OR REPLACE FUNCTION public.delete_account_fn(IN _email TEXT, IN _vessel_id TEXT) RETURNS BOOLEAN
AS $delete_account$
BEGIN
    --select count(*) from api.metrics m where vessel_id = _vessel_id;
    delete from api.metrics m where vessel_id = _vessel_id;
    --select * from api.metadata m where vessel_id = _vessel_id;
    delete from api.moorages m where vessel_id = _vessel_id;
    delete from api.logbook l where vessel_id = _vessel_id;
    delete from api.stays s where vessel_id = _vessel_id;
    delete from api.metadata m where vessel_id = _vessel_id;
    --select * from auth.vessels v where vessel_id = _vessel_id;
    delete from auth.vessels v where vessel_id = _vessel_id;
    --select * from auth.accounts a where email = _email;
    delete from auth.accounts a where email = _email;
    RETURN True;
END
$delete_account$ language plpgsql;

-- Dump all data for a account by email and vessel_id
CREATE OR REPLACE FUNCTION public.dump_account_fn(IN _email TEXT, IN _vessel_id TEXT) RETURNS BOOLEAN
AS $dump_account$
BEGIN
    RETURN True;
    -- TODO use COPY but we can't all in one?
    select count(*) from api.metrics m where vessel_id = _vessel_id;
    select * from api.metadata m where vessel_id = _vessel_id;
    select * from api.logbook l where vessel_id = _vessel_id;
    select * from api.moorages m where vessel_id = _vessel_id;
    select * from api.stays s where vessel_id = _vessel_id;
    select * from auth.vessels v where vessel_id = _vessel_id;
    select * from auth.accounts a where email  = _email;
END
$dump_account$ language plpgsql;

CREATE OR REPLACE FUNCTION public.delete_vessel_fn(IN _vessel_id TEXT) RETURNS BOOLEAN
AS $delete_vessel$
BEGIN
    RETURN True;
    select count(*) from api.metrics m where vessel_id = _vessel_id;
    delete from api.metrics m where vessel_id = _vessel_id;
    select * from api.metadata m where vessel_id = _vessel_id;
    delete from api.metadata m where vessel_id = _vessel_id;
    delete from api.logbook l where vessel_id = _vessel_id;
    delete from api.moorages m where vessel_id = _vessel_id;
    delete from api.stays s where vessel_id = _vessel_id;
END
$delete_vessel$ language plpgsql;