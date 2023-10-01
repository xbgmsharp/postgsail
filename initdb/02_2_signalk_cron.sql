---------------------------------------------------------------------------
-- cron job function helpers on public schema
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- Check for new logbook pending update
CREATE FUNCTION cron_process_new_logbook_fn() RETURNS void AS $$
declare
    process_rec record;
begin
    -- Check for new logbook pending update
    RAISE NOTICE 'cron_process_new_logbook_fn init loop';
    FOR process_rec in 
        SELECT * FROM process_queue 
            WHERE channel = 'new_logbook' AND processed IS NULL
            ORDER BY stored ASC LIMIT 100
    LOOP
        RAISE NOTICE 'cron_process_new_logbook_fn processing queue [%] for logbook id [%]', process_rec.id, process_rec.payload;
        -- update logbook
        PERFORM process_logbook_queue_fn(process_rec.payload::INTEGER);
        -- update process_queue table , processed
        UPDATE process_queue 
            SET 
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE 'cron_process_new_logbook_fn processed queue [%] for logbook id [%]', process_rec.id, process_rec.payload;
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_new_logbook_fn
    IS 'init by pg_cron to check for new logbook pending update, if so perform process_logbook_queue_fn';

-- Check for new stay pending update
CREATE FUNCTION cron_process_new_stay_fn() RETURNS void AS $$
declare
    process_rec record;
begin
    -- Check for new stay pending update
    RAISE NOTICE 'cron_process_new_stay_fn init loop';
    FOR process_rec in 
        SELECT * FROM process_queue 
            WHERE channel = 'new_stay' AND processed IS NULL
            ORDER BY stored ASC LIMIT 100
    LOOP
        RAISE NOTICE 'cron_process_new_stay_fn processing queue [%] for stay id [%]', process_rec.id, process_rec.payload;
        -- update stay
        PERFORM process_stay_queue_fn(process_rec.payload::INTEGER);
        -- update process_queue table , processed
        UPDATE process_queue 
            SET 
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE 'cron_process_new_stay_fn processed queue [%] for stay id [%]', process_rec.id, process_rec.payload;
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_new_stay_fn
    IS 'init by pg_cron to check for new stay pending update, if so perform process_stay_queue_fn';

-- Check for new moorage pending update
DROP FUNCTION IF EXISTS cron_process_new_moorage_fn;
CREATE OR REPLACE FUNCTION cron_process_new_moorage_fn() RETURNS void AS $$
declare
    process_rec record;
begin
    -- Check for new moorage pending update
    RAISE NOTICE 'cron_process_new_moorage_fn init loop';
    FOR process_rec in 
        SELECT * FROM process_queue 
            WHERE channel = 'new_moorage' AND processed IS NULL
            ORDER BY stored ASC LIMIT 100
    LOOP
        RAISE NOTICE 'cron_process_new_moorage_fn processing queue [%] for moorage id [%]', process_rec.id, process_rec.payload;
        -- update moorage
        PERFORM process_moorage_queue_fn(process_rec.payload::INTEGER);
        -- update process_queue table , processed
        UPDATE process_queue 
            SET 
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE 'cron_process_new_moorage_fn processed queue [%] for moorage id [%]', process_rec.id, process_rec.payload;
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_new_moorage_fn
    IS 'init by pg_cron to check for new moorage pending update, if so perform process_moorage_queue_fn';

-- CRON Monitor offline pending notification
create function cron_process_monitor_offline_fn() RETURNS void AS $$
declare
    metadata_rec record;
    process_id integer;
    user_settings jsonb;
    app_settings jsonb;
begin
    -- Check metadata last_update > 1h + cron_time(10m)
    RAISE NOTICE 'cron_process_monitor_offline_fn';
    FOR metadata_rec in 
        SELECT
            *, 
            NOW() AT TIME ZONE 'UTC' as now, 
            NOW() AT TIME ZONE 'UTC' - INTERVAL '70 MINUTES' as interval
        FROM api.metadata m
        WHERE 
            m.time < NOW() AT TIME ZONE 'UTC' - INTERVAL '70 MINUTES'
            AND active = True
        ORDER BY m.time desc
    LOOP
        RAISE NOTICE '-> cron_process_monitor_offline_fn metadata_id [%]', metadata_rec.id;
        -- update api.metadata table, set active to bool false
        UPDATE api.metadata
            SET 
                active = False
            WHERE id = metadata_rec.id;

        IF metadata_rec.vessel_id IS NULL OR metadata_rec.vessel_id = '' THEN
            RAISE WARNING '-> cron_process_monitor_offline_fn invalid metadata record vessel_id %', vessel_id;
            RAISE EXCEPTION 'Invalid metadata'
                USING HINT = 'Unknown vessel_id';
            RETURN;
        END IF;
        PERFORM set_config('vessel.id', metadata_rec.vessel_id, false);
        RAISE DEBUG '-> DEBUG cron_process_monitor_offline_fn vessel.id %', current_setting('vessel.id', false);
        RAISE NOTICE 'cron_process_monitor_offline_fn updated api.metadata table to inactive for [%] [%]', metadata_rec.id, metadata_rec.vessel_id;

        -- Gather email and pushover app settings
        --app_settings = get_app_settings_fn();
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(metadata_rec.vessel_id::TEXT);
        RAISE DEBUG '-> cron_process_monitor_offline_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('monitor_offline'::TEXT, user_settings::JSONB);
        --PERFORM send_email_py_fn('monitor_offline'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('monitor_offline'::TEXT, user_settings::JSONB, app_settings::JSONB);
        -- log/insert/update process_queue table with processed
        INSERT INTO process_queue
            (channel, payload, stored, processed, ref_id)
            VALUES 
                ('monitoring_offline', metadata_rec.id, metadata_rec.interval, now(), metadata_rec.vessel_id)
            RETURNING id INTO process_id;
        RAISE NOTICE '-> cron_process_monitor_offline_fn updated process_queue table [%]', process_id;
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_monitor_offline_fn
    IS 'init by pg_cron to monitor offline pending notification, if so perform send_email o send_pushover base on user preferences';

-- CRON for monitor back online pending notification
DROP FUNCTION IF EXISTS cron_process_monitor_online_fn;
CREATE FUNCTION cron_process_monitor_online_fn() RETURNS void AS $$
declare
    process_rec record;
    metadata_rec record;
    user_settings jsonb;
    app_settings jsonb;
begin
    -- Check for monitor online pending notification
    RAISE NOTICE 'cron_process_monitor_online_fn';
    FOR process_rec in 
        SELECT * from process_queue 
            where channel = 'monitoring_online' and processed is null
            order by stored asc
    LOOP
        RAISE NOTICE '-> cron_process_monitor_online_fn metadata_id [%]', process_rec.payload;
        SELECT * INTO metadata_rec 
            FROM api.metadata
            WHERE id = process_rec.payload::INTEGER;

        IF metadata_rec.vessel_id IS NULL OR metadata_rec.vessel_id = '' THEN
            RAISE WARNING '-> cron_process_monitor_online_fn invalid metadata record vessel_id %', vessel_id;
            RAISE EXCEPTION 'Invalid metadata'
                USING HINT = 'Unknown vessel_id';
            RETURN;
        END IF;
        PERFORM set_config('vessel.id', metadata_rec.vessel_id, false);
        RAISE DEBUG '-> DEBUG cron_process_monitor_online_fn vessel_id %', current_setting('vessel.id', false);

        -- Gather email and pushover app settings
        --app_settings = get_app_settings_fn();
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(metadata_rec.vessel_id::TEXT);
        RAISE DEBUG '-> DEBUG cron_process_monitor_online_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('monitor_online'::TEXT, user_settings::JSONB);
        --PERFORM send_email_py_fn('monitor_online'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('monitor_online'::TEXT, user_settings::JSONB, app_settings::JSONB);
        -- update process_queue entry as processed
        UPDATE process_queue 
            SET 
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_monitor_online_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_monitor_online_fn 
    IS 'init by pg_cron to monitor back online pending notification, if so perform send_email or send_pushover base on user preferences';

-- CRON for new account pending notification
CREATE FUNCTION cron_process_new_account_fn() RETURNS void AS $$
declare
    process_rec record;
begin
    -- Check for new account pending update
    RAISE NOTICE 'cron_process_new_account_fn';
    FOR process_rec in 
        SELECT * from process_queue 
            where channel = 'new_account' and processed is null
            order by stored asc
    LOOP
        RAISE NOTICE '-> cron_process_new_account_fn [%]', process_rec.payload;
        -- update account
        PERFORM process_account_queue_fn(process_rec.payload::TEXT);
        -- update process_queue entry as processed
        UPDATE process_queue 
            SET 
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_new_account_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_new_account_fn 
    IS 'deprecated, init by pg_cron to check for new account pending update, if so perform process_account_queue_fn';

-- CRON for new account pending otp validation notification
CREATE FUNCTION cron_process_new_account_otp_validation_fn() RETURNS void AS $$
declare
    process_rec record;
begin
    -- Check for new account pending update
    RAISE NOTICE 'cron_process_new_account_otp_validation_fn';
    FOR process_rec in
        SELECT * from process_queue
            where channel = 'new_account_otp' and processed is null
            order by stored asc
    LOOP
        RAISE NOTICE '-> cron_process_new_account_otp_validation_fn [%]', process_rec.payload;
        -- update account
        PERFORM process_account_otp_validation_queue_fn(process_rec.payload::TEXT);
        -- update process_queue entry as processed
        UPDATE process_queue
            SET
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_new_account_otp_validation_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_new_account_otp_validation_fn
    IS 'deprecated, init by pg_cron to check for new account otp pending update, if so perform process_account_otp_validation_queue_fn';

-- CRON for new vessel pending notification
CREATE FUNCTION cron_process_new_vessel_fn() RETURNS void AS $$
declare
    process_rec record;
begin
    -- Check for new vessel pending update
    RAISE NOTICE 'cron_process_new_vessel_fn';
    FOR process_rec in 
        SELECT * from process_queue 
            where channel = 'new_vessel' and processed is null
            order by stored asc
    LOOP
        RAISE NOTICE '-> cron_process_new_vessel_fn [%]', process_rec.payload;
        -- update vessel
        PERFORM process_vessel_queue_fn(process_rec.payload::TEXT);
        -- update process_queue entry as processed
        UPDATE process_queue 
            SET 
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_new_vessel_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION 
    public.cron_process_new_vessel_fn 
    IS 'deprecated, init by pg_cron to check for new vessel pending update, if so perform process_vessel_queue_fn';

-- CRON for new event notification
CREATE FUNCTION cron_process_new_notification_fn() RETURNS void AS $$
declare
    process_rec record;
begin
    -- Check for new event notification pending update
    RAISE NOTICE 'cron_process_new_notification_fn';
    FOR process_rec in
        SELECT * FROM process_queue
            WHERE
            (channel = 'new_account' OR channel = 'new_vessel' OR channel = 'email_otp')
                and processed is null
            order by stored asc
    LOOP
        RAISE NOTICE '-> cron_process_new_notification_fn for [%]', process_rec.payload;
        -- process_notification_queue
        PERFORM process_notification_queue_fn(process_rec.payload::TEXT, process_rec.channel::TEXT);
        -- update process_queue entry as processed
        UPDATE process_queue
            SET
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_new_notification_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_new_notification_fn
    IS 'init by pg_cron to check for new event pending notifications, if so perform process_notification_queue_fn';

-- CRON for Vacuum database
CREATE FUNCTION cron_vacuum_fn() RETURNS void AS $$
-- ERROR:  VACUUM cannot be executed from a function
declare
begin
    -- Vacuum
    RAISE NOTICE 'cron_vacuum_fn';
    VACUUM (FULL, VERBOSE, ANALYZE, INDEX_CLEANUP) api.logbook;
    VACUUM (FULL, VERBOSE, ANALYZE, INDEX_CLEANUP) api.stays;
    VACUUM (FULL, VERBOSE, ANALYZE, INDEX_CLEANUP) api.moorages;
    VACUUM (FULL, VERBOSE, ANALYZE, INDEX_CLEANUP) api.metrics;
    VACUUM (FULL, VERBOSE, ANALYZE, INDEX_CLEANUP) api.metadata;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION 
    public.cron_vacuum_fn
    IS 'init by pg_cron to full vacuum tables on schema api';

-- CRON for clean up job details logs
CREATE FUNCTION job_run_details_cleanup_fn() RETURNS void AS $$
DECLARE
BEGIN
    -- Remove job run log older than 3 months
    RAISE NOTICE 'job_run_details_cleanup_fn';
    DELETE FROM postgres.cron.job_run_details
        WHERE start_time <= NOW() AT TIME ZONE 'UTC' - INTERVAL '91 DAYS';
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.job_run_details_cleanup_fn
    IS 'init by pg_cron to cleanup job_run_details table on schema public postgres db';

-- CRON for alerts notification
CREATE FUNCTION cron_process_alerts_fn() RETURNS void AS $$
DECLARE
    alert_rec record;
BEGIN
    -- Check for new event notification pending update
    RAISE NOTICE 'cron_process_alerts_fn';
    FOR alert_rec in
        SELECT
            a.user_id,a.email,v.vessel_id
            FROM auth.accounts a, auth.vessels v, api.metadata m
            WHERE m.vessel_id = v.vessel_id
                AND a.email = v.owner_email
                AND (preferences->'alerting'->'enabled')::boolean = false
    LOOP
        RAISE NOTICE '-> cron_process_alert_rec_fn for [%]', alert_rec;
    END LOOP;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_alerts_fn
    IS 'init by pg_cron to check for alerts';

-- CRON for no vessel notification
CREATE FUNCTION cron_process_no_vessel_fn() RETURNS void AS $no_vessel$
DECLARE
    no_vessel record;
    user_settings jsonb;
BEGIN
    -- Check for user with no vessel register
    RAISE NOTICE 'cron_process_no_vessel_fn';
    FOR no_vessel in
        SELECT a.user_id,a.email,a.first
            FROM auth.accounts a
            WHERE NOT EXISTS (
                SELECT *
                FROM auth.vessels v
                WHERE v.owner_email = a.email)
    LOOP
        RAISE NOTICE '-> cron_process_no_vessel_rec_fn for [%]', no_vessel;
        SELECT json_build_object('email', no_vessel.email, 'recipient', a.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_no_vessel_rec_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('no_vessel'::TEXT, user_settings::JSONB);
    END LOOP;
END;
$no_vessel$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_no_vessel_fn
    IS 'init by pg_cron, check for user with no vessel register then send notification';

-- CRON for no metadata notification
CREATE FUNCTION cron_process_no_metadata_fn() RETURNS void AS $no_metadata$
DECLARE
    no_metadata_rec record;
    user_settings jsonb;
BEGIN
    -- Check for vessel register but with no metadata
    RAISE NOTICE 'cron_process_no_metadata_fn';
    FOR no_metadata_rec in
        SELECT
            a.user_id,a.email,a.first
            FROM auth.accounts a, auth.vessels v
            WHERE NOT EXISTS (
                SELECT *
                FROM  api.metadata m
                WHERE v.vessel_id = m.vessel_id) AND v.owner_email = a.email
    LOOP
        RAISE NOTICE '-> cron_process_no_activity_rec_fn for [%]', no_metadata_rec;
        SELECT json_build_object('email', no_metadata_rec.email, 'recipient', a.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_no_metadata_rec_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('no_metadata'::TEXT, user_settings::JSONB);
    END LOOP;
END;
$no_metadata$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_no_metadata_fn
    IS 'init by pg_cron, check for vessel with no metadata then send notification';

-- CRON for no activity notification
CREATE FUNCTION cron_process_no_activity_fn() RETURNS void AS $no_activity$
DECLARE
    no_activity_rec record;
    user_settings jsonb;
BEGIN
    -- Check for vessel with no activity for more than 200 days
    RAISE NOTICE 'cron_process_no_activity_fn';
    FOR no_activity_rec in
        SELECT
            v.owner_email,m.name,m.vessel_id,m.time
            FROM api.metadata m
            LEFT JOIN auth.vessels v ON v.vessel_id = m.vessel_id
            WHERE m.time <= NOW() AT TIME ZONE 'UTC' - INTERVAL '200 DAYS'
    LOOP
        RAISE NOTICE '-> cron_process_no_activity_rec_fn for [%]', no_activity_rec;
        SELECT json_build_object('email', no_activity_rec.owner_email, 'recipient', a.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_no_activity_rec_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('no_activity'::TEXT, user_settings::JSONB);
    END LOOP;
END;
$no_activity$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.cron_process_no_activity_fn
    IS 'init by pg_cron, check for vessel with no activity for more than 200 days then send notification';
