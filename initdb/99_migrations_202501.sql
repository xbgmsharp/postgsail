---------------------------------------------------------------------------
-- Copyright 2021-2025 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration January-March 2025
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Mark client_id as deprecated
COMMENT ON COLUMN api.metadata.client_id IS 'Deprecated client_id to be removed';
COMMENT ON COLUMN api.metrics.client_id IS 'Deprecated client_id to be removed';

-- Update metadata table COLUMN type to jsonb
ALTER TABLE api.metadata ALTER COLUMN "configuration" TYPE jsonb USING "configuration"::jsonb;
COMMENT ON COLUMN api.metadata.configuration IS 'Signalk path mapping for metrics';

-- Add new column available_keys
ALTER TABLE api.metadata ADD available_keys jsonb NULL;
COMMENT ON COLUMN api.metadata.available_keys IS 'Signalk paths with unit for custom mapping';

--DROP FUNCTION public.metadata_upsert_trigger_fn();
CREATE OR REPLACE FUNCTION public.metadata_upsert_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
    DECLARE
        metadata_id integer;
        metadata_active boolean;
    BEGIN
        -- Require Signalk plugin version 0.4.0
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
                    --client_id = NEW.client_id,
                    length = NEW.length,
                    beam = NEW.beam,
                    height = NEW.height,
                    ship_type = NEW.ship_type,
                    plugin_version = NEW.plugin_version,
                    signalk_version = NEW.signalk_version,
                    platform = REGEXP_REPLACE(NEW.platform, '[^a-zA-Z0-9\(\) ]', '', 'g'),
                    -- configuration = NEW.configuration, -- ignore configuration from vessel, it is manage by user
                    -- time = NEW.time, ignore the time sent by the vessel as it is out of sync sometimes.
                    time = NOW(), -- overwrite the time sent by the vessel
                    available_keys = NEW.available_keys,
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
$function$
;
COMMENT ON FUNCTION public.metadata_upsert_trigger_fn() IS 'process metadata from vessel, upsert';

-- Create or replace the function that will be executed by the trigger
CREATE OR REPLACE FUNCTION api.update_metadata_configuration()
RETURNS TRIGGER AS $$
BEGIN
    -- Require Signalk plugin version 0.4.0
    -- Update the configuration field with current date in ISO format
    -- Using jsonb_set if configuration is already a JSONB field
    IF NEW.configuration IS NOT NULL AND
        jsonb_typeof(NEW.configuration) = 'object' THEN
        NEW.configuration = jsonb_set(
            NEW.configuration, 
            '{update_at}', 
            to_jsonb(to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION api.update_metadata_configuration() IS 'Update the configuration field with current date in ISO format';

-- Create the trigger
CREATE TRIGGER metadata_update_configuration_trigger
BEFORE UPDATE ON api.metadata
FOR EACH ROW
EXECUTE FUNCTION api.update_metadata_configuration();

-- Update api.export_logbook_geojson_linestring_trip_fn, add metadata
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
        -- get the logbook geometry and metadata, an array for each log
        SELECT id, name,
            starttimestamp(trip),
            endtimestamp(trip),
            --speed(trip_sog),
            duration(trip),
            --length(trip) as length, -- Meters
            (length(trip) * 0.0005399568)::numeric as distance, -- NM
            twavg(trip_sog) as avg_sog,
            maxValue(trip_sog) as max_sog,
            maxValue(trip_depth) as max_depth, -- Depth
            maxValue(trip_batt_charge) as max_batt_charge, -- Battery Charge
            maxValue(trip_batt_voltage) as max_batt_voltage, -- Battery Voltage
            maxValue(trip_temp_water) as max_temp_water, -- Temperature water
            maxValue(trip_temp_out) as max_temp_out, -- Temperature outside
            maxValue(trip_pres_out) as max_pres_out, -- Pressure outside
            maxValue(trip_hum_out) as max_hum_out, -- Humidity outside
            twavg(trip_depth) as avg_depth, -- Depth
            twavg(trip_batt_charge) as avg_batt_charge, -- Battery Charge
            twavg(trip_batt_voltage) as avg_batt_voltage, -- Battery Voltage
            twavg(trip_temp_water) as avg_temp_water, -- Temperature water
            twavg(trip_temp_out) as avg_temp_out, -- Temperature outside
            twavg(trip_pres_out) as avg_pres_out, -- Pressure outside
            twavg(trip_hum_out) as avg_hum_out, -- Humidity outside
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
-- Description
COMMENT ON FUNCTION api.export_logbooks_geojson_linestring_trips_fn IS 'Generate geojson geometry LineString from trip with the corresponding properties';

-- Add public.get_season, return the season based on the input date for logbook tag
CREATE OR REPLACE FUNCTION public.get_season(input_date TIMESTAMPTZ)
RETURNS TEXT AS $$
BEGIN
    CASE
        WHEN (EXTRACT(MONTH FROM input_date) = 3 AND EXTRACT(DAY FROM input_date) >= 1) OR
             (EXTRACT(MONTH FROM input_date) BETWEEN 4 AND 5) THEN
            RETURN 'Spring';
        WHEN (EXTRACT(MONTH FROM input_date) = 6 AND EXTRACT(DAY FROM input_date) >= 1) OR
             (EXTRACT(MONTH FROM input_date) BETWEEN 7 AND 8) THEN
            RETURN 'Summer';
        WHEN (EXTRACT(MONTH FROM input_date) = 9 AND EXTRACT(DAY FROM input_date) >= 1) OR
             (EXTRACT(MONTH FROM input_date) BETWEEN 10 AND 11) THEN
            RETURN 'Fall';
        ELSE
            RETURN 'Winter';
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Refresh permissions
GRANT SELECT ON TABLE api.metrics,api.metadata TO scheduler;
GRANT INSERT, UPDATE, SELECT ON TABLE api.logbook,api.moorages,api.stays TO scheduler;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO scheduler;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO scheduler;
GRANT SELECT, UPDATE ON TABLE public.process_queue TO scheduler;

-- Update version
UPDATE public.app_settings
	SET value='0.9.0'
	WHERE "name"='app.version';
