---------------------------------------------------------------------------
-- singalk db permissions
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- List vessel
--TODO add geojson with position
CREATE OR REPLACE VIEW api.vessel_view AS
    SELECT
        v.name as name,
        v.mmsi as mmsi,
        v.created_at as created_at,
        m.time as last_contact
        FROM auth.vessels v, api.metadata m
        WHERE
            m.mmsi = current_setting('vessel.mmsi')
            AND lower(v.owner_email) = lower(current_setting('request.jwt.claims', true)::json->>'email');

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
			                    time,
			                    courseovergroundtrue,
			                    speedoverground,
			                    anglespeedapparent,
			                    longitude,latitude,
			                    st_makepoint(longitude,latitude) AS geo_point
			                    FROM public.last_metric
			                    WHERE latitude IS NOT NULL
			                        AND longitude IS NOT NULL
			                )
			            ) AS t
	            ) AS geojson_t
            WHERE v.mmsi = current_setting('vessel.mmsi')
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
CREATE FUNCTION api.settings_fn(OUT settings JSON) RETURNS JSON AS $user_settings$
    BEGIN
        select first,last,preferences,created_at INTO settings
            from auth.accounts
            where lower(email) = lower(current_setting('request.jwt.claims', true)::json->>'email');
    END;
$user_settings$ language plpgsql security definer;

-- Description
COMMENT ON FUNCTION
    api.settings_fn
    IS 'Expose user settings to API';
