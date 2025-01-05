---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

\echo 'Validate logbook operation'
-- set user_id
SELECT a.user_id as "user_id" FROM auth.accounts a WHERE a.email = 'demo+kapla@openplotter.cloud' \gset
--\echo :"user_id"
SELECT set_config('user.id', :'user_id', false) IS NOT NULL as user_id;

-- set vessel_id
SELECT v.vessel_id as "vessel_id" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
--\echo :"vessel_id"
SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;

-- Delete logbook for user
\echo 'logbook'
SELECT count(*) FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false);
\echo 'logbook'
-- track_geom and track_geojson are now dynamic from mobilitydb
SELECT name,_from_time IS NOT NULL AS _from_time, _to_time IS NOT NULL AS _to_time, trajectory(trip) AS track_geom, distance,duration,avg_speed,max_speed,max_wind_speed,notes,extra FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false) ORDER BY id ASC;

-- Delete logbook for user
\echo 'Delete logbook for user kapla'
SELECT api.delete_logbook_fn(5); -- delete Tropics Zone
SELECT api.delete_logbook_fn(6); -- delete Alaska Zone

-- Merge logbook for user
\echo 'Merge logbook for user kapla'
SELECT api.merge_logbook_fn(1,2);
