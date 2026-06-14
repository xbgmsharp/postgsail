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
SELECT vessel_id IS NOT NULL AS vessel_id_not_null, m.name, m.mmsi, m.length, m.beam, m.height, m.ship_type, m.plugin_version, m.signalk_version, m.time IS NOT NULL AS time, m.active, configuration IS NULL AS configuration_is_null, available_keys  IS NULL AS available_keys_is_null FROM api.metadata AS m ORDER BY m.name ASC;

\echo 'api.metadata get configuration'
select configuration from api.metadata; --WHERE vessel_id = current_setting('vessel.id', false);

\echo 'api.metadata update configuration'
UPDATE api.metadata SET configuration = '{ "depthKey": "environment.depth.belowTransducer" }'::jsonb; --WHERE vessel_id = current_setting('vessel.id', false);

\echo 'api.metadata get configuration with new value'
SELECT configuration->'depthKey' AS depthKey, configuration->'update_at' IS NOT NULL AS update_at_not_null from api.metadata; --WHERE vessel_id = current_setting('vessel.id', false);

\echo 'api.metadata get configuration base on update_at value'
SELECT configuration->'depthKey' AS depthKey, configuration->'update_at' IS NOT NULL AS update_at_not_null from api.metadata WHERE vessel_id = current_setting('vessel.id', false) AND configuration->>'update_at' <= to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"');

-- Upsert make_model on metadata table
\echo 'api.metadata set make_model'
UPDATE api.metadata
    SET user_data = jsonb_set(
        COALESCE(user_data, '{}'::jsonb),
        '{make_model}',
        '"my super yacht"'::jsonb
    )
    WHERE vessel_id = current_setting('vessel.id', false)
    RETURNING user_data->'make_model' AS make_model;

-- Upsert polar on metadata table
\echo 'api.metadata set polar'
UPDATE api.metadata
    SET user_data = jsonb_set(
        COALESCE(user_data, '{}'::jsonb),
        '{polar}',
        '"twa/tws;4;6;8;10;12;14;16;20;24\n0;0;0;0;0;0;0;0;0;0"'::jsonb
    )
    WHERE vessel_id = current_setting('vessel.id', false)
    RETURNING user_data->'polar' AS polar;

-- Ensure make_model on metadata table is updated
\echo 'api.metadata get make_model'
SELECT user_data->'make_model' AS make_model FROM api.metadata; --WHERE vessel_id = current_setting('vessel.id', false);

-- Ensure polar_updated_at on metadata table is updated by trigger
\echo 'api.metadata get polar_updated_at'
SELECT user_data->'polar' AS polar,user_data->>'polar_updated_at' IS NOT NULL AS polar_updated_at_not_null FROM api.metadata; --WHERE vessel_id = current_setting('vessel.id', false);

\echo 'api.metadata update alerting enabled and alarms low_water_depth_threshold'
SELECT api.update_metadata_userdata_fn(jsonb_build_object('alerting', jsonb_build_object('enabled', true))::TEXT);
SELECT api.update_metadata_userdata_fn(jsonb_build_object('alerting', jsonb_build_object('low_water_depth_threshold', 999))::TEXT);
SELECT api.update_metadata_userdata_fn(jsonb_build_object('alarms', jsonb_build_object('high_wind_speed_threshold', jsonb_build_object('date', '2024-01-29 01:50:00+00', 'value', 294)))::TEXT);
SELECT api.update_metadata_userdata_fn(jsonb_build_object('alarms', jsonb_build_object('low_water_depth_threshold', jsonb_build_object('date', '2024-01-29 01:50:00+00', 'value', 294)))::TEXT);

SELECT user_data->'alerting'->>'enabled' AS alerting_enabled,user_data->'alarms'->>'high_wind_speed_threshold' IS NOT NULL AS alarms_not_null FROM api.metadata; --WHERE vessel_id = current_setting('vessel.id', false);

-- vessel_role
SET ROLE vessel_role;

\echo 'api.metadata get configuration with new value as vessel'
select configuration->'depthKey' AS depthKey, configuration->'update_at' IS NOT NULL AS update_at_not_null from api.metadata; -- WHERE vessel_id = current_setting('vessel.id', false);

\echo 'api.metadata get configuration base on update_at value as vessel'
select configuration->'depthKey' AS depthKey, configuration->'update_at' IS NOT NULL AS update_at_not_null from api.metadata WHERE vessel_id = current_setting('vessel.id', false) AND configuration->>'update_at' <= to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
