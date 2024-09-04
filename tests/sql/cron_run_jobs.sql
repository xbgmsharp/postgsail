---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

-- Check the number of process pending
\echo 'Check the number of process pending'
-- Should be 24
SELECT count(*) as jobs from public.process_queue pq where pq.processed is null;
--set role scheduler
SELECT public.run_cron_jobs();
-- Check any pending job
SELECT count(*) as any_pending_jobs from public.process_queue pq where pq.processed is null;

-- Check the number of metrics entries
\echo 'Check the number of metrics entries'
SELECT count(*) as metrics_count from api.metrics;
