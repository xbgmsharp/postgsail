---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

\echo 'Validate Stats operation'
-- Assign vessel_id var
SELECT v.vessel_id as "vessel_id_kapla" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
SELECT v.vessel_id as "vessel_id_aava" FROM auth.vessels v WHERE v.owner_email = 'demo+aava@openplotter.cloud' \gset

-- user_role
SET ROLE user_role;
\echo 'ROLE user_role current_setting'

SELECT set_config('vessel.id', :'vessel_id_kapla', false) IS NOT NULL as vessel_id;

-- Stats logbook and moorages for user
\echo 'Stats logbook and moorages for user kapla'
--SELECT api.stats_fn();
WITH tbl as (SELECT api.stats_fn() as stats)
SELECT tbl.stats->'stats_logs'->>'name' = 'kapla' AS boat_name,
  (tbl.stats->'stats_logs'->>'count')::int = 1 AS logs_count,
  (tbl.stats->'stats_logs'->>'max_speed')::numeric = 20.3 AS max_speed,
  (tbl.stats->'stats_logs'->>'max_distance')::numeric = 16.58 AS max_distance,
  (tbl.stats->'stats_logs'->>'max_duration')::text = 'PT49M' AS max_duration,
  (tbl.stats->'stats_moorages'->>'home_ports')::int = 1 AS home_ports,
  (tbl.stats->'stats_moorages'->>'unique_moorages')::numeric = 5 AS unique_moorages,
  (tbl.stats->'moorages_top_countries') = '["fi"]' AS moorages_top_countries
  FROM tbl;

SELECT set_config('vessel.id', :'vessel_id_aava', false) IS NOT NULL as vessel_id;

-- Stats logbook and moorages for user
\echo 'Stats logbook and moorages for user aava'
--SELECT api.stats_fn();
WITH tbl as (SELECT api.stats_fn() as stats)
SELECT tbl.stats->'stats_logs'->>'name' = 'aava' AS boat_name,
  (tbl.stats->'stats_logs'->>'count')::int = 2 AS logs_count,
  (tbl.stats->'stats_logs'->>'max_speed')::numeric = 90.14 AS max_speed,
  (tbl.stats->'stats_logs'->>'max_distance')::numeric = 69.10 AS max_distance,
  (tbl.stats->'stats_moorages'->>'home_ports')::int = 1 AS home_ports,
  (tbl.stats->'stats_moorages'->>'unique_moorages')::numeric = 4 AS unique_moorages,
  (tbl.stats->'moorages_top_countries') = '["ee"]' AS moorages_top_countries
  FROM tbl;
