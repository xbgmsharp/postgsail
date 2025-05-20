---------------------------------------------------------------------------
-- Copyright 2021-2025 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration May 2025
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Update metadata table, add IP address column, remove id column, update vessel_id default
ALTER TABLE api.metadata DROP COLUMN IF EXISTS id;
ALTER TABLE api.metadata ALTER COLUMN vessel_id SET DEFAULT current_setting('vessel.id'::text, false);
ALTER TABLE api.metadata ADD COLUMN IF NOT EXISTS ip TEXT NULL;
ALTER TABLE api.metadata ALTER COLUMN mmsi TYPE text USING mmsi::text;
COMMENT ON COLUMN api.metadata.ip IS 'Store vessel ip address';

-- Add metadata_ext, new table to store vessel extended metadata from user
CREATE TABLE api.metadata_ext (
  vessel_id text PRIMARY KEY 
             DEFAULT current_setting('vessel.id'::text, false) 
             REFERENCES api.metadata(vessel_id) ON DELETE RESTRICT,
  make_model text NULL,
  polar text NULL, -- Store polar data in CSV notation as used on ORC sailboat data
  polar_updated_at timestamptz NULL,
  image_b64 text NULL, -- Store user boat image in b64 format
  image bytea NULL, -- Store user boat image in bytea format
  image_type text NULL, -- Store user boat image type in text format
  image_updated_at timestamptz NULL,
  created_at timestamptz DEFAULT now() NOT NULL
);
-- Description
COMMENT ON TABLE
    api.metadata_ext
    IS 'Stores metadata extended information for the vessel from user';

-- Comments
COMMENT ON COLUMN api.metadata_ext.polar IS 'Store polar data in CSV notation as used on ORC sailboat data';
COMMENT ON COLUMN api.metadata_ext.image IS 'Store user boat image in bytea format';
COMMENT ON COLUMN api.metadata_ext.image_type IS 'Store user boat image type in text format';
COMMENT ON COLUMN api.metadata_ext.make_model IS 'Store user make & model in text format';

-- Cleanup trigger on api schema
DROP FUNCTION IF EXISTS api.update_metadata_ext_added_at_fn();
DROP TRIGGER IF EXISTS metadata_update_configuration_trigger ON api.metadata;
DROP FUNCTION IF EXISTS api.update_metadata_configuration();

-- Move trigger on public schema
CREATE OR REPLACE FUNCTION public.update_metadata_configuration_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Only update configuration if it's a JSONB object and has changed
    IF NEW.configuration IS NOT NULL 
       AND NEW.configuration IS DISTINCT FROM OLD.configuration
       AND jsonb_typeof(NEW.configuration) = 'object' THEN

        NEW.configuration := jsonb_set(
            NEW.configuration,
            '{update_at}',
            to_jsonb(to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
        );
    END IF;

    RETURN NEW;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.update_metadata_configuration_trigger_fn() IS 'Update the configuration field with current date in ISO format';

-- Update trigger to use public schema
create trigger metadata_update_configuration_trigger before
update
    on
    api.metadata for each row execute function public.update_metadata_configuration_trigger_fn();
-- Description
COMMENT ON TRIGGER metadata_update_configuration_trigger ON api.metadata IS 'BEFORE UPDATE ON api.metadata run function api.update_metadata_configuration tp update the configuration field with current date in ISO format';

-- Create trigger to update polar_updated_at and image_updated_at accordingly.
CREATE OR REPLACE FUNCTION public.update_metadata_ext_added_at_trigger_fn()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.polar IS DISTINCT FROM OLD.polar THEN
    NEW.polar_updated_at := NOW();
  END IF;

  IF NEW.image IS DISTINCT FROM OLD.image THEN
    NEW.image_updated_at := NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION public.update_metadata_ext_added_at_trigger_fn() IS 'Update polar_updated_at and/or image_updated_at when polar and/or image is update';

CREATE TRIGGER metadata_ext_update_added_at_trigger
BEFORE INSERT OR UPDATE ON api.metadata_ext
FOR EACH ROW
EXECUTE FUNCTION public.update_metadata_ext_added_at_trigger_fn();
-- Description
COMMENT ON TRIGGER metadata_ext_update_added_at_trigger ON api.metadata_ext IS 'BEFORE INSERT OR UPDATE ON api.metadata_ext run function update_metadata_ext_added_at_trigger_fn';

-- Create update_metadata_ext_decode_base64_image_trigger_fn to decode base64 image
CREATE OR REPLACE FUNCTION public.update_metadata_ext_decode_base64_image_trigger_fn()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if image_b64 contains a base64 string to decode
    IF NEW.image_b64 IS NOT NULL AND NEW.image_b64 IS DISTINCT FROM OLD.image_b64 THEN
        BEGIN
            -- Decode base64 string and assign to image column (BYTEA type)
            NEW.image := decode(NEW.image_b64, 'base64');

            -- Clear the base64 text column - Not working
            --NEW.image_b64 := NULL;
        EXCEPTION
            WHEN others THEN
                RAISE EXCEPTION 'Failed to decode base64 image string: %', SQLERRM;
        END;
    END IF;

    -- Return the modified row with the decoded image
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION public.update_metadata_ext_decode_base64_image_trigger_fn() IS 'Decode base64 image string to bytea format';

CREATE TRIGGER metadata_ext_decode_image_trigger
  BEFORE INSERT OR UPDATE ON api.metadata_ext
  FOR EACH ROW
  EXECUTE FUNCTION public.update_metadata_ext_decode_base64_image_trigger_fn();
-- Description
COMMENT ON TRIGGER metadata_ext_decode_image_trigger ON api.metadata_ext IS 'BEFORE INSERT OR UPDATE ON api.metadata_ext run function update_metadata_ext_decode_base64_image_trigger_fn';

-- refactor metadata_upsert_trigger_fn with the new metadata schema, remove id.
CREATE OR REPLACE FUNCTION public.metadata_upsert_trigger_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_vessel_id TEXT := current_setting('vessel.id', true);
    headers   JSON := current_setting('request.headers', true)::json;
    client_ip TEXT := coalesce(headers->>'x-client-ip', NULL);
    metadata_record RECORD;
BEGIN
    -- Ensure vessel_id is set in NEW
    IF NEW.vessel_id IS NULL THEN
      NEW.vessel_id := v_vessel_id;
    END IF;

    -- Look for existing metadata
    SELECT active INTO metadata_record
      FROM api.metadata
      WHERE vessel_id = v_vessel_id;

    IF FOUND AND NOT metadata_record.active THEN
      -- Send notification as the vessel was inactive
      INSERT INTO process_queue (channel, payload, stored, ref_id)
        VALUES ('monitoring_online', v_vessel_id, NOW(), v_vessel_id);
    ELSIF NOT FOUND THEN
      -- First insert, Send notification as the vessel is active
      INSERT INTO process_queue (channel, payload, stored, ref_id)
        VALUES ('monitoring_online', v_vessel_id, NOW(), v_vessel_id);
    END IF;

    -- Check if mmsi is a valid 9-digit number
    IF NEW.mmsi::TEXT !~ '^\d{9}$' THEN
      NEW.mmsi := NULL;
    END IF;

    -- Normalize and overwrite vessel metadata
    NEW.platform := REGEXP_REPLACE(NEW.platform, '[^a-zA-Z0-9\(\) ]', '', 'g');
    NEW.time := NOW();
    NEW.active := TRUE;
    NEW.ip := client_ip;
    RETURN NEW; -- Insert new vessel metadata
END;
$function$;
-- Description
COMMENT ON FUNCTION public.metadata_upsert_trigger_fn() IS 'process metadata from vessel, upsert';

DROP TRIGGER metadata_notification_trigger ON api.metadata;
DROP FUNCTION public.metadata_notification_trigger_fn;
DROP TRIGGER metadata_upsert_trigger ON api.metadata;
CREATE TRIGGER metadata_upsert_trigger
  BEFORE INSERT OR UPDATE ON api.metadata
  FOR EACH ROW
  EXECUTE FUNCTION metadata_upsert_trigger_fn();
-- Description
COMMENT ON TRIGGER metadata_upsert_trigger ON api.metadata IS 'BEFORE INSERT OR UPDATE ON api.metadata run function metadata_upsert_trigger_fn';

--DROP FUNCTION public.metadata_grafana_trigger_fn();
-- Update metadata_grafana_trigger_fn with the new metadata schema, remove id.
CREATE OR REPLACE FUNCTION public.metadata_grafana_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
    DECLARE
    BEGIN
        RAISE NOTICE 'metadata_grafana_trigger_fn [%]', NEW;
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('grafana', NEW.vessel_id, now(), NEW.vessel_id);
        RETURN NULL;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION public.metadata_grafana_trigger_fn() IS 'process metadata grafana provisioning from vessel';

-- Create api.vessel_image to fetch boat image
create domain "*/*" as bytea;
create or replace function api.vessel_image(v_id TEXT default NULL) returns "*/*" 
LANGUAGE plpgsql
AS $function$
  declare headers text;
  declare blob bytea;
  begin
    select format(
      '[{"Content-Type": "%s"},'
       '{"Content-Disposition": "inline; filename=\"%s\""},'
       '{"Cache-Control": "max-age=900"}]'
      , image_type, v_id)
      into headers
      from api.metadata_ext where vessel_id = v_id;
    perform set_config('response.headers', headers, true);
    select image into blob from api.metadata_ext where vessel_id = v_id;
    if FOUND -- special var, see https://www.postgresql.org/docs/current/plpgsql-statements.html#PLPGSQL-STATEMENTS-DIAGNOSTICS
    then return(blob);
    else raise sqlstate 'PT404' using
      message = 'NOT FOUND',
      detail = 'File not found',
      hint = format('%s seems to be an invalid file', v_id);
    end if;
  end
$function$ ;
-- Description
COMMENT ON FUNCTION api.vessel_image IS 'Return vessel image from metadata_ext (image url)';

-- Create api.vessel_extended_fn() to expose extended vessel details
CREATE OR REPLACE FUNCTION api.vessel_extended_fn()
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id text := current_setting('vessel.id', false);
    result jsonb;
BEGIN
    SELECT jsonb_build_object(
          'make_model', make_model,
          'has_polar', polar IS NOT NULL,
          'has_image', image IS NOT NULL,
          'image_url', 
              CASE WHEN image IS NOT NULL 
                  THEN 'https://api.openplotter.cloud/rpc/vessel_image?v_id=' || v_id
                  ELSE NULL 
              END,
          'image_updated_at', image_updated_at
      )
      INTO result
      FROM api.metadata_ext
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
$function$;
-- Description
COMMENT ON FUNCTION api.vessel_extended_fn() IS 'Return vessel details from metadata_ext (polar csv,image url, make model)';

-- Update api.vessel_details_fn to use configuration
DROP FUNCTION api.vessel_details_fn(out json);
CREATE OR REPLACE FUNCTION api.vessel_details_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
BEGIN
     RETURN ( WITH tbl AS (
                SELECT mmsi,ship_type,length,beam,height,plugin_version,platform,configuration IS NOT NULL AS has_config FROM api.metadata WHERE vessel_id = current_setting('vessel.id', false)
                )
                SELECT jsonb_build_object(
                        'ship_type', (SELECT ais.description FROM aistypes ais, tbl t WHERE t.ship_type = ais.id),
                        'country', (SELECT mid.country FROM mid, tbl t WHERE LEFT(cast(t.mmsi as text), 3)::NUMERIC = mid.id),
                        'alpha_2', (SELECT o.alpha_2 FROM mid m, iso3166 o, tbl t WHERE LEFT(cast(t.mmsi as text), 3)::NUMERIC = m.id AND m.country_id = o.id),
                        'length', t.length,
                        'beam', t.beam,
                        'height', t.height,
                        'plugin_version', t.plugin_version,
                        'platform', t.platform,
                        'configuration', t.has_config)
                        FROM tbl t
            );
END;
$function$
;
-- Description
COMMENT ON FUNCTION api.vessel_details_fn() IS 'Return vessel details such as metadata (length,beam,height), ais type and country name and country iso3166-alpha-2';

DROP FUNCTION api.vessel_fn(out json);
-- Update api.vessel_fn to use metadata_ext
CREATE OR REPLACE FUNCTION api.vessel_fn(OUT vessel jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
    DECLARE
    BEGIN
        SELECT
            jsonb_build_object(
                'name', m.name,
                'mmsi', m.mmsi,
                'vessel_id', m.vessel_id,
                'created_at', v.created_at,
                'first_contact', m.created_at,
                'last_contact', m.time,
                'offline', (NOW() AT TIME ZONE 'UTC' - m.time) > INTERVAL '70 MINUTES',
                'geojson', ST_AsGeoJSON(geojson_t.*)::json
            )::jsonb
            || api.vessel_details_fn()::jsonb
            || api.vessel_extended_fn()::jsonb
            INTO vessel
            FROM auth.vessels v, api.metadata m, 
                (	select
                        current_setting('vessel.name') as name,
                        time,
                        courseovergroundtrue,
                        speedoverground,
                        anglespeedapparent,
                        longitude,latitude,
                        st_makepoint(longitude,latitude) AS geo_point
                        FROM api.metrics
                        WHERE
                            latitude IS NOT NULL
                            AND longitude IS NOT NULL
                            AND vessel_id = current_setting('vessel.id', false)
                        ORDER BY time DESC LIMIT 1
                ) AS geojson_t
            WHERE
                m.vessel_id = current_setting('vessel.id')
                AND m.vessel_id = v.vessel_id;
        --RAISE notice 'api.vessel_fn %', obj;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION api.vessel_fn(out jsonb) IS 'Expose vessel details to API';

DROP VIEW IF EXISTS api.monitoring_view;
DROP VIEW IF EXISTS api.monitoring_live;
DROP FUNCTION IF EXISTS public.stay_active_geojson_fn();
-- Update public.stay_active_geojson_fn function to produce a GeoJSON with the last position and stay details
CREATE or replace FUNCTION public.stay_active_geojson_fn(
    IN _time TIMESTAMPTZ DEFAULT NOW(),
    OUT _track_geojson jsonb
 ) AS $stay_active_geojson_fn$
BEGIN
    WITH stay_active AS (
        SELECT * FROM api.stays WHERE active IS true
    ),
    stay_gis_point AS (
        SELECT
            ST_AsGeoJSON(t.*)::jsonb AS GeoJSONPoint
        FROM (
            SELECT
                m.name,
                _time as time,
                s.stay_code,
                ST_MakePoint(s.longitude, s.latitude) AS geo_point,
                s.arrived,
                s.latitude,
                s.longitude
            FROM stay_active s
            LEFT JOIN api.moorages m ON m.id = s.moorage_id
        ) as t
    )
    SELECT stay_gis_point.GeoJSONPoint::jsonb INTO _track_geojson FROM stay_gis_point;
END;
$stay_active_geojson_fn$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.stay_active_geojson_fn
    IS 'Create a GeoJSON with a feature Point with the last position and stay details';

-- Update monitoring view to support live moorage in GeoJSON
CREATE VIEW api.monitoring_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT
        time AS "time",
        (NOW() AT TIME ZONE 'UTC' - time) > INTERVAL '70 MINUTES' as offline,
        metrics-> 'environment.water.temperature' AS waterTemperature,
        metrics-> 'environment.inside.temperature' AS insideTemperature,
        metrics-> 'environment.outside.temperature' AS outsideTemperature,
        metrics-> 'environment.wind.speedOverGround' AS windSpeedOverGround,
        metrics-> 'environment.wind.directionTrue' AS windDirectionTrue,
        metrics-> 'environment.inside.relativeHumidity' AS insideHumidity,
        metrics-> 'environment.outside.relativeHumidity' AS outsideHumidity,
        metrics-> 'environment.outside.pressure' AS outsidePressure,
        metrics-> 'environment.inside.pressure' AS insidePressure,
        metrics-> 'electrical.batteries.House.capacity.stateOfCharge' AS batteryCharge,
        metrics-> 'electrical.batteries.House.voltage' AS batteryVoltage,
        metrics-> 'environment.depth.belowTransducer' AS depth,
        jsonb_build_object(
            'type', 'Feature',
            'geometry', ST_AsGeoJSON(st_makepoint(longitude,latitude))::jsonb,
            'properties', jsonb_build_object(
                'name', current_setting('vessel.name', false),
                'latitude', m.latitude,
                'longitude', m.longitude,
                'time', m.time,
                'speedoverground', m.speedoverground,
                'windspeedapparent', m.windspeedapparent,
                'truewindspeed', COALESCE(metrics->'environment.wind.speedTrue', null),
                'truewinddirection', COALESCE(metrics->'environment.wind.directionTrue', null),
                'status', coalesce(m.status, null)
                )::jsonb ) AS geojson,
        current_setting('vessel.name', false) AS name,
        m.status,
        CASE
            WHEN m.status <> 'moored' THEN (
                SELECT public.logbook_active_geojson_fn() )
            WHEN m.status = 'moored' THEN (
                SELECT public.stay_active_geojson_fn(time) )
        END AS live
    FROM api.metrics m
    ORDER BY time DESC LIMIT 1;
-- Description
COMMENT ON VIEW
    api.monitoring_view
    IS 'Monitoring static web view';

-- DROP FUNCTION public.overpass_py_fn(in numeric, in numeric, out jsonb);
-- Update public.overpass_py_fn to check for seamark with name
CREATE OR REPLACE FUNCTION public.overpass_py_fn(lon numeric, lat numeric, OUT geo jsonb)
 RETURNS jsonb
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
 IMMUTABLE STRICT
AS $function$
    """
    Return https://overpass-turbo.eu seamark details within 400m
    https://overpass-turbo.eu/s/1EaG
    https://wiki.openstreetmap.org/wiki/Key:seamark:type
    """
    import requests
    import json
    import urllib.parse

    headers = {'User-Agent': 'PostgSail', 'From': 'xbgmsharp@gmail.com'}
    payload = """
[out:json][timeout:20];
is_in({0},{1})->.result_areas;
(
  area.result_areas["seamark:type"~"(mooring|harbour)"][~"^seamark:.*:category$"~"."][~"name"~"."];
  area.result_areas["seamark:type"~"(anchorage|anchor_berth|berth)"][~"name"~"."];
  area.result_areas["leisure"="marina"][~"name"~"."];
);
out tags;
nwr(around:400.0,{0},{1})->.all;
(
  nwr.all["seamark:type"~"(mooring|harbour)"][~"^seamark:.*:category$"~"."][~"name"~"."];
  nwr.all["seamark:type"~"(anchorage|anchor_berth|berth)"][~"name"~"."];
  nwr.all["leisure"="marina"][~"name"~"."];
  nwr.all["natural"~"(bay|beach)"][~"name"~"."];
  //nwr.all["waterway"="fuel"];
);
out tags;
    """.format(lat, lon)
    data = urllib.parse.quote(payload, safe="");
    url = f'https://overpass-api.de/api/interpreter?data={data}'.format(data)
    r = requests.get(url, headers)
    #print(r.text)
    #plpy.notice(url)
    plpy.notice('overpass-api coord lon[{}] lat[{}] [{}]'.format(lon, lat, r.status_code))
    if r.status_code == 200 and "elements" in r.json():
        r_dict = r.json()
        plpy.notice('overpass-api Got [{}]'.format(r_dict["elements"]))
        if r_dict["elements"]:
            if "tags" in r_dict["elements"][0] and r_dict["elements"][0]["tags"]:
                return r_dict["elements"][0]["tags"]; # return the first element
        return {}
    else:
        plpy.notice('overpass-api Failed to get overpass-api details')
    return {}
$function$
;
-- Description
COMMENT ON FUNCTION public.overpass_py_fn(in numeric, in numeric, out jsonb) IS 'Return https://overpass-turbo.eu seamark details within 400m using plpython3u';

-- DROP FUNCTION api.export_logbooks_geojson_linestring_trips_fn(in int4, in int4, in text, in text, out jsonb);
-- Update api.export_logbooks_geojson_linestring_trips_fn, add extra, _to_moorage_id, _from_moorage_id metadata
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
            --speed(trip_sog),
            duration(trip),
            --length(trip) as length, -- Meters
            (length(trip) * 0.0005399568)::numeric as distance, -- NM
            maxValue(trip_sog) as max_sog, -- SOG
            maxValue(trip_tws) as max_tws, -- Wind
            maxValue(trip_twd) as max_twd, -- Wind
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
            twavg(trip_tws) as avg_tws, -- Wind
            twavg(trip_twd) as avg_twd, -- Wind
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

-- Update api.monitoring_live, add live tracking view, Add support 6h outside barometer
DROP VIEW IF EXISTS api.monitoring_live;
CREATE or replace VIEW api.monitoring_live WITH (security_invoker=true,security_barrier=true) AS
  -- Gather the last 6h average outside pressure by 10 min range
  WITH pressure AS (
    SELECT 
      json_agg(json_build_object(
        'time', time_bucket,
        'outsidePressure', outsidePressure
      ) ORDER BY time_bucket) AS outsidePressureHistory
    FROM (
      SELECT
        time_bucket('10 minutes', mt.time) AS time_bucket,
        avg(COALESCE(
            mt.metrics->'pressure'->>'outside',
            mt.metrics->>(md.configuration->>'outsidePressureKey'),
            mt.metrics->>'environment.outside.pressure'
        )::FLOAT) AS outsidePressure
      FROM api.metrics mt
      JOIN api.metadata md ON md.vessel_id = mt.vessel_id
      WHERE mt.vessel_id = current_setting('vessel.id', false)
        AND mt.time > (NOW() AT TIME ZONE 'UTC' - INTERVAL '6 hour')
      GROUP BY time_bucket
    ) sub
  )
  SELECT
      mt.time AS "time",
      (NOW() AT TIME ZONE 'UTC' - mt.time) > INTERVAL '70 MINUTES' as offline,
      mt.metrics AS data,
      jsonb_build_object(
          'type', 'Feature',
          'geometry', ST_AsGeoJSON(st_makepoint(mt.longitude,mt.latitude))::jsonb,
          'properties', jsonb_build_object(
              'name', current_setting('vessel.name', false),
              'latitude', mt.latitude,
              'longitude', mt.longitude,
              'time', mt.time,
              'speedoverground', mt.speedoverground,
              'windspeedapparent',mt.windspeedapparent,
              'truewindspeed', -- Wind Speed True
                              COALESCE(
                                  mt.metrics->'wind'->>'speed',
                                  mt.metrics->>(md.configuration->>'windSpeedKey'),
                                  mt.metrics->>'environment.wind.speedTrue'
                              )::FLOAT,
              'truewinddirection', -- Wind Direction True
                                COALESCE(
                                    mt.metrics->'wind'->>'direction',
                                    mt.metrics->>(md.configuration->>'windDirectionKey'),
                                    mt.metrics->>'environment.wind.directionTrue'
                                )::FLOAT,
              'status', coalesce(mt.status, null)
              )::jsonb ) AS geojson,
      current_setting('vessel.name', false) AS name,
      mt.status,
      -- Water Temperature
      COALESCE(
          mt.metrics->'water'->>'temperature',
          mt.metrics->>(md.configuration->>'waterTemperatureKey'),
          mt.metrics->>'environment.water.temperature'
      )::FLOAT AS waterTemperature,

      -- Inside Temperature
      COALESCE(
          mt.metrics->'temperature'->>'inside',
          mt.metrics->>(md.configuration->>'insideTemperatureKey'),
          mt.metrics->>'environment.inside.temperature'
      )::FLOAT AS insideTemperature,

      -- Outside Temperature
      COALESCE(
          mt.metrics->'temperature'->>'outside',
          mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
          mt.metrics->>'environment.outside.temperature'
      )::FLOAT AS outsideTemperature,

      -- Wind Speed True
      COALESCE(
          mt.metrics->'wind'->>'speed',
          mt.metrics->>(md.configuration->>'windSpeedKey'),
          mt.metrics->>'environment.wind.speedTrue'
      )::FLOAT AS windSpeedOverGround,

      -- Wind Direction True
      COALESCE(
          mt.metrics->'wind'->>'direction',
          mt.metrics->>(md.configuration->>'windDirectionKey'),
          mt.metrics->>'environment.wind.directionTrue'
      )::FLOAT AS windDirectionTrue,

      -- Inside Humidity
      COALESCE(
          mt.metrics->'humidity'->>'inside',
          mt.metrics->>(md.configuration->>'insideHumidityKey'),
          mt.metrics->>'environment.inside.relativeHumidity',
          mt.metrics->>'environment.inside.humidity'
      )::FLOAT AS insideHumidity,

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

      -- Inside Pressure
      COALESCE(
          mt.metrics->'pressure'->>'inside',
          mt.metrics->>(md.configuration->>'insidePressureKey'),
          mt.metrics->>'environment.inside.pressure'
      )::FLOAT AS insidePressure,

      -- Battery Charge (State of Charge)
      COALESCE(
          mt.metrics->'battery'->>'charge',
          mt.metrics->>(md.configuration->>'stateOfChargeKey'),
          mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
      )::FLOAT AS batteryCharge,

      -- Battery Voltage
      COALESCE(
          mt.metrics->'battery'->>'voltage',
          mt.metrics->>(md.configuration->>'voltageKey'),
          mt.metrics->>'electrical.batteries.House.voltage'
      )::FLOAT AS batteryVoltage,

      -- Water Depth
      COALESCE(
          mt.metrics->'water'->>'depth',
          mt.metrics->>(md.configuration->>'depthKey'),
          mt.metrics->>'environment.depth.belowTransducer'
      )::FLOAT AS depth,

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

      CASE
          WHEN mt.status <> 'moored' THEN (
              SELECT public.logbook_active_geojson_fn() )
          WHEN mt.status = 'moored' THEN (
              SELECT public.stay_active_geojson_fn() )
      END AS live,
      -- Add the pressure history as a time series array
      pressure.outsidePressureHistory
  FROM api.metrics mt
  JOIN api.metadata md ON md.vessel_id = mt.vessel_id
  CROSS JOIN pressure
  ORDER BY time DESC LIMIT 1;
-- Description
COMMENT ON VIEW
    api.monitoring_live
    IS 'Dynamic Monitoring web view';

-- Update public.logbook_update_metrics_short_fn, aggregate more metrics and use user configuration
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
    voltage tfloat,
    solarPower tfloat,
    solarVoltage tfloat,
    tankLevel tfloat,
    heading tfloat
) AS $$
DECLARE
BEGIN
    -- Aggregate all metrics as trip is short.
    RETURN QUERY
    WITH metrics AS (
        -- Extract metrics
        SELECT mt.time,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT AS truewinddirection,
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
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_metrics_short_fn
    IS 'Optimize logbook metrics for short metrics';

-- Update public.logbook_update_metrics_fn, aggregate more metrics and use user configuration
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
    voltage tfloat,
    solarPower tfloat,
    solarVoltage tfloat,
    tankLevel tfloat,
    heading tfloat
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
            -- Heading True
            COALESCE(
                t.metrics->>'heading',
                t.metrics->>'navigation.headingTrue'
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                t.metrics->'wind'->>'speed',
                t.metrics->>(t.configuration->>'windSpeedKey'),
                t.metrics->>'environment.wind.speedTrue'
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                t.metrics->'wind'->>'direction',
                t.metrics->>(t.configuration->>'windDirectionKey'),
                t.metrics->>'environment.wind.directionTrue'
            )::FLOAT AS truewinddirection,
            -- Water Temperature
            COALESCE(
                t.metrics->'water'->>'temperature',
                t.metrics->>(t.configuration->>'waterTemperatureKey'),
                t.metrics->>'environment.water.temperature'
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                t.metrics->'water'->>'depth',
                t.metrics->>(t.configuration->>'depthKey'),
                t.metrics->>'environment.depth.belowTransducer'
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                t.metrics->'humidity'->>'outside',
                t.metrics->>(t.configuration->>'outsideHumidityKey'),
                t.metrics->>'environment.outside.relativeHumidity',
                t.metrics->>'environment.outside.humidity'
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                t.metrics->'pressure'->>'outside',
                t.metrics->>(t.configuration->>'outsidePressureKey'),
                t.metrics->>'environment.outside.pressure'
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                t.metrics->'temperature'->>'outside',
                t.metrics->>(t.configuration->>'outsideTemperatureKey'),
                t.metrics->>'environment.outside.temperature'
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                t.metrics->'battery'->>'charge',
                t.metrics->>(t.configuration->>'stateOfChargeKey'),
                t.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                t.metrics->'battery'->>'voltage',
                t.metrics->>(t.configuration->>'voltageKey'),
                t.metrics->>'electrical.batteries.House.voltage'
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                t.metrics->'solar'->>'power',
                t.metrics->>(t.configuration->>'solarPowerKey'),
                t.metrics->>'electrical.solar.Main.panelPower'
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                t.metrics->'solar'->>'voltage',
                t.metrics->>(t.configuration->>'solarVoltageKey'),
                t.metrics->>'electrical.solar.Main.panelVoltage'
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                t.metrics->'tank'->>'level',
                t.metrics->>(t.configuration->>'tankLevelKey'),
                t.metrics->>'tanks.fuel.0.currentLevel'
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(t.longitude, t.latitude) AS geo_point
        FROM (
            SELECT mt.*, md.configuration, row_number() OVER() AS row
            FROM api.metrics mt
            JOIN api.metadata md ON md.vessel_id = mt.vessel_id
            WHERE mt.latitude IS NOT NULL
                AND mt.longitude IS NOT NULL
                AND mt.time > (start_date + interval '10 minutes')
                AND mt.time < (end_date - interval '10 minutes')
                AND mt.vessel_id = current_setting('vessel.id', false)
				ORDER BY mt.time ASC
        ) t
        WHERE t.row % modulo_divisor = 0
    ),
    first_metric AS (
        -- Extract first 10 minutes metrics
        SELECT 
            mt.time,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT AS truewinddirection,
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
        ORDER BY mt.time ASC
    ),
    last_metric AS (
        -- Extract last 10 minutes metrics
        SELECT 
            mt.time,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT AS truewinddirection,
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
        ORDER BY mt.time ASC
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
        tfloatseq(array_agg(tfloat(o.voltage, o.time) ORDER BY o.time ASC) FILTER (WHERE o.voltage IS NOT NULL)) AS voltage,
        tfloatseq(array_agg(tfloat(o.solarPower, o.time) ORDER BY o.time ASC) FILTER (WHERE o.solarPower IS NOT NULL)) AS solarPower,
        tfloatseq(array_agg(tfloat(o.solarVoltage, o.time) ORDER BY o.time ASC) FILTER (WHERE o.solarVoltage IS NOT NULL)) AS solarVoltage,
        tfloatseq(array_agg(tfloat(o.tankLevel, o.time) ORDER BY o.time ASC) FILTER (WHERE o.tankLevel IS NOT NULL)) AS tankLevel,
        tfloatseq(array_agg(tfloat(o.heading, o.time) ORDER BY o.time ASC) FILTER (WHERE o.heading IS NOT NULL)) AS heading
    FROM optimize_metrics o;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_metrics_fn
    IS 'Optimize logbook metrics base on the total metrics';

-- Update public.logbook_update_metrics_timebucket_fn, aggregate more metrics and use user configuration
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
    voltage tfloat,
    solarPower tfloat,
    solarVoltage tfloat,
    tankLevel tfloat,
    heading tfloat
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
        SELECT time_bucket(bucket_interval::INTERVAL, mt.time) AS time_bucket,  -- Time-bucketed period
            avg(mt.courseovergroundtrue) as courseovergroundtrue,
            avg(mt.speedoverground) as speedoverground,
            avg(mt.windspeedapparent) as windspeedapparent,
            last(mt.longitude, mt.time) as longitude, last(mt.latitude, mt.time) as latitude,
            '' AS notes,
            last(mt.status, mt.time) as status,
            -- Heading True
            COALESCE(
                last(mt.metrics->>'heading', mt.time),
                last(mt.metrics->>'navigation.headingTrue', mt.time)
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                last(mt.metrics->'wind'->>'speed', mt.time),
                last(mt.metrics->>(md.configuration->>'windSpeedKey'), mt.time),
                last(mt.metrics->>'environment.wind.speedTrue', mt.time)
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                last(mt.metrics->'wind'->>'direction', mt.time),
                last(mt.metrics->>(md.configuration->>'windDirectionKey'), mt.time),
                last(mt.metrics->>'environment.wind.directionTrue', mt.time)
            )::FLOAT AS truewinddirection,
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
        -- Extract first 10 minutes metrics
        SELECT 
            mt.time AS time_bucket,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT AS truewinddirection,
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
        -- Extract last 10 minutes metrics
        SELECT 
            mt.time AS time_bucket,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT AS truewinddirection,
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
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_metrics_timebucket_fn
    IS 'Optimize logbook metrics base on the aggregate time-series';

-- DROP FUNCTION public.process_logbook_queue_fn(int4);
-- Update public.process_logbook_queue_fn to use new mobilitydb metrics
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

-- Remove unnecessary functions
DROP FUNCTION IF EXISTS api.monitoring_upsert_fn;
-- Add missing comments on function
COMMENT ON FUNCTION public.new_account_entry_fn() IS 'trigger process_queue on INSERT ofr new account';

-- Update public.cron_process_monitor_online_fn, refactor of metadata
CREATE OR REPLACE FUNCTION public.cron_process_monitor_online_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
    process_rec record;
    metadata_rec record;
    user_settings jsonb;
    app_settings jsonb;
begin
    -- Check for monitor online pending notification
    RAISE NOTICE 'cron_process_monitor_online_fn';
    FOR process_rec in 
        SELECT * from process_queue 
            where channel = 'monitoring_online' and processed is null
            order by stored asc
    LOOP
        RAISE NOTICE '-> cron_process_monitor_online_fn metadata_vessel_id [%]', process_rec.payload;
        SELECT * INTO metadata_rec 
            FROM api.metadata
            WHERE vessel_id = process_rec.payload::TEXT;

        IF metadata_rec.vessel_id IS NULL OR metadata_rec.vessel_id = '' THEN
            RAISE WARNING '-> cron_process_monitor_online_fn invalid metadata record vessel_id [%]', metadata_rec;
            RAISE EXCEPTION 'Invalid metadata'
                USING HINT = 'Unknown vessel_id';
            RETURN;
        END IF;
        PERFORM set_config('vessel.id', metadata_rec.vessel_id, false);
        RAISE DEBUG '-> DEBUG cron_process_monitor_online_fn vessel_id %', current_setting('vessel.id', false);

        -- Gather email and pushover app settings
        --app_settings = get_app_settings_fn();
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(metadata_rec.vessel_id::TEXT);
        RAISE DEBUG '-> DEBUG cron_process_monitor_online_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('monitor_online'::TEXT, user_settings::JSONB);
        --PERFORM send_email_py_fn('monitor_online'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('monitor_online'::TEXT, user_settings::JSONB, app_settings::JSONB);
        -- update process_queue entry as processed
        UPDATE process_queue 
            SET 
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_monitor_online_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$function$
;

-- DROP FUNCTION public.cron_process_monitor_offline_fn();
-- Update public.cron_process_monitor_offline_fn, Refactor metadata
CREATE OR REPLACE FUNCTION public.cron_process_monitor_offline_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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
        RAISE NOTICE '-> cron_process_monitor_offline_fn metadata_vessel_id [%]', metadata_rec.vessel_id;

        IF metadata_rec.vessel_id IS NULL OR metadata_rec.vessel_id = '' THEN
            RAISE WARNING '-> cron_process_monitor_offline_fn invalid metadata record vessel_id [%]', metadata_rec;
            RAISE EXCEPTION 'Invalid metadata'
                USING HINT = 'Unknown vessel_id';
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', metadata_rec.vessel_id, false);
        RAISE NOTICE 'cron_process_monitor_offline_fn, vessel.id [%], updated api.metadata table to inactive for [%]', current_setting('vessel.id', false), metadata_rec.vessel_id;

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
            WHERE vessel_id = current_setting('vessel.id', false);
        
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
                ('monitoring_offline', metadata_rec.vessel_id::TEXT, metadata_rec.interval, now(), metadata_rec.vessel_id)
            RETURNING id INTO process_id;
        RAISE NOTICE '-> cron_process_monitor_offline_fn updated process_queue table [%]', process_id;
    END LOOP;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.cron_process_monitor_offline_fn() IS 'init by pg_cron to monitor offline pending notification, if so perform send_email o send_pushover base on user preferences';

-- DROP FUNCTION public.cron_process_grafana_fn();
-- Update public.cron_process_grafana_fn, Refactor metadata
CREATE OR REPLACE FUNCTION public.cron_process_grafana_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    process_rec record;
    data_rec record;
    app_settings jsonb;
    user_settings jsonb;
BEGIN
    -- We run grafana provisioning only after the first received vessel metadata
    -- Check for new vessel metadata pending grafana provisioning
    RAISE NOTICE 'cron_process_grafana_fn';
    FOR process_rec in
        SELECT * from process_queue
            where channel = 'grafana' and processed is null
            order by stored asc
    LOOP
        RAISE NOTICE '-> cron_process_grafana_fn [%]', process_rec.payload;
        -- Gather url from app settings
        app_settings := get_app_settings_fn();
        -- Get vessel details base on metadata id
        SELECT
            v.owner_email,coalesce(m.name,v.name) as name,m.vessel_id into data_rec
            FROM auth.vessels v
            LEFT JOIN api.metadata m ON v.vessel_id = m.vessel_id
            WHERE m.vessel_id = process_rec.payload::TEXT;
        IF data_rec.vessel_id IS NULL OR data_rec.name IS NULL THEN
            RAISE WARNING '-> DEBUG cron_process_grafana_fn grafana_py_fn error [%]', data_rec;
            RETURN;
        END IF;
        -- as we got data from the vessel we can do the grafana provisioning.
        RAISE DEBUG '-> DEBUG cron_process_grafana_fn grafana_py_fn provisioning [%]', data_rec;
        PERFORM grafana_py_fn(data_rec.name, data_rec.vessel_id, data_rec.owner_email, app_settings);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(data_rec.vessel_id::TEXT);
        RAISE DEBUG '-> DEBUG cron_process_grafana_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        -- add user in keycloak
        PERFORM keycloak_auth_py_fn(data_rec.vessel_id, user_settings, app_settings);
        -- Send notification
        PERFORM send_notification_fn('grafana'::TEXT, user_settings::JSONB);
        -- update process_queue entry as processed
        UPDATE process_queue
            SET
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_grafana_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.cron_process_grafana_fn() IS 'init by pg_cron to check for new vessel pending grafana provisioning, if so perform grafana_py_fn';

-- DROP FUNCTION public.cron_process_skplugin_upgrade_fn();
-- Update cron_process_skplugin_upgrade_fn, update check for signalk plugin version
CREATE OR REPLACE FUNCTION public.cron_process_skplugin_upgrade_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    skplugin_upgrade_rec record;
    user_settings jsonb;
BEGIN
    -- Check for signalk plugin version
    RAISE NOTICE 'cron_process_plugin_upgrade_fn';
    FOR skplugin_upgrade_rec in
        SELECT
            v.owner_email,m.name,m.vessel_id,m.plugin_version,a.first
            FROM api.metadata m
            LEFT JOIN auth.vessels v ON v.vessel_id = m.vessel_id
            LEFT JOIN auth.accounts a ON v.owner_email = a.email
            WHERE m.plugin_version <> '0.4.1'
    LOOP
        RAISE NOTICE '-> cron_process_skplugin_upgrade_rec_fn for [%]', skplugin_upgrade_rec;
        SELECT json_build_object('email', skplugin_upgrade_rec.owner_email, 'recipient', skplugin_upgrade_rec.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_skplugin_upgrade_rec_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('skplugin_upgrade'::TEXT, user_settings::JSONB);
    END LOOP;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.cron_process_skplugin_upgrade_fn() IS 'init by pg_cron, check for signalk plugin version and notify for upgrade';

-- Grant access to the new table
GRANT SELECT ON TABLE api.metadata_ext TO user_role;
-- Allow users to update certain columns on metadata_ext table on API schema
GRANT INSERT,UPDATE (make_model, polar, image, image_b64, image_type) ON api.metadata_ext TO user_role;
-- Allow users to update certain columns on metadata table on API schema
GRANT INSERT,UPDATE (configuration) ON api.metadata TO user_role;
-- Allow anonymous to read api.metadata_ext table on API schema
GRANT SELECT ON TABLE api.metadata_ext TO api_anonymous;
-- Allow anonymous to export the vessel image on API schema
GRANT EXECUTE ON FUNCTION api.vessel_image TO api_anonymous;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO api_anonymous;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO api_anonymous;

ALTER TABLE api.metadata_ext ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.metadata_ext TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow user_role to insert, update and select on their own records
CREATE POLICY api_user_role ON api.metadata_ext TO user_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow anonymous to select
CREATE POLICY api_anonymous_role ON api.metadata_ext TO api_anonymous
    USING (true)
    WITH CHECK (false);

-- Allow user_role to select on their own records
DROP POLICY IF EXISTS api_user_role ON api.metrics;
CREATE POLICY api_user_role ON api.metrics TO user_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (false);
-- Allow vessel_role to inset on their own records
DROP POLICY IF EXISTS api_vessel_role ON api.metrics;
CREATE POLICY api_vessel_role ON api.metrics TO vessel_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));

-- Allow vessel_role to insert, update, select on their own records
DROP POLICY IF EXISTS api_vessel_role ON api.metadata;
CREATE POLICY api_vessel_role ON api.metadata TO vessel_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow user_role to insert, update, select on their own records
DROP POLICY IF EXISTS api_user_role ON api.metadata;
CREATE POLICY api_user_role ON api.metadata TO user_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));

-- refresh permissions
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO api_anonymous;

-- Update version
UPDATE public.app_settings
	SET value='0.9.1'
	WHERE "name"='app.version';

\c postgres
