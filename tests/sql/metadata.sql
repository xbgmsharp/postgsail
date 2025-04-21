---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

SELECT v.vessel_id as "vessel_id" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
--\echo :"vessel_id"
SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;

--SELECT * FROM api.metadata m;
\echo 'api.metadata details'
SELECT m.id, m.name, m.mmsi, m.length, m.beam, m.height, m.ship_type, m.plugin_version, m.signalk_version, m.time IS NOT NULL AS time, m.active, configuration, available_keys FROM api.metadata AS m ORDER BY m.name ASC;

\echo 'api.metadata get configuration'
select configuration from api.metadata WHERE vessel_id = current_setting('vessel.id', false);

\echo 'api.metadata update configuration'
UPDATE api.metadata SET configuration = '{ "depthKey": "environment.depth.belowTransducer" }' WHERE vessel_id = current_setting('vessel.id', false);

\echo 'api.metadata get configuration with new value'
select configuration->'depthKey' AS depthKey, configuration->'update_at' IS NOT NULL AS update_at from api.metadata WHERE vessel_id = current_setting('vessel.id', false);

\echo 'api.metadata get configuration base on update_at value'
select configuration->'depthKey' AS depthKey, configuration->'update_at' IS NOT NULL AS update_at from api.metadata WHERE vessel_id = current_setting('vessel.id', false) AND configuration->>'update_at' <= to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
