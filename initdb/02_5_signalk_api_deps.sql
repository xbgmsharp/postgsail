---------------------------------------------------------------------------
-- signalk db api schema
-- View and Function that have dependency with auth schema

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- Link auth.vessels with api.metadata
--ALTER TABLE api.metadata ADD vessel_id TEXT NOT NULL REFERENCES auth.vessels(vessel_id) ON DELETE RESTRICT;
ALTER TABLE api.metadata ADD FOREIGN KEY (vessel_id) REFERENCES auth.vessels(vessel_id) ON DELETE RESTRICT;
COMMENT ON COLUMN api.metadata.vessel_id IS 'Link auth.vessels with api.metadata via FOREIGN KEY and REFERENCES';

-- Link auth.vessels with auth.accounts
--ALTER TABLE auth.vessels ADD user_id TEXT NOT NULL REFERENCES auth.accounts(user_id) ON DELETE RESTRICT;
--COMMENT ON COLUMN auth.vessels.user_id IS 'Link auth.vessels with auth.accounts';
--COMMENT ON COLUMN auth.vessels.vessel_id IS 'Vessel identifier. Link auth.vessels with api.metadata';

-- REFERENCE ship type with AIS type ?
-- REFERENCE mmsi MID with country ?
ALTER TABLE api.logbook ADD FOREIGN KEY (_from_moorage_id) REFERENCES api.moorages(id) ON DELETE RESTRICT;
COMMENT ON COLUMN api.logbook._from_moorage_id IS 'Link api.moorages with api.logbook via FOREIGN KEY and REFERENCES';
ALTER TABLE api.logbook ADD FOREIGN KEY (_to_moorage_id) REFERENCES api.moorages(id) ON DELETE RESTRICT;
COMMENT ON COLUMN api.logbook._to_moorage_id IS 'Link api.moorages with api.logbook via FOREIGN KEY and REFERENCES';
ALTER TABLE api.stays ADD FOREIGN KEY (moorage_id) REFERENCES api.moorages(id) ON DELETE RESTRICT;
COMMENT ON COLUMN api.stays.moorage_id IS 'Link api.moorages with api.stays via FOREIGN KEY and REFERENCES';
ALTER TABLE api.stays ADD FOREIGN KEY (stay_code) REFERENCES api.stays_at(stay_code) ON DELETE RESTRICT;
COMMENT ON COLUMN api.stays.stay_code IS 'Link api.stays_at with api.stays via FOREIGN KEY and REFERENCES';
ALTER TABLE api.moorages ADD FOREIGN KEY (stay_code) REFERENCES api.stays_at(stay_code) ON DELETE RESTRICT;
COMMENT ON COLUMN api.moorages.stay_code IS 'Link api.stays_at with api.moorages via FOREIGN KEY and REFERENCES';

-- List vessel
--TODO add geojson with position
DROP VIEW IF EXISTS api.vessels_view;
CREATE OR REPLACE VIEW api.vessels_view WITH (security_invoker=true,security_barrier=true) AS
    WITH metadata AS (
        SELECT COALESCE(
            (SELECT  m.time
                FROM api.metadata m
                WHERE m.vessel_id = current_setting('vessel.id')
            )::TEXT ,
            NULL ) as last_contact
    )
    SELECT
        v.name as name,
        v.mmsi as mmsi,
        v.created_at as created_at,
        m.last_contact as last_contact,
        ((NOW() AT TIME ZONE 'UTC' - m.last_contact::TIMESTAMPTZ) > INTERVAL '70 MINUTES') as offline,
        (NOW() AT TIME ZONE 'UTC' - m.last_contact::TIMESTAMPTZ) as duration
    FROM auth.vessels v, metadata m
    WHERE v.owner_email = current_setting('user.email');
-- Description
COMMENT ON VIEW
    api.vessels_view
    IS 'Expose vessels listing to web api';

DROP FUNCTION IF EXISTS public.has_vessel_fn;
CREATE OR REPLACE FUNCTION public.has_vessel_fn() RETURNS BOOLEAN
AS $has_vessel$
	DECLARE
    BEGIN
        -- Check a vessel and user exist
        RETURN (
            SELECT auth.vessels.name
                FROM auth.vessels, auth.accounts
                WHERE auth.vessels.owner_email = auth.accounts.email
                    AND auth.accounts.email = current_setting('user.email')
            ) IS NOT NULL;
    END;
$has_vessel$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    public.has_vessel_fn
    IS 'Check if user has a vessel register';

DROP FUNCTION IF EXISTS public.has_vessel_metadata_fn;
CREATE OR REPLACE FUNCTION public.has_vessel_metadata_fn() RETURNS BOOLEAN
AS $has_vessel_metadata$
	DECLARE
    BEGIN
        -- Check a vessel metadata
        RETURN (
            SELECT m.vessel_id
                FROM auth.accounts a, auth.vessels v, api.metadata m
                WHERE m.vessel_id = v.vessel_id
                    AND auth.vessels.owner_email = auth.accounts.email
                    AND auth.accounts.email = current_setting('user.email')
            ) IS NOT NULL;
    END;
$has_vessel_metadata$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    public.has_vessel_metadata_fn
    IS 'Check if user has a vessel register';

-- Or function?
-- TODO Improve: return null until the vessel has sent metadata?
DROP FUNCTION IF EXISTS api.vessel_fn;
CREATE OR REPLACE FUNCTION api.vessel_fn(OUT vessel JSON) RETURNS JSON
AS $vessel$
    DECLARE
    BEGIN
        SELECT
            jsonb_build_object(
                'name', coalesce(m.name, null),
                'mmsi', coalesce(m.mmsi, null),
                'created_at', v.created_at,
                'first_contact', coalesce(m.created_at, null),
                'last_contact', coalesce(m.time, null),
                'geojson', coalesce(ST_AsGeoJSON(geojson_t.*)::json, null)
            )::jsonb || api.vessel_details_fn()::jsonb
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
$vessel$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.vessel_fn
    IS 'Expose vessel details to API';

-- Export user settings
DROP FUNCTION IF EXISTS api.settings_fn;
CREATE OR REPLACE FUNCTION api.settings_fn(out settings json) RETURNS JSON
AS $user_settings$
    BEGIN
       select row_to_json(row)::json INTO settings
        from (
            select a.email, a.first, a.last, a.preferences, a.created_at,
                INITCAP(CONCAT (LEFT(first, 1), ' ', last)) AS username,
                public.has_vessel_fn() as has_vessel
                --public.has_vessel_metadata_fn() as has_vessel_metadata,
            from auth.accounts a
            where email = current_setting('user.email')
               ) row;
    END;
$user_settings$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.settings_fn
    IS 'Expose user settings to API';

DROP FUNCTION IF EXISTS api.versions_fn;
CREATE OR REPLACE FUNCTION api.versions_fn() RETURNS JSON
AS $version$
    DECLARE
        _appv TEXT;
        _sysv TEXT;
    BEGIN
        SELECT
            value, rtrim(substring(version(), 0, 17)) AS sys_version into _appv,_sysv
            FROM app_settings
            WHERE name = 'app.version';
        RETURN json_build_object('api_version', _appv,
                           'sys_version', _sysv,
                           'timescaledb', (SELECT extversion as timescaledb FROM pg_extension WHERE extname='timescaledb'),
                           'postgis', (SELECT extversion as postgis FROM pg_extension WHERE extname='postgis'),
                           'postgrest', (SELECT rtrim(substring(application_name from 'PostgREST [0-9.]+')) as postgrest FROM pg_stat_activity WHERE application_name ilike '%postgrest%' LIMIT 1));
    END;
$version$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.versions_fn
    IS 'Expose as a function, app and system version to API';

DROP VIEW IF EXISTS api.versions_view;
CREATE OR REPLACE VIEW api.versions_view AS
    SELECT
        value AS api_version,
        --version() as sys_version
        rtrim(substring(version(), 0, 17)) AS sys_version,
        (SELECT extversion as timescaledb FROM pg_extension WHERE extname='timescaledb'),
        (SELECT extversion as postgis FROM pg_extension WHERE extname='postgis'),
        (SELECT rtrim(substring(application_name from 'PostgREST [0-9.]+')) as postgrest FROM pg_stat_activity WHERE application_name ilike '%postgrest%' limit 1)
    FROM app_settings
    WHERE name = 'app.version';
-- Description
COMMENT ON VIEW
    api.versions_view
    IS 'Expose as a table view app and system version to API';

DROP FUNCTION IF EXISTS api.update_user_preferences_fn;
-- Update/Add a specific user setting into preferences
CREATE OR REPLACE FUNCTION api.update_user_preferences_fn(IN key TEXT, IN value TEXT) RETURNS BOOLEAN AS
$update_user_preferences$
DECLARE
	first_c TEXT := NULL;
	last_c TEXT := NULL;
	_value TEXT := value;
BEGIN
	-- Is it the only way to check variable type?
	-- Convert string to jsonb and skip type of json obj or integer or boolean
	SELECT SUBSTRING(value, 1, 1),RIGHT(value, 1) INTO first_c,last_c;
	IF first_c <> '{' AND last_c <> '}' AND public.isnumeric(value) IS False
        AND public.isboolean(value) IS False THEN
		--RAISE WARNING '-> first_c:[%] last_c:[%] pg_typeof:[%]', first_c,last_c,pg_typeof(value);
		_value := to_jsonb(value)::jsonb;
	END IF;
    --RAISE WARNING '-> update_user_preferences_fn update preferences for user [%]', current_setting('request.jwt.claims', true)::json->>'email';
    UPDATE auth.accounts
		SET preferences =
            jsonb_set(preferences::jsonb, key::text[], _value::jsonb)
		WHERE
			email = current_setting('user.email', true);
	IF FOUND THEN
        --RAISE WARNING '-> update_user_preferences_fn True';
		RETURN True;
	END IF;
	--RAISE WARNING '-> update_user_preferences_fn False';
	RETURN False;
END;
$update_user_preferences$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.update_user_preferences_fn
    IS 'Update user preferences jsonb key pair value';

DROP FUNCTION IF EXISTS api.vessel_details_fn;
CREATE OR REPLACE FUNCTION api.vessel_details_fn() RETURNS JSON AS
$vessel_details$
DECLARE
BEGIN
     RETURN ( WITH tbl AS (
                SELECT mmsi,ship_type,length,beam,height,plugin_version,platform FROM api.metadata WHERE vessel_id = current_setting('vessel.id', false)
                )
                SELECT json_build_object(
                        'ship_type', (SELECT ais.description FROM aistypes ais, tbl t WHERE t.ship_type = ais.id),
                        'country', (SELECT mid.country FROM mid, tbl t WHERE LEFT(cast(t.mmsi as text), 3)::NUMERIC = mid.id),
                        'alpha_2', (SELECT o.alpha_2 FROM mid m, iso3166 o, tbl t WHERE LEFT(cast(t.mmsi as text), 3)::NUMERIC = m.id AND m.country_id = o.id),
                        'length', t.length,
                        'beam', t.beam,
                        'height', t.height,
                        'plugin_version', t.plugin_version,
                        'platform', t.platform)
                        FROM tbl t
            );
END;
$vessel_details$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.vessel_details_fn
    IS 'Return vessel details such as metadata (length,beam,height), ais type and country name and country iso3166-alpha-2';

DROP VIEW IF EXISTS api.eventlogs_view;
CREATE VIEW api.eventlogs_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT pq.*
        FROM public.process_queue pq
        WHERE channel <> 'pre_logbook' AND (ref_id = current_setting('user.id', true)
            OR ref_id = current_setting('vessel.id', true))
        ORDER BY id ASC;
-- Description
COMMENT ON VIEW
    api.eventlogs_view
    IS 'Event logs view';

DROP FUNCTION IF EXISTS api.update_logbook_observations_fn;
-- Update/Add a specific user observations into logbook
CREATE OR REPLACE FUNCTION api.update_logbook_observations_fn(IN _id INT, IN observations TEXT) RETURNS BOOLEAN AS
$update_logbook_observations$
DECLARE
BEGIN
    -- Merge existing observations with the new observations objects
    RAISE NOTICE '-> update_logbook_extra_fn id:[%] observations:[%]', _id, observations;
    -- { 'observations': { 'seaState': -1, 'cloudCoverage': -1, 'visibility': -1 } }
    UPDATE api.logbook SET extra = public.jsonb_recursive_merge(extra, observations::jsonb) WHERE id = _id;
    IF FOUND IS True THEN
        RETURN True;
    END IF;
    RETURN False;
END;
$update_logbook_observations$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.update_logbook_observations_fn
    IS 'Update/Add logbook observations jsonb key pair value';

CREATE TYPE public_type AS ENUM ('public_logs', 'public_logs_list', 'public_timelapse', 'public_monitoring', 'public_stats');
CREATE or replace FUNCTION api.ispublic_fn(IN boat TEXT, IN _type TEXT, IN _id INTEGER DEFAULT NULL) RETURNS BOOLEAN AS $ispublic$
DECLARE
    vessel TEXT := '^' || boat || '$';
    anonymous BOOLEAN := False;
    valid_public_type BOOLEAN := False;
    public_logs BOOLEAN := False;
BEGIN
    -- If boat is not NULL
    IF boat IS NULL THEN
        RAISE WARNING '-> ispublic_fn invalid input %', boat;
        RETURN False;
    END IF;
    -- Check if public_type is valid enum
    SELECT _type::name = any(enum_range(null::public_type)::name[]) INTO valid_public_type;
    IF valid_public_type IS False THEN
        -- Ignore entry if type is invalid
        RAISE WARNING '-> ispublic_fn invalid input type %', _type;
        RETURN False;
    END IF;

    RAISE WARNING '-> ispublic_fn _type [%], _id [%]', _type, _id;
    IF _type ~ '^public_(logs|timelapse)$' AND _id > 0 THEN
        WITH log as (
            SELECT vessel_id from api.logbook l where l.id = _id
        )
        SELECT EXISTS (
            SELECT l.vessel_id
            FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs, log l
            WHERE v.vessel_id = l.vessel_id
                    AND a.email = v.owner_email
                    AND a.preferences->>'public_vessel'::text ~* vessel
                    AND prefs.key = _type::TEXT
                    AND prefs.value::BOOLEAN = true
            ) into anonymous;
        RAISE WARNING '-> ispublic_fn public_logs output boat:[%], type:[%], result:[%]', boat, _type, anonymous;
	    IF anonymous IS True THEN
	        RETURN True;
	    END IF;
    ELSE
	    SELECT EXISTS (
	        SELECT a.email
	            FROM auth.accounts a, jsonb_each_text(a.preferences) as prefs
	            WHERE a.preferences->>'public_vessel'::text ~* vessel
	                    AND prefs.key = _type::TEXT
	                    AND prefs.value::BOOLEAN = true
	        ) into anonymous;
	    RAISE WARNING '-> ispublic_fn output boat:[%], type:[%], result:[%]', boat, _type, anonymous;
	    IF anonymous IS True THEN
	        RETURN True;
	    END IF;
    END IF;
    RETURN False;
END
$ispublic$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.ispublic_fn
    IS 'Is web page publicly accessible by register boat name and/or logbook id';
