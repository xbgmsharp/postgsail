---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

SELECT count(*) as count_eq_2 FROM api.metadata m;

SELECT v.vessel_id as "vessel_id" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
--\echo :"vessel_id"
SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;

-- user_role
SET ROLE user_role;

\echo 'api.metadata details'
SELECT vessel_id IS NOT NULL AS vessel_id_not_null, m.name, m.mmsi, m.length, m.beam, m.height, m.ship_type, m.plugin_version, m.signalk_version, m.time IS NOT NULL AS time, m.active, configuration, available_keys FROM api.metadata AS m ORDER BY m.name ASC;

\echo 'api.metadata get configuration'
select configuration from api.metadata; --WHERE vessel_id = current_setting('vessel.id', false);

\echo 'api.metadata update configuration'
UPDATE api.metadata SET configuration = '{ "depthKey": "environment.depth.belowTransducer" }'; --WHERE vessel_id = current_setting('vessel.id', false);

\echo 'api.metadata get configuration with new value'
select configuration->'depthKey' AS depthKey, configuration->'update_at' IS NOT NULL AS update_at_not_null from api.metadata; --WHERE vessel_id = current_setting('vessel.id', false);

\echo 'api.metadata get configuration base on update_at value'
select configuration->'depthKey' AS depthKey, configuration->'update_at' IS NOT NULL AS update_at_not_null from api.metadata WHERE vessel_id = current_setting('vessel.id', false) AND configuration->>'update_at' <= to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"');

-- Upsert make_model on metadata_ext table
\echo 'api.metadata_ext set make_model'
INSERT INTO api.metadata_ext (vessel_id, make_model)
    VALUES (current_setting('vessel.id', false), 'my super yacht')
    ON CONFLICT (vessel_id) DO UPDATE
    SET make_model = EXCLUDED.make_model;

-- Upsert polar on metadata_ext table
\echo 'api.metadata_ext set polar'
INSERT INTO api.metadata_ext (vessel_id, polar)
    VALUES (current_setting('vessel.id', false), 'twa/tws;4;6;8;10;12;14;16;20;24\n0;0;0;0;0;0;0;0;0;0')
    ON CONFLICT (vessel_id) DO UPDATE
    SET polar = EXCLUDED.polar;

-- Upsert image on metadata_ext table
\echo 'api.metadata_ext set image/image_b64'
INSERT INTO api.metadata_ext (vessel_id, image_b64)
    VALUES (current_setting('vessel.id', false), 'iVBORw0KGgoAAAANSUhEUgAAAMgAAAAyCAIAAACWMwO2AAABNklEQVR4nO3bwY6CMBiF0XYy7//KzIKk6VBjiMMNk59zVljRIH6WsrBv29bgal93HwA1CYsIYREhLCKERYSwiBAWEcIiQlhECIsIYREhLCKERYSwiBAWEcIiQlhECIsIYREhLCK+7z6A/6j33lq75G8m')
    ON CONFLICT (vessel_id) DO UPDATE
    SET image_b64 = EXCLUDED.image_b64;

-- Ensure make_model on metadata_ext table is updated
\echo 'api.metadata_ext get make_model'
SELECT make_model FROM api.metadata_ext; --WHERE vessel_id = current_setting('vessel.id', false);

-- Ensure polar_updated_at on metadata_ext table is updated by trigger
\echo 'api.metadata_ext get polar_updated_at'
SELECT polar,polar_updated_at IS NOT NULL AS polar_updated_at_not_null FROM api.metadata_ext; --WHERE vessel_id = current_setting('vessel.id', false);

-- Ensure image_updated_at on metadata_ext table is updated by trigger
\echo 'api.metadata_ext get image_updated_at'
SELECT image_b64 IS NULL AS image_b64_is_null,image IS NOT NULL AS image_not_null,image_updated_at IS NOT NULL AS image_updated_at_not_null FROM api.metadata_ext; --WHERE vessel_id = current_setting('vessel.id', false);

-- vessel_role
SET ROLE vessel_role;

\echo 'api.metadata get configuration with new value as vessel'
select configuration->'depthKey' AS depthKey, configuration->'update_at' IS NOT NULL AS update_at_not_null from api.metadata; -- WHERE vessel_id = current_setting('vessel.id', false);

\echo 'api.metadata get configuration base on update_at value as vessel'
select configuration->'depthKey' AS depthKey, configuration->'update_at' IS NOT NULL AS update_at_not_null from api.metadata WHERE vessel_id = current_setting('vessel.id', false) AND configuration->>'update_at' <= to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"');

-- api_anonymous
SET ROLE api_anonymous;

\echo 'api_anonymous get vessel image'
SELECT api.image('vessel', current_setting('vessel.id', false)) IS NOT NULL AS vessel_image_not_null;
