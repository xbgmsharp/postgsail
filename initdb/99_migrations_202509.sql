---------------------------------------------------------------------------
-- Copyright 2021-2025 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration September 2025
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Update message
UPDATE public.email_templates
	SET email_content = $body$ 
Hello __RECIPIENT__,
We noticed you haven't logged any sailing activity yet, and wanted to check if everything is working smoothly for you.
Sometimes getting started with a new platform can be a bit overwhelming. Whether you need help connecting your boat, understanding the features, or just have questions about how PostgSail works, we're here to support you.
Don't hesitate to reach out - we love helping fellow sailors make the most of our free, open-source platform.
Best regards,
The PostgSail Team
$body$
	WHERE "name"='no_activity';
UPDATE public.email_templates
	SET email_content = $body$
Welcome to PostgSail! We're excited to have you on board.
We noticed you haven't connected your boat to the platform yet. Once connected, you'll be able to start logging your voyages, monitoring your vessel's systems, and exploring all the features PostgSail has to offer.
Need help getting connected? We're here to assist you every step of the way. Just reply to this email or check out our documentation to get started.
Remember, PostgSail is completely free and open-source - built by sailors, for sailors.
Fair winds,
The PostgSail Team
$body$
	WHERE "name"='no_metadata';
UPDATE public.email_templates
	SET email_content = $body$
Hello __RECIPIENT__,
Thank you for creating your PostgSail account! We noticed you haven't added your boat details yet, which is the next step to unlock all of PostgSail's features.
Adding your vessel information will allow you to:
* Track your sailing adventures and log entries
* Monitor your boat's systems and sensors
* Access detailed voyage analytics and mapping tools

Getting started is quick and easy. If you need any assistance setting up your vessel or have questions about the platform, please don't hesitate to reach out - we're here to help.
As always, PostgSail remains completely free and open-source for the sailing community.
Happy sailing,
The PostgSail Team
$body$
	WHERE "name"='no_vessel';


-- Add api.logbook_ext, new table to store vessel extended metadata from user
CREATE TABLE api.logbook_ext (
  vessel_id TEXT
             DEFAULT current_setting('vessel.id'::TEXT, false)
             REFERENCES api.metadata(vessel_id) ON DELETE RESTRICT,
  ref_id INT PRIMARY KEY REFERENCES api.logbook(id) ON DELETE RESTRICT,
  polar TEXT NULL, -- Store polar data in CSV notation as used on ORC sailboat data
  image_b64 TEXT NULL, -- Store user boat image in b64 format
  image bytea NULL, -- Store user boat image in bytea format
  image_type TEXT NULL, -- Store user boat image type in text format
  image_url TEXT NULL, -- Store user boat image url in text format
  image_updated_at timestamptz NULL,
  created_at timestamptz DEFAULT now() NOT NULL
);
-- Description
COMMENT ON TABLE
    api.logbook_ext
    IS 'Stores logbook extended information for the vessel from user';

-- Add api.moorages_ext, new table to store vessel extended metadata from user
CREATE TABLE api.moorages_ext (
  vessel_id TEXT
             DEFAULT current_setting('vessel.id'::TEXT, false)
             REFERENCES api.metadata(vessel_id) ON DELETE RESTRICT,
  ref_id INT PRIMARY KEY REFERENCES api.moorages(id) ON DELETE RESTRICT,
  image_b64 TEXT NULL, -- Store user boat image in b64 format
  image bytea NULL, -- Store user boat image in bytea format
  image_type TEXT NULL, -- Store user boat image type in text format
  image_url TEXT NULL, -- Store user boat image url in text format
  image_updated_at timestamptz NULL,
  created_at timestamptz DEFAULT now() NOT NULL
);
-- Description
COMMENT ON TABLE
    api.moorages_ext
    IS 'Stores moorages extended information for the vessel from user';

-- Description of columns
-- api.logbook_ext
COMMENT ON COLUMN api.logbook_ext.polar IS 'Store logbook polar data in CSV notation as used on ORC sailboat data';
COMMENT ON COLUMN api.logbook_ext.image_b64 IS 'Base64 encoded image of the vessel';
COMMENT ON COLUMN api.logbook_ext.image IS 'Binary image data of the vessel';
COMMENT ON COLUMN api.logbook_ext.image_type IS 'MIME type of the image';
COMMENT ON COLUMN api.logbook_ext.image_url IS 'URL of the image';
COMMENT ON COLUMN api.logbook_ext.image_updated_at IS 'Timestamp when image was last updated';
COMMENT ON COLUMN api.logbook_ext.created_at IS 'Timestamp when the record was created';
COMMENT ON COLUMN api.logbook_ext.vessel_id IS 'Unique identifier for the vessel associated with the api.metadata entry';
COMMENT ON COLUMN api.logbook_ext.ref_id IS 'Unique identifier for the logbook entry associated with the api.logbook entry';
-- api.moorages_ext
COMMENT ON COLUMN api.moorages_ext.image_b64 IS 'Base64 encoded image of the vessel';
COMMENT ON COLUMN api.moorages_ext.image IS 'Binary image data of the vessel';
COMMENT ON COLUMN api.moorages_ext.image_type IS 'MIME type of the image';
COMMENT ON COLUMN api.moorages_ext.image_url IS 'URL of the image';
COMMENT ON COLUMN api.moorages_ext.image_updated_at IS 'Timestamp when image was last updated';
COMMENT ON COLUMN api.moorages_ext.created_at IS 'Timestamp when the record was created';
COMMENT ON COLUMN api.moorages_ext.vessel_id IS 'Unique identifier for the vessel associated with the api.metadata entry';
COMMENT ON COLUMN api.moorages_ext.ref_id IS 'Unique identifier for the moorage entry associated with the api.moorages entry';
-- Update api.stays_ext, rename stay_id to ref_id for consistency
ALTER TABLE api.stays_ext RENAME COLUMN stay_id TO ref_id;
COMMENT ON COLUMN api.stays_ext.ref_id IS 'Unique identifier for the stay entry associated with the api.stays entry';
-- Lint fix
CREATE INDEX ON api.stays_ext (ref_id);

-- Add index on vessel_id for faster lookup
CREATE INDEX ON api.logbook_ext (vessel_id);
CREATE INDEX ON api.moorages_ext (vessel_id);

-- Remove old image functions if exist
DROP FUNCTION IF EXISTS api.stays_image;
DROP FUNCTION IF EXISTS api.vessel_image;
-- Add api.image function, generic to retrieve image for vessel, stay, logbook or moorage with proper headers for PostgREST
CREATE OR REPLACE FUNCTION api.image(
    entity text,                  -- 'vessel', 'stay', 'logbook', 'moorage'
    v_id text DEFAULT NULL,       -- vessel_id
    _id integer DEFAULT NULL      -- ref id from stay, logbook, moorage when needed
)
RETURNS "*/*"
LANGUAGE plpgsql
AS $function$
DECLARE
    headers text;
    blob bytea;
    tbl text;
BEGIN
    -- Map entity name to table + id column
    CASE entity
        WHEN 'vessel'  THEN tbl := 'api.metadata_ext';
        WHEN 'stay'    THEN tbl := 'api.stays_ext';
        WHEN 'logbook' THEN tbl := 'api.logbook_ext';
        WHEN 'moorage' THEN tbl := 'api.moorages_ext';
        ELSE
            RAISE EXCEPTION 'Unsupported entity: %', entity
                USING ERRCODE = 'PT400',
                      DETAIL = 'Entity must be one of vessel, stay, logbook, moorage',
                      HINT   = 'Check input argument "entity".';
    END CASE;

    -- Build headers + fetch image
    IF entity = 'vessel' THEN
        EXECUTE format(
            $sql$
            SELECT format(
                '[{"Content-Type": "%%s"},'
                '{"Content-Disposition": "inline; filename=\"%%s.%%s\""},'
                '{"Cache-Control": "max-age=900"}]',
              image_type, %L, split_part(image_type, '/', 2)
            ), image
            FROM %s WHERE vessel_id = %L
            $sql$,
            v_id, tbl, v_id
        )
        INTO headers, blob;
    ELSE
        EXECUTE format(
            $sql$
            SELECT format(
                '[{"Content-Type": "%%s"},'
                '{"Content-Disposition": "inline; filename=\"%%s.%%s\""},'
                '{"Cache-Control": "max-age=900"}]',
              image_type, %L, split_part(image_type, '/', 2)
            ), image
            FROM %s WHERE vessel_id = %L AND ref_id = %s
            $sql$,
            entity || '_' || v_id || '_' || _id,
            tbl, v_id, _id
        )
        INTO headers, blob;
    END IF;

    -- Apply headers
    PERFORM set_config('response.headers', headers, true);

    -- Return image or 404
    IF blob IS NOT NULL THEN
        RETURN blob;
    ELSE
        RAISE sqlstate 'PT404'
          USING message = 'NOT FOUND',
                detail  = 'File not found',
                hint    = format('%s seems to be an invalid for %s', v_id, entity);
    END IF;
END
$function$;
-- Description
COMMENT ON FUNCTION api.image(text, text, integer) IS 'Retrieve image for vessel, stays, logs or moorages with proper headers for PostgREST';

-- DROP FUNCTION api.vessel_extended_fn();
-- Update api.vessel_extended_fn, update image_url and polar
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
          'has_image',
            CASE
                WHEN image IS NULL AND image_url IS NOT NULL THEN true
                WHEN image IS NOT NULL AND image_url IS NULL THEN true
                ELSE false
            END,
          'image_url', 
            CASE
                WHEN image IS NULL AND image_url IS NOT NULL THEN image_url
                WHEN image IS NOT NULL AND image_url IS NULL THEN '/rpc/image?entity=vessel&v_id=' || vessel_id
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
$function$
;
-- Description
COMMENT ON FUNCTION api.vessel_extended_fn() IS 'Return vessel details from metadata_ext (polar csv,image url, make model)';

DROP FUNCTION IF EXISTS public.stays_ext_update_s3_trigger_fn();
DROP TRIGGER IF EXISTS stays_ext_update_s3_trigger ON api.stays_ext;
--DROP VIEW IF EXISTS api.noteshistory_view;
ALTER VIEW IF EXISTS api.noteshistory_view RENAME TO stay_explore_view;
-- Rename api.noteshistory_view to api.stay_explore_view
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
        WHEN se.image IS NULL AND se.image_url IS NOT NULL THEN true
        WHEN se.image IS NOT NULL AND se.image_url IS NULL THEN true
        ELSE false
    END AS has_image,
    CASE
        WHEN se.image IS NULL AND se.image_url IS NOT NULL THEN se.image_url
        WHEN se.image IS NOT NULL AND se.image_url IS NULL THEN (('/rpc/image?entity=stays&v_id='::text || s.vessel_id) || '&_id='::text) || s.id
        ELSE NULL::text
    END AS image_url,
    s.id AS id, -- duplicate entry for compatibility
    s.name AS name -- duplicate entry for compatibility
    FROM api.stays s
    LEFT JOIN api.moorages m ON s.moorage_id = m.id
    LEFT JOIN api.stays_ext se ON s.id = se.ref_id
  --WHERE s.vessel_id = current_setting('vessel.id'::text, false)
  ORDER BY s.arrived DESC;
-- Description
COMMENT ON VIEW api.stay_explore_view IS 'List moorages notes order by stays';

-- api.stay_view source
-- Update api.stay_view, add image_url and has_image
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
        WHEN se.image IS NULL AND se.image_url IS NOT NULL THEN true
        WHEN se.image IS NOT NULL AND se.image_url IS NULL THEN true
        ELSE false
    END AS has_image,
    CASE
        WHEN se.image IS NULL AND se.image_url IS NOT NULL THEN se.image_url
        WHEN se.image IS NOT NULL AND se.image_url IS NULL THEN (('/rpc/image?entity=stays&v_id='::text || s.vessel_id) || '&_id='::text) || s.id
        ELSE NULL::text
    END AS image_url,
    se.image_updated_at
   FROM api.stays s
     JOIN api.stays_at sa ON s.stay_code = sa.stay_code
     JOIN api.moorages m ON s.moorage_id = m.id
     LEFT JOIN api.stays_ext se ON se.ref_id = s.id
     LEFT JOIN api.logbook _from ON _from._from_time = s.departed
     LEFT JOIN api.logbook _to ON _to._to_time = s.arrived
  WHERE s.departed IS NOT NULL AND _from._to_moorage_id IS NOT NULL AND s.name IS NOT NULL
  ORDER BY s.arrived DESC;
-- Description
COMMENT ON VIEW api.stay_view IS 'Stay web view';

-- Update api.moorage_view, add image_url and has_image
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
        WHEN me.image IS NULL AND me.image_url IS NOT NULL THEN true
        WHEN me.image IS NOT NULL AND me.image_url IS NULL THEN true
        ELSE false
    END AS has_image,
    CASE
        WHEN me.image IS NULL AND me.image_url IS NOT NULL THEN me.image_url
        WHEN me.image IS NOT NULL AND me.image_url IS NULL THEN (('/rpc/image?entity=moorages&v_id='::text || m.vessel_id) || '&_id='::text) || m.id
        ELSE NULL::text
    END AS image_url,
    me.image_updated_at
   FROM api.moorages m
     JOIN api.stays_at sa ON m.stay_code = sa.stay_code
     LEFT JOIN api.moorages_ext me ON m.id = me.ref_id
     LEFT JOIN stay_summary ss ON m.id = ss.moorage_id
     LEFT JOIN log_summary l ON m.id = l.moorage_id
  WHERE m.geog IS NOT NULL
  ORDER BY ss.total_duration DESC;
-- Description
COMMENT ON VIEW api.moorage_view IS 'Moorage details web view';

-- Update api.log_view, add image_url and has_image
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
    _to_moorage_id AS to_moorage_id,
    CASE
        WHEN le.image IS NULL AND le.image_url IS NOT NULL THEN true
        WHEN le.image IS NOT NULL AND le.image_url IS NULL THEN true
        ELSE false
    END AS has_image,
    CASE
        WHEN le.image IS NULL AND le.image_url IS NOT NULL THEN le.image_url
        WHEN le.image IS NOT NULL AND le.image_url IS NULL THEN (('/rpc/image?entity=logbook&v_id='::text || l.vessel_id) || '&_id='::text) || l.id
        ELSE NULL::text
    END AS image_url,
    le.image_updated_at,
    le.polar
   FROM api.logbook l
   LEFT JOIN api.logbook_ext le ON le.ref_id = l.id
  WHERE _to_time IS NOT NULL AND trip IS NOT NULL
  ORDER BY _from_time DESC;
-- Description
COMMENT ON VIEW api.log_view IS 'Log web view';

-- Update api.logs_geojson_view, add image_url and has_image
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
		    CASE
		        WHEN le.image IS NULL AND le.image_url IS NOT NULL THEN true
		        WHEN le.image IS NOT NULL AND le.image_url IS NULL THEN true
		        ELSE false
		    END AS has_image,
		    CASE
		        WHEN le.image IS NULL AND le.image_url IS NOT NULL THEN le.image_url
		        WHEN le.image IS NOT NULL AND le.image_url IS NULL THEN (('/rpc/image?entity=logbook&v_id='::text || l.vessel_id) || '&_id='::text) || l.id
		        ELSE NULL::text
		    END AS image_url,
		    le.image_updated_at
           FROM api.logbook l
           LEFT JOIN api.logbook_ext le ON le.ref_id = l.id
          WHERE l._to_time IS NOT NULL AND l.trip IS NOT NULL
          ORDER BY l._from_time DESC) tbl;
-- Description
COMMENT ON VIEW api.logs_geojson_view IS 'List logs with geojson';

-- api.moorages_geojson_view source
-- Update api.moorages_geojson_view, add image_url and has_image
CREATE OR REPLACE VIEW api.moorages_geojson_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT id,
    name,
    st_asgeojson(m.*)::jsonb AS geojson
   FROM ( SELECT m_1.id,
            m_1.name,
            m_1.default_stay,
            m_1.default_stay_id,
            m_1.home,
            m_1.notes,
            m_1.geog,
            m_1.logs_count,
            m_1.stays_count,
            m_1.stays_sum_duration,
            m_1.stay_first_seen,
            m_1.stay_last_seen,
            m_1.stay_first_seen_id,
            m_1.stay_last_seen_id,
        	CASE
			    WHEN me.image IS NULL AND me.image_url IS NOT NULL THEN true
			    WHEN me.image IS NOT NULL AND me.image_url IS NULL THEN true
			    ELSE false
			END AS has_image,
			CASE
			    WHEN me.image IS NULL AND me.image_url IS NOT NULL THEN me.image_url
			    WHEN me.image IS NOT NULL AND me.image_url IS NULL THEN (('/rpc/image?entity=moorage&v_id='::text || current_setting('vessel.id', false)) || '&_id='::text) || m_1.id
			        ELSE NULL::text
			    END AS image_url,
			me.image_updated_at
       FROM api.moorage_view m_1
     	LEFT JOIN api.moorages_ext me ON m_1.id = me.ref_id 
          WHERE m_1.geog IS NOT NULL) m;
-- Description
COMMENT ON VIEW api.moorages_geojson_view IS 'List moorages with geojson';

-- Update api.stays_geojson_view, call api.stay_explore_view
DROP VIEW IF EXISTS api.stays_geojson_view;
CREATE OR REPLACE VIEW api.stays_geojson_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT
        ST_AsGeoJSON(tbl.*)::JSONB as geojson
        FROM
        ( SELECT
            *,
            ST_MakePoint(longitude, latitude) FROM api.stay_explore_view
        ) AS tbl;
-- Description
COMMENT ON VIEW api.stays_geojson_view IS 'List stays with geojson';

-- DROP FUNCTION public.stay_delete_trigger_fn();
-- Update public.stay_delete_trigger_fn, rename stay_id to ref_id
CREATE OR REPLACE FUNCTION public.stay_delete_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE NOTICE 'stay_delete_trigger_fn [%]', OLD;
    -- If api.stays is deleted, deleted entry in api.stays_ext table as well.
    IF EXISTS (SELECT FROM information_schema.tables 
                WHERE table_schema = 'api' 
                AND table_name = 'stays_ext') THEN
        -- Delete stays_ext
        DELETE FROM api.stays_ext s
            WHERE s.ref_id = OLD.id;
    END IF;
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

-- Add public.update_tbl_ext_decode_base64_image_trigger_fn, decode a base64 image into bytea for all extended tables
CREATE OR REPLACE FUNCTION public.update_tbl_ext_decode_base64_image_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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
$function$
;
-- Description
COMMENT ON FUNCTION public.update_tbl_ext_decode_base64_image_trigger_fn() IS 'Decode base64 image string to bytea format for all extended tables, eg: logbook, moorages and stays';

CREATE TRIGGER logbook_ext_decode_image_trigger BEFORE INSERT OR UPDATE
ON api.logbook_ext FOR EACH ROW EXECUTE FUNCTION  public.update_tbl_ext_decode_base64_image_trigger_fn();
-- Description
COMMENT ON TRIGGER logbook_ext_decode_image_trigger ON api.logbook_ext IS 'BEFORE INSERT OR UPDATE ON api.logbook_ext run function update_tbl_ext_decode_base64_image_trigger_fn, convert image_b64 to image bytea';

CREATE TRIGGER moorages_ext_decode_image_trigger BEFORE INSERT OR UPDATE
    ON api.moorages_ext FOR EACH ROW EXECUTE FUNCTION public.update_tbl_ext_decode_base64_image_trigger_fn();
-- Description
COMMENT ON TRIGGER moorages_ext_decode_image_trigger ON api.moorages_ext IS 'BEFORE INSERT OR UPDATE ON api.moorages_ext run function update_tbl_ext_decode_base64_image_trigger_fn, convert image_b64 to image bytea';

DROP TRIGGER stays_ext_decode_image_trigger ON api.stays_ext;
CREATE TRIGGER stays_ext_decode_image_trigger BEFORE INSERT OR UPDATE
    ON api.stays_ext FOR EACH ROW EXECUTE FUNCTION public.update_tbl_ext_decode_base64_image_trigger_fn();
-- Description
COMMENT ON TRIGGER stays_ext_decode_image_trigger ON api.stays_ext IS 'BEFORE INSERT OR UPDATE ON api.stays_ext run function update_stays_ext_decode_base64_image_trigger_fn, convert image_b64 to image bytea';
-- Cleanup old function
DROP FUNCTION IF EXISTS public.update_stays_ext_decode_base64_image_trigger_fn();
-- Cleanup old function in api schema
DROP TRIGGER IF EXISTS metadata_ext_decode_image_trigger ON api.metadata_ext;
DROP TRIGGER IF EXISTS metadata_ext_update_added_at_trigger ON api.metadata_ext;
DROP FUNCTION IF EXISTS api.update_metadata_ext_decode_base64_image_fn();
DROP FUNCTION IF EXISTS public.update_metadata_ext_decode_base64_image_trigger_fn();
DROP FUNCTION IF EXISTS public.decode_base64_image_fn();

-- Add public.update_metadata_ext_added_at_fn, update polar_updated_at and image_updated_at when polar or image is updated in metadata_ext
CREATE OR REPLACE FUNCTION public.update_metadata_ext_added_at_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.polar IS DISTINCT FROM OLD.polar THEN
    NEW.polar_updated_at := NOW();
  END IF;

  IF NEW.image IS DISTINCT FROM OLD.image THEN
    NEW.image_updated_at := NOW();
  END IF;

  IF NEW.image_url IS DISTINCT FROM OLD.image_url THEN
    NEW.image_updated_at := NOW();
  END IF;

  RETURN NEW;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.update_metadata_ext_added_at_trigger_fn() IS 'Update polar_updated_at and image_updated_at when polar or image is updated in metadata_ext';

CREATE TRIGGER metadata_ext_update_added_at_trigger
    BEFORE INSERT OR UPDATE ON
    api.metadata_ext for each row execute function public.update_metadata_ext_added_at_trigger_fn();
-- Description
COMMENT ON TRIGGER metadata_ext_update_added_at_trigger ON api.metadata_ext IS 'BEFORE INSERT OR UPDATE ON api.metadata_ext run function update_metadata_ext_update_added_at_trigger_fn';

CREATE TRIGGER metadata_ext_decode_image_trigger
    BEFORE INSERT OR UPDATE ON
    api.metadata_ext for each row execute function public.update_tbl_ext_decode_base64_image_trigger_fn();
-- Description
COMMENT ON TRIGGER metadata_ext_decode_image_trigger ON api.metadata_ext IS 'BEFORE INSERT OR UPDATE ON api.metadata_ext run function update_metadata_ext_decode_image_trigger_fn';

-- Cleanup api schema from trigger function, api.update_tbl_ext_added_at_fn, update image_updated_at when image is updated in extended tables
DROP TRIGGER IF EXISTS stays_ext_update_added_at_trigger ON api.stays_ext;
DROP TRIGGER IF EXISTS logbook_ext_update_added_at_trigger ON api.logbook_ext;
DROP TRIGGER IF EXISTS moorages_ext_update_added_at_trigger ON api.moorages_ext;
DROP FUNCTION IF EXISTS api.update_metadata_ext_added_at_fn();
DROP FUNCTION IF EXISTS api.update_tbl_ext_added_at_fn();

-- Add public.update_tbl_ext_added_at_trigger_fn update image_updated_at when image is updated in extended tables
CREATE OR REPLACE FUNCTION public.update_tbl_ext_added_at_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN

  IF NEW.image IS DISTINCT FROM OLD.image THEN
    NEW.image_updated_at := NOW();
  END IF;

  IF NEW.image_url IS DISTINCT FROM OLD.image_url THEN
    NEW.image_updated_at := NOW();
  END IF;

  RETURN NEW;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.update_tbl_ext_added_at_trigger_fn() IS 'Update image_updated_at when image is updated in extended tables (logbook_ext, moorages_ext, stays_ext)';

CREATE TRIGGER logbook_ext_update_added_at_trigger
    BEFORE INSERT OR UPDATE ON
    api.logbook_ext for each row execute function public.update_tbl_ext_added_at_trigger_fn();
-- Description
COMMENT ON TRIGGER logbook_ext_update_added_at_trigger ON api.logbook_ext IS 'BEFORE INSERT OR UPDATE ON api.logbook_ext run function update_tbl_ext_added_at_trigger_fn';

CREATE TRIGGER moorages_ext_update_added_at_trigger
    BEFORE INSERT OR UPDATE ON
    api.moorages_ext for each row execute function public.update_tbl_ext_added_at_trigger_fn();
-- Description
COMMENT ON TRIGGER moorages_ext_update_added_at_trigger ON api.moorages_ext IS 'BEFORE INSERT OR UPDATE ON api.moorages_ext run function update_tbl_ext_added_at_trigger_fn';

CREATE TRIGGER stays_ext_update_added_at_trigger
    BEFORE INSERT OR UPDATE ON
    api.stays_ext for each row execute function public.update_tbl_ext_added_at_trigger_fn();
-- Description
COMMENT ON TRIGGER stays_ext_update_added_at_trigger ON api.stays_ext IS 'BEFORE INSERT OR UPDATE ON api.stays_ext run function update_tbl_ext_added_at_trigger_fn';

-- DROP FUNCTION public.send_email_py_fn(text, jsonb, jsonb);
-- Update public.send_email_py_fn, update logbook link for timelapse
CREATE OR REPLACE FUNCTION public.send_email_py_fn(email_type text, _user jsonb, app jsonb)
 RETURNS void
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
AS $function$
    # Import smtplib for the actual sending function
    import smtplib
    import requests

    # Import the email modules we need
    from email.message import EmailMessage
    from email.utils import formatdate,make_msgid
    from email.mime.text import MIMEText

    # Use the shared cache to avoid preparing the email metadata
    if email_type in SD:
        plan = SD[email_type]
    # A prepared statement from Python
    else:
        plan = plpy.prepare("SELECT * FROM email_templates WHERE name = $1", ["text"])
        SD[email_type] = plan

    # Execute the statement with the email_type param and limit to 1 result
    rv = plpy.execute(plan, [email_type], 1)
    email_subject = rv[0]['email_subject']
    email_content = rv[0]['email_content']

    # Replace fields using input jsonb obj
    if not _user or not app:
        plpy.notice('send_email_py_fn Parameters [{}] [{}]'.format(_user, app))
        plpy.error('Error missing parameters')
        return None

    if 'logbook_name' in _user and _user['logbook_name']:
        email_content = email_content.replace('__LOGBOOK_NAME__', str(_user['logbook_name']))
    if 'logbook_link' in _user and _user['logbook_link']:
        email_content = email_content.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'logbook_img' in _user and _user['logbook_img']:
        email_content = email_content.replace('__LOGBOOK_IMG__', str(_user['logbook_img']))
    if 'logbook_stats' in _user and _user['logbook_stats']:
        email_content = email_content.replace('__LOGBOOK_STATS__', str(_user['logbook_stats']))
    if 'video_link' in _user and _user['video_link']:
        email_content = email_content.replace('__VIDEO_LINK__', str(_user['video_link']))
    if 'recipient' in _user and _user['recipient']:
        email_content = email_content.replace('__RECIPIENT__', _user['recipient'])
    if 'boat' in _user and _user['boat']:
        email_content = email_content.replace('__BOAT__', _user['boat'])
    if 'badge' in _user and _user['badge']:
        email_content = email_content.replace('__BADGE_NAME__', _user['badge'])
    if 'otp_code' in _user and _user['otp_code']:
        email_content = email_content.replace('__OTP_CODE__', _user['otp_code'])
    if 'reset_qs' in _user and _user['reset_qs']:
        email_content = email_content.replace('__RESET_QS__', _user['reset_qs'])
    if 'alert' in _user and _user['alert']:
        email_content = email_content.replace('__ALERT__', _user['alert'])

    if 'app.url' in app and app['app.url']:
        email_content = email_content.replace('__APP_URL__', app['app.url'])

    email_from = 'root@localhost'
    if 'app.email_from' in app and app['app.email_from']:
        email_from = 'PostgSail <' + app['app.email_from'] + '>'
    #plpy.notice('Sending email from [{}] [{}]'.format(email_from, app['app.email_from']))

    email_to = 'root@localhost'
    if 'email' in _user and _user['email']:
        email_to = _user['email']
        #plpy.notice('Sending email to [{}] [{}]'.format(email_to, _user['email']))
    else:
        plpy.error('Error email to')
        return None

    if email_type == 'logbook':
        msg = EmailMessage()
        msg.set_content(email_content)
    else:
        msg = MIMEText(email_content, 'plain', 'utf-8')

    msg["Subject"] = email_subject
    msg["From"] = email_from
    msg["To"] = email_to
    msg["Date"] = formatdate()
    msg["Message-ID"] = make_msgid()

    if email_type == 'logbook' and 'logbook_img' in _user and _user['logbook_img']:
        # Create a Content-ID for the image
        image_cid = make_msgid()
        # Transform HTML template
        logbook_link = '{__APP_URL__}/log/{__LOGBOOK_LINK__}'.format( __APP_URL__=app['app.url'], __LOGBOOK_LINK__=str(_user['logbook_link']))
        timelapse_link = '{__APP_URL__}/timelapse/{__LOGBOOK_LINK__}'.format( __APP_URL__=app['app.url'], __LOGBOOK_LINK__=str(_user['logbook_link']))
        email_content = email_content.replace('\n', '<br/>')
        email_content = email_content.replace(logbook_link, '<a href="{logbook_link}">{logbook_link}</a>'.format(logbook_link=str(logbook_link)))
        email_content = email_content.replace(timelapse_link, '<a href="{timelapse_link}">{timelapse_link}</a>'.format(timelapse_link=str(timelapse_link)))
        email_content = email_content.replace(str(_user['logbook_name']), '<a href="{logbook_link}">{logbook_name}</a>'.format(logbook_link=str(logbook_link), logbook_name=str(_user['logbook_name'])))
        # Set an alternative html body
        msg.add_alternative("""\
<html>
    <body>
        <p>{email_content}</p>
        <img src="cid:{image_cid}">
    </body>
</html>
""".format(email_content=email_content, image_cid=image_cid[1:-1]), subtype='html')
        img_url = 'https://gis.openplotter.cloud/{}'.format(str(_user['logbook_img']))
        response = requests.get(img_url, stream=True)
        if response.status_code == 200:
            msg.get_payload()[1].add_related(response.raw.data,
                                            maintype='image', 
                                            subtype='png', 
                                            cid=image_cid)

    server_smtp = 'localhost'
    if 'app.email_server' in app and app['app.email_server']:
        server_smtp = app['app.email_server']
    #plpy.notice('Sending server [{}] [{}]'.format(server_smtp, app['app.email_server']))

    # Send the message via our own SMTP server.
    try:
        # send your message with credentials specified above
        with smtplib.SMTP(server_smtp, 587) as server:
            if 'app.email_user' in app and app['app.email_user'] \
                and 'app.email_pass' in app and app['app.email_pass']:
                server.starttls()
                server.login(app['app.email_user'], app['app.email_pass'])
            #server.send_message(msg)
            server.sendmail(msg["From"], msg["To"], msg.as_string())
            server.quit()
        # tell the script to report if your message was sent or which errors need to be fixed
        plpy.notice('Sent email successfully to [{}] [{}]'.format(msg["To"], msg["Subject"]))
        return None
    except OSError as error:
        plpy.error('OS Error occurred: ' + str(error))
    except smtplib.SMTPConnectError:
        plpy.error('Failed to connect to the server. Bad connection settings?')
    except smtplib.SMTPServerDisconnected:
        plpy.error('Failed to connect to the server. Wrong user/password?')
    except smtplib.SMTPException as e:
        plpy.error('SMTP error occurred: ' + str(e))
$function$
;
-- Description
COMMENT ON FUNCTION public.send_email_py_fn(text, jsonb, jsonb) IS 'Send email notification using plpython3u';

-- DROP FUNCTION public.export_logbook_polar_fn(int4);
-- Add public.export_logbook_polar_fn to generate polar for a log
CREATE OR REPLACE FUNCTION public.export_logbook_polar_fn(_id integer)
RETURNS TABLE (
    awa_bin integer,
    tws_bin integer,
    avg_speed numeric,
    max_speed numeric,
    samples integer
)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_vessel_id text;
    v_from_time timestamptz;
    v_to_time timestamptz;
BEGIN
    -- Get vessel_id and time range from logbook
    SELECT vessel_id, _from_time, _to_time
    INTO v_vessel_id, v_from_time, v_to_time
    FROM api.logbook
    WHERE id = _id;

    -- Safety check
    IF v_vessel_id IS NULL OR v_from_time IS NULL OR v_to_time IS NULL THEN
        RAISE EXCEPTION 'Logbook id % not found or missing time range', _id;
    END IF;

    -- Step 1–4: Build and return query
    RETURN QUERY
    WITH base AS (
        SELECT
            (ROUND(m.anglespeedapparent / 5) * 5)::int AS awa_bin_c,
            m.speedoverground,
            m.windspeedapparent,
            m.anglespeedapparent,
            (m.metrics->'wind'->>'speed')::NUMERIC AS true_wind_speed
        FROM api.metrics m
        WHERE m.speedoverground IS NOT NULL
          AND m.windspeedapparent IS NOT NULL
          AND m.anglespeedapparent IS NOT NULL
          AND vessel_id = v_vessel_id
          AND time >= v_from_time
          AND time <= v_to_time
          AND ABS(m.anglespeedapparent) >= 25
    ),
    grouped AS (
        SELECT
            awa_bin_c,
            (
                CASE
                    WHEN true_wind_speed < 7  THEN 6
                    WHEN true_wind_speed < 9  THEN 8
                    WHEN true_wind_speed < 11 THEN 10
                    WHEN true_wind_speed < 13 THEN 12
                    WHEN true_wind_speed < 15 THEN 14
                    WHEN true_wind_speed < 17 THEN 16
                    WHEN true_wind_speed < 22 THEN 20
                    WHEN true_wind_speed < 27 THEN 25
                    ELSE 30
                END
            )::int AS tws_bin_c,
            ROUND(AVG(speedoverground)::numeric, 2) AS avg_speed_c,
            ROUND(MAX(speedoverground)::numeric, 2) AS max_speed_c,
            COUNT(*)::int AS samples_c
        FROM base
        GROUP BY awa_bin_c, tws_bin_c
    ),
    tws_bins AS (
        SELECT DISTINCT tws_bin_c FROM grouped
    )
    SELECT g.awa_bin_c AS awa_bin,
           g.tws_bin_c AS tws_bin,
           g.avg_speed_c AS avg_speed,
           g.max_speed_c AS max_speed,
           g.samples_c AS samples
    FROM grouped g
    UNION ALL
    SELECT 0 AS awa_bin, t.tws_bin_c, 0 AS avg_speed, 0 AS max_speed, 0 AS samples
    FROM tws_bins t
    ORDER BY tws_bin, awa_bin;

END;
$function$;
-- Description
COMMENT ON FUNCTION public.export_logbook_polar_fn(int4) IS 'Generate polar for a log';

DROP FUNCTION IF EXISTS api.export_logbook_polar_csv_fn(int4);
-- Add api.export_logbook_polar_csv_fn to generate polar csv for a log
CREATE OR REPLACE FUNCTION api.export_logbook_polar_csv_fn(_id integer)
RETURNS text
LANGUAGE plpgsql
AS $function$
DECLARE
    v_csv text;
    v_header text;
BEGIN

    -- Safety check
    IF _id IS NULL THEN
        RAISE EXCEPTION 'Logbook id % not found', _id;
    END IF;

    -- Build header dynamically (fix: subquery for distinct tws_bin)
    SELECT 'twa/tws;' || string_agg(tws_bin::text, ';')
    INTO v_header
    FROM (
        SELECT DISTINCT g.tws_bin
        FROM public.export_logbook_polar_fn(_id) g
        ORDER BY g.tws_bin
    ) sub;

    -- Build body: pivot rows into CSV
    SELECT string_agg(row_line, E'\n')
    INTO v_csv
    FROM (
        SELECT p.awa_bin::text || ';' ||
               string_agg(COALESCE(p.avg_speed_txt, '0.0'), ';' ORDER BY p.tws_bin) AS row_line
        FROM (
            SELECT a.awa_bin,
                   t.tws_bin,
                   COALESCE(
                       to_char(MAX(g.avg_speed), 'FM999999990.000'),
                       '0.0'
                   ) AS avg_speed_txt
            FROM (SELECT DISTINCT g1.awa_bin FROM public.export_logbook_polar_fn(_id) g1) a
            CROSS JOIN (SELECT DISTINCT g2.tws_bin FROM public.export_logbook_polar_fn(_id) g2) t
            LEFT JOIN public.export_logbook_polar_fn(_id) g
                   ON g.awa_bin = a.awa_bin
                  AND g.tws_bin = t.tws_bin
            GROUP BY a.awa_bin, t.tws_bin
        ) p
        GROUP BY p.awa_bin
        ORDER BY p.awa_bin
    ) rows;

    -- Prepend header
    v_csv := v_header || E'\n' || COALESCE(v_csv, '');

    RETURN v_csv;
END;
$function$;
-- Description
COMMENT ON FUNCTION api.export_logbook_polar_csv_fn(int4) IS 'Generate polar csv in the orc-data format for a log';

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
    SELECT current_setting('request.path', true) ~ '^/(logs_view|log_view|rpc/timelapse_fn|rpc/timelapse2_fn|monitoring_view|stats_logs_view|stats_moorages_view|rpc/stats_logs_fn|rpc/export_logbooks_geojson_point_trips_fn|rpc/export_logbooks_geojson_linestring_trips_fn)$' INTO _ppath;
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

-- Refresh permissions user_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
-- Refresh permissions api_anonymous
GRANT EXECUTE ON FUNCTION api.image TO api_anonymous;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO api_anonymous;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO api_anonymous;
-- Refresh permissions Scheduler
GRANT SELECT ON ALL TABLES IN SCHEMA api TO scheduler;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO scheduler;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO scheduler;

-- Enforce RLS on extended tables
ALTER TABLE api.metadata_ext FORCE ROW LEVEL SECURITY;
ALTER TABLE api.stays_ext FORCE ROW LEVEL SECURITY;
ALTER TABLE api.logbook_ext FORCE ROW LEVEL SECURITY;
ALTER TABLE api.moorages_ext FORCE ROW LEVEL SECURITY;

-- Grant execute on polar CSV function
GRANT EXECUTE ON FUNCTION public.export_logbook_polar_fn(int4) TO grafana;

-- Allow anonymous to read api extended tables on API schema
GRANT SELECT ON TABLE api.metadata_ext TO api_anonymous;
GRANT SELECT ON TABLE api.logbook_ext TO api_anonymous;
GRANT SELECT ON TABLE api.stays_ext TO api_anonymous;
GRANT SELECT ON TABLE api.moorages_ext TO api_anonymous;
GRANT SELECT ON TABLE api.metadata_ext TO grafana;
GRANT SELECT ON TABLE api.logbook_ext TO grafana;
GRANT SELECT ON TABLE api.stays_ext TO grafana;
GRANT SELECT ON TABLE api.moorages_ext TO grafana;

-- Allow user_role to insert and update image fields on extended tables
GRANT INSERT,UPDATE (ref_id, image, image_b64, image_type, image_url) ON api.moorages_ext TO user_role;
GRANT INSERT,UPDATE (ref_id, image, image_b64, image_type, image_url) ON api.logbook_ext TO user_role;
GRANT INSERT,UPDATE (ref_id, image, image_b64, image_type, image_url) ON api.stays_ext TO user_role;
GRANT INSERT,UPDATE (polar, image, image_b64, image_type, image_url, image_updated_at) ON api.metadata_ext TO user_role;

-- Allow user_role to delete on extended tables
GRANT DELETE ON TABLE api.stays_ext TO user_role;
GRANT DELETE ON TABLE api.moorages_ext TO user_role;
GRANT DELETE ON TABLE api.logbook_ext TO user_role;

-- Enable RLS on api.logbook_ext
ALTER TABLE api.logbook_ext ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.logbook_ext TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow user_role to insert, update and select on their own records
CREATE POLICY api_user_role ON api.logbook_ext TO user_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow anonymous to select
CREATE POLICY api_anonymous_role ON api.logbook_ext TO api_anonymous
    USING (true)
    WITH CHECK (false);
-- Disallow vessel_role
CREATE POLICY api_vessel_role ON api.logbook_ext TO vessel_role
    USING (false)
    WITH CHECK (false);

-- Enable RLS on api.moorages_ext
ALTER TABLE api.moorages_ext ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.moorages_ext TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow user_role to insert, update and select on their own records
CREATE POLICY api_user_role ON api.moorages_ext TO user_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow anonymous to select
CREATE POLICY api_anonymous_role ON api.moorages_ext TO api_anonymous
    USING (true)
    WITH CHECK (false);
-- Disallow vessel_role
CREATE POLICY api_vessel_role ON api.moorages_ext TO vessel_role
    USING (false)
    WITH CHECK (false);

-- Update version
UPDATE public.app_settings
	SET value='0.9.4'
	WHERE "name"='app.version';

\c postgres