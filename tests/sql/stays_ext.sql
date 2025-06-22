---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

SELECT count(*) as count_eq_0 FROM api.stays_ext m;

SELECT v.vessel_id as "vessel_id" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
--\echo :"vessel_id"
SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;

-- user_role
SET ROLE user_role;

\echo 'api.stays details'
SELECT vessel_id IS NOT NULL AS vessel_id_not_null, m.name IS NOT NULL AS name_not_null FROM api.stays AS m WHERE active IS False ORDER BY m.name ASC;

-- Upsert image on stays_ext table
\echo 'api.stays_ext set image/image_b64'
INSERT INTO api.stays_ext (vessel_id, stay_id, image_b64)
    VALUES (current_setting('vessel.id', false), 1, 'iVBORw0KGgoAAAANSUhEUgAAAMgAAAAyCAIAAACWMwO2AAABNklEQVR4nO3bwY6CMBiF0XYy7//KzIKk6VBjiMMNk59zVljRIH6WsrBv29bgal93HwA1CYsIYREhLCKERYSwiBAWEcIiQlhECIsIYREhLCKERYSwiBAWEcIiQlhECIsIYREhLCK+7z6A/6j33lq75G8m')
    ON CONFLICT (stay_id) DO UPDATE
    SET image_b64 = EXCLUDED.image_b64;

-- Ensure image_updated_at on metadata_ext table is updated by trigger
\echo 'api.stays_ext get image_updated_at'
SELECT image_b64 IS NULL AS image_b64_is_null,image IS NOT NULL AS image_not_null,image_updated_at IS NOT NULL AS image_updated_at_not_null FROM api.metadata_ext; --WHERE vessel_id = current_setting('vessel.id', false);

-- vessel_role
SET ROLE vessel_role;

\echo 'api.stays_ext'
SELECT vessel_id IS NOT NULL AS vessel_id_not_null, stay_id FROM api.stays_ext;

-- api_anonymous
SET ROLE api_anonymous;

\echo 'api_anonymous get stays image'
SELECT api.stays_image(current_setting('vessel.id', false), 1) IS NOT NULL AS stays_image_not_null;
