---------------------------------------------------------------------------
-- PostgSail => Postgres + TimescaleDB + PostGIS + PostgREST
-- 
-- Inspired from:
-- https://groups.google.com/g/signalk/c/W2H15ODCic4
--
-- Description:
-- Insert data into table metadata from API using PostgREST
-- Insert data into table metrics from API using PostgREST
-- TimescaleDB Hypertable to store signalk metrics
-- pgsql functions to generate logbook, stays, moorages
-- CRON functions to process logbook, stays, moorages
-- python functions for geo reverse and send notification via email and/or pushover
-- Views statistics, timelapse, monitoring, logs
-- Always store time in UTC
---------------------------------------------------------------------------

-- vessels signalk -(POST)-> metadata -> metadata_upsert -(trigger)-> metadata_upsert_trigger_fn (INSERT or UPDATE)
-- vessels signalk -(POST)-> metrics -> metrics -(trigger)-> metrics_fn new log,stay,moorage

---------------------------------------------------------------------------

-- Drop database
-- % docker exec -i timescaledb-postgis psql -Uusername -W postgres -c "drop database signalk;"

-- Import Schema
-- % cat signalk.sql | docker exec -i timescaledb-postgis psql -Uusername postgres

-- Export hypertable
-- % docker exec -i timescaledb-postgis psql -Uusername -W signalk -c "\COPY (SELECT * FROM api.metrics ORDER BY time ASC) TO '/var/lib/postgresql/data/metrics.csv' DELIMITER ',' CSV"
-- Export hypertable to gzip
-- # docker exec -i timescaledb-postgis psql -Uusername -W signalk -c "\COPY (SELECT * FROM api.metrics ORDER BY time ASC) TO PROGRAM 'gzip > /var/lib/postgresql/data/metrics.csv.gz' CSV HEADER;"

DO $$
BEGIN
RAISE WARNING '
  _________.__                     .__   ____  __.
 /   _____/|__| ____   ____ _____  |  | |    |/ _|
 \_____  \ |  |/ ___\ /    \\__  \ |  | |      <  
 /        \|  / /_/  >   |  \/ __ \|  |_|    |  \ 
/_______  /|__\___  /|___|  (____  /____/____|__ \
        \/   /_____/      \/     \/             \/
 %', now();
END $$;

select version();

-- Database
CREATE DATABASE signalk;
-- Limit connection to 100
ALTER DATABASE signalk WITH CONNECTION LIMIT = 100;
-- Set timezone to UTC
ALTER DATABASE signalk SET TIMEZONE='UTC';

-- connect to the DB
\c signalk

-- Schema
CREATE SCHEMA IF NOT EXISTS api;
COMMENT ON SCHEMA api IS 'api schema expose to postgrest';

-- Revoke default privileges to all public functions
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Extensions
CREATE EXTENSION IF NOT EXISTS timescaledb; -- provides time series functions for PostgreSQL
-- CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit; -- provides time series functions for PostgreSQL
CREATE EXTENSION IF NOT EXISTS postgis; -- adds support for geographic objects to the PostgreSQL object-relational database
CREATE EXTENSION IF NOT EXISTS plpgsql; -- PL/pgSQL procedural language
CREATE EXTENSION IF NOT EXISTS plpython3u; -- implements PL/Python based on the Python 3 language variant.
CREATE EXTENSION IF NOT EXISTS jsonb_plpython3u CASCADE; -- tranform jsonb to python json type.
CREATE EXTENSION IF NOT EXISTS pg_stat_statements; -- provides a means for tracking planning and execution statistics of all SQL statements executed
CREATE EXTENSION IF NOT EXISTS "moddatetime"; -- provides functions for tracking last modification time

-- Trust plpython3u language by default
UPDATE pg_language SET lanpltrusted = true WHERE lanname = 'plpython3u';

---------------------------------------------------------------------------
-- Tables
--
---------------------------------------------------------------------------
-- Metadata from signalk
CREATE TABLE IF NOT EXISTS api.metadata(
  id SERIAL PRIMARY KEY,
  name VARCHAR(150) NULL,
  mmsi NUMERIC NULL,
  client_id VARCHAR(255) UNIQUE NOT NULL,
  length DOUBLE PRECISION NULL,
  beam DOUBLE PRECISION NULL,
  height DOUBLE PRECISION NULL,
  ship_type NUMERIC NULL,
  plugin_version VARCHAR(10) NOT NULL,
  signalk_version VARCHAR(10) NOT NULL,
  time TIMESTAMP WITHOUT TIME ZONE NOT NULL, -- should be rename to last_update !?
  active BOOLEAN DEFAULT True, -- trigger monitor online/offline
  -- vessel_id link auth.vessels with api.metadata
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);
-- Description
COMMENT ON TABLE
    api.metadata
    IS 'Stores metadata from vessel';
COMMENT ON COLUMN api.metadata.active IS 'trigger monitor online/offline';
-- Index
CREATE INDEX metadata_client_id_idx ON api.metadata (client_id);
CREATE INDEX metadata_mmsi_idx ON api.metadata (mmsi);
CREATE INDEX metadata_name_idx ON api.metadata (name);

---------------------------------------------------------------------------
-- Metrics from signalk
-- Create vessel status enum
CREATE TYPE status AS ENUM ('sailing', 'motoring', 'moored', 'anchored');
-- Table api.metrics
CREATE TABLE IF NOT EXISTS api.metrics (
  time TIMESTAMP WITHOUT TIME ZONE NOT NULL,
  client_id VARCHAR(255) NOT NULL REFERENCES api.metadata(client_id) ON DELETE RESTRICT,
  latitude DOUBLE PRECISION NULL,
  longitude DOUBLE PRECISION NULL,
  speedOverGround DOUBLE PRECISION NULL,
  courseOverGroundTrue DOUBLE PRECISION NULL,
  windSpeedApparent DOUBLE PRECISION NULL,
  angleSpeedApparent DOUBLE PRECISION NULL,
  status status NULL,
  metrics jsonb NULL,
  CONSTRAINT valid_client_id CHECK (length(client_id) > 10),
  CONSTRAINT valid_latitude CHECK (latitude >= -90 and latitude <= 90),
  CONSTRAINT valid_longitude CHECK (longitude >= -180 and longitude <= 180)
);
-- Description
COMMENT ON TABLE
    api.metrics
    IS 'Stores metrics from vessel';
COMMENT ON COLUMN api.metrics.latitude IS 'With CONSTRAINT but allow NULL value to be ignored silently by trigger';
COMMENT ON COLUMN api.metrics.longitude IS 'With CONSTRAINT but allow NULL value to be ignored silently by trigger';

-- Index
CREATE INDEX ON api.metrics (client_id, time DESC);
CREATE INDEX ON api.metrics (status, time DESC);
-- json index??
CREATE INDEX ON api.metrics using GIN (metrics);
-- timescaledb hypertable
--SELECT create_hypertable('api.metrics', 'time');
-- timescaledb hypertable with space partitions
SELECT create_hypertable('api.metrics', 'time', 'client_id',
    number_partitions => 2,
    chunk_time_interval => INTERVAL '7 day',
    if_not_exists => true);

---------------------------------------------------------------------------
-- Logbook
-- todo add clientid ref
-- todo add cosumption fuel?
-- todo add engine hour?
-- todo add geom object http://epsg.io/4326 EPSG:4326 Unit: degres
-- todo add geog object http://epsg.io/3857 EPSG:3857 Unit: meters
-- https://postgis.net/workshops/postgis-intro/geography.html#using-geography
-- https://medium.com/coord/postgis-performance-showdown-geometry-vs-geography-ec99967da4f0
-- virtual logbook by boat by client_id impossible? 
-- https://www.postgresql.org/docs/current/ddl-partitioning.html
-- Issue:
-- https://www.reddit.com/r/PostgreSQL/comments/di5mbr/postgresql_12_foreign_keys_and_partitioned_tables/f3tsoop/
CREATE TABLE IF NOT EXISTS api.logbook(
  id SERIAL PRIMARY KEY,
  client_id VARCHAR(255) NOT NULL REFERENCES api.metadata(client_id) ON DELETE RESTRICT,
--  client_id VARCHAR(255) NOT NULL,
  active BOOLEAN DEFAULT false,
  name VARCHAR(255),
  _from VARCHAR(255),
  _from_lat DOUBLE PRECISION NULL,
  _from_lng DOUBLE PRECISION NULL,
  _to VARCHAR(255),
  _to_lat DOUBLE PRECISION NULL,
  _to_lng DOUBLE PRECISION NULL,
  --track_geom Geometry(LINESTRING)
  track_geom geometry(LINESTRING,4326) NULL,
  track_geog geography(LINESTRING) NULL,
  track_geojson JSON NULL,
--  track_gpx XML NULL,
  _from_time TIMESTAMP WITHOUT TIME ZONE NOT NULL,
  _to_time TIMESTAMP WITHOUT TIME ZONE NULL,
  distance NUMERIC, -- meters?
  duration INTERVAL, -- duration in days and hours?
  avg_speed DOUBLE PRECISION NULL,
  max_speed DOUBLE PRECISION NULL,
  max_wind_speed DOUBLE PRECISION NULL,
  notes TEXT NULL
);
-- Description
COMMENT ON TABLE
    api.logbook
    IS 'Stores generated logbook';
COMMENT ON COLUMN api.logbook.distance IS 'in NM';

-- Index todo!
CREATE INDEX logbook_client_id_idx ON api.logbook (client_id);
CREATE INDEX ON api.logbook USING GIST ( track_geom );
COMMENT ON COLUMN api.logbook.track_geom IS 'postgis geometry type EPSG:4326 Unit: degres';
CREATE INDEX ON api.logbook USING GIST ( track_geog );
COMMENT ON COLUMN api.logbook.track_geog IS 'postgis geography type default SRID 4326 Unit: degres';
-- Otherwise -- ERROR:  Only lon/lat coordinate systems are supported in geography.
COMMENT ON COLUMN api.logbook.track_geojson IS 'store the geojson track metrics data, can not depend api.metrics table, should be generate from linetring to save disk space?';
--COMMENT ON COLUMN api.logbook.track_gpx IS 'store the gpx track metrics data, can not depend api.metrics table, should be generate from linetring to save disk space?';

---------------------------------------------------------------------------
-- Stays
-- todo add clientid ref
-- todo add FOREIGN KEY?
-- virtual logbook by boat? 
CREATE TABLE IF NOT EXISTS api.stays(
  id SERIAL PRIMARY KEY,
  client_id VARCHAR(255) NOT NULL REFERENCES api.metadata(client_id) ON DELETE RESTRICT,
--  client_id VARCHAR(255) NOT NULL,
  active BOOLEAN DEFAULT false,
  name VARCHAR(255),
  latitude DOUBLE PRECISION NULL,
  longitude DOUBLE PRECISION NULL,
  geog GEOGRAPHY(POINT) NULL,
  arrived TIMESTAMP WITHOUT TIME ZONE NOT NULL,
  departed TIMESTAMP WITHOUT TIME ZONE,
  duration INTERVAL, -- duration in days and hours?
  stay_code INT DEFAULT 1, -- REFERENCES api.stays_at(stay_code),
  notes TEXT NULL
);
-- Description
COMMENT ON TABLE
    api.stays
    IS 'Stores generated stays';

-- Index
CREATE INDEX stays_client_id_idx ON api.stays (client_id);
CREATE INDEX ON api.stays USING GIST ( geog );
COMMENT ON COLUMN api.stays.geog IS 'postgis geography type default SRID 4326 Unit: degres';
-- With other SRID ERROR: Only lon/lat coordinate systems are supported in geography.

---------------------------------------------------------------------------
-- Moorages
-- todo add clientid ref
-- virtual logbook by boat? 
CREATE TABLE IF NOT EXISTS api.moorages(
  id SERIAL PRIMARY KEY,
  client_id VARCHAR(255) NOT NULL REFERENCES api.metadata(client_id) ON DELETE RESTRICT,
--  client_id VARCHAR(255) NOT NULL,
  name VARCHAR(255),
  country VARCHAR(255), -- todo need to update reverse_geocode_py_fn
  stay_id INT NOT NULL, -- needed?
  stay_code INT DEFAULT 1, -- needed?  REFERENCES api.stays_at(stay_code)
  stay_duration INTERVAL NULL,
  reference_count INT DEFAULT 1,
  latitude DOUBLE PRECISION NULL,
  longitude DOUBLE PRECISION NULL,
  geog GEOGRAPHY(POINT) NULL,
  home_flag BOOLEAN DEFAULT false,
  notes TEXT NULL
);
-- Description
COMMENT ON TABLE
    api.moorages
    IS 'Stores generated moorages';

-- Index
CREATE INDEX moorages_client_id_idx ON api.moorages (client_id);
CREATE INDEX ON api.moorages USING GIST ( geog );
COMMENT ON COLUMN api.moorages.geog IS 'postgis geography type default SRID 4326 Unit: degres';
-- With other SRID ERROR: Only lon/lat coordinate systems are supported in geography.

---------------------------------------------------------------------------
-- Stay Type
CREATE TABLE IF NOT EXISTS api.stays_at(
  stay_code   INTEGER NOT NULL,
  description TEXT NOT NULL
);
-- Description
COMMENT ON TABLE api.stays_at IS 'Stay Type';
-- Insert default possible values
INSERT INTO api.stays_at(stay_code, description) VALUES
  (1, 'Unknow'),
  (2, 'Anchor'),
  (3, 'Mooring Buoy'),
  (4, 'Dock');

---------------------------------------------------------------------------
-- Trigger Functions Metadata table
--
-- UPSERT - Insert vs Update for Metadata
DROP FUNCTION IF EXISTS metadata_upsert_trigger_fn; 
CREATE FUNCTION metadata_upsert_trigger_fn() RETURNS trigger AS $metadata_upsert$
    DECLARE
        metadata_id integer;
        metadata_active boolean;
    BEGIN
        -- Set client_id to new value to allow RLS
        PERFORM set_config('vessel.client_id', NEW.client_id, false);
        -- UPSERT - Insert vs Update for Metadata
        RAISE NOTICE 'metadata_upsert_trigger_fn';
        SELECT m.id,m.active INTO metadata_id, metadata_active
            FROM api.metadata m
            WHERE (m.vessel_id IS NOT NULL AND m.vessel_id = current_setting('vessel.id', true))
                    OR (m.client_id IS NOT NULL AND m.client_id = NEW.client_id);
        RAISE NOTICE 'metadata_id %', metadata_id;
        IF metadata_id IS NOT NULL THEN
            -- send notifitacion if boat is back online
            IF metadata_active is False THEN
                -- Add monitor online entry to process queue for later notification
                INSERT INTO process_queue (channel, payload, stored) 
                    VALUES ('monitoring_online', metadata_id, now());
            END IF;
            -- Update vessel metadata
            UPDATE api.metadata
                SET
                    name = NEW.name,
                    mmsi = NEW.mmsi,
                    client_id = NEW.client_id,
                    length = NEW.length,
                    beam = NEW.beam,
                    height = NEW.height,
                    ship_type = NEW.ship_type,
                    plugin_version = NEW.plugin_version,
                    signalk_version = NEW.signalk_version,
                    time = NEW.time,
                    active = true
                WHERE id = metadata_id;
            RETURN NULL; -- Ignore insert
        ELSE
            IF NEW.vessel_id IS NULL THEN
                -- set vessel_id from jwt if not present in INSERT query
                NEW.vessel_id = current_setting('vessel.id');
            END IF;
            -- Insert new vessel metadata and
            RETURN NEW; -- Insert new vessel metadata
        END IF;
    END;
$metadata_upsert$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.metadata_upsert_trigger_fn
    IS 'process metadata from vessel, upsert';

CREATE TRIGGER metadata_moddatetime
	BEFORE UPDATE ON api.metadata
	FOR EACH ROW
	EXECUTE PROCEDURE moddatetime (updated_at);
-- Description
COMMENT ON TRIGGER metadata_moddatetime
  ON api.metadata
  IS 'Automatic update of updated_at on table modification';

-- FUNCTION Metadata notification for new vessel after insert
DROP FUNCTION IF EXISTS metadata_notification_trigger_fn; 
CREATE FUNCTION metadata_notification_trigger_fn() RETURNS trigger AS $metadata_notification$
    DECLARE
    BEGIN
        RAISE NOTICE 'metadata_notification_trigger_fn';
        INSERT INTO process_queue (channel, payload, stored) 
            VALUES ('monitoring_online', NEW.id, now());
        RETURN NULL;
    END;
$metadata_notification$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.metadata_notification_trigger_fn
    IS 'process metadata notification from vessel, monitoring_online';

---------------------------------------------------------------------------
-- Trigger metadata table
--
-- Metadata trigger BEFORE INSERT
CREATE TRIGGER metadata_upsert_trigger BEFORE INSERT ON api.metadata
    FOR EACH ROW EXECUTE FUNCTION metadata_upsert_trigger_fn();
-- Description
COMMENT ON TRIGGER
    metadata_upsert_trigger ON api.metadata
    IS 'BEFORE INSERT ON api.metadata run function metadata_upsert_trigger_fn';

-- Metadata trigger AFTER INSERT
CREATE TRIGGER metadata_notification_trigger AFTER INSERT ON api.metadata
    FOR EACH ROW EXECUTE FUNCTION metadata_notification_trigger_fn();
-- Description
COMMENT ON TRIGGER 
    metadata_notification_trigger ON api.metadata 
    IS 'AFTER INSERT ON api.metadata run function metadata_update_trigger_fn for notification on new vessel';

---------------------------------------------------------------------------
-- Trigger Functions metrics table
--
-- Create a logbook or stay entry base on the vessel state, eg: navigation.state
-- https://github.com/meri-imperiumi/signalk-autostate

DROP FUNCTION IF EXISTS metrics_trigger_fn;
CREATE FUNCTION metrics_trigger_fn() RETURNS trigger AS $metrics$
    DECLARE
        previous_status varchar;
        previous_time TIMESTAMP WITHOUT TIME ZONE;
        stay_code integer;
        logbook_id integer;
        stay_id integer;
        valid_status BOOLEAN;
    BEGIN
        -- Set client_id to new value to allow RLS
        PERFORM set_config('vessel.client_id', NEW.client_id, false);
        --RAISE NOTICE 'metrics_trigger_fn client_id [%]', NEW.client_id;
        -- Boat metadata are check using api.metrics REFERENCES to api.metadata
        -- Fetch the latest entry to compare status against the new status to be insert
        SELECT coalesce(m.status, 'moored'), m.time INTO previous_status, previous_time
            FROM api.metrics m 
            WHERE m.client_id IS NOT NULL
                AND m.client_id = NEW.client_id
            ORDER BY m.time DESC LIMIT 1;
        --RAISE NOTICE 'Metrics Status, New:[%] Previous:[%]', NEW.status, previous_status;
        IF previous_time = NEW.time THEN
            -- Ignore entry if same time
            RAISE WARNING 'Metrics Ignoring metric, duplicate time [%] = [%]', previous_time, NEW.time;
            RETURN NULL;
        END IF;
        IF previous_time > NEW.time THEN
            -- Ignore entry if new time is later than previous time
            RAISE WARNING 'Metrics Ignoring metric, new time is older [%] > [%]', previous_time, NEW.time;
            RETURN NULL;
        END IF;
        -- Check if latitude or longitude are null
        IF NEW.latitude IS NULL OR NEW.longitude IS NULL THEN
            -- Ignore entry if null latitude,longitude
            RAISE WARNING 'Metrics Ignoring metric, null latitude,longitude [%] [%]', NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        -- Check if status is null
        IF NEW.status IS NULL THEN
            RAISE WARNING 'Metrics Unknow NEW.status from vessel [%], set to default moored', NEW.status;
            NEW.status := 'moored';
        END IF;
        IF previous_status IS NULL THEN
            IF NEW.status = 'anchored' THEN
                RAISE WARNING 'Metrics Unknow previous_status from vessel [%], set to default current status [%]', previous_status, NEW.status;
                previous_status := NEW.status;
            ELSE
                RAISE WARNING 'Metrics Unknow previous_status from vessel [%], set to default status moored vs [%]', previous_status, NEW.status;
                previous_status := 'moored';
            END IF;
            -- Add new stay as no previous entry exist
            INSERT INTO api.stays 
                (client_id, active, arrived, latitude, longitude, stay_code) 
                VALUES (NEW.client_id, true, NEW.time, NEW.latitude, NEW.longitude, 1)
                RETURNING id INTO stay_id;
            -- Add stay entry to process queue for further processing
            INSERT INTO process_queue (channel, payload, stored)
                VALUES ('new_stay', stay_id, now());
            RAISE WARNING 'Metrics Insert first stay as no previous metrics exist, stay_id %', stay_id;
        END IF;
        -- Check if status is valid enum
        SELECT NEW.status::name = any(enum_range(null::status)::name[]) INTO valid_status;
        IF valid_status IS False THEN
            -- Ignore entry if status is invalid
            RAISE WARNING 'Metrics Ignoring metric, invalid status [%]', NEW.status;
            RETURN NULL;
        END IF;

        -- Check the state and if any previous/current entry
        -- If new status is sailing or motoring
        IF previous_status::TEXT <> NEW.status::TEXT AND
            ( (NEW.status::TEXT = 'sailing' AND previous_status::TEXT <> 'motoring')
             OR (NEW.status::TEXT = 'motoring' AND previous_status::TEXT <> 'sailing') ) THEN
            RAISE WARNING 'Metrics Update status, try new logbook, New:[%] Previous:[%]', NEW.status, previous_status;
            -- Start new log
            logbook_id := public.trip_in_progress_fn(NEW.client_id::TEXT);
            IF logbook_id IS NULL THEN
                INSERT INTO api.logbook
                    (client_id, active, _from_time, _from_lat, _from_lng)
                    VALUES (NEW.client_id, true, NEW.time, NEW.latitude, NEW.longitude)
                    RETURNING id INTO logbook_id;
                RAISE WARNING 'Metrics Insert new logbook, logbook_id %', logbook_id;
            ELSE
                UPDATE api.logbook
                    SET
                        active = false,
                        _to_time = NEW.time,
                        _to_lat = NEW.latitude,
                        _to_lng = NEW.longitude
                    WHERE id = logbook_id;
                RAISE WARNING 'Metrics Existing Logbook logbook_id [%] [%] [%]', logbook_id, NEW.status, NEW.time;
            END IF;

            -- End current stay
            stay_id := public.stay_in_progress_fn(NEW.client_id::TEXT);
            IF stay_id IS NOT NULL THEN
                UPDATE api.stays
                    SET
                        active = false,
                        departed = NEW.time
                    WHERE id = stay_id;
                RAISE WARNING 'Metrics Updating Stay end current stay_id [%] [%] [%]', stay_id, NEW.status, NEW.time;
                -- Add moorage entry to process queue for further processing
                INSERT INTO process_queue (channel, payload, stored)
                    VALUES ('new_moorage', stay_id, now());
            ELSE
                RAISE WARNING 'Metrics Invalid stay_id [%] [%]', stay_id, NEW.time;
            END IF;

        -- If new status is moored or anchored
        ELSIF previous_status::TEXT <> NEW.status::TEXT AND
            ( (NEW.status::TEXT = 'moored' AND previous_status::TEXT <> 'anchored')
             OR (NEW.status::TEXT = 'anchored' AND previous_status::TEXT <> 'moored') ) THEN
            -- Start new stays
            RAISE WARNING 'Metrics Update status, try new stay, New:[%] Previous:[%]', NEW.status, previous_status;
            stay_id := public.stay_in_progress_fn(NEW.client_id::TEXT);
            IF stay_id IS NULL THEN
                RAISE WARNING 'Metrics Inserting new stay [%]', NEW.status;
                -- If metric status is anchored set stay_code accordingly
                stay_code = 1;
                IF NEW.status = 'anchored' THEN
                    stay_code = 2;
                END IF;
                -- Add new stay
                INSERT INTO api.stays
                    (client_id, active, arrived, latitude, longitude, stay_code)
                    VALUES (NEW.client_id, true, NEW.time, NEW.latitude, NEW.longitude, stay_code)
                    RETURNING id INTO stay_id;
                -- Add stay entry to process queue for further processing
                INSERT INTO process_queue (channel, payload, stored)
                    VALUES ('new_stay', stay_id, now());
            ELSE
                RAISE WARNING 'Metrics Invalid stay_id [%] [%]', stay_id, NEW.time;
                UPDATE api.stays
                    SET
                        active = false,
                        departed = NEW.time
                    WHERE id = stay_id;
            END IF;

            -- End current log/trip
            -- Fetch logbook_id by client_id
            logbook_id := public.trip_in_progress_fn(NEW.client_id::TEXT);
            IF logbook_id IS NOT NULL THEN
                -- todo check on time start vs end
                RAISE WARNING 'Metrics Updating logbook status [%] [%] [%]', logbook_id, NEW.status, NEW.time;
                UPDATE api.logbook 
                    SET 
                        active = false, 
                        _to_time = NEW.time,
                        _to_lat = NEW.latitude,
                        _to_lng = NEW.longitude
                    WHERE id = logbook_id;
                -- Add logbook entry to process queue for later processing
                INSERT INTO process_queue (channel, payload, stored)
                    VALUEs ('new_logbook', logbook_id, now());
            ELSE
                RAISE WARNING 'Metrics Invalid logbook_id [%] [%]', logbook_id, NEW.time;
            END IF;
        END IF;
        RETURN NEW; -- Finally insert the actual new metric
    END;
$metrics$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.metrics_trigger_fn
    IS 'process metrics from vessel, generate new_logbook and new_stay';

--
-- Triggers logbook update on metrics insert
CREATE TRIGGER metrics_trigger BEFORE INSERT ON api.metrics
    FOR EACH ROW EXECUTE FUNCTION metrics_trigger_fn();
-- Description
COMMENT ON TRIGGER 
    metrics_trigger ON api.metrics 
    IS  'BEFORE INSERT ON api.metrics run function metrics_trigger_fn';

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
                    AND id <= end_log;
            --raise WARNING 'by log _geojson %' , _geojson;
        ELSIF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            SELECT jsonb_agg(track_geojson->'features') INTO _geojson
                FROM api.logbook
                WHERE _from_time >= start_log::TIMESTAMP WITHOUT TIME ZONE
                    AND _to_time <= end_date::TIMESTAMP WITHOUT TIME ZONE + interval '23 hours 59 minutes';
            --raise WARNING 'by date _geojson %' , _geojson;
        ELSE
            SELECT jsonb_agg(track_geojson->'features') INTO _geojson
                FROM api.logbook;
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
        IF logbook_rec.client_id IS NULL THEN
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
CREATE OR REPLACE FUNCTION api.export_logbook_gpx_fn(IN _id INTEGER) RETURNS pg_catalog.xml
AS $export_logbook_gpx$
    DECLARE
        log_rec record;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> export_logbook_geojson_fn invalid input %', _id;
            RETURN '';
        END IF;
        -- Gather log details _from_time and _to_time
        SELECT * INTO log_rec
            FROM
            api.logbook l
            WHERE l.id = _id;
        -- Ensure the query is successful
        IF log_rec.client_id IS NULL THEN
            RAISE WARNING '-> export_logbook_gpx_fn invalid logbook %', _id;
            RETURN '';
        END IF;
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
                xmlelement(name trk,
                    xmlelement(name name, log_rec.name),
                    xmlelement(name desc, log_rec.notes),
                    xmlelement(name link, xmlattributes(concat('https://iot.openplotter.cloud/log/', log_rec.id) as href),
                                                xmlelement(name text, log_rec.name)),
                    xmlelement(name extensions, xmlelement(name "postgsail:log_id", 1),
                                                xmlelement(name "postgsail:link", concat('https://iot.openplotter.cloud/log/', log_rec.id)),
                                                xmlelement(name "opencpn:guid", uuid_generate_v4()),
                                                xmlelement(name "opencpn:viz", '1'),
                                                xmlelement(name "opencpn:start", log_rec._from_time),
                                                xmlelement(name "opencpn:end", log_rec._to_time)
                                                ),
                    xmlelement(name trkseg, xmlagg(
                                                xmlelement(name trkpt,
                                                    xmlattributes(latitude as lat, longitude as lon),
                                                        xmlelement(name time, time)
                                                )))))::pg_catalog.xml
            FROM api.metrics m
            WHERE m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.time >= log_rec._from_time::TIMESTAMP WITHOUT TIME ZONE
                AND m.time <= log_rec._to_time::TIMESTAMP WITHOUT TIME ZONE
                AND client_id = log_rec.client_id;
            -- ERROR:  column "m.time" must appear in the GROUP BY clause or be used in an aggregate function at character 2304
            --ORDER BY m.time ASC;
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
CREATE FUNCTION public.trip_in_progress_fn(IN _client_id TEXT) RETURNS INT AS $trip_in_progress$
    DECLARE
        logbook_id INT := NULL;
    BEGIN
        SELECT id INTO logbook_id
            FROM api.logbook l
            WHERE l.client_id IS NOT NULL
                AND l.client_id = _client_id
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
CREATE FUNCTION public.stay_in_progress_fn(IN _client_id TEXT) RETURNS INT AS $stay_in_progress$
    DECLARE
        stay_id INT := NULL;
    BEGIN
        SELECT id INTO stay_id
                FROM api.stays s
                WHERE s.client_id IS NOT NULL
                    AND s.client_id = _client_id
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
            FROM api.moorages m;
    END;
$export_moorages_gpx$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    api.export_moorages_gpx_fn
    IS 'Export moorages as gpx';

---------------------------------------------------------------------------
-- API helper views
--
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Views
-- Views are invoked with the privileges of the view owner,
-- make the user_role the view’s owner.
---------------------------------------------------------------------------

CREATE VIEW first_metric AS
    SELECT * 
        FROM api.metrics
        ORDER BY time ASC LIMIT 1;

CREATE VIEW last_metric AS
    SELECT * 
        FROM api.metrics
        ORDER BY time DESC LIMIT 1;

CREATE VIEW trip_in_progress AS
    SELECT * 
        FROM api.logbook 
        WHERE active IS true;

CREATE VIEW stay_in_progress AS
    SELECT * 
        FROM api.stays 
        WHERE active IS true;

-- list all json keys from api.metrics.metric jsonb
--select m.time,jsonb_object_keys(m.metrics) from last_metric m where m.client_id = 'vessels.urn:mrn:imo:mmsi:787654321';

-- TODO: Use materialized views instead as it is not live data
-- Logs web view
DROP VIEW IF EXISTS api.logs_view;
CREATE OR REPLACE VIEW api.logs_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT id,
            name as "Name",
            _from as "From",
            _from_time as "Started",
            _to as "To",
            _to_time as "Ended",
            distance as "Distance",
            duration as "Duration"
        FROM api.logbook l
        WHERE _to_time IS NOT NULL
        ORDER BY _from_time DESC;
-- Description
COMMENT ON VIEW
    api.logs_view
    IS 'Logs web view';

-- Inital try of MATERIALIZED VIEW
CREATE MATERIALIZED VIEW api.logs_mat_view AS
    SELECT id,
            name as "Name",
            _from as "From",
            _from_time as "Started",
            _to as "To",
            _to_time as "Ended",
            distance as "Distance",
            duration as "Duration"
        FROM api.logbook l
        WHERE _to_time IS NOT NULL
        ORDER BY _from_time DESC;

DROP VIEW IF EXISTS api.log_view;
CREATE OR REPLACE VIEW api.log_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT id,
            name as "Name",
            _from as "From",
            _from_time as "Started",
            _to as "To",
            _to_time as "Ended",
            distance as "Distance",
            duration as "Duration",
            notes as "Notes",
            track_geojson as geojson,
            avg_speed as avg_speed,
            max_speed as max_speed,
            max_wind_speed as max_wind_speed
        FROM api.logbook l
        WHERE _to_time IS NOT NULL
        ORDER BY _from_time DESC;
-- Description
COMMENT ON VIEW
    api.logs_view
    IS 'Log web view';

-- Stays web view
-- TODO group by month
DROP VIEW IF EXISTS api.stays_view;
CREATE VIEW api.stays_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT s.id,
        concat(
            extract(DAYS FROM (s.departed-s.arrived)::interval),
            ' days',
            --DATE_TRUNC('day', s.departed-s.arrived),
            ' stay at ',
            s.name,
            ' in ',
            RTRIM(TO_CHAR(s.departed, 'Month')),
            ' ',
            TO_CHAR(s.departed, 'YYYY')
            ) as "name",
        s.name AS "moorage",
        m.id AS "moorage_id",
        (s.departed-s.arrived) AS "duration",
        sa.description AS "stayed_at",
        sa.stay_code AS "stayed_at_id",
        s.arrived AS "arrived",
        s.departed AS "departed",
        s.notes AS "notes"
    FROM api.stays s, api.stays_at sa, api.moorages m
    WHERE departed IS NOT NULL
        AND s.name IS NOT NULL
        AND s.stay_code = sa.stay_code
        AND s.id = m.stay_id
    ORDER BY s.arrived DESC;
-- Description
COMMENT ON VIEW
    api.stays_view
    IS 'Stays web view';

DROP VIEW IF EXISTS api.stay_view;
CREATE VIEW api.stay_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT s.id,
        concat(
            extract(DAYS FROM (s.departed-s.arrived)::interval),
            ' days',
            --DATE_TRUNC('day', s.departed-s.arrived),
            ' stay at ',
            s.name,
            ' in ',
            RTRIM(TO_CHAR(s.departed, 'Month')),
            ' ',
            TO_CHAR(s.departed, 'YYYY')
            ) as "name",
        s.name AS "moorage",
        m.id AS "moorage_id",
        (s.departed-s.arrived) AS "duration",
        sa.description AS "stayed_at",
        sa.stay_code AS "stayed_at_id",
        s.arrived AS "arrived",
        s.departed AS "departed",
        s.notes AS "notes"
    FROM api.stays s, api.stays_at sa, api.moorages m
    WHERE departed IS NOT NULL
        AND s.name IS NOT NULL
        AND s.stay_code = sa.stay_code
        AND s.id = m.stay_id
    ORDER BY s.arrived DESC;
-- Description
COMMENT ON VIEW
    api.stay_view
    IS 'Stay web view';

-- Moorages web view
-- TODO, this is wrong using distinct (m.name) should be using postgis geog feature
--DROP VIEW IF EXISTS api.moorages_view_old;
--CREATE VIEW api.moorages_view_old AS
--    SELECT
--        m.name AS Moorage,
--        sa.description AS "Default Stay",
--        sum((m.departed-m.arrived)) OVER (PARTITION by m.name) AS "Total Stay",
--        count(m.departed) OVER (PARTITION by m.name) AS "Arrivals & Departures"
--    FROM api.moorages m, api.stays_at sa
--    WHERE departed is not null 
--        AND m.name is not null
--        AND m.stay_code = sa.stay_code
--    GROUP BY m.name,sa.description,m.departed,m.arrived
--    ORDER BY 4 DESC;

-- the good way?
DROP VIEW IF EXISTS api.moorages_view;
CREATE OR REPLACE VIEW api.moorages_view WITH (security_invoker=true,security_barrier=true) AS -- TODO
    SELECT m.id,
        m.name AS Moorage,
        sa.description AS Default_Stay,
        sa.stay_code AS Default_Stay_Id,
        EXTRACT(DAY FROM justify_hours ( m.stay_duration )) AS Total_Stay, -- in days
        m.reference_count AS Arrivals_Departures
--        m.geog
--        m.stay_duration,
--        justify_hours ( m.stay_duration )
    FROM api.moorages m, api.stays_at sa
    WHERE m.name is not null
        AND m.stay_code = sa.stay_code
   GROUP BY m.id,m.name,sa.description,m.stay_duration,m.reference_count,m.geog,sa.stay_code
--   ORDER BY 4 DESC;
   ORDER BY m.reference_count DESC;
-- Description
COMMENT ON VIEW
    api.moorages_view
    IS 'Moorages listing web view';

DROP VIEW IF EXISTS api.moorage_view;
CREATE OR REPLACE VIEW api.moorage_view WITH (security_invoker=true,security_barrier=true) AS -- TODO
    SELECT id,
        m.name AS Name,
        m.stay_code AS Default_Stay,
        m.home_flag AS Home,
        EXTRACT(DAY FROM justify_hours ( m.stay_duration )) AS Total_Stay,
        m.reference_count AS Arrivals_Departures,
        m.notes
--        m.geog
    FROM api.moorages m
    WHERE m.name IS NOT NULL;
-- Description
COMMENT ON VIEW
    api.moorage_view
    IS 'Moorage details web view';

-- All moorage in 100 meters from the start of a logbook.
-- ST_DistanceSphere Returns minimum distance in meters between two lon/lat points.
--SELECT
--    m.name, ST_MakePoint(m._lng,m._lat),
--    l._from, ST_MakePoint(l._from_lng,l._from_lat),
--    ST_DistanceSphere(ST_MakePoint(m._lng,m._lat), ST_MakePoint(l._from_lng,l._from_lat))
--    FROM  api.moorages m , api.logbook l 
--    WHERE ST_DistanceSphere(ST_MakePoint(m._lng,m._lat), ST_MakePoint(l._from_lng,l._from_lat)) <= 100;

-- Stats web view
-- TODO....
-- first time entry from metrics
----> select * from api.metrics m ORDER BY m.time desc limit 1
-- last time entry from metrics
----> select * from api.metrics m ORDER BY m.time asc limit 1
-- max speed from logbook
-- max wind speed from logbook
----> select max(l.max_speed) as max_speed, max(l.max_wind_speed) as max_wind_speed from api.logbook l;
-- Total Distance from logbook
----> select sum(l.distance) as "Total Distance" from api.logbook l;
-- Total Time Underway from logbook
----> select sum(l.duration) as "Total Time Underway" from api.logbook l;
-- Longest Nonstop Sail from logbook, eg longest trip duration and distance
----> select max(l.duration),max(l.distance) from api.logbook l;
CREATE VIEW api.stats_logs_view WITH (security_invoker=true,security_barrier=true) AS -- TODO
    WITH
        meta AS ( 
            SELECT m.name FROM api.metadata m ),
        last_metric AS ( 
            SELECT m.time FROM api.metrics m ORDER BY m.time DESC limit 1),
        first_metric AS (
            SELECT m.time FROM api.metrics m ORDER BY m.time ASC limit 1),
        logbook AS (
            SELECT
                count(*) AS "Number of Log Entries",
                max(l.max_speed) AS "Max Speed",
                max(l.max_wind_speed) AS "Max Wind Speed",
                sum(l.distance) AS "Total Distance",
                sum(l.duration) AS "Total Time Underway",
                concat( max(l.distance), ' NM, ', max(l.duration), ' hours') AS "Longest Nonstop Sail"
            FROM api.logbook l)
    SELECT
        m.name as Name,
        fm.time AS first,
        lm.time AS last,
        l.* 
    FROM first_metric fm, last_metric lm, logbook l, meta m;
COMMENT ON VIEW
    api.stats_logs_view
    IS 'Statistics Logs web view';

-- Home Ports / Unique Moorages
----> select count(*) as "Home Ports" from api.moorages m where home_flag is true;
-- Unique Moorages
----> select count(*) as "Home Ports" from api.moorages m;
-- Time Spent at Home Port(s)
----> select sum(m.stay_duration) as "Time Spent at Home Port(s)" from api.moorages m where home_flag is true;
-- OR
----> select m.stay_duration as "Time Spent at Home Port(s)" from api.moorages m where home_flag is true;
-- Time Spent Away
----> select sum(m.stay_duration) as "Time Spent Away" from api.moorages m where home_flag is false;
-- Time Spent Away order by, group by stay_code (Dock, Anchor, Mooring Buoys, Unclassified)
----> select sa.description,sum(m.stay_duration) as "Time Spent Away" from api.moorages m, api.stays_at sa where home_flag is false AND m.stay_code = sa.stay_code group by m.stay_code,sa.description order by m.stay_code;
CREATE VIEW api.stats_moorages_view WITH (security_invoker=true,security_barrier=true) AS -- TODO
    WITH
        home_ports AS (
            select count(*) as home_ports from api.moorages m where home_flag is true
        ),
        unique_moorage AS (
            select count(*) as unique_moorage from api.moorages m
        ),
        time_at_home_ports AS (
            select sum(m.stay_duration) as time_at_home_ports from api.moorages m where home_flag is true
        ),
        time_spent_away AS (
            select sum(m.stay_duration) as time_spent_away from api.moorages m where home_flag is false
        )
    SELECT
        home_ports.home_ports as "Home Ports",
        unique_moorage.unique_moorage as "Unique Moorages",
        time_at_home_ports.time_at_home_ports "Time Spent at Home Port(s)",
        time_spent_away.time_spent_away as "Time Spent Away"
    FROM home_ports, unique_moorage, time_at_home_ports, time_spent_away;
COMMENT ON VIEW
    api.stats_moorages_view
    IS 'Statistics Moorages web view';

CREATE VIEW api.stats_moorages_away_view WITH (security_invoker=true,security_barrier=true) AS -- TODO
    SELECT sa.description,sum(m.stay_duration) as time_spent_away_by
    FROM api.moorages m, api.stays_at sa
    WHERE home_flag IS false
        AND m.stay_code = sa.stay_code
    GROUP BY m.stay_code,sa.description
    ORDER BY m.stay_code;
COMMENT ON VIEW
    api.stats_moorages_away_view
    IS 'Statistics Moorages Time Spent Away web view';

--CREATE VIEW api.stats_view AS -- todo
--    WITH
--        logs AS (
--            SELECT * FROM api.stats_logs_view ),
--        moorages AS (
--            SELECT * FROM api.stats_moorages_view)
--    SELECT
--        l.*,
--        m.*
--        FROM logs l, moorages m;
--COMMENT ON VIEW
--    api.stats_moorages_away_view
--    IS 'Statistics Moorages Time Spent Away web view';

-- View main monitoring for web app
CREATE VIEW api.monitoring_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT 
        time AS "time",
        (NOW() AT TIME ZONE 'UTC' - time) > INTERVAL '70 MINUTES' as offline,
        metrics-> 'environment.water.temperature' AS waterTemperature,
        metrics-> 'environment.inside.temperature' AS insideTemperature,
        metrics-> 'environment.outside.temperature' AS outsideTemperature,
        metrics-> 'environment.wind.speedOverGround' AS windSpeedOverGround,
        metrics-> 'environment.wind.directionGround' AS windDirectionGround,
        metrics-> 'environment.inside.humidity' AS insideHumidity,
        metrics-> 'environment.outside.humidity' AS outsideHumidity,
        metrics-> 'environment.outside.pressure' AS outsidePressure,
        metrics-> 'environment.inside.pressure' AS insidePressure,
        jsonb_build_object(
            'type', 'Feature',
            'geometry', ST_AsGeoJSON(st_makepoint(longitude,latitude))::jsonb,
            'properties', jsonb_build_object(
                'name', current_setting('vessel.name', false),
                'latitude', m.latitude,
                'longitude', m.longitude
                )::jsonb ) AS geojson,
        current_setting('vessel.name', false) AS name
    FROM api.metrics m 
    ORDER BY time DESC LIMIT 1;
COMMENT ON VIEW
    api.monitoring_view
    IS 'Monitoring web view';

CREATE VIEW api.monitoring_humidity AS
    SELECT 
        time AS "time",
        metrics-> 'environment.inside.humidity' AS insideHumidity,
        metrics-> 'environment.outside.humidity' AS outsideHumidity
    FROM api.metrics m 
    ORDER BY time DESC LIMIT 1;

-- View System RPI monitoring for grafana
-- View Electric monitoring for grafana

-- View main monitoring for grafana
-- LAST Monitoring data from json!
CREATE VIEW api.monitoring_temperatures AS
    SELECT 
        time AS "time",
        metrics-> 'environment.water.temperature' AS waterTemperature,
        metrics-> 'environment.inside.temperature' AS insideTemperature,
        metrics-> 'environment.outside.temperature' AS outsideTemperature
    FROM api.metrics m 
    ORDER BY time DESC LIMIT 1;

-- json key regexp
-- https://stackoverflow.com/questions/38204467/selecting-for-a-jsonb-array-contains-regex-match
-- Last voltage data from json!
CREATE VIEW api.monitoring_voltage AS
    SELECT
        time AS "time",
        cast(metrics-> 'electrical.batteries.AUX2.voltage' AS numeric) AS AUX2,
        cast(metrics-> 'electrical.batteries.House.voltage' AS numeric) AS House,
        cast(metrics-> 'environment.rpi.pijuice.gpioVoltage' AS numeric) AS gpioVoltage,
        cast(metrics-> 'electrical.batteries.Seatalk.voltage' AS numeric) AS SeatalkVoltage,
        cast(metrics-> 'electrical.batteries.Starter.voltage' AS numeric) AS StarterVoltage,
        cast(metrics-> 'environment.rpi.pijuice.batteryVoltage' AS numeric) AS RPIBatteryVoltage,
        cast(metrics-> 'electrical.batteries.victronDevice.voltage' AS numeric) AS victronDeviceVoltage
    FROM api.metrics m 
    ORDER BY time DESC LIMIT 1;

-- Infotiles web app
CREATE OR REPLACE VIEW api.total_info_view WITH (security_invoker=true,security_barrier=true) AS
-- Infotiles web app, not used calculated client side
    WITH
        l as (SELECT count(*) as logs FROM api.logbook),
        s as (SELECT count(*) as stays FROM api.stays),
        m as (SELECT count(*) as moorages FROM api.moorages)
        SELECT * FROM l,s,m;
COMMENT ON VIEW
    api.total_info_view
    IS 'Monitoring web view';

-- Badges
-- TODO View or function?