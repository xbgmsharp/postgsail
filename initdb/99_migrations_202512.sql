---------------------------------------------------------------------------
-- Copyright 2021-2025 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration December 2025
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';


-- Remove Duplicated Foreign Key Constraints
ALTER TABLE api.logbook DROP CONSTRAINT fk_from_moorage;
ALTER TABLE api.logbook DROP CONSTRAINT fk_to_moorage;

-- Update
--ALTER TABLE api.logbook ALTER COLUMN extra SET DEFAULT '{}'::JSONB;

-- Add user_data column to main tables
ALTER TABLE api.metadata ADD COLUMN IF NOT EXISTS user_data JSONB DEFAULT '{}'::jsonb;
ALTER TABLE api.logbook ADD COLUMN IF NOT EXISTS user_data JSONB DEFAULT '{}'::jsonb;
ALTER TABLE api.moorages ADD COLUMN IF NOT EXISTS user_data JSONB DEFAULT '{}'::jsonb;
ALTER TABLE api.stays ADD COLUMN IF NOT EXISTS user_data JSONB DEFAULT '{}'::jsonb;

-- Create GIN indexes for JSONB performance
CREATE INDEX IF NOT EXISTS metadata_user_data_idx ON api.metadata USING gin (user_data);
CREATE INDEX IF NOT EXISTS logbook_user_data_idx ON api.logbook USING gin (user_data);
CREATE INDEX IF NOT EXISTS logbook_extra_idx ON api.logbook USING gin (extra);
CREATE INDEX IF NOT EXISTS moorages_user_data_idx ON api.moorages USING gin (user_data);
CREATE INDEX IF NOT EXISTS stays_user_data_idx ON api.stays USING gin (user_data);

-- Add comments
COMMENT ON COLUMN api.metadata.user_data IS 'User-defined data including vessel polar (theoretical performance), make/model, and preferences';
COMMENT ON COLUMN api.logbook.user_data IS 'User-defined data Log-specific data including actual tags, observations, images and custom fields';
COMMENT ON COLUMN api.moorages.user_data IS 'User-defined data Mooring-specific data including images and custom fields';
COMMENT ON COLUMN api.stays.user_data IS 'User-defined data Stay-specific data including images and custom fields';

-- Remove unused functions
DROP FUNCTION IF EXISTS api.logs_geojson_fn;
DROP FUNCTION IF EXISTS api.stays_geojson_fn;
DROP FUNCTION IF EXISTS api.moorages_geojson_fn;

-- Remove images function
DROP FUNCTION IF EXISTS api.image;
DROP FUNCTION IF EXISTS public.decode_base64_image_fn;

-- Remove table _ext triggers and functions
DROP TRIGGER IF EXISTS metadata_ext_decode_image_trigger ON api.metadata_ext;
DROP TRIGGER IF EXISTS logbook_ext_decode_image_trigger ON api.logbook_ext;
DROP TRIGGER IF EXISTS stays_ext_decode_image_trigger ON api.stays_ext;
DROP TRIGGER IF EXISTS moorages_ext_decode_image_trigger ON api.moorages_ext;
DROP TRIGGER IF EXISTS metadata_ext_update_added_at_trigger ON api.metadata_ext;
DROP TRIGGER IF EXISTS update_tbl_ext_added_at_trigger_fn ON api.logbook_ext;
DROP TRIGGER IF EXISTS logbook_ext_update_added_at_trigger ON api.logbook_ext;
DROP TRIGGER IF EXISTS moorages_ext_update_added_at_trigger ON api.moorages_ext;
DROP TRIGGER IF EXISTS stays_ext_update_added_at_trigger ON api.stays_ext;
DROP FUNCTION IF EXISTS public.update_metadata_userdata_added_at_trigger_fn;
DROP FUNCTION IF EXISTS public.update_metadata_ext_added_at_trigger_fn;
DROP FUNCTION IF EXISTS public.update_tbl_ext_decode_base64_image_trigger_fn;
DROP FUNCTION IF EXISTS public.update_tbl_ext_added_at_trigger_fn;

-- Remove ext tables if existing
DROP TABLE IF EXISTS api.logbook_ext CASCADE;
DROP TABLE IF EXISTS api.moorages_ext CASCADE;
DROP TABLE IF EXISTS api.metadata_ext CASCADE;
DROP TABLE IF EXISTS api.stays_ext CASCADE;

-- DROP FUNCTION public.process_post_logbook_fn(int4);
-- Update public.process_post_logbook_fn, refactor polar user_data in logbook table
CREATE OR REPLACE FUNCTION public.process_post_logbook_fn(_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
    DECLARE
        obs_json jsonb default '{ "seaState": -1, "cloudCoverage": -1, "visibility": -1}'::jsonb;
        logbook_rec record;
        log_settings jsonb;
        user_settings jsonb;
        extra_json jsonb;
        log_img_url text;
        --logs_img_url text;
        log_stats text;
        --extent_bbox text;
		v_ship_type NUMERIC;
    BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_post_logbook_fn invalid input %', _id;
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
            RAISE WARNING '-> process_post_logbook_fn invalid logbook %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', logbook_rec.vessel_id, false);
        --RAISE WARNING 'public.process_post_logbook_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);

        -- Get ship_type from metadata
        SELECT ship_type
          INTO v_ship_type
          FROM api.metadata
          WHERE vessel_id = logbook_rec.vessel_id;

        -- Check if ship_type = 36 Sailing Vessel
        IF v_ship_type = 36 THEN
          -- Update polar user_data in logbook table
          UPDATE api.logbook 
            SET extra = COALESCE(extra, '{}'::jsonb) || jsonb_build_object(
                  'polar', api.export_logbook_polar_csv_fn(logbook_rec.id),
                  'polar_updated_at', to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                )
          WHERE id = logbook_rec.id;
        END IF;

        -- Add observations to user_data in logbook table
        UPDATE api.logbook
          SET user_data = jsonb_build_object('observations', obs_json)
        WHERE id = logbook_rec.id;

        -- Generate logbook image map name from QGIS
        SELECT CONCAT('log_', logbook_rec.vessel_id::TEXT, '_', logbook_rec.id, '.png') INTO log_img_url;
        --SELECT ST_Extent(ST_Transform(logbook_rec.track_geom, 3857))::TEXT AS envelope INTO extent_bbox FROM api.logbook WHERE id = logbook_rec.id;
        --PERFORM public.qgis_getmap_py_fn(logbook_rec.vessel_id::TEXT, logbook_rec.id, extent_bbox::TEXT, False);
        -- Generate logs image map name from QGIS
        --WITH merged AS (
        --    SELECT ST_Union(logbook_rec.track_geom) AS merged_geometry
        --        FROM api.logbook WHERE vessel_id = logbook_rec.vessel_id
        --)
        --SELECT ST_Extent(ST_Transform(merged_geometry, 3857))::TEXT AS envelope INTO extent_bbox FROM merged;
        --SELECT CONCAT('logs_', logbook_rec.vessel_id::TEXT, '_', logbook_rec.id, '.png') INTO logs_img_url;
        --PERFORM public.qgis_getmap_py_fn(logbook_rec.vessel_id::TEXT, logbook_rec.id, extent_bbox::TEXT, True);

        -- Add formatted distance and duration for email notification
        SELECT CONCAT(ROUND(logbook_rec.distance, 2), ' NM / ', ROUND(EXTRACT(epoch FROM logbook_rec.duration)/3600,2), 'H') INTO log_stats;

        -- Prepare notification, gather user settings
        SELECT json_build_object('logbook_name', logbook_rec.name,
            'logbook_link', logbook_rec.id,
            'logbook_img', log_img_url,
            'logbook_stats', log_stats) INTO log_settings;
        user_settings := get_user_settings_from_vesselid_fn(logbook_rec.vessel_id::TEXT);
        SELECT user_settings::JSONB || log_settings::JSONB into user_settings;
        RAISE NOTICE '-> debug process_post_logbook_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        RAISE NOTICE '-> debug process_post_logbook_fn log_settings [%]', log_settings;
        -- Send notification
        PERFORM send_notification_fn('logbook'::TEXT, user_settings::JSONB);
        -- Process badges
        RAISE NOTICE '-> debug process_post_logbook_fn user_settings [%]', user_settings->>'email'::TEXT;
        PERFORM set_config('user.email', user_settings->>'email'::TEXT, false);
        PERFORM badges_logbook_fn(logbook_rec.id, logbook_rec._to_time::TEXT);
        PERFORM badges_geom_fn(logbook_rec.id, logbook_rec._to_time::TEXT);
    END;
$function$
;
-- Description
COMMENT ON FUNCTION public.process_post_logbook_fn(int4) IS 'Notify user for new logbook.';

-- DROP FUNCTION api.merge_logbook_fn(int4, int4);
-- Update api.merge_logbook_fn, refactor polar user_data in logbook table
CREATE OR REPLACE FUNCTION api.merge_logbook_fn(id_start integer, id_end integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
    DECLARE
        logbook_rec_start record;
        logbook_rec_end record;
        log_name text;
        avg_rec record;
        geo_rec record;
        geojson jsonb;
        extra_json jsonb;
        t_rec record;
        _max_wind_speed NUMERIC;
        _avg_wind_speed NUMERIC;
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

       	-- generate logbook name, concat _from_location and _to_location from moorage name
       	SELECT CONCAT(logbook_rec_start._from, ' to ', logbook_rec_end._to) INTO log_name;

        -- mobilitydb, add spaciotemporal sequence
        -- reduce the numbers of metrics by skipping row or aggregate time-series
        -- By default the signalk PostgSail plugin report one entry every minute.
        IF avg_rec.count_metric < 30 THEN -- if less ~20min trip we keep it all data
            t_rec := public.logbook_update_metrics_short_fn(avg_rec.count_metric, logbook_rec_start._from_time, logbook_rec_end._to_time);
        --ELSIF avg_rec.count_metric < 2000 THEN -- if less ~33h trip we skip data
        --    t_rec := public.logbook_update_metrics_fn(avg_rec.count_metric, logbook_rec_start._from_time, logbook_rec_end._to_time);
        ELSE -- As we have too many data, we time-series aggregate data
            t_rec := public.logbook_update_metrics_timebucket_fn(avg_rec.count_metric, logbook_rec_start._from_time, logbook_rec_end._to_time);
        END IF;
        --RAISE NOTICE 'mobilitydb [%]', t_rec;
        IF t_rec.trajectory IS NULL THEN
            RAISE WARNING '-> merge_logbook_fn, vessel_id [%], invalid mobilitydb data [%] [%]', logbook_rec_start.vessel_id, logbook_rec_start.id, t_rec;
            RETURN;
        END IF;
        IF t_rec.truewindspeed IS NULL AND t_rec.windspeedapparent IS NOT NULL THEN
            _max_wind_speed := maxValue(t_rec.windspeedapparent)::NUMERIC(6,2); -- Fallback to apparent wind speed
            _avg_wind_speed := twAvg(t_rec.windspeedapparent)::NUMERIC(6,2); -- Fallback to apparent wind speed
        ELSE
            _max_wind_speed := maxValue(t_rec.truewindspeed)::NUMERIC(6,2);
            _avg_wind_speed := twAvg(t_rec.truewindspeed)::NUMERIC(6,2);
        END IF;
        -- add the avg_wind_speed
        -- Update the avg_wind_speed from mobilitydb data -- TWS in knots
        extra_json := extra_json || jsonb_build_object('avg_wind_speed', _avg_wind_speed);

        RAISE NOTICE 'Updating valid logbook entry logbook id:[%] start:[%] end:[%]', logbook_rec_start.id, logbook_rec_start._from_time, logbook_rec_end._to_time;
        UPDATE api.logbook
            SET
                duration = (logbook_rec_end._to_time::TIMESTAMPTZ - logbook_rec_start._from_time::TIMESTAMPTZ),
                -- Problem with invalid SOG metrics
                --avg_speed = twAvg(t_rec.speedoverground)::NUMERIC(6,2), -- avg speed in knots
                max_speed = maxValue(t_rec.speedoverground)::NUMERIC(6,2), -- max speed in knots
                -- Calculate speed using mobility from m/s to knots - MobilityDB calculates instantaneous speed between consecutive GPS points
                avg_speed = (twavg(speed(t_rec.trajectory)) * 1.94384)::NUMERIC(6,2), -- avg speed in knots
                --max_speed = (maxValue(speed(t_rec.trajectory)) * 1.94384)::NUMERIC(6,2), -- max speed in knots
                max_wind_speed = _max_wind_speed, -- TWS in knots
                -- Set _to metrics from end logbook
                _to = logbook_rec_end._to,
                _to_moorage_id = logbook_rec_end._to_moorage_id,
                _to_lat = logbook_rec_end._to_lat,
                _to_lng = logbook_rec_end._to_lng,
                _to_time = logbook_rec_end._to_time,
                name = log_name,
                --distance = geo_rec._track_distance, -- in Nautical Miles
                distance = (length(t_rec.trajectory)/1852)::NUMERIC(10,2), -- in Nautical Miles
                extra = extra_json,
                notes = NULL, -- reset pre_log process
                trip = t_rec.trajectory,
                trip_cog = t_rec.courseovergroundtrue,
                trip_sog = t_rec.speedoverground,
                trip_aws = t_rec.windspeedapparent,
                trip_awa = t_rec.windangleapparent,
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
                trip_hum_out = t_rec.outsidehumidity,
                trip_tank_level = t_rec.tankLevel,
                trip_solar_voltage = t_rec.solarVoltage,
                trip_solar_power = t_rec.solarPower,
                trip_heading = t_rec.heading
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
        ***/
        -- Update logbook mark for deletion
        UPDATE api.logbook
            SET notes = 'mark for deletion'
            WHERE id = logbook_rec_end.id;
        -- Update related stays mark for deletion
        UPDATE api.stays
            SET notes = 'mark for deletion'
            WHERE arrived = logbook_rec_start._to_time;
        -- Update related moorages mark for deletion
        -- We can't delete the stays and moorages as it might expand to other previous logs and stays
        --UPDATE api.moorages
        --    SET notes = 'mark for deletion'
        --    WHERE id = logbook_rec_start._to_moorage_id;

        -- Clean up, remove invalid logbook and stay, moorage entry
        DELETE FROM api.logbook WHERE id = logbook_rec_end.id;
        RAISE WARNING '-> merge_logbook_fn delete logbook id [%]', logbook_rec_end.id;
        DELETE FROM api.stays WHERE arrived = logbook_rec_start._to_time;
        RAISE WARNING '-> merge_logbook_fn delete stay arrived [%]', logbook_rec_start._to_time;
        -- We can't delete the stays and moorages as it might expand to other previous logs and stays
		-- Delete the moorage only if exactly one record exists with that id.
        DELETE FROM api.moorages
			WHERE id = logbook_rec_start._to_moorage_id
			  AND (
			    SELECT COUNT(*) 
			    FROM api.logbook
    			WHERE _from_moorage_id = logbook_rec_start._to_moorage_id
					OR _to_moorage_id = logbook_rec_start._to_moorage_id
			  ) = 1;
        RAISE WARNING '-> merge_logbook_fn delete moorage id [%]', logbook_rec_start._to_moorage_id;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION api.merge_logbook_fn(int4, int4) IS 'Merge 2 logbook by id, from the start of the lower log id and the end of the higher log id, update the calculate data as well (avg, geojson)';

-- DROP FUNCTION public.logbook_update_extra_json_fn(in int4, in text, in text, out json);
-- Update public.logbook_update_extra_json_fn, remove observations handling (refactor to process_post_logbook_fn) for user_data
CREATE OR REPLACE FUNCTION public.logbook_update_extra_json_fn(_id integer, _start text, _end text, OUT _extra_json json)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
    declare
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
        SELECT jsonb_build_object('metrics', metrics_json) INTO _extra_json;
        RAISE NOTICE '-> logbook_update_extra_json_fn log_json: %, runtime_json: %, _extra_json: %', log_json, runtime_json, _extra_json;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION public.logbook_update_extra_json_fn(in int4, in text, in text, out json) IS 'Update log details with extra_json using `propulsion.*.runTime` and `navigation.log`';

-- DROP FUNCTION api.vessel_extended_fn();
-- Update vessel_extended_fn refactor to use user_data from metadata table
CREATE OR REPLACE FUNCTION api.vessel_extended_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id text := current_setting('vessel.id', false);
    result jsonb;
BEGIN
    SELECT jsonb_build_object(
          'make_model', m.user_data->'make_model',
          'has_polar', m.user_data->'polar' IS NOT NULL,
          'has_images',
            CASE 
              WHEN jsonb_array_length(m.user_data->'images') > 0 THEN true
              ELSE false
            END,
          'image_url', m.user_data->'images'->0->>'url',
          'image_updated_at', m.user_data->'images'->0->>'updated_at',
          'images', m.user_data->'images'
      )
      INTO result
      FROM api.metadata m
      WHERE vessel_id = v_id;

    IF result IS NULL THEN
        result := jsonb_build_object(
            'make_model', NULL,
            'has_polar', false,
            'has_image', false,
            'image_url', NULL,
            'image_updated_at', NULL
        );
    END IF;

    RETURN result;
END;
$function$
;
-- Description
COMMENT ON FUNCTION api.vessel_extended_fn() IS 'Return vessel details from metadata_ext (polar csv,image url, make model)';

-- DROP FUNCTION public.update_metadata_ext_added_at_trigger_fn();
-- Update metadata trigger function to set polar_updated_at and image_updated_at
CREATE OR REPLACE FUNCTION public.update_metadata_userdata_added_at_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Only update user_data if it's a JSONB object and has changed
  IF NEW.user_data IS NOT NULL 
      AND NEW.user_data IS DISTINCT FROM OLD.user_data
      AND jsonb_typeof(NEW.user_data) = 'object' THEN
    -- Check if polar data has changed in user_data
    IF (NEW.user_data->'polar') IS DISTINCT FROM (OLD.user_data->'polar') THEN
      NEW.user_data := jsonb_set(
        COALESCE(NEW.user_data, '{}'::jsonb),
        '{polar_updated_at}',
        to_jsonb(to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
      );
    END IF;

    -- Check if images data has changed in user_data
    IF (NEW.user_data->'images') IS DISTINCT FROM (OLD.user_data->'images') THEN
      NEW.user_data := jsonb_set(
        COALESCE(NEW.user_data, '{}'::jsonb),
        '{image_updated_at}',
        to_jsonb(to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.update_metadata_userdata_added_at_trigger_fn() IS 'Update polar_updated_at and image_updated_at timestamps within user_data jsonb when polar or images change';

create trigger metadata_update_user_data_trigger before
update
    on
    api.metadata for each row execute function update_metadata_userdata_added_at_trigger_fn();

COMMENT ON TRIGGER metadata_update_user_data_trigger ON api.metadata IS 'BEFORE UPDATE ON api.metadata run function public.update_metadata_userdata_added_at_trigger_fn to update the user_data field with current date in ISO format when polar or images change';

-- Update logbook,moorages,stays trigger function to set image_updated_at
CREATE OR REPLACE FUNCTION public.update_tbl_userdata_added_at_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Only update user_data if it's a JSONB object and has changed
  IF NEW.user_data IS NOT NULL 
      AND NEW.user_data IS DISTINCT FROM OLD.user_data
      AND jsonb_typeof(NEW.user_data) = 'object' THEN
    -- Check if images data has changed in user_data
    IF (NEW.user_data->'images') IS DISTINCT FROM (OLD.user_data->'images') THEN
      NEW.user_data := jsonb_set(
        COALESCE(NEW.user_data, '{}'::jsonb),
        '{image_updated_at}',
        to_jsonb(to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.update_tbl_userdata_added_at_trigger_fn() IS 'Update image_updated_at timestamps within user_data jsonb when images change';

CREATE TRIGGER logbook_update_user_data_trigger before
UPDATE
    ON
    api.logbook for each row execute function update_tbl_userdata_added_at_trigger_fn();

COMMENT ON TRIGGER logbook_update_user_data_trigger ON api.logbook IS 'BEFORE UPDATE ON api.logbook run function public.update_tbl_userdata_added_at_trigger_fn to update the user_data field with current date in ISO format when polar or images change';

CREATE TRIGGER stays_update_user_data_trigger before
UPDATE
    ON
    api.stays for each row execute function update_tbl_userdata_added_at_trigger_fn();

COMMENT ON TRIGGER stays_update_user_data_trigger ON api.stays IS 'BEFORE UPDATE ON api.stays run function public.update_tbl_userdata_added_at_trigger_fn to update the user_data field with current date in ISO format when polar or images change';

CREATE TRIGGER moorages_update_user_data_trigger before
UPDATE
    ON
    api.moorages for each row execute function update_tbl_userdata_added_at_trigger_fn();

COMMENT ON TRIGGER moorages_update_user_data_trigger ON api.moorages IS 'BEFORE UPDATE ON api.moorages run function public.update_tbl_userdata_added_at_trigger_fn to update the user_data field with current date in ISO format when polar or images change';

-- api.logs_view source
-- Update logs_view with refactored user_data logic
CREATE OR REPLACE VIEW api.logs_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT id,
    name,
    _from AS "from",
    _from_time AS started,
    _to AS "to",
    _to_time AS ended,
    distance,
    duration,
    _from_moorage_id,
    _to_moorage_id,
    user_data -> 'tags'::text AS tags
   FROM api.logbook l
  WHERE name IS NOT NULL AND _to_time IS NOT NULL
  ORDER BY _from_time DESC;
-- Description
COMMENT ON VIEW api.logs_view IS 'Logs web view';

-- api.log_view source
-- Update log_view with refactored user_data logic
CREATE OR REPLACE VIEW api.log_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT l.id,
    l.name,
    l._from AS "from",
    l._from_time AS started,
    l._to AS "to",
    l._to_time AS ended,
    l.distance,
    l.duration,
    l.notes,
    api.export_logbook_geojson_trip_fn(l.id) AS geojson,
    l.avg_speed,
    l.max_speed,
    l.max_wind_speed,
    l.extra,
    l._from_moorage_id AS from_moorage_id,
    l._to_moorage_id AS to_moorage_id,
    l.extra->'polar' AS polar,
    l.user_data->'images' AS images,
    l.user_data->'tags' AS tags,
    l.user_data->'observations' AS observations,
    CASE 
        WHEN jsonb_array_length(l.user_data->'images') > 0 THEN true
        ELSE false
    END AS has_images
   FROM api.logbook l
  WHERE l._to_time IS NOT NULL AND l.trip IS NOT NULL
  ORDER BY l._from_time DESC;
-- Description
COMMENT ON VIEW api.log_view IS 'Log web view';

-- api.logs_geojson_view source
-- Update logs_geojson_view with refactored user_data logic
CREATE OR REPLACE VIEW api.logs_geojson_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT id,
    name,
    starttimestamp,
    st_asgeojson(tbl.*)::jsonb AS geojson
   FROM ( SELECT l.id,
            l.name,
            starttimestamp(l.trip) AS starttimestamp,
            endtimestamp(l.trip) AS endtimestamp,
            duration(l.trip) AS duration,
            (length(l.trip) * 0.0005399568::double precision)::numeric AS distance,
            maxvalue(l.trip_sog) AS max_sog,
            maxvalue(l.trip_tws) AS max_tws,
            maxvalue(l.trip_twd) AS max_twd,
            maxvalue(l.trip_depth) AS max_depth,
            maxvalue(l.trip_temp_water) AS max_temp_water,
            maxvalue(l.trip_temp_out) AS max_temp_out,
            maxvalue(l.trip_pres_out) AS max_pres_out,
            maxvalue(l.trip_hum_out) AS max_hum_out,
            maxvalue(l.trip_batt_charge) AS max_stateofcharge,
            maxvalue(l.trip_batt_voltage) AS max_voltage,
            maxvalue(l.trip_solar_voltage) AS max_solar_voltage,
            maxvalue(l.trip_solar_power) AS max_solar_power,
            maxvalue(l.trip_tank_level) AS max_tank_level,
            twavg(l.trip_sog) AS avg_sog,
            twavg(l.trip_tws) AS avg_tws,
            twavg(l.trip_twd) AS avg_twd,
            twavg(l.trip_depth) AS avg_depth,
            twavg(l.trip_temp_water) AS avg_temp_water,
            twavg(l.trip_temp_out) AS avg_temp_out,
            twavg(l.trip_pres_out) AS avg_pres_out,
            twavg(l.trip_hum_out) AS avg_hum_out,
            twavg(l.trip_batt_charge) AS avg_stateofcharge,
            twavg(l.trip_batt_voltage) AS avg_voltage,
            twavg(l.trip_solar_voltage) AS avg_solar_voltage,
            twavg(l.trip_solar_power) AS avg_solar_power,
            twavg(l.trip_tank_level) AS avg_tank_level,
            trajectory(l.trip)::geometry AS track_geog,
            l.extra,
            l._to_moorage_id,
            l._from_moorage_id,
            l.extra->'polar' AS polar,
            l.user_data->'images' AS images,
            l.user_data->'tags' AS tags,
            l.user_data->'observations' AS observations,
            CASE 
                WHEN jsonb_array_length(l.user_data->'images') > 0 THEN true
                ELSE false
            END AS has_images
           FROM api.logbook l
          WHERE l._to_time IS NOT NULL AND l.trip IS NOT NULL
          ORDER BY l._from_time DESC) tbl;
-- Description
COMMENT ON VIEW api.logs_geojson_view IS 'List logs as geojson';

-- api.moorage_view source
-- Update moorage_view with refactored user_data logic
CREATE OR REPLACE VIEW api.moorage_view
WITH(security_invoker=true,security_barrier=true)
AS WITH stay_details AS (
         SELECT s.moorage_id,
            s.arrived,
            s.departed,
            s.duration,
            s.id AS stay_id,
            first_value(s.id) OVER (PARTITION BY s.moorage_id ORDER BY s.arrived) AS first_seen_id,
            first_value(s.id) OVER (PARTITION BY s.moorage_id ORDER BY s.departed DESC) AS last_seen_id
           FROM api.stays s
          WHERE s.active = false
        ), stay_summary AS (
         SELECT stay_details.moorage_id,
            min(stay_details.arrived) AS first_seen,
            max(stay_details.departed) AS last_seen,
            sum(stay_details.duration) AS total_duration,
            count(*) AS stay_count,
            max(stay_details.first_seen_id) AS first_seen_id,
            max(stay_details.last_seen_id) AS last_seen_id
           FROM stay_details
          GROUP BY stay_details.moorage_id
        ), log_summary AS (
         SELECT logs.moorage_id,
            count(DISTINCT logs.id) AS log_count
           FROM ( SELECT l_1._from_moorage_id AS moorage_id,
                    l_1.id
                   FROM api.logbook l_1
                  WHERE l_1.active = false
                UNION ALL
                 SELECT l_1._to_moorage_id AS moorage_id,
                    l_1.id
                   FROM api.logbook l_1
                  WHERE l_1.active = false) logs
          GROUP BY logs.moorage_id
        )
 SELECT m.id,
    m.name,
    sa.description AS default_stay,
    sa.stay_code AS default_stay_id,
    m.notes,
    m.home_flag AS home,
    m.geog,
    m.latitude,
    m.longitude,
    COALESCE(l.log_count, 0::bigint) AS logs_count,
    COALESCE(ss.stay_count, 0::bigint) AS stays_count,
    COALESCE(ss.total_duration, 'PT0S'::interval) AS stays_sum_duration,
    ss.first_seen AS stay_first_seen,
    ss.last_seen AS stay_last_seen,
    ss.first_seen_id AS stay_first_seen_id,
    ss.last_seen_id AS stay_last_seen_id,
    CASE 
        WHEN jsonb_array_length(m.user_data->'images') > 0 THEN true
        ELSE false
    END AS has_images,
    m.user_data->'images' AS images
   FROM api.moorages m
     JOIN api.stays_at sa ON m.stay_code = sa.stay_code
     LEFT JOIN stay_summary ss ON m.id = ss.moorage_id
     LEFT JOIN log_summary l ON m.id = l.moorage_id
  WHERE m.geog IS NOT NULL
  ORDER BY ss.total_duration DESC;
-- Description
COMMENT ON VIEW api.moorage_view IS 'Moorage details web view';

-- api.moorages_geojson_view source
-- Update moorages_geojson_view with refactored user_data logic
CREATE OR REPLACE VIEW api.moorages_geojson_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT id,
    name,
    st_asgeojson(m.*)::jsonb AS geojson
   FROM ( SELECT * FROM api.moorage_view m_1
          WHERE m_1.geog IS NOT NULL) m;
-- Description
COMMENT ON VIEW api.moorages_geojson_view IS 'List moorages as geojson';

-- api.stats_moorages_view source
-- Update api.stats_moorages_view depending on api.moorage_view
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
-- Description
COMMENT ON VIEW api.stats_moorages_view IS 'Statistics Moorages web view';

-- api.stats_moorages_away_view source
-- Update api.stats_moorages_away_view depending on api.moorage_view
CREATE OR REPLACE VIEW api.stats_moorages_away_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT sa.description,
    sum(m.stays_sum_duration) AS time_spent_away_by
   FROM api.moorage_view m,
    api.stays_at sa
  WHERE m.home IS FALSE AND m.default_stay_id = sa.stay_code
  GROUP BY m.default_stay_id, sa.description
  ORDER BY m.default_stay_id;
-- Description
COMMENT ON VIEW api.stats_moorages_away_view IS 'Statistics Moorages Time Spent Away web view';

-- api.stay_view source
-- Update stay_view with refactored user_data logic
CREATE OR REPLACE VIEW api.stay_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT s.id,
    s.name,
    m.name AS moorage,
    m.id AS moorage_id,
    s.departed - s.arrived AS duration,
    sa.description AS stayed_at,
    sa.stay_code AS stayed_at_id,
    s.arrived,
    _from.id AS arrived_log_id,
    _from._to_moorage_id AS arrived_from_moorage_id,
    _from._to AS arrived_from_moorage_name,
    s.departed,
    _to.id AS departed_log_id,
    _to._from_moorage_id AS departed_to_moorage_id,
    _to._from AS departed_to_moorage_name,
    s.notes,
    CASE 
        WHEN jsonb_array_length(s.user_data->'images') > 0 THEN true
        ELSE false
    END AS has_images,
    s.user_data->'images' AS images
   FROM api.stays s
     JOIN api.stays_at sa ON s.stay_code = sa.stay_code
     JOIN api.moorages m ON s.moorage_id = m.id
     LEFT JOIN api.logbook _from ON _from._from_time = s.departed
     LEFT JOIN api.logbook _to ON _to._to_time = s.arrived
  WHERE s.departed IS NOT NULL AND _from._to_moorage_id IS NOT NULL AND s.name IS NOT NULL
  ORDER BY s.arrived DESC;
-- Description
COMMENT ON VIEW api.stay_view IS 'Stay web view';

-- api.stay_explore_view source
-- Update stay_explore_view with refactored user_data logic
CREATE OR REPLACE VIEW api.stay_explore_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT s.id AS stay_id,
    m.id AS moorage_id,
    m.name AS moorage_name,
    s.name AS stay_name,
    s.arrived,
    s.stay_code,
    s.latitude,
    s.longitude,
    s.notes AS stay_notes,
    m.notes AS moorage_notes,
    CASE 
        WHEN jsonb_array_length(s.user_data->'images') > 0 THEN true
        ELSE false
    END AS has_images,
    s.user_data->'images' AS images,
    s.id,
    s.name
   FROM api.stays s
     LEFT JOIN api.moorages m ON s.moorage_id = m.id
  ORDER BY s.arrived DESC;

COMMENT ON VIEW api.stay_explore_view IS 'List moorages notes order by stays';

-- api.stays_geojson_view source
-- Update stays_geojson_view with refactored user_data logic
CREATE OR REPLACE VIEW api.stays_geojson_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT st_asgeojson(tbl.*)::jsonb AS geojson
   FROM ( SELECT stay_explore_view.stay_id,
            stay_explore_view.moorage_id,
            stay_explore_view.moorage_name,
            stay_explore_view.stay_name,
            stay_explore_view.arrived,
            stay_explore_view.stay_code,
            stay_explore_view.latitude,
            stay_explore_view.longitude,
            stay_explore_view.stay_notes,
            stay_explore_view.moorage_notes,
            stay_explore_view.has_images,
            stay_explore_view.images,
            st_makepoint(stay_explore_view.longitude, stay_explore_view.latitude) AS st_makepoint
           FROM api.stay_explore_view) tbl;
-- Description
COMMENT ON VIEW api.stays_geojson_view IS 'List stays as geojson';

-- DROP FUNCTION api.update_logbook_observations_fn(int4, text);
-- Update api.update_logbook_observations_fn, refactor to use user_data
CREATE OR REPLACE FUNCTION api.update_logbook_observations_fn(_id integer, observations text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
BEGIN
    -- Merge existing observations with the new observations objects
    RAISE NOTICE '-> update_logbook_userdata_fn id:[%] observations:[%]', _id, observations;
    -- { 'observations': { 'seaState': -1, 'cloudCoverage': -1, 'visibility': -1 } }
    UPDATE api.logbook SET user_data = public.jsonb_recursive_merge(user_data, observations::jsonb) WHERE id = _id;
    IF FOUND IS True THEN
        RETURN True;
    END IF;
    RETURN False;
END;
$function$
;
-- Description
COMMENT ON FUNCTION api.update_logbook_observations_fn(int4, text) IS 'Update/Add logbook observations jsonb key pair value';

DROP FUNCTION IF EXISTS api.update_metadata_userdata_fn;
-- Add api.update_metadata_userdata_fn, Handle user_data objects
CREATE OR REPLACE FUNCTION api.update_metadata_userdata_fn(userdata text)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
DECLARE
BEGIN
    -- Merge existing user_data with the new user_data objects
    RAISE NOTICE '-> update_metadata_userdata_fn userdata:[%]', userdata;
    -- { 'make_model': 'my super yacht' }
    UPDATE api.metadata SET user_data = public.jsonb_recursive_merge(user_data, userdata::jsonb);
    IF FOUND IS True THEN
        RETURN True;
    END IF;
    RETURN False;
END;
$function$
;
-- Description
COMMENT ON FUNCTION api.update_metadata_userdata_fn IS 'Update/Add metadata user_data jsonb key pair value';

-- DROP FUNCTION public.stay_delete_trigger_fn();
-- Update stay_delete_trigger_fn to remove stays_ext references
CREATE OR REPLACE FUNCTION public.stay_delete_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE NOTICE 'stay_delete_trigger_fn [%]', OLD;
    -- If api.stays is deleted,
    -- Delete process_queue references
    DELETE FROM public.process_queue p
        WHERE p.payload = OLD.id::TEXT
            AND p.ref_id = OLD.vessel_id
            AND p.channel LIKE '%_stays';
    RETURN OLD;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.stay_delete_trigger_fn() IS 'When stays is delete, stays_ext need to deleted as well.';

-- DROP FUNCTION public.logbook_delete_trigger_fn();
-- Update logbook_delete_trigger_fn to remove logbook_ext references
CREATE OR REPLACE FUNCTION public.logbook_delete_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE NOTICE 'logbook_delete_trigger_fn [%]', OLD;
    -- If api.logbook is deleted,
    -- Delete process_queue references
    DELETE FROM public.process_queue p
        WHERE p.payload = OLD.id::TEXT
            AND p.ref_id = OLD.vessel_id
            AND p.channel LIKE '%_logbook';
    RETURN OLD;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.logbook_delete_trigger_fn() IS 'When logbook is delete, logbook_ext need to deleted as well.';

-- Allow users to update certain columns on specific TABLES on API schema
REVOKE UPDATE (extra) ON api.logbook FROM user_role;
GRANT UPDATE (user_data) ON api.metadata TO user_role;
GRANT UPDATE (user_data) ON api.logbook TO user_role;
GRANT UPDATE (user_data) ON api.stays TO user_role;
GRANT UPDATE (user_data) ON api.moorages TO user_role;

-- Refresh permissions user_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
-- Refresh permissions grafana
GRANT SELECT ON ALL TABLES IN SCHEMA api TO grafana;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO grafana;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO grafana;
-- Refresh permissions api_anonymous
GRANT SELECT ON ALL TABLES IN SCHEMA api TO api_anonymous;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO api_anonymous;

-- Update version 0.9.7
UPDATE public.app_settings
	SET value='0.9.7'
	WHERE "name"='app.version';
