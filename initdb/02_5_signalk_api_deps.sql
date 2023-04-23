---------------------------------------------------------------------------
-- signalk db api schema
-- View and Function that have dependency with auth schema

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- Link auth.vessels with api.metadata
ALTER TABLE api.metadata ADD vessel_id TEXT NOT NULL REFERENCES auth.vessels(vessel_id) ON DELETE RESTRICT;
COMMENT ON COLUMN api.metadata.vessel_id IS 'Link auth.vessels with api.metadata';

-- List vessel
--TODO add geojson with position
DROP VIEW IF EXISTS api.vessels_view;
CREATE OR REPLACE VIEW api.vessels_view AS
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
        v.created_at::timestamp(0) as created_at,
        m.last_contact as last_contact
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
    IS 'Expose has vessel to API';

-- Or function?
-- TODO Improve: return null until the vessel has sent metadata?
DROP FUNCTION IF EXISTS api.vessel_fn;
CREATE OR REPLACE FUNCTION api.vessel_fn(OUT vessel JSON) RETURNS JSON
AS $vessel$
	DECLARE 
    BEGIN
        SELECT
            json_build_object( 
	            'name', v.name,
	            'mmsi', coalesce(v.mmsi, null),
	            'created_at', v.created_at::timestamp(0),
	            'last_contact', coalesce(m.time, null),
	            'geojson', coalesce(ST_AsGeoJSON(geojson_t.*)::json, null)
            )
            INTO vessel
            FROM auth.vessels v, api.metadata m, 
				(	SELECT
			            t.*
			            FROM (
			                ( select
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
                                    AND client_id = current_setting('vessel.client_id', false)
                                ORDER BY time DESC
			                )
			            ) AS t
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
CREATE FUNCTION api.settings_fn(out settings json) RETURNS JSON
AS $user_settings$
    BEGIN
       select row_to_json(row)::json INTO settings
		from (
		    select email,first,last,preferences,created_at,
                INITCAP(CONCAT (LEFT(first, 1), ' ', last)) AS username,
                public.has_vessel_fn() as has_vessel
            from auth.accounts
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
                           'sys_version', _sysv);
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
        rtrim(substring(version(), 0, 17)) AS sys_version
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
