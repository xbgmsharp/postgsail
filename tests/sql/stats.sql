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
SELECT tbl.stats->'stats_logs'->>'name' AS boat_name,
  (tbl.stats->'stats_logs'->>'count')::int AS logs_count,
  (tbl.stats->'stats_logs'->>'max_speed')::numeric AS max_speed, -- issue with mobilitydb speed calculation
  (tbl.stats->'stats_logs'->>'max_distance')::numeric AS max_distance,
  (tbl.stats->'stats_logs'->>'max_duration')::text AS max_duration,
  (tbl.stats->'stats_logs'->>'max_wind_speed')::numeric AS max_wind_speed,
  (tbl.stats->'stats_moorages'->>'home_ports')::int AS home_ports,
  (tbl.stats->'stats_moorages'->>'unique_moorages')::numeric AS unique_moorages,
  --(tbl.stats->'moorages_top_countries') = '["fi"]' AS moorages_top_countries
  (tbl.stats->'moorages_top_countries') AS moorages_top_countries
  FROM tbl;

SELECT set_config('vessel.id', :'vessel_id_aava', false) IS NOT NULL as vessel_id;

-- Stats logbook and moorages for user
\echo 'Stats logbook and moorages for user aava'
--SELECT api.stats_fn();
WITH tbl as (SELECT api.stats_fn() as stats)
SELECT tbl.stats->'stats_logs'->>'name' AS boat_name,
  (tbl.stats->'stats_logs'->>'count')::int AS logs_count,
  (tbl.stats->'stats_logs'->>'max_speed')::numeric AS max_speed,
  (tbl.stats->'stats_logs'->>'max_distance')::numeric AS max_distance,
  (tbl.stats->'stats_moorages'->>'home_ports')::int AS home_ports,
  (tbl.stats->'stats_moorages'->>'unique_moorages')::numeric AS unique_moorages,
  (tbl.stats->'moorages_top_countries') AS moorages_top_countries
  FROM tbl;
