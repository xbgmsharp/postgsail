---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

SELECT v.vessel_id as "vessel_id" FROM auth.vessels v WHERE v.owner_email = 'demo+kapla@openplotter.cloud' \gset
--\echo :"vessel_id"
SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;

\echo 'Insert new api.logbook for badges'
INSERT INTO api.logbook
    (id, active, "name", "_from", "_from_lat", "_from_lng", "_to", "_to_lat", "_to_lng", track_geom, track_geog, track_geojson, "_from_time", "_to_time", distance, duration, avg_speed, max_speed, max_wind_speed, notes, vessel_id)
    OVERRIDING SYSTEM VALUE VALUES
    (nextval('api.logbook_id_seq'), false, 'Tropics Zone', NULL, NULL, NULL, NULL, NULL, NULL, 'SRID=4326;LINESTRING (-63.151124640791096 14.01074681627324, -77.0912026418618 12.870995731013664)'::public.geometry, NULL, NULL, NOW(), NOW(), 123, NULL, NULL, NULL, NULL, NULL, current_setting('vessel.id', false)),
    (nextval('api.logbook_id_seq'), false, 'Alaska Zone', NULL, NULL, NULL, NULL, NULL, NULL, 'SRID=4326;LINESTRING (-143.5773697471158 59.4404631255976, -152.35402122385003 56.58243132943173)'::public.geometry, NULL, NULL, NOW(), NOW(), 1234, NULL, NULL, NULL, NULL, NULL, current_setting('vessel.id', false));

\echo 'Set config'
SELECT set_config('user.email', 'demo+kapla@openplotter.cloud', false);

\echo 'Process badge'
SELECT badges_logbook_fn(5,NOW()::TEXT);
SELECT badges_logbook_fn(6,NOW()::TEXT);
SELECT badges_geom_fn(5,NOW()::TEXT);
SELECT badges_geom_fn(6,NOW()::TEXT);

\echo 'Check badges for all users'
SELECT jsonb_object_keys ( a.preferences->'badges' ) FROM auth.accounts a;

\echo 'Check details from vessel_id kapla'
SELECT 
    json_build_object( 
            'boat', v.name,
            'recipient', a.first,
            'email', v.owner_email,
            --'settings', a.preferences,
            'pushover_key', a.preferences->'pushover_key'
            --'badges', a.preferences->'badges'
            ) as user_settings
    FROM auth.accounts a, auth.vessels v, api.metadata m
    WHERE m.vessel_id = v.vessel_id
        AND m.vessel_id = current_setting('vessel.id', false)
        AND lower(a.email) = current_setting('user.email', false);

\echo 'Insert new api.moorages for badges'
INSERT INTO api.moorages
    (id,"name",country,stay_code,stay_duration,reference_count,latitude,longitude,geog,home_flag,notes,vessel_id)
    OVERRIDING SYSTEM VALUE VALUES
    (8,'Badge Mooring Pro',NULL,3,'11 days 00:39:56.418',1,NULL,NULL,NULL,false,'Badge Mooring Pro',current_setting('vessel.id', false)),
    (9,'Badge Anchormaster',NULL,2,'26 days 00:49:56.418',1,NULL,NULL,NULL,false,'Badge Anchormaster',current_setting('vessel.id', false));

\echo 'Set config'
SELECT set_config('user.email', 'demo+aava@openplotter.cloud', false);
--SELECT set_config('vessel.client_id', 'vessels.urn:mrn:imo:mmsi:787654321', false);
SELECT v.vessel_id as "vessel_id" FROM auth.vessels v WHERE v.owner_email = 'demo+aava@openplotter.cloud' \gset
--\echo :"vessel_id"
SELECT set_config('vessel.id', :'vessel_id', false) IS NOT NULL as vessel_id;

\echo 'Process badge'
SELECT badges_moorages_fn();

\echo 'Check badges for all users'
SELECT jsonb_object_keys ( a.preferences->'badges' ) FROM auth.accounts a;

\echo 'Check details from vessel_id aava'
--SELECT get_user_settings_from_vesselid_fn('vessels.urn:mrn:imo:mmsi:787654321'::TEXT);
SELECT 
    json_build_object( 
            'boat', v.name,
            'recipient', a.first,
            'email', v.owner_email,
            --'settings', a.preferences,
            'pushover_key', a.preferences->'pushover_key'
            --'badges', a.preferences->'badges'
            ) as user_settings
    FROM auth.accounts a, auth.vessels v, api.metadata m
    WHERE m.vessel_id = v.vessel_id
        AND m.vessel_id = current_setting('vessel.id', false)
        AND lower(a.email) = current_setting('user.email', false);
