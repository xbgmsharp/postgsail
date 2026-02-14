---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

\echo 'Validate views operation'
-- set user_id
SELECT a.user_id as "user_id" FROM auth.accounts a WHERE a.email = 'demo+aava@openplotter.cloud' \gset
--\echo :"user_id"
SELECT set_config('user.id', :'user_id', false) IS NOT NULL as user_id;

-- set vessel_id
SELECT v.vessel_id as "vessel_id" FROM auth.vessels v WHERE v.owner_email = 'demo+aava@openplotter.cloud' \gset
--\echo :"vessel_id"
SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;

--
-- user_role
SET ROLE user_role;
\echo 'ROLE user_role current_setting'

SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;

\echo 'logs view'
SELECT name,"from","to",started IS NOT NULL AS started_not_null, ended IS NOT NULL AS ended_not_null,distance,date_trunc('minute', duration::INTERVAL),_from_moorage_id,_to_moorage_id,tags FROM api.logs_view;

\echo 'log view'
SELECT name,"from","to",started IS NOT NULL AS started_not_null, ended IS NOT NULL AS ended_not_null,geojson->'features' IS NOT NULL AS geojson_features_not_null,distance,date_trunc('minute', duration::INTERVAL),avg_speed,max_speed,max_wind_speed,extra->>'avg_wind_speed' IS NOT NULL as avg_wind_speed_not_null,notes,polar IS NOT NULL as polar_is_not_null,tags,observations FROM api.log_view;

\echo 'stays view'
--SELECT * FROM api.stays_view;
SELECT name,moorage,moorage_id,date_trunc('minute', duration::INTERVAL) AS duration,stayed_at,stayed_at_id,arrived IS NOT NULL AS arrived_not_null,arrived_log_id,arrived_from_moorage_id,arrived_from_moorage_name,departed IS NOT NULL AS departed_not_null,departed_log_id,departed_to_moorage_id,departed_to_moorage_name,notes FROM api.stays_view;

\echo 'stay view'
--SELECT * FROM api.stay_view;
SELECT name,moorage,moorage_id,date_trunc('minute', duration::INTERVAL) AS duration,stayed_at,stayed_at_id,arrived IS NOT NULL AS arrived_not_null,arrived_log_id,arrived_from_moorage_id,arrived_from_moorage_name,departed IS NOT NULL AS departed_not_null,departed_log_id,departed_to_moorage_id,departed_to_moorage_name,notes FROM api.stay_view;

\echo 'moorages view'
--SELECT * FROM api.moorages_view;
SELECT moorage,default_stay,default_stay_id,arrivals_departures,date_trunc('minute', total_duration::INTERVAL) AS total_duration FROM api.moorages_view;

\echo 'moorage view'
--SELECT * FROM api.moorage_view;
SELECT name,default_stay,default_stay_id,date_trunc('minute', stays_sum_duration::INTERVAL) AS stays_sum_duration,notes,logs_count,stays_count,home,geog,stay_first_seen IS NOT NULL AS stay_first_seen_not_null, stay_last_seen IS NOT NULL AS stay_last_seen_not_null, stay_first_seen_id, stay_last_seen_id FROM api.moorage_view;
\echo 'logs geojson view'
--SELECT * FROM api.logs_geojson_view;
SELECT id,name,geojson->'geometry' IS NOT NULL AS geojson_geometry_not_null, geojson->'properties' IS NOT NULL AS geojson_properties_not_null FROM api.logs_geojson_view;

\echo 'moorages geojson view'
--SELECT * FROM api.moorages_geojson_view;
SELECT id,name,geojson->'geometry' IS NOT NULL AS geojson_geometry_not_null, geojson->'properties' IS NOT NULL AS geojson_properties_not_null FROM api.moorages_geojson_view;