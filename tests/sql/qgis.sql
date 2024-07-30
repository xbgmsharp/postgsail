---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

-- Assign vessel_id var
SELECT v.vessel_id as "vessel_id_kapla" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
SELECT v.vessel_id as "vessel_id_aava" FROM auth.vessels v WHERE v.owner_email = 'demo+aava@openplotter.cloud' \gset

-- qgis
SET ROLE qgis_role;

-- Get BBOX Extent from SQL query for a log:
-- "^/log_(\w+)_(\d+).png$"
-- "^/log_(\w+)_(\d+)_sat.png$
-- require a log_id, optional image width and height, scale_out
\echo 'Get BBOX Extent from SQL query for a log: "^/log_(\w+)_(\d+).png$"'
SELECT public.qgis_bbox_py_fn(null, 1);
SELECT public.qgis_bbox_py_fn(null, 3);
-- "^/log_(\w+)_(\d+)_line.png$"
\echo 'Get BBOX Extent from SQL query for a log as line: "^/log_(\w+)_(\d+)_line.png$"'
SELECT public.qgis_bbox_py_fn(null, 1, 333, 216, False);
SELECT public.qgis_bbox_py_fn(null, 3, 333, 216, False);
-- Get BBOX Extent from SQL query for all logs by vessel_id
-- "^/logs_(\w+)_(\d+).png$"
-- require a vessel_id, optional image width and height, scale_out
\echo 'Get BBOX Extent from SQL query for all logs by vessel_id: "^/logs_(\w+)_(\d+).png$"'
SELECT public.qgis_bbox_py_fn(:'vessel_id_kapla'::TEXT);
SELECT public.qgis_bbox_py_fn(:'vessel_id_aava'::TEXT);
-- Get BBOX Extent from SQL query for all logs by vessel_id
-- "^/logs_(\w+)_(\d+).png$"
-- require a vessel_id, optional image width and height, scale_out
\echo 'Get BBOX Extent from SQL query for a trip by vessel_id: "^/trip_(\w+)_(\d+)_(\d+).png$"'
SELECT public.qgis_bbox_py_fn(:'vessel_id_kapla'::TEXT, 1, 2);
SELECT public.qgis_bbox_py_fn(:'vessel_id_aava'::TEXT, 3, 4);
-- require a vessel_id, optional image width and height, scale_out as in Apache
\echo 'Get BBOX Extent from SQL query for a trip by vessel_id: "^/trip_((\w+)_(\d+)_(\d+)).png$"'
SELECT public.qgis_bbox_trip_py_fn(CONCAT(:'vessel_id_kapla'::TEXT, '_', 1, '_',2));
SELECT public.qgis_bbox_trip_py_fn(CONCAT(:'vessel_id_aava'::TEXT, '_', 3, '_', 4));

--SELECT set_config('vessel.id', :'vessel_id_kapla', false) IS NOT NULL as vessel_id;
-- SQL request from QGIS to fetch the necessary data base on vessel_id
--SELECT id, vessel_id, name as logname, ST_Transform(track_geom, 3857) as track_geom, ROUND(distance, 2) as distance, ROUND(EXTRACT(epoch FROM duration)/3600,2) as duration,_from_time,_to_time FROM api.logbook where track_geom is not null and _to_time is not null ORDER BY _from_time DESC;
SELECT count(*) FROM api.logbook where track_geom is not null and _to_time is not null;
