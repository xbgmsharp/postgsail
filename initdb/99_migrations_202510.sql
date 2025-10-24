---------------------------------------------------------------------------
-- Copyright 2021-2025 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration October 2025
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

ALTER TABLE api.logbook_ext ALTER COLUMN vessel_id SET NOT NULL;
ALTER TABLE api.moorages_ext ALTER COLUMN vessel_id SET NOT NULL;
ALTER TABLE api.moorages_ext ALTER COLUMN vessel_id SET NOT NULL;

--ALTER TABLE api.logbook RENAME COLUMN trip_twa TO trip_aws;

COMMENT ON COLUMN api.logbook.avg_speed IS 'avg speed in knots';
COMMENT ON COLUMN api.logbook.max_speed IS 'max speed in knots';
COMMENT ON COLUMN api.logbook.max_wind_speed IS 'true wind speed converted in knots, m/s from signalk plugin';
COMMENT ON COLUMN api.logbook.distance IS 'Distance in Nautical Miles converted mobilitydb meters to NM';
COMMENT ON COLUMN api.logbook.trip_sog IS 'SOG - Speed Over Ground in knots converted by signalk plugin';
COMMENT ON COLUMN api.logbook.trip_cog IS 'COG - Course Over Ground True in degrees converted from radians by signalk plugin';
COMMENT ON COLUMN api.logbook.trip_twa IS 'AWS (Apparent Wind Speed), windSpeedApparent in knots converted by signalk plugin';
COMMENT ON COLUMN api.logbook.trip_tws IS 'TWS - True Wind Speed in knots converted from m/s, raw from signalk plugin';
COMMENT ON COLUMN api.logbook.trip_twd IS 'TWD - True Wind Direction in degrees converted from radians, raw from signalk plugin';
COMMENT ON COLUMN api.logbook.trip_heading IS 'Heading True in degrees converted from radians, raw from signalk plugin';
COMMENT ON COLUMN api.logbook.trip_depth IS 'Depth in meters, raw from signalk plugin';
COMMENT ON COLUMN api.logbook.trip_temp_water IS 'Temperature water in Kelvin, raw from signalk plugin';
COMMENT ON COLUMN api.logbook.trip_temp_out IS 'Temperature outside in Kelvin, raw from signalk plugin';

-- DROP FUNCTION public.process_logbook_queue_fn(int4);
-- Update public.process_logbook_queue_fn, improve avg speed calculation, improve mobilitydb data handling force time-series
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
        _max_wind_speed NUMERIC;
        _avg_wind_speed NUMERIC;
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
        --extra_json := extra_json || jsonb_build_object('avg_wind_speed', twAvg(t_rec.truewindspeed));

        -- mobilitydb, add spaciotemporal sequence
        -- reduce the numbers of metrics by skipping row or aggregate time-series
        -- By default the signalk PostgSail plugin report one entry every minute.
        IF avg_rec.count_metric < 30 THEN -- if less ~20min trip we keep it all data
            t_rec := public.logbook_update_metrics_short_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        --ELSIF avg_rec.count_metric < 2000 THEN -- if less ~33h trip we skip data
        --    t_rec := public.logbook_update_metrics_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        ELSE -- As we have too many data, we time-series aggregate data
            t_rec := public.logbook_update_metrics_timebucket2_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        END IF;
        --RAISE NOTICE 'mobilitydb [%]', t_rec;
        IF t_rec.trajectory IS NULL THEN
            RAISE WARNING '-> process_logbook_queue_fn, vessel_id [%], invalid mobilitydb data [%] [%]', logbook_rec.vessel_id, _id, t_rec;
            RETURN;
        END IF;
        IF t_rec.truewindspeed IS NULL AND t_rec.windspeedapparent IS NOT NULL THEN
            _max_wind_speed := maxValue(t_rec.windspeedapparent)::NUMERIC(6,2); -- Fallback to apparent wind speed
            _avg_wind_speed := twAvg(t_rec.windspeedapparent)::NUMERIC(6,2); -- Fallback to apparent wind speed
        ELSE
            _max_wind_speed := maxValue(t_rec.truewindspeed)::NUMERIC(6,2);
            _avg_wind_speed := twAvg(t_rec.truewindspeed)::NUMERIC(6,2);
        END IF;
        -- Update the avg_wind_speed from mobilitydb data -- TWS in knots
        extra_json := extra_json || jsonb_build_object('avg_wind_speed', _avg_wind_speed);

        RAISE NOTICE 'Updating valid logbook, vessel_id [%], entry logbook id:[%] start:[%] end:[%]', logbook_rec.vessel_id, logbook_rec.id, logbook_rec._from_time, logbook_rec._to_time;
        UPDATE api.logbook
            SET
                duration = (logbook_rec._to_time::TIMESTAMPTZ - logbook_rec._from_time::TIMESTAMPTZ),
                --avg_speed = twAvg(t_rec.speedoverground), -- avg speed in knots
                --max_speed = maxValue(t_rec.speedoverground), -- max speed in knots
                avg_speed = (twavg(speed(t_rec.trajectory)) * 1.94384)::NUMERIC(6,2), -- avg speed in knots
                max_speed = (maxValue(speed(t_rec.trajectory)) * 1.94384)::NUMERIC(6,2), -- max speed in knots
                max_wind_speed = _max_wind_speed, -- TWS in knots
                _from = from_moorage.moorage_name,
                _from_moorage_id = from_moorage.moorage_id,
                _to_moorage_id = to_moorage.moorage_id,
                _to = to_moorage.moorage_name,
                name = log_name,
                --distance = geo_rec._track_distance, -- in Nautical Miles
                distance = (length(t_rec.trajectory)/1852)::NUMERIC(6,2), -- in Nautical Miles
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
                trip_hum_out = t_rec.outsidehumidity,
                trip_tank_level = t_rec.tankLevel,
                trip_solar_voltage = t_rec.solarVoltage,
                trip_solar_power = t_rec.solarPower,
                trip_heading = t_rec.heading
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
-- Description
COMMENT ON FUNCTION public.process_logbook_queue_fn(int4) IS 'Update logbook details when completed, logbook_update_avg_fn, logbook_update_geom_distance_fn, reverse_geocode_py_fn';

-- DROP FUNCTION public.process_post_logbook_fn(int4);
-- Update public.process_post_logbook_fn, add polar csv base on sailing vessel type
CREATE OR REPLACE FUNCTION public.process_post_logbook_fn(_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
    DECLARE
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
			-- Upsert into logbook_ext
			INSERT INTO api.logbook_ext (vessel_id, ref_id, polar)
				VALUES (logbook_rec.vessel_id, logbook_rec.id, api.export_logbook_polar_csv_fn(logbook_rec.id))
				ON CONFLICT (ref_id) DO UPDATE
				SET polar = EXCLUDED.polar;
		END IF;

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
-- Update api.merge_logbook_fn, improve avg speed calculation, improve mobilitydb data handling force time-series
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
            t_rec := public.logbook_update_metrics_timebucket2_fn(avg_rec.count_metric, logbook_rec_start._from_time, logbook_rec_end._to_time);
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
                --avg_speed = twAvg(t_rec.speedoverground), -- avg speed in knots
                --max_speed = maxValue(t_rec.speedoverground), -- max speed in knots
                avg_speed = (twavg(speed(t_rec.trajectory)) * 1.94384)::NUMERIC(6,2), -- avg speed in knots
                max_speed = (maxValue(speed(t_rec.trajectory)) * 1.94384)::NUMERIC(6,2), -- max speed in knots
                max_wind_speed = _max_wind_speed, -- TWS in knots
                -- Set _to metrics from end logbook
                _to = logbook_rec_end._to,
                _to_moorage_id = logbook_rec_end._to_moorage_id,
                _to_lat = logbook_rec_end._to_lat,
                _to_lng = logbook_rec_end._to_lng,
                _to_time = logbook_rec_end._to_time,
                name = log_name,
                --distance = geo_rec._track_distance, -- in Nautical Miles
                distance = (length(t_rec.trajectory)/1852)::NUMERIC(6,2), -- in Nautical Miles
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
        DELETE FROM api.logbook_ext WHERE ref_id = logbook_rec_end.id;
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

-- DROP FUNCTION public.cron_alerts_fn();
-- Update public.cron_alerts_fn, fix alert indoor message
CREATE OR REPLACE FUNCTION public.cron_alerts_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    alert_rec record;
    default_last_metric TIMESTAMPTZ := NOW() - interval '1 day';
    last_metric TIMESTAMPTZ;
    metric_rec record;
    app_settings JSONB;
    user_settings JSONB;
    alerting JSONB;
    _alarms JSONB;
    alarms TEXT;
    alert_default JSONB := '{
        "low_pressure_threshold": 990,
        "high_wind_speed_threshold": 30,
        "low_water_depth_threshold": 1,
        "min_notification_interval": 6,
        "high_pressure_drop_threshold": 12,
        "low_battery_charge_threshold": 90,
        "low_battery_voltage_threshold": 12.5,
        "low_water_temperature_threshold": 10,
        "low_indoor_temperature_threshold": 7,
        "low_outdoor_temperature_threshold": 3
    }';
BEGIN
    -- Check for new event notification pending update
    RAISE NOTICE 'cron_alerts_fn';
    FOR alert_rec in
        SELECT
            a.user_id,a.email,v.vessel_id,
            COALESCE((a.preferences->'alert_last_metric')::TEXT, default_last_metric::TEXT) as last_metric,
            (alert_default || ( -- Filters out empty strings (""), so they are not included in the result.
							    SELECT jsonb_object_agg(key, value)
							    FROM jsonb_each(a.preferences->'alerting') 
							    WHERE value <> '""'
							  )) as alerting,
            (a.preferences->'alarms')::JSONB as alarms,
            m.configuration as config
            FROM auth.accounts a
            LEFT JOIN auth.vessels AS v ON v.owner_email = a.email
            LEFT JOIN api.metadata AS m ON m.vessel_id = v.vessel_id
            WHERE (a.preferences->'alerting'->'enabled')::boolean = True
                AND m.active = True
        LOOP
        RAISE NOTICE '-> cron_alerts_fn for [%]', alert_rec;
        PERFORM set_config('vessel.id', alert_rec.vessel_id, false);
        PERFORM set_config('user.email', alert_rec.email, false);
        --RAISE WARNING 'public.cron_process_alert_rec_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(alert_rec.vessel_id::TEXT);
        RAISE NOTICE '-> cron_alerts_fn checking user_settings [%]', user_settings;
        -- Get all metrics from the last last_metric avg by 5 minutes
        FOR metric_rec in
            SELECT time_bucket('5 minutes', m.time) AS time_bucket,
                    avg(-- Inside Temperature
                        COALESCE(
                            m.metrics->'temperature'->>'inside',
                            m.metrics->>(md.configuration->>'insideTemperatureKey'),
                            m.metrics->>'environment.inside.temperature'
                        )::FLOAT) AS intemp,
                    avg(-- Wind Speed True (converted from m/s to knots)
                        COALESCE(
                            mt.metrics->'wind'->>'speed', mt.time,
                            mt.metrics->>(md.configuration->>'windSpeedKey'), mt.time,
                            mt.metrics->>'environment.wind.speedTrue', mt.time
                        )::FLOAT * 1.94384) AS wind,
                    avg(-- Water Depth
                        COALESCE(
                            m.metrics->'water'->>'depth',
                            m.metrics->>(md.configuration->>'depthKey'),
                            m.metrics->>'environment.depth.belowTransducer'
                        )::FLOAT) AS watdepth,
                    avg(-- Outside Temperature
                        COALESCE(
                            m.metrics->'temperature'->>'outside',
                            m.metrics->>(alert_rec.config->>'outsideTemperatureKey'),
                            m.metrics->>'environment.outside.temperature'
                        )::NUMERIC) AS outtemp,
                    avg(-- Water Temperature
                        COALESCE(
                            m.metrics->'water'->>'temperature',
                            m.metrics->>(alert_rec.config->>'waterTemperatureKey'),
                            m.metrics->>'environment.water.temperature'
                        )::NUMERIC) AS wattemp,
                    avg(-- Outside Pressure
                        COALESCE(
                            m.metrics->'pressure'->>'outside',
                            m.metrics->>(alert_rec.config->>'outsidePressureKey'),
                            m.metrics->>'environment.outside.pressure'
                        )::NUMERIC) AS pressure,
                    avg(-- Battery Voltage
                        COALESCE(
                            m.metrics->'battery'->>'voltage',
                            m.metrics->>(alert_rec.config->>'voltageKey'),
                            m.metrics->>'electrical.batteries.House.voltage'
                        )::NUMERIC) AS voltage,
                    avg(-- Battery Charge (State of Charge)
                        COALESCE(
                            m.metrics->'battery'->>'charge',
                            m.metrics->>(alert_rec.config->>'stateOfChargeKey'),
                            m.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
                        )::NUMERIC) AS charge
                FROM api.metrics m
                JOIN api.metadata md ON md.vessel_id = m.vessel_id
                WHERE md.vessel_id = alert_rec.vessel_id
                    AND m.time >= alert_rec.last_metric::TIMESTAMPTZ
                GROUP BY time_bucket
                ORDER BY time_bucket ASC LIMIT 100
        LOOP
            RAISE NOTICE '-> cron_alerts_fn checking metrics [%]', metric_rec;
            RAISE NOTICE '-> cron_alerts_fn checking alerting [%]', alert_rec.alerting;
            --RAISE NOTICE '-> cron_alerts_fn checking debug [%] [%]', kelvinToCel(metric_rec.intemp), (alert_rec.alerting->'low_indoor_temperature_threshold');
            IF metric_rec.intemp IS NOT NULL AND public.kelvintocel(metric_rec.intemp::NUMERIC) < (alert_rec.alerting->'low_indoor_temperature_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug indoor_temp [%]', (alert_rec.alarms->'low_indoor_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug indoor_temp [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_indoor_temperature_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_indoor_temperature_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_indoor_temperature_threshold": {"value": '|| kelvinToCel(metric_rec.intemp) ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_indoor_temperature_threshold value:'|| kelvinToCel(metric_rec.intemp) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_indoor_temperature_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_indoor_temperature_threshold';
            END IF;
            IF metric_rec.outtemp IS NOT NULL AND public.kelvintocel(metric_rec.outtemp::NUMERIC) < (alert_rec.alerting->>'low_outdoor_temperature_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug outdoor_temp [%]', (alert_rec.alarms->'low_outdoor_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug outdoor_temp [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_outdoor_temperature_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_outdoor_temperature_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_outdoor_temperature_threshold": {"value": '|| kelvinToCel(metric_rec.outtemp) ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_outdoor_temperature_threshold value:'|| kelvinToCel(metric_rec.outtemp) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_outdoor_temperature_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_outdoor_temperature_threshold';
            END IF;
            IF metric_rec.wattemp IS NOT NULL AND public.kelvintocel(metric_rec.wattemp::NUMERIC) < (alert_rec.alerting->>'low_water_temperature_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug water_temp [%]', (alert_rec.alarms->'low_water_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug water_temp [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_water_temperature_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_water_temperature_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_water_temperature_threshold": {"value": '|| kelvinToCel(metric_rec.wattemp) ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_water_temperature_threshold value:'|| kelvinToCel(metric_rec.wattemp) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_water_temperature_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_water_temperature_threshold';
            END IF;
            IF metric_rec.watdepth IS NOT NULL AND metric_rec.watdepth::NUMERIC < (alert_rec.alerting->'low_water_depth_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug water_depth [%]', (alert_rec.alarms->'low_water_depth_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug water_depth [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_water_depth_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_water_depth_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_water_depth_threshold": {"value": '|| metric_rec.watdepth ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_water_depth_threshold value:'|| ROUND(metric_rec.watdepth::NUMERIC,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_water_depth_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_water_depth_threshold';
            END IF;
            if metric_rec.pressure IS NOT NULL AND metric_rec.pressure::NUMERIC < (alert_rec.alerting->'high_pressure_drop_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug pressure [%]', (alert_rec.alarms->'high_pressure_drop_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug pressure [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'high_pressure_drop_threshold'->>'date') IS NULL) OR
                    (((_alarms->'high_pressure_drop_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"high_pressure_drop_threshold": {"value": '|| metric_rec.pressure ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "high_pressure_drop_threshold value:'|| ROUND(metric_rec.pressure,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug high_pressure_drop_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug high_pressure_drop_threshold';
            END IF;
            IF metric_rec.wind IS NOT NULL AND metric_rec.wind::NUMERIC > (alert_rec.alerting->'high_wind_speed_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug wind [%]', (alert_rec.alarms->'high_wind_speed_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug wind [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'high_wind_speed_threshold'->>'date') IS NULL) OR
                    (((_alarms->'high_wind_speed_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"high_wind_speed_threshold": {"value": '|| metric_rec.wind ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "high_wind_speed_threshold value:'|| ROUND(metric_rec.wind,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug high_wind_speed_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug high_wind_speed_threshold';
            END IF;
            IF metric_rec.voltage IS NOT NULL AND metric_rec.voltage::NUMERIC < (alert_rec.alerting->'low_battery_voltage_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug voltage [%]', (alert_rec.alarms->'low_battery_voltage_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug voltage [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_battery_voltage_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_battery_voltage_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_battery_voltage_threshold": {"value": '|| metric_rec.voltage ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_battery_voltage_threshold value:'|| ROUND(metric_rec.voltage,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_voltage_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_voltage_threshold';
            END IF;
            IF metric_rec.charge IS NOT NULL AND (metric_rec.charge::NUMERIC*100) < (alert_rec.alerting->'low_battery_charge_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_battery_charge_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_battery_charge_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_battery_charge_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_battery_charge_threshold": {"value": '|| (metric_rec.charge*100) ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_battery_charge_threshold value:'|| ROUND(metric_rec.charge::NUMERIC*100,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_charge_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_charge_threshold';
            END IF;
            -- Record last metrics time
            SELECT metric_rec.time_bucket INTO last_metric;
        END LOOP;
        PERFORM api.update_user_preferences_fn('{alert_last_metric}'::TEXT, last_metric::TEXT);
    END LOOP;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.cron_alerts_fn() IS 'init by pg_cron to check for alerts';

-- DROP FUNCTION public.check_jwt();
-- Update public.check_jwt, Add support for MCP server access
CREATE OR REPLACE FUNCTION public.check_jwt()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
-- Prevent unregister user or unregister vessel access
-- Allow anonymous access
DECLARE
  _role name := NULL;
  _email text := NULL;
  anonymous_rec record;
  _path name := NULL;
  _vid text := NULL;
  _vname text := NULL;
  boat TEXT := NULL;
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
  -- RESET settings to avoid sql shared session cache
  -- Valid for every new HTTP request
  PERFORM set_config('vessel.id', NULL, true);
  PERFORM set_config('vessel.name', NULL, true);
  PERFORM set_config('user.id', NULL, true);
  PERFORM set_config('user.email', NULL, true);
  -- Extract email and role from jwt token
  --RAISE WARNING 'check_jwt jwt %', current_setting('request.jwt.claims', true);
  SELECT current_setting('request.jwt.claims', true)::json->>'email' INTO _email;
  PERFORM set_config('user.email', _email, true);
  SELECT current_setting('request.jwt.claims', true)::json->>'role' INTO _role;
  --RAISE WARNING 'jwt email %', current_setting('request.jwt.claims', true)::json->>'email';
  --RAISE WARNING 'jwt role %', current_setting('request.jwt.claims', true)::json->>'role';
  --RAISE WARNING 'cur_user %', current_user;
  --RAISE WARNING 'user.id [%], user.email [%]', current_setting('user.id', true), current_setting('user.email', true);
  --RAISE WARNING 'vessel.id [%], vessel.name [%]', current_setting('vessel.id', true), current_setting('vessel.name', true);

  --TODO SELECT current_setting('request.jwt.uid', true)::json->>'uid' INTO _user_id;
  --TODO RAISE WARNING 'jwt user_id %', current_setting('request.jwt.uid', true)::json->>'uid';
  --TODO SELECT current_setting('request.jwt.vid', true)::json->>'vid' INTO _vessel_id;
  --TODO RAISE WARNING 'jwt vessel_id %', current_setting('request.jwt.vid', true)::json->>'vid';
  IF _role = 'user_role' OR _role = 'mcp_role' THEN
    -- Check the user exist in the accounts table
    SELECT * INTO account_rec
        FROM auth.accounts
        WHERE auth.accounts.email = _email;
    IF account_rec.email IS NULL THEN
        RAISE EXCEPTION 'Invalid user'
            USING HINT = 'Unknown user or password';
    END IF;
    -- Set session variables
    PERFORM set_config('user.id', account_rec.user_id, true);
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
    PERFORM set_config('vessel.id', vessel_rec.vessel_id, true);
    PERFORM set_config('vessel.name', vessel_rec.name, true);
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
    PERFORM set_config('vessel.id', vessel_rec.vessel_id, true);
    PERFORM set_config('vessel.name', vessel_rec.name, true);
    --RAISE WARNING 'public.check_jwt() user_role vessel.name %', current_setting('vessel.name', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.id %', current_setting('vessel.id', false);
  ELSIF _role = 'api_anonymous' THEN
    --RAISE WARNING 'public.check_jwt() api_anonymous path[%] vid:[%]', current_setting('request.path', true), current_setting('vessel.id', false); 
    -- Check if path is the a valid allow anonymous path
    SELECT current_setting('request.path', true) ~ '^/(logs_view|log_view|rpc/timelapse_fn|rpc/timelapse2_fn|monitoring_live|monitoring_view|stats_logs_view|stats_moorages_view|rpc/stats_logs_fn|rpc/export_logbooks_geojson_point_trips_fn|rpc/export_logbooks_geojson_linestring_trips_fn)$' INTO _ppath;
    if _ppath is True then
        -- Check is custom header is present and valid
        SELECT current_setting('request.headers', true)::json->>'x-is-public' into _pheader;
        --RAISE WARNING 'public.check_jwt() api_anonymous _pheader [%]', _pheader;
        if _pheader is null then
            return;
			--RAISE EXCEPTION 'Invalid public_header'
            --    USING HINT = 'Stop being so evil and maybe you can log in';
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
                SELECT v.vessel_id, v.name into anonymous_rec
                    FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs, log l
                    WHERE v.vessel_id = l.vessel_id
                        AND a.email = v.owner_email
                        AND a.preferences->>'public_vessel'::text ~* boat
                        AND prefs.key = _ptype::TEXT
                        AND prefs.value::BOOLEAN = true;
                RAISE WARNING '-> ispublic_fn public_logs output boat:[%], type:[%], result:[%]', _pvessel, _ptype, anonymous_rec;
                IF anonymous_rec.vessel_id IS NOT NULL THEN
                    PERFORM set_config('vessel.id', anonymous_rec.vessel_id, true);
                    PERFORM set_config('vessel.name', anonymous_rec.name, true);
                    RETURN;
                END IF;
            ELSE
                SELECT v.vessel_id, v.name into anonymous_rec
                        FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs
                        WHERE a.email = v.owner_email
                            AND a.preferences->>'public_vessel'::text ~* boat
                            AND prefs.key = _ptype::TEXT
                            AND prefs.value::BOOLEAN = true;
                RAISE WARNING '-> ispublic_fn output boat:[%], type:[%], result:[%]', _pvessel, _ptype, anonymous_rec;
                IF anonymous_rec.vessel_id IS NOT NULL THEN
                    PERFORM set_config('vessel.id', anonymous_rec.vessel_id, true);
                    PERFORM set_config('vessel.name', anonymous_rec.name, true);
                    RETURN;
                END IF;
            END IF;
            --RAISE sqlstate 'PT404' using message = 'unknown resource';
        END IF; -- end anonymous path
    END IF;
  ELSIF _role <> 'api_anonymous' THEN
    RAISE EXCEPTION 'Invalid role'
      USING HINT = 'Stop being so evil and maybe you can log in';
  END IF;
END
$function$
;
-- Description
COMMENT ON FUNCTION public.check_jwt() IS 'PostgREST API db-pre-request check, set_config according to role (api_anonymous,vessel_role,user_role)';

-- Update deprecated function comments
COMMENT ON FUNCTION public.logbook_update_metrics_fn(int4, timestamptz, timestamptz) IS 'DEPRECATED, Optimize logbook metrics base on the total metrics';
COMMENT ON FUNCTION public.logbook_update_metrics_timebucket_fn(int4, timestamptz, timestamptz) IS 'DEPRECATED, Optimize logbook metrics base on the aggregate time-series';
COMMENT ON FUNCTION api.export_logbook_geojson_fn(in int4, out jsonb) IS 'DEPRECATED, Export a log entry to geojson with features LineString and Point';

-- DROP FUNCTION public.logbook_update_metrics_short_fn(int4, timestamptz, timestamptz);
-- Update public.logbook_update_metrics_short_fn, Convert data wind speed from m/s to knots and wind direction from radians to degrees and heading from radians to degrees
CREATE OR REPLACE FUNCTION public.logbook_update_metrics_short_fn(total_entry integer, start_date timestamp with time zone, end_date timestamp with time zone)
 RETURNS TABLE(trajectory tgeogpoint, courseovergroundtrue tfloat, speedoverground tfloat, windspeedapparent tfloat, truewindspeed tfloat, truewinddirection tfloat, notes ttext, status ttext, watertemperature tfloat, depth tfloat, outsidehumidity tfloat, outsidepressure tfloat, outsidetemperature tfloat, stateofcharge tfloat, voltage tfloat, solarpower tfloat, solarvoltage tfloat, tanklevel tfloat, heading tfloat)
 LANGUAGE plpgsql
AS $function$
DECLARE
BEGIN
    -- Aggregate all metrics as trip is short.
    RETURN QUERY
    WITH metrics AS (
        -- Extract metrics
        SELECT date_trunc('minute', mt.time) AS time,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent, -- Wind Speed Apparent in knots from plugin
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True (converted from radians to degrees)
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT * (180.0 / PI()) AS heading,
            -- Wind Speed True (converted from m/s to knots)
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT * 1.94384 AS truewindspeed,
            -- Wind Direction True (converted from radians to degrees)
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT * (180.0 / PI()) AS truewinddirection,
            -- Water Temperature
            COALESCE(
                mt.metrics->'water'->>'temperature',
                mt.metrics->>(md.configuration->>'waterTemperatureKey'),
                mt.metrics->>'environment.water.temperature'
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                mt.metrics->'water'->>'depth',
                mt.metrics->>(md.configuration->>'depthKey'),
                mt.metrics->>'environment.depth.belowTransducer'
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                mt.metrics->'humidity'->>'outside',
                mt.metrics->>(md.configuration->>'outsideHumidityKey'),
                mt.metrics->>'environment.outside.relativeHumidity',
                mt.metrics->>'environment.outside.humidity'
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                mt.metrics->'pressure'->>'outside',
                mt.metrics->>(md.configuration->>'outsidePressureKey'),
                mt.metrics->>'environment.outside.pressure'
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                mt.metrics->'temperature'->>'outside',
                mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
                mt.metrics->>'environment.outside.temperature'
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                mt.metrics->'battery'->>'charge',
                mt.metrics->>(md.configuration->>'stateOfChargeKey'),
                mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                mt.metrics->'battery'->>'voltage',
                mt.metrics->>(md.configuration->>'voltageKey'),
                mt.metrics->>'electrical.batteries.House.voltage'
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                mt.metrics->'solar'->>'power',
                mt.metrics->>(md.configuration->>'solarPowerKey'),
                mt.metrics->>'electrical.solar.Main.panelPower'
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                mt.metrics->'solar'->>'voltage',
                mt.metrics->>(md.configuration->>'solarVoltageKey'),
                mt.metrics->>'electrical.solar.Main.panelVoltage'
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                mt.metrics->'tank'->>'level',
                mt.metrics->>(md.configuration->>'tankLevelKey'),
                mt.metrics->>'tanks.fuel.0.currentLevel'
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(mt.longitude, mt.latitude) AS geo_point
        FROM api.metrics mt
        JOIN api.metadata md ON md.vessel_id = mt.vessel_id
        WHERE mt.latitude IS NOT NULL
            AND mt.longitude IS NOT NULL
            AND mt.time >= start_date
            AND mt.time <= end_date
            AND mt.vessel_id = current_setting('vessel.id', false)
            ORDER BY mt.time ASC
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
        tfloatseq(array_agg(tfloat(o.voltage, o.time) ORDER BY o.time ASC) FILTER (WHERE o.voltage IS NOT NULL)) AS voltage,
        tfloatseq(array_agg(tfloat(o.solarPower, o.time) ORDER BY o.time ASC) FILTER (WHERE o.solarPower IS NOT NULL)) AS solarPower,
        tfloatseq(array_agg(tfloat(o.solarVoltage, o.time) ORDER BY o.time ASC) FILTER (WHERE o.solarVoltage IS NOT NULL)) AS solarVoltage,
        tfloatseq(array_agg(tfloat(o.tankLevel, o.time) ORDER BY o.time ASC) FILTER (WHERE o.tankLevel IS NOT NULL)) AS tankLevel,
        tfloatseq(array_agg(tfloat(o.heading, o.time) ORDER BY o.time ASC) FILTER (WHERE o.heading IS NOT NULL)) AS heading
    FROM metrics o;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.logbook_update_metrics_short_fn(int4, timestamptz, timestamptz) IS 'Optimize logbook metrics for short metrics';

-- DROP FUNCTION public.logbook_update_metrics_timebucket2_fn(int4, timestamptz, timestamptz);
-- Update public.logbook_update_metrics_timebucket2_fn, Choose bucket interval based on trip duration, Convert data wind speed from m/s to knots and wind direction from radians to degrees and heading from radians to degrees
CREATE OR REPLACE FUNCTION public.logbook_update_metrics_timebucket2_fn(total_entry integer, start_date timestamp with time zone, end_date timestamp with time zone)
 RETURNS TABLE(trajectory tgeogpoint, courseovergroundtrue tfloat, speedoverground tfloat, windspeedapparent tfloat, truewindspeed tfloat, truewinddirection tfloat, notes ttext, status ttext, watertemperature tfloat, depth tfloat, outsidehumidity tfloat, outsidepressure tfloat, outsidetemperature tfloat, stateofcharge tfloat, voltage tfloat, solarpower tfloat, solarvoltage tfloat, tanklevel tfloat, heading tfloat)
 LANGUAGE plpgsql
AS $function$
DECLARE
    bucket_interval INTERVAL;
    trip_duration INTERVAL;
BEGIN
    -- Compute voyage duration
    trip_duration := end_date - start_date;

    -- Choose bucket interval based on trip duration
    -- 1m (<= 6h), 2m (<= 12h), 3m (<= 18h), 5m (<= 24h), 10m (<= 48h), else 15m
    IF trip_duration <= INTERVAL '6 hours' THEN
        bucket_interval := '1 minute';
    ELSIF trip_duration <= INTERVAL '12 hours' THEN
        bucket_interval := '2 minutes';
    ELSIF trip_duration <= INTERVAL '18 hours' THEN
        bucket_interval := '3 minutes';
    ELSIF trip_duration <= INTERVAL '24 hours' THEN
        bucket_interval := '5 minutes';
    ELSIF trip_duration <= INTERVAL '48 hours' THEN
        bucket_interval := '10 minutes';
    ELSE
        bucket_interval := '15 minutes';
    END IF;

    RETURN QUERY
    WITH metrics AS (
        -- Extract metrics base the total of entry ignoring first and last 10 minutes metrics
        -- Normalize to minute boundary, this ensures time_bucket is always at :00 seconds
        SELECT date_trunc('minute', time_bucket(bucket_interval::INTERVAL, mt.time)) AS time_bucket,  -- Time-bucketed period
            avg(mt.courseovergroundtrue) as courseovergroundtrue,
            avg(mt.speedoverground) as speedoverground,
            avg(mt.windspeedapparent) as windspeedapparent, -- Wind Speed Apparent in knots from plugin
            last(mt.longitude, mt.time) as longitude, last(mt.latitude, mt.time) as latitude,
            '' AS notes,
            last(mt.status, mt.time) as status,
            -- Heading True (converted from radians to degrees)
            COALESCE(
                last(mt.metrics->>'heading', mt.time),
                last(mt.metrics->>'navigation.headingTrue', mt.time)
            )::FLOAT * (180.0 / PI()) AS heading,
            -- Wind Speed True (converted from m/s to knots)
            COALESCE(
                last(mt.metrics->'wind'->>'speed', mt.time),
                last(mt.metrics->>(md.configuration->>'windSpeedKey'), mt.time),
                last(mt.metrics->>'environment.wind.speedTrue', mt.time)
            )::FLOAT * 1.94384 AS truewindspeed,
            -- Wind Direction True (converted from radians to degrees)
            COALESCE(
                last(mt.metrics->'wind'->>'direction', mt.time),
                last(mt.metrics->>(md.configuration->>'windDirectionKey'), mt.time),
                last(mt.metrics->>'environment.wind.directionTrue', mt.time)
            )::FLOAT * (180.0 / PI()) AS truewinddirection,
            -- Water Temperature
            COALESCE(
                last(mt.metrics->'water'->>'temperature', mt.time),
                last(mt.metrics->>(md.configuration->>'waterTemperatureKey'), mt.time),
                last(mt.metrics->>'environment.water.temperature', mt.time)
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                last(mt.metrics->'water'->>'depth', mt.time),
                last(mt.metrics->>(md.configuration->>'depthKey'), mt.time),
                last(mt.metrics->>'environment.depth.belowTransducer', mt.time)
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                last(mt.metrics->'humidity'->>'outside', mt.time),
                last(mt.metrics->>(md.configuration->>'outsideHumidityKey'), mt.time),
                last(mt.metrics->>'environment.outside.relativeHumidity', mt.time),
                last(mt.metrics->>'environment.outside.humidity', mt.time)
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                last(mt.metrics->'pressure'->>'outside', mt.time),
                last(mt.metrics->>(md.configuration->>'outsidePressureKey'), mt.time),
                last(mt.metrics->>'environment.outside.pressure', mt.time)
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                last(mt.metrics->'temperature'->>'outside', mt.time),
                last(mt.metrics->>(md.configuration->>'outsideTemperatureKey'), mt.time),
                last(mt.metrics->>'environment.outside.temperature', mt.time)
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                last(mt.metrics->'battery'->>'charge', mt.time),
                last(mt.metrics->>(md.configuration->>'stateOfChargeKey'), mt.time),
                last(mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge', mt.time)
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                last(mt.metrics->'battery'->>'voltage', mt.time),
                last(mt.metrics->>(md.configuration->>'voltageKey'), mt.time),
                last(mt.metrics->>'electrical.batteries.House.voltage', mt.time)
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                last(mt.metrics->'solar'->>'power', mt.time),
                last(mt.metrics->>(md.configuration->>'solarPowerKey'), mt.time),
                last(mt.metrics->>'electrical.solar.Main.panelPower', mt.time)
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                last(mt.metrics->'solar'->>'voltage', mt.time),
                last(mt.metrics->>(md.configuration->>'solarVoltageKey'), mt.time),
                last(mt.metrics->>'electrical.solar.Main.panelVoltage', mt.time)
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                last(mt.metrics->'tank'->>'level', mt.time),
                last(mt.metrics->>(md.configuration->>'tankLevelKey'), mt.time),
                last(mt.metrics->>'tanks.fuel.0.currentLevel', mt.time)
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(last(mt.longitude, mt.time),last(mt.latitude, mt.time)) AS geo_point
        FROM api.metrics mt
        JOIN api.metadata md ON md.vessel_id = mt.vessel_id
        WHERE mt.latitude IS NOT NULL
            AND mt.longitude IS NOT NULL
            AND mt.time > (start_date + interval '10 minutes')
            AND mt.time < (end_date - interval '10 minutes')
            AND mt.vessel_id = current_setting('vessel.id', false)
        GROUP BY time_bucket
        ORDER BY time_bucket ASC
    ),
    first_metric AS (
        -- Extract first 10 minutes metrics, Normalize to minute boundary
        SELECT 
            date_trunc('minute', mt.time) AS time_bucket,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True (converted from radians to degrees)
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT * (180.0 / PI()) AS heading,
            -- Wind Speed True (converted from m/s to knots)
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT * 1.94384 AS truewindspeed,
            -- Wind Direction True (converted from radians to degrees)
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT * (180.0 / PI()) AS truewinddirection,
            -- Water Temperature
            COALESCE(
                mt.metrics->'water'->>'temperature',
                mt.metrics->>(md.configuration->>'waterTemperatureKey'),
                mt.metrics->>'environment.water.temperature'
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                mt.metrics->'water'->>'depth',
                mt.metrics->>(md.configuration->>'depthKey'),
                mt.metrics->>'environment.depth.belowTransducer'
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                mt.metrics->'humidity'->>'outside',
                mt.metrics->>(md.configuration->>'outsideHumidityKey'),
                mt.metrics->>'environment.outside.relativeHumidity',
                mt.metrics->>'environment.outside.humidity'
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                mt.metrics->'pressure'->>'outside',
                mt.metrics->>(md.configuration->>'outsidePressureKey'),
                mt.metrics->>'environment.outside.pressure'
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                mt.metrics->'temperature'->>'outside',
                mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
                mt.metrics->>'environment.outside.temperature'
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                mt.metrics->'battery'->>'charge',
                mt.metrics->>(md.configuration->>'stateOfChargeKey'),
                mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                mt.metrics->'battery'->>'voltage',
                mt.metrics->>(md.configuration->>'voltageKey'),
                mt.metrics->>'electrical.batteries.House.voltage'
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                mt.metrics->'solar'->>'power',
                mt.metrics->>(md.configuration->>'solarPowerKey'),
                mt.metrics->>'electrical.solar.Main.panelPower'
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                mt.metrics->'solar'->>'voltage',
                mt.metrics->>(md.configuration->>'solarVoltageKey'),
                mt.metrics->>'electrical.solar.Main.panelVoltage'
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                mt.metrics->'tank'->>'level',
                mt.metrics->>(md.configuration->>'tankLevelKey'),
                mt.metrics->>'tanks.fuel.0.currentLevel'
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(mt.longitude, mt.latitude) AS geo_point
        FROM api.metrics mt
        JOIN api.metadata md ON md.vessel_id = mt.vessel_id
        WHERE mt.latitude IS NOT NULL
            AND mt.longitude IS NOT NULL
            AND mt.time >= start_date
            AND mt.time < (start_date + interval '10 minutes')
            AND mt.vessel_id = current_setting('vessel.id', false)
        ORDER BY time_bucket ASC
    ),
    last_metric AS (
        -- Extract last 10 minutes metrics, Normalize to minute boundary
        SELECT 
            date_trunc('minute', mt.time) AS time_bucket,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True (converted from radians to degrees)
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT * (180.0 / PI()) AS heading,
            -- Wind Speed True (converted from m/s to knots)
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT * 1.94384 AS truewindspeed,
            -- Wind Direction True (converted from radians to degrees)
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT * (180.0 / PI()) AS truewinddirection,
            -- Water Temperature
            COALESCE(
                mt.metrics->'water'->>'temperature',
                mt.metrics->>(md.configuration->>'waterTemperatureKey'),
                mt.metrics->>'environment.water.temperature'
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                mt.metrics->'water'->>'depth',
                mt.metrics->>(md.configuration->>'depthKey'),
                mt.metrics->>'environment.depth.belowTransducer'
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                mt.metrics->'humidity'->>'outside',
                mt.metrics->>(md.configuration->>'outsideHumidityKey'),
                mt.metrics->>'environment.outside.relativeHumidity',
                mt.metrics->>'environment.outside.humidity'
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                mt.metrics->'pressure'->>'outside',
                mt.metrics->>(md.configuration->>'outsidePressureKey'),
                mt.metrics->>'environment.outside.pressure'
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                mt.metrics->'temperature'->>'outside',
                mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
                mt.metrics->>'environment.outside.temperature'
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                mt.metrics->'battery'->>'charge',
                mt.metrics->>(md.configuration->>'stateOfChargeKey'),
                mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                mt.metrics->'battery'->>'voltage',
                mt.metrics->>(md.configuration->>'voltageKey'),
                mt.metrics->>'electrical.batteries.House.voltage'
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                mt.metrics->'solar'->>'power',
                mt.metrics->>(md.configuration->>'solarPowerKey'),
                mt.metrics->>'electrical.solar.Main.panelPower'
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                mt.metrics->'solar'->>'voltage',
                mt.metrics->>(md.configuration->>'solarVoltageKey'),
                mt.metrics->>'electrical.solar.Main.panelVoltage'
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                mt.metrics->'tank'->>'level',
                mt.metrics->>(md.configuration->>'tankLevelKey'),
                mt.metrics->>'tanks.fuel.0.currentLevel'
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(mt.longitude, mt.latitude) AS geo_point
        FROM api.metrics mt
        JOIN api.metadata md ON md.vessel_id = mt.vessel_id
        WHERE mt.latitude IS NOT NULL
            AND mt.longitude IS NOT NULL
            AND mt.time <= end_date
            AND mt.time > (end_date - interval '10 minutes')
            AND mt.vessel_id = current_setting('vessel.id', false)
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
        tfloatseq(array_agg(tfloat(o.voltage, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.voltage IS NOT NULL)) AS voltage,
        tfloatseq(array_agg(tfloat(o.solarPower, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.solarPower IS NOT NULL)) AS solarPower,
        tfloatseq(array_agg(tfloat(o.solarVoltage, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.solarVoltage IS NOT NULL)) AS solarVoltage,
        tfloatseq(array_agg(tfloat(o.tankLevel, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.tankLevel IS NOT NULL)) AS tankLevel,
        tfloatseq(array_agg(tfloat(o.heading, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.heading IS NOT NULL)) AS heading
    FROM optimize_metrics o;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.logbook_update_metrics_timebucket2_fn(int4, timestamptz, timestamptz) IS 'Optimize logbook metrics base on the aggregate time-series';

-- Update api.export_logbook_geojson_point_trip_fn, add more metrics properties
CREATE OR REPLACE FUNCTION api.export_logbook_geojson_point_trip_fn(_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
                valueAtTimestamp(points.trip_hum_out, getTimestamp(points.point)) AS outsidehumidity,
                valueAtTimestamp(points.trip_solar_voltage, getTimestamp(points.point)) AS solarvoltage,
                valueAtTimestamp(points.trip_solar_power, getTimestamp(points.point)) AS solarpower,
                valueAtTimestamp(points.trip_tank_level, getTimestamp(points.point)) AS tanklevel,
                valueAtTimestamp(points.trip_heading, getTimestamp(points.point)) AS heading
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
                    trip_hum_out,
                    trip_solar_voltage,
                    trip_solar_power,
                    trip_tank_level,
                    trip_heading
                FROM api.logbook
                WHERE id = _id
            ) AS points
        ) AS t;
END;
$function$
;
-- Description
COMMENT ON FUNCTION api.export_logbook_geojson_point_trip_fn(int4) IS 'Generate geojson geometry Point from trip with the corresponding properties';

-- Update api.export_logbook_geojson_linestring_trip_fn, ensure the metrics properties are dynamic
CREATE OR REPLACE FUNCTION api.export_logbook_geojson_linestring_trip_fn(_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
BEGIN
    -- Return a geojson with a geometry linestring and the corresponding properties
    RETURN
            json_build_object(
            'type', 'FeatureCollection',
            'features', json_agg(ST_AsGeoJSON(log.*)::json))
    FROM -- Extract max/avg values from trip and return as geojson
        ( SELECT id, name,
            starttimestamp(trip),
            endtimestamp(trip),
            (twavg(speed(trip)) * 1.94384)::NUMERIC(6,2) as avg_speed, -- avg speed in knots
            (maxValue(speed(trip)) * 1.94384)::NUMERIC(6,2) as max_speed, -- max speed in knots
            duration(trip),
            --length(trip) as length, -- Meters
            (length(trip)/1852)::NUMERIC(6,2) as distance, -- in Nautical Miles
            maxValue(trip_sog) as max_sog, -- SOG
            maxValue(trip_tws) as max_tws, -- Wind Speed
            maxValue(trip_twd) as max_twd, -- Wind Direction
            maxValue(trip_depth) as max_depth, -- Depth
            maxValue(trip_temp_water) as max_temp_water, -- Temperature water
            maxValue(trip_temp_out) as max_temp_out, -- Temperature outside
            maxValue(trip_pres_out) as max_pres_out, -- Pressure outside
            maxValue(trip_hum_out) as max_hum_out, -- Humidity outside
            maxValue(trip_batt_charge) as max_stateofcharge, -- stateofcharge
            maxValue(trip_batt_voltage) as max_voltage, -- voltage
            maxValue(trip_solar_voltage) as max_solar_voltage, -- solar voltage
            maxValue(trip_solar_power) as max_solar_power, -- solar power
            maxValue(trip_tank_level) as max_tank_level, -- tank level
            twavg(trip_sog) as avg_sog, -- SOG
            twavg(trip_twa) as avg_twa, -- Wind Speed Apparent
            twavg(trip_tws) as avg_tws, -- Wind Speed
            twavg(trip_twd) as avg_twd, -- Wind Direction
            twavg(trip_depth) as avg_depth, -- Depth
            twavg(trip_temp_water) as avg_temp_water, -- Temperature water
            twavg(trip_temp_out) as avg_temp_out, -- Temperature outside
            twavg(trip_pres_out) as avg_pres_out, -- Pressure outside
            twavg(trip_hum_out) as avg_hum_out, -- Humidity outside
            twavg(trip_batt_charge) as avg_stateofcharge, -- stateofcharge
            twavg(trip_batt_voltage) as avg_voltage, -- voltage
            twavg(trip_solar_voltage) as avg_solar_voltage, -- solar voltage
            twavg(trip_solar_power) as avg_solar_power, -- solar power
            twavg(trip_tank_level) as avg_tank_level, -- tank level
            trajectory(trip)::geometry as track_geog, -- extract trip to geography
            extra,
            _to_moorage_id,
            _from_moorage_id,
            timestamps(trip) as times -- extract timestamps to array
            FROM api.logbook l
            WHERE id = _id
           ) AS log;
END;
$function$
;
-- Description
COMMENT ON FUNCTION api.export_logbook_geojson_linestring_trip_fn(int4) IS 'Generate geojson geometry LineString from trip with the corresponding properties';

-- DROP FUNCTION api.export_logbook_metrics_trip_fn(int4);
-- Update api.export_logbook_metrics_trip_fn, add more metrics properties
CREATE OR REPLACE FUNCTION api.export_logbook_metrics_trip_fn(_id integer)
 RETURNS jsonb
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
            valueAtTimestamp(points.trip_hum_out, getTimestamp(points.point)) AS outsidehumidity,
            valueAtTimestamp(points.trip_solar_voltage, getTimestamp(points.point)) AS solarvoltage,
            valueAtTimestamp(points.trip_solar_power, getTimestamp(points.point)) AS solarpower,
            valueAtTimestamp(points.trip_tank_level, getTimestamp(points.point)) AS tanklevel,
            valueAtTimestamp(points.trip_heading, getTimestamp(points.point)) AS heading
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
                    trip_hum_out,
                    trip_solar_voltage,
                    trip_solar_power,
                    trip_tank_level,
                    trip_heading
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
            WHEN (metrics_geojson->1->'properties'->>'notes') = '' THEN -- it is not null but empty??
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
            WHEN (metrics_geojson->-1->'properties'->>'notes') = '' THEN -- it is not null but empty??
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
-- Description
COMMENT ON FUNCTION api.export_logbook_metrics_trip_fn(int4) IS 'Export a log entry to an array of GeoJSON feature format of geometry point';

-- DROP FUNCTION api.export_logbooks_geojson_linestring_trips_fn(in int4, in int4, in text, in text, out jsonb);
-- Update api.export_logbooks_geojson_linestring_trips_fn, ensure the metrics properties are dynamic
CREATE OR REPLACE FUNCTION api.export_logbooks_geojson_linestring_trips_fn(start_log integer DEFAULT NULL::integer, end_log integer DEFAULT NULL::integer, start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT geojson jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    logs_geojson jsonb;
BEGIN
    -- Normalize start and end values
    IF start_log IS NOT NULL AND end_log IS NULL THEN end_log := start_log; END IF;
    IF start_date IS NOT NULL AND end_date IS NULL THEN end_date := start_date; END IF;

    WITH logbook_data AS (
        -- get the logbook geometry and metadata, an array for each log
        SELECT id, name,
            starttimestamp(trip),
            endtimestamp(trip),
            (twavg(speed(trip)) * 1.94384)::NUMERIC(6,2) as avg_speed, -- avg speed in knots
            (maxValue(speed(trip)) * 1.94384)::NUMERIC(6,2) as max_speed, -- max speed in knots
            duration(trip),
            --length(trip) as length, -- Meters
            (length(trip)/1852)::NUMERIC(6,2) as distance, -- in Nautical Miles
            maxValue(trip_sog) as max_sog, -- SOG
            maxValue(trip_twa) as max_twa, -- Wind Speed Apparent
            maxValue(trip_tws) as max_tws, -- Wind Speed
            maxValue(trip_twd) as max_twd, -- Wind Direction
            maxValue(trip_depth) as max_depth, -- Depth
            maxValue(trip_temp_water) as max_temp_water, -- Temperature water
            maxValue(trip_temp_out) as max_temp_out, -- Temperature outside
            maxValue(trip_pres_out) as max_pres_out, -- Pressure outside
            maxValue(trip_hum_out) as max_hum_out, -- Humidity outside
            maxValue(trip_batt_charge) as max_stateofcharge, -- stateofcharge
            maxValue(trip_batt_voltage) as max_voltage, -- voltage
            maxValue(trip_solar_voltage) as max_solar_voltage, -- Solar voltage
            maxValue(trip_solar_power) as max_solar_power, -- Solar power
            maxValue(trip_tank_level) as max_tank_level, -- tank level
            twavg(trip_sog) as avg_sog, -- SOG
            twavg(trip_twa) as avg_twa, -- Wind Speed Apparent
            twavg(trip_tws) as avg_tws, -- Wind Speed
            twavg(trip_twd) as avg_twd, -- Wind Direction
            twavg(trip_depth) as avg_depth, -- Depth
            twavg(trip_temp_water) as avg_temp_water, -- Temperature water
            twavg(trip_temp_out) as avg_temp_out, -- Temperature outside
            twavg(trip_pres_out) as avg_pres_out, -- Pressure outside
            twavg(trip_hum_out) as avg_hum_out, -- Humidity outside
            twavg(trip_batt_charge) as avg_stateofcharge, -- stateofcharge
            twavg(trip_batt_voltage) as avg_voltage, -- voltage
            twavg(trip_solar_voltage) as avg_solar_voltage, -- Solar voltage
            twavg(trip_solar_power) as avg_solar_power, -- Solar power
            twavg(trip_tank_level) as avg_tank_level, -- tank level
            trajectory(l.trip)::geometry as track_geog, -- extract trip to geography
            extra,
            _to_moorage_id,
            _from_moorage_id
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
$function$
;
-- Description
COMMENT ON FUNCTION api.export_logbooks_geojson_linestring_trips_fn(in int4, in int4, in text, in text, out jsonb) IS 'Generate geojson geometry LineString from trip with the corresponding properties';

-- DROP FUNCTION api.logbook_update_geojson_trip_fn(int4);
-- Update api.logbook_update_geojson_trip_fn, Add more metrics properties
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
            valueAtTimestamp(points.trip_status, getTimestamp(points.point)) AS status,
            valueAtTimestamp(points.trip_batt_charge, getTimestamp(points.point)) AS stateofcharge,
            valueAtTimestamp(points.trip_batt_voltage, getTimestamp(points.point)) AS voltage,
            valueAtTimestamp(points.trip_temp_water, getTimestamp(points.point)) AS watertemperature,
            valueAtTimestamp(points.trip_temp_out, getTimestamp(points.point)) AS outsidetemperature,
            valueAtTimestamp(points.trip_pres_out, getTimestamp(points.point)) AS outsidepressure,
            valueAtTimestamp(points.trip_hum_out, getTimestamp(points.point)) AS outsidehumidity,
            valueAtTimestamp(points.trip_solar_voltage, getTimestamp(points.point)) AS solarvoltage,
            valueAtTimestamp(points.trip_solar_power, getTimestamp(points.point)) AS solarpower,
            valueAtTimestamp(points.trip_tank_level, getTimestamp(points.point)) AS tanklevel,
            valueAtTimestamp(points.trip_heading, getTimestamp(points.point)) AS heading
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
                    trip_hum_out,
                    trip_solar_voltage,
                    trip_solar_power,
                    trip_tank_level,
                    trip_heading
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
COMMENT ON FUNCTION api.logbook_update_geojson_trip_fn(int4) IS 'Export a log trip entry to GEOJSON format with custom properties for timelapse replay';

-- Update Row Level Security policies for api.metadata table
CREATE POLICY api_anonymous_role ON api.metadata TO api_anonymous
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (false);

-- Refresh permissions user_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;

GRANT SELECT ON TABLE api.monitoring_live TO api_anonymous;

-- Update version
UPDATE public.app_settings
	SET value='0.9.6'
	WHERE "name"='app.version';

\c postgres
-- Set cron job username to current user
UPDATE cron.job
    SET username = current_user
    WHERE username = 'username';
