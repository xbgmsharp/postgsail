
-- connect to the DB
\c signalk

---------------------------------------------------------------------------
-- Tables
--
---------------------------------------------------------------------------
-- Metadata from signalk
CREATE TABLE IF NOT EXISTS api.metadata(
  id SERIAL PRIMARY KEY,
  name TEXT NULL,
  mmsi NUMERIC NULL,
  client_id TEXT NULL,
  -- vessel_id link auth.vessels with api.metadata
  vessel_id TEXT NOT NULL UNIQUE,
  length DOUBLE PRECISION NULL,
  beam DOUBLE PRECISION NULL,
  height DOUBLE PRECISION NULL,
  ship_type NUMERIC NULL,
  plugin_version TEXT NOT NULL,
  signalk_version TEXT NOT NULL,
  time TIMESTAMP WITHOUT TIME ZONE NOT NULL, -- should be rename to last_update !?
  active BOOLEAN DEFAULT True, -- trigger monitor online/offline
  created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);
-- Description
COMMENT ON TABLE
    api.metadata
    IS 'Stores metadata from vessel';
COMMENT ON COLUMN api.metadata.active IS 'trigger monitor online/offline';
-- Index
CREATE INDEX metadata_vessel_id_idx ON api.metadata (vessel_id);
--CREATE INDEX metadata_mmsi_idx ON api.metadata (mmsi);
-- is unused index ?
CREATE INDEX metadata_name_idx ON api.metadata (name);

---------------------------------------------------------------------------
-- Metrics from signalk
-- Create vessel status enum
CREATE TYPE status AS ENUM ('sailing', 'motoring', 'moored', 'anchored');
-- Table api.metrics
CREATE TABLE IF NOT EXISTS api.metrics (
  time TIMESTAMP WITHOUT TIME ZONE NOT NULL,
  --client_id VARCHAR(255) NOT NULL REFERENCES api.metadata(client_id) ON DELETE RESTRICT,
  client_id TEXT NULL,
  vessel_id TEXT NOT NULL REFERENCES api.metadata(vessel_id) ON DELETE RESTRICT,
  latitude DOUBLE PRECISION NULL,
  longitude DOUBLE PRECISION NULL,
  speedOverGround DOUBLE PRECISION NULL,
  courseOverGroundTrue DOUBLE PRECISION NULL,
  windSpeedApparent DOUBLE PRECISION NULL,
  angleSpeedApparent DOUBLE PRECISION NULL,
  status status NULL,
  metrics jsonb NULL,
  --CONSTRAINT valid_client_id CHECK (length(client_id) > 10),
  CONSTRAINT valid_latitude CHECK (latitude >= -90 and latitude <= 90),
  CONSTRAINT valid_longitude CHECK (longitude >= -180 and longitude <= 180),
  PRIMARY KEY (time, vessel_id)
);
-- Description
COMMENT ON TABLE
    api.metrics
    IS 'Stores metrics from vessel';
COMMENT ON COLUMN api.metrics.latitude IS 'With CONSTRAINT but allow NULL value to be ignored silently by trigger';
COMMENT ON COLUMN api.metrics.longitude IS 'With CONSTRAINT but allow NULL value to be ignored silently by trigger';

-- Index
CREATE INDEX ON api.metrics (vessel_id, time DESC);
CREATE INDEX ON api.metrics (status, time DESC);
-- json index??
CREATE INDEX ON api.metrics using GIN (metrics);
-- timescaledb hypertable
SELECT create_hypertable('api.metrics', 'time', chunk_time_interval => INTERVAL '7 day');
-- timescaledb hypertable with space partitions
-- ERROR:  new row for relation "_hyper_1_2_chunk" violates check constraint "constraint_4"
-- ((_timescaledb_internal.get_partition_hash(vessel_id) < 1073741823))
--SELECT create_hypertable('api.metrics', 'time', 'vessel_id',
--    number_partitions => 2,
--    chunk_time_interval => INTERVAL '7 day',
--    if_not_exists => true);

---------------------------------------------------------------------------
-- Logbook
-- todo add consumption fuel?
-- todo add engine hour?
-- todo add geom object http://epsg.io/4326 EPSG:4326 Unit: degres
-- todo add geog object http://epsg.io/3857 EPSG:3857 Unit: meters
-- https://postgis.net/workshops/postgis-intro/geography.html#using-geography
-- https://medium.com/coord/postgis-performance-showdown-geometry-vs-geography-ec99967da4f0
-- virtual logbook by boat by client_id impossible? 
-- https://www.postgresql.org/docs/current/ddl-partitioning.html
-- Issue:
-- https://www.reddit.com/r/PostgreSQL/comments/di5mbr/postgresql_12_foreign_keys_and_partitioned_tables/f3tsoop/
-- Check unused index

CREATE TABLE IF NOT EXISTS api.logbook(
  id SERIAL PRIMARY KEY,
  --client_id VARCHAR(255) NOT NULL REFERENCES api.metadata(client_id) ON DELETE RESTRICT,
  --client_id VARCHAR(255) NULL,
  vessel_id TEXT NOT NULL REFERENCES api.metadata(vessel_id) ON DELETE RESTRICT,
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
  track_gpx XML NULL,
  _from_time TIMESTAMP WITHOUT TIME ZONE NOT NULL,
  _to_time TIMESTAMP WITHOUT TIME ZONE NULL,
  distance NUMERIC, -- meters?
  duration INTERVAL, -- duration in days and hours?
  avg_speed DOUBLE PRECISION NULL,
  max_speed DOUBLE PRECISION NULL,
  max_wind_speed DOUBLE PRECISION NULL,
  notes TEXT NULL, -- remarks
  extra JSONB NULL -- other signalk metrics of interest
);
-- Description
COMMENT ON TABLE
    api.logbook
    IS 'Stores generated logbook';
COMMENT ON COLUMN api.logbook.distance IS 'in NM';
COMMENT ON COLUMN api.logbook.extra IS 'other metrics of interest, runTime, currentLevel, etc';

-- Index todo!
CREATE INDEX logbook_vessel_id_idx ON api.logbook (vessel_id);
CREATE INDEX ON api.logbook USING GIST ( track_geom );
COMMENT ON COLUMN api.logbook.track_geom IS 'postgis geometry type EPSG:4326 Unit: degres';
CREATE INDEX ON api.logbook USING GIST ( track_geog );
COMMENT ON COLUMN api.logbook.track_geog IS 'postgis geography type default SRID 4326 Unit: degres';
-- Otherwise -- ERROR:  Only lon/lat coordinate systems are supported in geography.
COMMENT ON COLUMN api.logbook.track_geojson IS 'store the geojson track metrics data, can not depend api.metrics table, should be generate from linetring to save disk space?';
COMMENT ON COLUMN api.logbook.track_gpx IS 'store the gpx track metrics data, can not depend api.metrics table, should be generate from linetring to save disk space?';

---------------------------------------------------------------------------
-- Stays
-- virtual logbook by boat? 
CREATE TABLE IF NOT EXISTS api.stays(
  id SERIAL PRIMARY KEY,
  --client_id VARCHAR(255) NOT NULL REFERENCES api.metadata(client_id) ON DELETE RESTRICT,
  --client_id VARCHAR(255) NULL,
  vessel_id TEXT NOT NULL REFERENCES api.metadata(vessel_id) ON DELETE RESTRICT,
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
CREATE INDEX stays_vessel_id_idx ON api.stays (vessel_id);
CREATE INDEX ON api.stays USING GIST ( geog );
COMMENT ON COLUMN api.stays.geog IS 'postgis geography type default SRID 4326 Unit: degres';
-- With other SRID ERROR: Only lon/lat coordinate systems are supported in geography.

---------------------------------------------------------------------------
-- Moorages
-- virtual logbook by boat? 
CREATE TABLE IF NOT EXISTS api.moorages(
  id SERIAL PRIMARY KEY,
  --client_id VARCHAR(255) NOT NULL REFERENCES api.metadata(client_id) ON DELETE RESTRICT,
  --client_id VARCHAR(255) NULL,
  vessel_id TEXT NOT NULL REFERENCES api.metadata(vessel_id) ON DELETE RESTRICT,
  name TEXT,
  country TEXT, -- todo need to update reverse_geocode_py_fn
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
CREATE INDEX moorages_vessel_id_idx ON api.moorages (vessel_id);
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
                NEW.vessel_id := current_setting('vessel.id');
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
        RAISE NOTICE 'metadata_notification_trigger_fn [%]', NEW;
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('monitoring_online', NEW.id, now(), NEW.vessel_id);
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
        _vessel_id TEXT;
    BEGIN
        --RAISE NOTICE 'metrics_trigger_fn';
        --RAISE WARNING 'metrics_trigger_fn [%] [%]', current_setting('vessel.id', true), NEW;
        -- Ensure vessel.id to new value to allow RLS
        IF NEW.vessel_id IS NULL THEN
            -- set vessel_id from jwt if not present in INSERT query
            NEW.vessel_id := current_setting('vessel.id');
        END IF;
        -- Boat metadata are check using api.metrics REFERENCES to api.metadata
        -- Fetch the latest entry to compare status against the new status to be insert
        SELECT coalesce(m.status, 'moored'), m.time INTO previous_status, previous_time
            FROM api.metrics m 
            WHERE m.vessel_id IS NOT NULL
                AND m.vessel_id = current_setting('vessel.id', true)
            ORDER BY m.time DESC LIMIT 1;
        --RAISE NOTICE 'Metrics Status, New:[%] Previous:[%]', NEW.status, previous_status;
        IF previous_time = NEW.time THEN
            -- Ignore entry if same time
            RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], duplicate time [%] = [%]', NEW.vessel_id, previous_time, NEW.time;
            RETURN NULL;
        END IF;
        IF previous_time > NEW.time THEN
            -- Ignore entry if new time is later than previous time
            RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], new time is older [%] > [%]', NEW.vessel_id, previous_time, NEW.time;
            RETURN NULL;
        END IF;
        -- Check if latitude or longitude are null
        IF NEW.latitude IS NULL OR NEW.longitude IS NULL THEN
            -- Ignore entry if null latitude,longitude
            RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], null latitude,longitude [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        -- Check if status is null
        IF NEW.status IS NULL THEN
            RAISE WARNING 'Metrics Unknown NEW.status, vessel_id [%], null status, set to default moored from [%]', NEW.vessel_id, NEW.status;
            NEW.status := 'moored';
        END IF;
        IF previous_status IS NULL THEN
            IF NEW.status = 'anchored' THEN
                RAISE WARNING 'Metrics Unknown previous_status from vessel_id [%], [%] set to default current status [%]', NEW.vessel_id, previous_status, NEW.status;
                previous_status := NEW.status;
            ELSE
                RAISE WARNING 'Metrics Unknown previous_status from vessel_id [%], [%] set to default status moored vs [%]', NEW.vessel_id, previous_status, NEW.status;
                previous_status := 'moored';
            END IF;
            -- Add new stay as no previous entry exist
            INSERT INTO api.stays 
                (vessel_id, active, arrived, latitude, longitude, stay_code)
                VALUES (current_setting('vessel.id', true), true, NEW.time, NEW.latitude, NEW.longitude, 1)
                RETURNING id INTO stay_id;
            -- Add stay entry to process queue for further processing
            INSERT INTO process_queue (channel, payload, stored, ref_id)
                VALUES ('new_stay', stay_id, now(), current_setting('vessel.id', true));
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
        -- If change of state and new status is sailing or motoring
        IF previous_status::TEXT <> NEW.status::TEXT AND
            ( (NEW.status::TEXT = 'sailing' AND previous_status::TEXT <> 'motoring')
             OR (NEW.status::TEXT = 'motoring' AND previous_status::TEXT <> 'sailing') ) THEN
            RAISE WARNING 'Metrics Update status, try new logbook, New:[%] Previous:[%]', NEW.status, previous_status;
            -- Start new log
            logbook_id := public.trip_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF logbook_id IS NULL THEN
                INSERT INTO api.logbook
                    (vessel_id, active, _from_time, _from_lat, _from_lng)
                    VALUES (current_setting('vessel.id', true), true, NEW.time, NEW.latitude, NEW.longitude)
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
            stay_id := public.stay_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF stay_id IS NOT NULL THEN
                UPDATE api.stays
                    SET
                        active = false,
                        departed = NEW.time
                    WHERE id = stay_id;
                RAISE WARNING 'Metrics Updating Stay end current stay_id [%] [%] [%]', stay_id, NEW.status, NEW.time;
                -- Add moorage entry to process queue for further processing
                INSERT INTO process_queue (channel, payload, stored, ref_id)
                    VALUES ('new_moorage', stay_id, now(), current_setting('vessel.id', true));
            ELSE
                RAISE WARNING 'Metrics Invalid stay_id [%] [%]', stay_id, NEW.time;
            END IF;

        -- If change of state and new status is moored or anchored
        ELSIF previous_status::TEXT <> NEW.status::TEXT AND
            ( (NEW.status::TEXT = 'moored' AND previous_status::TEXT <> 'anchored')
             OR (NEW.status::TEXT = 'anchored' AND previous_status::TEXT <> 'moored') ) THEN
            -- Start new stays
            RAISE WARNING 'Metrics Update status, try new stay, New:[%] Previous:[%]', NEW.status, previous_status;
            stay_id := public.stay_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF stay_id IS NULL THEN
                RAISE WARNING 'Metrics Inserting new stay [%]', NEW.status;
                -- If metric status is anchored set stay_code accordingly
                stay_code = 1;
                IF NEW.status = 'anchored' THEN
                    stay_code = 2;
                END IF;
                -- Add new stay
                INSERT INTO api.stays
                    (vessel_id, active, arrived, latitude, longitude, stay_code)
                    VALUES (current_setting('vessel.id', true), true, NEW.time, NEW.latitude, NEW.longitude, stay_code)
                    RETURNING id INTO stay_id;
                -- Add stay entry to process queue for further processing
                INSERT INTO process_queue (channel, payload, stored, ref_id)
                    VALUES ('new_stay', stay_id, now(), current_setting('vessel.id', true));
            ELSE
                RAISE WARNING 'Metrics Invalid stay_id [%] [%]', stay_id, NEW.time;
                UPDATE api.stays
                    SET
                        active = false,
                        departed = NEW.time
                    WHERE id = stay_id;
            END IF;

            -- End current log/trip
            -- Fetch logbook_id by vessel_id
            logbook_id := public.trip_in_progress_fn(current_setting('vessel.id', true)::TEXT);
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
                INSERT INTO process_queue (channel, payload, stored, ref_id)
                    VALUEs ('new_logbook', logbook_id, now(), current_setting('vessel.id', true));
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
    IS 'process metrics from vessel, generate new_logbook and new_stay.';

--
-- Triggers logbook update on metrics insert
CREATE TRIGGER metrics_trigger BEFORE INSERT ON api.metrics
    FOR EACH ROW EXECUTE FUNCTION metrics_trigger_fn();
-- Description
COMMENT ON TRIGGER 
    metrics_trigger ON api.metrics 
    IS  'BEFORE INSERT ON api.metrics run function metrics_trigger_fn';
