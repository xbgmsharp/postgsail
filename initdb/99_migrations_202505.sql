---------------------------------------------------------------------------
-- Copyright 2021-2025 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration May 2025
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Timing mode is enabled'
\timing

\echo 'Force timezone, just in case'
set timezone to 'UTC';

-- Update email_templates table, add new autodiscovery template
INSERT INTO public.email_templates ("name",email_subject,email_content,pushover_title,pushover_message)
	VALUES ('autodiscovery','PostgSail Personalize Your Boat Profile',E'Hello __RECIPIENT__,\nGood news! Your boat is now connected! ⚓\nWe\’ve updated your SignalK path mapping, so you might want to take a quick look and make sure everything\’s set up just right. You can check it out here: __APP_URL__/boat/mapping.\n\nWhile you\'re at it, why not add a personal touch to your Postgsail profile and let the world see your amazing boat?\n📸 Add a great photo – whether it\’s out on the water or chilling at the dock.\n🛠️ Enter the make and model – so everything\’s accurate.\n🧭 Upload your polar - it\’s super easy.\nHappy sailing! 🌊\n','PostgSail autodiscovery',E'We updated your signalk path mapping.');

-- Update metadata table, add IP address column, remove id column, update vessel_id default
ALTER TABLE api.metadata DROP COLUMN IF EXISTS id;
ALTER TABLE api.metadata ALTER COLUMN vessel_id SET DEFAULT current_setting('vessel.id'::text, false);
ALTER TABLE api.metadata ADD COLUMN IF NOT EXISTS ip TEXT NULL;
ALTER TABLE api.metadata ALTER COLUMN mmsi TYPE text USING mmsi::text;
COMMENT ON COLUMN api.metadata.ip IS 'Store vessel ip address';

-- Add metadata_ext, new table to store vessel extended metadata from user
CREATE TABLE api.metadata_ext (
  vessel_id text PRIMARY KEY
             DEFAULT current_setting('vessel.id'::text, false)
             REFERENCES api.metadata(vessel_id) ON DELETE RESTRICT,
  make_model text NULL,
  polar text NULL, -- Store polar data in CSV notation as used on ORC sailboat data
  polar_updated_at timestamptz NULL,
  image_b64 text NULL, -- Store user boat image in b64 format
  image bytea NULL, -- Store user boat image in bytea format
  image_type text NULL, -- Store user boat image type in text format
  image_url TEXT NULL, -- Store user boat image url in text format
  image_updated_at timestamptz NULL,
  created_at timestamptz DEFAULT now() NOT NULL
);
-- Description
COMMENT ON TABLE
    api.metadata_ext
    IS 'Stores metadata extended information for the vessel from user';

-- Comments
COMMENT ON COLUMN api.metadata_ext.polar IS 'Store polar data in CSV notation as used on ORC sailboat data';
COMMENT ON COLUMN api.metadata_ext.image IS 'Store user boat image in bytea format';
COMMENT ON COLUMN api.metadata_ext.image_type IS 'Store user boat image type in text format';
COMMENT ON COLUMN api.metadata_ext.make_model IS 'Store user make & model in text format';

-- Add stays_ext, new table to store vessel extended stays from user
CREATE TABLE api.stays_ext (
    vessel_id text NOT NULL
             DEFAULT current_setting('vessel.id'::text, false)
             REFERENCES api.metadata(vessel_id) ON DELETE RESTRICT,
    stay_id INT PRIMARY KEY REFERENCES api.stays(id) ON DELETE RESTRICT,
    image bytea NULL, -- Store user boat image in bytea format
    image_b64 text NULL, -- Store user boat image in b64 format
    image_type text NULL, -- Store user boat image type in text format
    image_url TEXT NULL, -- Store user boat image url in text format
    image_updated_at timestamptz NULL,
    created_at timestamptz DEFAULT now() NOT NULL
);
-- Description
COMMENT ON TABLE
    api.stays_ext
    IS 'Stores stays extended information for the stays from user';

-- Comments
COMMENT ON COLUMN api.stays_ext.image IS 'Store stays image in bytea format';
COMMENT ON COLUMN api.stays_ext.image_type IS 'Store stays image type in text format';

-- Cleanup trigger on api schema
DROP FUNCTION IF EXISTS api.update_metadata_ext_added_at_fn();
DROP TRIGGER IF EXISTS metadata_update_configuration_trigger ON api.metadata;
DROP FUNCTION IF EXISTS api.update_metadata_configuration();

-- Move trigger on public schema
CREATE OR REPLACE FUNCTION public.update_metadata_configuration_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- Only update configuration if it's a JSONB object and has changed
    IF NEW.configuration IS NOT NULL 
       AND NEW.configuration IS DISTINCT FROM OLD.configuration
       AND jsonb_typeof(NEW.configuration) = 'object' THEN

        NEW.configuration := jsonb_set(
            NEW.configuration,
            '{update_at}',
            to_jsonb(to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
        );
    END IF;

    RETURN NEW;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.update_metadata_configuration_trigger_fn() IS 'Update the configuration field with current date in ISO format';

-- Update trigger to use public schema
create trigger metadata_update_configuration_trigger before
update
    on
    api.metadata for each row execute function public.update_metadata_configuration_trigger_fn();
-- Description
COMMENT ON TRIGGER metadata_update_configuration_trigger ON api.metadata IS 'BEFORE UPDATE ON api.metadata run function api.update_metadata_configuration tp update the configuration field with current date in ISO format';

-- Create trigger to update polar_updated_at and image_updated_at accordingly.
CREATE OR REPLACE FUNCTION public.update_metadata_ext_added_at_trigger_fn()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.polar IS DISTINCT FROM OLD.polar THEN
    NEW.polar_updated_at := NOW();
  END IF;

  IF NEW.image IS DISTINCT FROM OLD.image THEN
    NEW.image_updated_at := NOW();
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION public.update_metadata_ext_added_at_trigger_fn() IS 'Update polar_updated_at and/or image_updated_at when polar and/or image is update';

CREATE TRIGGER metadata_ext_update_added_at_trigger
BEFORE INSERT OR UPDATE ON api.metadata_ext
FOR EACH ROW
EXECUTE FUNCTION public.update_metadata_ext_added_at_trigger_fn();
-- Description
COMMENT ON TRIGGER metadata_ext_update_added_at_trigger ON api.metadata_ext IS 'BEFORE INSERT OR UPDATE ON api.metadata_ext run function update_metadata_ext_added_at_trigger_fn';

-- Create update_metadata_ext_decode_base64_image_trigger_fn to decode base64 image
CREATE OR REPLACE FUNCTION public.update_metadata_ext_decode_base64_image_trigger_fn()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if image_b64 contains a base64 string to decode
    IF NEW.image_b64 IS NOT NULL AND NEW.image_b64 IS DISTINCT FROM OLD.image_b64 THEN
        BEGIN
            -- Decode base64 string and assign to image column (BYTEA type)
            NEW.image := decode(NEW.image_b64, 'base64');

            -- Clear the base64 text column - Not working
            --NEW.image_b64 := NULL;
        EXCEPTION
            WHEN others THEN
                RAISE EXCEPTION 'Failed to decode base64 image string: %', SQLERRM;
        END;
    END IF;

    -- Return the modified row with the decoded image
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION public.update_metadata_ext_decode_base64_image_trigger_fn() IS 'Decode base64 image string to bytea format';

CREATE TRIGGER metadata_ext_decode_image_trigger
  BEFORE INSERT OR UPDATE ON api.metadata_ext
  FOR EACH ROW
  EXECUTE FUNCTION public.update_metadata_ext_decode_base64_image_trigger_fn();
-- Description
COMMENT ON TRIGGER metadata_ext_decode_image_trigger ON api.metadata_ext IS 'BEFORE INSERT OR UPDATE ON api.metadata_ext run function update_metadata_ext_decode_base64_image_trigger_fn';

-- refactor metadata_upsert_trigger_fn with the new metadata schema, remove id and check valid mmsi.
CREATE OR REPLACE FUNCTION public.metadata_upsert_trigger_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    v_vessel_id TEXT := current_setting('vessel.id', true);
    headers   JSON := current_setting('request.headers', true)::json;
    client_ip TEXT := coalesce(headers->>'x-client-ip', NULL);
    metadata_record RECORD;
BEGIN
    -- run only if from vessel as vessel_role
    --RAISE NOTICE 'metadata_upsert_trigger_fn request.jwt.claims role [%] [%]', current_role, current_setting('request.jwt.claims', true)::json->>'role';
    IF current_role IS DISTINCT FROM 'vessel_role' THEN
        RAISE NOTICE 'metadata_upsert_trigger_fn skipped: role is not vessel_role or is NULL role:[%]', current_role;
        RETURN NEW; -- Skip further processing
    END IF;
    -- If monitoring set offline or configuration changed, skip processing
    -- active state is set by the monitoring service
    -- configuration is set by the user_role
    IF TG_OP = 'UPDATE'
        AND (
            (OLD.configuration IS DISTINCT FROM NEW.configuration AND NEW.configuration IS NOT NULL)
            OR (OLD.active IS DISTINCT FROM NEW.active AND NEW.active IS FALSE)
        ) THEN
        RAISE NOTICE 'metadata_upsert_trigger_fn skipped for update on configuration or active only';
        RETURN NEW; -- Skip further processing
    END IF;

    -- Ensure vessel_id is set in NEW
    IF NEW.vessel_id IS NULL THEN
      NEW.vessel_id := v_vessel_id;
    END IF;

    -- Look for existing metadata
    SELECT active INTO metadata_record
      FROM api.metadata
      WHERE vessel_id = v_vessel_id;

    --RAISE NOTICE 'metadata_upsert_trigger_fn update vessel FOUND:[%] metadata:[%]', FOUND, metadata_record;
    -- PostgREST - trigger runs twice INSERT on conflict UPDATE
    IF FOUND AND NOT metadata_record.active AND TG_OP = 'UPDATE' THEN
      -- Send notification as the vessel was inactive
      RAISE NOTICE 'metadata_upsert_trigger_fn set monitoring_online as the vessel was inactive';
      INSERT INTO process_queue (channel, payload, stored, ref_id)
        VALUES ('monitoring_online', v_vessel_id, NOW(), v_vessel_id);
    ELSIF NOT FOUND AND TG_OP = 'INSERT' THEN
      -- First insert, Send notification as the vessel is active
      RAISE NOTICE 'metadata_upsert_trigger_fn First insert, set monitoring_online as the vessel is now active';
      INSERT INTO process_queue (channel, payload, stored, ref_id)
        VALUES ('monitoring_online', v_vessel_id, NOW(), v_vessel_id);
    END IF;

    -- Check if mmsi is a valid 9-digit number
    NEW.mmsi := regexp_replace(NEW.mmsi::TEXT, '\s', '', 'g');  -- remove all whitespace
    IF NEW.mmsi::TEXT !~ '^\d{9}$' THEN
      NEW.mmsi := NULL;
    END IF;

    -- Normalize and overwrite vessel metadata
    NEW.platform := REGEXP_REPLACE(NEW.platform, '[^a-zA-Z0-9\(\) ]', '', 'g');
    NEW.time := NOW();
    NEW.active := TRUE;
    NEW.ip := client_ip;
    RETURN NEW; -- Insert or Update vessel metadata
END;
$function$;
-- Description
COMMENT ON FUNCTION public.metadata_upsert_trigger_fn() IS 'process metadata from vessel, upsert';

DROP TRIGGER metadata_notification_trigger ON api.metadata;
DROP FUNCTION public.metadata_notification_trigger_fn;
DROP TRIGGER metadata_upsert_trigger ON api.metadata;
CREATE TRIGGER metadata_upsert_trigger
  BEFORE INSERT OR UPDATE ON api.metadata
  FOR EACH ROW
  EXECUTE FUNCTION public.metadata_upsert_trigger_fn();
-- Description
COMMENT ON TRIGGER metadata_upsert_trigger ON api.metadata IS 'BEFORE INSERT OR UPDATE ON api.metadata run function metadata_upsert_trigger_fn';

--DROP FUNCTION public.metadata_grafana_trigger_fn();
-- Update metadata_grafana_trigger_fn with the new metadata schema, remove id.
CREATE OR REPLACE FUNCTION public.metadata_grafana_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
    DECLARE
    BEGIN
        RAISE NOTICE 'metadata_grafana_trigger_fn [%]', NEW;
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('grafana', NEW.vessel_id, now(), NEW.vessel_id);
        RETURN NULL;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION public.metadata_grafana_trigger_fn() IS 'process metadata grafana provisioning from vessel';

-- Create update_stays_ext_decode_base64_image_trigger_fn to decode base64 image
CREATE OR REPLACE FUNCTION public.update_stays_ext_decode_base64_image_trigger_fn()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if image_b64 contains a base64 string to decode
    IF NEW.image_b64 IS NOT NULL AND NEW.image_b64 IS DISTINCT FROM OLD.image_b64 THEN
        BEGIN
            -- Decode base64 string and assign to image column (BYTEA type)
            NEW.image := decode(NEW.image_b64, 'base64');

            -- Clear the base64 text column - Not working
            --NEW.image_b64 := NULL;
        EXCEPTION
            WHEN others THEN
                RAISE EXCEPTION 'Failed to decode base64 image string: %', SQLERRM;
        END;
    END IF;

    -- Return the modified row with the decoded image
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION public.update_stays_ext_decode_base64_image_trigger_fn() IS 'Decode base64 image string to bytea format';

CREATE TRIGGER stays_ext_decode_image_trigger
  BEFORE INSERT OR UPDATE ON api.stays_ext
  FOR EACH ROW
  EXECUTE FUNCTION public.update_stays_ext_decode_base64_image_trigger_fn();
-- Description
COMMENT ON TRIGGER stays_ext_decode_image_trigger ON api.stays_ext IS 'BEFORE INSERT OR UPDATE ON api.stays_ext run function update_stays_ext_decode_base64_image_trigger_fn';

-- Create function public.autodiscovery_config_fn, to generate autodiscovery monitoring configuration
CREATE OR REPLACE FUNCTION public.autodiscovery_config_fn(input_json jsonb)
RETURNS jsonb AS $$
DECLARE
    key TEXT;
    path TEXT;
    result_json jsonb := '{}';
    latest_metrics jsonb;
    alt_path TEXT;
BEGIN
    -- Get the most recent metrics row
    SELECT metrics INTO latest_metrics
      FROM api.metrics
      WHERE vessel_id = current_setting('vessel.id', false)
      ORDER BY time DESC
      LIMIT 1;

    IF NOT FOUND THEN
        RAISE WARNING 'autodiscovery_config_fn, No metrics found for vessel_id: %', current_setting('vessel.id', false);
        RETURN result_json; -- Return empty JSON if no metrics found
    END IF;

    -- Iterate over each key and path in the input
    FOR key, path IN
        SELECT je.key, je.value
        FROM jsonb_each_text(input_json) AS je(key, value)
    LOOP
        -- If the path exists, keep it
        IF latest_metrics ? path THEN
            result_json := result_json || jsonb_build_object(key, path);

        -- If path doesn't exist and it's 'voltageKey', search for an alternative
        ELSIF key = 'voltageKey' THEN
            SELECT metric_key INTO alt_path
            FROM jsonb_object_keys(latest_metrics) AS metric_key
            WHERE metric_key ILIKE 'electrical.batteries.%.voltage'
            LIMIT 1;

            IF alt_path IS NOT NULL THEN
                result_json := result_json || jsonb_build_object(key, alt_path);
            END IF;

        ELSIF key = 'solarPowerKey' THEN
            SELECT metric_key INTO alt_path
            FROM jsonb_object_keys(latest_metrics) AS metric_key
            WHERE metric_key ILIKE 'electrical.solar.%.panelPower'
            LIMIT 1;

            IF alt_path IS NOT NULL THEN
                result_json := result_json || jsonb_build_object(key, alt_path);
            END IF;

        ELSIF key = 'solarVoltageKey' THEN
            SELECT metric_key INTO alt_path
            FROM jsonb_object_keys(latest_metrics) AS metric_key
            WHERE metric_key ILIKE 'electrical.solar.%.panelVoltage'
            LIMIT 1;

            IF alt_path IS NOT NULL THEN
                result_json := result_json || jsonb_build_object(key, alt_path);
            END IF;

        ELSIF key = 'stateOfChargeKey' THEN
            SELECT metric_key INTO alt_path
            FROM jsonb_object_keys(latest_metrics) AS metric_key
            WHERE metric_key ILIKE 'electrical.batteries.%.stateOfCharge'
            LIMIT 1;

            IF alt_path IS NOT NULL THEN
                result_json := result_json || jsonb_build_object(key, alt_path);
            END IF;

        ELSIF key = 'tankLevelKey' THEN
            SELECT metric_key INTO alt_path
            FROM jsonb_object_keys(latest_metrics) AS metric_key
            WHERE metric_key ILIKE 'tanks.fuel.%.currentLevel'
            LIMIT 1;

            IF alt_path IS NOT NULL THEN
                result_json := result_json || jsonb_build_object(key, alt_path);
            END IF;

        ELSIF key = 'outsideHumidityKey' THEN
            SELECT metric_key INTO alt_path
            FROM jsonb_object_keys(latest_metrics) AS metric_key
            WHERE metric_key ILIKE 'environment.%.humidity'
            LIMIT 1;

            IF alt_path IS NOT NULL THEN
                result_json := result_json || jsonb_build_object(key, alt_path);
            END IF;

        ELSIF key = 'outsidePressureKey' THEN
            SELECT metric_key INTO alt_path
            FROM jsonb_object_keys(latest_metrics) AS metric_key
            WHERE metric_key ILIKE 'environment.%.pressure'
            LIMIT 1;

            IF alt_path IS NOT NULL THEN
                result_json := result_json || jsonb_build_object(key, alt_path);
            END IF;

        ELSIF key = 'outsideTemperatureKey' THEN
            SELECT metric_key INTO alt_path
            FROM jsonb_object_keys(latest_metrics) AS metric_key
            WHERE metric_key ILIKE 'environment.%.temperature'
            LIMIT 1;

            IF alt_path IS NOT NULL THEN
                result_json := result_json || jsonb_build_object(key, alt_path);
            END IF;

        END IF;

    END LOOP;

    RETURN result_json;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION public.autodiscovery_config_fn(input_json jsonb) IS 'Clean the JSONB column by removing keys that are not present in the latest metrics row.';

-- Update metadata_autodiscovery_trigger_fn with the new metadata schema, remove id.
CREATE OR REPLACE FUNCTION public.metadata_autodiscovery_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
    DECLARE
    BEGIN
        RAISE NOTICE 'metadata_autodiscovery_trigger_fn [%]', NEW;
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('autodiscovery', NEW.vessel_id, NOW(), NEW.vessel_id);
        RETURN NULL;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION public.metadata_autodiscovery_trigger_fn() IS 'process metadata autodiscovery config provisioning from vessel';

-- Create trigger to process metadata for autodiscovery_config provisioning
CREATE TRIGGER metadata_autodiscovery_trigger
  AFTER INSERT ON api.metadata
  FOR EACH ROW
  EXECUTE FUNCTION public.metadata_autodiscovery_trigger_fn();
-- Description
COMMENT ON TRIGGER metadata_autodiscovery_trigger ON api.metadata IS 'AFTER INSERT ON api.metadata run function metadata_autodiscovery_trigger_fn for later signalk mapping provisioning on new vessel';

-- Create cron_process_autodiscovery_fn to process autodiscovery config provisioning
CREATE OR REPLACE FUNCTION public.cron_process_autodiscovery_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    process_rec record;
    data_rec record;
    latest_metrics record;
    app_settings jsonb;
    user_settings jsonb;
    config jsonb;
    config_default jsonb := '{
        "depthKey": "environment.depth.belowTransducer",
        "voltageKey": "electrical.batteries.House.voltage",
        "windSpeedKey": "environment.wind.speedTrue",
        "solarPowerKey": "electrical.solar.Main.panelPower",
        "solarVoltageKey": "electrical.solar.Main.panelVoltage",
        "stateOfChargeKey": "electrical.batteries.House.capacity.stateOfCharge",
        "windDirectionKey": "environment.wind.directionTrue",
        "insideHumidityKey": "environment.outside.humidity",
        "insidePressureKey": "environment.inside.mainCabin.pressure",
        "outsideHumidityKey": "environment.outside.humidity",
        "outsidePressureKey": "environment.outside.pressure",
        "waterTemperatureKey": "environment.water.temperature",
        "insideTemperatureKey": "environment.inside.temperature",
        "outsideTemperatureKey": "environment.outside.temperature"
      }'::JSONB;
BEGIN
    -- We run autodiscovery provisioning only after the first received vessel metadata
    -- Check for new vessel metadata pending autodiscovery provisioning
    RAISE NOTICE 'cron_process_autodiscovery_fn';
    FOR process_rec in
        SELECT * from process_queue
            where channel = 'autodiscovery' and processed is null
            order by stored asc
    LOOP
        RAISE NOTICE '-> cron_process_autodiscovery_fn [%]', process_rec.payload;
        -- Gather url from app settings
        app_settings := get_app_settings_fn();
        -- Get vessel details base on vessel id
        SELECT
            v.owner_email, coalesce(m.name, v.name) as name, m.vessel_id, m.configuration into data_rec
            FROM auth.vessels v
            LEFT JOIN api.metadata m ON v.vessel_id = m.vessel_id
            WHERE m.vessel_id = process_rec.payload::TEXT;
        IF data_rec.vessel_id IS NULL OR data_rec.name IS NULL THEN
            RAISE WARNING '-> DEBUG cron_process_autodiscovery_fn error [%]', data_rec;
            RETURN;
        END IF;
        PERFORM set_config('vessel.id', data_rec.vessel_id::TEXT, false);
        SELECT metrics INTO latest_metrics
            FROM api.metrics
            WHERE vessel_id = current_setting('vessel.id', false)
            ORDER BY time DESC
            LIMIT 1;
        IF NOT FOUND THEN
            RAISE WARNING '-> DEBUG cron_process_autodiscovery_fn, No metrics found for vessel_id: %', current_setting('vessel.id', false);
            CONTINUE; -- Skip to the next process_rec
        END IF;
        -- as we got data from the vessel we can do the autodiscovery provisioning.
        IF data_rec.configuration IS NULL THEN
            data_rec.configuration := '{}'::JSONB; -- Initialize empty configuration if NULL
        END IF;
        --RAISE DEBUG '-> DEBUG cron_process_autodiscovery_fn autodiscovery_config_fn provisioning [%] [%] [%]', config_default, data_rec.configuration, (config_default || data_rec.configuration);
        SELECT public.autodiscovery_config_fn(config_default || data_rec.configuration) INTO config;
        --RAISE DEBUG '-> DEBUG cron_process_autodiscovery_fn autodiscovery_config_fn [%]', config;
        -- Check if config is empty
        IF config IS NULL OR config = '{}'::JSONB THEN
            RAISE WARNING '-> DEBUG cron_process_autodiscovery_fn, vessel.id [%], autodiscovery_config_fn error [%]', current_setting('vessel.id', false), config;
            -- update process_queue entry as processed
            UPDATE process_queue
                SET
                    processed = NOW()
                WHERE id = process_rec.id;
            RAISE NOTICE '-> cron_process_autodiscovery_fn updated process_queue table [%]', process_rec.id;
            CONTINUE; -- Skip to the next process_rec
        END IF;
        -- Update metadata configuration with the new config
        RAISE NOTICE '-> cron_process_autodiscovery_fn, vessel.id [%], update api.metadata configuration', current_setting('vessel.id', false);
        UPDATE api.metadata
            SET configuration = config
            WHERE vessel_id = current_setting('vessel.id', false);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(data_rec.vessel_id::TEXT);
        --RAISE DEBUG '-> DEBUG cron_process_autodiscovery_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('autodiscovery'::TEXT, user_settings::JSONB);
        -- update process_queue entry as processed
        UPDATE process_queue
            SET
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_autodiscovery_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.cron_process_autodiscovery_fn() IS 'init by pg_cron to check for new vessel pending autodiscovery config provisioning';

-- Create api.stays_image to fetch stays image
create domain "*/*" as bytea;
create or replace function api.stays_image(v_id TEXT default NULL, _id INTEGER default NULL) returns "*/*"
LANGUAGE plpgsql
AS $function$
  declare headers text;
  declare blob bytea;
  begin
    select format(
      '[{"Content-Type": "%s"},'
       '{"Content-Disposition": "inline; filename=\"%s\""},'
       '{"Cache-Control": "max-age=900"}]'
      , image_type, v_id)
      into headers
      from api.stays_ext where vessel_id = v_id and stay_id = _id;
    perform set_config('response.headers', headers, true);
    select image into blob from api.stays_ext where vessel_id = v_id and stay_id = _id;
    if FOUND -- special var, see https://www.postgresql.org/docs/current/plpgsql-statements.html#PLPGSQL-STATEMENTS-DIAGNOSTICS
    then return(blob);
    else raise sqlstate 'PT404' using
      message = 'NOT FOUND',
      detail = 'File not found',
      hint = format('%s seems to be an invalid file', v_id);
    end if;
  end
$function$ ;
-- Description
COMMENT ON FUNCTION api.stays_image IS 'Return stays image from stays_ext (image url)';

-- Create api.vessel_image to fetch boat image
create or replace function api.vessel_image(v_id TEXT default NULL) returns "*/*" 
LANGUAGE plpgsql
AS $function$
  declare headers text;
  declare blob bytea;
  begin
    select format(
      '[{"Content-Type": "%s"},'
       '{"Content-Disposition": "inline; filename=\"%s\""},'
       '{"Cache-Control": "max-age=900"}]'
      , image_type, v_id)
      into headers
      from api.metadata_ext where vessel_id = v_id;
    perform set_config('response.headers', headers, true);
    select image into blob from api.metadata_ext where vessel_id = v_id;
    if FOUND -- special var, see https://www.postgresql.org/docs/current/plpgsql-statements.html#PLPGSQL-STATEMENTS-DIAGNOSTICS
    then return(blob);
    else raise sqlstate 'PT404' using
      message = 'NOT FOUND',
      detail = 'File not found',
      hint = format('%s seems to be an invalid file', v_id);
    end if;
  end
$function$ ;
-- Description
COMMENT ON FUNCTION api.vessel_image IS 'Return vessel image from metadata_ext (image url)';

-- Create api.vessel_extended_fn() to expose extended vessel details
CREATE OR REPLACE FUNCTION api.vessel_extended_fn()
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
    v_id text := current_setting('vessel.id', false);
    result jsonb;
BEGIN
    SELECT jsonb_build_object(
          'make_model', make_model,
          'has_polar', polar IS NOT NULL,
          'has_image', image IS NOT NULL,
          'image_url', 
            CASE
                WHEN image IS NOT NULL AND image_url IS NOT NULL THEN image_url
                WHEN image IS NOT NULL AND image_url IS NULL THEN '/rpc/vessel_image?v_id=' || vessel_id
                ELSE NULL
            END,
          'image_updated_at', image_updated_at
      )
      INTO result
      FROM api.metadata_ext
      WHERE vessel_id = v_id;

    IF result IS NULL THEN
        result := jsonb_build_object(
            'make_model', NULL,
            'has_polar', false,
            'has_image', false,
            'image_url', NULL,
            'image_updated_at', NULL
        );
    END IF;

    RETURN result;
END;
$function$;
-- Description
COMMENT ON FUNCTION api.vessel_extended_fn() IS 'Return vessel details from metadata_ext (polar csv,image url, make model)';

-- Update api.vessel_details_fn to use configuration
DROP FUNCTION api.vessel_details_fn(out json);
CREATE OR REPLACE FUNCTION api.vessel_details_fn()
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
BEGIN
     RETURN ( WITH tbl AS (
                SELECT mmsi,ship_type,length,beam,height,plugin_version,platform,configuration IS NOT NULL AS has_config FROM api.metadata WHERE vessel_id = current_setting('vessel.id', false)
                )
                SELECT jsonb_build_object(
                        'ship_type', (SELECT ais.description FROM aistypes ais, tbl t WHERE t.ship_type = ais.id),
                        'country', (SELECT mid.country FROM mid, tbl t WHERE LEFT(cast(t.mmsi as text), 3)::NUMERIC = mid.id),
                        'alpha_2', (SELECT o.alpha_2 FROM mid m, iso3166 o, tbl t WHERE LEFT(cast(t.mmsi as text), 3)::NUMERIC = m.id AND m.country_id = o.id),
                        'length', t.length,
                        'beam', t.beam,
                        'height', t.height,
                        'plugin_version', t.plugin_version,
                        'platform', t.platform,
                        'configuration', t.has_config)
                        FROM tbl t
            );
END;
$function$
;
-- Description
COMMENT ON FUNCTION api.vessel_details_fn() IS 'Return vessel details such as metadata (length,beam,height), ais type and country name and country iso3166-alpha-2';

DROP FUNCTION api.vessel_fn(out json);
-- Update api.vessel_fn to use metadata_ext
CREATE OR REPLACE FUNCTION api.vessel_fn(OUT vessel jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
    DECLARE
    BEGIN
        SELECT
            jsonb_build_object(
                'name', m.name,
                'mmsi', m.mmsi,
                'vessel_id', m.vessel_id,
                'created_at', v.created_at,
                'first_contact', m.created_at,
                'last_contact', m.time,
                'offline', (NOW() AT TIME ZONE 'UTC' - m.time) > INTERVAL '70 MINUTES',
                'geojson', ST_AsGeoJSON(geojson_t.*)::json
            )::jsonb
            || api.vessel_details_fn()::jsonb
            || api.vessel_extended_fn()::jsonb
            INTO vessel
            FROM auth.vessels v, api.metadata m, 
                (	select
                        current_setting('vessel.name') as name,
                        time,
                        courseovergroundtrue,
                        speedoverground,
                        anglespeedapparent,
                        longitude,latitude,
                        st_makepoint(longitude,latitude) AS geo_point
                        FROM api.metrics
                        WHERE
                            latitude IS NOT NULL
                            AND longitude IS NOT NULL
                            AND vessel_id = current_setting('vessel.id', false)
                        ORDER BY time DESC LIMIT 1
                ) AS geojson_t
            WHERE
                m.vessel_id = current_setting('vessel.id')
                AND m.vessel_id = v.vessel_id;
        --RAISE notice 'api.vessel_fn %', obj;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION api.vessel_fn(out jsonb) IS 'Expose vessel details to API';

DROP VIEW IF EXISTS api.monitoring_view;
DROP VIEW IF EXISTS api.monitoring_live;
DROP FUNCTION IF EXISTS public.stay_active_geojson_fn();
-- Update public.stay_active_geojson_fn function to produce a GeoJSON with the last position and stay details and anchor details
CREATE OR REPLACE FUNCTION public.stay_active_geojson_fn(
    IN _time TIMESTAMPTZ DEFAULT NOW(),
    OUT _track_geojson jsonb
) AS $stay_active_geojson_fn$
BEGIN
    WITH stay_active AS (
        SELECT * FROM api.stays WHERE active IS TRUE
    ),
    metric_active AS (
        SELECT * FROM api.metrics ORDER BY time DESC LIMIT 1
    ),
    stay_features AS (
        SELECT jsonb_build_object(
            'type', 'Feature',
            'geometry', ST_AsGeoJSON(ST_MakePoint(s.longitude, s.latitude))::jsonb,
            'properties', jsonb_build_object(
                'name', m.name,
                'time', _time,
                'stay_code', s.stay_code,
                'arrived', s.arrived,
                'latitude', s.latitude,
                'longitude', s.longitude,
                'anchor', l.metrics->'anchor'
            )
        ) AS feature
        FROM stay_active s
        LEFT JOIN api.moorages m ON m.id = s.moorage_id
        CROSS JOIN metric_active l
    )
    SELECT feature
    INTO _track_geojson
    FROM stay_features;
END;
$stay_active_geojson_fn$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.stay_active_geojson_fn
    IS 'Create a GeoJSON with a feature Point with the last position and stay details';

-- Update monitoring view to support live moorage in GeoJSON
CREATE VIEW api.monitoring_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT
        time AS "time",
        (NOW() AT TIME ZONE 'UTC' - time) > INTERVAL '70 MINUTES' as offline,
        metrics-> 'environment.water.temperature' AS waterTemperature,
        metrics-> 'environment.inside.temperature' AS insideTemperature,
        metrics-> 'environment.outside.temperature' AS outsideTemperature,
        metrics-> 'environment.wind.speedOverGround' AS windSpeedOverGround,
        metrics-> 'environment.wind.directionTrue' AS windDirectionTrue,
        metrics-> 'environment.inside.relativeHumidity' AS insideHumidity,
        metrics-> 'environment.outside.relativeHumidity' AS outsideHumidity,
        metrics-> 'environment.outside.pressure' AS outsidePressure,
        metrics-> 'environment.inside.pressure' AS insidePressure,
        metrics-> 'electrical.batteries.House.capacity.stateOfCharge' AS batteryCharge,
        metrics-> 'electrical.batteries.House.voltage' AS batteryVoltage,
        metrics-> 'environment.depth.belowTransducer' AS depth,
        jsonb_build_object(
            'type', 'Feature',
            'geometry', ST_AsGeoJSON(st_makepoint(longitude,latitude))::jsonb,
            'properties', jsonb_build_object(
                'name', current_setting('vessel.name', false),
                'latitude', m.latitude,
                'longitude', m.longitude,
                'time', m.time,
                'speedoverground', m.speedoverground,
                'windspeedapparent', m.windspeedapparent,
                'truewindspeed', COALESCE(metrics->'environment.wind.speedTrue', null),
                'truewinddirection', COALESCE(metrics->'environment.wind.directionTrue', null),
                'status', coalesce(m.status, null)
                )::jsonb ) AS geojson,
        current_setting('vessel.name', false) AS name,
        m.status,
        CASE
            WHEN m.status <> 'moored' AND m.status <> 'anchored' THEN (
                SELECT public.logbook_active_geojson_fn() )
            WHEN m.status = 'moored' OR m.status = 'anchored' THEN (
                SELECT public.stay_active_geojson_fn(time) )
        END AS live
    FROM api.metrics m
    ORDER BY time DESC LIMIT 1;
-- Description
COMMENT ON VIEW
    api.monitoring_view
    IS 'Monitoring static web view';

-- DROP FUNCTION public.overpass_py_fn(in numeric, in numeric, out jsonb);
-- Update public.overpass_py_fn to check for seamark with name
CREATE OR REPLACE FUNCTION public.overpass_py_fn(lon numeric, lat numeric, OUT geo jsonb)
 RETURNS jsonb
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
 IMMUTABLE STRICT
AS $function$
    """
    Return https://overpass-turbo.eu seamark details within 400m
    https://overpass-turbo.eu/s/1EaG
    https://wiki.openstreetmap.org/wiki/Key:seamark:type
    """
    import requests
    import json
    import urllib.parse

    headers = {'User-Agent': 'PostgSail', 'From': 'xbgmsharp@gmail.com'}
    payload = """
[out:json][timeout:20];
is_in({0},{1})->.result_areas;
(
  area.result_areas["seamark:type"~"(mooring|harbour)"][~"^seamark:.*:category$"~"."][~"name"~"."];
  area.result_areas["seamark:type"~"(anchorage|anchor_berth|berth)"][~"name"~"."];
  area.result_areas["leisure"="marina"][~"name"~"."];
);
out tags;
nwr(around:400.0,{0},{1})->.all;
(
  nwr.all["seamark:type"~"(mooring|harbour)"][~"^seamark:.*:category$"~"."][~"name"~"."];
  nwr.all["seamark:type"~"(anchorage|anchor_berth|berth)"][~"name"~"."];
  nwr.all["leisure"="marina"][~"name"~"."];
  nwr.all["natural"~"(bay|beach)"][~"name"~"."];
  //nwr.all["waterway"="fuel"];
);
out tags;
    """.format(lat, lon)
    data = urllib.parse.quote(payload, safe="");
    url = f'https://overpass-api.de/api/interpreter?data={data}'.format(data)
    r = requests.get(url, headers)
    #print(r.text)
    #plpy.notice(url)
    plpy.notice('overpass-api coord lon[{}] lat[{}] [{}]'.format(lon, lat, r.status_code))
    if r.status_code == 200 and "elements" in r.json():
        r_dict = r.json()
        plpy.notice('overpass-api Got [{}]'.format(r_dict["elements"]))
        if r_dict["elements"]:
            if "tags" in r_dict["elements"][0] and r_dict["elements"][0]["tags"]:
                return r_dict["elements"][0]["tags"]; # return the first element
        return {}
    else:
        plpy.notice('overpass-api Failed to get overpass-api details')
    return {}
$function$
;
-- Description
COMMENT ON FUNCTION public.overpass_py_fn(in numeric, in numeric, out jsonb) IS 'Return https://overpass-turbo.eu seamark details within 400m using plpython3u';

-- DROP FUNCTION api.export_logbooks_geojson_linestring_trips_fn(in int4, in int4, in text, in text, out jsonb);
-- Update api.export_logbooks_geojson_linestring_trips_fn, add extra, _to_moorage_id, _from_moorage_id metadata
CREATE OR REPLACE FUNCTION api.export_logbooks_geojson_linestring_trips_fn(start_log integer DEFAULT NULL::integer, end_log integer DEFAULT NULL::integer, start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT geojson jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    logs_geojson jsonb;
BEGIN
    -- Normalize start and end values
    IF start_log IS NOT NULL AND end_log IS NULL THEN end_log := start_log; END IF;
    IF start_date IS NOT NULL AND end_date IS NULL THEN end_date := start_date; END IF;

    WITH logbook_data AS (
        -- get the logbook geometry and metadata, an array for each log
        SELECT id, name,
            starttimestamp(trip),
            endtimestamp(trip),
            --speed(trip_sog),
            duration(trip),
            --length(trip) as length, -- Meters
            (length(trip) * 0.0005399568)::numeric as distance, -- NM
            maxValue(trip_sog) as max_sog, -- SOG
            maxValue(trip_tws) as max_tws, -- Wind
            maxValue(trip_twd) as max_twd, -- Wind
            maxValue(trip_depth) as max_depth, -- Depth
            maxValue(trip_temp_water) as max_temp_water, -- Temperature water
            maxValue(trip_temp_out) as max_temp_out, -- Temperature outside
            maxValue(trip_pres_out) as max_pres_out, -- Pressure outside
            maxValue(trip_hum_out) as max_hum_out, -- Humidity outside
            maxValue(trip_batt_charge) as max_stateofcharge, -- stateofcharge
            maxValue(trip_batt_voltage) as max_voltage, -- voltage
            maxValue(trip_solar_voltage) as max_solar_voltage, -- solar voltage
            maxValue(trip_solar_power) as max_solar_power, -- solar power
            maxValue(trip_tank_level) as max_tank_level, -- tank level
            twavg(trip_sog) as avg_sog, -- SOG
            twavg(trip_tws) as avg_tws, -- Wind
            twavg(trip_twd) as avg_twd, -- Wind
            twavg(trip_depth) as avg_depth, -- Depth
            twavg(trip_temp_water) as avg_temp_water, -- Temperature water
            twavg(trip_temp_out) as avg_temp_out, -- Temperature outside
            twavg(trip_pres_out) as avg_pres_out, -- Pressure outside
            twavg(trip_hum_out) as avg_hum_out, -- Humidity outside
            twavg(trip_batt_charge) as avg_stateofcharge, -- stateofcharge
            twavg(trip_batt_voltage) as avg_voltage, -- voltage
            twavg(trip_solar_voltage) as avg_solar_voltage, -- solar voltage
            twavg(trip_solar_power) as avg_solar_power, -- solar power
            twavg(trip_tank_level) as avg_tank_level, -- tank level
            trajectory(l.trip)::geometry as track_geog, -- extract trip to geography
            extra,
            _to_moorage_id,
            _from_moorage_id
        FROM api.logbook l
        WHERE (start_log IS NULL OR l.id >= start_log) AND
              (end_log IS NULL OR l.id <= end_log) AND
              (start_date IS NULL OR l._from_time >= start_date::TIMESTAMPTZ) AND
              (end_date IS NULL OR l._to_time <= end_date::TIMESTAMPTZ + interval '23 hours 59 minutes') AND
              l.trip IS NOT NULL
        ORDER BY l._from_time ASC
    ),
    collect as (
        SELECT ST_Collect(
                        ARRAY(
                            SELECT track_geog FROM logbook_data))
    )
    -- Create the GeoJSON response
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', json_agg(ST_AsGeoJSON(logs.*)::json)) INTO geojson FROM logbook_data logs;
END;
$function$
;
-- Description
COMMENT ON FUNCTION api.export_logbooks_geojson_linestring_trips_fn(in int4, in int4, in text, in text, out jsonb) IS 'Generate geojson geometry LineString from trip with the corresponding properties';

-- Update api.monitoring_live, add live tracking view, Add support 6h outside barometer
DROP VIEW IF EXISTS api.monitoring_live;
CREATE OR REPLACE VIEW api.monitoring_live WITH (security_invoker=true,security_barrier=true) AS
  -- Gather the last 6h average outside pressure by 10 min range
  WITH pressure AS (
    SELECT 
      json_agg(json_build_object(
        'time', time_bucket,
        'outsidePressure', outsidePressure
      ) ORDER BY time_bucket) AS outsidePressureHistory
    FROM (
      SELECT
        time_bucket('10 minutes', mt.time) AS time_bucket,
        avg(COALESCE(
            mt.metrics->'pressure'->>'outside',
            mt.metrics->>(md.configuration->>'outsidePressureKey'),
            mt.metrics->>'environment.outside.pressure'
        )::FLOAT) AS outsidePressure
      FROM api.metrics mt
      JOIN api.metadata md ON md.vessel_id = mt.vessel_id
      WHERE mt.vessel_id = current_setting('vessel.id', false)
        AND mt.time > (NOW() AT TIME ZONE 'UTC' - INTERVAL '6 hour')
      GROUP BY time_bucket
    ) sub
  )
  SELECT
      mt.time AS "time",
      (NOW() AT TIME ZONE 'UTC' - mt.time) > INTERVAL '70 MINUTES' as offline,
      mt.metrics AS data,
      jsonb_build_object(
          'type', 'Feature',
          'geometry', ST_AsGeoJSON(st_makepoint(mt.longitude,mt.latitude))::jsonb,
          'properties', jsonb_build_object(
              'name', current_setting('vessel.name', false),
              'latitude', mt.latitude,
              'longitude', mt.longitude,
              'time', mt.time,
              'speedoverground', mt.speedoverground,
              'windspeedapparent',mt.windspeedapparent,
              'truewindspeed', -- Wind Speed True
                              COALESCE(
                                  mt.metrics->'wind'->>'speed',
                                  mt.metrics->>(md.configuration->>'windSpeedKey'),
                                  mt.metrics->>'environment.wind.speedTrue'
                              )::FLOAT,
              'truewinddirection', -- Wind Direction True
                                COALESCE(
                                    mt.metrics->'wind'->>'direction',
                                    mt.metrics->>(md.configuration->>'windDirectionKey'),
                                    mt.metrics->>'environment.wind.directionTrue'
                                )::FLOAT,
              'status', coalesce(mt.status, null)
              )::jsonb ) AS geojson,
      current_setting('vessel.name', false) AS name,
      mt.status,
      -- Water Temperature
      COALESCE(
          mt.metrics->'water'->>'temperature',
          mt.metrics->>(md.configuration->>'waterTemperatureKey'),
          mt.metrics->>'environment.water.temperature'
      )::FLOAT AS waterTemperature,

      -- Inside Temperature
      COALESCE(
          mt.metrics->'temperature'->>'inside',
          mt.metrics->>(md.configuration->>'insideTemperatureKey'),
          mt.metrics->>'environment.inside.temperature'
      )::FLOAT AS insideTemperature,

      -- Outside Temperature
      COALESCE(
          mt.metrics->'temperature'->>'outside',
          mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
          mt.metrics->>'environment.outside.temperature'
      )::FLOAT AS outsideTemperature,

      -- Wind Speed True
      COALESCE(
          mt.metrics->'wind'->>'speed',
          mt.metrics->>(md.configuration->>'windSpeedKey'),
          mt.metrics->>'environment.wind.speedTrue'
      )::FLOAT AS windSpeedOverGround,

      -- Wind Direction True
      COALESCE(
          mt.metrics->'wind'->>'direction',
          mt.metrics->>(md.configuration->>'windDirectionKey'),
          mt.metrics->>'environment.wind.directionTrue'
      )::FLOAT AS windDirectionTrue,

      -- Inside Humidity
      COALESCE(
          mt.metrics->'humidity'->>'inside',
          mt.metrics->>(md.configuration->>'insideHumidityKey'),
          mt.metrics->>'environment.inside.relativeHumidity',
          mt.metrics->>'environment.inside.humidity'
      )::FLOAT AS insideHumidity,

      -- Outside Humidity
      COALESCE(
          mt.metrics->'humidity'->>'outside',
          mt.metrics->>(md.configuration->>'outsideHumidityKey'),
          mt.metrics->>'environment.outside.relativeHumidity',
          mt.metrics->>'environment.outside.humidity'
      )::FLOAT AS outsideHumidity,

      -- Outside Pressure
      COALESCE(
          mt.metrics->'pressure'->>'outside',
          mt.metrics->>(md.configuration->>'outsidePressureKey'),
          mt.metrics->>'environment.outside.pressure'
      )::FLOAT AS outsidePressure,

      -- Inside Pressure
      COALESCE(
          mt.metrics->'pressure'->>'inside',
          mt.metrics->>(md.configuration->>'insidePressureKey'),
          mt.metrics->>'environment.inside.pressure'
      )::FLOAT AS insidePressure,

      -- Battery Charge (State of Charge)
      COALESCE(
          mt.metrics->'battery'->>'charge',
          mt.metrics->>(md.configuration->>'stateOfChargeKey'),
          mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
      )::FLOAT AS batteryCharge,

      -- Battery Voltage
      COALESCE(
          mt.metrics->'battery'->>'voltage',
          mt.metrics->>(md.configuration->>'voltageKey'),
          mt.metrics->>'electrical.batteries.House.voltage'
      )::FLOAT AS batteryVoltage,

      -- Water Depth
      COALESCE(
          mt.metrics->'water'->>'depth',
          mt.metrics->>(md.configuration->>'depthKey'),
          mt.metrics->>'environment.depth.belowTransducer'
      )::FLOAT AS depth,

      -- Solar Power
      COALESCE(
          mt.metrics->'solar'->>'power',
          mt.metrics->>(md.configuration->>'solarPowerKey'),
          mt.metrics->>'electrical.solar.Main.panelPower'
      )::FLOAT AS solarPower,

      -- Solar Voltage
      COALESCE(
          mt.metrics->'solar'->>'voltage',
          mt.metrics->>(md.configuration->>'solarVoltageKey'),
          mt.metrics->>'electrical.solar.Main.panelVoltage'
      )::FLOAT AS solarVoltage,

      -- Tank Level
      COALESCE(
          mt.metrics->'tank'->>'level',
          mt.metrics->>(md.configuration->>'tankLevelKey'),
          mt.metrics->>'tanks.fuel.0.currentLevel'
      )::FLOAT AS tankLevel,

      CASE
        WHEN mt.status <> 'moored' AND mt.status <> 'anchored' THEN (
            SELECT public.logbook_active_geojson_fn() )
        WHEN mt.status = 'moored' OR mt.status = 'anchored' THEN (
            SELECT public.stay_active_geojson_fn(mt.time) )
      END AS live,
      -- Add the pressure history as a time series array
      pressure.outsidePressureHistory
  FROM api.metrics mt
  JOIN api.metadata md ON md.vessel_id = mt.vessel_id
  CROSS JOIN pressure
  ORDER BY time DESC LIMIT 1;
-- Description
COMMENT ON VIEW
    api.monitoring_live
    IS 'Dynamic Monitoring web view';

-- Update public.logbook_update_metrics_short_fn, aggregate more metrics and use user configuration
DROP FUNCTION IF EXISTS public.logbook_update_metrics_short_fn;
CREATE OR REPLACE FUNCTION public.logbook_update_metrics_short_fn(
    total_entry INT,
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ
)
RETURNS TABLE (
    trajectory tgeogpoint,
    courseovergroundtrue tfloat,
    speedoverground tfloat,
    windspeedapparent tfloat,
    truewindspeed tfloat,
    truewinddirection tfloat,
    notes ttext,
    status ttext,
    watertemperature tfloat,
    depth tfloat,
    outsidehumidity tfloat,
    outsidepressure tfloat,
    outsidetemperature tfloat,
    stateofcharge tfloat,
    voltage tfloat,
    solarPower tfloat,
    solarVoltage tfloat,
    tankLevel tfloat,
    heading tfloat
) AS $$
DECLARE
BEGIN
    -- Aggregate all metrics as trip is short.
    RETURN QUERY
    WITH metrics AS (
        -- Extract metrics
        SELECT mt.time,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT AS truewinddirection,
            -- Water Temperature
            COALESCE(
                mt.metrics->'water'->>'temperature',
                mt.metrics->>(md.configuration->>'waterTemperatureKey'),
                mt.metrics->>'environment.water.temperature'
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                mt.metrics->'water'->>'depth',
                mt.metrics->>(md.configuration->>'depthKey'),
                mt.metrics->>'environment.depth.belowTransducer'
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                mt.metrics->'humidity'->>'outside',
                mt.metrics->>(md.configuration->>'outsideHumidityKey'),
                mt.metrics->>'environment.outside.relativeHumidity',
                mt.metrics->>'environment.outside.humidity'
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                mt.metrics->'pressure'->>'outside',
                mt.metrics->>(md.configuration->>'outsidePressureKey'),
                mt.metrics->>'environment.outside.pressure'
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                mt.metrics->'temperature'->>'outside',
                mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
                mt.metrics->>'environment.outside.temperature'
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                mt.metrics->'battery'->>'charge',
                mt.metrics->>(md.configuration->>'stateOfChargeKey'),
                mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                mt.metrics->'battery'->>'voltage',
                mt.metrics->>(md.configuration->>'voltageKey'),
                mt.metrics->>'electrical.batteries.House.voltage'
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                mt.metrics->'solar'->>'power',
                mt.metrics->>(md.configuration->>'solarPowerKey'),
                mt.metrics->>'electrical.solar.Main.panelPower'
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                mt.metrics->'solar'->>'voltage',
                mt.metrics->>(md.configuration->>'solarVoltageKey'),
                mt.metrics->>'electrical.solar.Main.panelVoltage'
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                mt.metrics->'tank'->>'level',
                mt.metrics->>(md.configuration->>'tankLevelKey'),
                mt.metrics->>'tanks.fuel.0.currentLevel'
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(mt.longitude, mt.latitude) AS geo_point
        FROM api.metrics mt
        JOIN api.metadata md ON md.vessel_id = mt.vessel_id
        WHERE mt.latitude IS NOT NULL
            AND mt.longitude IS NOT NULL
            AND mt.time >= start_date
            AND mt.time <= end_date
            AND mt.vessel_id = current_setting('vessel.id', false)
            ORDER BY mt.time ASC
    )
    -- Create mobilitydb temporal sequences
    SELECT 
        tgeogpointseq(array_agg(tgeogpoint(ST_SetSRID(o.geo_point, 4326)::geography, o.time) ORDER BY o.time ASC)) AS trajectory,
        tfloatseq(array_agg(tfloat(o.courseovergroundtrue, o.time) ORDER BY o.time ASC) FILTER (WHERE o.courseovergroundtrue IS NOT NULL)) AS courseovergroundtrue,
        tfloatseq(array_agg(tfloat(o.speedoverground, o.time) ORDER BY o.time ASC) FILTER (WHERE o.speedoverground IS NOT NULL)) AS speedoverground,
        tfloatseq(array_agg(tfloat(o.windspeedapparent, o.time) ORDER BY o.time ASC) FILTER (WHERE o.windspeedapparent IS NOT NULL)) AS windspeedapparent,
        tfloatseq(array_agg(tfloat(o.truewindspeed, o.time) ORDER BY o.time ASC) FILTER (WHERE o.truewindspeed IS NOT NULL)) AS truewindspeed,
        tfloatseq(array_agg(tfloat(o.truewinddirection, o.time) ORDER BY o.time ASC) FILTER (WHERE o.truewinddirection IS NOT NULL)) AS truewinddirection,
        ttextseq(array_agg(ttext(o.notes, o.time) ORDER BY o.time ASC)) AS notes,
        ttextseq(array_agg(ttext(o.status, o.time) ORDER BY o.time ASC) FILTER (WHERE o.status IS NOT NULL)) AS status,
        tfloatseq(array_agg(tfloat(o.watertemperature, o.time) ORDER BY o.time ASC) FILTER (WHERE o.watertemperature IS NOT NULL)) AS watertemperature,
        tfloatseq(array_agg(tfloat(o.depth, o.time) ORDER BY o.time ASC) FILTER (WHERE o.depth IS NOT NULL)) AS depth,
        tfloatseq(array_agg(tfloat(o.outsidehumidity, o.time) ORDER BY o.time ASC) FILTER (WHERE o.outsidehumidity IS NOT NULL)) AS outsidehumidity,
        tfloatseq(array_agg(tfloat(o.outsidepressure, o.time) ORDER BY o.time ASC) FILTER (WHERE o.outsidepressure IS NOT NULL)) AS outsidepressure,
        tfloatseq(array_agg(tfloat(o.outsidetemperature, o.time) ORDER BY o.time ASC) FILTER (WHERE o.outsidetemperature IS NOT NULL)) AS outsidetemperature,
        tfloatseq(array_agg(tfloat(o.stateofcharge, o.time) ORDER BY o.time ASC) FILTER (WHERE o.stateofcharge IS NOT NULL)) AS stateofcharge,
        tfloatseq(array_agg(tfloat(o.voltage, o.time) ORDER BY o.time ASC) FILTER (WHERE o.voltage IS NOT NULL)) AS voltage,
        tfloatseq(array_agg(tfloat(o.solarPower, o.time) ORDER BY o.time ASC) FILTER (WHERE o.solarPower IS NOT NULL)) AS solarPower,
        tfloatseq(array_agg(tfloat(o.solarVoltage, o.time) ORDER BY o.time ASC) FILTER (WHERE o.solarVoltage IS NOT NULL)) AS solarVoltage,
        tfloatseq(array_agg(tfloat(o.tankLevel, o.time) ORDER BY o.time ASC) FILTER (WHERE o.tankLevel IS NOT NULL)) AS tankLevel,
        tfloatseq(array_agg(tfloat(o.heading, o.time) ORDER BY o.time ASC) FILTER (WHERE o.heading IS NOT NULL)) AS heading
    FROM metrics o;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_metrics_short_fn
    IS 'Optimize logbook metrics for short metrics';

-- Update public.logbook_update_metrics_fn, aggregate more metrics and use user configuration
DROP FUNCTION IF EXISTS public.logbook_update_metrics_fn;
CREATE OR REPLACE FUNCTION public.logbook_update_metrics_fn(
    total_entry INT,
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ
)
RETURNS TABLE (
    trajectory tgeogpoint,
    courseovergroundtrue tfloat,
    speedoverground tfloat,
    windspeedapparent tfloat,
    truewindspeed tfloat,
    truewinddirection tfloat,
    notes ttext,
    status ttext,
    watertemperature tfloat,
    depth tfloat,
    outsidehumidity tfloat,
    outsidepressure tfloat,
    outsidetemperature tfloat,
    stateofcharge tfloat,
    voltage tfloat,
    solarPower tfloat,
    solarVoltage tfloat,
    tankLevel tfloat,
    heading tfloat
) AS $$
DECLARE
    modulo_divisor INT;
BEGIN
    -- Aggregate data to reduce size by skipping row.
    -- Determine modulo based on total_entry
    IF total_entry <= 500 THEN
        modulo_divisor := 1;
    ELSIF total_entry > 500 AND total_entry <= 1000 THEN
        modulo_divisor := 2;
    ELSIF total_entry > 1000 AND total_entry <= 2000 THEN
        modulo_divisor := 3;
    ELSIF total_entry > 2000 AND total_entry <= 3000 THEN
        modulo_divisor := 4;
    ELSE
        modulo_divisor := 5;
    END IF;

    RETURN QUERY
    WITH metrics AS (
        -- Extract metrics base the total of entry ignoring first and last 10 minutes metrics
        SELECT t.time,
            t.courseovergroundtrue,
            t.speedoverground,
            t.windspeedapparent,
            t.longitude,
            t.latitude,
            '' AS notes,
            t.status,
            -- Heading True
            COALESCE(
                t.metrics->>'heading',
                t.metrics->>'navigation.headingTrue'
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                t.metrics->'wind'->>'speed',
                t.metrics->>(t.configuration->>'windSpeedKey'),
                t.metrics->>'environment.wind.speedTrue'
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                t.metrics->'wind'->>'direction',
                t.metrics->>(t.configuration->>'windDirectionKey'),
                t.metrics->>'environment.wind.directionTrue'
            )::FLOAT AS truewinddirection,
            -- Water Temperature
            COALESCE(
                t.metrics->'water'->>'temperature',
                t.metrics->>(t.configuration->>'waterTemperatureKey'),
                t.metrics->>'environment.water.temperature'
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                t.metrics->'water'->>'depth',
                t.metrics->>(t.configuration->>'depthKey'),
                t.metrics->>'environment.depth.belowTransducer'
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                t.metrics->'humidity'->>'outside',
                t.metrics->>(t.configuration->>'outsideHumidityKey'),
                t.metrics->>'environment.outside.relativeHumidity',
                t.metrics->>'environment.outside.humidity'
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                t.metrics->'pressure'->>'outside',
                t.metrics->>(t.configuration->>'outsidePressureKey'),
                t.metrics->>'environment.outside.pressure'
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                t.metrics->'temperature'->>'outside',
                t.metrics->>(t.configuration->>'outsideTemperatureKey'),
                t.metrics->>'environment.outside.temperature'
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                t.metrics->'battery'->>'charge',
                t.metrics->>(t.configuration->>'stateOfChargeKey'),
                t.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                t.metrics->'battery'->>'voltage',
                t.metrics->>(t.configuration->>'voltageKey'),
                t.metrics->>'electrical.batteries.House.voltage'
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                t.metrics->'solar'->>'power',
                t.metrics->>(t.configuration->>'solarPowerKey'),
                t.metrics->>'electrical.solar.Main.panelPower'
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                t.metrics->'solar'->>'voltage',
                t.metrics->>(t.configuration->>'solarVoltageKey'),
                t.metrics->>'electrical.solar.Main.panelVoltage'
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                t.metrics->'tank'->>'level',
                t.metrics->>(t.configuration->>'tankLevelKey'),
                t.metrics->>'tanks.fuel.0.currentLevel'
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(t.longitude, t.latitude) AS geo_point
        FROM (
            SELECT mt.*, md.configuration, row_number() OVER() AS row
            FROM api.metrics mt
            JOIN api.metadata md ON md.vessel_id = mt.vessel_id
            WHERE mt.latitude IS NOT NULL
                AND mt.longitude IS NOT NULL
                AND mt.time > (start_date + interval '10 minutes')
                AND mt.time < (end_date - interval '10 minutes')
                AND mt.vessel_id = current_setting('vessel.id', false)
				ORDER BY mt.time ASC
        ) t
        WHERE t.row % modulo_divisor = 0
    ),
    first_metric AS (
        -- Extract first 10 minutes metrics
        SELECT 
            mt.time,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT AS truewinddirection,
            -- Water Temperature
            COALESCE(
                mt.metrics->'water'->>'temperature',
                mt.metrics->>(md.configuration->>'waterTemperatureKey'),
                mt.metrics->>'environment.water.temperature'
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                mt.metrics->'water'->>'depth',
                mt.metrics->>(md.configuration->>'depthKey'),
                mt.metrics->>'environment.depth.belowTransducer'
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                mt.metrics->'humidity'->>'outside',
                mt.metrics->>(md.configuration->>'outsideHumidityKey'),
                mt.metrics->>'environment.outside.relativeHumidity',
                mt.metrics->>'environment.outside.humidity'
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                mt.metrics->'pressure'->>'outside',
                mt.metrics->>(md.configuration->>'outsidePressureKey'),
                mt.metrics->>'environment.outside.pressure'
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                mt.metrics->'temperature'->>'outside',
                mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
                mt.metrics->>'environment.outside.temperature'
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                mt.metrics->'battery'->>'charge',
                mt.metrics->>(md.configuration->>'stateOfChargeKey'),
                mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                mt.metrics->'battery'->>'voltage',
                mt.metrics->>(md.configuration->>'voltageKey'),
                mt.metrics->>'electrical.batteries.House.voltage'
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                mt.metrics->'solar'->>'power',
                mt.metrics->>(md.configuration->>'solarPowerKey'),
                mt.metrics->>'electrical.solar.Main.panelPower'
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                mt.metrics->'solar'->>'voltage',
                mt.metrics->>(md.configuration->>'solarVoltageKey'),
                mt.metrics->>'electrical.solar.Main.panelVoltage'
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                mt.metrics->'tank'->>'level',
                mt.metrics->>(md.configuration->>'tankLevelKey'),
                mt.metrics->>'tanks.fuel.0.currentLevel'
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(mt.longitude, mt.latitude) AS geo_point
        FROM api.metrics mt
        JOIN api.metadata md ON md.vessel_id = mt.vessel_id
        WHERE mt.latitude IS NOT NULL
            AND mt.longitude IS NOT NULL
            AND mt.time >= start_date
            AND mt.time < (start_date + interval '10 minutes')
            AND mt.vessel_id = current_setting('vessel.id', false)
        ORDER BY mt.time ASC
    ),
    last_metric AS (
        -- Extract last 10 minutes metrics
        SELECT 
            mt.time,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT AS truewinddirection,
            -- Water Temperature
            COALESCE(
                mt.metrics->'water'->>'temperature',
                mt.metrics->>(md.configuration->>'waterTemperatureKey'),
                mt.metrics->>'environment.water.temperature'
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                mt.metrics->'water'->>'depth',
                mt.metrics->>(md.configuration->>'depthKey'),
                mt.metrics->>'environment.depth.belowTransducer'
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                mt.metrics->'humidity'->>'outside',
                mt.metrics->>(md.configuration->>'outsideHumidityKey'),
                mt.metrics->>'environment.outside.relativeHumidity',
                mt.metrics->>'environment.outside.humidity'
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                mt.metrics->'pressure'->>'outside',
                mt.metrics->>(md.configuration->>'outsidePressureKey'),
                mt.metrics->>'environment.outside.pressure'
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                mt.metrics->'temperature'->>'outside',
                mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
                mt.metrics->>'environment.outside.temperature'
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                mt.metrics->'battery'->>'charge',
                mt.metrics->>(md.configuration->>'stateOfChargeKey'),
                mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                mt.metrics->'battery'->>'voltage',
                mt.metrics->>(md.configuration->>'voltageKey'),
                mt.metrics->>'electrical.batteries.House.voltage'
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                mt.metrics->'solar'->>'power',
                mt.metrics->>(md.configuration->>'solarPowerKey'),
                mt.metrics->>'electrical.solar.Main.panelPower'
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                mt.metrics->'solar'->>'voltage',
                mt.metrics->>(md.configuration->>'solarVoltageKey'),
                mt.metrics->>'electrical.solar.Main.panelVoltage'
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                mt.metrics->'tank'->>'level',
                mt.metrics->>(md.configuration->>'tankLevelKey'),
                mt.metrics->>'tanks.fuel.0.currentLevel'
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(mt.longitude, mt.latitude) AS geo_point
        FROM api.metrics mt
        JOIN api.metadata md ON md.vessel_id = mt.vessel_id
        WHERE mt.latitude IS NOT NULL
            AND mt.longitude IS NOT NULL
            AND mt.time <= end_date
            AND mt.time > (end_date - interval '10 minutes')
            AND mt.vessel_id = current_setting('vessel.id', false)
        ORDER BY mt.time ASC
    ),
    optimize_metrics AS (
        -- Combine and order the results
        SELECT * FROM first_metric
        UNION ALL
        SELECT * FROM metrics
        UNION ALL
        SELECT * FROM last_metric
        ORDER BY time ASC
    )
    -- Create mobilitydb temporal sequences
    SELECT 
        tgeogpointseq(array_agg(tgeogpoint(ST_SetSRID(o.geo_point, 4326)::geography, o.time) ORDER BY o.time ASC)) AS trajectory,
        tfloatseq(array_agg(tfloat(o.courseovergroundtrue, o.time) ORDER BY o.time ASC) FILTER (WHERE o.courseovergroundtrue IS NOT NULL)) AS courseovergroundtrue,
        tfloatseq(array_agg(tfloat(o.speedoverground, o.time) ORDER BY o.time ASC) FILTER (WHERE o.speedoverground IS NOT NULL)) AS speedoverground,
        tfloatseq(array_agg(tfloat(o.windspeedapparent, o.time) ORDER BY o.time ASC) FILTER (WHERE o.windspeedapparent IS NOT NULL)) AS windspeedapparent,
        tfloatseq(array_agg(tfloat(o.truewindspeed, o.time) ORDER BY o.time ASC) FILTER (WHERE o.truewindspeed IS NOT NULL)) AS truewindspeed,
        tfloatseq(array_agg(tfloat(o.truewinddirection, o.time) ORDER BY o.time ASC) FILTER (WHERE o.truewinddirection IS NOT NULL)) AS truewinddirection,
        ttextseq(array_agg(ttext(o.notes, o.time) ORDER BY o.time ASC)) AS notes,
        ttextseq(array_agg(ttext(o.status, o.time) ORDER BY o.time ASC) FILTER (WHERE o.status IS NOT NULL)) AS status,
        tfloatseq(array_agg(tfloat(o.watertemperature, o.time) ORDER BY o.time ASC) FILTER (WHERE o.watertemperature IS NOT NULL)) AS watertemperature,
        tfloatseq(array_agg(tfloat(o.depth, o.time) ORDER BY o.time ASC) FILTER (WHERE o.depth IS NOT NULL)) AS depth,
        tfloatseq(array_agg(tfloat(o.outsidehumidity, o.time) ORDER BY o.time ASC) FILTER (WHERE o.outsidehumidity IS NOT NULL)) AS outsidehumidity,
        tfloatseq(array_agg(tfloat(o.outsidepressure, o.time) ORDER BY o.time ASC) FILTER (WHERE o.outsidepressure IS NOT NULL)) AS outsidepressure,
        tfloatseq(array_agg(tfloat(o.outsidetemperature, o.time) ORDER BY o.time ASC) FILTER (WHERE o.outsidetemperature IS NOT NULL)) AS outsidetemperature,
        tfloatseq(array_agg(tfloat(o.stateofcharge, o.time) ORDER BY o.time ASC) FILTER (WHERE o.stateofcharge IS NOT NULL)) AS stateofcharge,
        tfloatseq(array_agg(tfloat(o.voltage, o.time) ORDER BY o.time ASC) FILTER (WHERE o.voltage IS NOT NULL)) AS voltage,
        tfloatseq(array_agg(tfloat(o.solarPower, o.time) ORDER BY o.time ASC) FILTER (WHERE o.solarPower IS NOT NULL)) AS solarPower,
        tfloatseq(array_agg(tfloat(o.solarVoltage, o.time) ORDER BY o.time ASC) FILTER (WHERE o.solarVoltage IS NOT NULL)) AS solarVoltage,
        tfloatseq(array_agg(tfloat(o.tankLevel, o.time) ORDER BY o.time ASC) FILTER (WHERE o.tankLevel IS NOT NULL)) AS tankLevel,
        tfloatseq(array_agg(tfloat(o.heading, o.time) ORDER BY o.time ASC) FILTER (WHERE o.heading IS NOT NULL)) AS heading
    FROM optimize_metrics o;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_metrics_fn
    IS 'Optimize logbook metrics base on the total metrics';

-- Update public.logbook_update_metrics_timebucket_fn, aggregate more metrics and use user configuration
DROP FUNCTION IF EXISTS public.logbook_update_metrics_timebucket_fn;
CREATE OR REPLACE FUNCTION public.logbook_update_metrics_timebucket_fn(
    total_entry INT,
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ
)
RETURNS TABLE (
    trajectory tgeogpoint,
    courseovergroundtrue tfloat,
    speedoverground tfloat,
    windspeedapparent tfloat,
    truewindspeed tfloat,
    truewinddirection tfloat,
    notes ttext,
    status ttext,
    watertemperature tfloat,
    depth tfloat,
    outsidehumidity tfloat,
    outsidepressure tfloat,
    outsidetemperature tfloat,
    stateofcharge tfloat,
    voltage tfloat,
    solarPower tfloat,
    solarVoltage tfloat,
    tankLevel tfloat,
    heading tfloat
) AS $$
DECLARE
    bucket_interval INTERVAL;
BEGIN
    -- Aggregate metrics by time-series to reduce size
    -- Determine modulo based on total_entry
    IF total_entry <= 500 THEN
        bucket_interval := '2 minutes';
    ELSIF total_entry > 500 AND total_entry <= 1000 THEN
        bucket_interval := '3 minutes';
    ELSIF total_entry > 1000 AND total_entry <= 2000 THEN
        bucket_interval := '5 minutes';
    ELSIF total_entry > 2000 AND total_entry <= 3000 THEN
        bucket_interval := '10 minutes';
    ELSE
        bucket_interval := '15 minutes';
    END IF;

    RETURN QUERY
    WITH metrics AS (
        -- Extract metrics base the total of entry ignoring first and last 10 minutes metrics
        SELECT time_bucket(bucket_interval::INTERVAL, mt.time) AS time_bucket,  -- Time-bucketed period
            avg(mt.courseovergroundtrue) as courseovergroundtrue,
            avg(mt.speedoverground) as speedoverground,
            avg(mt.windspeedapparent) as windspeedapparent,
            last(mt.longitude, mt.time) as longitude, last(mt.latitude, mt.time) as latitude,
            '' AS notes,
            last(mt.status, mt.time) as status,
            -- Heading True
            COALESCE(
                last(mt.metrics->>'heading', mt.time),
                last(mt.metrics->>'navigation.headingTrue', mt.time)
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                last(mt.metrics->'wind'->>'speed', mt.time),
                last(mt.metrics->>(md.configuration->>'windSpeedKey'), mt.time),
                last(mt.metrics->>'environment.wind.speedTrue', mt.time)
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                last(mt.metrics->'wind'->>'direction', mt.time),
                last(mt.metrics->>(md.configuration->>'windDirectionKey'), mt.time),
                last(mt.metrics->>'environment.wind.directionTrue', mt.time)
            )::FLOAT AS truewinddirection,
            -- Water Temperature
            COALESCE(
                last(mt.metrics->'water'->>'temperature', mt.time),
                last(mt.metrics->>(md.configuration->>'waterTemperatureKey'), mt.time),
                last(mt.metrics->>'environment.water.temperature', mt.time)
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                last(mt.metrics->'water'->>'depth', mt.time),
                last(mt.metrics->>(md.configuration->>'depthKey'), mt.time),
                last(mt.metrics->>'environment.depth.belowTransducer', mt.time)
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                last(mt.metrics->'humidity'->>'outside', mt.time),
                last(mt.metrics->>(md.configuration->>'outsideHumidityKey'), mt.time),
                last(mt.metrics->>'environment.outside.relativeHumidity', mt.time),
                last(mt.metrics->>'environment.outside.humidity', mt.time)
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                last(mt.metrics->'pressure'->>'outside', mt.time),
                last(mt.metrics->>(md.configuration->>'outsidePressureKey'), mt.time),
                last(mt.metrics->>'environment.outside.pressure', mt.time)
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                last(mt.metrics->'temperature'->>'outside', mt.time),
                last(mt.metrics->>(md.configuration->>'outsideTemperatureKey'), mt.time),
                last(mt.metrics->>'environment.outside.temperature', mt.time)
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                last(mt.metrics->'battery'->>'charge', mt.time),
                last(mt.metrics->>(md.configuration->>'stateOfChargeKey'), mt.time),
                last(mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge', mt.time)
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                last(mt.metrics->'battery'->>'voltage', mt.time),
                last(mt.metrics->>(md.configuration->>'voltageKey'), mt.time),
                last(mt.metrics->>'electrical.batteries.House.voltage', mt.time)
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                last(mt.metrics->'solar'->>'power', mt.time),
                last(mt.metrics->>(md.configuration->>'solarPowerKey'), mt.time),
                last(mt.metrics->>'electrical.solar.Main.panelPower', mt.time)
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                last(mt.metrics->'solar'->>'voltage', mt.time),
                last(mt.metrics->>(md.configuration->>'solarVoltageKey'), mt.time),
                last(mt.metrics->>'electrical.solar.Main.panelVoltage', mt.time)
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                last(mt.metrics->'tank'->>'level', mt.time),
                last(mt.metrics->>(md.configuration->>'tankLevelKey'), mt.time),
                last(mt.metrics->>'tanks.fuel.0.currentLevel', mt.time)
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(last(mt.longitude, mt.time),last(mt.latitude, mt.time)) AS geo_point
        FROM api.metrics mt
        JOIN api.metadata md ON md.vessel_id = mt.vessel_id
        WHERE mt.latitude IS NOT NULL
            AND mt.longitude IS NOT NULL
            AND mt.time > (start_date + interval '10 minutes')
            AND mt.time < (end_date - interval '10 minutes')
            AND mt.vessel_id = current_setting('vessel.id', false)
        GROUP BY time_bucket
        ORDER BY time_bucket ASC
    ),
    first_metric AS (
        -- Extract first 10 minutes metrics
        SELECT 
            mt.time AS time_bucket,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT AS truewinddirection,
            -- Water Temperature
            COALESCE(
                mt.metrics->'water'->>'temperature',
                mt.metrics->>(md.configuration->>'waterTemperatureKey'),
                mt.metrics->>'environment.water.temperature'
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                mt.metrics->'water'->>'depth',
                mt.metrics->>(md.configuration->>'depthKey'),
                mt.metrics->>'environment.depth.belowTransducer'
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                mt.metrics->'humidity'->>'outside',
                mt.metrics->>(md.configuration->>'outsideHumidityKey'),
                mt.metrics->>'environment.outside.relativeHumidity',
                mt.metrics->>'environment.outside.humidity'
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                mt.metrics->'pressure'->>'outside',
                mt.metrics->>(md.configuration->>'outsidePressureKey'),
                mt.metrics->>'environment.outside.pressure'
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                mt.metrics->'temperature'->>'outside',
                mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
                mt.metrics->>'environment.outside.temperature'
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                mt.metrics->'battery'->>'charge',
                mt.metrics->>(md.configuration->>'stateOfChargeKey'),
                mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                mt.metrics->'battery'->>'voltage',
                mt.metrics->>(md.configuration->>'voltageKey'),
                mt.metrics->>'electrical.batteries.House.voltage'
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                mt.metrics->'solar'->>'power',
                mt.metrics->>(md.configuration->>'solarPowerKey'),
                mt.metrics->>'electrical.solar.Main.panelPower'
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                mt.metrics->'solar'->>'voltage',
                mt.metrics->>(md.configuration->>'solarVoltageKey'),
                mt.metrics->>'electrical.solar.Main.panelVoltage'
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                mt.metrics->'tank'->>'level',
                mt.metrics->>(md.configuration->>'tankLevelKey'),
                mt.metrics->>'tanks.fuel.0.currentLevel'
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(mt.longitude, mt.latitude) AS geo_point
        FROM api.metrics mt
        JOIN api.metadata md ON md.vessel_id = mt.vessel_id
        WHERE mt.latitude IS NOT NULL
            AND mt.longitude IS NOT NULL
            AND mt.time >= start_date
            AND mt.time < (start_date + interval '10 minutes')
            AND mt.vessel_id = current_setting('vessel.id', false)
        ORDER BY time_bucket ASC
    ),
    last_metric AS (
        -- Extract last 10 minutes metrics
        SELECT 
            mt.time AS time_bucket,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT AS heading,
            -- Wind Speed True
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT AS truewindspeed,
            -- Wind Direction True
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT AS truewinddirection,
            -- Water Temperature
            COALESCE(
                mt.metrics->'water'->>'temperature',
                mt.metrics->>(md.configuration->>'waterTemperatureKey'),
                mt.metrics->>'environment.water.temperature'
            )::FLOAT AS waterTemperature,
            -- Water Depth
            COALESCE(
                mt.metrics->'water'->>'depth',
                mt.metrics->>(md.configuration->>'depthKey'),
                mt.metrics->>'environment.depth.belowTransducer'
            )::FLOAT AS depth,
            -- Outside Humidity
            COALESCE(
                mt.metrics->'humidity'->>'outside',
                mt.metrics->>(md.configuration->>'outsideHumidityKey'),
                mt.metrics->>'environment.outside.relativeHumidity',
                mt.metrics->>'environment.outside.humidity'
            )::FLOAT AS outsideHumidity,
            -- Outside Pressure
            COALESCE(
                mt.metrics->'pressure'->>'outside',
                mt.metrics->>(md.configuration->>'outsidePressureKey'),
                mt.metrics->>'environment.outside.pressure'
            )::FLOAT AS outsidePressure,
            -- Outside Temperature
            COALESCE(
                mt.metrics->'temperature'->>'outside',
                mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
                mt.metrics->>'environment.outside.temperature'
            )::FLOAT AS outsideTemperature,
            -- Battery Charge (State of Charge)
            COALESCE(
                mt.metrics->'battery'->>'charge',
                mt.metrics->>(md.configuration->>'stateOfChargeKey'),
                mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
            )::FLOAT AS stateofcharge,
            -- Battery Voltage
            COALESCE(
                mt.metrics->'battery'->>'voltage',
                mt.metrics->>(md.configuration->>'voltageKey'),
                mt.metrics->>'electrical.batteries.House.voltage'
            )::FLOAT AS voltage,
            -- Solar Power
            COALESCE(
                mt.metrics->'solar'->>'power',
                mt.metrics->>(md.configuration->>'solarPowerKey'),
                mt.metrics->>'electrical.solar.Main.panelPower'
            )::FLOAT AS solarPower,
            -- Solar Voltage
            COALESCE(
                mt.metrics->'solar'->>'voltage',
                mt.metrics->>(md.configuration->>'solarVoltageKey'),
                mt.metrics->>'electrical.solar.Main.panelVoltage'
            )::FLOAT AS solarVoltage,
            -- Tank Level
            COALESCE(
                mt.metrics->'tank'->>'level',
                mt.metrics->>(md.configuration->>'tankLevelKey'),
                mt.metrics->>'tanks.fuel.0.currentLevel'
            )::FLOAT AS tankLevel,
            -- Geo Point
            ST_MakePoint(mt.longitude, mt.latitude) AS geo_point
        FROM api.metrics mt
        JOIN api.metadata md ON md.vessel_id = mt.vessel_id
        WHERE mt.latitude IS NOT NULL
            AND mt.longitude IS NOT NULL
            AND mt.time <= end_date
            AND mt.time > (end_date - interval '10 minutes')
            AND mt.vessel_id = current_setting('vessel.id', false)
        ORDER BY time_bucket ASC
    ),
    optimize_metrics AS (
        -- Combine and order the results
        SELECT * FROM first_metric
        UNION ALL
        SELECT * FROM metrics
        UNION ALL
        SELECT * FROM last_metric
        ORDER BY time_bucket ASC
    )
    -- Create mobilitydb temporal sequences
    SELECT 
        tgeogpointseq(array_agg(tgeogpoint(ST_SetSRID(o.geo_point, 4326)::geography, o.time_bucket) ORDER BY o.time_bucket ASC)) AS trajectory,
        tfloatseq(array_agg(tfloat(o.courseovergroundtrue, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.courseovergroundtrue IS NOT NULL)) AS courseovergroundtrue,
        tfloatseq(array_agg(tfloat(o.speedoverground, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.speedoverground IS NOT NULL)) AS speedoverground,
        tfloatseq(array_agg(tfloat(o.windspeedapparent, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.windspeedapparent IS NOT NULL)) AS windspeedapparent,
        tfloatseq(array_agg(tfloat(o.truewindspeed, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.truewindspeed IS NOT NULL)) AS truewindspeed,
        tfloatseq(array_agg(tfloat(o.truewinddirection, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.truewinddirection IS NOT NULL)) AS truewinddirection,
        ttextseq(array_agg(ttext(o.notes, o.time_bucket) ORDER BY o.time_bucket ASC)) AS notes,
        ttextseq(array_agg(ttext(o.status, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.status IS NOT NULL)) AS status,
        tfloatseq(array_agg(tfloat(o.watertemperature, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.watertemperature IS NOT NULL)) AS watertemperature,
        tfloatseq(array_agg(tfloat(o.depth, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.depth IS NOT NULL)) AS depth,
        tfloatseq(array_agg(tfloat(o.outsidehumidity, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.outsidehumidity IS NOT NULL)) AS outsidehumidity,
        tfloatseq(array_agg(tfloat(o.outsidepressure, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.outsidepressure IS NOT NULL)) AS outsidepressure,
        tfloatseq(array_agg(tfloat(o.outsidetemperature, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.outsidetemperature IS NOT NULL)) AS outsidetemperature,
        tfloatseq(array_agg(tfloat(o.stateofcharge, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.stateofcharge IS NOT NULL)) AS stateofcharge,
        tfloatseq(array_agg(tfloat(o.voltage, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.voltage IS NOT NULL)) AS voltage,
        tfloatseq(array_agg(tfloat(o.solarPower, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.solarPower IS NOT NULL)) AS solarPower,
        tfloatseq(array_agg(tfloat(o.solarVoltage, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.solarVoltage IS NOT NULL)) AS solarVoltage,
        tfloatseq(array_agg(tfloat(o.tankLevel, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.tankLevel IS NOT NULL)) AS tankLevel,
        tfloatseq(array_agg(tfloat(o.heading, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.heading IS NOT NULL)) AS heading
    FROM optimize_metrics o;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.logbook_update_metrics_timebucket_fn
    IS 'Optimize logbook metrics base on the aggregate time-series';

-- DROP FUNCTION public.process_logbook_queue_fn(int4);
-- Update public.process_logbook_queue_fn to use new mobilitydb metrics
CREATE OR REPLACE FUNCTION public.process_logbook_queue_fn(_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
    DECLARE
        logbook_rec record;
        from_name text;
        to_name text;
        log_name text;
        from_moorage record;
        to_moorage record;
        avg_rec record;
        geo_rec record;
        t_rec record;
        log_settings jsonb;
        user_settings jsonb;
        geojson jsonb;
        extra_json jsonb;
    BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_logbook_queue_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Get the logbook record with all necessary fields exist
        SELECT * INTO logbook_rec
            FROM api.logbook
            WHERE active IS false
                AND id = _id
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        -- Ensure the query is successful
        IF logbook_rec.vessel_id IS NULL THEN
            RAISE WARNING '-> process_logbook_queue_fn invalid logbook %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', logbook_rec.vessel_id, false);
        --RAISE WARNING 'public.process_logbook_queue_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);

        -- Calculate logbook data average and geo
        -- Update logbook entry with the latest metric data and calculate data
        avg_rec := public.logbook_update_avg_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        geo_rec := public.logbook_update_geom_distance_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);

        -- Do we have an existing moorage within 300m of the new log
        -- generate logbook name, concat _from_location and _to_location from moorage name
        from_moorage := public.process_lat_lon_fn(logbook_rec._from_lng::NUMERIC, logbook_rec._from_lat::NUMERIC);
        to_moorage := public.process_lat_lon_fn(logbook_rec._to_lng::NUMERIC, logbook_rec._to_lat::NUMERIC);
        SELECT CONCAT(from_moorage.moorage_name, ' to ' , to_moorage.moorage_name) INTO log_name;

        -- Process `propulsion.*.runTime` and `navigation.log`
        -- Calculate extra json
        extra_json := public.logbook_update_extra_json_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        -- add the avg_wind_speed
        extra_json := extra_json || jsonb_build_object('avg_wind_speed', avg_rec.avg_wind_speed);

        -- mobilitydb, add spaciotemporal sequence
        -- reduce the numbers of metrics by skipping row or aggregate time-series
        -- By default the signalk PostgSail plugin report one entry every minute.
        IF avg_rec.count_metric < 30 THEN -- if less ~20min trip we keep it all data
            t_rec := public.logbook_update_metrics_short_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        ELSIF avg_rec.count_metric < 2000 THEN -- if less ~33h trip we skip data
            t_rec := public.logbook_update_metrics_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        ELSE -- As we have too many data, we time-series aggregate data
            t_rec := public.logbook_update_metrics_timebucket_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        END IF;
        --RAISE NOTICE 'mobilitydb [%]', t_rec;
        IF t_rec.trajectory IS NULL THEN
            RAISE WARNING '-> process_logbook_queue_fn, vessel_id [%], invalid mobilitydb data [%] [%]', logbook_rec.vessel_id, _id, t_rec;
            RETURN;
        END IF;

        RAISE NOTICE 'Updating valid logbook, vessel_id [%], entry logbook id:[%] start:[%] end:[%]', logbook_rec.vessel_id, logbook_rec.id, logbook_rec._from_time, logbook_rec._to_time;
        UPDATE api.logbook
            SET
                duration = (logbook_rec._to_time::TIMESTAMPTZ - logbook_rec._from_time::TIMESTAMPTZ),
                avg_speed = avg_rec.avg_speed,
                max_speed = avg_rec.max_speed,
                max_wind_speed = avg_rec.max_wind_speed,
                _from = from_moorage.moorage_name,
                _from_moorage_id = from_moorage.moorage_id,
                _to_moorage_id = to_moorage.moorage_id,
                _to = to_moorage.moorage_name,
                name = log_name,
                distance = geo_rec._track_distance,
                extra = extra_json,
                notes = NULL, -- reset pre_log process
                trip = t_rec.trajectory,
                trip_cog = t_rec.courseovergroundtrue,
                trip_sog = t_rec.speedoverground,
                trip_twa = t_rec.windspeedapparent,
                trip_tws = t_rec.truewindspeed,
                trip_twd = t_rec.truewinddirection,
                trip_notes = t_rec.notes,
                trip_status = t_rec.status,
                trip_depth = t_rec.depth,
                trip_batt_charge = t_rec.stateofcharge,
                trip_batt_voltage = t_rec.voltage,
                trip_temp_water = t_rec.watertemperature,
                trip_temp_out = t_rec.outsidetemperature,
                trip_pres_out = t_rec.outsidepressure,
                trip_hum_out = t_rec.outsidehumidity,
                trip_tank_level = t_rec.tankLevel,
                trip_solar_voltage = t_rec.solarVoltage,
                trip_solar_power = t_rec.solarPower,
                trip_heading = t_rec.heading
            WHERE id = logbook_rec.id;

        /*** Deprecated removed column
        -- GeoJSON require track_geom field geometry linestring
        --geojson := logbook_update_geojson_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        -- GeoJSON require trip* columns
        geojson := api.logbook_update_geojson_trip_fn(logbook_rec.id);
        UPDATE api.logbook
            SET -- Update the data column, it should be generate dynamically on request
                -- However there is a lot of dependencies to concider for a larger cleanup
                -- badges, qgis etc... depends on track_geom
                -- many export and others functions depends on track_geojson
                track_geojson = geojson,
                track_geog = trajectory(t_rec.trajectory),
                track_geom = trajectory(t_rec.trajectory)::geometry
            WHERE id = logbook_rec.id;

        -- GeoJSON Timelapse require track_geojson geometry point
        -- Add properties to the geojson for timelapse purpose
        PERFORM public.logbook_timelapse_geojson_fn(logbook_rec.id);
        */
        -- Add post logbook entry to process queue for notification and QGIS processing
        -- Require as we need the logbook to be updated with SQL commit
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('post_logbook', logbook_rec.id, NOW(), current_setting('vessel.id', true));

    END;
$function$
;
-- Description
COMMENT ON FUNCTION public.process_logbook_queue_fn(int4) IS 'Update logbook details when completed, logbook_update_avg_fn, logbook_update_geom_distance_fn, reverse_geocode_py_fn';

-- Remove unnecessary functions
DROP FUNCTION IF EXISTS api.monitoring_upsert_fn;
-- Add missing comments on function
COMMENT ON FUNCTION public.new_account_entry_fn() IS 'trigger process_queue on INSERT ofr new account';

-- Update public.cron_process_monitor_online_fn, refactor of metadata
CREATE OR REPLACE FUNCTION public.cron_process_monitor_online_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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
        RAISE NOTICE '-> cron_process_monitor_online_fn metadata_vessel_id [%]', process_rec.payload;
        SELECT vessel_id INTO metadata_rec
            FROM api.metadata
            WHERE vessel_id = process_rec.payload::TEXT;

        IF metadata_rec.vessel_id IS NULL OR metadata_rec.vessel_id = '' THEN
            RAISE WARNING '-> cron_process_monitor_online_fn invalid metadata record vessel_id [%]', metadata_rec;
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
$function$
;
-- Description
COMMENT ON FUNCTION public.cron_process_monitor_online_fn() IS 'refactor of metadata';

-- DROP FUNCTION public.cron_process_monitor_offline_fn();
-- Update public.cron_process_monitor_offline_fn, Refactor metadata
CREATE OR REPLACE FUNCTION public.cron_process_monitor_offline_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
declare
    metadata_rec record;
    process_id integer;
    user_settings jsonb;
    app_settings jsonb;
    metrics_rec record;
begin
    -- Check metadata last_update > 1h + cron_time(10m)
    RAISE NOTICE 'cron_process_monitor_offline_fn';
    FOR metadata_rec in 
        SELECT
            vessel_id,
            time,
            NOW() AT TIME ZONE 'UTC' as now, 
            NOW() AT TIME ZONE 'UTC' - INTERVAL '70 MINUTES' as interval
        FROM api.metadata m
        WHERE 
            m.time < NOW() AT TIME ZONE 'UTC' - INTERVAL '70 MINUTES'
            AND active = True
        ORDER BY m.time DESC
    LOOP
        RAISE NOTICE '-> cron_process_monitor_offline_fn metadata_vessel_id [%]', metadata_rec.vessel_id;

        IF metadata_rec.vessel_id IS NULL OR metadata_rec.vessel_id = '' THEN
            RAISE WARNING '-> cron_process_monitor_offline_fn invalid metadata record vessel_id [%]', metadata_rec;
            RAISE EXCEPTION 'Invalid metadata'
                USING HINT = 'Unknown vessel_id';
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', metadata_rec.vessel_id, false);

        -- Ensure we don't have any metrics for the same period.
        SELECT time AS "time",
                (NOW() AT TIME ZONE 'UTC' - time) > INTERVAL '70 MINUTES' as offline
                INTO metrics_rec
            FROM api.metrics m 
            WHERE vessel_id = current_setting('vessel.id', false)
            ORDER BY time DESC LIMIT 1;
        RAISE NOTICE '-> cron_process_monitor_offline_fn metadata:[%] metrics:[%]', metadata_rec, metrics_rec;
        IF metrics_rec.offline IS False THEN
            CONTINUE; -- skip if we have metrics for the same period
        END IF;

        -- vessel is offline, update api.metadata table, set active to bool false
        UPDATE api.metadata
            SET 
                active = False
            WHERE vessel_id = current_setting('vessel.id', false);

        RAISE NOTICE '-> cron_process_monitor_offline_fn, vessel.id [%], updated api.metadata table to inactive', current_setting('vessel.id', false);

        -- Gather email and pushover app settings
        --app_settings = get_app_settings_fn();
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(metadata_rec.vessel_id::TEXT);
        RAISE DEBUG '-> cron_process_monitor_offline_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('monitor_offline'::TEXT, user_settings::JSONB);
        -- log/insert/update process_queue table with processed
        INSERT INTO process_queue
            (channel, payload, stored, processed, ref_id)
            VALUES 
                ('monitoring_offline', metadata_rec.vessel_id::TEXT, metadata_rec.interval, now(), metadata_rec.vessel_id)
            RETURNING id INTO process_id;
        RAISE NOTICE '-> cron_process_monitor_offline_fn updated process_queue table [%]', process_id;
    END LOOP;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.cron_process_monitor_offline_fn() IS 'init by pg_cron to monitor offline pending notification, if so perform send_email o send_pushover base on user preferences';

-- DROP FUNCTION public.cron_process_grafana_fn();
-- Update public.cron_process_grafana_fn, Refactor metadata
CREATE OR REPLACE FUNCTION public.cron_process_grafana_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    process_rec record;
    data_rec record;
    app_settings jsonb;
    user_settings jsonb;
BEGIN
    -- We run grafana provisioning only after the first received vessel metadata
    -- Check for new vessel metadata pending grafana provisioning
    RAISE NOTICE 'cron_process_grafana_fn';
    FOR process_rec in
        SELECT * from process_queue
            where channel = 'grafana' and processed is null
            order by stored asc
    LOOP
        RAISE NOTICE '-> cron_process_grafana_fn [%]', process_rec.payload;
        -- Gather url from app settings
        app_settings := get_app_settings_fn();
        -- Get vessel details base on metadata id
        SELECT
            v.owner_email,coalesce(m.name,v.name) as name,m.vessel_id into data_rec
            FROM auth.vessels v
            LEFT JOIN api.metadata m ON v.vessel_id = m.vessel_id
            WHERE m.vessel_id = process_rec.payload::TEXT;
        IF data_rec.vessel_id IS NULL OR data_rec.name IS NULL THEN
            RAISE WARNING '-> DEBUG cron_process_grafana_fn grafana_py_fn error [%]', data_rec;
            RETURN;
        END IF;
        -- as we got data from the vessel we can do the grafana provisioning.
        RAISE DEBUG '-> DEBUG cron_process_grafana_fn grafana_py_fn provisioning [%]', data_rec;
        PERFORM grafana_py_fn(data_rec.name, data_rec.vessel_id, data_rec.owner_email, app_settings);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(data_rec.vessel_id::TEXT);
        RAISE DEBUG '-> DEBUG cron_process_grafana_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        -- add user in keycloak
        PERFORM keycloak_auth_py_fn(data_rec.vessel_id, user_settings, app_settings);
        -- Send notification
        PERFORM send_notification_fn('grafana'::TEXT, user_settings::JSONB);
        -- update process_queue entry as processed
        UPDATE process_queue
            SET
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_grafana_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.cron_process_grafana_fn() IS 'init by pg_cron to check for new vessel pending grafana provisioning, if so perform grafana_py_fn';

-- DROP FUNCTION public.cron_process_skplugin_upgrade_fn();
-- Update cron_process_skplugin_upgrade_fn, update check for signalk plugin version
CREATE OR REPLACE FUNCTION public.cron_process_skplugin_upgrade_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    skplugin_upgrade_rec record;
    user_settings jsonb;
BEGIN
    -- Check for signalk plugin version
    RAISE NOTICE 'cron_process_plugin_upgrade_fn';
    FOR skplugin_upgrade_rec in
        SELECT
            v.owner_email,m.name,m.vessel_id,m.plugin_version,a.first
            FROM api.metadata m
            LEFT JOIN auth.vessels v ON v.vessel_id = m.vessel_id
            LEFT JOIN auth.accounts a ON v.owner_email = a.email
            WHERE m.plugin_version <> '0.4.1'
    LOOP
        RAISE NOTICE '-> cron_process_skplugin_upgrade_rec_fn for [%]', skplugin_upgrade_rec;
        SELECT json_build_object('email', skplugin_upgrade_rec.owner_email, 'recipient', skplugin_upgrade_rec.first) into user_settings;
        RAISE NOTICE '-> debug cron_process_skplugin_upgrade_rec_fn [%]', user_settings;
        -- Send notification
        PERFORM send_notification_fn('skplugin_upgrade'::TEXT, user_settings::JSONB);
    END LOOP;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.cron_process_skplugin_upgrade_fn() IS 'init by pg_cron, check for signalk plugin version and notify for upgrade';

-- DROP FUNCTION public.cron_alerts_fn();
-- Update public.cron_alerts_fn, add support for custom monitoring path
CREATE OR REPLACE FUNCTION public.cron_alerts_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    alert_rec record;
    default_last_metric TIMESTAMPTZ := NOW() - interval '1 day';
    last_metric TIMESTAMPTZ;
    metric_rec record;
    app_settings JSONB;
    user_settings JSONB;
    alerting JSONB;
    _alarms JSONB;
    alarms TEXT;
    alert_default JSONB := '{
        "low_pressure_threshold": 990,
        "high_wind_speed_threshold": 30,
        "low_water_depth_threshold": 1,
        "min_notification_interval": 6,
        "high_pressure_drop_threshold": 12,
        "low_battery_charge_threshold": 90,
        "low_battery_voltage_threshold": 12.5,
        "low_water_temperature_threshold": 10,
        "low_indoor_temperature_threshold": 7,
        "low_outdoor_temperature_threshold": 3
    }';
BEGIN
    -- Check for new event notification pending update
    RAISE NOTICE 'cron_alerts_fn';
    FOR alert_rec in
        SELECT
            a.user_id,a.email,v.vessel_id,
            COALESCE((a.preferences->'alert_last_metric')::TEXT, default_last_metric::TEXT) as last_metric,
            (alert_default || (a.preferences->'alerting')::JSONB) as alerting,
            (a.preferences->'alarms')::JSONB as alarms,
            m.configuration as config
            FROM auth.accounts a
            LEFT JOIN auth.vessels AS v ON v.owner_email = a.email
            LEFT JOIN api.metadata AS m ON m.vessel_id = v.vessel_id
            WHERE (a.preferences->'alerting'->'enabled')::boolean = True
                AND m.active = True
        LOOP
        RAISE NOTICE '-> cron_alerts_fn for [%]', alert_rec;
        PERFORM set_config('vessel.id', alert_rec.vessel_id, false);
        PERFORM set_config('user.email', alert_rec.email, false);
        --RAISE WARNING 'public.cron_process_alert_rec_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(alert_rec.vessel_id::TEXT);
        RAISE NOTICE '-> cron_alerts_fn checking user_settings [%]', user_settings;
        -- Get all metrics from the last last_metric avg by 5 minutes
        FOR metric_rec in
            SELECT time_bucket('5 minutes', m.time) AS time_bucket,
                    avg((m.metrics->'environment.inside.temperature')::NUMERIC) AS intemp,
                    avg((m.metrics->'environment.wind.speedTrue')::NUMERIC) AS wind,
                    avg((m.metrics->'environment.depth.belowTransducer')::NUMERIC) AS watdepth,
                    avg(-- Outside Temperature
                        COALESCE(
                            m.metrics->'temperature'->>'outside',
                            m.metrics->>(alert_rec.config->>'outsideTemperatureKey'),
                            m.metrics->>'environment.outside.temperature'
                        )::NUMERIC) AS outtemp,
                    avg(-- Water Temperature
                        COALESCE(
                            m.metrics->'water'->>'temperature',
                            m.metrics->>(alert_rec.config->>'waterTemperatureKey'),
                            m.metrics->>'environment.water.temperature'
                        )::NUMERIC) AS wattemp,
                    avg(-- Outside Pressure
                        COALESCE(
                            m.metrics->'pressure'->>'outside',
                            m.metrics->>(alert_rec.config->>'outsidePressureKey'),
                            m.metrics->>'environment.outside.pressure'
                        )::NUMERIC) AS pressure,
                    avg(-- Battery Voltage
                        COALESCE(
                            m.metrics->'battery'->>'voltage',
                            m.metrics->>(alert_rec.config->>'voltageKey'),
                            m.metrics->>'electrical.batteries.House.voltage'
                        )::NUMERIC) AS voltage,
                    avg(-- Battery Charge (State of Charge)
                        COALESCE(
                            m.metrics->'battery'->>'charge',
                            m.metrics->>(alert_rec.config->>'stateOfChargeKey'),
                            m.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
                        )::NUMERIC) AS charge
                FROM api.metrics m
                WHERE vessel_id = alert_rec.vessel_id
                    AND m.time >= alert_rec.last_metric::TIMESTAMPTZ
                GROUP BY time_bucket
                ORDER BY time_bucket ASC LIMIT 100
        LOOP
            RAISE NOTICE '-> cron_alerts_fn checking metrics [%]', metric_rec;
            RAISE NOTICE '-> cron_alerts_fn checking alerting [%]', alert_rec.alerting;
            --RAISE NOTICE '-> cron_alerts_fn checking debug [%] [%]', kelvinToCel(metric_rec.intemp), (alert_rec.alerting->'low_indoor_temperature_threshold');
            IF metric_rec.intemp IS NOT NULL AND public.kelvintocel(metric_rec.intemp::NUMERIC) < (alert_rec.alerting->'low_indoor_temperature_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_indoor_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_indoor_temperature_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_indoor_temperature_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_indoor_temperature_threshold": {"value": '|| kelvinToCel(metric_rec.intemp) ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_outdoor_temperature_threshold value:'|| kelvinToCel(metric_rec.intemp) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_indoor_temperature_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_indoor_temperature_threshold';
            END IF;
            IF metric_rec.outtemp IS NOT NULL AND public.kelvintocel(metric_rec.outtemp::NUMERIC) < (alert_rec.alerting->>'low_outdoor_temperature_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_outdoor_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_outdoor_temperature_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_outdoor_temperature_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_outdoor_temperature_threshold": {"value": '|| kelvinToCel(metric_rec.outtemp) ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_outdoor_temperature_threshold value:'|| kelvinToCel(metric_rec.outtemp) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_outdoor_temperature_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_outdoor_temperature_threshold';
            END IF;
            IF metric_rec.wattemp IS NOT NULL AND public.kelvintocel(metric_rec.wattemp::NUMERIC) < (alert_rec.alerting->>'low_water_temperature_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_water_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_water_temperature_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_water_temperature_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_water_temperature_threshold": {"value": '|| kelvinToCel(metric_rec.wattemp) ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_water_temperature_threshold value:'|| kelvinToCel(metric_rec.wattemp) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_water_temperature_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_water_temperature_threshold';
            END IF;
            IF metric_rec.watdepth IS NOT NULL AND metric_rec.watdepth::NUMERIC < (alert_rec.alerting->'low_water_depth_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_water_depth_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_water_depth_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_water_depth_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_water_depth_threshold": {"value": '|| metric_rec.watdepth ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_water_depth_threshold value:'|| ROUND(metric_rec.watdepth,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_water_depth_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_water_depth_threshold';
            END IF;
            if metric_rec.pressure IS NOT NULL AND metric_rec.pressure::NUMERIC < (alert_rec.alerting->'high_pressure_drop_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'high_pressure_drop_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'high_pressure_drop_threshold'->>'date') IS NULL) OR
                    (((_alarms->'high_pressure_drop_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"high_pressure_drop_threshold": {"value": '|| metric_rec.pressure ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "high_pressure_drop_threshold value:'|| ROUND(metric_rec.pressure,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug high_pressure_drop_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug high_pressure_drop_threshold';
            END IF;
            IF metric_rec.wind IS NOT NULL AND metric_rec.wind::NUMERIC > (alert_rec.alerting->'high_wind_speed_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'high_wind_speed_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'high_wind_speed_threshold'->>'date') IS NULL) OR
                    (((_alarms->'high_wind_speed_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"high_wind_speed_threshold": {"value": '|| metric_rec.wind ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "high_wind_speed_threshold value:'|| ROUND(metric_rec.wind,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug high_wind_speed_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug high_wind_speed_threshold';
            END IF;
            if metric_rec.voltage IS NOT NULL AND metric_rec.voltage::NUMERIC < (alert_rec.alerting->'low_battery_voltage_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_battery_voltage_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_battery_voltage_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_battery_voltage_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_battery_voltage_threshold": {"value": '|| metric_rec.voltage ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_battery_voltage_threshold value:'|| ROUND(metric_rec.voltage,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_voltage_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_voltage_threshold';
            END IF;
            if metric_rec.charge IS NOT NULL AND (metric_rec.charge::NUMERIC*100) < (alert_rec.alerting->'low_battery_charge_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_battery_charge_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
                -- Get latest alarms
                SELECT preferences->'alarms' INTO _alarms FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Is alarm in the min_notification_interval time frame
                IF (
                    ((_alarms->'low_battery_charge_threshold'->>'date') IS NULL) OR
                    (((_alarms->'low_battery_charge_threshold'->>'date')::TIMESTAMPTZ
                    + ((interval '1 hour') * (alert_rec.alerting->>'min_notification_interval')::NUMERIC))
                    < metric_rec.time_bucket::TIMESTAMPTZ)
                    ) THEN
                    -- Add alarm
                    alarms := '{"low_battery_charge_threshold": {"value": '|| (metric_rec.charge*100) ||', "date":"' || metric_rec.time_bucket || '"}}';
                    -- Merge alarms
                    SELECT public.jsonb_recursive_merge(_alarms::jsonb, alarms::jsonb) into _alarms;
                    -- Update alarms for user
                    PERFORM api.update_user_preferences_fn('{alarms}'::TEXT, _alarms::TEXT);
                    -- Gather user settings
                    user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                    SELECT user_settings::JSONB || ('{"alert": "low_battery_charge_threshold value:'|| ROUND(metric_rec.charge::NUMERIC*100,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_charge_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_charge_threshold';
            END IF;
            -- Record last metrics time
            SELECT metric_rec.time_bucket INTO last_metric;
        END LOOP;
        PERFORM api.update_user_preferences_fn('{alert_last_metric}'::TEXT, last_metric::TEXT);
    END LOOP;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.cron_alerts_fn() IS 'init by pg_cron to check for alerts';

DROP FUNCTION IF EXISTS public.kelvintocel(numeric);
-- Update public.kelvintocel, Add an overloaded kelvintocel(double precision) function
CREATE OR REPLACE FUNCTION public.kelvintocel(temperature double precision)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
	RETURN ROUND((((temperature)::numeric - 273.15) * 10) / 10);
END
$function$
;
-- Description
COMMENT ON FUNCTION public.kelvintocel(double precision) IS 'convert kelvin To Celsius';

-- DROP FUNCTION public.run_cron_jobs();
-- Udpate public.run_cron_jobs, add cron_process_autodiscovery_fn function calls
CREATE OR REPLACE FUNCTION public.run_cron_jobs()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
    -- In correct order
    perform public.cron_process_new_notification_fn();
    perform public.cron_process_monitor_online_fn();
    --perform public.cron_process_grafana_fn();
    perform public.cron_process_pre_logbook_fn();
    perform public.cron_process_new_logbook_fn();
    perform public.cron_process_post_logbook_fn();
    perform public.cron_process_new_stay_fn();
    --perform public.cron_process_new_moorage_fn();
    perform public.cron_process_monitor_offline_fn();
    perform public.cron_process_autodiscovery_fn();
END
$function$
;

-- Create view api.noteshistory_view, List stays and moorages notes order by stays
DROP VIEW IF EXISTS api.noteshistory_view;
CREATE OR REPLACE VIEW api.noteshistory_view WITH (security_invoker=true,security_barrier=true) AS
    -- List moorages notes order by stays
    SELECT
        s.id AS stay_id,
        m.id AS moorage_id,
        m.name AS moorage_name,
        s.name AS stay_name,
        s.arrived,
        s.stay_code,
        s.latitude,
        s.longitude,
        s.notes as stay_notes,
        m.notes as moorage_notes,
        --image IS NOT NULL AS has_image,
        CASE
            WHEN image IS NULL AND image_url IS NOT NULL THEN True
            WHEN image IS NOT NULL AND image_url IS NULL THEN True
            ELSE False
        END AS has_image,
        CASE
            WHEN image IS NULL AND image_url IS NOT NULL THEN image_url
            WHEN image IS NOT NULL AND image_url IS NULL THEN '/rpc/stays_image?v_id=' || s.vessel_id || '&_id=' || s.id
            ELSE NULL
        END AS image_url
    FROM
        api.stays s
    LEFT JOIN
        api.moorages m ON s.moorage_id = m.id
    LEFT JOIN
        api.stays_ext se ON s.vessel_id = se.vessel_id AND s.id = se.stay_id
    WHERE s.vessel_id = current_setting('vessel.id', false)
    ORDER BY s.arrived DESC;
-- Description
COMMENT ON VIEW api.noteshistory_view IS 'List moorages notes order by stays';

-- DROP FUNCTION public.process_stay_queue_fn(int4);
-- Udpate public.process_stay_queue_fn, replace '0 day' stay name by 'short stay' name
CREATE OR REPLACE FUNCTION public.process_stay_queue_fn(_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
    DECLARE
        stay_rec record;
        moorage record;
    BEGIN
        RAISE NOTICE 'process_stay_queue_fn';
        -- If _id is valid, not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_stay_queue_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Get the stay record with all necessary fields exist
        SELECT * INTO stay_rec
            FROM api.stays
            WHERE active IS false
                AND departed IS NOT NULL
                AND arrived IS NOT NULL
                AND longitude IS NOT NULL
                AND latitude IS NOT NULL
                AND id = _id;
        -- Ensure the query is successful
        IF stay_rec.vessel_id IS NULL THEN
            RAISE WARNING '-> process_stay_queue_fn invalid stay %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', stay_rec.vessel_id, false);

        -- Do we have an existing moorage within 300m of the new stay
        moorage := process_lat_lon_fn(stay_rec.longitude::NUMERIC, stay_rec.latitude::NUMERIC);

        RAISE NOTICE '-> process_stay_queue_fn Updating stay entry [%]', stay_rec.id;
        UPDATE api.stays
        SET
            name = CONCAT(
                CASE
                    WHEN ROUND(EXTRACT(EPOCH FROM (stay_rec.departed::timestamptz - stay_rec.arrived::timestamptz)) / 86400) = 0
                    THEN 'Short'
                    ELSE ROUND(EXTRACT(EPOCH FROM (stay_rec.departed::timestamptz - stay_rec.arrived::timestamptz)) / 86400)::TEXT || ' days'
                END,
                ' stay at ',
                moorage.moorage_name,
                ' in ',
                RTRIM(TO_CHAR(stay_rec.departed, 'Month')),
                ' ',
                TO_CHAR(stay_rec.departed, 'YYYY')
            ),
            moorage_id = moorage.moorage_id,
            duration = (stay_rec.departed::timestamptz - stay_rec.arrived::timestamptz),
            stay_code = moorage.moorage_type,
            geog = Geography(ST_MakePoint(stay_rec.longitude, stay_rec.latitude))
        WHERE id = stay_rec.id;

        RAISE NOTICE '-> process_stay_queue_fn Updating moorage entry [%]', moorage.moorage_id;
        /* reference_count and stay_duration are dynamically calculated
        UPDATE api.moorages
            SET
                reference_count = (
                    with _from as (select count(*) from api.logbook where _from_moorage_id = moorage.moorage_id),
                        _to as (select count(*) from api.logbook where _to_moorage_id = moorage.moorage_id)
                        select _from.count+_to.count from _from,_to
                ),
                stay_duration = (
                    select sum(departed-arrived) from api.stays where moorage_id = moorage.moorage_id
                )
            WHERE id = moorage.moorage_id;
        */
        -- Process badges
        PERFORM badges_moorages_fn();
    END;
$function$
;

COMMENT ON FUNCTION public.process_stay_queue_fn(int4) IS 'Update stay details, reverse_geocode_py_fn';

CREATE OR REPLACE FUNCTION api.logs_geojson_fn() RETURNS SETOF api.log_view AS $$
  SELECT * FROM api.log_view;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION api.moorages_geojson_fn() RETURNS SETOF api.moorage_view AS $$
  SELECT * FROM api.moorage_view;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION api.stays_geojson_fn() RETURNS SETOF api.noteshistory_view AS $$
  SELECT * FROM api.noteshistory_view;
$$ LANGUAGE SQL STABLE;

DROP VIEW IF EXISTS api.logs_geojson_view;
-- Create view api.logs_geojson_view, List logs with geojson
CREATE OR REPLACE VIEW api.logs_geojson_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT
        tbl.id,
        tbl.name,
        tbl.starttimestamp,
        ST_AsGeoJSON(tbl.*)::JSONB as geojson
        FROM
            ( SELECT id, name,
            starttimestamp(trip),
            endtimestamp(trip),
            --speed(trip_sog),
            duration(trip),
            --length(trip) as length, -- Meters
            (length(trip) * 0.0005399568)::numeric as distance, -- NM
            maxValue(trip_sog) as max_sog, -- SOG
            maxValue(trip_tws) as max_tws, -- Wind Speed
            maxValue(trip_twd) as max_twd, -- Wind Direction
            maxValue(trip_depth) as max_depth, -- Depth
            maxValue(trip_temp_water) as max_temp_water, -- Temperature water
            maxValue(trip_temp_out) as max_temp_out, -- Temperature outside
            maxValue(trip_pres_out) as max_pres_out, -- Pressure outside
            maxValue(trip_hum_out) as max_hum_out, -- Humidity outside
            maxValue(trip_batt_charge) as max_stateofcharge, -- stateofcharge
            maxValue(trip_batt_voltage) as max_voltage, -- voltage
            maxValue(trip_solar_voltage) as max_solar_voltage, -- solar voltage
            maxValue(trip_solar_power) as max_solar_power, -- solar power
            maxValue(trip_tank_level) as max_tank_level, -- tank level
            twavg(trip_sog) as avg_sog, -- SOG
            twavg(trip_tws) as avg_tws, -- Wind Speed
            twavg(trip_twd) as avg_twd, -- Wind Direction
            twavg(trip_depth) as avg_depth, -- Depth
            twavg(trip_temp_water) as avg_temp_water, -- Temperature water
            twavg(trip_temp_out) as avg_temp_out, -- Temperature outside
            twavg(trip_pres_out) as avg_pres_out, -- Pressure outside
            twavg(trip_hum_out) as avg_hum_out, -- Humidity outside
            twavg(trip_batt_charge) as avg_stateofcharge, -- stateofcharge
            twavg(trip_batt_voltage) as avg_voltage, -- voltage
            twavg(trip_solar_voltage) as avg_solar_voltage, -- solar voltage
            twavg(trip_solar_power) as avg_solar_power, -- solar power
            twavg(trip_tank_level) as avg_tank_level, -- tank level
            trajectory(l.trip)::geometry as track_geog, -- extract trip to geography
            extra,
            _to_moorage_id,
            _from_moorage_id
        FROM api.logbook l
        WHERE _to_time IS NOT NULL AND trip IS NOT NULL
        ORDER BY _from_time DESC
    ) AS tbl;
-- Description
COMMENT ON VIEW api.logs_geojson_view IS 'List logs with geojson';

DROP VIEW IF EXISTS api.moorages_geojson_view;
-- Create view api.moorages_geojson_view, List moorages with geojson
CREATE OR REPLACE VIEW api.moorages_geojson_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT
        m.id,
        m.name,
        ST_AsGeoJSON(m.*)::JSONB as geojson
        FROM
        ( SELECT
            m.id,
            m.name,
            m.default_stay,
            m.default_stay_id,
            m.home,
            m.notes,
            m.geog,
            logs_count, -- Counting the number of logs
            stays_count, -- Counting the number of stays
            stays_sum_duration, -- Summing the stay durations
            stay_first_seen, -- First stay observed
            stay_last_seen,  -- Last stay observed
            stay_first_seen_id, -- First stay id observed
            stay_last_seen_id  -- Last stay id observed
            FROM api.moorage_view m
            WHERE geog IS NOT null
        ) AS m;
-- Description
COMMENT ON VIEW api.moorages_geojson_view IS 'List moorages with geojson';

DROP VIEW IF EXISTS api.stays_geojson_view;
CREATE OR REPLACE VIEW api.stays_geojson_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT
        ST_AsGeoJSON(tbl.*)::JSONB as geojson
        FROM
        ( SELECT
            *,
            ST_MakePoint(longitude, latitude) FROM api.noteshistory_view
        ) AS tbl;
-- Description
COMMENT ON VIEW api.stays_geojson_view IS 'List stays with geojson';

-- Create view api.export_stays_geojson_fn, List stays with geojson
CREATE OR REPLACE FUNCTION api.export_stays_geojson_fn(OUT geojson jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
    BEGIN
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features',
                ( SELECT
                    json_agg(ST_AsGeoJSON(stays.*)::JSON) as stays_geojson
                    FROM
                    ( SELECT
                        *,
                        ST_MakePoint(longitude, latitude)
                        FROM api.noteshistory_view
                    ) AS stays
                )
            ) INTO geojson;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION api.export_stays_geojson_fn(out jsonb) IS 'Export stays as geojson';

-- Create api.export_vessel_geojson_fn, export vessel as geojson
CREATE OR REPLACE FUNCTION api.export_vessel_geojson_fn(OUT geojson jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
    BEGIN
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features',
                ( SELECT
                    json_agg(ST_AsGeoJSON(vessel.*)::JSON) as vessel_geojson
                    FROM
                    ( SELECT
                        current_setting('vessel.name') as name,
                        time,
                        courseovergroundtrue,
                        speedoverground,
                        anglespeedapparent,
                        longitude,latitude,
                        st_makepoint(longitude,latitude) AS geo_point
                        FROM api.metrics
                        WHERE
                            latitude IS NOT NULL
                            AND longitude IS NOT NULL
                            AND vessel_id = current_setting('vessel.id', false)
                        ORDER BY time DESC LIMIT 1
                    ) AS vessel
                )
            ) INTO geojson;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION api.export_vessel_geojson_fn(out jsonb) IS 'Export vessel as geojson';

-- DROP FUNCTION api.export_logbook_geojson_linestring_trip_fn(int4);
-- Update api.export_logbook_geojson_linestring_trip_fn, add more trip properties to geojson
CREATE OR REPLACE FUNCTION api.export_logbook_geojson_linestring_trip_fn(_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
BEGIN
    -- Return a geojson with a geometry linestring and the corresponding properties
    RETURN
            json_build_object(
            'type', 'FeatureCollection',
            'features', json_agg(ST_AsGeoJSON(log.*)::json))
    FROM -- Extract max/avg values from trip and return as geojson
        ( SELECT id, name,
            starttimestamp(trip),
            endtimestamp(trip),
            --speed(trip_sog),
            duration(trip),
            --length(trip) as length, -- Meters
            (length(trip) * 0.0005399568)::numeric as distance, -- NM
            maxValue(trip_sog) as max_sog, -- SOG
            maxValue(trip_tws) as max_tws, -- Wind Speed
            maxValue(trip_twd) as max_twd, -- Wind Direction
            maxValue(trip_depth) as max_depth, -- Depth
            maxValue(trip_temp_water) as max_temp_water, -- Temperature water
            maxValue(trip_temp_out) as max_temp_out, -- Temperature outside
            maxValue(trip_pres_out) as max_pres_out, -- Pressure outside
            maxValue(trip_hum_out) as max_hum_out, -- Humidity outside
            maxValue(trip_batt_charge) as max_stateofcharge, -- stateofcharge
            maxValue(trip_batt_voltage) as max_voltage, -- voltage
            maxValue(trip_solar_voltage) as max_solar_voltage, -- solar voltage
            maxValue(trip_solar_power) as max_solar_power, -- solar power
            maxValue(trip_tank_level) as max_tank_level, -- tank level
            twavg(trip_sog) as avg_sog, -- SOG
            twavg(trip_tws) as avg_tws, -- Wind Speed
            twavg(trip_twd) as avg_twd, -- Wind Direction
            twavg(trip_depth) as avg_depth, -- Depth
            twavg(trip_temp_water) as avg_temp_water, -- Temperature water
            twavg(trip_temp_out) as avg_temp_out, -- Temperature outside
            twavg(trip_pres_out) as avg_pres_out, -- Pressure outside
            twavg(trip_hum_out) as avg_hum_out, -- Humidity outside
            twavg(trip_batt_charge) as avg_stateofcharge, -- stateofcharge
            twavg(trip_batt_voltage) as avg_voltage, -- voltage
            twavg(trip_solar_voltage) as avg_solar_voltage, -- solar voltage
            twavg(trip_solar_power) as avg_solar_power, -- solar power
            twavg(trip_tank_level) as avg_tank_level, -- tank level
            trajectory(trip)::geometry as track_geog, -- extract trip to geography
            extra,
            _to_moorage_id,
            _from_moorage_id,
            timestamps(trip) as times -- extract timestamps to array
            FROM api.logbook l
            WHERE id = _id
           ) AS log;
END;
$function$
;

COMMENT ON FUNCTION api.export_logbook_geojson_linestring_trip_fn(int4) IS 'Generate geojson geometry LineString from trip with the corresponding properties';

-- DROP FUNCTION api.export_logbook_geojson_trip_fn(int4);
-- Update api.export_logbook_geojson_trip_fn, add more trip properties to geojson
CREATE OR REPLACE FUNCTION api.export_logbook_geojson_trip_fn(_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    logbook_rec RECORD;
    log_geojson JSONB;
    metrics_geojson JSONB;
    first_feature_obj JSONB;
    second_feature_note JSONB;
    last_feature_note JSONB;
BEGIN
    -- Validate input
    IF _id IS NULL OR _id < 1 THEN
        RAISE WARNING '-> export_logbook_geojson_trip_fn invalid input %', _id;
        RETURN NULL;
    END IF;

    -- Fetch the processed logbook data.
    SELECT id, name, distance, duration, avg_speed, max_speed, max_wind_speed, extra->>'avg_wind_speed' AS avg_wind_speed,
           _from, _to, _from_time, _to_time, _from_moorage_id, _to_moorage_id, notes,
           trajectory(trip) AS trajectory,
           timestamps(trip) AS times
    INTO logbook_rec
    FROM api.logbook
    WHERE id = _id;

    -- Create JSON notes for feature properties
    first_feature_obj := jsonb_build_object('trip', jsonb_build_object('name', logbook_rec.name, 'duration', logbook_rec.duration, 'distance', logbook_rec.distance));
    second_feature_note := jsonb_build_object('notes', COALESCE(logbook_rec._from, ''));
    last_feature_note := jsonb_build_object('notes', COALESCE(logbook_rec._to, ''));

    -- GeoJSON Feature for Logbook linestring
    SELECT ST_AsGeoJSON(logbook_rec.*)::jsonb INTO log_geojson;

    -- GeoJSON Features for Metrics Points
    SELECT jsonb_agg(ST_AsGeoJSON(t.*)::jsonb) INTO metrics_geojson
    FROM ( -- Extract points from trip and their corresponding metrics
        SELECT
            geometry(getvalue(points.point)) AS point_geometry,
            getTimestamp(points.point) AS time,
            valueAtTimestamp(points.trip_cog, getTimestamp(points.point)) AS courseovergroundtrue,
            valueAtTimestamp(points.trip_sog, getTimestamp(points.point)) AS speedoverground,
            valueAtTimestamp(points.trip_twa, getTimestamp(points.point)) AS windspeedapparent,
            valueAtTimestamp(points.trip_tws, getTimestamp(points.point)) AS truewindspeed,
            valueAtTimestamp(points.trip_twd, getTimestamp(points.point)) AS truewinddirection,
            valueAtTimestamp(points.trip_notes, getTimestamp(points.point)) AS notes,
            valueAtTimestamp(points.trip_status, getTimestamp(points.point)) AS status,
            valueAtTimestamp(points.trip_depth, getTimestamp(points.point)) AS depth,
            valueAtTimestamp(points.trip_batt_charge, getTimestamp(points.point)) AS stateofcharge,
            valueAtTimestamp(points.trip_batt_voltage, getTimestamp(points.point)) AS voltage,
            valueAtTimestamp(points.trip_temp_water, getTimestamp(points.point)) AS watertemperature,
            valueAtTimestamp(points.trip_temp_out, getTimestamp(points.point)) AS outsidetemperature,
            valueAtTimestamp(points.trip_pres_out, getTimestamp(points.point)) AS outsidepressure,
            valueAtTimestamp(points.trip_hum_out, getTimestamp(points.point)) AS outsidehumidity,
            valueAtTimestamp(points.trip_solar_voltage, getTimestamp(points.point)) AS solarvoltage,
            valueAtTimestamp(points.trip_solar_power, getTimestamp(points.point)) AS solarpower,
            valueAtTimestamp(points.trip_tank_level, getTimestamp(points.point)) AS tanklevel,
            valueAtTimestamp(points.trip_heading, getTimestamp(points.point)) AS heading
        FROM (
            SELECT unnest(instants(trip)) AS point,
                    trip_cog,
                    trip_sog,
                    trip_twa,
                    trip_tws,
                    trip_twd,
                    trip_notes,
                    trip_status,
                    trip_depth,
                    trip_batt_charge,
                    trip_batt_voltage,
                    trip_temp_water,
                    trip_temp_out,
                    trip_pres_out,
                    trip_hum_out,
					trip_solar_voltage,
					trip_solar_power,
					trip_tank_level,
					trip_heading
            FROM api.logbook
            WHERE id = _id
                AND trip IS NOT NULL
        ) AS points
    ) AS t;

    -- Update the properties of the first feature
    metrics_geojson := jsonb_set(
        metrics_geojson,
        '{0, properties}',
        (metrics_geojson->0->'properties' || first_feature_obj)::jsonb,
        true
    );
    -- Update the properties of the third feature
    metrics_geojson := jsonb_set(
        metrics_geojson,
        '{1, properties}',
        CASE
            WHEN (metrics_geojson->1->'properties'->>'notes') = '' THEN
                (metrics_geojson->1->'properties' || second_feature_note)::jsonb
            ELSE
                metrics_geojson->1->'properties'
        END,
        true
    );
    -- Update the properties of the last feature
    metrics_geojson := jsonb_set(
        metrics_geojson,
        '{-1, properties}',
        CASE
            WHEN (metrics_geojson->-1->'properties'->>'notes') = '' THEN
                (metrics_geojson->-1->'properties' || last_feature_note)::jsonb
            ELSE
                metrics_geojson->-1->'properties'
        END,
        true
    );

    -- Combine Logbook and Metrics GeoJSON
    RETURN jsonb_build_object('type', 'FeatureCollection', 'features', log_geojson || metrics_geojson);

END;
$function$
;
-- Description
COMMENT ON FUNCTION api.export_logbook_geojson_trip_fn(int4) IS 'Export a log trip entry to GEOJSON format with custom properties for timelapse replay';

-- DROP FUNCTION api.export_logbooks_geojson_linestring_trips_fn(in int4, in int4, in text, in text, out jsonb);
-- Update api.export_logbooks_geojson_linestring_trips_fn, add more trip properties to geojson
CREATE OR REPLACE FUNCTION api.export_logbooks_geojson_linestring_trips_fn(start_log integer DEFAULT NULL::integer, end_log integer DEFAULT NULL::integer, start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT geojson jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
    logs_geojson jsonb;
BEGIN
    -- Normalize start and end values
    IF start_log IS NOT NULL AND end_log IS NULL THEN end_log := start_log; END IF;
    IF start_date IS NOT NULL AND end_date IS NULL THEN end_date := start_date; END IF;

    WITH logbook_data AS (
        -- get the logbook geometry and metadata, an array for each log
        SELECT id, name,
            starttimestamp(trip),
            endtimestamp(trip),
            --speed(trip_sog),
            duration(trip),
            --length(trip) as length, -- Meters
            (length(trip) * 0.0005399568)::numeric as distance, -- NM
            maxValue(trip_sog) as max_sog, -- SOG
            maxValue(trip_tws) as max_tws, -- Wind Speed
            maxValue(trip_twd) as max_twd, -- Wind Direction
            maxValue(trip_depth) as max_depth, -- Depth
            maxValue(trip_temp_water) as max_temp_water, -- Temperature water
            maxValue(trip_temp_out) as max_temp_out, -- Temperature outside
            maxValue(trip_pres_out) as max_pres_out, -- Pressure outside
            maxValue(trip_hum_out) as max_hum_out, -- Humidity outside
            maxValue(trip_batt_charge) as max_stateofcharge, -- stateofcharge
            maxValue(trip_batt_voltage) as max_voltage, -- voltage
            maxValue(trip_solar_voltage) as max_solar_voltage, -- Solar voltage
            maxValue(trip_solar_power) as max_solar_power, -- Solar power
            maxValue(trip_tank_level) as max_tank_level, -- tank level
            twavg(trip_sog) as avg_sog, -- SOG
            twavg(trip_tws) as avg_tws, -- Wind Speed
            twavg(trip_twd) as avg_twd, -- Wind Direction
            twavg(trip_depth) as avg_depth, -- Depth
            twavg(trip_temp_water) as avg_temp_water, -- Temperature water
            twavg(trip_temp_out) as avg_temp_out, -- Temperature outside
            twavg(trip_pres_out) as avg_pres_out, -- Pressure outside
            twavg(trip_hum_out) as avg_hum_out, -- Humidity outside
            twavg(trip_batt_charge) as avg_stateofcharge, -- stateofcharge
            twavg(trip_batt_voltage) as avg_voltage, -- voltage
            twavg(trip_solar_voltage) as avg_solar_voltage, -- Solar voltage
            twavg(trip_solar_power) as avg_solar_power, -- Solar power
            twavg(trip_tank_level) as avg_tank_level, -- tank level
            trajectory(l.trip)::geometry as track_geog, -- extract trip to geography
            extra,
            _to_moorage_id,
            _from_moorage_id
        FROM api.logbook l
        WHERE (start_log IS NULL OR l.id >= start_log) AND
              (end_log IS NULL OR l.id <= end_log) AND
              (start_date IS NULL OR l._from_time >= start_date::TIMESTAMPTZ) AND
              (end_date IS NULL OR l._to_time <= end_date::TIMESTAMPTZ + interval '23 hours 59 minutes') AND
              l.trip IS NOT NULL
        ORDER BY l._from_time ASC
    ),
    collect as (
        SELECT ST_Collect(
                        ARRAY(
                            SELECT track_geog FROM logbook_data))
    )
    -- Create the GeoJSON response
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', json_agg(ST_AsGeoJSON(logs.*)::json)) INTO geojson FROM logbook_data logs;
END;
$function$
;
-- Description
COMMENT ON FUNCTION api.export_logbooks_geojson_linestring_trips_fn(in int4, in int4, in text, in text, out jsonb) IS 'Generate geojson geometry LineString from trip with the corresponding properties';

-- Revoke security definer
ALTER FUNCTION api.update_logbook_observations_fn(_id integer, observations text) SECURITY INVOKER;
ALTER FUNCTION api.delete_logbook_fn(_id integer) SECURITY INVOKER;

-- Grant access to the new table
GRANT SELECT ON TABLE api.metadata_ext,api.stays_ext TO user_role;
-- Allow users to update certain columns on metadata_ext table on API schema
GRANT INSERT,UPDATE (make_model, polar, image, image_b64, image_type, image_url) ON api.metadata_ext TO user_role;
-- Allow users to update certain columns on stays_ext table on API schema
GRANT INSERT,UPDATE (stay_id, image, image_b64, image_type, image_url) ON api.stays_ext TO user_role;
-- Allow users to update certain columns on metadata table on API schema
GRANT INSERT,UPDATE (configuration) ON api.metadata TO user_role;
-- Allow users to update certain columns on logbook table on API schema
GRANT UPDATE (extra) ON api.logbook TO user_role;
-- Allow anonymous to read api.metadata_ext table on API schema
GRANT SELECT ON TABLE api.metadata_ext TO api_anonymous;
-- Allow anonymous to export the vessel and stays image on API schema
-- Imgage reuqest from browser does not include the JWT token therfore thread as anonymous
GRANT EXECUTE ON FUNCTION api.vessel_image TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.stays_image TO api_anonymous;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO api_anonymous;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO api_anonymous;
-- Allow anonymous to execute the stats functions
GRANT EXECUTE ON FUNCTION api.stats_logs_fn to api_anonymous;
GRANT EXECUTE ON FUNCTION api.stats_stays_fn to api_anonymous;
GRANT EXECUTE ON FUNCTION api.stats_fn to api_anonymous;

ALTER TABLE api.stays_ext ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.stays_ext TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow user_role to insert, update and select on their own records
CREATE POLICY api_user_role ON api.stays_ext TO user_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow anonymous to select
CREATE POLICY api_anonymous_role ON api.stays_ext TO api_anonymous
    USING (true)
    WITH CHECK (false);
-- Disallow vessel_role
CREATE POLICY api_vessel_role ON api.stays_ext TO vessel_role
    USING (false)
    WITH CHECK (false);

ALTER TABLE api.metadata_ext ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.metadata_ext TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow user_role to insert, update and select on their own records
CREATE POLICY api_user_role ON api.metadata_ext TO user_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow anonymous to select
CREATE POLICY api_anonymous_role ON api.metadata_ext TO api_anonymous
    USING (true)
    WITH CHECK (false);
-- Disallow vessel_role
CREATE POLICY api_vessel_role ON api.metadata_ext TO vessel_role
    USING (false)
    WITH CHECK (false);

-- Allow user_role to select on their own records
DROP POLICY IF EXISTS api_user_role ON api.metrics;
CREATE POLICY api_user_role ON api.metrics TO user_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (false);
-- Allow vessel_role to inset on their own records
DROP POLICY IF EXISTS api_vessel_role ON api.metrics;
CREATE POLICY api_vessel_role ON api.metrics TO vessel_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));

-- Allow vessel_role to insert, update, select on their own records
DROP POLICY IF EXISTS api_vessel_role ON api.metadata;
CREATE POLICY api_vessel_role ON api.metadata TO vessel_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow user_role to insert, update, select on their own records
DROP POLICY IF EXISTS api_user_role ON api.metadata;
CREATE POLICY api_user_role ON api.metadata TO user_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));

-- refresh permissions
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
GRANT SELECT ON ALL TABLES IN SCHEMA api TO api_anonymous;
-- Allow users to write table in public schema
GRANT USAGE, CREATE ON SCHEMA public TO  user_role;
-- Scheduler
GRANT SELECT ON ALL TABLES IN SCHEMA api TO scheduler;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO scheduler;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO scheduler;

-- Update version
UPDATE public.app_settings
	SET value='0.9.1'
	WHERE "name"='app.version';

\c postgres
-- Create a every 20 minute job cron_process_autodiscovery_fn, no rush we want the metrics to be collected first
SELECT cron.schedule('cron_autodiscovery', '*/20 * * * *', 'select public.cron_process_autodiscovery_fn()');
UPDATE cron.job
    SET username = current_user,
        database = 'signalk',
        active = True
    WHERE jobname = 'cron_autodiscovery';
