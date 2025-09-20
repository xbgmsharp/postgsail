---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

SELECT count(*) as count_eq_0 FROM api.moorages_ext m;

SELECT v.vessel_id as "vessel_id" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
--\echo :"vessel_id"
SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;

-- user_role
SET ROLE user_role;

\echo 'api.moorages details'
SELECT vessel_id IS NOT NULL AS vessel_id_not_null, m.name IS NOT NULL AS name_not_null FROM api.moorages AS m ORDER BY m.name ASC;

-- Upsert image on moorages_ext table
\echo 'api.moorages_ext set image/image_b64'
INSERT INTO api.moorages_ext (vessel_id, ref_id, image_b64)
    VALUES (current_setting('vessel.id', false), 1, 'iVBORw0KGgoAAAANSUhEUgAAAMgAAAAyCAIAAACWMwO2AAABNklEQVR4nO3bwY6CMBiF0XYy7//KzIKk6VBjiMMNk59zVljRIH6WsrBv29bgal93HwA1CYsIYREhLCKERYSwiBAWEcIiQlhECIsIYREhLCKERYSwiBAWEcIiQlhECIsIYREhLCK+7z6A/6j33lq75G8m')
    ON CONFLICT (ref_id) DO UPDATE
    SET image_b64 = EXCLUDED.image_b64;

-- Ensure image_updated_at on metadata_ext table is updated by trigger
\echo 'api.moorages_ext get image_updated_at'
SELECT image_b64 IS NULL AS image_b64_is_null,image IS NOT NULL AS image_not_null,image_updated_at IS NOT NULL AS image_updated_at_not_null FROM api.moorages_ext; --WHERE vessel_id = current_setting('vessel.id', false);

-- vessel_role
SET ROLE vessel_role;

\echo 'api.moorages_ext vessel_role denied'
SELECT vessel_id IS NOT NULL AS vessel_id_not_null, ref_id FROM api.moorages_ext;

-- api_anonymous
SET ROLE api_anonymous;

\echo 'api_anonymous get moorage image'
SELECT api.image('moorage', current_setting('vessel.id', false), 1) IS NOT NULL AS moorage_image_not_null;
