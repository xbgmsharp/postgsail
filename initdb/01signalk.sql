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
