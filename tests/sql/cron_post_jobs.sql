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

-- user_role
SET ROLE user_role;

--\echo :"vessel_id"
SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;

-- Test logbook for user
\echo 'logbook'
SELECT count(*) FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false);
\echo 'logbook'
--SELECT name,_from_time IS NOT NULL AS _from_time,_to_time IS NOT NULL AS _to_time, track_geojson IS NOT NULL AS track_geojson, trajectory(trip)::geometry as track_geom, distance,duration,round(avg_speed::NUMERIC,6),max_speed,max_wind_speed,notes,extra FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false);
--SELECT name,_from_time IS NOT NULL AS _from_time,_to_time IS NOT NULL AS _to_time, api.export_logbook_geojson_trip_fn(id) IS NOT NULL AS track_geojson, trajectory(trip)::geometry as track_geom, distance,duration,round(avg_speed::NUMERIC,6),max_speed,max_wind_speed,notes,extra FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false);
SELECT name IS NOT NULL AS name_not_null,_from_time IS NOT NULL AS _from_time,_to_time IS NOT NULL AS _to_time, api.export_logbook_geojson_trip_fn(id) IS NOT NULL AS track_geojson, trajectory(trip)::geometry as track_geom, distance,duration,avg_speed,max_speed,max_wind_speed,notes,extra->>'polar' IS NOT NULL as polar_is_not_null,extra->>'avg_wind_speed' as avg_wind_speed,user_data FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false) ORDER BY id ASC;

-- Test stays for user
\echo 'stays'
SELECT count(*) FROM api.stays WHERE vessel_id = current_setting('vessel.id', false);
\echo 'stays'
SELECT active,name IS NOT NULL AS name_not_null,geog,stay_code IS NOT NULL AS stay_code_not_null FROM api.stays WHERE vessel_id = current_setting('vessel.id', false) ORDER BY id ASC;

-- Test event logs view for user
\echo 'eventlogs_view'
SELECT count(*) from api.eventlogs_view;

-- Test stats function for user
\echo 'stats_fn'
--SELECT api.stats_fn();
-- Extract stats_logs key with explicit cast to avoid 'unknown' type
SELECT api.stats_fn() AS stats_fn INTO stats_jsonb;
SELECT  stats_fn->'stats_logs'->'name'      AS stats_logs_name,
        stats_fn->'logs_top_speed'          AS logs_top_speed,
        (stats_fn->'stats_moorages') IS NOT NULL AS stats_moorages_not_null,
        stats_fn->'logs_top_distance'       AS logs_top_distance,
        stats_fn->'logs_top_duration'       AS logs_top_duration,
        stats_fn->'logs_top_avg_speed'      AS logs_top_avg_speed,
        stats_fn->'logs_top_wind_speed'     AS logs_top_wind_speed,
        stats_fn->'moorages_top_arrivals'   AS moorages_top_arrivals,
        stats_fn->'moorages_top_duration'   AS moorages_top_duration,
        stats_fn->'moorages_top_countries'  AS moorages_top_countries,
        jsonb_array_length(stats_fn->'stats_moorages'->'time_spent_away_by') >= 1  AS time_spent_away_by_is_gt_1,
        stats_fn->'stats_moorages'->'time_at_home_ports'      AS time_at_home_ports
        FROM stats_jsonb;
DROP TABLE stats_jsonb;

\echo 'stats_logs_fn'
--SELECT api.stats_logs_fn();
SELECT api.stats_logs_fn() INTO stats_logs_jsonb;
SELECT stats_logs_fn->'name'                    AS name,
        stats_logs_fn->'count'                  AS count,
        stats_logs_fn->'max_speed'              AS max_speed,
        stats_logs_fn->'max_distance'           AS max_distance,
        stats_logs_fn->'max_duration'           AS max_duration,
        stats_logs_fn->'max_speed_id'           AS max_speed_id,
        stats_logs_fn->'sum_distance'           AS sum_distance,
        stats_logs_fn->'sum_duration'           AS sum_duration,
        stats_logs_fn->'max_wind_speed'         AS max_wind_speed,
        stats_logs_fn->'max_distance_id'        AS max_distance_id,
        stats_logs_fn->'max_duration_id'        AS max_duration_id,
        stats_logs_fn->'max_wind_speed_id'      AS max_wind_speed_id,
        stats_logs_fn->'first_date'             IS NOT NULL AS first_date,
        stats_logs_fn->'last_date'              IS NOT NULL AS last_date,
        stats_logs_fn->'metrics_first'          IS NOT NULL AS metrics_first,
        stats_logs_fn->'metrics_last'           IS NOT NULL AS metrics_last,
        stats_logs_fn->'longest_nonstop_sail'   IS NOT NULL AS longest_nonstop_sail,
        stats_logs_fn->'best_24h_distance_nm'   IS NOT NULL AS best_24h_distance_nm,
        stats_logs_fn->'best_24h_window_start'  IS NOT NULL AS best_24h_window_start,
        stats_logs_fn->'best_24h_log_id'        IS NOT NULL AS best_24h_log_id,
        stats_logs_fn->'best_24h_route'         IS NOT NULL AS best_24h_route
        FROM stats_logs_jsonb;
DROP TABLE stats_logs_jsonb;
SELECT api.stats_logs_fn('2022-01-01'::timestamptz,'2022-06-12'::timestamptz);

-- Update logbook observations
\echo 'update_logbook_observations_fn'
SELECT user_data FROM api.logbook l WHERE id = 1 AND vessel_id = current_setting('vessel.id', false);
SELECT api.update_logbook_observations_fn(1, '{"observations":{"cloudCoverage":1}}'::TEXT);
SELECT user_data FROM api.logbook l WHERE id = 1 AND vessel_id = current_setting('vessel.id', false);

\echo 'add tags to logbook'
SELECT user_data FROM api.logbook l WHERE id = 1 AND vessel_id = current_setting('vessel.id', false);
SELECT api.update_logbook_observations_fn(1, '{"tags": ["tag_name"]}'::TEXT);
SELECT user_data FROM api.logbook l WHERE id = 1 AND vessel_id = current_setting('vessel.id', false);

\echo 'Check logbook geojson LineString properties'
WITH logbook_tbl AS (
    SELECT api.logbook_update_geojson_trip_fn(id) AS geojson
    FROM api.logbook WHERE id = 1 AND vessel_id = current_setting('vessel.id', false)
)
SELECT jsonb_object_keys(jsonb_path_query(geojson, '$.features[0].properties'))
    FROM logbook_tbl;
\echo 'Check logbook geojson Point properties'
WITH logbook_tbl AS (
    SELECT api.logbook_update_geojson_trip_fn(id) AS geojson
    FROM api.logbook WHERE id = 1 AND vessel_id = current_setting('vessel.id', false)
)
SELECT jsonb_object_keys(jsonb_path_query(geojson, '$.features[1].properties'))
    FROM logbook_tbl;

-- Check export
\echo 'Check logbook export fn'
--SELECT api.export_logbook_geojson_fn(1);
--SELECT api.export_logbook_gpx_fn(1);
--SELECT api.export_logbook_kml_fn(1);
SELECT api.export_logbook_gpx_trip_fn(1) IS NOT NULL AS gpx_trip;
SELECT api.export_logbook_kml_trip_fn(1) IS NOT NULL AS kml_trip;
SELECT api.export_logbook_polar_csv_fn(1) IS NOT NULL AS polar_csv;

-- Check history
--\echo 'monitoring history fn'
--select api.monitoring_history_fn();
--select api.monitoring_history_fn('24');
