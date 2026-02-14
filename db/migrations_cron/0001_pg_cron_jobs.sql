-- +goose Up
-- +goose StatementBegin

-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- -----------------------------------------------------------------------------
-- Monitoring jobs
-- -----------------------------------------------------------------------------
SELECT cron.schedule_in_database (
    'cron_monitor_offline',
    '*/11 * * * *',
    'SELECT public.cron_process_monitor_offline_fn();',
    'signalk'
);

SELECT cron.schedule_in_database (
    'cron_monitor_online',
    '*/10 * * * *',
    'SELECT public.cron_process_monitor_online_fn();',
    'signalk'
);

-- -----------------------------------------------------------------------------
-- Logbook / stay processing
-- -----------------------------------------------------------------------------
SELECT cron.schedule_in_database (
    'cron_pre_logbook',
    '*/5 * * * *',
    'SELECT public.cron_process_pre_logbook_fn();',
    'signalk'
);

SELECT cron.schedule_in_database (
    'cron_new_logbook',
    '*/6 * * * *',
    'SELECT public.cron_process_new_logbook_fn();',
    'signalk'
);

SELECT cron.schedule_in_database (
    'cron_new_stay',
    '*/7 * * * *',
    'SELECT public.cron_process_new_stay_fn();',
    'signalk'
);

SELECT cron.schedule_in_database (
    'cron_post_logbook',
    '*/7 * * * *',
    'SELECT public.cron_process_post_logbook_fn();',
    'signalk'
);

-- -----------------------------------------------------------------------------
-- Notifications & alerts
-- -----------------------------------------------------------------------------
SELECT cron.schedule_in_database (
    'cron_new_notification',
    '*/1 * * * *',
    'SELECT public.cron_process_new_notification_fn();',
    'signalk'
);

SELECT cron.schedule_in_database (
    'cron_alerts',
    '*/11 * * * *',
    'SELECT public.cron_alerts_fn();',
    'signalk'
);

-- -----------------------------------------------------------------------------
-- External integrations
-- -----------------------------------------------------------------------------
SELECT cron.schedule_in_database (
    'cron_grafana',
    '*/5 * * * *',
    'SELECT public.cron_process_grafana_fn();',
    'signalk'
);

SELECT cron.schedule_in_database (
    'cron_windy',
    '*/5 * * * *',
    'SELECT public.cron_windy_fn();',
    'signalk'
);

-- -----------------------------------------------------------------------------
-- Maintenance / cleanup
-- -----------------------------------------------------------------------------
SELECT cron.schedule_in_database (
    'cron_prune_otp',
    '*/15 * * * *',
    'SELECT public.cron_prune_otp_fn();',
    'signalk'
);

-- -----------------------------------------------------------------------------
-- Discovery / metadata checks
-- -----------------------------------------------------------------------------
SELECT cron.schedule_in_database (
    'cron_autodiscovery',
    '*/20 * * * *',
    'SELECT public.cron_process_autodiscovery_fn();',
    'signalk'
);

-- +goose StatementEnd