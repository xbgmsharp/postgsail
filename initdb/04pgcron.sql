---------------------------------------------------------------------------
-- pg_cron async job
--
--CREATE DATABASE cron_database;
--CREATE SCHEMA IF NOT EXISTS cron;
--\c cron_database
\c postgres

CREATE EXTENSION IF NOT EXISTS pg_cron; -- provides a simple cron-based job scheduler for PostgreSQL
-- TRUNCATE table jobs
--TRUNCATE TABLE cron.job CONTINUE IDENTITY RESTRICT;

-- Create a every 5 minutes or minute job cron_process_new_logbook_fn ??
SELECT cron.schedule('cron_new_logbook', '*/5 * * * *', 'select public.cron_process_new_logbook_fn()');
--UPDATE cron.job SET database = 'signalk' where jobname = 'cron_new_logbook';

-- Create a every 5 minute job cron_process_new_stay_fn
SELECT cron.schedule('cron_new_stay', '*/6 * * * *', 'select public.cron_process_new_stay_fn()');
--UPDATE cron.job SET database = 'signalk' where jobname = 'cron_new_stay';

-- Create a every 6 minute job cron_process_new_moorage_fn, delay from stay to give time to generate geo reverse location, eg: name
--SELECT cron.schedule('cron_new_moorage', '*/7 * * * *', 'select public.cron_process_new_moorage_fn()');
--UPDATE cron.job SET database = 'signalk' where jobname = 'cron_new_moorage';

-- Create a every 10 minute job cron_process_monitor_offline_fn
SELECT cron.schedule('cron_monitor_offline', '*/11 * * * *', 'select public.cron_process_monitor_offline_fn()');
--UPDATE cron.job SET database = 'signalk' where jobname = 'cron_monitor_offline';

-- Create a every 10 minute job cron_process_monitor_online_fn
SELECT cron.schedule('cron_monitor_online', '*/10 * * * *', 'select public.cron_process_monitor_online_fn()');
--UPDATE cron.job SET database = 'signalk' where jobname = 'cron_monitor_online';

-- Create a every 5 minute job cron_process_new_account_fn
--SELECT cron.schedule('cron_new_account', '*/5 * * * *', 'select public.cron_process_new_account_fn()');
--UPDATE cron.job SET database = 'signalk' where jobname = 'cron_new_account';

-- Create a every 5 minute job cron_process_new_vessel_fn
--SELECT cron.schedule('cron_new_vessel', '*/5 * * * *', 'select public.cron_process_new_vessel_fn()');
--UPDATE cron.job SET database = 'signalk' where jobname = 'cron_new_vessel';

-- Create a every 6 minute job cron_process_new_account_otp_validation_queue_fn, delay from cron_new_account
--SELECT cron.schedule('cron_new_account_otp', '*/6 * * * *', 'select public.cron_process_new_account_otp_validation_fn()');
--UPDATE cron.job SET database = 'signalk' where jobname = 'cron_new_account_otp';

-- Notification
-- Create a every 1 minute job cron_process_new_notification_queue_fn, new_account, new_vessel, _new_account_otp
SELECT cron.schedule('cron_new_notification', '*/1 * * * *', 'select public.cron_process_new_notification_fn()');
--UPDATE cron.job SET database = 'signalk' where jobname = 'cron_new_notification';

-- Maintenance
-- Vacuum database schema api at "At 01:31 on Sunday."
SELECT cron.schedule('cron_vacuum_api', '31 1 * * 0', 'VACUUM (FULL, VERBOSE, ANALYZE, INDEX_CLEANUP) api.logbook,api.stays,api.moorages,api.metadata,api.metrics;');
-- Vacuum database schema auth at "At 01:01 on Sunday."
SELECT cron.schedule('cron_vacuum_auth', '1 1 * * 0', 'VACUUM (FULL, VERBOSE, ANALYZE, INDEX_CLEANUP) auth.accounts,auth.vessels,auth.otp;');
-- Remove old jobs log at "At 02:02 on Sunday."
SELECT cron.schedule('job_run_details_cleanup', '2 2 * * 0', 'select public.job_run_details_cleanup_fn()');
-- Rebuilding indexes schema api at "first day of each month at 23:15."
SELECT cron.schedule('cron_reindex_api', '15 23 1 * *', 'REINDEX TABLE api.logbook; REINDEX TABLE api.stays; REINDEX TABLE api.moorages; REINDEX TABLE api.metadata; REINDEX TABLE api.metrics;');
-- Rebuilding indexes schema auth at "first day of each month at 23:01."
SELECT cron.schedule('cron_reindex_auth', '1 23 1 * *', 'REINDEX TABLE auth.accounts; REINDEX TABLE auth.vessels; REINDEX TABLE auth.otp;');
-- Any other maintenance require?

-- OTP
-- Create a every 15 minute job cron_process_prune_otp_fn
SELECT cron.schedule('cron_prune_otp', '*/15 * * * *', 'select public.cron_process_prune_otp_fn()');

-- Alerts
-- Create a every 11 minute job cron_process_alerts_fn
--SELECT cron.schedule('cron_alerts', '*/11 * * * *', 'select public.cron_process_alerts_fn()');

-- Notifications/Reminders of no vessel & no metadata & no activity
-- At 08:05 on Sunday.
-- At 08:05 on every 4th day-of-month if it's on Sunday.
SELECT cron.schedule('cron_no_vessel', '5 8 */4 * 0', 'select public.cron_process_no_vessel_fn()');
SELECT cron.schedule('cron_no_metadata', '5 8 */4 * 0', 'select public.cron_process_no_metadata_fn()');
SELECT cron.schedule('cron_no_activity', '5 8 */4 * 0', 'select public.cron_process_no_activity_fn()');

-- Cron job settings
UPDATE cron.job SET database = 'signalk';
UPDATE cron.job SET username = 'username'; -- TODO update to scheduler, pending process_queue update
--UPDATE cron.job SET username = 'username' where jobname = 'cron_vacuum'; -- TODO Update to superuser for vaccuum permissions
UPDATE cron.job SET nodename = '/var/run/postgresql/'; -- VS default localhost ??
UPDATE cron.job	SET database = 'postgresql' WHERE jobname = 'job_run_details_cleanup';
-- check job lists
SELECT * FROM cron.job;
-- unschedule by job id
--SELECT cron.unschedule(1);
-- unschedule by job name
--SELECT cron.unschedule('cron_new_logbook');
-- TRUNCATE TABLE cron.job_run_details
--TRUNCATE TABLE cron.job_run_details CONTINUE IDENTITY RESTRICT;
-- check job log
SELECT * FROM cron.job_run_details ORDER BY end_time DESC;
-- DEBUG Disable all
UPDATE cron.job SET active = False;