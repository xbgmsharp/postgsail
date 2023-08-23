---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

-- set user_id
SELECT a.user_id as "user_id" FROM auth.accounts a WHERE a.email = 'demo+kapla@openplotter.cloud' \gset
--\echo :"user_id"
SELECT set_config('user.id', :'user_id', false) IS NOT NULL as user_id;

-- set vessel_id
SELECT v.vessel_id as "vessel_id" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
--\echo :"vessel_id"
SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;

-- Test logbook for user
\echo 'logbook'
SELECT count(*) FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false);
\echo 'logbook'
SELECT name,_from_time IS NOT NULL AS _from_time,_to_time IS NOT NULL AS _to_time, track_geojson IS NOT NULL AS track_geojson, track_gpx IS NOT NULL AS track_gpx, track_geom, distance,duration,avg_speed,max_speed,max_wind_speed,notes,extra FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false);

-- Test stays for user
\echo 'stays'
SELECT count(*) FROM api.stays WHERE vessel_id = current_setting('vessel.id', false);
\echo 'stays'
SELECT active,name,geog,stay_code FROM api.stays WHERE vessel_id = current_setting('vessel.id', false);

-- Test event logs view for user
\echo 'eventlogs_view'
select count(*) from api.eventlogs_view;

-- Test event logs view for user
\echo 'stats_logs_fn'
select api.stats_logs_fn(null, null);
select api.stats_logs_fn('2022-01-01'::text,'2022-06-12'::text);
