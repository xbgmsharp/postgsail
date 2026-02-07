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
\echo 'List of installed extensions'
SELECT e.extname AS "Name", e.extversion AS "Version", n.nspname AS "Schema", c.description AS "Description" 
    FROM pg_catalog.pg_extension e 
    LEFT JOIN pg_catalog.pg_namespace n ON n.oid = e.extnamespace 
    LEFT JOIN pg_catalog.pg_description c ON c.objoid = e.oid AND c.classoid = 'pg_catalog.pg_extension'::pg_catalog.regclass 
    ORDER BY 1;

-- List of installed extensions available for upgrade
\echo 'List of installed extensions available for upgrade'
SELECT name, default_version, installed_version FROM pg_available_extensions where default_version <> installed_version;

-- List Language
\echo 'List Language'
--SELECT * FROM pg_language;
SELECT lanname,lanispl,lanpltrusted,lanacl FROM pg_language order by lanname;

-- List of databases
-- ICU Missing entry in some system?
--\l
\echo 'List of databases'
SELECT datname,datconnlimit,datcollate,datctype,datallowconn FROM pg_database order by datname;

-- List of relations
\echo 'List of relations'
--\dtables

-- List tables from schema api
\echo 'List of relations from schema api'
select t.table_name as schema_api
    from information_schema.tables t
    where t.table_schema = 'api'
        and t.table_type = 'BASE TABLE'
    order by t.table_name;

-- List tables from schema public
\echo 'List of relations from schema public'
select t.table_name as schema_public
    from information_schema.tables t
    where t.table_schema = 'public'
        and t.table_type = 'BASE TABLE'
        and t.table_name NOT LIKE 'goose_db_version%'
    order by t.table_name;

-- List tables from schema auth
\echo 'List of relations from schema auth'
select t.table_name as schema_auth
    from information_schema.tables t
    where t.table_schema = 'auth'
        and t.table_type = 'BASE TABLE'
    order by t.table_name;

-- List tables from schema jwt
\echo 'List of relations from schema jwt'
select t.table_name as schema_jwt
    from information_schema.tables t
    where t.table_schema = 'jwt'
        and t.table_type = 'BASE TABLE'
    order by t.table_name;

-- List Row Security Policies - todo reduce and improve output
\echo 'List Row Security Policies'
select * from pg_policies order by schemaname, tablename, policyname;

-- Test functions
\echo 'Test nominatim reverse_geocode_py_fn'
SELECT public.reverse_geocode_py_fn('nominatim', 1.4440116666666667, 38.82985166666667);
\echo 'Test geoip reverse_geoip_py_fn'
--SELECT reverse_geoip_py_fn('62.74.13.231');
\echo 'Test opverpass API overpass_py_fn'
--SELECT public.overpass_py_fn(2.19917, 41.386873333333334); -- Port Olimpic
--SELECT public.overpass_py_fn(1.92574333333, 41.258915); -- Port de la Ginesta
--SELECT public.overpass_py_fn(23.4321, 59.9768833333333); -- Norra hamnen

-- List details product versions
SELECT api.versions_fn();
SELECT * FROM api.versions_view;

-- List application settings
--SELECT * IS NOT NULl FROM public.app_settings;
