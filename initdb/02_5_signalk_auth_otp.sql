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
        otp_pass VARCHAR(10) := NULL;
    BEGIN
        IF email IS NULL OR _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;
        SELECT lower(a.email) INTO _email_check FROM auth.accounts a WHERE a.email = _email;
        IF _email_check IS NULL THEN
            RETURN NULL;
        END IF;
        --SELECT substr(gen_random_uuid()::text, 1, 6) INTO otp_pass;
        SELECT generate_uid_fn(6) INTO otp_pass;
        INSERT INTO auth.otp (user_email, otp_pass) VALUES (_email_check, otp_pass);
        RETURN otp_pass;
    END;
$generate_otp$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.generate_otp_fn
    IS 'Generate otp code';

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
            -- Set user email into env to allow RLS update 
            PERFORM set_config('user.email', _email, false);
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

CREATE OR REPLACE FUNCTION api.pushover_subscribe_link_fn(IN email TEXT, OUT pushover_link JSON) RETURNS JSON
AS $pushover_subscribe_link$
	DECLARE
        app_url text;
        otp_code text;
        pushover_app_url text;
        success text;
        failure text;
    BEGIN
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
        otp_code := api.generate_otp_fn(email);
        -- On sucess redirect to to API endpoing
        SELECT CONCAT(
            '?success=',
            urlencode(CONCAT(app_url,'/api/rpc/pushover_fn?token=')),
            otp_code)
            INTO success;
        -- On failure redirect to user settings, where he does come from
        SELECT CONCAT(
            '&failure=',
            urlencode(CONCAT(app_url,'/settings'))
            ) INTO failure;
        SELECT json_build_object( 'link', CONCAT(pushover_app_url, success, failure)) INTO pushover_link;
    END;
$pushover_subscribe_link$ language plpgsql security definer;

-- Pushover Subscription API
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
            -- Pushover send a notificataion when sucesssfull with the description of the app
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
    IS 'Store pushover_user_key into user preferences if valid token/otp';

-- Telegram OTP Validation
-- Expose as an API endpoint
DROP FUNCTION IF EXISTS api.telegram_fn;
CREATE OR REPLACE FUNCTION api.telegram_fn(IN token TEXT, IN telegram_obj TEXT) RETURNS BOOLEAN
AS $telegram$
	DECLARE
		_email TEXT := NULL;
		_updated BOOLEAN := False;
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
            SELECT api.update_user_preferences_fn('{telegram}'::TEXT, telegram_obj::TEXT) INTO _updated;
            -- Delete token when validated
            DELETE FROM auth.otp
                WHERE user_email = _email;
            -- Send Notification async
            INSERT INTO process_queue (channel, payload, stored)
                VALUES ('telegram_valid', _email, now());
			RETURN _updated;
		END IF;
		RETURN False;
    END;
$telegram$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.telegram_fn
    IS 'Store telegram chat details into user preferences if valid token/otp';

-- Telegram user validation
DROP FUNCTION IF EXISTS auth.telegram_user_exists_fn;
CREATE OR REPLACE FUNCTION auth.telegram_user_exists_fn(IN email TEXT, IN chat_id BIGINT) RETURNS BOOLEAN
AS $telegram_user_exists$
	declare
		_email CITEXT := email;
		_chat_id BIGINT := chat_id;
    BEGIN
        IF _email IS NULL OR _chat_id IS NULL THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;
        -- Does user and telegram obj
        SELECT preferences->'telegram'->'id' INTO _chat_id
            FROM auth.accounts a
            WHERE a.email = _email
			AND cast(preferences->'telegram'->'id' as BIGINT) = _chat_id::BIGINT;
        IF FOUND THEN
            RETURN TRUE;
       	END IF;
        RETURN FALSE;
    END;
$telegram_user_exists$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    auth.telegram_user_exists_fn
    IS 'Check if user exist base on email and telegram obj preferences';

-- Telegram bot JWT auth
-- Expose as an API endpoint
-- Avoid sending a password so use email and chat_id as key pair
DROP FUNCTION IF EXISTS api.bot(text,BIGINT);
CREATE OR REPLACE FUNCTION api.bot(IN email TEXT, IN chat_id BIGINT) RETURNS auth.jwt_token
AS $telegram_bot$
	declare
		_email TEXT := email;
		_chat_id BIGINT := chat_id;
        _exist BOOLEAN := False;
        result auth.jwt_token;
        app_jwt_secret text;
    BEGIN
        IF _email IS NULL OR _chat_id IS NULL THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;
        -- check email and _chat_id
        select auth.telegram_user_exists_fn(_email, _chat_id) into _exist;
        if _exist is null or _exist <> True then
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        end if;

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
                extract(epoch from now())::integer + 60*60 as exp
            ) r
            into result;
        return result;
    END;
$telegram_bot$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.bot
    IS 'Generate a JWT user_role token from email for telegram bot';

-- Telegram chat_id Session validation
DROP FUNCTION IF EXISTS auth.telegram_session_exists_fn;
CREATE OR REPLACE FUNCTION auth.telegram_session_exists_fn(IN chat_id BIGINT) RETURNS auth.jwt_token
AS $telegram_session_exists$
	declare
		_email CITEXT := NULL;
		_chat_id BIGINT := chat_id;
        result auth.jwt_token;
        app_jwt_secret text;
    BEGIN
        IF _chat_id IS NULL THEN
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;

        -- Find user emial based on telegram chat_id
        SELECT preferences->'telegram'->'id' INTO _email
            FROM auth.accounts a
            WHERE cast(preferences->'telegram'->'id' as BIGINT) = _chat_id::BIGINT;
        IF NOT FOUND then
            RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
        END IF;

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
                extract(epoch from now())::integer + 60*60 as exp
            ) r
            into result;
        return result;
    END;
$telegram_session_exists$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    auth.telegram_session_exists_fn
    IS 'Check if session/user exist based on chat_id to renew telegram user to bot jwt token';
