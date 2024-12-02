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
SELECT name,_from_time IS NOT NULL AS _from_time,_to_time IS NOT NULL AS _to_time, track_geojson IS NOT NULL AS track_geojson, trajectory(trip)::geometry as track_geom, distance,duration,round(avg_speed::NUMERIC,6),max_speed,max_wind_speed,notes,extra FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false);

-- Test stays for user
\echo 'stays'
SELECT count(*) FROM api.stays WHERE vessel_id = current_setting('vessel.id', false);
\echo 'stays'
SELECT active,name IS NOT NULL AS name,geog,stay_code FROM api.stays WHERE vessel_id = current_setting('vessel.id', false);

-- Test event logs view for user
\echo 'eventlogs_view'
SELECT count(*) from api.eventlogs_view;

-- Test event logs view for user
\echo 'stats_logs_fn'
SELECT api.stats_logs_fn(null, null) INTO stats_jsonb;
SELECT stats_logs_fn->'name' AS name,
        stats_logs_fn->'count' AS count,
        stats_logs_fn->'max_speed' As max_speed,
        stats_logs_fn->'max_distance' AS max_distance,
        stats_logs_fn->'max_duration' AS max_duration,
        stats_logs_fn->'max_speed_id',
        stats_logs_fn->'sum_distance',
        stats_logs_fn->'sum_duration',
        stats_logs_fn->'max_wind_speed',
        stats_logs_fn->'max_distance_id',
        stats_logs_fn->'max_duration_id',
        stats_logs_fn->'max_wind_speed_id',
        stats_logs_fn->'first_date' IS NOT NULL AS first_date,
        stats_logs_fn->'last_date' IS NOT NULL AS last_date
        FROM stats_jsonb;
DROP TABLE stats_jsonb;
SELECT api.stats_logs_fn('2022-01-01'::text,'2022-06-12'::text);

-- Update logbook observations
\echo 'update_logbook_observations_fn'
SELECT extra FROM api.logbook l WHERE id = 1 AND vessel_id = current_setting('vessel.id', false);
SELECT api.update_logbook_observations_fn(1, '{"observations":{"cloudCoverage":1}}'::TEXT);
SELECT extra FROM api.logbook l WHERE id = 1 AND vessel_id = current_setting('vessel.id', false);

\echo 'add tags to logbook'
SELECT extra FROM api.logbook l WHERE id = 1 AND vessel_id = current_setting('vessel.id', false);
SELECT api.update_logbook_observations_fn(1, '{"tags": ["tag_name"]}'::TEXT);
SELECT extra FROM api.logbook l WHERE id = 1 AND vessel_id = current_setting('vessel.id', false);

\echo 'Check numbers of geojson properties'
SELECT jsonb_object_keys(jsonb_path_query(track_geojson, '$.features[0].properties'))
    FROM api.logbook where id = 1 AND vessel_id = current_setting('vessel.id', false);
SELECT jsonb_object_keys(jsonb_path_query(track_geojson, '$.features[1].properties'))
    FROM api.logbook where id = 1 AND vessel_id = current_setting('vessel.id', false);

-- Check export
--\echo 'check logbook export fn'
--SELECT api.export_logbook_geojson_fn(1);
--SELECT api.export_logbook_gpx_fn(1);
--SELECT api.export_logbook_kml_fn(1);

-- Check history
--\echo 'monitoring history fn'
--select api.monitoring_history_fn();
--select api.monitoring_history_fn('24');
