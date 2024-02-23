---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

\echo 'Set vessel_id and vessel.name'
-- set vessel_id
SELECT v.vessel_id as "vessel_id" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
--\echo :"vessel_id"
SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;

-- set name
SELECT v.name as "name" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
--\echo :"vessel_id"
SELECT set_config('vessel.name', :'name', false) IS NOT NULL as name;

\echo 'Test monitoring_view for user'
-- Test monitoring for user
--select * from api.monitoring_view;
select count(*) from api.monitoring_view;

\echo 'Test monitoring_view2 for user'
-- Test monitoring for user
--select * from api.monitoring_view2;
select count(*) from api.monitoring_view2;

\echo 'Test monitoring_view3 for user'
-- Test monitoring for user
--select * from api.monitoring_view3;
select count(*) from api.monitoring_view3;

\echo 'Test monitoring_voltage for user'
-- Test monitoring for user
--select * from api.monitoring_voltage;
select count(*) from api.monitoring_voltage;

\echo 'Test monitoring_temperatures for user'
-- Test monitoring for user
--select * from api.monitoring_temperatures;
select count(*) from api.monitoring_temperatures;

\echo 'Test monitoring_humidity for user'
-- Test monitoring for user
--select * from api.monitoring_humidity;
select count(*) from api.monitoring_humidity;
