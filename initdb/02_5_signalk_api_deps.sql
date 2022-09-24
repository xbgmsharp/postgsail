---------------------------------------------------------------------------
-- singalk db permissions
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- List vessel
--TODO add geojson with position
DROP VIEW IF EXISTS api.vessels_view;
CREATE OR REPLACE VIEW api.vessels_view AS
    SELECT
        v.name as name,
        v.mmsi as mmsi,
        v.created_at as created_at,
        coalesce(m.time, null) as last_contact
        FROM auth.vessels v, api.metadata m
        WHERE
            m.mmsi = current_setting('vessel.mmsi')
            AND m.mmsi = v.mmsi
            AND lower(v.owner_email) = lower(current_setting('request.jwt.claims', true)::json->>'email');

DROP VIEW IF EXISTS api.vessel_p_view;
CREATE OR REPLACE VIEW api.vessel_p_view AS
    SELECT
        v.name as name,
        v.mmsi as mmsi,
        v.created_at as created_at,
        null as last_contact
        FROM auth.vessels v
        WHERE lower(v.owner_email) = lower(current_setting('request.jwt.claims', true)::json->>'email');

-- Or function?
DROP FUNCTION IF EXISTS api.vessel_fn;
CREATE OR REPLACE FUNCTION api.vessel_fn(OUT vessel JSON) RETURNS JSON
AS $vessel$
	DECLARE 
    BEGIN
        SELECT
            json_build_object( 
	            'name', v.name,
	            'mmsi', v.mmsi,
	            'created_at', v.created_at,
	            'last_contact', m.time,
	            'geojson', ST_AsGeoJSON(geojson_t.*)::json
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
			                    FROM public.last_metric
			                    WHERE
                                    latitude IS NOT NULL
                                    AND longitude IS NOT NULL
                                    AND client_id LIKE '%' || current_setting('vessel.mmsi', false)
			                )
			            ) AS t
	            ) AS geojson_t
            WHERE
                m.mmsi = current_setting('vessel.mmsi')
                AND m.mmsi = v.mmsi;
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
                INITCAP(CONCAT (LEFT(first, 1), ' ', last)) AS username
            from auth.accounts
            where lower(email) = lower(current_setting('request.jwt.claims', true)::json->>'email')
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
            value, version() into _appv,_sysv
        FROM app_settings
        WHERE name = 'app.version';
        RETURN json_build_object('app_version', _appv,
                           'sys_version', _sysv);
    END;
$version$ language plpgsql security definer;
-- Description
COMMENT ON FUNCTION
    api.versions_fn
    IS 'Expose function app and system version to API';

DROP VIEW IF EXISTS api.versions_view;
CREATE OR REPLACE VIEW api.versions_view AS
    SELECT
        value as app_version,
        version() as sys_version
    FROM app_settings
    WHERE name = 'app.version';
-- Description
COMMENT ON VIEW
    api.versions_view
    IS 'Expose view app and system version to API';
