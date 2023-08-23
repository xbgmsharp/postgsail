---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

--
-- telegram
SET ROLE username;
-- Does chat id session exist?
SELECT auth.telegram_session_exists_fn(1234567890);
SELECT auth.telegram_session_exists_fn(9876543210);
SELECT auth.telegram_session_exists_fn(1472583690);

-- Assign vessel_id var
SELECT v.vessel_id as "vessel_id_kapla" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
SELECT v.vessel_id as "vessel_id_aava" FROM auth.vessels v WHERE v.owner_email = 'demo+aava@openplotter.cloud' \gset

SET ROLE api_anonymous;
SELECT api.telegram(1234567890::BIGINT) IS NOT NULL as telegram_session;
SELECT api.telegram(9876543210::BIGINT) IS NOT NULL as telegram_session;
SELECT api.telegram(1472583690::BIGINT) IS NULL as telegram_session;

SET ROLE user_role;
SET "user.email" = 'demo+kapla@openplotter.cloud';
--SET vessel.id = 'f94e995cf4d3';
SELECT set_config('vessel.id', :'vessel_id_kapla', false) IS NOT NULL as vessel_id;
SET vessel.name = 'kapla';
--SET vessel.client_id = 'vessels.urn:mrn:imo:mmsi:123456789';
--SELECT * FROM api.vessels_view v;
SELECT name, mmsi, created_at IS NOT NULL as created_at, last_contact IS NOT NULL as last_contact FROM api.vessels_view v;
SELECT name,geojson,watertemperature,insidetemperature,outsidetemperature FROM api.monitoring_view m;

SET "user.email" = 'demo+aava@openplotter.cloud';
SELECT set_config('vessel.id', :'vessel_id_aava', false) IS NOT NULL as vessel_id;
--SET vessel.id = '341dcfa30afb';
SET vessel.name = 'aava';
--SET vessel.client_id = 'vessels.urn:mrn:imo:mmsi:787654321';
--SELECT * FROM api.vessels_view v;
SELECT name, mmsi, created_at IS NOT NULL as created_at, last_contact IS NOT NULL as last_contact FROM api.vessels_view v;
SELECT name,geojson,watertemperature,insidetemperature,outsidetemperature FROM api.monitoring_view m;
