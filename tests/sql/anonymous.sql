---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

\echo 'Validate anonymous access'
SELECT api.ispublic_fn('kapla', 'public_test');
SELECT api.ispublic_fn('kapla', 'public_logs_list');
SELECT api.ispublic_fn('kapla', 'public_logs', 1);
SELECT api.ispublic_fn('kapla', 'public_logs', 3);
SELECT api.ispublic_fn('kapla', 'public_monitoring');
SELECT api.ispublic_fn('kapla', 'public_timelapse');

SELECT api.ispublic_fn('aava', 'public_test');
SELECT api.ispublic_fn('aava', 'public_logs_list');
SELECT api.ispublic_fn('aava', 'public_logs', 1);
SELECT api.ispublic_fn('aava', 'public_logs', 3);
SELECT api.ispublic_fn('aava', 'public_monitoring');
SELECT api.ispublic_fn('aava', 'public_timelapse');

-- set vessel_id
SELECT v.vessel_id as "vessel_id" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
--\echo :"vessel_id"
SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;
SELECT set_config('vessel.name', 'kapla', false) IS NOT NULL as vessel_id;

-- api_anonymous
SET ROLE api_anonymous;

\echo 'api_anonymous logs_list'
-- SELECT * FROM api.logs_view;
SELECT count(*) AS count_eq_4 FROM api.logs_view;

\echo 'api_anonymous stays_list'
-- SELECT * FROM api.stays_view;
SELECT count(*) AS count_eq_2 FROM api.stays_view;

\echo 'api_anonymous moorages_list'
-- SELECT * FROM api.moorages_view;
SELECT count(*) AS count_eq_3 FROM api.moorages_view;

\echo 'api_anonymous log_view id=1'
SELECT name IS NOT NULL as name_is_not_null FROM api.log_view WHERE id = 1;

\echo 'api_anonymous monitoring_view'
SELECT time IS NOT NULL as time_is_not_null, name IS NOT NULL as name_is_not_null FROM api.monitoring_view;

\echo 'api_anonymous monitoring_live'
SELECT time IS NOT NULL as time_is_not_null, name IS NOT NULL as name_is_not_null FROM api.monitoring_live;

