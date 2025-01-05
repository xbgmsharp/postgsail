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

-- user_role
SET ROLE user_role;
-- Switch user as aava
SELECT set_config('vessel.id', :'vessel_id_aava', false) IS NOT NULL as vessel_id;

-- Update notes
\echo 'Add a note for an entry from a trip'
-- Get original value, should be empty
SELECT numInstants(trip), valueAtTimestamp(trip_notes,timestampN(trip,13)) from api.logbook where id = 3;
-- Create the string
SELECT concat('["fishing"@', timestampN(trip,13),',""@',timestampN(trip,14),']') as to_be_update FROM api.logbook where id = 3 \gset
--\echo :to_be_update
-- Update the notes
SELECT api.update_trip_notes_fn(3, :'to_be_update');
-- Compare with previous value, should include "fishing"
SELECT valueAtTimestamp(trip_notes,timestampN(trip,13)) from api.logbook where id = 3;

-- Delete notes
\echo 'Delete an entry from a trip'
-- Get original value, should be 45
SELECT numInstants(trip), jsonb_array_length(api.export_logbook_geojson_point_trip_fn(id)->'features') from api.logbook where id = 3;
-- Extract the timestamps of the invalid coords
--SELECT timestampN(trip,14) as "to_be_delete" FROM api.logbook where id = 3 \gset
SELECT concat('[', timestampN(trip,14),',',timestampN(trip,15),')') as to_be_delete FROM api.logbook where id = 3 \gset
--\echo :to_be_delete
-- Delete the entry for all trip sequence
SELECT api.delete_trip_entry_fn(3, :'to_be_delete');
-- Compare with previous value, should be 44
SELECT numInstants(trip), jsonb_array_length(api.export_logbook_geojson_point_trip_fn(id)->'features') from api.logbook where id = 3;

-- Export PostGIS geography from a trip
\echo 'Export PostGIS geography from trajectory'
--SELECT ST_IsValid(trajectory(trip)::geometry) IS TRUE FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false);
SELECT trajectory(trip)::geometry FROM api.logbook WHERE id = 3;

-- Export GeoJSON from a trip
\echo 'Export GeoJSON with properties from a trip'
SELECT jsonb_array_length(api.export_logbook_geojson_point_trip_fn(3)->'features');

-- Export GPX from a trip
\echo 'Export GPX from a trip'
SELECT api.export_logbook_gpx_trip_fn(3) IS NOT NULL;

-- Export KML from a trip
\echo 'Export KML from a trip'
SELECT api.export_logbook_kml_trip_fn(3) IS NOT NULL;

-- Switch user as kapla
SELECT set_config('vessel.id', :'vessel_id_kapla', false) IS NOT NULL as vessel_id;

-- Export timelapse as Geometry LineString from a trip
\echo 'Export timelapse as Geometry LineString from a trip'
SELECT api.export_logbooks_geojson_linestring_trips_fn(1,2) FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false);

-- Export timelapse as Geometry Point from a trip
\echo 'Export timelapse as Geometry Point from a trip'
SELECT api.export_logbooks_geojson_point_trips_fn(1,2) IS NOT NULL FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false);

-- Export GPX from trips
\echo 'Export GPX from trips'
SELECT api.export_logbooks_gpx_trips_fn(1,2) IS NOT NULL FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false);

-- Export KML from trips
\echo 'Export KML from trips'
SELECT api.export_logbooks_kml_trips_fn(1,2) IS NOT NULL FROM api.logbook WHERE vessel_id = current_setting('vessel.id', false);
