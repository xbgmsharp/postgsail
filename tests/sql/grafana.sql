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
SELECT current_user, current_setting('user.email', true);

SELECT v.name AS __text, m.vessel_id IS NOT NULL AS __value FROM auth.vessels v JOIN api.metadata m ON v.owner_email = 'demo+kapla@openplotter.cloud' and m.vessel_id = v.vessel_id;

\echo 'auth.vessels details'
--SELECT * FROM auth.vessels v;
SELECT v.vessel_id IS NOT NULL AS vessel_id, v.owner_email, v.mmsi, v.name, v.role FROM auth.vessels AS v;
--SELECT * FROM api.metadata m;
\echo 'api.metadata details'
SELECT vessel_id IS NOT NULL AS vessel_id_not_null, m.name, m.mmsi, m.length, m.beam, m.height, m.ship_type, m.plugin_version, m.signalk_version, m.time IS NOT NULL AS time, m.active, configuration IS NOT NULL AS configuration_not_null, available_keys FROM api.metadata AS m  ORDER BY name ASC;

\echo 'api.logs_view'
--SELECT * FROM api.logbook l;
--SELECT * FROM api.logs_view l;
SELECT l.id, l.name, l.from, l.to, l.distance, l.duration, l._from_moorage_id, l._to_moorage_id FROM api.logs_view AS l ORDER BY id ASC;
--SELECT * FROM api.log_view l;

\echo 'api.stays'
--SELECT * FROM api.stays s;
SELECT m.id, m.vessel_id IS NOT NULL AS vessel_id, m.moorage_id, m.active, m.name IS NOT NULL AS name, m.latitude, m.longitude, m.geog, m.arrived IS NOT NULL AS arrived, m.departed IS NOT NULL AS departed, m.duration, m.stay_code, m.notes FROM api.stays AS m ORDER BY id ASC;

\echo 'api.stays_view'
--SELECT * FROM api.stays_view s;
SELECT m.id, m.name IS NOT NULL AS name, m.moorage, m.moorage_id, m.duration, m.stayed_at, m.stayed_at_id, m.arrived IS NOT NULL AS arrived, m.departed IS NOT NULL AS departed, m.notes FROM api.stays_view AS m ORDER BY id ASC;

\echo 'api.moorages'
--SELECT * FROM api.moorages m;
--SELECT m.id, m.vessel_id IS NOT NULL AS vessel_id, m.name, m.country, m.stay_code, m.stay_duration, m.reference_count, m.latitude, m.longitude, m.geog, m.home_flag, m.notes FROM api.moorages AS m;
SELECT m.id, m.vessel_id IS NOT NULL AS vessel_id, m.name, m.country, m.stay_code, m.latitude, m.longitude, m.geog, m.home_flag, m.notes FROM api.moorages AS m ORDER BY id ASC;

\echo 'api.moorages_view'
SELECT * FROM api.moorages_view;

\echo 'api.moorage_view'
--SELECT * FROM api.moorage_view;
SELECT m.id, m.name, default_stay, m.latitude, m.longitude, m.geog, m.home, m.notes, logs_count, stays_count, stay_first_seen_id, stay_last_seen_id, stay_first_seen IS NOT NULL AS stay_first_seen, stay_last_seen IS NOT NULL AS stay_last_seen FROM api.moorage_view m ORDER BY id ASC;
