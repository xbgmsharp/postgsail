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
-- grafana_auth
SET ROLE grafana_auth;
\echo 'ROLE grafana_auth current_setting'
SELECT current_user, current_setting('user.email', true), current_setting('vessel.client_id', true), current_setting('vessel.id', true);

--SELECT a.pass,v.name,m.client_id FROM auth.accounts a JOIN auth.vessels v ON a.email = 'demo+kapla@openplotter.cloud' AND a.role = 'user_role' AND cast(a.preferences->>'email_valid' as Boolean) = True AND v.owner_email = a.email JOIN api.metadata m ON m.vessel_id = v.vessel_id;
--SELECT a.pass,v.name,m.client_id FROM auth.accounts a JOIN auth.vessels v ON a.email = 'demo+kapla@openplotter.cloud' AND a.role = 'user_role' AND v.owner_email = a.email JOIN api.metadata m ON m.vessel_id = v.vessel_id;
\echo 'link vessel and user based on current_setting'
SELECT v.name,m.client_id FROM auth.accounts a JOIN auth.vessels v ON a.role = 'user_role' AND v.owner_email = a.email JOIN api.metadata m ON m.vessel_id = v.vessel_id;

\echo 'auth.accounts details'
SELECT a.public_id IS NOT NULL AS public_id, a.user_id IS NOT NULL AS user_id, a.email, a.first, a.last, a.pass IS NOT NULL AS pass, a.role, a.preferences->'telegram'->'chat' AS telegram, a.preferences->'pushover_user_key' AS pushover_user_key FROM auth.accounts AS a;
\echo 'auth.vessels details'
--SELECT 'SELECT ' || STRING_AGG('v.' || column_name, ', ') || ' FROM auth.vessels AS v' FROM information_schema.columns WHERE table_name = 'vessels' AND table_schema = 'auth' AND column_name NOT IN ('created_at', 'updated_at');
SELECT v.vessel_id IS NOT NULL AS vessel_id, v.owner_email, v.mmsi, v.name, v.role FROM auth.vessels AS v;
\echo 'api.metadata details'
--
SELECT m.id, m.name, m.mmsi, m.client_id, m.length, m.beam, m.height, m.ship_type, m.plugin_version, m.signalk_version, m.time IS NOT NULL AS time, m.active FROM api.metadata AS m;

--
-- grafana
SET ROLE grafana;
\echo 'ROLE grafana current_setting'

\echo 'Set current_setting value'
SET "user.email" = 'demo+kapla@openplotter.cloud';
--SET vessel.client_id = 'vessels.urn:mrn:imo:mmsi:123456789';

--select v.vessel_id FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud';
SELECT v.vessel_id as "vessel_id" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
--\echo :"vessel_id"
SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;

--SELECT current_user, current_setting('user.email', true), current_setting('vessel.client_id', true), current_setting('vessel.id', true);
SELECT current_user, current_setting('user.email', true), current_setting('vessel.client_id', true);

SELECT v.name AS __text, m.client_id AS __value FROM auth.vessels v JOIN api.metadata m ON v.owner_email = 'demo+kapla@openplotter.cloud' and m.vessel_id = v.vessel_id;

\echo 'auth.vessels details'
--SELECT * FROM auth.vessels v;
SELECT v.vessel_id IS NOT NULL AS vessel_id, v.owner_email, v.mmsi, v.name, v.role FROM auth.vessels AS v;
--SELECT * FROM api.metadata m;
\echo 'api.metadata details'
SELECT m.id, m.name, m.mmsi, m.client_id, m.length, m.beam, m.height, m.ship_type, m.plugin_version, m.signalk_version, m.time IS NOT NULL AS time, m.active FROM api.metadata AS m;

\echo 'api.logs_view'
--SELECT * FROM api.logbook l;
--SELECT * FROM api.logs_view l;
SELECT l.id, l.name, l.from, l.to, l.distance, l.duration, l._from_moorage_id, l._to_moorage_id FROM api.logs_view AS l;
--SELECT * FROM api.log_view l;

\echo 'api.stays'
--SELECT * FROM api.stays s;
SELECT m.id, m.vessel_id IS NOT NULL AS vessel_id, m.moorage_id, m.active, m.name, m.latitude, m.longitude, m.geog, m.arrived IS NOT NULL AS arrived, m.departed IS NOT NULL AS departed, m.duration, m.stay_code, m.notes FROM api.stays AS m;

\echo 'stays_view'
--SELECT * FROM api.stays_view s;
SELECT m.id, m.name IS NOT NULL AS name, m.moorage, m.moorage_id, m.duration, m.stayed_at, m.stayed_at_id, m.arrived IS NOT NULL AS arrived, m.departed IS NOT NULL AS departed, m.notes FROM api.stays_view AS m;

\echo 'api.moorages'
--SELECT * FROM api.moorages m;
SELECT m.id, m.vessel_id IS NOT NULL AS vessel_id, m.name, m.country, m.stay_code, m.stay_duration, m.reference_count, m.latitude, m.longitude, m.geog, m.home_flag, m.notes FROM api.moorages AS m;

\echo 'api.moorages_view'
SELECT * FROM api.moorages_view s;
