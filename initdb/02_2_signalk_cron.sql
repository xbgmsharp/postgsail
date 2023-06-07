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
    RAISE NOTICE 'cron_process_new_logbook_fn';
    FOR process_rec in 
        SELECT * FROM process_queue 
            WHERE channel = 'new_logbook' AND processed IS NULL
            ORDER BY stored ASC
    LOOP
        RAISE NOTICE '-> cron_process_new_logbook_fn [%]', process_rec.payload;
        -- update logbook
        PERFORM process_logbook_queue_fn(process_rec.payload::INTEGER);
        -- update process_queue table , processed
        UPDATE process_queue 
            SET 
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_new_logbook_fn updated process_queue table [%]', process_rec.id;
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
    RAISE NOTICE 'cron_process_new_stay_fn';
    FOR process_rec in 
        SELECT * FROM process_queue 
            WHERE channel = 'new_stay' AND processed IS NULL
            ORDER BY stored ASC
    LOOP
        RAISE NOTICE '-> cron_process_new_stay_fn [%]', process_rec.payload;
        -- update stay
        PERFORM process_stay_queue_fn(process_rec.payload::INTEGER);
        -- update process_queue table , processed
        UPDATE process_queue 
            SET 
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_new_stay_fn updated process_queue table [%]', process_rec.id;
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
    RAISE NOTICE 'cron_process_new_moorage_fn';
    FOR process_rec in 
        SELECT * FROM process_queue 
            WHERE channel = 'new_moorage' AND processed IS NULL
            ORDER BY stored ASC
    LOOP
        RAISE NOTICE '-> cron_process_new_moorage_fn [%]', process_rec.payload;
        -- update moorage
        PERFORM process_moorage_queue_fn(process_rec.payload::INTEGER);
        -- update process_queue table , processed
        UPDATE process_queue 
            SET 
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_new_moorage_fn updated process_queue table [%]', process_rec.id;
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

        IF metadata_rec.client_id IS NULL OR metadata_rec.client_id = '' THEN
            RAISE WARNING '-> cron_process_monitor_offline_fn invalid metadata record client_id %', client_id;
            RAISE EXCEPTION 'Invalid metadata'
                USING HINT = 'Unknow client_id';
            RETURN;
        END IF;
        PERFORM set_config('vessel.client_id', metadata_rec.client_id, false);
        RAISE DEBUG '-> DEBUG cron_process_monitor_offline_fn vessel.client_id %', current_setting('vessel.client_id', false);
        RAISE NOTICE '-> cron_process_monitor_offline_fn updated api.metadata table to inactive for [%] [%]', metadata_rec.id, metadata_rec.client_id;

        -- Gather email and pushover app settings
        --app_settings = get_app_settings_fn();
        -- Gather user settings
        user_settings := get_user_settings_from_clientid_fn(metadata_rec.client_id::TEXT);
        RAISE DEBUG '-> cron_process_monitor_offline_fn get_user_settings_from_clientid_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('monitor_offline'::TEXT, user_settings::JSONB);
        --PERFORM send_email_py_fn('monitor_offline'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('monitor_offline'::TEXT, user_settings::JSONB, app_settings::JSONB);
        -- log/insert/update process_queue table with processed
        INSERT INTO process_queue
            (channel, payload, stored, processed) 
            VALUES 
                ('monitoring_offline', metadata_rec.id, metadata_rec.interval, now())
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

        IF metadata_rec.client_id IS NULL OR metadata_rec.client_id = '' THEN
            RAISE WARNING '-> cron_process_monitor_online_fn invalid metadata record client_id %', client_id;
            RAISE EXCEPTION 'Invalid metadata'
                USING HINT = 'Unknow client_id';
            RETURN;
        END IF;
        PERFORM set_config('vessel.client_id', metadata_rec.client_id, false);
        RAISE DEBUG '-> DEBUG cron_process_monitor_online_fn vessel.client_id %', current_setting('vessel.client_id', false);

        -- Gather email and pushover app settings
        --app_settings = get_app_settings_fn();
        -- Gather user settings
        user_settings := get_user_settings_from_clientid_fn(metadata_rec.client_id::TEXT);
        RAISE DEBUG '-> DEBUG cron_process_monitor_online_fn get_user_settings_from_clientid_fn [%]', user_settings;
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
    IS 'init by pg_cron to check for new account pending update, if so perform process_account_queue_fn';

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
    IS 'init by pg_cron to check for new account otp pending update, if so perform process_account_otp_validation_queue_fn';

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
    IS 'init by pg_cron to check for new vessel pending update, if so perform process_vessel_queue_fn';

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
CREATE FUNCTION cron_vaccum_fn() RETURNS void AS $$
-- ERROR:  VACUUM cannot be executed from a function
declare
begin
    -- Vacuum
    RAISE NOTICE 'cron_vaccum_fn';
    VACUUM (FULL, VERBOSE, ANALYZE, INDEX_CLEANUP) api.logbook;
    VACUUM (FULL, VERBOSE, ANALYZE, INDEX_CLEANUP) api.stays;
    VACUUM (FULL, VERBOSE, ANALYZE, INDEX_CLEANUP) api.moorages;
    VACUUM (FULL, VERBOSE, ANALYZE, INDEX_CLEANUP) api.metrics;
    VACUUM (FULL, VERBOSE, ANALYZE, INDEX_CLEANUP) api.metadata;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION 
    public.cron_vaccum_fn
    IS 'init by pg_cron to full vaccum tables on schema api';

-- CRON for Vacuum database
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
    public.cron_vaccum_fn
    IS 'init by pg_cron to cleanup job_run_details table on schema public postgras db';
