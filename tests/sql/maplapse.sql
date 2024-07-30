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
SELECT set_config('vessel.id', :'vessel_id_kapla', false) IS NOT NULL as vessel_id;
-- insert fake request maplapse
\echo 'Insert fake request maplapse'
SELECT api.maplapse_record_fn('Kapla,?start_log=1&end_log=1&height=100vh');

-- maplapse_role
SET ROLE maplapse_role;

\echo 'GET pending maplapse task'
SELECT id as maplapse_id from process_queue where channel = 'maplapse_video' and processed is null order by stored asc limit 1 \gset
SELECT count(id) from process_queue where channel = 'maplapse_video' and processed is null limit 1;

\echo 'Update process on completion'
UPDATE process_queue SET processed = NOW() WHERE id = :'maplapse_id';

\echo 'Insert video availability notification in process queue'
INSERT INTO process_queue ("channel", "payload", "ref_id", "stored") VALUES ('new_video', CONCAT('video_', :'vessel_id_kapla'::TEXT, '_1', '_1.mp4'), :'vessel_id_kapla'::TEXT, NOW());
