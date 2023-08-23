---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

-- List PostgreSQL version
--SELECT version();
-- check only version number to remove arch details
SHOW server_version;

-- List Postgis version
SELECT postgis_full_version();

-- List of installed extensions
-- \dx
--SELECT extname,extversion FROM pg_extension;
SELECT e.extname AS "Name", e.extversion AS "Version", n.nspname AS "Schema", c.description AS "Description" 
    FROM pg_catalog.pg_extension e 
    LEFT JOIN pg_catalog.pg_namespace n ON n.oid = e.extnamespace 
    LEFT JOIN pg_catalog.pg_description c ON c.objoid = e.oid AND c.classoid = 'pg_catalog.pg_extension'::pg_catalog.regclass 
    ORDER BY 1;

-- List of installed extensions available for upgrade
SELECT name, default_version, installed_version FROM pg_available_extensions where default_version <> installed_version;

-- List Language
\echo 'List Language'
SELECT * FROM pg_language;

-- List of databases
-- ICU Missing entry in some system?
--\l
SELECT datname,datconnlimit,datcollate,datctype,datallowconn FROM pg_database;

-- List of relations
\echo 'List of relations'
\dtables

-- List tables from schema api
select t.table_name as schema_api
    from information_schema.tables t
    where t.table_schema = 'api'
        and t.table_type = 'BASE TABLE'
    order by t.table_name;

-- List tables from schema public
select t.table_name as schema_public
    from information_schema.tables t
    where t.table_schema = 'public'
        and t.table_type = 'BASE TABLE'
    order by t.table_name;

-- List tables from schema auth
select t.table_name as schema_auth
    from information_schema.tables t
    where t.table_schema = 'auth'
        and t.table_type = 'BASE TABLE'
    order by t.table_name;

-- List tables from schema jwt
select t.table_name as schema_jwt
    from information_schema.tables t
    where t.table_schema = 'jwt'
        and t.table_type = 'BASE TABLE'
    order by t.table_name;

-- List Row Security Policies - todo reduce and improve output
\echo 'List Row Security Policies'
select * from pg_policies;

-- Test functions
\echo 'Test nominatim reverse_geocode_py_fn'
SELECT public.reverse_geocode_py_fn('nominatim', 1.4440116666666667, 38.82985166666667);
\echo 'Test geoip reverse_geoip_py_fn'
--SELECT reverse_geoip_py_fn('62.74.13.231');

-- List details product versions
SELECT api.versions_fn();
SELECT * FROM api.versions_view;

-- List application settings
--SELECT * IS NOT NULl FROM public.app_settings;
