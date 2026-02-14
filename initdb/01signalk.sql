---------------------------------------------------------------------------
-- PostgSail => PostgreSQL + TimescaleDB + PostGIS + MobilityDB + PostgREST
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
---------------------------------------------------------------------------

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
-- Set datestyle output
ALTER DATABASE signalk SET datestyle TO "ISO, DMY";
-- Set intervalstyle output
ALTER DATABASE signalk SET intervalstyle TO 'iso_8601';
-- Set statement timeout to 5 minutes
ALTER DATABASE signalk SET statement_timeout = '5min';

-- connect to the DB
\c signalk

-- Revoke default privileges to all public functions
ALTER DEFAULT PRIVILEGES REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- Extensions
CREATE EXTENSION IF NOT EXISTS timescaledb; -- provides time series functions for PostgreSQL
CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit; -- provides more hyperfunctions, fully compatible with TimescaleDB for PostgreSQL
CREATE EXTENSION IF NOT EXISTS postgis; -- adds support for geographic objects to the PostgreSQL object-relational database
CREATE EXTENSION IF NOT EXISTS mobilitydb; -- provides job scheduling for PostgreSQL
CREATE EXTENSION IF NOT EXISTS plpgsql; -- PL/pgSQL procedural language
CREATE EXTENSION IF NOT EXISTS plpython3u; -- implements PL/Python based on the Python 3 language variant.
CREATE EXTENSION IF NOT EXISTS jsonb_plpython3u CASCADE; -- transform jsonb to python json type.
CREATE EXTENSION IF NOT EXISTS pg_stat_statements; -- provides a means for tracking planning and execution statistics of all SQL statements executed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; -- provides functions to generate universally unique identifiers (UUIDs)
CREATE EXTENSION IF NOT EXISTS moddatetime; -- provides functions for tracking last modification time
CREATE EXTENSION IF NOT EXISTS citext; -- provides data type for case-insensitive character strings
CREATE EXTENSION IF NOT EXISTS pgcrypto; -- provides cryptographic functions

-- Trust plpython3u language by default
UPDATE pg_language SET lanpltrusted = true WHERE lanname = 'plpython3u';

DO $$
BEGIN
RAISE WARNING '
  _____          _         _____       _ _ 
 |  __ \        | |       / ____|     (_) |
 | |__) |__  ___| |_ __ _| (___   __ _ _| |
 |  ___/ _ \/ __| __/ _` |\___ \ / _` | | |
 | |  | (_) \__ \ || (_| |____) | (_| | | |
 |_|   \___/|___/\__\__, |_____/ \__,_|_|_|
                     __/ |                 
                    |___/                  
 %', now();
END $$;
