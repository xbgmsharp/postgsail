
-- connect to the DB
\c signalk

---------------------------------------------------------------------------
-- API helper views
--
---------------------------------------------------------------------------

---------------------------------------------------------------------------
-- Views
-- Views are invoked with the privileges of the view owner,
-- make the user_role the view’s owner.
---------------------------------------------------------------------------

CREATE VIEW first_metric AS
    SELECT * 
        FROM api.metrics
        ORDER BY time ASC LIMIT 1;

CREATE VIEW last_metric AS
    SELECT * 
        FROM api.metrics
        ORDER BY time DESC LIMIT 1;

CREATE VIEW trip_in_progress AS
    SELECT * 
        FROM api.logbook 
        WHERE active IS true;

CREATE VIEW stay_in_progress AS
    SELECT * 
        FROM api.stays 
        WHERE active IS true;

-- TODO: Use materialized views instead as it is not live data
-- Logs web view
DROP VIEW IF EXISTS api.logs_view;
CREATE OR REPLACE VIEW api.logs_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT id,
            name as "name",
            _from as "from",
            _from_time as "started",
            _to as "to",
            _to_time as "ended",
            distance as "distance",
            duration as "duration"
        FROM api.logbook l
        WHERE _to_time IS NOT NULL
        ORDER BY _from_time DESC;
-- Description
COMMENT ON VIEW
    api.logs_view
    IS 'Logs web view';

-- Initial try of MATERIALIZED VIEW
CREATE MATERIALIZED VIEW api.logs_mat_view AS
    SELECT id,
            name as "name",
            _from as "from",
            _from_time as "started",
            _to as "to",
            _to_time as "ended",
            distance as "distance",
            duration as "duration"
        FROM api.logbook l
        WHERE _to_time IS NOT NULL
        ORDER BY _from_time DESC;
-- Description
COMMENT ON MATERIALIZED VIEW
    api.logs_mat_view
    IS 'Logs MATERIALIZED web view';

DROP VIEW IF EXISTS api.log_view;
CREATE OR REPLACE VIEW api.log_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT id,
            name as "name",
            _from as "from",
            _from_time as "started",
            _to as "to",
            _to_time as "ended",
            distance as "distance",
            duration as "duration",
            notes as "notes",
            track_geojson as geojson,
            avg_speed as avg_speed,
            max_speed as max_speed,
            max_wind_speed as max_wind_speed,
            extra as extra
        FROM api.logbook l
        WHERE _to_time IS NOT NULL
        ORDER BY _from_time DESC;
-- Description
COMMENT ON VIEW
    api.log_view
    IS 'Log web view';

-- Stays web view
-- TODO group by month
DROP VIEW IF EXISTS api.stays_view;
CREATE OR REPLACE VIEW api.stays_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT s.id,
        concat(
            extract(DAYS FROM (s.departed-s.arrived)::interval),
            ' days',
            --DATE_TRUNC('day', s.departed-s.arrived),
            ' stay at ',
            s.name,
            ' in ',
            RTRIM(TO_CHAR(s.departed, 'Month')),
            ' ',
            TO_CHAR(s.departed, 'YYYY')
            ) as "name",
        s.name AS "moorage",
        m.id AS "moorage_id",
        (s.departed-s.arrived) AS "duration",
        sa.description AS "stayed_at",
        sa.stay_code AS "stayed_at_id",
        s.arrived AS "arrived",
        s.departed AS "departed",
        s.notes AS "notes"
    FROM api.stays s, api.stays_at sa, api.moorages m
    WHERE departed IS NOT NULL
        AND s.name IS NOT NULL
        AND s.stay_code = sa.stay_code
        AND s.id = m.stay_id
    ORDER BY s.arrived DESC;
-- Description
COMMENT ON VIEW
    api.stays_view
    IS 'Stays web view';

DROP VIEW IF EXISTS api.stay_view;
CREATE OR REPLACE VIEW api.stay_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT s.id,
        concat(
            extract(DAYS FROM (s.departed-s.arrived)::interval),
            ' days',
            --DATE_TRUNC('day', s.departed-s.arrived),
            ' stay at ',
            s.name,
            ' in ',
            RTRIM(TO_CHAR(s.departed, 'Month')),
            ' ',
            TO_CHAR(s.departed, 'YYYY')
            ) as "name",
        s.name AS "moorage",
        m.id AS "moorage_id",
        (s.departed-s.arrived) AS "duration",
        sa.description AS "stayed_at",
        sa.stay_code AS "stayed_at_id",
        s.arrived AS "arrived",
        s.departed AS "departed",
        s.notes AS "notes"
    FROM api.stays s, api.stays_at sa, api.moorages m
    WHERE departed IS NOT NULL
        AND s.name IS NOT NULL
        AND s.stay_code = sa.stay_code
        AND s.id = m.stay_id
    ORDER BY s.arrived DESC;
-- Description
COMMENT ON VIEW
    api.stay_view
    IS 'Stay web view';

-- Moorages web view
-- TODO, this is wrong using distinct (m.name) should be using postgis geog feature
--DROP VIEW IF EXISTS api.moorages_view_old;
--CREATE VIEW api.moorages_view_old AS
--    SELECT
--        m.name AS Moorage,
--        sa.description AS "Default Stay",
--        sum((m.departed-m.arrived)) OVER (PARTITION by m.name) AS "Total Stay",
--        count(m.departed) OVER (PARTITION by m.name) AS "Arrivals & Departures"
--    FROM api.moorages m, api.stays_at sa
--    WHERE departed is not null 
--        AND m.name is not null
--        AND m.stay_code = sa.stay_code
--    GROUP BY m.name,sa.description,m.departed,m.arrived
--    ORDER BY 4 DESC;

-- the good way?
DROP VIEW IF EXISTS api.moorages_view;
CREATE OR REPLACE VIEW api.moorages_view WITH (security_invoker=true,security_barrier=true) AS -- TODO
    SELECT m.id,
        m.name AS Moorage,
        sa.description AS Default_Stay,
        sa.stay_code AS Default_Stay_Id,
        EXTRACT(DAY FROM justify_hours ( m.stay_duration )) AS Total_Stay, -- in days
        m.reference_count AS Arrivals_Departures
--        m.geog
--        m.stay_duration,
--        justify_hours ( m.stay_duration )
    FROM api.moorages m, api.stays_at sa
    WHERE m.name IS NOT NULL
        AND geog IS NOT NULL
        AND m.stay_code = sa.stay_code
   GROUP BY m.id,m.name,sa.description,m.stay_duration,m.reference_count,m.geog,sa.stay_code
--   ORDER BY 4 DESC;
   ORDER BY m.reference_count DESC;
-- Description
COMMENT ON VIEW
    api.moorages_view
    IS 'Moorages listing web view';

DROP VIEW IF EXISTS api.moorage_view;
CREATE OR REPLACE VIEW api.moorage_view WITH (security_invoker=true,security_barrier=true) AS -- TODO
    SELECT id,
        m.name AS Name,
        sa.description AS Default_Stay,
        sa.stay_code AS Default_Stay_Id,
        m.home_flag AS Home,
        EXTRACT(DAY FROM justify_hours ( m.stay_duration )) AS Total_Stay,
        m.reference_count AS Arrivals_Departures,
        m.notes
--        m.geog
    FROM api.moorages m, api.stays_at sa
    WHERE m.name IS NOT NULL
        AND geog IS NOT NULL
        AND m.stay_code = sa.stay_code;
-- Description
COMMENT ON VIEW
    api.moorage_view
    IS 'Moorage details web view';

-- All moorage in 100 meters from the start of a logbook.
-- ST_DistanceSphere Returns minimum distance in meters between two lon/lat points.
--SELECT
--    m.name, ST_MakePoint(m._lng,m._lat),
--    l._from, ST_MakePoint(l._from_lng,l._from_lat),
--    ST_DistanceSphere(ST_MakePoint(m._lng,m._lat), ST_MakePoint(l._from_lng,l._from_lat))
--    FROM  api.moorages m , api.logbook l 
--    WHERE ST_DistanceSphere(ST_MakePoint(m._lng,m._lat), ST_MakePoint(l._from_lng,l._from_lat)) <= 100;

-- Stats web view
-- TODO....
-- first time entry from metrics
----> select * from api.metrics m ORDER BY m.time desc limit 1
-- last time entry from metrics
----> select * from api.metrics m ORDER BY m.time asc limit 1
-- max speed from logbook
-- max wind speed from logbook
----> select max(l.max_speed) as max_speed, max(l.max_wind_speed) as max_wind_speed from api.logbook l;
-- Total Distance from logbook
----> select sum(l.distance) as "Total Distance" from api.logbook l;
-- Total Time Underway from logbook
----> select sum(l.duration) as "Total Time Underway" from api.logbook l;
-- Longest Nonstop Sail from logbook, eg longest trip duration and distance
----> select max(l.duration),max(l.distance) from api.logbook l;
CREATE OR REPLACE VIEW api.stats_logs_view WITH (security_invoker=true,security_barrier=true) AS -- TODO
    WITH
        meta AS ( 
            SELECT m.name FROM api.metadata m ),
        last_metric AS ( 
            SELECT m.time FROM api.metrics m ORDER BY m.time DESC limit 1),
        first_metric AS (
            SELECT m.time FROM api.metrics m ORDER BY m.time ASC limit 1),
        logbook AS (
            SELECT
                count(*) AS "number_of_log_entries",
                max(l.max_speed) AS "max_speed",
                max(l.max_wind_speed) AS "max_wind_speed",
                sum(l.distance) AS "total_distance",
                sum(l.duration) AS "total_time_underway",
                concat( max(l.distance), ' NM, ', max(l.duration), ' hours') AS "longest_nonstop_sail"
            FROM api.logbook l)
    SELECT
        m.name as Name,
        fm.time AS first,
        lm.time AS last,
        l.* 
    FROM first_metric fm, last_metric lm, logbook l, meta m;
COMMENT ON VIEW
    api.stats_logs_view
    IS 'Statistics Logs web view';

-- Home Ports / Unique Moorages
----> select count(*) as "Home Ports" from api.moorages m where home_flag is true;
-- Unique Moorages
----> select count(*) as "Home Ports" from api.moorages m;
-- Time Spent at Home Port(s)
----> select sum(m.stay_duration) as "Time Spent at Home Port(s)" from api.moorages m where home_flag is true;
-- OR
----> select m.stay_duration as "Time Spent at Home Port(s)" from api.moorages m where home_flag is true;
-- Time Spent Away
----> select sum(m.stay_duration) as "Time Spent Away" from api.moorages m where home_flag is false;
-- Time Spent Away order by, group by stay_code (Dock, Anchor, Mooring Buoys, Unclassified)
----> select sa.description,sum(m.stay_duration) as "Time Spent Away" from api.moorages m, api.stays_at sa where home_flag is false AND m.stay_code = sa.stay_code group by m.stay_code,sa.description order by m.stay_code;
CREATE OR REPLACE VIEW api.stats_moorages_view WITH (security_invoker=true,security_barrier=true) AS -- TODO
    WITH
        home_ports AS (
            select count(*) as home_ports from api.moorages m where home_flag is true
        ),
        unique_moorage AS (
            select count(*) as unique_moorage from api.moorages m
        ),
        time_at_home_ports AS (
            select sum(m.stay_duration) as time_at_home_ports from api.moorages m where home_flag is true
        ),
        time_spent_away AS (
            select sum(m.stay_duration) as time_spent_away from api.moorages m where home_flag is false
        )
    SELECT
        home_ports.home_ports as "home_ports",
        unique_moorage.unique_moorage as "unique_moorages",
        time_at_home_ports.time_at_home_ports "time_spent_at_home_port(s)",
        time_spent_away.time_spent_away as "time_spent_away"
    FROM home_ports, unique_moorage, time_at_home_ports, time_spent_away;
COMMENT ON VIEW
    api.stats_moorages_view
    IS 'Statistics Moorages web view';

CREATE OR REPLACE VIEW api.stats_moorages_away_view WITH (security_invoker=true,security_barrier=true) AS -- TODO
    SELECT sa.description,sum(m.stay_duration) as time_spent_away_by
    FROM api.moorages m, api.stays_at sa
    WHERE home_flag IS false
        AND m.stay_code = sa.stay_code
    GROUP BY m.stay_code,sa.description
    ORDER BY m.stay_code;
COMMENT ON VIEW
    api.stats_moorages_away_view
    IS 'Statistics Moorages Time Spent Away web view';

--CREATE VIEW api.stats_view AS -- todo
--    WITH
--        logs AS (
--            SELECT * FROM api.stats_logs_view ),
--        moorages AS (
--            SELECT * FROM api.stats_moorages_view)
--    SELECT
--        l.*,
--        m.*
--        FROM logs l, moorages m;
--COMMENT ON VIEW
--    api.stats_moorages_away_view
--    IS 'Statistics Moorages Time Spent Away web view';

-- View main monitoring for web app
DROP VIEW IF EXISTS api.monitoring_view;
CREATE VIEW api.monitoring_view WITH (security_invoker=true,security_barrier=true) AS
    SELECT 
        time AS "time",
        (NOW() AT TIME ZONE 'UTC' - time) > INTERVAL '70 MINUTES' as offline,
        metrics-> 'environment.water.temperature' AS waterTemperature,
        metrics-> 'environment.inside.temperature' AS insideTemperature,
        metrics-> 'environment.outside.temperature' AS outsideTemperature,
        metrics-> 'environment.wind.speedOverGround' AS windSpeedOverGround,
        metrics-> 'environment.wind.directionGround' AS windDirectionGround,
        metrics-> 'environment.inside.relativeHumidity' AS insideHumidity,
        metrics-> 'environment.outside.relativeHumidity' AS outsideHumidity,
        metrics-> 'environment.outside.pressure' AS outsidePressure,
        metrics-> 'environment.inside.pressure' AS insidePressure,
        metrics-> 'electrical.batteries.House.capacity.stateOfCharge' AS batteryCharge,
        metrics-> 'electrical.batteries.House.voltage' AS batteryVoltage,
        jsonb_build_object(
            'type', 'Feature',
            'geometry', ST_AsGeoJSON(st_makepoint(longitude,latitude))::jsonb,
            'properties', jsonb_build_object(
                'name', current_setting('vessel.name', false),
                'latitude', m.latitude,
                'longitude', m.longitude
                )::jsonb ) AS geojson,
        current_setting('vessel.name', false) AS name
    FROM api.metrics m
    ORDER BY time DESC LIMIT 1;
COMMENT ON VIEW
    api.monitoring_view
    IS 'Monitoring static web view';

DROP VIEW IF EXISTS api.monitoring_humidity;
CREATE VIEW api.monitoring_humidity WITH (security_invoker=true,security_barrier=true) AS
    SELECT m.time, key, value
        FROM api.metrics m,
            jsonb_each_text(m.metrics)
        WHERE key ILIKE 'environment.%.humidity' OR key ILIKE 'environment.%.relativeHumidity'
        ORDER BY m.time DESC;
COMMENT ON VIEW
    api.monitoring_humidity
    IS 'Monitoring environment.%.humidity web view';

-- View System RPI monitoring for grafana
-- View Electric monitoring for grafana

-- View main monitoring for grafana
-- LAST Monitoring data from json!
DROP VIEW IF EXISTS api.monitoring_temperatures;
CREATE VIEW api.monitoring_temperatures WITH (security_invoker=true,security_barrier=true) AS
    SELECT m.time, key, value
        FROM api.metrics m,
            jsonb_each_text(m.metrics)
        WHERE key ILIKE 'environment.%.temperature'
        ORDER BY m.time DESC;
COMMENT ON VIEW
    api.monitoring_temperatures
    IS 'Monitoring environment.%.temperature web view';

-- json key regexp
-- https://stackoverflow.com/questions/38204467/selecting-for-a-jsonb-array-contains-regex-match
-- Last voltage data from json!
DROP VIEW IF EXISTS api.monitoring_voltage;
CREATE VIEW api.monitoring_voltage WITH (security_invoker=true,security_barrier=true) AS
    SELECT m.time, key, value
        FROM api.metrics m,
            jsonb_each_text(m.metrics)
        WHERE key ILIKE 'electrical.%.voltage'
        ORDER BY m.time DESC;
COMMENT ON VIEW
    api.monitoring_voltage
    IS 'Monitoring electrical.%.voltage web view';

-- Last whatever data from json!
DROP VIEW IF EXISTS api.monitoring_view2;
CREATE VIEW api.monitoring_view2 WITH (security_invoker=true,security_barrier=true) AS
    SELECT
         *
        FROM
            jsonb_each(
                ( SELECT metrics FROM api.metrics m ORDER BY time DESC LIMIT 1)
            );
    --      WHERE key ilike 'tanks.%.capacity%'
    --          or key ilike 'electrical.solar.%.panelPower'
    --          or key ilike 'electrical.batteries%stateOfCharge'
    --          or key ilike 'tanks\.%currentLevel'
COMMENT ON VIEW
    api.monitoring_view2
    IS 'Monitoring Last whatever data from json web view';

-- Timeseries whatever data from json!
DROP VIEW IF EXISTS api.monitoring_view3;
CREATE VIEW api.monitoring_view3 WITH (security_invoker=true,security_barrier=true) AS
    SELECT m.time, key, value
        FROM api.metrics m,
            jsonb_each_text(m.metrics)
         ORDER BY m.time DESC;
    --    WHERE key ILIKE 'electrical.batteries%voltage';
    --      WHERE key ilike 'tanks.%.capacity%'
    --          or key ilike 'electrical.solar.%.panelPower'
    --          or key ilike 'electrical.batteries%stateOfCharge';
    -- key ILIKE 'propulsion.%.runTime'
    -- key ILIKE 'navigation.log'
COMMENT ON VIEW
    api.monitoring_view3
    IS 'Monitoring Timeseries whatever data from json web view';

-- Infotiles web app
DROP VIEW IF EXISTS api.total_info_view;
CREATE VIEW api.total_info_view WITH (security_invoker=true,security_barrier=true) AS
-- Infotiles web app, not used calculated client side
    WITH
        l as (SELECT count(*) as logs FROM api.logbook),
        s as (SELECT count(*) as stays FROM api.stays),
        m as (SELECT count(*) as moorages FROM api.moorages)
        SELECT * FROM l,s,m;
COMMENT ON VIEW
    api.total_info_view
    IS 'total_info_view web view';
