---------------------------------------------------------------------------
-- signalk db auth schema
-- View and Function that have dependency with auth schema

-- List current database
select current_database();

-- connect to the DB
\c signalk

DROP TABLE IF EXISTS auth.otp;
CREATE TABLE IF NOT EXISTS auth.otp (
  -- update email type to CITEXT, https://www.postgresql.org/docs/current/citext.html
  user_email CITEXT NOT NULL PRIMARY KEY REFERENCES auth.accounts(email) ON DELETE RESTRICT,
  otp_pass VARCHAR(10) NOT NULL,
  otp_timestamp TIMESTAMP WITHOUT TIME ZONE DEFAULT NOW(),
  otp_tries SMALLINT NOT NULL DEFAULT '0'
);
-- Description
COMMENT ON TABLE
    auth.otp
    IS 'Stores temporal otp code for up to 15 minutes';
-- Indexes
CREATE INDEX otp_pass_idx ON auth.otp (otp_pass);
CREATE INDEX otp_user_email_idx ON auth.otp (user_email);

DROP FUNCTION IF EXISTS public.generate_uid_fn;
CREATE OR REPLACE FUNCTION public.generate_uid_fn(size INT) RETURNS TEXT
AS $generate_uid_fn$
    DECLARE
        characters TEXT := '0123456789';
        bytes BYTEA := gen_random_bytes(size);
        l INT := length(characters);
        i INT := 0;
        output TEXT := '';
    BEGIN
        WHILE i < size LOOP
            output := output || substr(characters, get_byte(bytes, i) % l + 1, 1);
            i := i + 1;
        END LOOP;
        RETURN output;
    END;
$generate_uid_fn$ LANGUAGE plpgsql VOLATILE;
-- Description
COMMENT ON FUNCTION
    public.generate_uid_fn
    IS 'Generate a random digit';

-- gerenate a OTP code by email
-- Expose as an API endpoint
DROP FUNCTION IF EXISTS api.generate_otp_fn;
CREATE OR REPLACE FUNCTION api.generate_otp_fn(IN email TEXT) RETURNS TEXT
AS $generate_otp$
    DECLARE
        _email CITEXT := email;
        _email_check TEXT := NULL;
        _otp_pass VARCHAR(10) := NULL;
    BEGIN
        IF email IS NULL OR _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;
        SELECT lower(a.email) INTO _email_check FROM auth.accounts a WHERE a.email = _email;
        IF _email_check IS NULL THEN
            RETURN NULL;
        END IF;
        --SELECT substr(gen_random_uuid()::text, 1, 6) INTO otp_pass;
        SELECT generate_uid_fn(6) INTO _otp_pass;
        -- upsert - Insert or update otp code on conflit
        INSERT INTO auth.otp (user_email, otp_pass)
                VALUES (_email_check, _otp_pass)
                ON CONFLICT (user_email) DO UPDATE SET otp_pass = _otp_pass, otp_timestamp = NOW();
        RETURN _otp_pass;
    END;
$generate_otp$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.generate_otp_fn
    IS 'Generate otp code';

DROP FUNCTION IF EXISTS api.recover;
CREATE OR REPLACE FUNCTION api.recover(in email text) returns BOOLEAN
AS $recover_fn$
	DECLARE
        _email CITEXT := email;
        _user_id TEXT := NULL;
        otp_pass TEXT := NULL;
        _reset_qs TEXT := NULL;
        user_settings jsonb := NULL;
    BEGIN
        IF _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'Invalid input'
                USING HINT = 'Check your parameter';
        END IF;
        SELECT user_id INTO _user_id FROM auth.accounts a WHERE a.email = _email;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invalid input'
                USING HINT = 'Check your parameter';
        END IF;
        -- Generate OTP
        otp_pass := api.generate_otp_fn(email);
        SELECT CONCAT('uuid=', _user_id, '&token=', otp_pass) INTO _reset_qs;
        -- Send email/notifications
        user_settings := '{"email": "' || _email || '", "reset_qs": "' || _reset_qs || '"}';
        PERFORM send_notification_fn('email_reset'::TEXT, user_settings::JSONB);
        RETURN TRUE;
    END;
$recover_fn$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.recover
    IS 'Send recover password email to reset password';

DROP FUNCTION IF EXISTS api.reset;
CREATE OR REPLACE FUNCTION api.reset(in pass text, in token text, in uuid text) returns BOOLEAN
AS $reset_fn$
	DECLARE
        _email TEXT := NULL;
    BEGIN
         -- Check parameters
        IF token IS NULL OR uuid IS NULL OR pass IS NULL THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;
        -- Verify token
        SELECT auth.verify_otp_fn(token) INTO _email;
		IF _email IS NOT NULL THEN
            SELECT email INTO _email FROM auth.accounts WHERE user_id = uuid;
            IF _email IS NULL THEN
                RETURN False;
            END IF;
            -- Set user new password
            UPDATE auth.accounts
                SET pass = pass
                WHERE email = _email;
	        -- Enable email_validation into user preferences
            PERFORM api.update_user_preferences_fn('{email_valid}'::TEXT, True::TEXT);
            -- Enable email_notifications
            PERFORM api.update_user_preferences_fn('{email_notifications}'::TEXT, True::TEXT);
            -- Delete token when validated
            DELETE FROM auth.otp
                WHERE user_email = _email;
			RETURN True;
		END IF;
		RETURN False;
    END;
$reset_fn$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.reset
    IS 'Reset user password base on otp code and user_id send by email from api.recover';

DROP FUNCTION IF EXISTS auth.verify_otp_fn;
CREATE OR REPLACE FUNCTION auth.verify_otp_fn(IN token TEXT) RETURNS TEXT
AS $verify_otp$
	DECLARE
        email TEXT := NULL;
    BEGIN
        IF token IS NULL THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;
        -- Token is valid 15 minutes
        SELECT user_email INTO email
            FROM auth.otp
            WHERE otp_timestamp > NOW() AT TIME ZONE 'UTC' - INTERVAL '15 MINUTES'
                AND otp_tries < 3 
                AND otp_pass = token;
        RETURN email;
    END;
$verify_otp$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    auth.verify_otp_fn
    IS 'Verify OTP';

-- CRON to purge OTP older than 15 minutes
DROP FUNCTION IF EXISTS public.cron_process_prune_otp_fn;
CREATE OR REPLACE FUNCTION public.cron_process_prune_otp_fn() RETURNS void
AS $$
    DECLARE
        otp_rec record;
    BEGIN
        -- Purge OTP older than 15 minutes
        RAISE NOTICE 'cron_process_prune_otp_fn';
        FOR otp_rec in
            SELECT *
            FROM auth.otp
            WHERE otp_timestamp < NOW() AT TIME ZONE 'UTC' - INTERVAL '15 MINUTES'
            ORDER BY otp_timestamp desc
        LOOP
            RAISE NOTICE '-> cron_process_prune_otp_fn deleting expired otp for user [%]', otp_rec.user_email;
            -- remove entry
            DELETE FROM auth.otp
                WHERE user_email = otp_rec.user_email;
            RAISE NOTICE '-> cron_process_prune_otp_fn deleted expire otp for user [%]', otp_rec.user_email;
        END LOOP;
    END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION 
    public.cron_process_prune_otp_fn
    IS 'init by pg_cron to purge older than 15 minutes OTP token';

-- Email OTP validation
-- Expose as an API endpoint
DROP FUNCTION IF EXISTS api.email_fn;
CREATE OR REPLACE FUNCTION api.email_fn(IN token TEXT) RETURNS BOOLEAN
AS $email_validation$
	DECLARE
		_email TEXT := NULL;
    BEGIN
        -- Check parameters
        IF token IS NULL THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;
        -- Verify token
        SELECT auth.verify_otp_fn(token) INTO _email;
		IF _email IS NOT NULL THEN
            -- Check the email JWT token match the OTP email
            IF current_setting('user.email', true) <> _email THEN
                RETURN False;
            END IF;
            -- Set user email into env to allow RLS update 
            --PERFORM set_config('user.email', _email, false);
	        -- Enable email_validation into user preferences
            PERFORM api.update_user_preferences_fn('{email_valid}'::TEXT, True::TEXT);
            -- Enable email_notifications
            PERFORM api.update_user_preferences_fn('{email_notifications}'::TEXT, True::TEXT);
            -- Delete token when validated
            DELETE FROM auth.otp
                WHERE user_email = _email;
            -- Disable to reduce spam
            -- Send Notification async
            --INSERT INTO process_queue (channel, payload, stored)
            --    VALUES ('email_valid', _email, now());
            RETURN True;
		END IF;
		RETURN False;
    END;
$email_validation$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.email_fn
    IS 'Store email_valid into user preferences if valid token/otp';

-- Pushover Subscription API
-- Web-Based Subscription Process
-- https://pushover.net/api/subscriptions#web
-- Expose as an API endpoint
CREATE OR REPLACE FUNCTION api.pushover_subscribe_link_fn(OUT pushover_link JSON) RETURNS JSON
AS $pushover_subscribe_link$
	DECLARE
        app_url text;
        otp_code text;
        pushover_app_url text;
        success text;
        failure text;
        email text := current_setting('user.email', true);
    BEGIN
--https://pushover.net/api/subscriptions#web
-- "https://pushover.net/subscribe/PostgSail-23uvrho1d5y6n3e"
-- + "?success=" + urlencode("https://beta.openplotter.cloud/api/rpc/pushover_fn?token=" + generate_otp_fn({{email}}))
-- + "&failure=" + urlencode("https://beta.openplotter.cloud/settings");
        -- get app_url
        SELECT
            value INTO app_url
        FROM
            public.app_settings
        WHERE
            name = 'app.url';
        -- get pushover url subscribe
        SELECT
            value INTO pushover_app_url
        FROM
            public.app_settings
        WHERE
            name = 'app.pushover_app_url';
        -- Generate OTP
        otp_code := api.generate_otp_fn(email);
        -- On success redirect to API endpoint
        SELECT CONCAT(
            '?success=',
            public.urlescape_py_fn(CONCAT(app_url,'/pushover?token=')),
            otp_code)
            INTO success;
        -- On failure redirect to user settings, where he does come from
        SELECT CONCAT(
            '&failure=',
            public.urlescape_py_fn(CONCAT(app_url,'/profile'))
            ) INTO failure;
        SELECT json_build_object('link', CONCAT(pushover_app_url, success, failure)) INTO pushover_link;
    END;
$pushover_subscribe_link$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.pushover_subscribe_link_fn
    IS 'Generate Pushover subscription link';

-- Confirm Pushover Subscription
-- Web-Based Subscription Process
-- https://pushover.net/api/subscriptions#web
-- Expose as an API endpoint
DROP FUNCTION IF EXISTS api.pushover_fn;
CREATE OR REPLACE FUNCTION api.pushover_fn(IN token TEXT, IN pushover_user_key TEXT) RETURNS BOOLEAN
AS $pushover$
	DECLARE
		_email TEXT := NULL;
    BEGIN
        -- Check parameters
        IF token IS NULL OR pushover_user_key IS NULL THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;
        -- Verify token
        SELECT auth.verify_otp_fn(token) INTO _email;
		IF _email IS NOT NULL THEN
            -- Set user email into env to allow RLS update
            PERFORM set_config('user.email', _email, false);
            -- Add pushover_user_key into user preferences
            PERFORM api.update_user_preferences_fn('{pushover_user_key}'::TEXT, pushover_user_key::TEXT);
            -- Enable phone_notifications
            PERFORM api.update_user_preferences_fn('{phone_notifications}'::TEXT, True::TEXT);
            -- Delete token when validated
            DELETE FROM auth.otp
                WHERE user_email = _email;
            -- Disable Notification because
            -- Pushover send a notification when sucesssful with the description of the app
            --
            -- Send Notification async
            --INSERT INTO process_queue (channel, payload, stored)
            --    VALUES ('pushover_valid', _email, now());
			RETURN True;
		END IF;
		RETURN False;
    END;
$pushover$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.pushover_fn
    IS 'Confirm Pushover Subscription and store pushover_user_key into user preferences if provide a valid OTP token';

-- Telegram OTP Validation
-- Expose as an API endpoint
DROP FUNCTION IF EXISTS api.telegram_fn;
CREATE OR REPLACE FUNCTION api.telegram_fn(IN token TEXT, IN telegram_obj TEXT) RETURNS BOOLEAN
AS $telegram$
    DECLARE
        _email TEXT := NULL;
        user_settings jsonb;
    BEGIN
        -- Check parameters
        IF token IS NULL OR telegram_obj IS NULL THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;
        -- Verify token
        SELECT auth.verify_otp_fn(token) INTO _email;
		IF _email IS NOT NULL THEN
            -- Set user email into env to allow RLS update
            PERFORM set_config('user.email', _email, false);
	        -- Add telegram obj into user preferences
            PERFORM api.update_user_preferences_fn('{telegram}'::TEXT, telegram_obj::TEXT);
            -- Delete token when validated
            DELETE FROM auth.otp
                WHERE user_email = _email;
            -- Send Notification async
            --INSERT INTO process_queue (channel, payload, stored)
            --    VALUES ('telegram_valid', _email, now());
			RETURN True;
		END IF;
		RETURN False;
    END;
$telegram$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.telegram_fn
    IS 'Confirm telegram user and store telegram chat details into user preferences if provide a valid OTP token';

-- Telegram user validation
DROP FUNCTION IF EXISTS auth.telegram_user_exists_fn;
CREATE OR REPLACE FUNCTION auth.telegram_user_exists_fn(IN email TEXT, IN user_id BIGINT) RETURNS BOOLEAN
AS $telegram_user_exists$
    DECLARE
        _email CITEXT := email;
        _user_id BIGINT := user_id;
    BEGIN
        IF _email IS NULL OR _chat_id IS NULL THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;
        -- Does user and telegram obj
        SELECT preferences->'telegram'->'from'->'id' INTO _user_id
            FROM auth.accounts a
            WHERE a.email = _email
                AND cast(preferences->'telegram'->'from'->'id' as BIGINT) = _user_id::BIGINT;
        IF FOUND THEN
            RETURN TRUE;
       	END IF;
        RETURN FALSE;
    END;
$telegram_user_exists$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    auth.telegram_user_exists_fn
    IS 'Check if user exist based on email and user_id';

-- Telegram otp validation
DROP FUNCTION IF EXISTS api.telegram_otp_fn;
CREATE OR REPLACE FUNCTION api.telegram_otp_fn(IN email TEXT, OUT otp_code TEXT) RETURNS TEXT
AS $telegram_otp$
    DECLARE
        _email CITEXT := email;
        user_settings jsonb := NULL;
    BEGIN
        IF _email IS NULL THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;
        -- Generate token
        otp_code := api.generate_otp_fn(_email);
        IF otp_code IS NOT NULL THEN
            -- Set user email into env to allow RLS update
            PERFORM set_config('user.email', _email, false);
            -- Send Notification
            user_settings := '{"email": "' || _email || '", "otp_code": "' || otp_code || '"}';
            PERFORM send_notification_fn('telegram_otp'::TEXT, user_settings::JSONB);
        END IF;
    END;
$telegram_otp$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.telegram_otp_fn
    IS 'Telegram otp generation';

-- Telegram JWT auth
-- Expose as an API endpoint
-- Avoid sending a password so use email and chat_id as key pair
DROP FUNCTION IF EXISTS api.telegram;
CREATE OR REPLACE FUNCTION api.telegram(IN user_id BIGINT, IN email TEXT DEFAULT NULL) RETURNS auth.jwt_token
AS $telegram_jwt$
    DECLARE
        _email TEXT := email;
        _user_id BIGINT := user_id;
        _uid TEXT := NULL;
        _exist BOOLEAN := False;
        result auth.jwt_token;
        app_jwt_secret text;
    BEGIN
        IF _user_id IS NULL THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;

        -- Check _user_id
        SELECT auth.telegram_session_exists_fn(_user_id) into _exist;
        IF _exist IS NULL OR _exist <> True THEN
            --RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
            RETURN NULL;
        END IF;

        -- Get email and user_id
        SELECT a.email,a.user_id INTO _email,_uid
            FROM auth.accounts a
            WHERE cast(preferences->'telegram'->'from'->'id' as BIGINT) = _user_id::BIGINT;

        -- Get app_jwt_secret
        SELECT value INTO app_jwt_secret
            FROM app_settings
            WHERE name = 'app.jwt_secret';

        -- Generate JWT token, force user_role
        select jwt.sign(
            row_to_json(r)::json, app_jwt_secret
            ) as token
            from (
                select 'user_role' as role,
                (select lower(_email)) as email,
                _uid as uid,
                extract(epoch from now())::integer + 60*60 as exp
            ) r
            into result;
        return result;
    END;
$telegram_jwt$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.telegram
    IS 'Generate a JWT user_role token based on chat_id from telegram';

-- Telegram chat_id session validation
DROP FUNCTION IF EXISTS auth.telegram_session_exists_fn;
CREATE OR REPLACE FUNCTION auth.telegram_session_exists_fn(IN user_id BIGINT) RETURNS BOOLEAN
AS $telegram_session_exists$
    DECLARE
        _id BIGINT := NULL;
        _user_id BIGINT := user_id;
        _email TEXT := NULL;
    BEGIN
        IF user_id IS NULL THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;

        -- Find user email based on telegram chat_id
        SELECT preferences->'telegram'->'from'->'id' INTO _id
            FROM auth.accounts a
            WHERE cast(preferences->'telegram'->'from'->'id' as BIGINT) = _user_id::BIGINT;
        IF FOUND THEN
            RETURN True;
        END IF;
        RETURN FALSE;
    END;
$telegram_session_exists$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    auth.telegram_session_exists_fn
    IS 'Check if session/user exist based on user_id';
