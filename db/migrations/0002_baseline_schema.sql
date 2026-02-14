-- +goose Up
-- +goose StatementBegin

--
-- PostgreSQL database dump
--
-- Dumped from database version 18.1 (Debian 18.1-1.pgdg13+2)
-- Dumped by pg_dump version 18.1 (Debian 18.1-1.pgdg13+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
--SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'backend public functions and tables';


--
-- Name: timescaledb; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS timescaledb WITH SCHEMA public;


--
-- Name: EXTENSION timescaledb; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION timescaledb IS 'Enables scalable inserts and complex queries for time-series data (Community Edition)';


--
-- Name: api; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA api;


--
-- Name: SCHEMA api; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA api IS 'PostgSail API

A RESTful API that serves PostgSail data using postgrest.';


--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA auth;


--
-- Name: SCHEMA auth; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA auth IS 'auth postgrest for users and vessels';


--
-- Name: jwt; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA jwt;


--
-- Name: SCHEMA jwt; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA jwt IS 'jwt auth postgrest';


--
-- Name: timescaledb_toolkit; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit WITH SCHEMA public;


--
-- Name: EXTENSION timescaledb_toolkit; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION timescaledb_toolkit IS 'Library of analytical hyperfunctions, time-series pipelining, and other SQL utilities';


--
-- Name: plpython3u; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpython3u WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpython3u; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpython3u IS 'PL/Python3U untrusted procedural language';


--
-- Name: jsonb_plpython3u; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS jsonb_plpython3u WITH SCHEMA public;


--
-- Name: EXTENSION jsonb_plpython3u; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION jsonb_plpython3u IS 'transform between jsonb and plpython3u';


--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: postgis; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;


--
-- Name: EXTENSION postgis; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION postgis IS 'PostGIS geometry and geography spatial types and functions';


--
-- Name: mobilitydb; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS mobilitydb WITH SCHEMA public;


--
-- Name: EXTENSION mobilitydb; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION mobilitydb IS 'MobilityDB geospatial trajectory data management & analysis platform';


--
-- Name: moddatetime; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS moddatetime WITH SCHEMA public;


--
-- Name: EXTENSION moddatetime; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION moddatetime IS 'functions for tracking last modification time';


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA public;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: jwt_token; Type: TYPE; Schema: auth; Owner: -
--

CREATE TYPE auth.jwt_token AS (
	token text
);


--
-- Name: */*; Type: DOMAIN; Schema: public; Owner: -
--

CREATE DOMAIN public."*/*" AS bytea;


--
-- Name: application/geo+json; Type: DOMAIN; Schema: public; Owner: -
--

CREATE DOMAIN public."application/geo+json" AS jsonb;


--
-- Name: application/gpx+xml; Type: DOMAIN; Schema: public; Owner: -
--

CREATE DOMAIN public."application/gpx+xml" AS xml;


--
-- Name: application/vnd.google-earth.kml+xml; Type: DOMAIN; Schema: public; Owner: -
--

CREATE DOMAIN public."application/vnd.google-earth.kml+xml" AS xml;


--
-- Name: public_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.public_type AS ENUM (
    'public_logs',
    'public_logs_list',
    'public_timelapse',
    'public_monitoring',
    'public_stats'
);


--
-- Name: status_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.status_type AS ENUM (
    'sailing',
    'motoring',
    'moored',
    'anchored'
);


--
-- Name: text/xml; Type: DOMAIN; Schema: public; Owner: -
--

CREATE DOMAIN public."text/xml" AS xml;


--
-- Name: counts_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.counts_fn() RETURNS jsonb
    LANGUAGE sql
    AS $$
    SELECT jsonb_build_object(
        'logs', (SELECT COUNT(*) FROM api.logbook),
        'moorages', (SELECT COUNT(*) FROM api.moorages),
        'stays', (SELECT COUNT(*) FROM api.stays)
    );
$$;


--
-- Name: FUNCTION counts_fn(); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.counts_fn() IS 'count logbook, moorages and stays entries';


--
-- Name: delete_logbook_fn(integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.delete_logbook_fn(_id integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
    DECLARE
        logbook_rec record;
        previous_stays_id numeric;
        current_stays_departed text;
        current_stays_id numeric;
        current_stays_active boolean;
       BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> delete_logbook_fn invalid input %', _id;
            RETURN FALSE;
        END IF;
        -- Get the logbook record with all necessary fields exist
        SELECT * INTO logbook_rec
            FROM api.logbook
            WHERE id = _id;
        -- Ensure the query is successful
        IF logbook_rec.vessel_id IS NULL THEN
            RAISE WARNING '-> delete_logbook_fn invalid logbook %', _id;
            RETURN FALSE;
        END IF;
        -- Update logbook
        UPDATE api.logbook l
            SET notes = 'mark for deletion'
            WHERE l.vessel_id = current_setting('vessel.id', false)
                AND id = logbook_rec.id;
        -- Update metrics status to moored
        UPDATE api.metrics
            SET status = 'moored'
            WHERE time >= logbook_rec._from_time::TIMESTAMPTZ
                AND time <= logbook_rec._to_time::TIMESTAMPTZ
                AND vessel_id = current_setting('vessel.id', false);
        -- Get related stays
        SELECT id,departed,active INTO current_stays_id,current_stays_departed,current_stays_active
            FROM api.stays s
            WHERE s.vessel_id = current_setting('vessel.id', false)
                AND s.arrived = logbook_rec._to_time;
        -- Update related stays
        UPDATE api.stays s
            SET notes = 'mark for deletion'
            WHERE s.vessel_id = current_setting('vessel.id', false)
                AND s.arrived = logbook_rec._to_time;
        -- Find previous stays
        SELECT id INTO previous_stays_id
            FROM api.stays s
            WHERE s.vessel_id = current_setting('vessel.id', false)
                AND s.arrived < logbook_rec._to_time
                ORDER BY s.arrived DESC LIMIT 1;
        -- Update previous stays with the departed time from current stays
        --  and set the active state from current stays
        UPDATE api.stays
            SET departed = current_stays_departed::TIMESTAMPTZ,
                active = current_stays_active
            WHERE vessel_id = current_setting('vessel.id', false)
                AND id = previous_stays_id;
        -- Clean up, remove invalid logbook and stay entry
        DELETE FROM api.logbook WHERE id = logbook_rec.id;
        RAISE WARNING '-> delete_logbook_fn delete logbook [%]', logbook_rec.id;
        DELETE FROM api.stays WHERE id = current_stays_id;
        RAISE WARNING '-> delete_logbook_fn delete stays [%]', current_stays_id;
        /* Deprecated, remove moorage reference
        -- Clean up, Subtract (-1) moorages ref count
        UPDATE api.moorages
            SET reference_count = reference_count - 1
            WHERE vessel_id = current_setting('vessel.id', false)
                AND id = previous_stays_id;
        */
        RETURN TRUE;
    END;
$$;


--
-- Name: FUNCTION delete_logbook_fn(_id integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.delete_logbook_fn(_id integer) IS 'Delete a logbook and dependency stay';


--
-- Name: delete_trip_entry_fn(integer, public.tstzspan); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.delete_trip_entry_fn(_id integer, update_string public.tstzspan) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE api.logbook l
        SET
            trip = deleteTime(l.trip, update_string),
            trip_cog = deleteTime(l.trip_cog, update_string),
            trip_sog = deleteTime(l.trip_sog, update_string),
            trip_aws = deleteTime(l.trip_aws, update_string),
            trip_awa = deleteTime(l.trip_awa, update_string),
            trip_tws = deleteTime(l.trip_tws, update_string),
            trip_twd = deleteTime(l.trip_twd, update_string),
            trip_notes = deleteTime(l.trip_notes, update_string),
            trip_status = deleteTime(l.trip_status, update_string),
            trip_depth = deleteTime(l.trip_depth, update_string),
            trip_batt_charge = deleteTime(l.trip_batt_charge, update_string),
            trip_batt_voltage = deleteTime(l.trip_batt_voltage, update_string),
            trip_temp_water = deleteTime(l.trip_temp_water, update_string),
            trip_temp_out = deleteTime(l.trip_temp_out, update_string),
            trip_pres_out = deleteTime(l.trip_pres_out, update_string),
            trip_hum_out = deleteTime(l.trip_hum_out, update_string),
            trip_solar_voltage = deleteTime(l.trip_solar_voltage, update_string),
            trip_solar_power = deleteTime(l.trip_solar_power, update_string),
            trip_tank_level = deleteTime(l.trip_tank_level, update_string),
            trip_heading = deleteTime(l.trip_heading, update_string)
        WHERE id = _id;
        -- Update metadata
        UPDATE api.logbook l
            SET
                -- Calculate speed using mobility from m/s to knots
                -- Problem with invalid SOG metrics
                --avg_speed = twAvg(trip_sog)::NUMERIC(6,2), -- avg speed in knots
                max_speed = maxValue(trip_sog)::NUMERIC(6,2), -- max speed in knots
                -- Calculate speed using mobility from m/s to knots - MobilityDB calculates instantaneous speed between consecutive GPS points
                avg_speed = (twavg(speed(trip)) * 1.94384)::NUMERIC(6,2), -- avg speed in knots
                --max_speed = (maxValue(speed(trip)) * 1.94384)::NUMERIC(6,2), -- max speed in knots
                distance = (length(trip)/1852)::NUMERIC(10,2) -- in Nautical Miles
            WHERE id = _id;
END;
$$;


--
-- Name: FUNCTION delete_trip_entry_fn(_id integer, update_string public.tstzspan); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.delete_trip_entry_fn(_id integer, update_string public.tstzspan) IS 'Delete at a specific time a temporal sequence for all trip_* column from a logbook, recalculate the trip accordingly';


--
-- Name: email_fn(text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.email_fn(token text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION email_fn(token text); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.email_fn(token text) IS 'Store email_valid into user preferences if valid token/otp';


--
-- Name: export_logbook_geojson_linestring_trip_fn(integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_logbook_geojson_linestring_trip_fn(_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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
            avg_speed, -- avg speed in knots
            max_speed, -- max speed in knots
            duration(trip),
            --length(trip) as length, -- Meters
            (length(trip)/1852)::NUMERIC(6,2) as distance, -- in Nautical Miles
            maxValue(trip_sog) as max_sog, -- SOG
            maxValue(trip_tws) as max_tws, -- Wind Speed
            maxValue(trip_twd) as max_twd, -- Wind Direction
            maxValue(trip_awa) as max_awa, -- Wind Angle Apparent
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
            twavg(trip_aws) as avg_aws, -- Wind Speed Apparent
            twavg(trip_awa) as avg_awa, -- Wind Angle Apparent
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
$$;


--
-- Name: FUNCTION export_logbook_geojson_linestring_trip_fn(_id integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_logbook_geojson_linestring_trip_fn(_id integer) IS 'Generate geojson geometry LineString from trip with the corresponding properties';


--
-- Name: export_logbook_geojson_point_trip_fn(integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_logbook_geojson_point_trip_fn(_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    -- Return a geojson with each geometry point and the corresponding properties
    RETURN
            json_build_object(
                'type', 'FeatureCollection',
                'features', json_agg(ST_AsGeoJSON(t.*)::json))
        FROM (
            SELECT 
                geometry(getvalue(points.point)) AS point_geometry,
                getTimestamp(points.point) AS time,
                valueAtTimestamp(points.trip_cog, getTimestamp(points.point)) AS courseovergroundtrue,
                valueAtTimestamp(points.trip_sog, getTimestamp(points.point)) AS speedoverground,
                valueAtTimestamp(points.trip_aws, getTimestamp(points.point)) AS windspeedapparent,
                valueAtTimestamp(points.trip_awa, getTimestamp(points.point)) AS windangleapparent,
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
            FROM 
            (
                SELECT 
                    unnest(instants(trip)) AS point,
                    trip_cog,
                    trip_sog,
                    trip_aws,
                    trip_awa,
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
            ) AS points
        ) AS t;
END;
$$;


--
-- Name: FUNCTION export_logbook_geojson_point_trip_fn(_id integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_logbook_geojson_point_trip_fn(_id integer) IS 'Generate geojson geometry Point from trip with the corresponding properties';


--
-- Name: export_logbook_geojson_trip_fn(integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_logbook_geojson_trip_fn(_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    logbook_rec RECORD;
    log_geojson JSONB;
    log_legs_geojson JSONB := '{}'::JSONB;
    metrics_geojson JSONB;
    first_feature_obj JSONB;
    second_feature_note JSONB;
    last_feature_note JSONB;
BEGIN
    SET search_path TO public, api;
    -- Validate input
    IF _id IS NULL OR _id < 1 THEN
        RAISE WARNING '-> export_logbook_geojson_trip_fn invalid input %', _id;
        RETURN NULL;
    END IF;

    -- Fetch the processed logbook data.
    SELECT id, name, distance, duration, avg_speed, max_speed, max_wind_speed, extra->>'avg_wind_speed' AS avg_wind_speed,
           _from, _to, _from_time, _to_time, _from_moorage_id, _to_moorage_id, notes,
           public.trajectory(trip) AS trajectory,
           public.timestamps(trip) AS times
    INTO logbook_rec
    FROM api.logbook
    WHERE id = _id;

    -- Create JSON notes for feature properties
    first_feature_obj := jsonb_build_object('trip', jsonb_build_object('name', logbook_rec.name, 'duration', logbook_rec.duration, 'distance', logbook_rec.distance));
    second_feature_note := jsonb_build_object('notes', COALESCE(logbook_rec._from, ''));
    last_feature_note := jsonb_build_object('notes', COALESCE(logbook_rec._to, ''));

    -- GeoJSON Feature for Logbook linestring
    SELECT public.ST_AsGeoJSON(logbook_rec.*)::jsonb INTO log_geojson;
	-- GeoJSON Feature Logbook split log into 24h linestring if larger than 24h
    IF logbook_rec.duration > interval '24 hours' THEN
        log_legs_geojson := public.split_logbook_by24h_geojson_fn(logbook_rec.id);
    END IF;

    -- GeoJSON Features for Metrics Points
    SELECT jsonb_agg(public.ST_AsGeoJSON(t.*)::jsonb) INTO metrics_geojson
    FROM ( -- Extract points from trip and their corresponding metrics
        SELECT
            geometry(getvalue(points.point)) AS point_geometry,
            getTimestamp(points.point) AS time,
            valueAtTimestamp(points.trip_cog, getTimestamp(points.point)) AS courseovergroundtrue,
            valueAtTimestamp(points.trip_sog, getTimestamp(points.point)) AS speedoverground,
            valueAtTimestamp(points.trip_aws, getTimestamp(points.point)) AS windspeedapparent,
            valueAtTimestamp(points.trip_awa, getTimestamp(points.point)) AS windangleapparent,
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
                    trip_aws,
                    trip_awa,
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

    -- Combine Logbook and Metrics GeoJSON and the log legs FeatureCollection
    RETURN jsonb_build_object('type', 'FeatureCollection', 'features', log_geojson || COALESCE(metrics_geojson, '[]'::jsonb) || COALESCE(log_legs_geojson->'features', '[]'::jsonb));

END;
$$;


--
-- Name: FUNCTION export_logbook_geojson_trip_fn(_id integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_logbook_geojson_trip_fn(_id integer) IS 'Export a log trip entry to GEOJSON format with custom properties for timelapse replay';


--
-- Name: export_logbook_gpx_trip_fn(integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_logbook_gpx_trip_fn(_id integer) RETURNS public."text/xml"
    LANGUAGE plpgsql
    AS $$
DECLARE
    app_settings jsonb;
BEGIN
    -- Validate input
    IF _id IS NULL OR _id < 1 THEN
        RAISE WARNING '-> export_logbook_gpx_trip_fn invalid input %', _id;
        RETURN '';
    END IF;

    -- Retrieve application settings
    app_settings := get_app_url_fn();

    -- Generate GPX XML with structured track data
    RETURN xmlelement(name gpx,
                      xmlattributes( '1.1' as version,
                                     'PostgSAIL' as creator,
                                     'http://www.topografix.com/GPX/1/1' as xmlns,
                                     'http://www.opencpn.org' as "xmlns:opencpn",
                                     app_settings->>'app.url' as "xmlns:postgsail",
                                     'http://www.w3.org/2001/XMLSchema-instance' as "xmlns:xsi",
                                     'http://www.garmin.com/xmlschemas/GpxExtensions/v3' as "xmlns:gpxx",
                                     'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/GpxExtensions/v3 http://www8.garmin.com/xmlschemas/GpxExtensionsv3.xsd' as "xsi:schemaLocation"),

        -- Metadata section
        xmlelement(name metadata,
                   xmlelement(name link, xmlattributes(app_settings->>'app.url' as href),
                              xmlelement(name text, 'PostgSail'))),

        -- Track section
        xmlelement(name trk,
                   xmlelement(name name, l.name),
                   xmlelement(name desc, l.notes),
                   xmlelement(name link, xmlattributes(concat(app_settings->>'app.url', '/log/', l.id) as href),
                              xmlelement(name text, l.name)),
                   xmlelement(name extensions,
                              xmlelement(name "postgsail:log_id", l.id),
                              xmlelement(name "postgsail:link", concat(app_settings->>'app.url', '/log/', l.id)),
                              xmlelement(name "opencpn:guid", uuid_generate_v4()),
                              xmlelement(name "opencpn:viz", '1'),
                              xmlelement(name "opencpn:start", l._from_time),
                              xmlelement(name "opencpn:end", l._to_time)),

                   -- Track segments with point data
                   xmlelement(name trkseg, xmlagg(
                               xmlelement(name trkpt,
                                          xmlattributes( ST_Y(getvalue(point)::geometry) as lat, ST_X(getvalue(point)::geometry) as lon ),
                                          xmlelement(name time, getTimestamp(point))
                               )))
        )
    )::pg_catalog.xml
    FROM api.logbook l
    JOIN LATERAL (
        SELECT unnest(instants(trip)) AS point
        FROM api.logbook WHERE id = _id
    ) AS points ON true
    WHERE l.id = _id
	GROUP BY l.name, l.notes, l.id;
END;
$$;


--
-- Name: FUNCTION export_logbook_gpx_trip_fn(_id integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_logbook_gpx_trip_fn(_id integer) IS 'Export a log trip entry to GPX XML format';


--
-- Name: export_logbook_kml_trip_fn(integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_logbook_kml_trip_fn(_id integer) RETURNS public."text/xml"
    LANGUAGE plpgsql
    AS $$
DECLARE
    logbook_rec RECORD;
BEGIN
    -- Validate input ID
    IF _id IS NULL OR _id < 1 THEN
        RAISE WARNING '-> export_logbook_kml_trip_fn invalid input %', _id;
        RETURN '';
    END IF;

    -- Fetch logbook details including the track geometry
    SELECT id, name, notes, vessel_id, ST_AsKML(trajectory(trip)) AS track_kml INTO logbook_rec
        FROM api.logbook 
        WHERE id = _id;

    -- Check if the logbook record is found
    IF logbook_rec.vessel_id IS NULL THEN
        RAISE WARNING '-> export_logbook_kml_trip_fn invalid logbook %', _id;
        RETURN '';
    END IF;

    -- Generate KML XML document
    RETURN xmlelement(
        name kml,
        xmlattributes(
            '1.0' as version,
            'PostgSAIL' as creator,
            'http://www.w3.org/2005/Atom' as "xmlns:atom",
            'http://www.opengis.net/kml/2.2' as "xmlns",
            'http://www.google.com/kml/ext/2.2' as "xmlns:gx",
            'http://www.opengis.net/kml/2.2' as "xmlns:kml"
        ),
        xmlelement(
            name "Document",
            xmlelement(name "name", logbook_rec.name),
            xmlelement(name "description", logbook_rec.notes),
            xmlelement(
                name "Placemark",
                logbook_rec.track_kml::pg_catalog.xml
            )
        )
    )::pg_catalog.xml;
END;
$$;


--
-- Name: FUNCTION export_logbook_kml_trip_fn(_id integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_logbook_kml_trip_fn(_id integer) IS 'Export a log trip entry to KML XML format';


--
-- Name: export_logbook_metrics_trip_fn(integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_logbook_metrics_trip_fn(_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    logbook_rec RECORD;
    metrics_geojson JSONB;
    first_feature_obj JSONB;
    second_feature_note JSONB;
    last_feature_note JSONB;
BEGIN
    -- Validate input
    IF _id IS NULL OR _id < 1 THEN
        RAISE WARNING '-> export_logbook_metrics_trip_fn invalid input %', _id;
        RETURN NULL;
    END IF;

    -- Fetch the processed logbook data.
    SELECT id, name, distance, duration, _from, _to
    INTO logbook_rec
    FROM api.logbook
    WHERE id = _id;

    -- Create JSON notes for feature properties
    first_feature_obj := jsonb_build_object('trip', jsonb_build_object('name', logbook_rec.name, 'duration', logbook_rec.duration, 'distance', logbook_rec.distance));
    second_feature_note := jsonb_build_object('notes', COALESCE(logbook_rec._from, ''));
    last_feature_note := jsonb_build_object('notes', COALESCE(logbook_rec._to, ''));

    -- GeoJSON Features for Metrics Points
    SELECT jsonb_agg(ST_AsGeoJSON(t.*)::jsonb) INTO metrics_geojson
    FROM (
        SELECT 
            geometry(getvalue(points.point)) AS point_geometry,
            getTimestamp(points.point) AS time,
            valueAtTimestamp(points.trip_cog, getTimestamp(points.point)) AS courseovergroundtrue,
            valueAtTimestamp(points.trip_sog, getTimestamp(points.point)) AS speedoverground,
            valueAtTimestamp(points.trip_aws, getTimestamp(points.point)) AS windspeedapparent,
            valueAtTimestamp(points.trip_awa, getTimestamp(points.point)) AS windangleapparent,
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
                    trip_aws,
                    trip_awa,
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
            WHEN (metrics_geojson->1->'properties'->>'notes') = '' THEN -- it is not null but empty??
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
            WHEN (metrics_geojson->-1->'properties'->>'notes') = '' THEN -- it is not null but empty??
                (metrics_geojson->-1->'properties' || last_feature_note)::jsonb
            ELSE
                metrics_geojson->-1->'properties'
        END,
        true
    );

    -- Set output
    RETURN metrics_geojson;

END;
$$;


--
-- Name: FUNCTION export_logbook_metrics_trip_fn(_id integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_logbook_metrics_trip_fn(_id integer) IS 'Export a log entry to an array of GeoJSON feature format of geometry point';


--
-- Name: export_logbook_polar_csv_fn(integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_logbook_polar_csv_fn(_id integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_csv text;
    v_header text;
BEGIN

    -- Safety check
    IF _id IS NULL THEN
        RAISE EXCEPTION 'Logbook id % not found', _id;
    END IF;

    -- Build header dynamically (fix: subquery for distinct tws_bin)
    SELECT 'twa/tws;' || string_agg(tws_bin::text, ';')
    INTO v_header
    FROM (
        SELECT DISTINCT g.tws_bin
        FROM public.export_logbook_polar_fn(_id) g
        ORDER BY g.tws_bin
    ) sub;

    -- Build body: pivot rows into CSV
    SELECT string_agg(row_line, E'\n')
    INTO v_csv
    FROM (
        SELECT p.awa_bin::text || ';' ||
               string_agg(COALESCE(p.avg_speed_txt, '0.0'), ';' ORDER BY p.tws_bin) AS row_line
        FROM (
            SELECT a.awa_bin,
                   t.tws_bin,
                   COALESCE(
                       to_char(MAX(g.avg_speed), 'FM999999990.000'),
                       '0.0'
                   ) AS avg_speed_txt
            FROM (SELECT DISTINCT g1.awa_bin FROM public.export_logbook_polar_fn(_id) g1) a
            CROSS JOIN (SELECT DISTINCT g2.tws_bin FROM public.export_logbook_polar_fn(_id) g2) t
            LEFT JOIN public.export_logbook_polar_fn(_id) g
                   ON g.awa_bin = a.awa_bin
                  AND g.tws_bin = t.tws_bin
            GROUP BY a.awa_bin, t.tws_bin
        ) p
        GROUP BY p.awa_bin
        ORDER BY p.awa_bin
    ) rows;

    -- Prepend header
    v_csv := v_header || E'\n' || COALESCE(v_csv, '');

    RETURN v_csv;
END;
$$;


--
-- Name: FUNCTION export_logbook_polar_csv_fn(_id integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_logbook_polar_csv_fn(_id integer) IS 'Generate polar csv in the orc-data format for a log';


--
-- Name: export_logbooks_geojson_linestring_trips_fn(integer, integer, text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_logbooks_geojson_linestring_trips_fn(start_log integer DEFAULT NULL::integer, end_log integer DEFAULT NULL::integer, start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT geojson jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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
            avg_speed, -- avg speed in knots
            max_speed, -- max speed in knots
            duration(trip),
            --length(trip) as length, -- Meters
            (length(trip)/1852)::NUMERIC(6,2) as distance, -- in Nautical Miles
            maxValue(trip_sog) as max_sog, -- SOG
            maxValue(trip_aws) as max_aws, -- Wind Speed Apparent
            maxValue(trip_awa) as max_awa, -- Wind Angle Apparent
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
            twavg(trip_aws) as avg_aws, -- Wind Speed Apparent
            twavg(trip_awa) as avg_awa, -- Wind Angle Apparent
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
$$;


--
-- Name: FUNCTION export_logbooks_geojson_linestring_trips_fn(start_log integer, end_log integer, start_date text, end_date text, OUT geojson jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_logbooks_geojson_linestring_trips_fn(start_log integer, end_log integer, start_date text, end_date text, OUT geojson jsonb) IS 'Generate geojson geometry LineString from trip with the corresponding properties';


--
-- Name: export_logbooks_geojson_point_trips_fn(integer, integer, text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_logbooks_geojson_point_trips_fn(start_log integer DEFAULT NULL::integer, end_log integer DEFAULT NULL::integer, start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT geojson jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    metrics_geojson jsonb;
BEGIN
    -- Normalize start and end values
    IF start_log IS NOT NULL AND end_log IS NULL THEN end_log := start_log; END IF;
    IF start_date IS NOT NULL AND end_date IS NULL THEN end_date := start_date; END IF;

    WITH logbook_data AS (
        -- get the logbook data, an array for each log
        SELECT api.export_logbook_metrics_trip_fn(l.id) AS log_geojson
        FROM api.logbook l
        WHERE (start_log IS NULL OR l.id >= start_log) AND
              (end_log IS NULL OR l.id <= end_log) AND
              (start_date IS NULL OR l._from_time >= start_date::TIMESTAMPTZ) AND
              (end_date IS NULL OR l._to_time <= end_date::TIMESTAMPTZ + interval '23 hours 59 minutes') AND
              l.trip IS NOT NULL
        ORDER BY l._from_time ASC
    )
    -- Create the GeoJSON response
    SELECT jsonb_build_object(
        'type', 'FeatureCollection',
        'features', jsonb_agg(feature_element)) INTO geojson
        FROM logbook_data l,
            LATERAL jsonb_array_elements(l.log_geojson) AS feature_element; -- Flatten the arrays and create a GeoJSON FeatureCollection
END;
$$;


--
-- Name: FUNCTION export_logbooks_geojson_point_trips_fn(start_log integer, end_log integer, start_date text, end_date text, OUT geojson jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_logbooks_geojson_point_trips_fn(start_log integer, end_log integer, start_date text, end_date text, OUT geojson jsonb) IS 'Export all selected logs into a geojson `trip` to a geojson as points including properties';


--
-- Name: export_logbooks_gpx_trips_fn(integer, integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_logbooks_gpx_trips_fn(start_log integer DEFAULT NULL::integer, end_log integer DEFAULT NULL::integer) RETURNS public."text/xml"
    LANGUAGE plpgsql
    AS $$
    declare
        merged_xml XML;
        app_settings jsonb;
    BEGIN
        -- Merge GIS track_geom of geometry type Point into a jsonb array format
        -- Normalize start and end values
        IF start_log IS NOT NULL AND end_log IS NULL THEN end_log := start_log; END IF;

        -- Gather url from app settings
        app_settings := get_app_url_fn();

        WITH logbook_data AS (
            -- get the logbook data, an array for each log
            SELECT 
                ST_Y(getvalue(point)::geometry) as lat,
                ST_X(getvalue(point)::geometry) as lon,
                getTimestamp(point) as time
            FROM (
                SELECT unnest(instants(trip)) AS point
                FROM api.logbook l
                WHERE (start_log IS NULL OR l.id >= start_log) AND
                    (end_log IS NULL OR l.id <= end_log) AND
                    l.trip IS NOT NULL
                ORDER BY l._from_time ASC
            ) AS points
        )

        --RAISE WARNING '-> export_logbooks_gpx_fn app_settings %', app_settings;
        -- Generate GPX XML, extract Point features from trip.
        SELECT xmlelement(name "gpx",
                            xmlattributes(  '1.1' as version,
                                            'PostgSAIL' as creator,
                                            'http://www.topografix.com/GPX/1/1' as xmlns,
                                            'http://www.opencpn.org' as "xmlns:opencpn",
                                            app_settings->>'app.url' as "xmlns:postgsail"),
                xmlelement(name "metadata",
                    xmlelement(name "link", xmlattributes(app_settings->>'app.url' as href),
                        xmlelement(name "text", 'PostgSail'))),
                xmlelement(name "trk",
                    xmlelement(name "name", 'trip name'),
                    xmlelement(name "trkseg", xmlagg(
                                                xmlelement(name "trkpt",
                                                    xmlattributes(lat, lon),
                                                        xmlelement(name "time", time)
                                                )))))::pg_catalog.xml
            INTO merged_xml
            FROM logbook_data;
            return merged_xml;
    END;
$$;


--
-- Name: FUNCTION export_logbooks_gpx_trips_fn(start_log integer, end_log integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_logbooks_gpx_trips_fn(start_log integer, end_log integer) IS 'Export a logs entries to GPX XML format';


--
-- Name: export_logbooks_kml_trips_fn(integer, integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_logbooks_kml_trips_fn(start_log integer DEFAULT NULL::integer, end_log integer DEFAULT NULL::integer) RETURNS public."text/xml"
    LANGUAGE plpgsql
    AS $$
DECLARE
    _geom geometry;
    app_settings jsonb;
BEGIN
    -- Normalize start and end values
    IF start_log IS NOT NULL AND end_log IS NULL THEN end_log := start_log; END IF;

    WITH logbook_data AS (
        -- get the logbook data, an array for each log
        SELECT
            trajectory(trip)::geometry as track_geog -- extract trip to geography
        FROM api.logbook l
        WHERE (start_log IS NULL OR l.id >= start_log) AND
              (end_log IS NULL OR l.id <= end_log) AND
              l.trip IS NOT NULL
        ORDER BY l._from_time ASC
    )
    SELECT ST_Collect(
                        ARRAY(
                            SELECT track_geog FROM logbook_data)
            ) INTO _geom;

    -- Extract POINT from LINESTRING to generate KML XML
    RETURN xmlelement(name kml,
            xmlattributes(  '1.0' as version,
                            'PostgSAIL' as creator,
                            'http://www.w3.org/2005/Atom' as "xmlns:atom",
                            'http://www.opengis.net/kml/2.2' as "xmlns",
                            'http://www.google.com/kml/ext/2.2' as "xmlns:gx",
                            'http://www.opengis.net/kml/2.2' as "xmlns:kml"),
            xmlelement(name "Document",
                xmlelement(name "name", 'trip name'),
                xmlelement(name "Placemark",
                    ST_AsKML(_geom)::pg_catalog.xml
                )
            )
        )::pg_catalog.xml;
END;
$$;


--
-- Name: FUNCTION export_logbooks_kml_trips_fn(start_log integer, end_log integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_logbooks_kml_trips_fn(start_log integer, end_log integer) IS 'Export a logs entries to KML XML format';


--
-- Name: export_moorages_geojson_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_moorages_geojson_fn(OUT geojson jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
    DECLARE
    BEGIN
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features',
                ( SELECT
                    json_agg(ST_AsGeoJSON(m.*)::JSON) as moorages_geojson
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
                    ) AS m
                )
            ) INTO geojson;
    END;
$$;


--
-- Name: FUNCTION export_moorages_geojson_fn(OUT geojson jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_moorages_geojson_fn(OUT geojson jsonb) IS 'Export moorages as geojson';


--
-- Name: export_moorages_gpx_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_moorages_gpx_fn() RETURNS public."text/xml"
    LANGUAGE plpgsql
    AS $$
    DECLARE
        app_settings jsonb;
    BEGIN
        -- Gather url from app settings
        app_settings := get_app_url_fn();
        -- Generate XML
        RETURN xmlelement(name gpx,
                    xmlattributes(  '1.1' as version,
                                    'PostgSAIL' as creator,
                                    'http://www.topografix.com/GPX/1/1' as xmlns,
                                    'http://www.opencpn.org' as "xmlns:opencpn",
                                    app_settings->>'app.url' as "xmlns:postgsail",
                                    'http://www.w3.org/2001/XMLSchema-instance' as "xmlns:xsi",
                                    'http://www.garmin.com/xmlschemas/GpxExtensions/v3' as "xmlns:gpxx",
                                    'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/GpxExtensions/v3 http://www8.garmin.com/xmlschemas/GpxExtensionsv3.xsd' as "xsi:schemaLocation"),
                    xmlagg(
                        xmlelement(name wpt, xmlattributes(m.latitude as lat, m.longitude as lon),
                            xmlelement(name name, m.name),
                            xmlelement(name time, m.stay_first_seen),
                            xmlelement(name desc,
                                concat(E'First Stayed On: ',  m.stay_first_seen,
                                    E'\nLast Stayed On: ',  m.stay_last_seen,
                                    E'\nTotal Stays Visits: ', m.stays_count,
                                    E'\nTotal Stays Duration: ', m.stays_sum_duration,
                                    E'\nTotal Logs, Arrivals and Departures: ', m.logs_count,
                                    E'\nNotes: ', m.notes,
                                    E'\nLink: ', concat(app_settings->>'app.url','/moorage/', m.id)),
                                    xmlelement(name "opencpn:guid", uuid_generate_v4())),
                            xmlelement(name sym, 'anchor'),
                            xmlelement(name type, 'WPT'),
                            xmlelement(name link, xmlattributes(concat(app_settings->>'app.url','/moorage/', m.id) as href),
                                                        xmlelement(name text, m.name)),
                            xmlelement(name extensions, xmlelement(name "postgsail:mooorage_id", m.id),
                                                        xmlelement(name "postgsail:link", concat(app_settings->>'app.url','/moorage/', m.id)),
                                                        xmlelement(name "opencpn:guid", uuid_generate_v4()),
                                                        xmlelement(name "opencpn:viz", '1'),
                                                        xmlelement(name "opencpn:scale_min_max", xmlattributes(true as UseScale, 30000 as ScaleMin, 0 as ScaleMax)
                                                        ))))
                    )::pg_catalog.xml
            FROM api.moorage_view m
            WHERE geog IS NOT NULL;
    END;
$$;


--
-- Name: FUNCTION export_moorages_gpx_fn(); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_moorages_gpx_fn() IS 'Export moorages as gpx';


--
-- Name: export_moorages_kml_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_moorages_kml_fn() RETURNS public."text/xml"
    LANGUAGE plpgsql
    AS $$
    DECLARE
        app_settings jsonb;
    BEGIN
        -- Gather url from app settings
        app_settings := get_app_url_fn();
        -- Generate XML
        RETURN xmlelement(name kml,
                    xmlattributes(  '1.0' as version,
                                    'PostgSAIL' as creator,
                                    'http://www.w3.org/2005/Atom' as "xmlns:atom",
                                    'http://www.opengis.net/kml/2.2' as "xmlns",
                                    'http://www.google.com/kml/ext/2.2' as "xmlns:gx",
                                    'http://www.opengis.net/kml/2.2' as "xmlns:kml"),
                    xmlelement(name "Document",
                        xmlagg(
                            xmlelement(name "Placemark",
                                xmlelement(name "name", m.name),
                                xmlelement(name "description",
                                    concat(E'First Stayed On: ', m.stay_first_seen,
                                        E'\nLast Stayed On: ', m.stay_last_seen,
                                        E'\nTotal Stays Visits: ', m.stays_count,
                                        E'\nTotal Stays Duration: ', m.stays_sum_duration,
                                        E'\nTotal Logs, Arrivals and Departures: ', m.logs_count,
                                        E'\nNotes: ', m.notes,
                                        E'\nLink: ', concat(app_settings->>'app.url','/moorage/', m.id))),
                                ST_AsKml(m.geog)::XML)
                        )
                    )
                )::pg_catalog.xml
            FROM api.moorage_view m
            WHERE geog IS NOT NULL;
    END;
$$;


--
-- Name: FUNCTION export_moorages_kml_fn(); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_moorages_kml_fn() IS 'Export moorages as kml';


--
-- Name: export_stays_geojson_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_stays_geojson_fn(OUT geojson jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: FUNCTION export_stays_geojson_fn(OUT geojson jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_stays_geojson_fn(OUT geojson jsonb) IS 'Export stays as geojson';


--
-- Name: export_vessel_geojson_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.export_vessel_geojson_fn(OUT geojson jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: FUNCTION export_vessel_geojson_fn(OUT geojson jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.export_vessel_geojson_fn(OUT geojson jsonb) IS 'Export vessel as geojson';


--
-- Name: find_log_from_moorage_fn(integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.find_log_from_moorage_fn(_id integer, OUT geojson jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
    DECLARE
        moorage_rec record;
        _geojson jsonb;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> find_log_from_moorage_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Gather moorage details
        SELECT * INTO moorage_rec
            FROM api.moorages m
            WHERE m.id = _id;
        -- Find all log from and to moorage geopoint within 100m
        SELECT api.export_logbook_geojson_linestring_trip_fn(id)::JSON->'features' INTO _geojson
            FROM api.logbook l
            WHERE ST_DWithin(
                    Geography(ST_MakePoint(l._from_lng, l._from_lat)),
                    moorage_rec.geog,
                    1000 -- in meters ?
                );
        -- Return a GeoJSON filter on LineString
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', _geojson ) INTO geojson;
    END;
$$;


--
-- Name: FUNCTION find_log_from_moorage_fn(_id integer, OUT geojson jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.find_log_from_moorage_fn(_id integer, OUT geojson jsonb) IS 'Find all log from moorage geopoint within 100m';


--
-- Name: find_log_to_moorage_fn(integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.find_log_to_moorage_fn(_id integer, OUT geojson jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
    DECLARE
        moorage_rec record;
        _geojson jsonb;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> find_log_from_moorage_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Gather moorage details
        SELECT * INTO moorage_rec
            FROM api.moorages m
            WHERE m.id = _id;
        -- Find all log from and to moorage geopoint within 100m
        SELECT api.export_logbook_geojson_linestring_trip_fn(id)::JSON->'features' INTO _geojson
            FROM api.logbook l
            WHERE ST_DWithin(
                    Geography(ST_MakePoint(l._to_lng, l._to_lat)),
                    moorage_rec.geog,
                    1000 -- in meters ?
                );
        -- Return a GeoJSON filter on LineString
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', _geojson ) INTO geojson;
    END;
$$;


--
-- Name: FUNCTION find_log_to_moorage_fn(_id integer, OUT geojson jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.find_log_to_moorage_fn(_id integer, OUT geojson jsonb) IS 'Find all log to moorage geopoint within 100m';


--
-- Name: find_stay_from_moorage_fn(integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.find_stay_from_moorage_fn(_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        moorage_rec record;
        stay_rec record;
    BEGIN
        -- If _id is is not NULL and > 0
        SELECT * INTO moorage_rec
            FROM api.moorages m 
            WHERE m.id = _id;
        -- find all log from and to moorage geopoint within 100m
        --RETURN QUERY
            SELECT s.id,s.arrived,s.departed,s.duration,sa.description
                FROM api.stays s, api.stays_at sa
                WHERE ST_DWithin(
                        s.geog,
                        moorage_rec.geog,
                        100 -- in meters ?
                    )
                    AND departed IS NOT NULL
                    AND s.name IS NOT NULL
                    AND s.stay_code = sa.stay_code
                ORDER BY s.arrived DESC;
    END;
$$;


--
-- Name: FUNCTION find_stay_from_moorage_fn(_id integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.find_stay_from_moorage_fn(_id integer) IS 'Find all stay within 100m of moorage geopoint';


--
-- Name: generate_otp_fn(text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.generate_otp_fn(email text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION generate_otp_fn(email text); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.generate_otp_fn(email text) IS 'Generate otp code';


--
-- Name: ispublic_fn(text, text, integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.ispublic_fn(boat text, _type text, _id integer DEFAULT NULL::integer) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
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
$_$;


--
-- Name: FUNCTION ispublic_fn(boat text, _type text, _id integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.ispublic_fn(boat text, _type text, _id integer) IS 'Is web page publicly accessible by register boat name and/or logbook id';


--
-- Name: logbook_update_geojson_trip_fn(integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.logbook_update_geojson_trip_fn(_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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
        RAISE WARNING '-> logbook_update_geojson_trip_fn invalid input %', _id;
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
    FROM (
        SELECT 
            geometry(getvalue(points.point)) AS point_geometry,
            getTimestamp(points.point) AS time,
            valueAtTimestamp(points.trip_cog, getTimestamp(points.point)) AS cog,
            valueAtTimestamp(points.trip_sog, getTimestamp(points.point)) AS sog,
            valueAtTimestamp(points.trip_aws, getTimestamp(points.point)) AS aws,
            valueAtTimestamp(points.trip_awa, getTimestamp(points.point)) AS awa,
            valueAtTimestamp(points.trip_tws, getTimestamp(points.point)) AS tws,
            valueAtTimestamp(points.trip_twd, getTimestamp(points.point)) AS twd,
            valueAtTimestamp(points.trip_notes, getTimestamp(points.point)) AS notes,
            valueAtTimestamp(points.trip_status, getTimestamp(points.point)) AS status,
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
                    trip_aws,
                    trip_awa,
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
            WHEN (metrics_geojson->1->'properties'->>'notes') IS NULL THEN 
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
            WHEN (metrics_geojson->-1->'properties'->>'notes') IS NULL THEN
                (metrics_geojson->-1->'properties' || last_feature_note)::jsonb
            ELSE
                metrics_geojson->-1->'properties'
        END,
        true
    );

    -- Combine Logbook and Metrics GeoJSON
    RETURN jsonb_build_object('type', 'FeatureCollection', 'features', log_geojson || metrics_geojson);

END;
$$;


--
-- Name: FUNCTION logbook_update_geojson_trip_fn(_id integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.logbook_update_geojson_trip_fn(_id integer) IS 'Export a log trip entry to GEOJSON format with custom properties for timelapse replay';


--
-- Name: login(text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.login(email text, pass text) RETURNS auth.jwt_token
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  _role name;
  result auth.jwt_token;
  app_jwt_secret text;
  _email_valid boolean := false;
  _email text := email;
  _user_id text := null;
  _user_disable boolean := false;
  headers   json := current_setting('request.headers', true)::json;
  client_ip text := coalesce(headers->>'x-client-ip', NULL);
begin
  -- check email and password
  select auth.user_role(email, pass) into _role;
  if _role is null then
    -- HTTP/403
    --raise invalid_password using message = 'invalid user or password';
    -- HTTP/401
    --raise insufficient_privilege using message = 'invalid user or password';
    -- HTTP/402 - to distinguish with JWT Expiration token
    RAISE sqlstate 'PT402' using message = 'invalid email or password',
            detail = 'invalid auth specification',
            hint = 'Use a valid email and password';
  end if;

  -- Gather user information
  SELECT preferences['disable'], preferences['email_valid'], user_id 
        INTO _user_disable,_email_valid,_user_id
        FROM auth.accounts a
        WHERE a.email = _email;

  -- Check if user is disable due to abuse
  IF _user_disable::BOOLEAN IS TRUE THEN
  	-- due to the raise, the insert is never committed.
    --INSERT INTO process_queue (channel, payload, stored, ref_id)
    --  VALUES ('account_disable', _email, now(), _user_id);
    RAISE sqlstate 'PT402' using message = 'Account disable, contact us',
            detail = 'Quota exceeded',
            hint = 'Upgrade your plan';
  END IF;

  -- Check if email has been verified, if not generate OTP
  IF _email_valid::BOOLEAN IS NOT True THEN
    INSERT INTO process_queue (channel, payload, stored, ref_id)
      VALUES ('email_otp', _email, now(), _user_id);
  END IF;

  -- Track IP per user to avoid abuse
  --RAISE WARNING 'api.login debug: [%],[%]', client_ip, login.email;
  IF client_ip IS NOT NULL THEN
    UPDATE auth.accounts a SET 
        preferences = jsonb_recursive_merge(a.preferences, jsonb_build_object('ip', client_ip)),
        connected_at = NOW()
        WHERE a.email = login.email;
  END IF;

  -- Get app_jwt_secret
  SELECT value INTO app_jwt_secret
    FROM app_settings
    WHERE name = 'app.jwt_secret';

  --RAISE WARNING 'api.login debug: [%],[%],[%]', app_jwt_secret, _role, login.email;
  -- Generate jwt
  select jwt.sign(
  --    row_to_json(r), ''
  --    row_to_json(r)::json, current_setting('app.jwt_secret')::text
      row_to_json(r)::json, app_jwt_secret
    ) as token
    from (
      select _role as role, login.email as email,  -- TODO replace with user_id
    --  select _role as role, user_id as uid, -- add support in check_jwt
         extract(epoch from now())::integer + 60*60 as exp
    ) r
    into result;
  return result;
end;
$$;


--
-- Name: FUNCTION login(email text, pass text); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.login(email text, pass text) IS 'Handle user login, returns a JWT token with user role and email.';


--
-- Name: logs_by_day_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.logs_by_day_fn(OUT charts jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
    DECLARE
        data JSONB;
    BEGIN
        -- Query logs by day
        SELECT json_object_agg(day,count) INTO data
            FROM (
                    SELECT
                        to_char(date_trunc('day', _from_time), 'D') as day,
                        count(*) as count
                        FROM api.logbook
                        GROUP BY day
                        ORDER BY day
                ) AS t;
        -- Merge jsonb to get all 7 days
        SELECT '{"01": 0, "02": 0, "03": 0, "04": 0, "05": 0, "06": 0, "07": 0}'::jsonb ||
            data::jsonb INTO charts;
    END;
$$;


--
-- Name: FUNCTION logs_by_day_fn(OUT charts jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.logs_by_day_fn(OUT charts jsonb) IS 'logbook by day for web charts';


--
-- Name: logs_by_month_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.logs_by_month_fn(OUT charts jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
    DECLARE
        data JSONB;
    BEGIN
        -- Query logs by month
        SELECT json_object_agg(month,count) INTO data
            FROM (
                    SELECT
                        to_char(date_trunc('month', _from_time), 'MM') as month,
                        count(*) as count
                        FROM api.logbook
                        GROUP BY month
                        ORDER BY month
                ) AS t;
        -- Merge jsonb to get all 12 months
        SELECT '{"01": 0, "02": 0, "03": 0, "04": 0, "05": 0, "06": 0, "07": 0, "08": 0, "09": 0, "10": 0, "11": 0,"12": 0}'::jsonb ||
            data::jsonb INTO charts;
    END;
$$;


--
-- Name: FUNCTION logs_by_month_fn(OUT charts jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.logs_by_month_fn(OUT charts jsonb) IS 'logbook by month for web charts';


--
-- Name: merge_logbook_fn(integer, integer); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.merge_logbook_fn(id_start integer, id_end integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        logbook_rec_start record;
        logbook_rec_end record;
        log_name text;
        avg_rec record;
        geo_rec record;
        geojson jsonb;
        extra_json jsonb;
        t_rec record;
        _max_wind_speed NUMERIC;
        _avg_wind_speed NUMERIC;
    BEGIN
        -- If id_start or id_end is not NULL
        IF (id_start IS NULL OR id_start < 1) OR (id_end IS NULL OR id_end < 1) THEN
            RAISE WARNING '-> merge_logbook_fn invalid input % %', id_start, id_end;
            RETURN;
        END IF;
        -- If id_end is lower than id_start
        IF id_end <= id_start THEN
            RAISE WARNING '-> merge_logbook_fn invalid input % < %', id_end, id_start;
            RETURN;
        END IF;
        -- Get the start logbook record with all necessary fields exist
        SELECT * INTO logbook_rec_start
            FROM api.logbook
            WHERE active IS false
                AND id = id_start
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        -- Ensure the query is successful
        IF logbook_rec_start.vessel_id IS NULL THEN
            RAISE WARNING '-> merge_logbook_fn invalid logbook %', id_start;
            RETURN;
        END IF;
        -- Get the end logbook record with all necessary fields exist
        SELECT * INTO logbook_rec_end
            FROM api.logbook
            WHERE active IS false
                AND id = id_end
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        -- Ensure the query is successful
        IF logbook_rec_end.vessel_id IS NULL THEN
            RAISE WARNING '-> merge_logbook_fn invalid logbook %', id_end;
            RETURN;
        END IF;

       	RAISE WARNING '-> merge_logbook_fn logbook start:% end:%', id_start, id_end;
        PERFORM set_config('vessel.id', logbook_rec_start.vessel_id, false);
   
        -- Calculate logbook data average and geo
        -- Update logbook entry with the latest metric data and calculate data
        avg_rec := logbook_update_avg_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);
        geo_rec := logbook_update_geom_distance_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);

	    -- Process `propulsion.*.runTime` and `navigation.log`
        -- Calculate extra json
        extra_json := logbook_update_extra_json_fn(logbook_rec_start.id, logbook_rec_start._from_time::TEXT, logbook_rec_end._to_time::TEXT);

       	-- generate logbook name, concat _from_location and _to_location from moorage name
       	SELECT CONCAT(logbook_rec_start._from, ' to ', logbook_rec_end._to) INTO log_name;

        -- mobilitydb, add spaciotemporal sequence
        -- reduce the numbers of metrics by skipping row or aggregate time-series
        -- By default the signalk PostgSail plugin report one entry every minute.
        IF avg_rec.count_metric < 30 THEN -- if less ~20min trip we keep it all data
            t_rec := public.logbook_update_metrics_short_fn(avg_rec.count_metric, logbook_rec_start._from_time, logbook_rec_end._to_time);
        --ELSIF avg_rec.count_metric < 2000 THEN -- if less ~33h trip we skip data
        --    t_rec := public.logbook_update_metrics_fn(avg_rec.count_metric, logbook_rec_start._from_time, logbook_rec_end._to_time);
        ELSE -- As we have too many data, we time-series aggregate data
            t_rec := public.logbook_update_metrics_timebucket_fn(avg_rec.count_metric, logbook_rec_start._from_time, logbook_rec_end._to_time);
        END IF;
        --RAISE NOTICE 'mobilitydb [%]', t_rec;
        IF t_rec.trajectory IS NULL THEN
            RAISE WARNING '-> merge_logbook_fn, vessel_id [%], invalid mobilitydb data [%] [%]', logbook_rec_start.vessel_id, logbook_rec_start.id, t_rec;
            RETURN;
        END IF;
        IF t_rec.truewindspeed IS NULL AND t_rec.windspeedapparent IS NOT NULL THEN
            _max_wind_speed := maxValue(t_rec.windspeedapparent)::NUMERIC(6,2); -- Fallback to apparent wind speed
            _avg_wind_speed := twAvg(t_rec.windspeedapparent)::NUMERIC(6,2); -- Fallback to apparent wind speed
        ELSE
            _max_wind_speed := maxValue(t_rec.truewindspeed)::NUMERIC(6,2);
            _avg_wind_speed := twAvg(t_rec.truewindspeed)::NUMERIC(6,2);
        END IF;
        -- add the avg_wind_speed
        -- Update the avg_wind_speed from mobilitydb data -- TWS in knots
        extra_json := extra_json || jsonb_build_object('avg_wind_speed', _avg_wind_speed);

        RAISE NOTICE 'Updating valid logbook entry logbook id:[%] start:[%] end:[%]', logbook_rec_start.id, logbook_rec_start._from_time, logbook_rec_end._to_time;
        UPDATE api.logbook
            SET
                duration = (logbook_rec_end._to_time::TIMESTAMPTZ - logbook_rec_start._from_time::TIMESTAMPTZ),
                -- Problem with invalid SOG metrics
                --avg_speed = twAvg(t_rec.speedoverground)::NUMERIC(6,2), -- avg speed in knots
                max_speed = maxValue(t_rec.speedoverground)::NUMERIC(6,2), -- max speed in knots
                -- Calculate speed using mobility from m/s to knots - MobilityDB calculates instantaneous speed between consecutive GPS points
                avg_speed = (twavg(speed(t_rec.trajectory)) * 1.94384)::NUMERIC(6,2), -- avg speed in knots
                --max_speed = (maxValue(speed(t_rec.trajectory)) * 1.94384)::NUMERIC(6,2), -- max speed in knots
                max_wind_speed = _max_wind_speed, -- TWS in knots
                -- Set _to metrics from end logbook
                _to = logbook_rec_end._to,
                _to_moorage_id = logbook_rec_end._to_moorage_id,
                _to_lat = logbook_rec_end._to_lat,
                _to_lng = logbook_rec_end._to_lng,
                _to_time = logbook_rec_end._to_time,
                name = log_name,
                --distance = geo_rec._track_distance, -- in Nautical Miles
                distance = (length(t_rec.trajectory)/1852)::NUMERIC(10,2), -- in Nautical Miles
                extra = extra_json,
                notes = NULL, -- reset pre_log process
                trip = t_rec.trajectory,
                trip_cog = t_rec.courseovergroundtrue,
                trip_sog = t_rec.speedoverground,
                trip_aws = t_rec.windspeedapparent,
                trip_awa = t_rec.windangleapparent,
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
            WHERE id = logbook_rec_start.id;

        /*** Deprecated removed column
        -- GeoJSON require track_geom field geometry linestring
        --geojson := logbook_update_geojson_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        -- GeoJSON require trip* columns
        geojson := api.logbook_update_geojson_trip_fn(logbook_rec_start.id);
        UPDATE api.logbook
            SET -- Update the data column, it should be generate dynamically on request
                -- However there is a lot of dependencies to consider for a larger cleanup
                -- badges, qgis etc... depends on track_geom
                -- many export and others functions depends on track_geojson
                track_geojson = geojson,
                track_geog = trajectory(t_rec.trajectory),
                track_geom = trajectory(t_rec.trajectory)::geometry
         --       embedding = NULL,
         --       spatial_embedding = NULL
            WHERE id = logbook_rec_start.id;

        -- GeoJSON Timelapse require track_geojson geometry point
        -- Add properties to the geojson for timelapse purpose
        PERFORM public.logbook_timelapse_geojson_fn(logbook_rec_start.id);
        ***/
        -- Update logbook mark for deletion
        UPDATE api.logbook
            SET notes = 'mark for deletion'
            WHERE id = logbook_rec_end.id;
        -- Update related stays mark for deletion
        UPDATE api.stays
            SET notes = 'mark for deletion'
            WHERE arrived = logbook_rec_start._to_time;
        -- Update related moorages mark for deletion
        -- We can't delete the stays and moorages as it might expand to other previous logs and stays
        --UPDATE api.moorages
        --    SET notes = 'mark for deletion'
        --    WHERE id = logbook_rec_start._to_moorage_id;

        -- Clean up, remove invalid logbook and stay, moorage entry
        DELETE FROM api.logbook WHERE id = logbook_rec_end.id;
        RAISE WARNING '-> merge_logbook_fn delete logbook id [%]', logbook_rec_end.id;
        DELETE FROM api.stays WHERE arrived = logbook_rec_start._to_time;
        RAISE WARNING '-> merge_logbook_fn delete stay arrived [%]', logbook_rec_start._to_time;
        -- We can't delete the stays and moorages as it might expand to other previous logs and stays
		-- Delete the moorage only if exactly one record exists with that id.
        DELETE FROM api.moorages
			WHERE id = logbook_rec_start._to_moorage_id
			  AND (
			    SELECT COUNT(*) 
			    FROM api.logbook
    			WHERE _from_moorage_id = logbook_rec_start._to_moorage_id
					OR _to_moorage_id = logbook_rec_start._to_moorage_id
			  ) = 1;
        RAISE WARNING '-> merge_logbook_fn delete moorage id [%]', logbook_rec_start._to_moorage_id;
    END;
$$;


--
-- Name: FUNCTION merge_logbook_fn(id_start integer, id_end integer); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.merge_logbook_fn(id_start integer, id_end integer) IS 'Merge 2 logbook by id, from the start of the lower log id and the end of the higher log id, update the calculate data as well (avg, geojson)';


--
-- Name: monitoring_history_fn(text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.monitoring_history_fn(time_interval text DEFAULT '24'::text, OUT history_metrics jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
    DECLARE
        bucket_interval interval := '5 minutes';
    BEGIN
        RAISE NOTICE '-> monitoring_history_fn';
        SELECT CASE time_interval
            WHEN '24' THEN '5 minutes'
            WHEN '48' THEN '2 hours'
            WHEN '72' THEN '4 hours'
            WHEN '168' THEN '7 hours'
            ELSE '5 minutes'
            END bucket INTO bucket_interval;
        RAISE NOTICE '-> monitoring_history_fn % %', time_interval, bucket_interval;
        WITH history_table AS (
            SELECT time_bucket(bucket_interval::INTERVAL, mt.time) AS time_bucket,
                avg(-- Water Temperature
                    COALESCE(
                        mt.metrics->'water'->>'temperature',
                        mt.metrics->>(md.configuration->>'waterTemperatureKey'),
                        mt.metrics->>'environment.water.temperature'
                    )::FLOAT) AS waterTemperature,
                avg(-- Inside Temperature
                    COALESCE(
                        mt.metrics->'temperature'->>'inside',
                        mt.metrics->>(md.configuration->>'insideTemperatureKey'),
                        mt.metrics->>'environment.inside.temperature'
                    )::FLOAT) AS insideTemperature,
                avg(-- Outside Temperature
                    COALESCE(
                        mt.metrics->'temperature'->>'outside',
                        mt.metrics->>(md.configuration->>'outsideTemperatureKey'),
                        mt.metrics->>'environment.outside.temperature'
                    )::FLOAT) AS outsideTemperature,
                avg(-- Wind Speed True
                    COALESCE(
                        mt.metrics->'wind'->>'speed',
                        mt.metrics->>(md.configuration->>'windSpeedKey'),
                        mt.metrics->>'environment.wind.speedTrue',
                        mt.metrics->>'environment.wind.speedApparent'
                    )::FLOAT) AS windSpeedOverGround,
                avg(-- Inside Humidity
                    COALESCE(
                        mt.metrics->'humidity'->>'inside',
                        mt.metrics->>(md.configuration->>'insideHumidityKey'),
                        mt.metrics->>'environment.inside.relativeHumidity',
                        mt.metrics->>'environment.inside.humidity'
                    )::FLOAT) AS insideHumidity,
                avg(-- Outside Humidity
                    COALESCE(
                        mt.metrics->'humidity'->>'outside',
                        mt.metrics->>(md.configuration->>'outsideHumidityKey'),
                        mt.metrics->>'environment.outside.relativeHumidity',
                        mt.metrics->>'environment.outside.humidity'
                    )::FLOAT) AS outsideHumidity,
                avg(-- Outside Pressure
                    COALESCE(
                        mt.metrics->'pressure'->>'outside',
                        mt.metrics->>(md.configuration->>'outsidePressureKey'),
                        mt.metrics->>'environment.outside.pressure'
                    )::FLOAT) AS outsidePressure,
                avg(--Inside Pressure
                    COALESCE(
                        mt.metrics->'pressure'->>'inside',
                        mt.metrics->>(md.configuration->>'insidePressureKey'),
                        mt.metrics->>'environment.inside.pressure'
                    )::FLOAT) AS insidePressure,
                avg(-- Battery Charge (State of Charge)
                    COALESCE(
                        mt.metrics->'battery'->>'charge',
                        mt.metrics->>(md.configuration->>'stateOfChargeKey'),
                        mt.metrics->>'electrical.batteries.House.capacity.stateOfCharge'
                    )::FLOAT) AS batteryCharge,
                avg(-- Battery Voltage
                    COALESCE(
                        mt.metrics->'battery'->>'voltage',
                        mt.metrics->>(md.configuration->>'voltageKey'),
                        mt.metrics->>'electrical.batteries.House.voltage'
                    )::FLOAT) AS batteryVoltage,
                avg(-- Water Depth
                    COALESCE(
                        mt.metrics->'water'->>'depth',
                        mt.metrics->>(md.configuration->>'depthKey'),
                        mt.metrics->>'environment.depth.belowTransducer'
                    )::FLOAT) AS depth
                FROM api.metrics mt
				JOIN api.metadata md ON md.vessel_id = mt.vessel_id
                WHERE mt.time > (NOW() AT TIME ZONE 'UTC' - INTERVAL '1 hours' * time_interval::NUMERIC)
                GROUP BY time_bucket
                ORDER BY time_bucket asc
        )
        SELECT jsonb_agg(history_table) INTO history_metrics FROM history_table;
    END
$$;


--
-- Name: FUNCTION monitoring_history_fn(time_interval text, OUT history_metrics jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.monitoring_history_fn(time_interval text, OUT history_metrics jsonb) IS 'Export metrics from a time period 24h, 48h, 72h, 7d';


--
-- Name: pushover_fn(text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.pushover_fn(token text, pushover_user_key text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION pushover_fn(token text, pushover_user_key text); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.pushover_fn(token text, pushover_user_key text) IS 'Confirm Pushover Subscription and store pushover_user_key into user preferences if provide a valid OTP token';


--
-- Name: pushover_subscribe_link_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.pushover_subscribe_link_fn(OUT pushover_link json) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION pushover_subscribe_link_fn(OUT pushover_link json); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.pushover_subscribe_link_fn(OUT pushover_link json) IS 'Generate Pushover subscription link';


--
-- Name: recover(text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.recover(email text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
        -- Enable email_notifications
        PERFORM api.update_user_preferences_fn('{email_notifications}'::TEXT, True::TEXT);
        -- Send email/notifications
        user_settings := '{"email": "' || _email || '", "reset_qs": "' || _reset_qs || '"}';
        PERFORM send_notification_fn('email_reset'::TEXT, user_settings::JSONB);
        RETURN TRUE;
    END;
$$;


--
-- Name: FUNCTION recover(email text); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.recover(email text) IS 'Send recover password email to reset password';


--
-- Name: register_vessel(text, text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.register_vessel(vessel_email text, vessel_mmsi text, vessel_name text) RETURNS auth.jwt_token
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  result auth.jwt_token;
  app_jwt_secret text;
  vessel_rec record;
  _vessel_id text;
begin
  IF vessel_email IS NULL OR vessel_email = ''
	  OR vessel_name IS NULL OR vessel_name = '' THEN
    RAISE EXCEPTION 'Invalid input'
        USING HINT = 'Check your parameter';
  END IF;
  IF public.isnumeric(vessel_mmsi) IS False THEN
    vessel_mmsi = NULL;
  END IF;
  -- check vessel exist
  SELECT * INTO vessel_rec
    FROM auth.vessels vessel
    WHERE vessel.owner_email = vessel_email;
  IF vessel_rec IS NULL THEN
      RAISE WARNING 'Register new vessel name:[%] mmsi:[%] for [%]', vessel_name, vessel_mmsi, vessel_email;
      INSERT INTO auth.vessels (owner_email, mmsi, name, role)
        VALUES (vessel_email, vessel_mmsi::NUMERIC, vessel_name, 'vessel_role') RETURNING vessel_id INTO _vessel_id;
    vessel_rec.role := 'vessel_role';
    vessel_rec.owner_email = vessel_email;
    vessel_rec.vessel_id = _vessel_id;
  END IF;

  -- Get app_jwt_secret
  SELECT value INTO app_jwt_secret
    FROM app_settings
    WHERE name = 'app.jwt_secret';

  select jwt.sign(
      row_to_json(r)::json, app_jwt_secret
    ) as token
    from (
      select vessel_rec.role as role,
      vessel_rec.owner_email as email, -- TODO replace with user_id
    --  vessel_rec.user_id as uid
      vessel_rec.vessel_id as vid
    ) r
    into result;
  return result;
 
end;
$$;


--
-- Name: reset(text, text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.reset(pass text, token text, uuid text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
    DECLARE
        _email TEXT := NULL;
        _pass TEXT := pass;
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
                SET pass = _pass
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
$$;


--
-- Name: FUNCTION reset(pass text, token text, uuid text); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.reset(pass text, token text, uuid text) IS 'Reset user password base on otp code and user_id send by email from api.recover';


--
-- Name: settings_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.settings_fn(OUT settings json) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION settings_fn(OUT settings json); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.settings_fn(OUT settings json) IS 'Expose user settings to API';


--
-- Name: signup(text, text, text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.signup(email text, pass text, firstname text, lastname text) RETURNS auth.jwt_token
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
declare
  _role name;
begin
  IF email IS NULL OR email = ''
	 OR pass IS NULL OR pass = '' THEN
    RAISE EXCEPTION 'Invalid input'
        USING HINT = 'Check your parameter';
  END IF;
  -- check email and password
  select auth.user_role(email, pass) into _role;
  if _role is null then
	  RAISE WARNING 'Register new account email:[%]', email;
    -- TODO replace preferences default into table rather than trigger
	  INSERT INTO auth.accounts ( email, pass, first, last, role, preferences)
	    VALUES (email, pass, firstname, lastname, 'user_role', '{"email_notifications":true}');
  end if;
  return ( api.login(email, pass) );
end;
$$;


--
-- Name: stats_fn(text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.stats_fn(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT stats jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
    DECLARE
        _start_date TIMESTAMPTZ DEFAULT '1970-01-01';
        _end_date TIMESTAMPTZ DEFAULT NOW();
        stats_logs JSONB;
        stats_moorages JSONB;
        stats_logs_topby JSONB;
        stats_moorages_topby JSONB;
    BEGIN
        IF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            RAISE WARNING '--> stats_fn, filter result stats by date [%]', start_date;
            _start_date := start_date::TIMESTAMPTZ;
            _end_date := end_date::TIMESTAMPTZ;
        END IF;
        RAISE NOTICE '--> stats_fn, _start_date [%], _end_date [%]', _start_date, _end_date;
        -- Get global logs statistics
        SELECT api.stats_logs_fn(_start_date::TEXT, _end_date::TEXT) INTO stats_logs;
        -- Get global stays/moorages statistics
        SELECT api.stats_stays_fn(_start_date::TEXT, _end_date::TEXT) INTO stats_moorages;
        -- Get Top 5 trips statistics
        WITH
            logs_view AS (
                SELECT id,avg_speed,max_speed,max_wind_speed,distance,duration
                    FROM api.logbook l
                    WHERE _from_time >= _start_date::TIMESTAMPTZ
                        AND _to_time <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
						AND trip IS NOT NULL
            ),
            logs_top_avg_speed AS (
                SELECT id,avg_speed FROM logs_view
                GROUP BY id,avg_speed
                ORDER BY avg_speed DESC
                LIMIT 5),
            logs_top_speed AS (
                SELECT id,max_speed FROM logs_view
                WHERE max_speed IS NOT NULL
                GROUP BY id,max_speed
                ORDER BY max_speed DESC
                LIMIT 5),
            logs_top_wind_speed AS (
                SELECT id,max_wind_speed FROM logs_view
				WHERE max_wind_speed IS NOT NULL
                GROUP BY id,max_wind_speed
                ORDER BY max_wind_speed DESC
                LIMIT 5),
            logs_top_distance AS (
                SELECT id FROM logs_view
                GROUP BY id,distance
                ORDER BY distance DESC
                LIMIT 5),
            logs_top_duration AS (
                SELECT id FROM logs_view
                GROUP BY id,duration
                ORDER BY duration DESC
                LIMIT 5)
		-- Stats Top Logs
        SELECT jsonb_build_object(
            'stats_logs', stats_logs,
            'stats_moorages', stats_moorages,
            'logs_top_speed', (SELECT jsonb_agg(logs_top_speed.*) FROM logs_top_speed),
            'logs_top_avg_speed', (SELECT jsonb_agg(logs_top_avg_speed.*) FROM logs_top_avg_speed),
            'logs_top_wind_speed', (SELECT jsonb_agg(logs_top_wind_speed.*) FROM logs_top_wind_speed),
            'logs_top_distance', (SELECT jsonb_agg(logs_top_distance.id) FROM logs_top_distance),
            'logs_top_duration', (SELECT jsonb_agg(logs_top_duration.id) FROM logs_top_duration)
         ) INTO stats;
		-- Stats top 5 moorages statistics
        WITH
            stays AS (
                SELECT distinct(moorage_id) as moorage_id, sum(duration) as duration, count(id) as reference_count
                    FROM api.stays s
                    WHERE s.arrived >= _start_date::TIMESTAMPTZ
                        AND s.departed <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
                    group by s.moorage_id
                    order by s.moorage_id
            ),
            moorages AS (
                SELECT m.id, m.home_flag, mv.stays_count, mv.stays_sum_duration, m.stay_code, m.country, s.duration as dur, s.reference_count as ref_count
                    FROM api.moorages m, stays s, api.moorage_view mv
                    WHERE s.moorage_id = m.id
                        AND mv.id = m.id
                    order by s.moorage_id
            ),
            moorages_top_arrivals AS (
                SELECT id,ref_count FROM moorages
                GROUP BY id,ref_count
                ORDER BY ref_count DESC
                LIMIT 5),
            moorages_top_duration AS (
                SELECT id,dur FROM moorages
                GROUP BY id,dur
                ORDER BY dur DESC
                LIMIT 5),
            moorages_countries AS (
                SELECT DISTINCT(country) FROM moorages
                WHERE country IS NOT NULL AND country <> 'unknown'
                GROUP BY country
                ORDER BY country DESC
                LIMIT 5)
		SELECT stats || jsonb_build_object(
		    'moorages_top_arrivals', (SELECT jsonb_agg(moorages_top_arrivals) FROM moorages_top_arrivals),
		    'moorages_top_duration', (SELECT jsonb_agg(moorages_top_duration) FROM moorages_top_duration),
		    'moorages_top_countries', (SELECT jsonb_agg(moorages_countries.country) FROM moorages_countries)
		 ) INTO stats;
    END;
$$;


--
-- Name: FUNCTION stats_fn(start_date text, end_date text, OUT stats jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.stats_fn(start_date text, end_date text, OUT stats jsonb) IS 'Statistic by date for Logs and Moorages and Stays';


--
-- Name: stats_logs_fn(text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.stats_logs_fn(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT stats jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
    DECLARE
        _start_date TIMESTAMPTZ DEFAULT '1970-01-01';
        _end_date TIMESTAMPTZ DEFAULT NOW();
    BEGIN
        IF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            RAISE WARNING '--> stats_logs_fn, filter result stats by date [%]', start_date;
            _start_date := start_date::TIMESTAMPTZ;
            _end_date := end_date::TIMESTAMPTZ;
        END IF;
        RAISE NOTICE '--> stats_logs_fn, _start_date [%], _end_date [%]', _start_date, _end_date;
        WITH
            meta AS (
                SELECT m.name FROM api.metadata m ),
            logs_view AS (
                SELECT *
                    FROM api.logbook l
                    WHERE _from_time >= _start_date::TIMESTAMPTZ
                        AND _to_time <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
						AND trip IS NOT NULL
                ),
            first_date AS (
                SELECT _from_time as first_date from logs_view ORDER BY first_date ASC LIMIT 1
            ),
            last_date AS (
                SELECT _to_time as last_date from logs_view ORDER BY _to_time DESC LIMIT 1
            ),
            max_speed_id AS (
                SELECT id FROM logs_view WHERE max_speed = (SELECT max(max_speed) FROM logs_view) ),
            max_wind_speed_id AS (
                SELECT id FROM logs_view WHERE max_wind_speed = (SELECT max(max_wind_speed) FROM logs_view)),
            max_distance_id AS (
                SELECT id FROM logs_view WHERE distance = (SELECT max(distance) FROM logs_view)),
            max_duration_id AS (
                SELECT id FROM logs_view WHERE duration = (SELECT max(duration) FROM logs_view)),
            logs_stats AS (
                SELECT
                    count(*) AS count,
                    max(max_speed) AS max_speed,
                    max(max_wind_speed) AS max_wind_speed,
                    max(distance) AS max_distance,
                    sum(distance) AS sum_distance,
                    max(duration) AS max_duration,
                    sum(duration) AS sum_duration
                FROM logs_view l )
              --select * from logbook;
        -- Return a JSON
        SELECT jsonb_build_object(
            'name', meta.name,
            'first_date', first_date.first_date,
            'last_date', last_date.last_date,
            'max_speed_id', max_speed_id.id,
            'max_wind_speed_id', max_wind_speed_id.id,
            'max_duration_id', max_duration_id.id,
            'max_distance_id', max_distance_id.id)::jsonb || to_jsonb(logs_stats.*)::jsonb INTO stats
            FROM max_speed_id, max_wind_speed_id, max_distance_id, max_duration_id,
                logs_stats, meta, logs_view, first_date, last_date;
    END;
$$;


--
-- Name: FUNCTION stats_logs_fn(start_date text, end_date text, OUT stats jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.stats_logs_fn(start_date text, end_date text, OUT stats jsonb) IS 'Logs stats by date';


--
-- Name: stats_stays_fn(text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.stats_stays_fn(start_date text DEFAULT NULL::text, end_date text DEFAULT NULL::text, OUT stats json) RETURNS json
    LANGUAGE plpgsql
    AS $$
    DECLARE
        _start_date TIMESTAMPTZ DEFAULT '1970-01-01';
        _end_date TIMESTAMPTZ DEFAULT NOW();
    BEGIN
        IF start_date IS NOT NULL AND public.isdate(start_date::text) AND public.isdate(end_date::text) THEN
            RAISE NOTICE '--> stats_stays_fn, custom filter result stats by date [%]', start_date;
            _start_date := start_date::TIMESTAMPTZ;
            _end_date := end_date::TIMESTAMPTZ;
        END IF;
        RAISE NOTICE '--> stats_stays_fn, _start_date [%], _end_date [%]', _start_date, _end_date;
        WITH
            stays AS (
                SELECT distinct(moorage_id) as moorage_id, sum(duration) as duration, count(id) as reference_count
                    FROM api.stays s
                    WHERE arrived >= _start_date::TIMESTAMPTZ
                        AND departed <= _end_date::TIMESTAMPTZ + interval '23 hours 59 minutes'
                    group by moorage_id
                    order by moorage_id
            ),
            moorages AS (
                SELECT m.id, m.home_flag, mv.stays_count, mv.stays_sum_duration, m.stay_code, m.country, s.duration, s.reference_count
                    FROM api.moorages m, stays s, api.moorage_view mv
                    WHERE s.moorage_id = m.id
                    and mv.id = m.id
                    order by moorage_id
            ),
            home_ports AS (
                select count(*) as home_ports from api.moorages m where home_flag is true
            ),
            unique_moorages AS (
                select count(*) as unique_moorages from api.moorages m
            ),
            time_at_home_ports AS (
                select sum(m.stays_sum_duration) as time_at_home_ports from api.moorage_view m where home is true
            ),
            sum_stay_duration AS (
                select sum(m.stays_sum_duration) as sum_stay_duration from api.moorage_view m where home is false
            ),
            time_spent_away_arr AS (
                select m.default_stay_id as stay_code,sum(m.stays_sum_duration) as stay_duration from api.moorage_view m where home is false group by m.default_stay_id order by m.default_stay_id
            ),
            time_spent_arr as (
                select jsonb_agg(t.*) as time_spent_away_arr from time_spent_away_arr t
            ),
            time_spent_away AS (
                select sum(m.stays_sum_duration) as time_spent_away from api.moorage_view m where home is false
            ),
            time_spent as (
                select jsonb_agg(t.*) as time_spent_away from time_spent_away t
            )
        -- Return a JSON
        SELECT jsonb_build_object(
            'home_ports', home_ports.home_ports,
            'unique_moorages', unique_moorages.unique_moorages,
            'time_at_home_ports', time_at_home_ports.time_at_home_ports,
            'time_spent_away', time_spent_away.time_spent_away,
            'time_spent_away_arr', time_spent_arr.time_spent_away_arr) INTO stats
            FROM home_ports, unique_moorages,
                        time_at_home_ports, sum_stay_duration, time_spent_away, time_spent_arr;
    END;
$$;


--
-- Name: FUNCTION stats_stays_fn(start_date text, end_date text, OUT stats json); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.stats_stays_fn(start_date text, end_date text, OUT stats json) IS 'Stays/Moorages stats by date';


--
-- Name: status_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.status_fn(OUT status jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
    DECLARE
        in_route BOOLEAN := False;
    BEGIN
        -- When stays or log is active, moorage_id is NULL..
        RAISE NOTICE '-> status_fn';
        SELECT EXISTS ( SELECT id
                        FROM api.logbook l
                        WHERE active IS True
                        LIMIT 1
                    ) INTO in_route;
        IF in_route IS True THEN
            -- In route from <logbook.from_name> departed at <>
            SELECT jsonb_build_object('status', 'In route', 'location', 'm.name', 'departed', l._from_time) INTO status
                FROM api.logbook l, api.stays_at sa, api.moorages m
                WHERE l._from_moorage_id = m.id AND l.active IS True;
        ELSE
            -- At <Stat_at.Desc> in <Moorage.name> departed at <>
            SELECT jsonb_build_object('status', sa.description, 'location', m.name, 'arrived', s.arrived) INTO status
                FROM api.stays s, api.stays_at sa, api.moorages m
                WHERE s.stay_code = sa.stay_code AND s.moorage_id = m.id AND s.active IS True;
        END IF;
    END
$$;


--
-- Name: FUNCTION status_fn(OUT status jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.status_fn(OUT status jsonb) IS 'generate vessel status';


--
-- Name: telegram(bigint, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.telegram(user_id bigint, email text DEFAULT NULL::text) RETURNS auth.jwt_token
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION telegram(user_id bigint, email text); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.telegram(user_id bigint, email text) IS 'Generate a JWT user_role token based on chat_id from telegram';


--
-- Name: telegram_fn(text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.telegram_fn(token text, telegram_obj text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION telegram_fn(token text, telegram_obj text); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.telegram_fn(token text, telegram_obj text) IS 'Confirm telegram user and store telegram chat details into user preferences if provide a valid OTP token';


--
-- Name: telegram_otp_fn(text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.telegram_otp_fn(email text, OUT otp_code text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION telegram_otp_fn(email text, OUT otp_code text); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.telegram_otp_fn(email text, OUT otp_code text) IS 'Telegram otp generation';


--
-- Name: update_logbook_observations_fn(integer, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.update_logbook_observations_fn(_id integer, observations text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    -- Merge existing observations with the new observations objects
    RAISE NOTICE '-> update_logbook_userdata_fn id:[%] observations:[%]', _id, observations;
    -- { 'observations': { 'seaState': -1, 'cloudCoverage': -1, 'visibility': -1 } }
    UPDATE api.logbook SET user_data = public.jsonb_recursive_merge(user_data, observations::jsonb) WHERE id = _id;
    IF FOUND IS True THEN
        RETURN True;
    END IF;
    RETURN False;
END;
$$;


--
-- Name: FUNCTION update_logbook_observations_fn(_id integer, observations text); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.update_logbook_observations_fn(_id integer, observations text) IS 'Update/Add logbook observations jsonb key pair value';


--
-- Name: update_metadata_userdata_fn(text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.update_metadata_userdata_fn(userdata text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    -- Merge existing user_data with the new user_data objects
    RAISE NOTICE '-> update_metadata_userdata_fn userdata:[%]', userdata;
    -- { 'make_model': 'my super yacht' }
    UPDATE api.metadata SET user_data = public.jsonb_recursive_merge(user_data, userdata::jsonb);
    IF FOUND IS True THEN
        RETURN True;
    END IF;
    RETURN False;
END;
$$;


--
-- Name: FUNCTION update_metadata_userdata_fn(userdata text); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.update_metadata_userdata_fn(userdata text) IS 'Update/Add metadata user_data jsonb key pair value';


--
-- Name: update_trip_notes_fn(integer, public.ttext); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.update_trip_notes_fn(_id integer, update_string public.ttext) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE api.logbook l
    SET trip_notes = update(l.trip_notes, update_string)
    WHERE id = _id;
END;
$$;


--
-- Name: FUNCTION update_trip_notes_fn(_id integer, update_string public.ttext); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.update_trip_notes_fn(_id integer, update_string public.ttext) IS 'Update trip note at a specific time for a temporal sequence';


--
-- Name: update_user_preferences_fn(text, text); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.update_user_preferences_fn(key text, value text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION update_user_preferences_fn(key text, value text); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.update_user_preferences_fn(key text, value text) IS 'Update user preferences jsonb key pair value';


--
-- Name: versions_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.versions_fn() RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
						   'mobilitydb', (SELECT extversion as mobilitydb FROM pg_extension WHERE extname='mobilitydb'),
                           'timescaledb', (SELECT extversion as timescaledb FROM pg_extension WHERE extname='timescaledb'),
                           'postgis', (SELECT extversion as postgis FROM pg_extension WHERE extname='postgis'),
                           'postgrest', (SELECT rtrim(substring(application_name from 'PostgREST [0-9.]+')) as postgrest FROM pg_stat_activity WHERE application_name ilike '%postgrest%' LIMIT 1));
    END;
$$;


--
-- Name: FUNCTION versions_fn(); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.versions_fn() IS 'Expose as a function, app and system version to API';


--
-- Name: vessel_details_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.vessel_details_fn() RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: FUNCTION vessel_details_fn(); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.vessel_details_fn() IS 'Return vessel details such as metadata (length,beam,height), ais type and country name and country iso3166-alpha-2';


--
-- Name: vessel_extended_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.vessel_extended_fn() RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id text := current_setting('vessel.id', false);
    result jsonb;
BEGIN
    SELECT jsonb_build_object(
          'make_model', m.user_data->'make_model',
          'has_polar', m.user_data->'polar' IS NOT NULL,
          'has_images',
            CASE 
              WHEN jsonb_array_length(m.user_data->'images') > 0 THEN true
              ELSE false
            END,
          'image_url', m.user_data->'images'->0->>'url',
          'image_updated_at', m.user_data->'images'->0->>'updated_at',
          'images', m.user_data->'images'
      )
      INTO result
      FROM api.metadata m
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
$$;


--
-- Name: FUNCTION vessel_extended_fn(); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.vessel_extended_fn() IS 'Return vessel details from metadata_ext (polar csv,image url, make model)';


--
-- Name: vessel_fn(); Type: FUNCTION; Schema: api; Owner: -
--

CREATE FUNCTION api.vessel_fn(OUT vessel jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION vessel_fn(OUT vessel jsonb); Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON FUNCTION api.vessel_fn(OUT vessel jsonb) IS 'Expose vessel details to API';


--
-- Name: check_role_exists(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.check_role_exists() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if not exists (select 1 from pg_roles as r where r.rolname = new.role) then
    raise foreign_key_violation using message =
      'unknown database role: ' || new.role;
    return null;
  end if;
  return new;
end
$$;


--
-- Name: encrypt_pass(); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.encrypt_pass() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  if tg_op = 'INSERT' or new.pass <> old.pass then
    new.pass = crypt(new.pass, gen_salt('bf'));
  end if;
  return new;
end
$$;


--
-- Name: FUNCTION encrypt_pass(); Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON FUNCTION auth.encrypt_pass() IS 'encrypt user pass on insert or update';


--
-- Name: telegram_session_exists_fn(bigint); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.telegram_session_exists_fn(user_id bigint) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION telegram_session_exists_fn(user_id bigint); Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON FUNCTION auth.telegram_session_exists_fn(user_id bigint) IS 'Check if session/user exist based on user_id';


--
-- Name: telegram_user_exists_fn(text, bigint); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.telegram_user_exists_fn(email text, user_id bigint) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION telegram_user_exists_fn(email text, user_id bigint); Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON FUNCTION auth.telegram_user_exists_fn(email text, user_id bigint) IS 'Check if user exist based on email and user_id';


--
-- Name: user_role(text, text); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.user_role(email text, pass text) RETURNS name
    LANGUAGE plpgsql
    AS $$
begin
  return (
  select role from auth.accounts
   where accounts.email = user_role.email
     and user_role.pass is NOT NULL
     and accounts.pass = crypt(user_role.pass, accounts.pass)
  );
end;
$$;


--
-- Name: verify_otp_fn(text); Type: FUNCTION; Schema: auth; Owner: -
--

CREATE FUNCTION auth.verify_otp_fn(token text) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION verify_otp_fn(token text); Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON FUNCTION auth.verify_otp_fn(token text) IS 'Verify OTP';


--
-- Name: algorithm_sign(text, text, text); Type: FUNCTION; Schema: jwt; Owner: -
--

CREATE FUNCTION jwt.algorithm_sign(signables text, secret text, algorithm text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
WITH
  alg AS (
    SELECT CASE
      WHEN algorithm = 'HS256' THEN 'sha256'
      WHEN algorithm = 'HS384' THEN 'sha384'
      WHEN algorithm = 'HS512' THEN 'sha512'
      ELSE '' END AS id)  -- hmac throws error
SELECT jwt.url_encode(public.hmac(signables, secret, alg.id)) FROM alg;
$$;


--
-- Name: sign(json, text, text); Type: FUNCTION; Schema: jwt; Owner: -
--

CREATE FUNCTION jwt.sign(payload json, secret text, algorithm text DEFAULT 'HS256'::text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
WITH
  header AS (
    SELECT jwt.url_encode(convert_to('{"alg":"' || algorithm || '","typ":"JWT"}', 'utf8')) AS data
    ),
  payload AS (
    SELECT jwt.url_encode(convert_to(payload::text, 'utf8')) AS data
    ),
  signables AS (
    SELECT header.data || '.' || payload.data AS data FROM header, payload
    )
SELECT
    signables.data || '.' ||
    jwt.algorithm_sign(signables.data, secret, algorithm) FROM signables;
$$;


--
-- Name: try_cast_double(text); Type: FUNCTION; Schema: jwt; Owner: -
--

CREATE FUNCTION jwt.try_cast_double(inp text) RETURNS double precision
    LANGUAGE plpgsql IMMUTABLE
    AS $$
  BEGIN
    BEGIN
      RETURN inp::double precision;
    EXCEPTION
      WHEN OTHERS THEN RETURN NULL;
    END;
  END;
$$;


--
-- Name: url_decode(text); Type: FUNCTION; Schema: jwt; Owner: -
--

CREATE FUNCTION jwt.url_decode(data text) RETURNS bytea
    LANGUAGE sql IMMUTABLE
    AS $$
WITH t AS (SELECT translate(data, '-_', '+/') AS trans),
     rem AS (SELECT length(t.trans) % 4 AS remainder FROM t) -- compute padding size
    SELECT decode(
        t.trans ||
        CASE WHEN rem.remainder > 0
           THEN repeat('=', (4 - rem.remainder))
           ELSE '' END,
    'base64') FROM t, rem;
$$;


--
-- Name: url_encode(bytea); Type: FUNCTION; Schema: jwt; Owner: -
--

CREATE FUNCTION jwt.url_encode(data bytea) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
    SELECT translate(encode(data, 'base64'), E'+/=\n', '-_');
$$;


--
-- Name: verify(text, text, text); Type: FUNCTION; Schema: jwt; Owner: -
--

CREATE FUNCTION jwt.verify(token text, secret text, algorithm text DEFAULT 'HS256'::text) RETURNS TABLE(header json, payload json, valid boolean)
    LANGUAGE sql IMMUTABLE
    AS $$
  SELECT
    jwt.header AS header,
    jwt.payload AS payload,
    jwt.signature_ok AND tstzrange(
      to_timestamp(jwt.try_cast_double(jwt.payload->>'nbf')),
      to_timestamp(jwt.try_cast_double(jwt.payload->>'exp'))
    ) @> CURRENT_TIMESTAMP AS valid
  FROM (
    SELECT
      convert_from(jwt.url_decode(r[1]), 'utf8')::json AS header,
      convert_from(jwt.url_decode(r[2]), 'utf8')::json AS payload,
      r[3] = jwt.algorithm_sign(r[1] || '.' || r[2], secret, algorithm) AS signature_ok
    FROM regexp_split_to_array(token, '\.') r
  ) jwt
$$;


--
-- Name: autodiscovery_config_fn(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.autodiscovery_config_fn(input_json jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: FUNCTION autodiscovery_config_fn(input_json jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.autodiscovery_config_fn(input_json jsonb) IS 'Clean the JSONB column by removing keys that are not present in the latest metrics row.';


--
-- Name: badges_geom_fn(integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.badges_geom_fn(logbook_id integer, logbook_time text) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        _badges jsonb;
        _exist BOOLEAN := false;
        badge text;
        marine_rec record;
        user_settings jsonb;
        badge_tmp text;
    begin
	    --RAISE NOTICE '--> public.badges_geom_fn user.email [%], vessel.id [%]', current_setting('user.email', false), current_setting('vessel.id', false);
        -- Tropical & Alaska zone manually add into ne_10m_geography_marine_polys
        -- Check if each geographic marine zone exist as a badge
	    FOR marine_rec IN
	        WITH log AS (
		            SELECT trajectory(l.trip)::geometry AS track_geom FROM api.logbook l
                        WHERE l.id = logbook_id AND vessel_id = current_setting('vessel.id', false)
		            )
	        SELECT name from log, public.ne_10m_geography_marine_polys
                WHERE ST_Intersects(
		                ST_SetSRID(geom,4326),
                        log.track_geom
		            )
	    LOOP
            -- If not generate and insert the new badge
            --RAISE WARNING 'geography_marine [%]', marine_rec.name;
            SELECT jsonb_extract_path(a.preferences, 'badges', marine_rec.name) IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            --RAISE WARNING 'geography_marine [%]', _exist;
            if _exist is false then
                -- Create badge
                badge := '{"' || marine_rec.name || '": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) INTO badge;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                --RAISE WARNING '--> badges_geom_fn [%]', badge;
                -- Gather user settings
                badge_tmp := '{"badge": "' || marine_rec.name || '"}';
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || badge_tmp::JSONB INTO user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
	    END LOOP;
    END;
$$;


--
-- Name: FUNCTION badges_geom_fn(logbook_id integer, logbook_time text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.badges_geom_fn(logbook_id integer, logbook_time text) IS 'check geometry logbook for new badges, eg: Tropic, Alaska, Geographic zone';


--
-- Name: badges_logbook_fn(integer, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.badges_logbook_fn(logbook_id integer, logbook_time text) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        _badges jsonb;
        _exist BOOLEAN := null;
        total integer;
        max_wind_speed integer;
        distance integer;
        badge text;
        user_settings jsonb;
    BEGIN

        -- Helmsman = first log entry
        SELECT (preferences->'badges'->'Helmsman') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false THEN
            -- is first logbook?
            select count(*) into total from api.logbook l where vessel_id = current_setting('vessel.id', false);
            if total >= 1 then
                -- Add badge
                badge := '{"Helmsman": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- Update badges
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Helmsman"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

        -- Wake Maker = windspeeds above 15kts
        SELECT (preferences->'badges'->'Wake Maker') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        --RAISE WARNING '-> Wake Maker %', _exist;
        if _exist is false then
            -- is 15 knot+ logbook?
            select l.max_wind_speed into max_wind_speed from api.logbook l where l.id = logbook_id AND l.max_wind_speed >= 15 and vessel_id = current_setting('vessel.id', false);
            --RAISE WARNING '-> Wake Maker max_wind_speed %', max_wind_speed;
           if max_wind_speed >= 15 then
                -- Create badge
                badge := '{"Wake Maker": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
                --RAISE WARNING '-> Wake Maker max_wind_speed badge %', badge;
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                --RAISE WARNING '-> Wake Maker max_wind_speed badge % %', badge, _badges;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Wake Maker"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

        -- Stormtrooper = windspeeds above 30kts
        SELECT (preferences->'badges'->'Stormtrooper') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
            --RAISE WARNING '-> Stormtrooper %', _exist;
            select l.max_wind_speed into max_wind_speed from api.logbook l where l.id = logbook_id AND l.max_wind_speed >= 30 and vessel_id = current_setting('vessel.id', false);
            --RAISE WARNING '-> Stormtrooper max_wind_speed %', max_wind_speed;
            if max_wind_speed >= 30 then
                -- Create badge
                badge := '{"Stormtrooper": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
                --RAISE WARNING '-> Stormtrooper max_wind_speed badge %', badge;
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- RAISE WARNING '-> Wake Maker max_wind_speed badge % %', badge, _badges;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Stormtrooper"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

        -- Navigator Award = one logbook with distance over 100NM
        SELECT (preferences->'badges'->'Navigator Award') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
            select l.distance into distance from api.logbook l where l.id = logbook_id AND l.distance >= 100 and vessel_id = current_setting('vessel.id', false);
            if distance >= 100 then
                -- Create badge
                badge := '{"Navigator Award": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Navigator Award"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

        -- Captain Award = total logbook distance over 1000NM
        SELECT (preferences->'badges'->'Captain Award') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
            select sum(l.distance) into distance from api.logbook l where vessel_id = current_setting('vessel.id', false);
            if distance >= 1000 then
                -- Create badge
                badge := '{"Captain Award": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Captain Award"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

    END;
$$;


--
-- Name: FUNCTION badges_logbook_fn(logbook_id integer, logbook_time text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.badges_logbook_fn(logbook_id integer, logbook_time text) IS 'check for new badges, eg: Helmsman, Wake Maker, Stormtrooper';


--
-- Name: badges_moorages_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.badges_moorages_fn() RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        _badges jsonb;
        _exist BOOLEAN := false;
        duration integer;
        badge text;
        user_settings jsonb;
    BEGIN
        -- Check and set environment
        user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
        PERFORM set_config('user.email', user_settings->>'email'::TEXT, false);
        -- Get moorages with total duration
        CREATE TEMP TABLE badges_moorages_tbl AS
        SELECT 
            m.id,
            m.home_flag,
            sa.stay_code AS default_stay_id,
            EXTRACT(day FROM (COALESCE(SUM(distinct s.duration), INTERVAL 'PT0S'))) AS total_duration_days,
            COALESCE(SUM(distinct s.duration), INTERVAL 'PT0S') AS total_duration -- Summing the stay durations
        FROM 
            api.moorages m
        JOIN
            api.stays_at sa 
            ON m.stay_code = sa.stay_code
        LEFT JOIN
            api.stays s 
            ON m.id = s.moorage_id
            AND s.active = False -- exclude active stays
            AND s.vessel_id = current_setting('vessel.id', false)
        WHERE 
            --m.stay_duration <> 'PT0S'
            m.geog IS NOT NULL 
            AND m.stay_code = sa.stay_code
            AND m.vessel_id = current_setting('vessel.id', false)
        GROUP BY 
            m.id, sa.stay_code
        ORDER BY 
            total_duration_days DESC;

        -- Explorer = 10 days away from home port
        SELECT (preferences->'badges'->'Explorer') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
            --select sum(m.stay_duration) from api.moorages m where home_flag is false;
            --SELECT extract(day from (select sum(m.stay_duration) INTO duration FROM api.moorages m WHERE home_flag IS false AND vessel_id = current_setting('vessel.id', false) ));
            SELECT total_duration_days INTO duration FROM badges_moorages_tbl WHERE home_flag IS FALSE;
            if duration >= 10 then
                -- Create badge
                badge := '{"Explorer": {"date":"' || NOW()::timestamp || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Explorer"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

        -- Mooring Pro = 10 nights on buoy!
        SELECT (preferences->'badges'->'Mooring Pro') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
            -- select sum(m.stay_duration) from api.moorages m where stay_code = 3;
            --SELECT extract(day from (select sum(m.stay_duration) INTO duration FROM api.moorages m WHERE stay_code = 3 AND vessel_id = current_setting('vessel.id', false) ));
            SELECT total_duration_days INTO duration FROM badges_moorages_tbl WHERE default_stay_id = 3;
            if duration >= 10 then
                -- Create badge
                badge := '{"Mooring Pro": {"date":"' || NOW()::timestamp || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Mooring Pro"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

        -- Anchormaster = 25 days on anchor
        SELECT (preferences->'badges'->'Anchormaster') IS NOT NULL INTO _exist FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
        if _exist is false then
            -- select sum(m.stay_duration) from api.moorages m where stay_code = 2;
            -- SELECT extract(day from (select sum(m.stay_duration) INTO duration FROM api.moorages m WHERE stay_code = 2 AND vessel_id = current_setting('vessel.id', false) ));
            SELECT total_duration_days INTO duration FROM badges_moorages_tbl WHERE default_stay_id = 2;
            if duration >= 25 then
                -- Create badge
                badge := '{"Anchormaster": {"date":"' || NOW()::timestamp || '"}}';
                -- Get existing badges
                SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
                -- Merge badges
                SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) into badge;
                -- Update badges for user
                PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
                -- Gather user settings
                user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
                SELECT user_settings::JSONB || '{"badge": "Anchormaster"}'::JSONB into user_settings;
                -- Send notification
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            end if;
        end if;

    -- Drop the temporary table
    DROP TABLE IF EXISTS badges_moorages_tbl;

    END;
$$;


--
-- Name: FUNCTION badges_moorages_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.badges_moorages_fn() IS 'check moorages for new badges, eg: Explorer, Mooring Pro, Anchormaster';


--
-- Name: check_jwt(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_jwt() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
-- Prevent unregister user or unregister vessel access
-- Allow anonymous access
DECLARE
  _role name := NULL;
  _email text := NULL;
  anonymous_rec record;
  _path name := NULL;
  _vid text := NULL;
  _vname text := NULL;
  boat TEXT := NULL;
  _pid INTEGER := 0; -- public_id
  _pvessel TEXT := NULL; -- public_type
  _ptype TEXT := NULL; -- public_type
  _ppath BOOLEAN := False; -- public_path
  _pvalid BOOLEAN := False; -- public_valid
  _pheader text := NULL; -- public_header
  valid_public_type BOOLEAN := False;
  account_rec record;
  vessel_rec record;
BEGIN
  -- RESET settings to avoid sql shared session cache
  -- Valid for every new HTTP request
  PERFORM set_config('vessel.id', NULL, true);
  PERFORM set_config('vessel.name', NULL, true);
  PERFORM set_config('user.id', NULL, true);
  PERFORM set_config('user.email', NULL, true);
  -- Extract email and role from jwt token
  --RAISE WARNING 'check_jwt jwt %', current_setting('request.jwt.claims', true);
  SELECT current_setting('request.jwt.claims', true)::json->>'email' INTO _email;
  PERFORM set_config('user.email', _email, true);
  SELECT current_setting('request.jwt.claims', true)::json->>'role' INTO _role;
  --RAISE WARNING 'jwt email %', current_setting('request.jwt.claims', true)::json->>'email';
  --RAISE WARNING 'jwt role %', current_setting('request.jwt.claims', true)::json->>'role';
  --RAISE WARNING 'cur_user %', current_user;
  --RAISE WARNING 'user.id [%], user.email [%]', current_setting('user.id', true), current_setting('user.email', true);
  --RAISE WARNING 'vessel.id [%], vessel.name [%]', current_setting('vessel.id', true), current_setting('vessel.name', true);

  --TODO SELECT current_setting('request.jwt.uid', true)::json->>'uid' INTO _user_id;
  --TODO RAISE WARNING 'jwt user_id %', current_setting('request.jwt.uid', true)::json->>'uid';
  --TODO SELECT current_setting('request.jwt.vid', true)::json->>'vid' INTO _vessel_id;
  --TODO RAISE WARNING 'jwt vessel_id %', current_setting('request.jwt.vid', true)::json->>'vid';
  IF _role = 'user_role' OR _role = 'mcp_role' THEN
    -- Check the user exist in the accounts table
    SELECT * INTO account_rec
        FROM auth.accounts
        WHERE auth.accounts.email = _email;
    IF account_rec.email IS NULL THEN
        RAISE EXCEPTION 'Invalid user'
            USING HINT = 'Unknown user or password';
    END IF;
    -- Set session variables
    PERFORM set_config('user.id', account_rec.user_id, true);
    SELECT current_setting('request.path', true) into _path;
    --RAISE WARNING 'req path %', current_setting('request.path', true);
    -- Function allow without defined vessel like for anonymous role
    IF _path ~ '^\/rpc\/(login|signup|recover|reset)$' THEN
        RETURN;
    END IF;
    -- Function allow without defined vessel as user role
    -- openapi doc, user settings, otp code and vessel registration
    IF _path = '/rpc/settings_fn'
        OR _path = '/rpc/register_vessel'
        OR _path = '/rpc/update_user_preferences_fn'
        OR _path = '/rpc/versions_fn'
        OR _path = '/rpc/email_fn'
        OR _path = '/' THEN
        RETURN;
    END IF;
    -- Check a vessel and user exist
    SELECT auth.vessels.* INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = auth.accounts.email
            AND auth.accounts.email = _email;
    -- check if boat exist yet?
    IF vessel_rec.owner_email IS NULL THEN
        -- Return http status code 551 with message
        RAISE sqlstate 'PT551' using
            message = 'Vessel Required',
            detail = 'Invalid vessel',
            hint = 'Unknown vessel';
        --RETURN; -- ignore if not exist
    END IF;
    -- Redundant?
    IF vessel_rec.vessel_id IS NULL THEN
        RAISE EXCEPTION 'Invalid vessel'
            USING HINT = 'Unknown vessel id';
    END IF;
    -- Set session variables
    PERFORM set_config('vessel.id', vessel_rec.vessel_id, true);
    PERFORM set_config('vessel.name', vessel_rec.name, true);
    --RAISE WARNING 'public.check_jwt() user_role vessel.id [%]', current_setting('vessel.id', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.name [%]', current_setting('vessel.name', false);
  ELSIF _role = 'vessel_role' THEN
    SELECT current_setting('request.path', true) into _path;
    --RAISE WARNING 'req path %', current_setting('request.path', true);
    -- Function allow without defined vessel like for anonymous role
    IF _path ~ '^\/rpc\/(oauth_\w+)$' THEN
        RETURN;
    END IF;
    -- Extract vessel_id from jwt token
    SELECT current_setting('request.jwt.claims', true)::json->>'vid' INTO _vid;
    -- Check the vessel and user exist
    SELECT auth.vessels.* INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = auth.accounts.email
            AND auth.accounts.email = _email
            AND auth.vessels.vessel_id = _vid;
    IF vessel_rec.owner_email IS NULL THEN
        RAISE EXCEPTION 'Invalid vessel'
            USING HINT = 'Unknown vessel owner_email';
    END IF;
    PERFORM set_config('vessel.id', vessel_rec.vessel_id, true);
    PERFORM set_config('vessel.name', vessel_rec.name, true);
    --RAISE WARNING 'public.check_jwt() user_role vessel.name %', current_setting('vessel.name', false);
    --RAISE WARNING 'public.check_jwt() user_role vessel.id %', current_setting('vessel.id', false);
  ELSIF _role = 'api_anonymous' THEN
    --RAISE WARNING 'public.check_jwt() api_anonymous path[%] vid:[%]', current_setting('request.path', true), current_setting('vessel.id', false); 
    -- Check if path is the a valid allow anonymous path
    SELECT current_setting('request.path', true) ~ '^/(logs_view|log_view|rpc/timelapse_fn|rpc/timelapse2_fn|monitoring_live|monitoring_view|stats_logs_view|stats_moorages_view|rpc/stats_logs_fn|rpc/export_logbooks_geojson_point_trips_fn|rpc/export_logbooks_geojson_linestring_trips_fn)$' INTO _ppath;
    if _ppath is True then
        -- Check is custom header is present and valid
        SELECT current_setting('request.headers', true)::json->>'x-is-public' into _pheader;
        --RAISE WARNING 'public.check_jwt() api_anonymous _pheader [%]', _pheader;
        if _pheader is null then
            return;
			--RAISE EXCEPTION 'Invalid public_header'
            --    USING HINT = 'Stop being so evil and maybe you can log in';
        end if;
        SELECT convert_from(decode(_pheader, 'base64'), 'utf-8')
                            ~ '\w+,public_(logs|logs_list|stats|timelapse|monitoring),\d+$' into _pvalid;
        RAISE WARNING 'public.check_jwt() api_anonymous _pvalid [%]', _pvalid;
        if _pvalid is null or _pvalid is False then
            RAISE EXCEPTION 'Invalid public_valid'
                USING HINT = 'Stop being so evil and maybe you can log in';
        end if;
        WITH regex AS (
            SELECT regexp_match(
                        convert_from(
                            decode(_pheader, 'base64'), 'utf-8'),
                        '(\w+),(public_(logs|logs_list|stats|timelapse|monitoring)),(\d+)$') AS match
            )
        SELECT match[1], match[2], match[4] into _pvessel, _ptype, _pid
            FROM regex;
        RAISE WARNING 'public.check_jwt() api_anonymous [%] [%] [%]', _pvessel, _ptype, _pid;
        if _pvessel is not null and _ptype is not null then
            -- Everything seem fine, get the vessel_id base on the vessel name.
            SELECT _ptype::name = any(enum_range(null::public_type)::name[]) INTO valid_public_type;
            IF valid_public_type IS False THEN
                -- Ignore entry if type is invalid
                RAISE EXCEPTION 'Invalid public_type'
                    USING HINT = 'Stop being so evil and maybe you can log in';
            END IF;
            -- Check if boat name match public_vessel name
            boat := '^' || _pvessel || '$';
            IF _ptype ~ '^public_(logs|timelapse)$' AND _pid > 0 THEN
                WITH log as (
                    SELECT vessel_id from api.logbook l where l.id = _pid
                )
                SELECT v.vessel_id, v.name into anonymous_rec
                    FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs, log l
                    WHERE v.vessel_id = l.vessel_id
                        AND a.email = v.owner_email
                        AND a.preferences->>'public_vessel'::text ~* boat
                        AND prefs.key = _ptype::TEXT
                        AND prefs.value::BOOLEAN = true;
                RAISE WARNING '-> ispublic_fn public_logs output boat:[%], type:[%], result:[%]', _pvessel, _ptype, anonymous_rec;
                IF anonymous_rec.vessel_id IS NOT NULL THEN
                    PERFORM set_config('vessel.id', anonymous_rec.vessel_id, true);
                    PERFORM set_config('vessel.name', anonymous_rec.name, true);
                    RETURN;
                END IF;
            ELSE
                SELECT v.vessel_id, v.name into anonymous_rec
                        FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs
                        WHERE a.email = v.owner_email
                            AND a.preferences->>'public_vessel'::text ~* boat
                            AND prefs.key = _ptype::TEXT
                            AND prefs.value::BOOLEAN = true;
                RAISE WARNING '-> ispublic_fn output boat:[%], type:[%], result:[%]', _pvessel, _ptype, anonymous_rec;
                IF anonymous_rec.vessel_id IS NOT NULL THEN
                    PERFORM set_config('vessel.id', anonymous_rec.vessel_id, true);
                    PERFORM set_config('vessel.name', anonymous_rec.name, true);
                    RETURN;
                END IF;
            END IF;
            --RAISE sqlstate 'PT404' using message = 'unknown resource';
        END IF; -- end anonymous path
    END IF;
  ELSIF _role <> 'api_anonymous' THEN
    RAISE EXCEPTION 'Invalid role'
      USING HINT = 'Stop being so evil and maybe you can log in';
  END IF;
END
$_$;


--
-- Name: FUNCTION check_jwt(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.check_jwt() IS 'PostgREST API db-pre-request check, set_config according to role (api_anonymous,vessel_role,user_role)';


--
-- Name: cron_alerts_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cron_alerts_fn() RETURNS void
    LANGUAGE plpgsql
    AS $$
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
            (alert_default || ( -- Filters out empty strings (""), so they are not included in the result.
							    SELECT jsonb_object_agg(key, value)
							    FROM jsonb_each(a.preferences->'alerting') 
							    WHERE value <> '""'
							  )) as alerting,
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
                    avg(-- Inside Temperature
                        COALESCE(
                            m.metrics->'temperature'->>'inside',
                            m.metrics->>(md.configuration->>'insideTemperatureKey'),
                            m.metrics->>'environment.inside.temperature'
                        )::FLOAT) AS intemp,
                    avg(-- Wind Speed True (converted from m/s to knots)
                        COALESCE(
                            m.metrics->'wind'->>'speed',
                            m.metrics->>(md.configuration->>'windSpeedKey'),
                            m.metrics->>'environment.wind.speedTrue'
                        )::FLOAT * 1.94384)::NUMERIC AS wind,
                    avg(-- Water Depth
                        COALESCE(
                            m.metrics->'water'->>'depth',
                            m.metrics->>(md.configuration->>'depthKey'),
                            m.metrics->>'environment.depth.belowTransducer'
                        )::FLOAT) AS watdepth,
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
                JOIN api.metadata md ON md.vessel_id = m.vessel_id
                WHERE md.vessel_id = alert_rec.vessel_id
                    AND m.time >= alert_rec.last_metric::TIMESTAMPTZ
                GROUP BY time_bucket
                ORDER BY time_bucket ASC LIMIT 100
        LOOP
            RAISE NOTICE '-> cron_alerts_fn checking metrics [%]', metric_rec;
            RAISE NOTICE '-> cron_alerts_fn checking alerting [%]', alert_rec.alerting;
            --RAISE NOTICE '-> cron_alerts_fn checking debug [%] [%]', kelvinToCel(metric_rec.intemp), (alert_rec.alerting->'low_indoor_temperature_threshold');
            IF metric_rec.intemp IS NOT NULL AND public.kelvintocel(metric_rec.intemp::NUMERIC) < (alert_rec.alerting->'low_indoor_temperature_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug indoor_temp [%]', (alert_rec.alarms->'low_indoor_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug indoor_temp [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
                    SELECT user_settings::JSONB || ('{"alert": "low_indoor_temperature_threshold value:'|| kelvinToCel(metric_rec.intemp) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_indoor_temperature_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_indoor_temperature_threshold';
            END IF;
            IF metric_rec.outtemp IS NOT NULL AND public.kelvintocel(metric_rec.outtemp::NUMERIC) < (alert_rec.alerting->>'low_outdoor_temperature_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug outdoor_temp [%]', (alert_rec.alarms->'low_outdoor_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug outdoor_temp [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
                RAISE NOTICE '-> cron_alerts_fn checking debug water_temp [%]', (alert_rec.alarms->'low_water_temperature_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug water_temp [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
                RAISE NOTICE '-> cron_alerts_fn checking debug water_depth [%]', (alert_rec.alarms->'low_water_depth_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug water_depth [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
                    SELECT user_settings::JSONB || ('{"alert": "low_water_depth_threshold value:'|| ROUND(metric_rec.watdepth::NUMERIC,2) ||' date:'|| metric_rec.time_bucket ||' "}'::text)::JSONB into user_settings;
                    -- Send notification
                    PERFORM send_notification_fn('alert'::TEXT, user_settings::JSONB);
                    -- DEBUG
                    RAISE NOTICE '-> cron_alerts_fn checking debug low_water_depth_threshold +interval';
                END IF;
                RAISE NOTICE '-> cron_alerts_fn checking debug low_water_depth_threshold';
            END IF;
            if metric_rec.pressure IS NOT NULL AND metric_rec.pressure::NUMERIC < (alert_rec.alerting->'high_pressure_drop_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug pressure [%]', (alert_rec.alarms->'high_pressure_drop_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug pressure [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
                RAISE NOTICE '-> cron_alerts_fn checking debug wind [%]', (alert_rec.alarms->'high_wind_speed_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug wind [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
            IF metric_rec.voltage IS NOT NULL AND metric_rec.voltage::NUMERIC < (alert_rec.alerting->'low_battery_voltage_threshold')::NUMERIC then
                RAISE NOTICE '-> cron_alerts_fn checking debug voltage [%]', (alert_rec.alarms->'low_battery_voltage_threshold'->>'date')::TIMESTAMPTZ;
                RAISE NOTICE '-> cron_alerts_fn checking debug voltage [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
            IF metric_rec.charge IS NOT NULL AND (metric_rec.charge::NUMERIC*100) < (alert_rec.alerting->'low_battery_charge_threshold')::NUMERIC then
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
$$;


--
-- Name: FUNCTION cron_alerts_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cron_alerts_fn() IS 'init by pg_cron to check for alerts';


--
-- Name: cron_process_autodiscovery_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cron_process_autodiscovery_fn() RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: FUNCTION cron_process_autodiscovery_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cron_process_autodiscovery_fn() IS 'init by pg_cron to check for new vessel pending autodiscovery config provisioning';


--
-- Name: cron_process_grafana_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cron_process_grafana_fn() RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: FUNCTION cron_process_grafana_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cron_process_grafana_fn() IS 'init by pg_cron to check for new vessel pending grafana provisioning, if so perform grafana_py_fn';


--
-- Name: cron_process_monitor_offline_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cron_process_monitor_offline_fn() RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: FUNCTION cron_process_monitor_offline_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cron_process_monitor_offline_fn() IS 'init by pg_cron to monitor offline pending notification, if so perform send_email o send_pushover base on user preferences';


--
-- Name: cron_process_monitor_online_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cron_process_monitor_online_fn() RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: FUNCTION cron_process_monitor_online_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cron_process_monitor_online_fn() IS 'refactor of metadata';


--
-- Name: cron_process_new_logbook_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cron_process_new_logbook_fn() RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
    process_rec record;
begin
    -- Check for new logbook pending update
    RAISE NOTICE 'cron_process_new_logbook_fn init loop';
    FOR process_rec in 
        SELECT * FROM process_queue 
            WHERE channel = 'new_logbook' AND processed IS NULL
            ORDER BY stored ASC LIMIT 100
    LOOP
        RAISE NOTICE 'cron_process_new_logbook_fn processing queue [%] for logbook id [%]', process_rec.id, process_rec.payload;
        -- update logbook
        PERFORM process_logbook_queue_fn(process_rec.payload::INTEGER);
        -- update process_queue table , processed
        UPDATE process_queue 
            SET 
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE 'cron_process_new_logbook_fn processed queue [%] for logbook id [%]', process_rec.id, process_rec.payload;
    END LOOP;
END;
$$;


--
-- Name: FUNCTION cron_process_new_logbook_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cron_process_new_logbook_fn() IS 'init by pg_cron to check for new logbook pending update, if so perform process_logbook_queue_fn';


--
-- Name: cron_process_new_notification_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cron_process_new_notification_fn() RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: FUNCTION cron_process_new_notification_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cron_process_new_notification_fn() IS 'init by pg_cron to check for new event pending notifications, if so perform process_notification_queue_fn';


--
-- Name: cron_process_new_stay_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cron_process_new_stay_fn() RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
    process_rec record;
begin
    -- Check for new stay pending update
    RAISE NOTICE 'cron_process_new_stay_fn init loop';
    FOR process_rec in 
        SELECT * FROM process_queue 
            WHERE channel = 'new_stay' AND processed IS NULL
            ORDER BY stored ASC LIMIT 100
    LOOP
        RAISE NOTICE 'cron_process_new_stay_fn processing queue [%] for stay id [%]', process_rec.id, process_rec.payload;
        -- update stay
        PERFORM process_stay_queue_fn(process_rec.payload::INTEGER);
        -- update process_queue table , processed
        UPDATE process_queue 
            SET 
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE 'cron_process_new_stay_fn processed queue [%] for stay id [%]', process_rec.id, process_rec.payload;
    END LOOP;
END;
$$;


--
-- Name: FUNCTION cron_process_new_stay_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cron_process_new_stay_fn() IS 'init by pg_cron to check for new stay pending update, if so perform process_stay_queue_fn';


--
-- Name: cron_process_post_logbook_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cron_process_post_logbook_fn() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    process_rec record;
BEGIN
    -- Check for new logbook pending update
    RAISE NOTICE 'cron_process_post_logbook_fn init loop';
    FOR process_rec in
        SELECT * FROM process_queue
            WHERE channel = 'post_logbook' AND processed IS NULL
            ORDER BY stored ASC LIMIT 100
    LOOP
        RAISE NOTICE 'cron_process_post_logbook_fn processing queue [%] for logbook id [%]', process_rec.id, process_rec.payload;
        -- update logbook
        PERFORM process_post_logbook_fn(process_rec.payload::INTEGER);
        -- update process_queue table , processed
        UPDATE process_queue
            SET
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE 'cron_process_post_logbook_fn processed queue [%] for logbook id [%]', process_rec.id, process_rec.payload;
    END LOOP;
END;
$$;


--
-- Name: FUNCTION cron_process_post_logbook_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cron_process_post_logbook_fn() IS 'init by pg_cron to check for new logbook pending notification, after process_new_logbook_fn';


--
-- Name: cron_process_pre_logbook_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cron_process_pre_logbook_fn() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    process_rec record;
BEGIN
    -- Check for new logbook pending update
    RAISE NOTICE 'cron_process_pre_logbook_fn init loop';
    FOR process_rec in
        SELECT * FROM process_queue
            WHERE channel = 'pre_logbook' AND processed IS NULL
            ORDER BY stored ASC LIMIT 100
    LOOP
        RAISE NOTICE 'cron_process_pre_logbook_fn processing queue [%] for logbook id [%]', process_rec.id, process_rec.payload;
        -- update logbook
        PERFORM process_pre_logbook_fn(process_rec.payload::INTEGER);
        -- update process_queue table , processed
        UPDATE process_queue
            SET
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE 'cron_process_pre_logbook_fn processed queue [%] for logbook id [%]', process_rec.id, process_rec.payload;
    END LOOP;
END;
$$;


--
-- Name: FUNCTION cron_process_pre_logbook_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cron_process_pre_logbook_fn() IS 'init by pg_cron to check for new logbook pending update, if so perform process_logbook_valid_fn';


--
-- Name: cron_prune_otp_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cron_prune_otp_fn() RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        otp_rec record;
    BEGIN
        -- Purge OTP older than 15 minutes
        RAISE NOTICE 'cron_prune_otp_fn';
        FOR otp_rec in
            SELECT *
            FROM auth.otp
            WHERE otp_timestamp < NOW() AT TIME ZONE 'UTC' - INTERVAL '15 MINUTES'
            ORDER BY otp_timestamp desc
        LOOP
            RAISE NOTICE '-> cron_prune_otp_fn deleting expired otp for user [%]', otp_rec.user_email;
            -- remove entry
            DELETE FROM auth.otp
                WHERE user_email = otp_rec.user_email;
            RAISE NOTICE '-> cron_prune_otp_fn deleted expire otp for user [%]', otp_rec.user_email;
        END LOOP;
    END;
$$;


--
-- Name: FUNCTION cron_prune_otp_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cron_prune_otp_fn() IS 'init by pg_cron to purge older than 15 minutes OTP token';


--
-- Name: cron_windy_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cron_windy_fn() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    windy_rec RECORD;
    default_last_metric TIMESTAMPTZ := NOW() - INTERVAL '1 day';
    last_metric TIMESTAMPTZ := NOW();
    metric_rec RECORD;
    windy_metric JSONB;
    app_settings JSONB;
    user_settings JSONB;
    windy_pws JSONB;
    error_message TEXT;
BEGIN
    RAISE NOTICE 'cron_process_windy_fn: Starting Windy data upload process.';

    -- Fetch app settings
    app_settings := get_app_settings_fn();
    RAISE NOTICE '-> cron_process_windy_fn: app settings: %', app_settings;

    -- Iterate over users with Windy enabled
    FOR windy_rec IN
        SELECT
            a.id,
            a.email,
            v.vessel_id,
            v.name,
            COALESCE((a.preferences->'windy_last_metric')::TEXT, default_last_metric::TEXT) AS last_metric
        FROM auth.accounts a
        LEFT JOIN auth.vessels v ON v.owner_email = a.email
        LEFT JOIN api.metadata m ON m.vessel_id = v.vessel_id
        WHERE (a.preferences->'public_windy')::BOOLEAN = TRUE
        AND m.active = TRUE
        ORDER BY COALESCE((a.preferences->>'windy_last_metric')::TIMESTAMP, default_last_metric::TIMESTAMP) ASC
    LOOP
        RAISE NOTICE '-> cron_process_windy_fn: Processing vessel: [%]', windy_rec.name;

        -- Set vessel context
        PERFORM set_config('vessel.id', windy_rec.vessel_id, FALSE);

        -- Fetch user settings
        user_settings := get_user_settings_from_vesselid_fn(windy_rec.vessel_id::TEXT);
        RAISE NOTICE '-> cron_process_windy_fn: windy_rec: [%]', windy_rec;
        RAISE NOTICE '-> cron_process_windy_fn: checking user_settings [%]', user_settings;

        -- Fetch 5-minute aggregated metrics
        FOR metric_rec IN
            SELECT
                time_bucket('5 minutes', mt.time) AS time_bucket,
                AVG(COALESCE(
                    (mt.metrics->'temperature'->>'outside')::FLOAT,
                    (mt.metrics->>(md.configuration->>'outsideTemperatureKey'))::FLOAT,
                    (mt.metrics->>'environment.outside.temperature')::FLOAT
                )) AS temperature,
                AVG(COALESCE(
                    (mt.metrics->'pressure'->>'outside')::FLOAT,
                    (mt.metrics->>(md.configuration->>'outsidePressureKey'))::FLOAT,
                    (mt.metrics->>'environment.outside.pressure')::FLOAT
                )) AS pressure,
                AVG(COALESCE(
                    (mt.metrics->'humidity'->>'outside')::FLOAT,
                    (mt.metrics->>(md.configuration->>'outsideHumidityKey'))::FLOAT,
                    (mt.metrics->>'environment.outside.relativeHumidity')::FLOAT,
                    (mt.metrics->>'environment.outside.humidity')::FLOAT
                )) AS rh,
                AVG(COALESCE(
                    (mt.metrics->'wind'->>'direction')::FLOAT,
                    (mt.metrics->>(md.configuration->>'windDirectionKey'))::FLOAT,
                    (mt.metrics->>'environment.wind.directionTrue')::FLOAT
                )) AS winddir,
                AVG(COALESCE(
                    (mt.metrics->'wind'->>'speed')::FLOAT,
                    (mt.metrics->>(md.configuration->>'windSpeedKey'))::FLOAT,
                    (mt.metrics->>'environment.wind.speedTrue')::FLOAT,
                    (mt.metrics->>'environment.wind.speedApparent')::FLOAT
                )) AS wind,
                MAX(COALESCE(
                    (mt.metrics->'wind'->>'speed')::FLOAT,
                    (mt.metrics->>(md.configuration->>'windSpeedKey'))::FLOAT,
                    (mt.metrics->>'environment.wind.speedTrue')::FLOAT,
                    (mt.metrics->>'environment.wind.speedApparent')::FLOAT
                )) AS gust,
                LAST(latitude, mt.time) AS lat,
                LAST(longitude, mt.time) AS lng
            FROM api.metrics mt
            JOIN api.metadata md ON md.vessel_id = mt.vessel_id
            WHERE md.vessel_id = windy_rec.vessel_id
              AND mt.time >= windy_rec.last_metric::TIMESTAMPTZ
            GROUP BY time_bucket
            ORDER BY time_bucket ASC
            LIMIT 100
        LOOP
            --RAISE NOTICE '-> cron_process_windy_fn: metric_rec: [%]', metric_rec;
            -- Skip invalid metrics
            IF metric_rec.temperature IS NULL
               OR metric_rec.pressure IS NULL
               OR metric_rec.rh IS NULL
               OR metric_rec.wind IS NULL
               OR metric_rec.winddir IS NULL
               OR metric_rec.time_bucket < NOW() - INTERVAL '2 days' THEN
               --RAISE NOTICE '-> cron_process_windy_fn: ignoring invalid metric: [%]', metric_rec;
                CONTINUE;
            END IF;

            -- Build Windy metric payload
            windy_metric := jsonb_build_object(
                'dateutc', metric_rec.time_bucket,
                'station', user_settings['settings']['windy'],
                'name', windy_rec.name,
                'lat', metric_rec.lat,
                'lon', metric_rec.lng,
                'temp', public.kelvintocel(metric_rec.temperature::NUMERIC),
                'wind', metric_rec.wind,
                'gust', metric_rec.gust,
                'winddir', metric_rec.winddir::NUMERIC,
                'pressure', metric_rec.pressure,
                'rh', public.valToPercent(metric_rec.rh::NUMERIC)
            );

            RAISE NOTICE '-> cron_process_windy_fn: Sending metric at % to Windy: %', metric_rec.time_bucket, windy_metric;
            BEGIN
                -- Send to Windy
                windy_pws := public.windy_pws_py_fn(windy_metric, user_settings, app_settings);

                IF windy_pws ? 'password' THEN
                    -- Save Station ID
                    PERFORM api.update_user_preferences_fn(
                            '{windy}'::TEXT,
                            windy_pws->>'id'::TEXT);
                    -- Save Station password token
                    PERFORM api.update_user_preferences_fn(
                            '{windy_password_station}'::TEXT,
                            windy_pws->>'password'::TEXT);
                    -- Send notification
                    PERFORM send_notification_fn('windy'::TEXT, user_settings::JSONB);
                ELSIF windy_pws ? 'status' THEN
                    PERFORM api.update_user_preferences_fn(
                            '{windy_last_metric}'::TEXT,
                            metric_rec.time_bucket::TEXT);
                END IF;

                -- Update last_metric time
                last_metric := metric_rec.time_bucket;
                -- Windy is rate limiting the requests, there is no bulk processing
                PERFORM pg_sleep(2);

            EXCEPTION WHEN OTHERS THEN
                error_message := 'Error processing vessel ' || windy_rec.name || ': ' || SQLERRM;
                RAISE NOTICE '%', error_message;
            END;
        END LOOP;

        -- Update last metric time in user preferences
        PERFORM api.update_user_preferences_fn(
            '{windy_last_metric}'::TEXT,
            last_metric::TEXT
        );
        -- Windy is rate limiting the requests, there is no bulk processing
        PERFORM pg_sleep(3);
    END LOOP;

    RAISE NOTICE '-> cron_process_windy_fn: Windy data upload process completed.';
END;
$$;


--
-- Name: FUNCTION cron_windy_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.cron_windy_fn() IS 'init by pg_cron to create (or update) station and uploading observations to Windy Personal Weather Station observations';


--
-- Name: debug_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.debug_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    BEGIN
        --RAISE NOTICE 'debug_trigger_fn [%]', NEW;
        IF NEW.channel = 'email_otp' THEN
            RAISE WARNING 'debug_trigger_fn: channel is email_otp [%]', NEW;
        END IF;
        RETURN NEW;
    END;
$$;


--
-- Name: delete_vessel_fn(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_vessel_fn(_vessel_id text) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
  total_metrics INTEGER;
  del_metrics INTEGER;
  del_logs INTEGER;
  del_stays INTEGER;
  del_moorages INTEGER;
  del_queue INTEGER;
  out_json JSONB;
BEGIN
    select count(*) INTO total_metrics from api.metrics m where vessel_id = _vessel_id;
    WITH deleted AS (delete from api.metrics m where vessel_id = _vessel_id RETURNING *) SELECT count(*) INTO del_metrics FROM deleted;
    WITH deleted AS (delete from api.logbook l where vessel_id = _vessel_id RETURNING *) SELECT count(*) INTO del_logs FROM deleted;
    WITH deleted AS (delete from api.stays s where vessel_id = _vessel_id RETURNING *) SELECT count(*) INTO del_stays FROM deleted;
    WITH deleted AS (delete from api.moorages m where vessel_id = _vessel_id RETURNING *) SELECT count(*) INTO del_moorages FROM deleted;
    WITH deleted AS (delete from public.process_queue m where ref_id = _vessel_id RETURNING *) SELECT count(*) INTO del_queue FROM deleted;
    SELECT jsonb_build_object('total_metrics', total_metrics,
                            'del_metrics', del_metrics,
                            'del_logs', del_logs,
                            'del_stays', del_stays,
                            'del_moorages', del_moorages,
                            'del_queue', del_queue) INTO out_json;
    RETURN out_json;
END
$$;


--
-- Name: FUNCTION delete_vessel_fn(_vessel_id text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.delete_vessel_fn(_vessel_id text) IS 'Delete all vessel data (metrics,logbook,stays,moorages,process_queue) for a vessel_id';


--
-- Name: dump_account_fn(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.dump_account_fn(_email text, _vessel_id text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN True;
    -- TODO use COPY but we can't all in one?
    select count(*) from api.metrics m where vessel_id = _vessel_id;
    select * from api.metadata m where vessel_id = _vessel_id;
    select * from api.logbook l where vessel_id = _vessel_id;
    select * from api.moorages m where vessel_id = _vessel_id;
    select * from api.stays s where vessel_id = _vessel_id;
    select * from auth.vessels v where vessel_id = _vessel_id;
    select * from auth.accounts a where email  = _email;
END
$$;


--
-- Name: export_logbook_polar_fn(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.export_logbook_polar_fn(_id integer) RETURNS TABLE(awa_bin integer, tws_bin integer, avg_speed numeric, max_speed numeric, samples integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_vessel_id text;
    v_from_time timestamptz;
    v_to_time timestamptz;
BEGIN
    -- Get vessel_id and time range from logbook
    SELECT vessel_id, _from_time, _to_time
    INTO v_vessel_id, v_from_time, v_to_time
    FROM api.logbook
    WHERE id = _id;

    -- Safety check
    IF v_vessel_id IS NULL OR v_from_time IS NULL OR v_to_time IS NULL THEN
        RAISE EXCEPTION 'Logbook id % not found or missing time range', _id;
    END IF;

    -- Step 1–4: Build and return query
    RETURN QUERY
    WITH base AS (
        SELECT
            (ROUND(m.anglespeedapparent / 5) * 5)::INT AS awa_bin_c,
            m.speedoverground,
            m.windspeedapparent,
            m.anglespeedapparent,
            -- Wind Speed True (converted from m/s to knots)
            COALESCE(
                m.metrics->'wind'->>'speed',
                --m.metrics->>(md.configuration->>'windSpeedKey'),
                m.metrics->>'environment.wind.speedTrue'
            )::FLOAT * 1.94384 AS true_wind_speed
        FROM api.metrics m
        WHERE m.speedoverground IS NOT NULL
          AND m.windspeedapparent IS NOT NULL
          AND m.anglespeedapparent IS NOT NULL
          AND m.vessel_id = v_vessel_id
          AND m.time >= v_from_time
          AND m.time <= v_to_time
          AND ABS(m.anglespeedapparent) >= 25
    ),
    grouped AS (
        SELECT
            awa_bin_c,
            (
                CASE
                    WHEN true_wind_speed < 7  THEN 6
                    WHEN true_wind_speed < 9  THEN 8
                    WHEN true_wind_speed < 11 THEN 10
                    WHEN true_wind_speed < 13 THEN 12
                    WHEN true_wind_speed < 15 THEN 14
                    WHEN true_wind_speed < 17 THEN 16
                    WHEN true_wind_speed < 22 THEN 20
                    WHEN true_wind_speed < 27 THEN 25
                    ELSE 30
                END
            )::int AS tws_bin_c,
            ROUND(AVG(speedoverground)::numeric, 2) AS avg_speed_c,
            ROUND(MAX(speedoverground)::numeric, 2) AS max_speed_c,
            COUNT(*)::int AS samples_c
        FROM base
        GROUP BY awa_bin_c, tws_bin_c
    ),
    tws_bins AS (
        SELECT DISTINCT tws_bin_c FROM grouped
    )
    SELECT g.awa_bin_c AS awa_bin,
           g.tws_bin_c AS tws_bin,
           g.avg_speed_c AS avg_speed,
           g.max_speed_c AS max_speed,
           g.samples_c AS samples
    FROM grouped g
    UNION ALL
    SELECT 0 AS awa_bin, t.tws_bin_c, 0 AS avg_speed, 0 AS max_speed, 0 AS samples
    FROM tws_bins t
    ORDER BY tws_bin, awa_bin;

END;
$$;


--
-- Name: FUNCTION export_logbook_polar_fn(_id integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.export_logbook_polar_fn(_id integer) IS 'Generate polar for a log';


--
-- Name: generate_uid_fn(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_uid_fn(size integer) RETURNS text
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: FUNCTION generate_uid_fn(size integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.generate_uid_fn(size integer) IS 'Generate a random digit';


--
-- Name: generate_ulid(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_ulid() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    timestamp  BIGINT;
    random_part TEXT;
BEGIN
    timestamp := FLOOR(EXTRACT(EPOCH FROM clock_timestamp()) * 1000);
    random_part := encode(gen_random_bytes(10), 'hex');
    RETURN to_hex(timestamp) || random_part;
END;
$$;


--
-- Name: FUNCTION generate_ulid(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.generate_ulid() IS 'Generate a ULID (Universally Unique Lexicographically Sortable Identifier)';


--
-- Name: geojson_py_fn(jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.geojson_py_fn(original jsonb, geometry_type text) RETURNS jsonb
    LANGUAGE plpython3u IMMUTABLE STRICT
    AS $$
    import json
    parsed = json.loads(original)
    output = []
    #plpy.notice(parsed)
    # [None, None]
    if None not in parsed:
        for idx, x in enumerate(parsed):
            #plpy.notice(idx, x)
            for feature in x:
                #plpy.notice(feature)
                if (feature['geometry']['type'] != geometry_type):
                    output.append(feature)
                #elif (feature['properties']['id']): TODO
                #    output.append(feature)
                #else:
                #    plpy.notice('ignoring')
    return json.dumps(output)
$$;


--
-- Name: FUNCTION geojson_py_fn(original jsonb, geometry_type text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.geojson_py_fn(original jsonb, geometry_type text) IS 'Parse geojson using plpython3u (should be done in PGSQL), deprecated';


--
-- Name: get_app_settings_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_app_settings_fn(OUT app_settings jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    SELECT
        jsonb_object_agg(name, value) INTO app_settings
    FROM
        public.app_settings
    WHERE
        name LIKE 'app.email%'
        OR name LIKE 'app.pushover%'
        OR name LIKE 'app.url'
        OR name LIKE 'app.telegram%'
        OR name LIKE 'app.grafana_admin_uri'
        OR name LIKE 'app.keycloak_uri'
        OR name LIKE 'app.windy_apikey'
        OR name LIKE 'app.%_uri'
        OR name LIKE 'app.%_url';
END;
$$;


--
-- Name: FUNCTION get_app_settings_fn(OUT app_settings jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_app_settings_fn(OUT app_settings jsonb) IS 'get application settings details, email, pushover, telegram, grafana_admin_uri';


--
-- Name: get_app_url_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_app_url_fn(OUT app_settings jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
BEGIN
    SELECT
        jsonb_object_agg(name, value) INTO app_settings
    FROM
        public.app_settings
    WHERE
        name = 'app.url';
END;
$$;


--
-- Name: FUNCTION get_app_url_fn(OUT app_settings jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_app_url_fn(OUT app_settings jsonb) IS 'get application url security definer';


--
-- Name: get_season(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_season(input_date timestamp with time zone) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    CASE
        WHEN (EXTRACT(MONTH FROM input_date) = 3 AND EXTRACT(DAY FROM input_date) >= 1) OR
             (EXTRACT(MONTH FROM input_date) BETWEEN 4 AND 5) THEN
            RETURN 'Spring';
        WHEN (EXTRACT(MONTH FROM input_date) = 6 AND EXTRACT(DAY FROM input_date) >= 1) OR
             (EXTRACT(MONTH FROM input_date) BETWEEN 7 AND 8) THEN
            RETURN 'Summer';
        WHEN (EXTRACT(MONTH FROM input_date) = 9 AND EXTRACT(DAY FROM input_date) >= 1) OR
             (EXTRACT(MONTH FROM input_date) BETWEEN 10 AND 11) THEN
            RETURN 'Fall';
        ELSE
            RETURN 'Winter';
    END CASE;
END;
$$;


--
-- Name: get_user_settings_from_vesselid_fn(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_user_settings_from_vesselid_fn(vesselid text, OUT user_settings jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
    DECLARE
    BEGIN
        -- If vessel_id is not NULL
        IF vesselid IS NULL OR vesselid = '' THEN
            RAISE WARNING '-> get_user_settings_from_vesselid_fn invalid input %', vesselid;
        END IF;
        SELECT 
            json_build_object( 
                    'boat' , v.name,
                    'recipient', a.first,
                    'email', v.owner_email,
                    'settings', a.preferences
                    ) INTO user_settings
            FROM auth.accounts a, auth.vessels v, api.metadata m
            WHERE m.vessel_id = v.vessel_id
                AND m.vessel_id = vesselid
                AND a.email = v.owner_email;
        PERFORM set_config('user.email', user_settings->>'email'::TEXT, false);
        PERFORM set_config('user.recipient', user_settings->>'recipient'::TEXT, false);
    END;
$$;


--
-- Name: FUNCTION get_user_settings_from_vesselid_fn(vesselid text, OUT user_settings jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_user_settings_from_vesselid_fn(vesselid text, OUT user_settings jsonb) IS 'get user settings details from a vesselid initiate for notifications';


--
-- Name: grafana_py_fn(text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.grafana_py_fn(_v_name text, _v_id text, _u_email text, app jsonb) RETURNS void
    LANGUAGE plpython3u TRANSFORM FOR TYPE jsonb
    AS $$
	"""
	https://grafana.com/docs/grafana/latest/developers/http_api/
	Create organization base on vessel name
	Create user base on user email
	Add user to organization
	Add data_source to organization
	Add dashboard to organization
    Update organization preferences
	"""
	import requests
	import json
	import re

	grafana_uri = None
	if 'app.grafana_admin_uri' in app and app['app.grafana_admin_uri']:
		grafana_uri = app['app.grafana_admin_uri']
	else:
		plpy.error('Error no grafana_admin_uri defined, check app settings')
		return None

	b_name = None
	if not _v_name:
		b_name = _v_id
	else:
		b_name = _v_name

	# add vessel org
	headers = {'User-Agent': 'PostgSail', 'From': 'xbgmsharp@gmail.com',
	'Accept': 'application/json', 'Content-Type': 'application/json'}
	path = 'api/orgs'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	data_dict = {'name':b_name}
	data = json.dumps(data_dict)
	r = requests.post(url, data=data, headers=headers)
	#print(r.text)
	plpy.notice(r.json())
	if r.status_code == 200 and "orgId" in r.json():
		org_id = r.json()['orgId']
	else:
		plpy.error('Error grafana add vessel org {req} - {res}'.format(req=data_dict,res=r.json()))
		return none

	# add user to vessel org
	path = 'api/admin/users'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	data_dict = {'orgId':org_id, 'email':_u_email, 'password':'asupersecretpassword'}
	data = json.dumps(data_dict)
	r = requests.post(url, data=data, headers=headers)
	#print(r.text)
	plpy.notice(r.json())
	if r.status_code == 200 and "id" in r.json():
		user_id = r.json()['id']
	else:
		plpy.error('Error grafana add user to vessel org')
		return

	# read data_source
	path = 'api/datasources/1'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	r = requests.get(url, headers=headers)
	#print(r.text)
	plpy.notice(r.json())
	data_source = r.json()
	data_source['id'] = 0
	data_source['orgId'] = org_id
	data_source['uid'] = "ds_" + _v_id
	data_source['name'] = "ds_" + _v_id
	data_source['secureJsonData'] = {}
	data_source['secureJsonData']['password'] = 'mysecretpassword'
	data_source['readOnly'] = True
	if "secureJsonFields" in data_source:
		del data_source['secureJsonFields']

	# add data_source to vessel org
	path = 'api/datasources'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	data = json.dumps(data_source)
	headers['X-Grafana-Org-Id'] = str(org_id)
	r = requests.post(url, data=data, headers=headers)
	plpy.notice(r.json())
	del headers['X-Grafana-Org-Id']
	if r.status_code != 200 and "id" not in r.json():
		plpy.error('Error grafana add data_source to vessel org')
		return

	dashboards_tpl = [ 'pgsail_tpl_electrical', 'pgsail_tpl_logbook', 'pgsail_tpl_monitor', 'pgsail_tpl_rpi', 'pgsail_tpl_solar', 'pgsail_tpl_weather', 'pgsail_tpl_home']
	for dashboard in dashboards_tpl:
		# read dashboard template by uid
		path = 'api/dashboards/uid'
		url = f'{grafana_uri}/{path}/{dashboard}'.format(grafana_uri,path,dashboard)
		if 'X-Grafana-Org-Id' in headers:
			del headers['X-Grafana-Org-Id']
		r = requests.get(url, headers=headers)
		plpy.notice(r.json())
		if r.status_code != 200 and "id" not in r.json():
			plpy.error('Error grafana read dashboard template')
			return
		new_dashboard = r.json()
		del new_dashboard['meta']
		new_dashboard['dashboard']['version'] = 0
		new_dashboard['dashboard']['id'] = 0
		new_uid = re.sub(r'pgsail_tpl_(.*)', r'postgsail_\1', new_dashboard['dashboard']['uid'])
		new_dashboard['dashboard']['uid'] = f'{new_uid}_{_v_id}'.format(new_uid,_v_id)
		# add dashboard to vessel org
		path = 'api/dashboards/db'
		url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
		data = json.dumps(new_dashboard)
		new_data = data.replace('PCC52D03280B7034C', data_source['uid'])
		headers['X-Grafana-Org-Id'] = str(org_id)
		r = requests.post(url, data=new_data, headers=headers)
		plpy.notice(r.json())
		if r.status_code != 200 and "id" not in r.json():
			plpy.error('Error grafana add dashboard to vessel org')
			return

	# Update Org Prefs
	path = 'api/org/preferences'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	home_dashboard = {}
	home_dashboard['timezone'] = 'utc'
	home_dashboard['homeDashboardUID'] = f'postgsail_home_{_v_id}'.format(_v_id)
	data = json.dumps(home_dashboard)
	headers['X-Grafana-Org-Id'] = str(org_id)
	r = requests.patch(url, data=data, headers=headers)
	plpy.notice(r.json())
	if r.status_code != 200:
		plpy.error('Error grafana update org preferences')
		return

	plpy.notice('Done')
$$;


--
-- Name: FUNCTION grafana_py_fn(_v_name text, _v_id text, _u_email text, app jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.grafana_py_fn(_v_name text, _v_id text, _u_email text, app jsonb) IS 'Grafana Organization,User,data_source,dashboards provisioning via HTTP API using plpython3u';


--
-- Name: has_vessel_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_vessel_fn() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION has_vessel_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.has_vessel_fn() IS 'Check if user has a vessel register';


--
-- Name: has_vessel_metadata_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_vessel_metadata_fn() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
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
$$;


--
-- Name: FUNCTION has_vessel_metadata_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.has_vessel_metadata_fn() IS 'Check if user has a vessel register';


--
-- Name: isboolean(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.isboolean(text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $_$
DECLARE x BOOLEAN;
BEGIN
    x = $1::BOOLEAN;
    RETURN TRUE;
EXCEPTION WHEN others THEN
    RETURN FALSE;
END;
$_$;


--
-- Name: FUNCTION isboolean(text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.isboolean(text) IS 'Check typeof value is boolean';


--
-- Name: isdate(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.isdate(s character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
  perform s::date;
  return true;
exception when others then
  return false;
END;
$$;


--
-- Name: FUNCTION isdate(s character varying); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.isdate(s character varying) IS 'Check typeof value is date';


--
-- Name: isdouble(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.isdouble(text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $_$
DECLARE x DOUBLE PRECISION;
BEGIN
    x = $1::DOUBLE PRECISION;
    RETURN TRUE;
EXCEPTION WHEN others THEN
    RETURN FALSE;
END;
$_$;


--
-- Name: FUNCTION isdouble(text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.isdouble(text) IS 'Check typeof value is double';


--
-- Name: isnumeric(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.isnumeric(text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $_$
DECLARE x NUMERIC;
BEGIN
    x = $1::NUMERIC;
    RETURN TRUE;
EXCEPTION WHEN others THEN
    RETURN FALSE;
END;
$_$;


--
-- Name: FUNCTION isnumeric(text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.isnumeric(text) IS 'Check typeof value is numeric';


--
-- Name: istimestamptz(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.istimestamptz(text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $_$
DECLARE x TIMESTAMPTZ;
BEGIN
    x = $1::TIMESTAMPTZ;
    RETURN TRUE;
EXCEPTION WHEN others THEN
    RETURN FALSE;
END;
$_$;


--
-- Name: FUNCTION istimestamptz(text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.istimestamptz(text) IS 'Check typeof value is TIMESTAMPTZ';


--
-- Name: jsonb_diff_val(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jsonb_diff_val(val1 jsonb, val2 jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
    DECLARE
    result JSONB;
    v RECORD;
    BEGIN
    result = val1;
    FOR v IN SELECT * FROM jsonb_each(val2) LOOP
        IF result @> jsonb_build_object(v.key,v.value)
            THEN result = result - v.key;
        ELSIF result ? v.key THEN CONTINUE;
        ELSE
            result = result || jsonb_build_object(v.key,'null');
        END IF;
    END LOOP;
    RETURN result;
    END;
$$;


--
-- Name: FUNCTION jsonb_diff_val(val1 jsonb, val2 jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.jsonb_diff_val(val1 jsonb, val2 jsonb) IS 'Compare two jsonb objects';


--
-- Name: jsonb_key_exists(jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jsonb_key_exists(some_json jsonb, outer_key text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN (some_json->outer_key) IS NOT NULL;
END;
$$;


--
-- Name: FUNCTION jsonb_key_exists(some_json jsonb, outer_key text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.jsonb_key_exists(some_json jsonb, outer_key text) IS 'function that checks if an outer key exists in some_json and returns a boolean';


--
-- Name: jsonb_recursive_merge(jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.jsonb_recursive_merge(a jsonb, b jsonb) RETURNS jsonb
    LANGUAGE sql
    AS $$
    SELECT
        jsonb_object_agg(
            coalesce(ka, kb),
            CASE
            WHEN va isnull THEN vb
            WHEN vb isnull THEN va
            WHEN jsonb_typeof(va) <> 'object' OR jsonb_typeof(vb) <> 'object' THEN vb
            ELSE jsonb_recursive_merge(va, vb) END
        )
        FROM jsonb_each(A) temptable1(ka, va)
        FULL JOIN jsonb_each(B) temptable2(kb, vb) ON ka = kb
$$;


--
-- Name: FUNCTION jsonb_recursive_merge(a jsonb, b jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.jsonb_recursive_merge(a jsonb, b jsonb) IS 'Merging JSONB values';


--
-- Name: kelvintocel(double precision); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kelvintocel(temperature double precision) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
	RETURN ROUND((((temperature)::numeric - 273.15) * 10) / 10);
END
$$;


--
-- Name: FUNCTION kelvintocel(temperature double precision); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.kelvintocel(temperature double precision) IS 'convert kelvin To Celsius';


--
-- Name: logbook_active_geojson_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_active_geojson_fn(OUT _track_geojson jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
BEGIN
    WITH log_active AS (
        SELECT * FROM api.logbook WHERE active IS True
    ),
    log_gis_line AS (
        SELECT
            ST_MakeLine(
                ARRAY(
                    SELECT st_makepoint(longitude,latitude) AS geo_point
                        FROM api.metrics m, log_active l
                        WHERE m.latitude IS NOT NULL
                            AND m.longitude IS NOT NULL
                            AND m.time >= l._from_time::TIMESTAMPTZ
                        ORDER BY m.time ASC
                )
            ) AS line,
            (SELECT _from_time FROM log_active) AS _from_time,
            (SELECT NOW() - _from_time::TIMESTAMPTZ FROM log_active) AS duration_iso,
            (SELECT ST_Length(ST_MakeLine(ARRAY(
                SELECT st_makepoint(longitude,latitude) AS geo_point
                    FROM api.metrics m, log_active l
                    WHERE m.latitude IS NOT NULL
                        AND m.longitude IS NOT NULL
                        AND m.time >= l._from_time::TIMESTAMPTZ
                    ORDER BY m.time ASC
            ))::geography) / 1852 AS distance_nm
             FROM log_active) AS distance_nm
    ),
    log_gis_point AS (
        SELECT
            ST_AsGeoJSON(t.*)::json AS GeoJSONPoint
        FROM (
            ( SELECT
                time,
                courseovergroundtrue,
                speedoverground,
                windspeedapparent,
                longitude,latitude,
                '' AS notes,
                coalesce(metrics->>'environment.wind.speedTrue', null) as truewindspeed,
                coalesce(metrics->>'environment.wind.directionTrue', null) as truewinddirection,
                coalesce(status, null) AS status,
                ST_MakePoint(longitude,latitude) AS geo_point
                FROM api.metrics m
                WHERE m.latitude IS NOT NULL
                    AND m.longitude IS NOT NULL
                ORDER BY m.time DESC LIMIT 1
            )
        ) as t
    ),
    log_agg as (
        SELECT
            CASE WHEN log_gis_line.line IS NOT NULL THEN
                ( SELECT jsonb_agg(
                    jsonb_build_object(
                        'type', 'Feature',
                        'geometry', ST_AsGeoJSON(log_gis_line.line)::jsonb,
                        'properties', jsonb_build_object(
                            '_from_time', log_gis_line._from_time,
                            'distance', log_gis_line.distance_nm,
                            'duration', log_gis_line.duration_iso,
                            'in_route', True
                        )
                    )
                )::jsonb AS GeoJSONLine FROM log_gis_line )
            ELSE
                ( SELECT '[]'::json AS GeoJSONLine )::jsonb
            END
        FROM log_gis_line
    )
    SELECT
        jsonb_build_object(
            'type', 'FeatureCollection',
            'features', log_agg.GeoJSONLine::jsonb || log_gis_point.GeoJSONPoint::jsonb
        ) INTO _track_geojson
    FROM log_agg, log_gis_point;
END;
$$;


--
-- Name: FUNCTION logbook_active_geojson_fn(OUT _track_geojson jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_active_geojson_fn(OUT _track_geojson jsonb) IS 'Create a GeoJSON with 2 features, LineString with a current active log and Point with the last position';


--
-- Name: logbook_completed_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_completed_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    BEGIN
        RAISE NOTICE 'logbook_completed_trigger_fn [%]', OLD;
        RAISE NOTICE 'logbook_completed_trigger_fn [%] [%]', OLD._to_time, NEW._to_time;
        -- Add logbook entry to process queue for later processing
        --IF ( OLD._to_time <> NEW._to_time ) THEN
            INSERT INTO process_queue (channel, payload, stored, ref_id)
                VALUES ('new_logbook', NEW.id, NOW(), current_setting('vessel.id', true));
        --END IF;
        RETURN OLD; -- result is ignored since this is an AFTER trigger
    END;
$$;


--
-- Name: FUNCTION logbook_completed_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_completed_trigger_fn() IS 'Automatic process_queue for completed logbook._to_time';


--
-- Name: logbook_delete_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_delete_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE NOTICE 'logbook_delete_trigger_fn [%]', OLD;
    -- If api.logbook is deleted,
    -- Delete process_queue references
    DELETE FROM public.process_queue p
        WHERE p.payload = OLD.id::TEXT
            AND p.ref_id = OLD.vessel_id
            AND p.channel LIKE '%_logbook';
    RETURN OLD;
END;
$$;


--
-- Name: FUNCTION logbook_delete_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_delete_trigger_fn() IS 'When logbook is delete, process_queue references need to deleted as well.';


--
-- Name: logbook_get_extra_json_fn(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_get_extra_json_fn(search text, OUT output_json json) RETURNS json
    LANGUAGE plpgsql
    AS $$
    declare
     metric_json jsonb default '{}'::jsonb;
     metric_rec record;
    BEGIN
    -- TODO
		-- Calculate 'search' first entry
        FOR metric_rec IN
            SELECT key, value
                FROM api.metrics m,
                        jsonb_each_text(m.metrics)
                WHERE key ILIKE search
                    AND time = _start::TIMESTAMPTZ
                    AND vessel_id = current_setting('vessel.id', false)
        LOOP
            -- Engine Hours in seconds
            RAISE NOTICE '-> logbook_get_extra_json_fn metric: %', metric_rec;
            WITH
                end_metric AS (
                    -- Fetch 'tanks.%.currentVolume' last entry
                    SELECT key, value
                        FROM api.metrics m,
                            jsonb_each_text(m.metrics)
                        WHERE key ILIKE metric_rec.key
                            AND time = _end::TIMESTAMPTZ
                            AND vessel_id = current_setting('vessel.id', false)
                ),
                metric AS (
                    -- Subtract
                    SELECT (end_metric.value::numeric - metric_rec.value::numeric) AS value FROM end_metric
                )
            -- Generate JSON
            SELECT jsonb_build_object(metric_rec.key, metric.value) INTO metric_json FROM metrics;
            RAISE NOTICE '-> logbook_get_extra_json_fn key: %, value: %', metric_rec.key, metric_json;
        END LOOP;
    END;
$$;


--
-- Name: FUNCTION logbook_get_extra_json_fn(search text, OUT output_json json); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_get_extra_json_fn(search text, OUT output_json json) IS 'TODO';


--
-- Name: logbook_metrics_dwithin_fn(text, text, double precision, double precision); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_metrics_dwithin_fn(_start text, _end text, lgn double precision, lat double precision, OUT count_metric numeric) RETURNS numeric
    LANGUAGE plpgsql
    AS $$
    BEGIN
        SELECT count(*) INTO count_metric
            FROM api.metrics m
            WHERE
                m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.time >= _start::TIMESTAMPTZ
                AND m.time <= _end::TIMESTAMPTZ
                AND vessel_id = current_setting('vessel.id', false)
                AND ST_DWithin(
                    Geography(ST_MakePoint(m.longitude, m.latitude)),
                    Geography(ST_MakePoint(lgn, lat)),
                    50
                );
    END;
$$;


--
-- Name: FUNCTION logbook_metrics_dwithin_fn(_start text, _end text, lgn double precision, lat double precision, OUT count_metric numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_metrics_dwithin_fn(_start text, _end text, lgn double precision, lat double precision, OUT count_metric numeric) IS 'Check if all entries for a logbook are in stationary movement with 50 meters';


--
-- Name: logbook_metrics_timebucket_fn(text, integer, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_metrics_timebucket_fn(bucket_interval text, _id integer, _start timestamp with time zone, _end timestamp with time zone, OUT timebucket boolean) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE
    time_rec record;
    stay_rec record;
    log_rec record;
    geo_rec record;
    ref_time timestamptz;
    stay_id integer;
    stay_lat DOUBLE PRECISION;
    stay_lng DOUBLE PRECISION;
    stay_arv timestamptz;
    in_interval boolean := False;
    log_id integer;
    log_lat DOUBLE PRECISION;
    log_lng DOUBLE PRECISION;
    log_start timestamptz;
    in_log boolean := False;
BEGIN
    timebucket := False;
    -- Agg metrics over a bucket_interval
    RAISE NOTICE '-> logbook_metrics_timebucket_fn Starting loop by [%], _start[%], _end[%]', bucket_interval, _start, _end;
    for time_rec in
        WITH tbl_bucket AS (
            SELECT time_bucket(bucket_interval::INTERVAL, time) AS time_bucket,
                    avg(speedoverground) AS speed,
                    last(latitude, time) AS lat,
                    last(longitude, time) AS lng,
                    st_makepoint(avg(longitude),avg(latitude)) AS geo_point
                FROM api.metrics m
                WHERE
                    m.latitude IS NOT NULL
                    AND m.longitude IS NOT NULL
                    AND m.time >= _start::TIMESTAMPTZ
                    AND m.time <= _end::TIMESTAMPTZ
                    AND m.vessel_id = current_setting('vessel.id', false)
                GROUP BY time_bucket
                ORDER BY time_bucket asc
            ),
        tbl_bucket2 AS (
                SELECT time_bucket,
                    speed,
                    geo_point,lat,lng,
                    LEAD(time_bucket,1) OVER (
                        ORDER BY time_bucket asc
                    ) time_interval,
                    LEAD(geo_point,1) OVER (
                        ORDER BY time_bucket asc
                    ) geo_interval
                FROM tbl_bucket
                WHERE speed <= 0.5
            )
        SELECT time_bucket,
                speed,
                geo_point,lat,lng,
                time_interval,
                bucket_interval,
                (bucket_interval::interval * 2) AS min_interval,
                (time_bucket - time_interval) AS diff_interval,
                (time_bucket - time_interval)::INTERVAL < (bucket_interval::interval * 2)::INTERVAL AS to_be_process
        FROM tbl_bucket2
        WHERE (time_bucket - time_interval)::INTERVAL < (bucket_interval::interval * 2)::INTERVAL
    loop
        RAISE NOTICE '-> logbook_metrics_timebucket_fn ref_time [%] interval [%] bucket_interval[%]', ref_time, time_rec.time_bucket, bucket_interval;
        select ref_time + bucket_interval::interval * 1 >= time_rec.time_bucket into in_interval;
        RAISE NOTICE '-> logbook_metrics_timebucket_fn ref_time+inverval[%] interval [%], in_interval [%]', ref_time + bucket_interval::interval * 1, time_rec.time_bucket, in_interval;
        if ST_DWithin(Geography(ST_MakePoint(stay_lng, stay_lat)), Geography(ST_MakePoint(time_rec.lng, time_rec.lat)), 50) IS True then
            in_interval := True;
        end if;
        if ST_DWithin(Geography(ST_MakePoint(log_lng, log_lat)), Geography(ST_MakePoint(time_rec.lng, time_rec.lat)), 50) IS False then
            in_interval := False;
        end if;
        if in_interval is true then
            ref_time := time_rec.time_bucket;
        end if;
        RAISE NOTICE '-> logbook_metrics_timebucket_fn ref_time is stay within of next point %', ST_DWithin(Geography(ST_MakePoint(stay_lng, stay_lat)), Geography(ST_MakePoint(time_rec.lng, time_rec.lat)), 50);
        RAISE NOTICE '-> logbook_metrics_timebucket_fn ref_time is NOT log within of next point %', ST_DWithin(Geography(ST_MakePoint(log_lng, log_lat)), Geography(ST_MakePoint(time_rec.lng, time_rec.lat)), 50);
        if time_rec.time_bucket::TIMESTAMPTZ < _start::TIMESTAMPTZ + bucket_interval::interval * 1 then
            in_interval := True;
        end if;
        RAISE NOTICE '-> logbook_metrics_timebucket_fn ref_time is NOT before start[%] or +interval[%]', (time_rec.time_bucket::TIMESTAMPTZ < _start::TIMESTAMPTZ), (time_rec.time_bucket::TIMESTAMPTZ < _start::TIMESTAMPTZ + bucket_interval::interval * 1);
        continue when in_interval is True;

        RAISE NOTICE '-> logbook_metrics_timebucket_fn after continue stay_id[%], in_log[%]', stay_id, in_log;
        if stay_id is null THEN
            RAISE NOTICE '-> Close current logbook logbook_id ref_time [%] time_rec.time_bucket [%]', ref_time, time_rec.time_bucket;
            -- Close current logbook
            geo_rec := logbook_update_geom_distance_fn(_id, _start::TEXT, time_rec.time_bucket::TEXT);
            UPDATE api.logbook
                SET
                    active = false,
                    _to_time = time_rec.time_bucket,
                    _to_lat = time_rec.lat,
                    _to_lng = time_rec.lng,
                    track_geom = geo_rec._track_geom,
                    notes = 'updated time_bucket'
                WHERE id = _id;
            -- Add logbook entry to process queue for later processing
            INSERT INTO process_queue (channel, payload, stored, ref_id)
                VALUES ('pre_logbook', _id, NOW(), current_setting('vessel.id', true));
            RAISE WARNING '-> Updated existing logbook logbook_id [%] [%] and add to process_queue', _id, time_rec.time_bucket;
            -- Add new stay
            INSERT INTO api.stays
                (vessel_id, active, arrived, latitude, longitude, notes)
                VALUES (current_setting('vessel.id', false), false, time_rec.time_bucket, time_rec.lat, time_rec.lng, 'autogenerated time_bucket')
                RETURNING id, latitude, longitude, arrived INTO stay_id, stay_lat, stay_lng, stay_arv;
            RAISE WARNING '-> Add new stay stay_id [%] [%]', stay_id, time_rec.time_bucket;
            timebucket := True;
        elsif in_log is false THEN
            -- Close current stays
            UPDATE api.stays
                SET
                    active = false,
                    departed = ref_time,
                    notes = 'autogenerated time_bucket'
                WHERE id = stay_id;
            -- Add stay entry to process queue for further processing
            INSERT INTO process_queue (channel, payload, stored, ref_id)
                VALUES ('new_stay', stay_id, now(), current_setting('vessel.id', true));
            RAISE WARNING '-> Updated existing stays stay_id [%] departed [%] and add to process_queue', stay_id, ref_time;
            -- Add new logbook
            INSERT INTO api.logbook
                (vessel_id, active, _from_time, _from_lat, _from_lng, notes)
                VALUES (current_setting('vessel.id', false), false, ref_time, stay_lat, stay_lng, 'autogenerated time_bucket')
                RETURNING id, _from_lat, _from_lng, _from_time INTO log_id, log_lat, log_lng, log_start;
            RAISE WARNING '-> Add new logbook, logbook_id [%] [%]', log_id, ref_time;
            in_log := true;
            stay_id := 0;
            stay_lat := null;
            stay_lng := null;
            timebucket := True;
        elsif in_log is true THEN
            RAISE NOTICE '-> Close current logbook logbook_id [%], ref_time [%], time_rec.time_bucket [%]', log_id, ref_time, time_rec.time_bucket;
            -- Close current logbook
            geo_rec := logbook_update_geom_distance_fn(_id, log_start::TEXT, time_rec.time_bucket::TEXT);
            UPDATE api.logbook
                SET
                    active = false,
                    _to_time = time_rec.time_bucket,
                    _to_lat = time_rec.lat,
                    _to_lng = time_rec.lng,
                    track_geom = geo_rec._track_geom,
                    notes = 'autogenerated time_bucket'
                WHERE id = log_id;
            -- Add logbook entry to process queue for later processing
            INSERT INTO process_queue (channel, payload, stored, ref_id)
                VALUES ('pre_logbook', log_id, NOW(), current_setting('vessel.id', true));
            RAISE WARNING '-> Update Existing logbook logbook_id [%] [%] and add to process_queue', log_id, time_rec.time_bucket;
            -- Add new stay
            INSERT INTO api.stays
                (vessel_id, active, arrived, latitude, longitude, notes)
                VALUES (current_setting('vessel.id', false), false, time_rec.time_bucket, time_rec.lat, time_rec.lng, 'autogenerated time_bucket')
                RETURNING id, latitude, longitude, arrived INTO stay_id, stay_lat, stay_lng, stay_arv;
            RAISE WARNING '-> Add new stay stay_id [%] [%]', stay_id, time_rec.time_bucket;
            in_log := false;
            log_id := null;
            log_lat := null;
            log_lng := null;
            timebucket := True;
        end if;
        RAISE WARNING '-> Update new ref_time [%]', ref_time;
        ref_time := time_rec.time_bucket;
    end loop;

    RAISE NOTICE '-> logbook_metrics_timebucket_fn Ending loop stay_id[%], in_log[%]', stay_id, in_log;
    if in_log is true then
        RAISE NOTICE '-> Ending log ref_time [%] interval [%]', ref_time, time_rec.time_bucket;
    end if;
    if stay_id > 0 then
        RAISE NOTICE '-> Ending stay ref_time [%] interval [%]', ref_time, time_rec.time_bucket;
        select * into stay_rec from api.stays s where arrived = _end;
        -- Close current stays
        UPDATE api.stays
            SET
                active = false,
                arrived = stay_arv,
                notes = 'updated time_bucket'
            WHERE id = stay_rec.id;
        -- Add stay entry to process queue for further processing
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('new_stay', stay_rec.id, now(), current_setting('vessel.id', true));
        RAISE WARNING '-> Ending Update Existing stays stay_id [%] arrived [%] and add to process_queue', stay_rec.id, stay_arv;
        delete from api.stays where id = stay_id;
        RAISE WARNING '-> Ending Delete Existing stays stay_id [%]', stay_id;
        stay_arv := null;
        stay_id := null;
        stay_lat := null;
        stay_lng := null;
        timebucket := True;
    end if;
END;
$$;


--
-- Name: FUNCTION logbook_metrics_timebucket_fn(bucket_interval text, _id integer, _start timestamp with time zone, _end timestamp with time zone, OUT timebucket boolean); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_metrics_timebucket_fn(bucket_interval text, _id integer, _start timestamp with time zone, _end timestamp with time zone, OUT timebucket boolean) IS 'Check if all entries for a logbook are in stationary movement per time bucket of 15 or 5 min, speed < 0.6knot, d_within 50m of the stay point';


--
-- Name: logbook_timelapse_geojson_fn(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_timelapse_geojson_fn(_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
    declare
        first_feature_note JSONB;
        second_feature_note JSONB;
        last_feature_note JSONB;
        logbook_rec record;
    begin
        -- We need to fetch the processed logbook data.
        SELECT name,duration,distance,_from,_to INTO logbook_rec
            FROM api.logbook
            WHERE active IS false
                AND id = _id
                AND _from_lng IS NOT NULL
                AND _from_lat IS NOT NULL
                AND _to_lng IS NOT NULL
                AND _to_lat IS NOT NULL;
        --raise warning '-> logbook_rec: %', logbook_rec;
        select format('{"trip": { "name": "%s", "duration": "%s", "distance": "%s" }}', logbook_rec.name, logbook_rec.duration, logbook_rec.distance) into first_feature_note;
        select format('{"notes": "%s"}', logbook_rec._from) into second_feature_note;
        select format('{"notes": "%s"}', logbook_rec._to) into last_feature_note;
        --raise warning '-> logbook_rec: % % %', first_feature_note, second_feature_note, last_feature_note;

        -- Update the properties of the first feature, the second with geometry point
        UPDATE api.logbook
            SET track_geojson = jsonb_set(
                track_geojson,
                '{features, 1, properties}',
                (track_geojson -> 'features' -> 1 -> 'properties' || first_feature_note)::jsonb
            )
            WHERE id = _id
                and track_geojson -> 'features' -> 1 -> 'geometry' ->> 'type' = 'Point';

        -- Update the properties of the third feature, the second with geometry point
        UPDATE api.logbook
            SET track_geojson = jsonb_set(
                track_geojson,
                '{features, 2, properties}',
                (track_geojson -> 'features' -> 2 -> 'properties' || second_feature_note)::jsonb
            )
            where id = _id
                and track_geojson -> 'features' -> 2 -> 'geometry' ->> 'type' = 'Point';

        -- Update the properties of the last feature with geometry point
        UPDATE api.logbook
            SET track_geojson = jsonb_set(
                track_geojson,
                '{features, -1, properties}',
                CASE
                    WHEN COALESCE((track_geojson -> 'features' -> -1 -> 'properties' ->> 'notes'), '') = '' THEN
                        (track_geojson -> 'features' -> -1 -> 'properties' || last_feature_note)::jsonb
                    ELSE
                        track_geojson -> 'features' -> -1 -> 'properties'
                END
            )
            WHERE id = _id
                and track_geojson -> 'features' -> -1 -> 'geometry' ->> 'type' = 'Point';
end;
$$;


--
-- Name: FUNCTION logbook_timelapse_geojson_fn(_id integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_timelapse_geojson_fn(_id integer) IS 'Update logbook geojson, Add properties to some geojson features for timelapse purpose';


--
-- Name: logbook_update_avg_fn(integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_update_avg_fn(_id integer, _start text, _end text, OUT avg_speed double precision, OUT max_speed double precision, OUT max_wind_speed double precision, OUT avg_wind_speed double precision, OUT count_metric integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
    BEGIN
        RAISE NOTICE '-> logbook_update_avg_fn calculate avg for logbook id=%, start:"%", end:"%"', _id, _start, _end;
        SELECT AVG(speedoverground), MAX(speedoverground), MAX(windspeedapparent), AVG(windspeedapparent), COUNT(*) INTO
                avg_speed, max_speed, max_wind_speed, avg_wind_speed, count_metric
            FROM api.metrics m
            WHERE m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.time >= _start::TIMESTAMPTZ
                AND m.time <= _end::TIMESTAMPTZ
                AND vessel_id = current_setting('vessel.id', false);
        RAISE NOTICE '-> logbook_update_avg_fn avg for logbook id=%, avg_speed:%, max_speed:%, avg_wind_speed:%, max_wind_speed:%, count:%', _id, avg_speed, max_speed, avg_wind_speed, max_wind_speed, count_metric;
    END;
$$;


--
-- Name: FUNCTION logbook_update_avg_fn(_id integer, _start text, _end text, OUT avg_speed double precision, OUT max_speed double precision, OUT max_wind_speed double precision, OUT avg_wind_speed double precision, OUT count_metric integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_update_avg_fn(_id integer, _start text, _end text, OUT avg_speed double precision, OUT max_speed double precision, OUT max_wind_speed double precision, OUT avg_wind_speed double precision, OUT count_metric integer) IS 'Update logbook details with calculate average and max data, AVG(speedOverGround), MAX(speedOverGround), MAX(windspeedapparent), count_metric';


--
-- Name: logbook_update_extra_json_fn(integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_update_extra_json_fn(_id integer, _start text, _end text, OUT _extra_json json) RETURNS json
    LANGUAGE plpgsql
    AS $$
    declare
        log_json jsonb default '{}'::jsonb;
        runtime_json jsonb default '{}'::jsonb;
        metrics_json jsonb default '{}'::jsonb;
        metric_rec record;
    BEGIN
        -- Calculate 'navigation.log' metrics
        WITH
            start_trip as (
                -- Fetch 'navigation.log' start, first entry
                SELECT key, value
                FROM api.metrics m,
                        jsonb_each_text(m.metrics)
                WHERE key ILIKE 'navigation.log'
                    AND time = _start::TIMESTAMPTZ
                    AND vessel_id = current_setting('vessel.id', false)
            ),
            end_trip as (
                -- Fetch 'navigation.log' end, last entry
                SELECT key, value
                FROM api.metrics m,
                        jsonb_each_text(m.metrics)
                WHERE key ILIKE 'navigation.log'
                    AND time = _end::TIMESTAMPTZ
                    AND vessel_id = current_setting('vessel.id', false)
            ),
            nm as (
                -- calculate distance and convert meter to nautical miles
                SELECT ((end_trip.value::NUMERIC - start_trip.value::numeric) * 0.00053996) as trip from start_trip,end_trip
            )
        -- Generate JSON
        SELECT jsonb_build_object('navigation.log', trip) INTO log_json FROM nm;
        RAISE NOTICE '-> logbook_update_extra_json_fn navigation.log: %', log_json;

        -- Calculate engine hours from propulsion.%.runTime first entry
        FOR metric_rec IN
            SELECT key, value
                FROM api.metrics m,
                        jsonb_each_text(m.metrics)
                WHERE key ILIKE 'propulsion.%.runTime'
                    AND time = _start::TIMESTAMPTZ
                    AND vessel_id = current_setting('vessel.id', false)
        LOOP
            -- Engine Hours in seconds
            RAISE NOTICE '-> logbook_update_extra_json_fn propulsion.*.runTime: %', metric_rec;
            with
            end_runtime AS (
                -- Fetch 'propulsion.*.runTime' last entry
                SELECT key, value
                    FROM api.metrics m,
                            jsonb_each_text(m.metrics)
                    WHERE key ILIKE metric_rec.key
                        AND time = _end::TIMESTAMPTZ
                        AND vessel_id = current_setting('vessel.id', false)
            ),
            runtime AS (
                -- calculate runTime Engine Hours as ISO duration
                --SELECT (end_runtime.value::numeric - metric_rec.value::numeric) AS value FROM end_runtime
                SELECT (((end_runtime.value::numeric - metric_rec.value::numeric) / 3600) * '1 hour'::interval)::interval as value FROM end_runtime
            )
            -- Generate JSON
            SELECT jsonb_build_object(metric_rec.key, runtime.value) INTO runtime_json FROM runtime;
            RAISE NOTICE '-> logbook_update_extra_json_fn key: %, value: %', metric_rec.key, runtime_json;
        END LOOP;

        -- Update logbook with extra value and return json
        SELECT COALESCE(log_json::JSONB, '{}'::jsonb) || COALESCE(runtime_json::JSONB, '{}'::jsonb) INTO metrics_json;
        SELECT jsonb_build_object('metrics', metrics_json) INTO _extra_json;
        RAISE NOTICE '-> logbook_update_extra_json_fn log_json: %, runtime_json: %, _extra_json: %', log_json, runtime_json, _extra_json;
    END;
$$;


--
-- Name: FUNCTION logbook_update_extra_json_fn(_id integer, _start text, _end text, OUT _extra_json json); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_update_extra_json_fn(_id integer, _start text, _end text, OUT _extra_json json) IS 'Update log details with extra_json using `propulsion.*.runTime` and `navigation.log`';


--
-- Name: logbook_update_geojson_fn(integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_update_geojson_fn(_id integer, _start text, _end text, OUT _track_geojson json) RETURNS json
    LANGUAGE plpgsql
    AS $$
    declare
     log_geojson jsonb;
     metrics_geojson jsonb;
     _map jsonb;
    begin
        -- GeoJson Feature Logbook linestring
        SELECT
            ST_AsGeoJSON(log.*) into log_geojson
        FROM
           ( SELECT
                id,name,
                distance,
                duration,
                avg_speed,
                max_speed,
                max_wind_speed,
                _from_time,
                _to_time,
                _from_moorage_id,
                _to_moorage_id,
                notes,
                extra['avg_wind_speed'] as avg_wind_speed,
                track_geom
                FROM api.logbook
                WHERE id = _id
           ) AS log;
        -- GeoJson Feature Metrics point
        SELECT
            json_agg(ST_AsGeoJSON(t.*)::json) into metrics_geojson
        FROM (
            ( SELECT
                time,
                courseovergroundtrue,
                speedoverground,
                windspeedapparent,
                longitude,latitude,
                '' AS notes,
                coalesce(metersToKnots((metrics->'environment.wind.speedTrue')::NUMERIC), null) as truewindspeed,
                coalesce(radiantToDegrees((metrics->'environment.wind.directionTrue')::NUMERIC), null) as truewinddirection,
                coalesce(status, null) as status,
                st_makepoint(longitude,latitude) AS geo_point
                FROM api.metrics m
                WHERE m.latitude IS NOT NULL
                    AND m.longitude IS NOT NULL
                    AND time >= _start::TIMESTAMPTZ
                    AND time <= _end::TIMESTAMPTZ
                    AND vessel_id = current_setting('vessel.id', false)
                ORDER BY m.time ASC
            )
        ) AS t;

        -- Merge jsonb
        SELECT log_geojson::jsonb || metrics_geojson::jsonb into _map;
        -- output
        SELECT
            json_build_object(
                'type', 'FeatureCollection',
                'features', _map
            ) into _track_geojson;
    END;
$$;


--
-- Name: FUNCTION logbook_update_geojson_fn(_id integer, _start text, _end text, OUT _track_geojson json); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_update_geojson_fn(_id integer, _start text, _end text, OUT _track_geojson json) IS 'Update log details with geojson';


--
-- Name: logbook_update_geom_distance_fn(integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_update_geom_distance_fn(_id integer, _start text, _end text, OUT _track_geom public.geometry, OUT _track_distance double precision) RETURNS record
    LANGUAGE plpgsql
    AS $$
    BEGIN
        SELECT ST_MakeLine( 
            ARRAY(
                --SELECT ST_SetSRID(ST_MakePoint(longitude,latitude),4326) as geo_point
                SELECT st_makepoint(longitude,latitude) AS geo_point
                    FROM api.metrics m
                    WHERE m.latitude IS NOT NULL
                        AND m.longitude IS NOT NULL
                        AND m.time >= _start::TIMESTAMPTZ
                        AND m.time <= _end::TIMESTAMPTZ
                        AND vessel_id = current_setting('vessel.id', false)
                    ORDER BY m.time ASC
            )
        ) INTO _track_geom;
        --RAISE NOTICE '-> GIS LINESTRING %', _track_geom;
        -- SELECT ST_Length(_track_geom,false) INTO _track_distance;
        -- Meter to Nautical Mile (international) Conversion
        -- SELECT TRUNC (st_length(st_transform(track_geom,4326)::geography)::INT / 1.852) from logbook where id = 209; -- in NM
        -- SELECT (st_length(st_transform(track_geom,4326)::geography)::INT * 0.0005399568) from api.logbook where id = 1; -- in NM
        --SELECT TRUNC (ST_Length(_track_geom,false)::INT / 1.852) INTO _track_distance; -- in NM
        SELECT TRUNC (ST_Length(_track_geom,false)::INT * 0.0005399568, 4) INTO _track_distance; -- in NM
        RAISE NOTICE '-> logbook_update_geom_distance_fn GIS Length %', _track_distance;
    END;
$$;


--
-- Name: FUNCTION logbook_update_geom_distance_fn(_id integer, _start text, _end text, OUT _track_geom public.geometry, OUT _track_distance double precision); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_update_geom_distance_fn(_id integer, _start text, _end text, OUT _track_geom public.geometry, OUT _track_distance double precision) IS 'Update logbook details with geometry data an distance, ST_Length in Nautical Mile (international)';


--
-- Name: logbook_update_gpx_fn(integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_update_gpx_fn(_id integer, _start text, _end text, OUT _track_gpx xml) RETURNS xml
    LANGUAGE plpgsql
    AS $$
    DECLARE
        log_rec record;
        app_settings jsonb;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> logbook_update_gpx_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Gather log details _from_time and _to_time
        SELECT * INTO log_rec
            FROM
            api.logbook l
            WHERE l.id = _id;
        -- Ensure the query is successful
        IF log_rec.vessel_id IS NULL THEN
            RAISE WARNING '-> logbook_update_gpx_fn invalid logbook %', _id;
            RETURN;
        END IF;
        -- Gather url from app settings
        app_settings := get_app_settings_fn();
        --RAISE DEBUG '-> logbook_update_gpx_fn app_settings %', app_settings;
        -- Generate XML
        SELECT xmlelement(name gpx,
                            xmlattributes(  '1.1' as version,
                                            'PostgSAIL' as creator,
                                            'http://www.topografix.com/GPX/1/1' as xmlns,
                                            'http://www.opencpn.org' as "xmlns:opencpn",
                                            app_settings->>'app.url' as "xmlns:postgsail",
                                            'http://www.w3.org/2001/XMLSchema-instance' as "xmlns:xsi",
                                            'http://www.garmin.com/xmlschemas/GpxExtensions/v3' as "xmlns:gpxx",
                                            'http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd http://www.garmin.com/xmlschemas/GpxExtensions/v3 http://www8.garmin.com/xmlschemas/GpxExtensionsv3.xsd' as "xsi:schemaLocation"),
                xmlelement(name trk,
                    xmlelement(name name, log_rec.name),
                    xmlelement(name desc, log_rec.notes),
                    xmlelement(name link, xmlattributes(concat(app_settings->>'app.url', '/log/', log_rec.id) as href),
                                                xmlelement(name text, log_rec.name)),
                    xmlelement(name extensions, xmlelement(name "postgsail:log_id", log_rec.id),
                                                xmlelement(name "postgsail:link", concat(app_settings->>'app.url','/log/', log_rec.id)),
                                                xmlelement(name "opencpn:guid", uuid_generate_v4()),
                                                xmlelement(name "opencpn:viz", '1'),
                                                xmlelement(name "opencpn:start", log_rec._from_time),
                                                xmlelement(name "opencpn:end", log_rec._to_time)
                                                ),
                    xmlelement(name trkseg, xmlagg(
                                                xmlelement(name trkpt,
                                                    xmlattributes(latitude as lat, longitude as lon),
                                                        xmlelement(name time, time)
                                                )))))::pg_catalog.xml INTO _track_gpx
            FROM api.metrics m
            WHERE m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.time >= log_rec._from_time::TIMESTAMPTZ
                AND m.time <= log_rec._to_time::TIMESTAMPTZ
                AND vessel_id = log_rec.vessel_id
            GROUP BY m.time
            ORDER BY m.time ASC;
    END;
$$;


--
-- Name: FUNCTION logbook_update_gpx_fn(_id integer, _start text, _end text, OUT _track_gpx xml); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_update_gpx_fn(_id integer, _start text, _end text, OUT _track_gpx xml) IS 'Update log details with gpx xml, deprecated';


--
-- Name: logbook_update_metrics_short_fn(integer, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_update_metrics_short_fn(total_entry integer, start_date timestamp with time zone, end_date timestamp with time zone) RETURNS TABLE(trajectory public.tgeogpoint, courseovergroundtrue public.tfloat, speedoverground public.tfloat, windspeedapparent public.tfloat, windangleapparent public.tfloat, truewindspeed public.tfloat, truewinddirection public.tfloat, notes public.ttext, status public.ttext, watertemperature public.tfloat, depth public.tfloat, outsidehumidity public.tfloat, outsidepressure public.tfloat, outsidetemperature public.tfloat, stateofcharge public.tfloat, voltage public.tfloat, solarpower public.tfloat, solarvoltage public.tfloat, tanklevel public.tfloat, heading public.tfloat)
    LANGUAGE plpgsql
    AS $$
DECLARE
BEGIN
    -- Aggregate all metrics as trip is short.
    RETURN QUERY
    WITH metrics AS (
        -- Extract metrics
        SELECT mt.time AS time,
            mt.courseovergroundtrue,
            mt.speedoverground,
            mt.windspeedapparent, -- Wind Speed Apparent AWS in knots from plugin
            mt.anglespeedapparent, -- Wind Angle Apparent AWA in degrees from plugin
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True (converted from radians to degrees)
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT * (180.0 / PI()) AS heading,
            -- Wind Speed True (converted from m/s to knots)
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT * 1.94384 AS truewindspeed,
            -- Wind Direction True (converted from radians to degrees)
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT * (180.0 / PI()) AS truewinddirection,
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
        tfloatseq(array_agg(tfloat(o.anglespeedapparent, o.time) ORDER BY o.time ASC) FILTER (WHERE o.anglespeedapparent IS NOT NULL)) AS windangleapparent,
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
$$;


--
-- Name: FUNCTION logbook_update_metrics_short_fn(total_entry integer, start_date timestamp with time zone, end_date timestamp with time zone); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_update_metrics_short_fn(total_entry integer, start_date timestamp with time zone, end_date timestamp with time zone) IS 'Optimize logbook metrics for short metrics';


--
-- Name: logbook_update_metrics_timebucket_fn(integer, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logbook_update_metrics_timebucket_fn(total_entry integer, start_date timestamp with time zone, end_date timestamp with time zone) RETURNS TABLE(trajectory public.tgeogpoint, courseovergroundtrue public.tfloat, speedoverground public.tfloat, windspeedapparent public.tfloat, windangleapparent public.tfloat, truewindspeed public.tfloat, truewinddirection public.tfloat, notes public.ttext, status public.ttext, watertemperature public.tfloat, depth public.tfloat, outsidehumidity public.tfloat, outsidepressure public.tfloat, outsidetemperature public.tfloat, stateofcharge public.tfloat, voltage public.tfloat, solarpower public.tfloat, solarvoltage public.tfloat, tanklevel public.tfloat, heading public.tfloat)
    LANGUAGE plpgsql
    AS $$
DECLARE
    bucket_interval INTERVAL;
    trip_duration INTERVAL;
BEGIN
    -- Compute voyage duration
    trip_duration := end_date - start_date;

    -- Choose bucket interval based on trip duration
    -- 1m (<= 6h), 2m (<= 12h), 3m (<= 18h), 5m (<= 24h), 10m (<= 48h), else 15m
    IF trip_duration <= INTERVAL '6 hours' THEN
        bucket_interval := '1 minute';
    ELSIF trip_duration <= INTERVAL '12 hours' THEN
        bucket_interval := '2 minutes';
    ELSIF trip_duration <= INTERVAL '18 hours' THEN
        bucket_interval := '3 minutes';
    ELSIF trip_duration <= INTERVAL '24 hours' THEN
        bucket_interval := '5 minutes';
    ELSIF trip_duration <= INTERVAL '48 hours' THEN
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
            avg(mt.windspeedapparent) as windspeedapparent, -- Wind Speed Apparent in knots from plugin
            avg(mt.anglespeedapparent) as anglespeedapparent, -- Wind Angle Apparent in degrees from plugin
            last(mt.longitude, mt.time) as longitude, last(mt.latitude, mt.time) as latitude,
            '' AS notes,
            last(mt.status, mt.time) as status,
            -- Heading True (converted from radians to degrees)
            COALESCE(
                last(mt.metrics->>'heading', mt.time),
                last(mt.metrics->>'navigation.headingTrue', mt.time)
            )::FLOAT * (180.0 / PI()) AS heading,
            -- Wind Speed True (converted from m/s to knots)
            COALESCE(
                last(mt.metrics->'wind'->>'speed', mt.time),
                last(mt.metrics->>(md.configuration->>'windSpeedKey'), mt.time),
                last(mt.metrics->>'environment.wind.speedTrue', mt.time)
            )::FLOAT * 1.94384 AS truewindspeed,
            -- Wind Direction True (converted from radians to degrees)
            COALESCE(
                last(mt.metrics->'wind'->>'direction', mt.time),
                last(mt.metrics->>(md.configuration->>'windDirectionKey'), mt.time),
                last(mt.metrics->>'environment.wind.directionTrue', mt.time)
            )::FLOAT * (180.0 / PI()) AS truewinddirection,
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
            mt.anglespeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True (converted from radians to degrees)
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT * (180.0 / PI()) AS heading,
            -- Wind Speed True (converted from m/s to knots)
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT * 1.94384 AS truewindspeed,
            -- Wind Direction True (converted from radians to degrees)
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT * (180.0 / PI()) AS truewinddirection,
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
            mt.anglespeedapparent,
            mt.longitude,
            mt.latitude,
            '' AS notes,
            mt.status,
            -- Heading True (converted from radians to degrees)
            COALESCE(
                mt.metrics->>'heading',
                mt.metrics->>'navigation.headingTrue'
            )::FLOAT * (180.0 / PI()) AS heading,
            -- Wind Speed True (converted from m/s to knots)
            COALESCE(
                mt.metrics->'wind'->>'speed',
                mt.metrics->>(md.configuration->>'windSpeedKey'),
                mt.metrics->>'environment.wind.speedTrue'
            )::FLOAT * 1.94384 AS truewindspeed,
            -- Wind Direction True (converted from radians to degrees)
            COALESCE(
                mt.metrics->'wind'->>'direction',
                mt.metrics->>(md.configuration->>'windDirectionKey'),
                mt.metrics->>'environment.wind.directionTrue'
            )::FLOAT * (180.0 / PI()) AS truewinddirection,
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
        tfloatseq(array_agg(tfloat(o.anglespeedapparent, o.time_bucket) ORDER BY o.time_bucket ASC) FILTER (WHERE o.anglespeedapparent IS NOT NULL)) AS windangleapparent,
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
$$;


--
-- Name: FUNCTION logbook_update_metrics_timebucket_fn(total_entry integer, start_date timestamp with time zone, end_date timestamp with time zone); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.logbook_update_metrics_timebucket_fn(total_entry integer, start_date timestamp with time zone, end_date timestamp with time zone) IS 'Optimize logbook metrics base on the aggregate time-series';


--
-- Name: metadata_autodiscovery_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.metadata_autodiscovery_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    BEGIN
        RAISE NOTICE 'metadata_autodiscovery_trigger_fn [%]', NEW;
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('autodiscovery', NEW.vessel_id, NOW(), NEW.vessel_id);
        RETURN NULL;
    END;
$$;


--
-- Name: FUNCTION metadata_autodiscovery_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.metadata_autodiscovery_trigger_fn() IS 'process metadata autodiscovery config provisioning from vessel';


--
-- Name: metadata_grafana_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.metadata_grafana_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    BEGIN
        RAISE NOTICE 'metadata_grafana_trigger_fn [%]', NEW;
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('grafana', NEW.vessel_id, now(), NEW.vessel_id);
        RETURN NULL;
    END;
$$;


--
-- Name: FUNCTION metadata_grafana_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.metadata_grafana_trigger_fn() IS 'process metadata grafana provisioning from vessel';


--
-- Name: metadata_upsert_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.metadata_upsert_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
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
$_$;


--
-- Name: FUNCTION metadata_upsert_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.metadata_upsert_trigger_fn() IS 'process metadata from vessel, upsert';


--
-- Name: meterstoknots(numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.meterstoknots(meters numeric) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN ROUND(((meters * 1.9438445) * 10) / 10, 2);
END
$$;


--
-- Name: FUNCTION meterstoknots(meters numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.meterstoknots(meters numeric) IS 'convert speed meters/s To Knots';


--
-- Name: metrics_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.metrics_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
        previous_metric record;
        stay_code INTEGER;
        logbook_id INTEGER;
        stay_id INTEGER;
        valid_status BOOLEAN := False;
        _vessel_id TEXT;
        distance BOOLEAN := False;
    BEGIN
        --RAISE NOTICE 'metrics_trigger_fn';
        --RAISE WARNING 'metrics_trigger_fn [%] [%]', current_setting('vessel.id', true), NEW;
        -- Ensure vessel.id to new value to allow RLS
        IF NEW.vessel_id IS NULL THEN
            -- set vessel_id from jwt if not present in INSERT query
            NEW.vessel_id := current_setting('vessel.id');
        END IF;
        -- Boat metadata are check using api.metrics REFERENCES to api.metadata
        -- Fetch the latest entry to compare status against the new status to be insert
        SELECT * INTO previous_metric
            FROM api.metrics m 
            WHERE m.vessel_id IS NOT NULL
                AND m.vessel_id = current_setting('vessel.id', true)
            ORDER BY m.time DESC LIMIT 1;
        --RAISE NOTICE 'Metrics Status, New:[%] Previous:[%]', NEW.status, previous_metric.status;
        IF previous_metric.time = NEW.time THEN
            -- Ignore entry if same time
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], duplicate time [%] = [%]', NEW.vessel_id, previous_metric.time, NEW.time;
            RETURN NULL;
        END IF;
        IF previous_metric.time > NEW.time THEN
            -- Ignore entry if new time is later than previous time
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], new time is older than previous_metric.time [%] > [%]', NEW.vessel_id, previous_metric.time, NEW.time;
            RETURN NULL;
        END IF;
        IF NEW.time > NOW() THEN
            -- Ignore entry if new time is in the future.
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], new time is in the future [%] > [%]', NEW.vessel_id, NEW.time, NOW();
            RETURN NULL;
        END IF;
        -- Check if latitude or longitude are not type double
        --IF public.isdouble(NEW.latitude::TEXT) IS False OR public.isdouble(NEW.longitude::TEXT) IS False THEN
        --    -- Ignore entry if null latitude,longitude
        --    RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], not a double type for latitude or longitude [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
        --    RETURN NULL;
        --END IF;
        -- Check if latitude or longitude are null
        IF NEW.latitude IS NULL OR NEW.longitude IS NULL THEN
            -- Ignore entry if null latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], null latitude or longitude [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        -- Check if valid latitude
        IF NEW.latitude >= 90 OR NEW.latitude <= -90 THEN
            -- Ignore entry if invalid latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid latitude >= 90 OR <= -90 [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        -- Check if valid longitude
        IF NEW.longitude >= 180 OR NEW.longitude <= -180 THEN
            -- Ignore entry if invalid latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid longitude >= 180 OR <= -180 [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        IF NEW.latitude = NEW.longitude THEN
            -- Ignore entry if latitude,longitude are equal
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], latitude and longitude are equal [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            RETURN NULL;
        END IF;
        -- Check distance with previous point is > 10km
        --IF ST_Distance(
        --    ST_MakePoint(NEW.latitude,NEW.longitude)::geography,
        --    ST_MakePoint(previous_metric.latitude,previous_metric.longitude)::geography) > 10000 THEN
        --    RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], distance between previous metric and new metric is too long >10km, distance[%]', NEW.vessel_id, distance;
        --    RETURN NULL;
        --END IF;
        -- Check if status is null but speed is over 3knots set status to sailing
        IF NEW.status IS NULL AND NEW.speedoverground >= 3 THEN
            RAISE WARNING 'Metrics Unknown NEW.status from vessel_id [%], null status, set to sailing because of speedoverground is +3 from [%]', NEW.vessel_id, NEW.status;
            NEW.status := 'sailing';
        -- Check if status is null then set status to default moored
        ELSIF NEW.status IS NULL THEN
            RAISE WARNING 'Metrics Unknown NEW.status from vessel_id [%], null status, set to default moored from [%]', NEW.vessel_id, NEW.status;
            NEW.status := 'moored';
        END IF;
        IF previous_metric.status IS NULL THEN
            IF NEW.status = 'anchored' THEN
                RAISE WARNING 'Metrics Unknown previous_metric.status from vessel_id [%], [%] set to default current status [%]', NEW.vessel_id, previous_metric.status, NEW.status;
                previous_metric.status := NEW.status;
            ELSE
                RAISE WARNING 'Metrics Unknown previous_metric.status from vessel_id [%], [%] set to default status moored vs [%]', NEW.vessel_id, previous_metric.status, NEW.status;
                previous_metric.status := 'moored';
            END IF;
            -- Add new stay as no previous entry exist
            INSERT INTO api.stays 
                (vessel_id, active, arrived, latitude, longitude, stay_code)
                VALUES (current_setting('vessel.id', true), true, NEW.time, NEW.latitude, NEW.longitude, 1)
                RETURNING id INTO stay_id;
            -- Add stay entry to process queue for further processing
            --INSERT INTO process_queue (channel, payload, stored, ref_id)
            --    VALUES ('new_stay', stay_id, now(), current_setting('vessel.id', true));
            --RAISE WARNING 'Metrics Insert first stay as no previous metrics exist, stay_id stay_id [%] [%] [%]', stay_id, NEW.status, NEW.time;
        END IF;
        -- Check if status is valid enum
        SELECT NEW.status::name = any(enum_range(null::status_type)::name[]) INTO valid_status;
        IF valid_status IS False THEN
            -- Ignore entry if status is invalid
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid status [%]', NEW.vessel_id, NEW.status;
            RETURN NULL;
        END IF;
        -- Check if speedOverGround is valid value
        IF NEW.speedoverground >= 40 THEN
            -- Ignore entry as speedOverGround is invalid
            RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], speedOverGround is invalid, over 40 < [%]', NEW.vessel_id, NEW.speedoverground;
            RETURN NULL;
        END IF;

        -- Check the state and if any previous/current entry
        -- If change of state and new status is sailing or motoring
        IF previous_metric.status::TEXT <> NEW.status::TEXT AND
            ( (NEW.status::TEXT = 'sailing' AND previous_metric.status::TEXT <> 'motoring')
             OR (NEW.status::TEXT = 'motoring' AND previous_metric.status::TEXT <> 'sailing') ) THEN
            RAISE WARNING 'Metrics Update status, vessel_id [%], try new logbook, New:[%] Previous:[%]', NEW.vessel_id, NEW.status, previous_metric.status;
            -- Start new log
            logbook_id := public.trip_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF logbook_id IS NULL THEN
                INSERT INTO api.logbook
                    (vessel_id, active, _from_time, _from_lat, _from_lng)
                    VALUES (current_setting('vessel.id', true), true, NEW.time, NEW.latitude, NEW.longitude)
                    RETURNING id INTO logbook_id;
                RAISE WARNING 'Metrics Insert new logbook, vessel_id [%], logbook_id [%] [%] [%]', NEW.vessel_id, logbook_id, NEW.status, NEW.time;
            ELSE
                UPDATE api.logbook
                    SET
                        active = false,
                        _to_time = NEW.time,
                        _to_lat = NEW.latitude,
                        _to_lng = NEW.longitude
                    WHERE id = logbook_id;
                RAISE WARNING 'Metrics Existing logbook, vessel_id [%], logbook_id [%] [%] [%]', NEW.vessel_id, logbook_id, NEW.status, NEW.time;
            END IF;

            -- End current stay
            stay_id := public.stay_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF stay_id IS NOT NULL THEN
                UPDATE api.stays
                    SET
                        active = false,
                        departed = NEW.time
                    WHERE id = stay_id;
                -- Add stay entry to process queue for further processing
                INSERT INTO process_queue (channel, payload, stored, ref_id)
                    VALUES ('new_stay', stay_id, NOW(), current_setting('vessel.id', true));
                RAISE WARNING 'Metrics Updating, vessel_id [%], Stay end current stay_id [%] [%] [%]', NEW.vessel_id, stay_id, NEW.status, NEW.time;
            ELSE
                RAISE WARNING 'Metrics Invalid, vessel_id [%], stay_id [%] [%]', NEW.vessel_id, stay_id, NEW.time;
            END IF;

        -- If change of state and new status is moored or anchored
        ELSIF previous_metric.status::TEXT <> NEW.status::TEXT AND
            ( (NEW.status::TEXT = 'moored' AND previous_metric.status::TEXT <> 'anchored')
             OR (NEW.status::TEXT = 'anchored' AND previous_metric.status::TEXT <> 'moored') ) THEN
            -- Start new stays
            RAISE WARNING 'Metrics Update status, vessel_id [%], try new stay, New:[%] Previous:[%]', NEW.vessel_id, NEW.status, previous_metric.status;
            stay_id := public.stay_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF stay_id IS NULL THEN
                RAISE WARNING 'Metrics Inserting, vessel_id [%], new stay [%]', NEW.vessel_id, NEW.status;
                -- If metric status is anchored set stay_code accordingly
                stay_code = 1;
                IF NEW.status = 'anchored' THEN
                    stay_code = 2;
                END IF;
                -- Add new stay
                INSERT INTO api.stays
                    (vessel_id, active, arrived, latitude, longitude, stay_code)
                    VALUES (current_setting('vessel.id', true), true, NEW.time, NEW.latitude, NEW.longitude, stay_code)
                    RETURNING id INTO stay_id;
                RAISE WARNING 'Metrics Insert, vessel_id [%], new stay, stay_id [%] [%] [%]', NEW.vessel_id, stay_id, NEW.status, NEW.time;
            ELSE
                RAISE WARNING 'Metrics Invalid, vessel_id [%], stay_id [%] [%]', NEW.vessel_id, stay_id, NEW.time;
                UPDATE api.stays
                    SET
                        active = false,
                        departed = NEW.time,
                        notes = 'Invalid stay?'
                    WHERE id = stay_id;
            END IF;

            -- End current log/trip
            -- Fetch logbook_id by vessel_id
            logbook_id := public.trip_in_progress_fn(current_setting('vessel.id', true)::TEXT);
            IF logbook_id IS NOT NULL THEN
                -- todo check on time start vs end
                RAISE WARNING 'Metrics Updating, vessel_id [%], logbook status [%] [%] [%]', NEW.vessel_id, logbook_id, NEW.status, NEW.time;
                UPDATE api.logbook 
                    SET 
                        active = false, 
                        _to_time = NEW.time,
                        _to_lat = NEW.latitude,
                        _to_lng = NEW.longitude
                    WHERE id = logbook_id;
                -- Add logbook entry to process queue for later processing
                INSERT INTO process_queue (channel, payload, stored, ref_id)
                    VALUES ('pre_logbook', logbook_id, NOW(), current_setting('vessel.id', true));
            ELSE
                RAISE WARNING 'Metrics Invalid, vessel_id [%], logbook_id [%] [%] [%]', NEW.vessel_id, logbook_id, NEW.status, NEW.time;
            END IF;
        END IF;
        RETURN NEW; -- Finally insert the actual new metric
    END;
$$;


--
-- Name: FUNCTION metrics_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.metrics_trigger_fn() IS 'process metrics from vessel, generate pre_logbook and new_stay.';


--
-- Name: moorage_delete_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.moorage_delete_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    BEGIN
        RAISE NOTICE 'moorages_delete_trigger_fn [%]', OLD;
        DELETE FROM api.stays WHERE moorage_id = OLD.id;
        DELETE FROM api.logbook WHERE _from_moorage_id = OLD.id;
        DELETE FROM api.logbook WHERE _to_moorage_id = OLD.id;
        -- Delete process_queue references
        DELETE FROM public.process_queue p
            WHERE p.payload = OLD.id::TEXT
                AND p.ref_id = OLD.vessel_id
                AND p.channel = 'new_moorage';
        RETURN OLD; -- result is ignored since this is an AFTER trigger
    END;
$$;


--
-- Name: FUNCTION moorage_delete_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.moorage_delete_trigger_fn() IS 'Automatic delete logbook and stays reference when delete a moorage';


--
-- Name: moorage_update_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.moorage_update_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    BEGIN
        RAISE NOTICE 'moorages_update_trigger_fn [%]', NEW;
        IF ( OLD.name != NEW.name) THEN
            UPDATE api.logbook SET _from = NEW.name WHERE _from_moorage_id = NEW.id;
            UPDATE api.logbook SET _to = NEW.name WHERE _to_moorage_id = NEW.id;
        END IF;
        IF ( OLD.stay_code != NEW.stay_code) THEN
            UPDATE api.stays SET stay_code = NEW.stay_code WHERE moorage_id = NEW.id;
        END IF;
        RETURN NULL; -- result is ignored since this is an AFTER trigger
    END;
$$;


--
-- Name: FUNCTION moorage_update_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.moorage_update_trigger_fn() IS 'Automatic update of name and stay_code on logbook and stays reference';


--
-- Name: nanoid(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.nanoid(size integer DEFAULT 12) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    id TEXT := '';
    bytes BYTEA := gen_random_bytes(size);
    alphabet TEXT := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    byte INT;
BEGIN
    FOR i IN 0..size-1 LOOP
        byte := get_byte(bytes, i);
        id := id || substr(alphabet, (byte % 62) + 1, 1);
    END LOOP;
    RETURN id;
END;
$$;


--
-- Name: FUNCTION nanoid(size integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.nanoid(size integer) IS 'Generate a short random alphanumeric ID of specified length';


--
-- Name: new_account_entry_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.new_account_entry_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    insert into process_queue (channel, payload, stored, ref_id) values ('new_account', NEW.email, now(), NEW.user_id);
    return NEW;
END;
$$;


--
-- Name: FUNCTION new_account_entry_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.new_account_entry_fn() IS 'trigger process_queue on INSERT for new account';


--
-- Name: new_account_otp_validation_entry_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.new_account_otp_validation_entry_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    -- Add email_otp check only if not from oauth server
    if (NEW.preferences->>'email_verified')::boolean IS NOT True then
        insert into process_queue (channel, payload, stored, ref_id) values ('email_otp', NEW.email, now(), NEW.user_id);
    end if;
    return NEW;
END;
$$;


--
-- Name: new_vessel_entry_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.new_vessel_entry_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    insert into process_queue (channel, payload, stored, ref_id) values ('new_vessel', NEW.owner_email, now(), NEW.vessel_id);
    return NEW;
END;
$$;


--
-- Name: new_vessel_public_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.new_vessel_public_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    -- Update user settings with a public vessel name
    perform api.update_user_preferences_fn('{public_vessel}', regexp_replace(NEW.name, '\W+', '', 'g'));
    return NEW;
END;
$$;


--
-- Name: new_vessel_trim_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.new_vessel_trim_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.name := TRIM(NEW.name);
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION new_vessel_trim_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.new_vessel_trim_fn() IS 'Trim space vessel name';


--
-- Name: overpass_py_fn(numeric, numeric, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.overpass_py_fn(lon numeric, lat numeric, retry boolean DEFAULT false, OUT geo jsonb) RETURNS jsonb
    LANGUAGE plpython3u TRANSFORM FOR TYPE jsonb IMMUTABLE STRICT
    AS $_$
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
    url = f'https://overpass.private.coffee/api/interpreter?data={data}'.format(data)
    if retry:
        plpy.notice('overpass-api Retrying overpass-api.de API call')
        url = f'https://overpass-api.de/api/interpreter?data={data}'.format(data)
    try:
        # Add reasonable timeout: 30 seconds for connection, 30 seconds for read
        r = requests.get(url, headers=headers, timeout=(60, 60))
        #print(r.text)
        #plpy.notice(url)
        plpy.notice('overpass-api coord lon[{}] lat[{}] [{}]'.format(lon, lat, r.status_code))
        if r.status_code == 200:
            try:
                r_dict = r.json()
            except ValueError as e:
                plpy.notice('overpass-api Failed to decode JSON: {}'.format(e))
                #plpy.notice('Response text: {}'.format(r.text))
                return { "error": "invalid_json" };
            r_dict = r.json()
            #plpy.notice('overpass-api Got [{}]'.format(r_dict["elements"]))
            if "elements" in r_dict and r_dict["elements"]:
                if "tags" in r_dict["elements"][0] and r_dict["elements"][0]["tags"]:
                    return r_dict["elements"][0]["tags"]; # return the first element
            return { "error": "empty" };
        else:
            plpy.notice('overpass-api Failed to get overpass-api details with status code: {}'.format(r.status_code))
            #plpy.notice('overpass-api Failed Response text: {}'.format(r.text))
            return { "error": "failed_request" };

    except requests.exceptions.Timeout:
        plpy.warning('overpass-api Request timed out after 60s')
        if not retry:
            return overpass_py_fn(lon, lat, True)
        return {"error": "timeout"}
        
    except requests.exceptions.RequestException as e:
        plpy.warning('overpass-api Request exception: {}'.format(str(e)))
        if not retry:
            return overpass_py_fn(lon, lat, True)
        return {"error": "request_exception"}
        
    except Exception as e:
        plpy.error('overpass-api Unexpected exception: {}'.format(str(e)))
        return {"error": "unexpected_exception"}
$_$;


--
-- Name: FUNCTION overpass_py_fn(lon numeric, lat numeric, retry boolean, OUT geo jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.overpass_py_fn(lon numeric, lat numeric, retry boolean, OUT geo jsonb) IS 'Return https://overpass-turbo.eu seamark details within 400m using plpython3u';


--
-- Name: process_account_otp_validation_queue_fn(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.process_account_otp_validation_queue_fn(_email text) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        account_rec record;
        user_settings jsonb;
        app_settings jsonb;
        otp_code text;
    BEGIN
        IF _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        SELECT * INTO account_rec
            FROM auth.accounts
            WHERE email = _email;
        IF account_rec.email IS NULL OR account_rec.email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        -- Gather email and pushover app settings
        app_settings := get_app_settings_fn();
        otp_code := api.generate_otp_fn(_email);
        -- set user email variable
        PERFORM set_config('user.email', account_rec.email, false);
        -- Gather user settings
        user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '", "otp_code": "' || otp_code || '"}';
        -- Send notification email, pushover
        PERFORM send_notification_fn('email_otp'::TEXT, user_settings::JSONB);
        --PERFORM send_email_py_fn('email_otp'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('user'::TEXT, user_settings::JSONB, app_settings::JSONB);
    END;
$$;


--
-- Name: FUNCTION process_account_otp_validation_queue_fn(_email text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.process_account_otp_validation_queue_fn(_email text) IS 'process new account otp validation notification, deprecated';


--
-- Name: process_account_queue_fn(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.process_account_queue_fn(_email text) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
       	account_rec record;
        user_settings jsonb;
        app_settings jsonb;
    BEGIN
        IF _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        SELECT * INTO account_rec
            FROM auth.accounts
            WHERE email = _email;
        IF account_rec.email IS NULL OR account_rec.email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        -- Gather email and pushover app settings
        app_settings := get_app_settings_fn();
        -- set user email variable
        PERFORM set_config('user.email', account_rec.email, false);
        -- Gather user settings
        user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '"}';
        -- Send notification email, pushover
        PERFORM send_notification_fn('new_account'::TEXT, user_settings::JSONB);
        --PERFORM send_email_py_fn('user'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('user'::TEXT, user_settings::JSONB, app_settings::JSONB);
    END;
$$;


--
-- Name: FUNCTION process_account_queue_fn(_email text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.process_account_queue_fn(_email text) IS 'process new account notification, deprecated';


--
-- Name: process_lat_lon_fn(numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.process_lat_lon_fn(lon numeric, lat numeric, OUT moorage_id integer, OUT moorage_type integer, OUT moorage_name text, OUT moorage_country text) RETURNS record
    LANGUAGE plpgsql
    AS $$
    DECLARE
        stay_rec record;
        --moorage_id INTEGER := NULL;
        --moorage_type INTEGER := 1; -- Unknown
        --moorage_name TEXT := NULL;
        --moorage_country TEXT := NULL;
        existing_rec record;
        geo jsonb;
        overpass jsonb;
    BEGIN
        RAISE NOTICE '-> process_lat_lon_fn';
        IF lon IS NULL OR lat IS NULL THEN
            RAISE WARNING '-> process_lat_lon_fn invalid input lon %, lat %', lon, lat;
            --return NULL;
        END IF;

        -- Do we have an existing moorages within 300m of the new stay
        FOR existing_rec in
            SELECT
                *
            FROM api.moorages m
            WHERE
                m.latitude IS NOT NULL
                AND m.longitude IS NOT NULL
                AND m.geog IS NOT NULL
                AND ST_DWithin(
                    Geography(ST_MakePoint(m.longitude, m.latitude)),
                    Geography(ST_MakePoint(lon, lat)),
                    300 -- in meters
                    )
                AND m.vessel_id = current_setting('vessel.id', false)
            ORDER BY id ASC
        LOOP
            -- found previous stay within 300m of the new moorage
            IF existing_rec.id IS NOT NULL AND existing_rec.id > 0 THEN
                RAISE NOTICE '-> process_lat_lon_fn found previous moorages within 300m %', existing_rec;
                EXIT; -- exit loop
            END IF;
        END LOOP;

        -- if with in 300m use existing name and stay_code
        -- else insert new entry
        IF existing_rec.id IS NOT NULL AND existing_rec.id > 0 THEN
            RAISE NOTICE '-> process_lat_lon_fn found close by moorage using existing name and stay_code %', existing_rec;
            moorage_id := existing_rec.id;
            moorage_name := existing_rec.name;
            moorage_type := existing_rec.stay_code;
        ELSE
            RAISE NOTICE '-> process_lat_lon_fn create new moorage';
            -- query overpass api to guess moorage type
            overpass := overpass_py_fn(lon::NUMERIC, lat::NUMERIC);
            IF overpass->>'error' IS NOT NULL THEN
                -- Retry logic
                RAISE NOTICE '-> process_lat_lon_fn overpass returned error, retrying once: %', overpass->>'error';
                overpass := overpass_py_fn(lon::NUMERIC, lat::NUMERIC, true);
            END IF;
            RAISE NOTICE '-> process_lat_lon_fn overpass name:[%] seamark:type:[%]', overpass->'name', overpass->'seamark:type';
            moorage_type = 1; -- Unknown
            IF overpass->>'seamark:type' = 'harbour' AND overpass->>'seamark:harbour:category' = 'marina' THEN
                moorage_type = 4; -- Dock
            ELSIF overpass->>'seamark:type' = 'mooring' AND overpass->>'seamark:mooring:category' = 'buoy' THEN
                moorage_type = 3; -- Mooring Buoy
            ELSIF overpass->>'seamark:type' ~ '(anchorage|anchor_berth|berth)' OR overpass->>'natural' ~ '(bay|beach)' THEN
                moorage_type = 2; -- Anchor
            ELSIF overpass->>'seamark:type' = 'mooring' THEN
                moorage_type = 3; -- Mooring Buoy
            ELSIF overpass->>'leisure' = 'marina' THEN
                moorage_type = 4; -- Dock
            END IF;
            -- geo reverse _lng _lat
            geo := reverse_geocode_py_fn('nominatim', lon::NUMERIC, lat::NUMERIC);
            moorage_country := geo->>'country_code';
            IF overpass->>'name:en' IS NOT NULL THEN
                moorage_name = overpass->>'name:en';
            ELSIF overpass->>'name' IS NOT NULL THEN
                moorage_name = overpass->>'name';
            ELSE
                moorage_name := geo->>'name';
            END IF;
            RAISE NOTICE '-> process_lat_lon_fn output name:[%] type:[%]', moorage_name, moorage_type;
            RAISE NOTICE '-> process_lat_lon_fn insert new moorage for [%] name:[%] type:[%]', current_setting('vessel.id', false), moorage_name, moorage_type;
            -- Insert new moorage from stay
            INSERT INTO api.moorages
                (vessel_id, name, country, stay_code, latitude, longitude, geog, overpass, nominatim)
                VALUES (
                    current_setting('vessel.id', false),
                    coalesce(replace(moorage_name,'"', ''), null),
                    coalesce(moorage_country, null),
                    moorage_type,
                    lat,
                    lon,
                    Geography(ST_MakePoint(lon, lat)),
                    coalesce(overpass, null),
                    coalesce(geo, null)
                ) returning id into moorage_id;
            -- Add moorage entry to process queue for reference
            INSERT INTO process_queue (channel, payload, stored, ref_id, processed)
                VALUES ('new_moorage', moorage_id, now(), current_setting('vessel.id', true), now());
        END IF;
        --return json_build_object(
        --        'id', moorage_id,
        --        'name', moorage_name,
        --        'type', moorage_type
        --        )::jsonb;
    END;
$$;


--
-- Name: FUNCTION process_lat_lon_fn(lon numeric, lat numeric, OUT moorage_id integer, OUT moorage_type integer, OUT moorage_name text, OUT moorage_country text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.process_lat_lon_fn(lon numeric, lat numeric, OUT moorage_id integer, OUT moorage_type integer, OUT moorage_name text, OUT moorage_country text) IS 'Add or Update moorage base on lat/lon';


--
-- Name: process_logbook_queue_fn(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.process_logbook_queue_fn(_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
        _max_wind_speed NUMERIC;
        _avg_wind_speed NUMERIC;
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
        --extra_json := extra_json || jsonb_build_object('avg_wind_speed', twAvg(t_rec.truewindspeed));

        -- mobilitydb, add spaciotemporal sequence
        -- reduce the numbers of metrics by skipping row or aggregate time-series
        -- By default the signalk PostgSail plugin report one entry every minute.
        IF avg_rec.count_metric < 30 THEN -- if less ~20min trip we keep it all data
            t_rec := public.logbook_update_metrics_short_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        --ELSIF avg_rec.count_metric < 2000 THEN -- if less ~33h trip we skip data
        --    t_rec := public.logbook_update_metrics_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        ELSE -- As we have too many data, we time-series aggregate data
            t_rec := public.logbook_update_metrics_timebucket_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        END IF;
        --RAISE NOTICE 'mobilitydb [%]', t_rec;
        IF t_rec.trajectory IS NULL THEN
            RAISE WARNING '-> process_logbook_queue_fn, vessel_id [%], invalid mobilitydb data [%] [%]', logbook_rec.vessel_id, _id, t_rec;
            RETURN;
        END IF;
        IF t_rec.truewindspeed IS NULL AND t_rec.windspeedapparent IS NOT NULL THEN
            _max_wind_speed := maxValue(t_rec.windspeedapparent)::NUMERIC(6,2); -- Fallback to apparent wind speed
            _avg_wind_speed := twAvg(t_rec.windspeedapparent)::NUMERIC(6,2); -- Fallback to apparent wind speed
        ELSE
            _max_wind_speed := maxValue(t_rec.truewindspeed)::NUMERIC(6,2);
            _avg_wind_speed := twAvg(t_rec.truewindspeed)::NUMERIC(6,2);
        END IF;
        -- Update the avg_wind_speed from mobilitydb data -- TWS in knots
        extra_json := extra_json || jsonb_build_object('avg_wind_speed', _avg_wind_speed);

        RAISE NOTICE 'Updating valid logbook, vessel_id [%], entry logbook id:[%] start:[%] end:[%]', logbook_rec.vessel_id, logbook_rec.id, logbook_rec._from_time, logbook_rec._to_time;
        UPDATE api.logbook
            SET
                duration = (logbook_rec._to_time::TIMESTAMPTZ - logbook_rec._from_time::TIMESTAMPTZ),
                -- Problem with invalid SOG metrics
                --avg_speed = twAvg(t_rec.speedoverground)::NUMERIC(6,2), -- avg speed in knots
                max_speed = maxValue(t_rec.speedoverground)::NUMERIC(6,2), -- max speed in knots
                -- Calculate speed using mobility from m/s to knots - MobilityDB calculates instantaneous speed between consecutive GPS points
                avg_speed = (twavg(speed(t_rec.trajectory)) * 1.94384)::NUMERIC(6,2), -- avg speed in knots
                --max_speed = (maxValue(speed(t_rec.trajectory)) * 1.94384)::NUMERIC(6,2), -- max speed in knots
                max_wind_speed = _max_wind_speed, -- TWS in knots
                _from = from_moorage.moorage_name,
                _from_moorage_id = from_moorage.moorage_id,
                _to_moorage_id = to_moorage.moorage_id,
                _to = to_moorage.moorage_name,
                name = log_name,
                --distance = geo_rec._track_distance, -- in Nautical Miles
                distance = (length(t_rec.trajectory)/1852)::NUMERIC(10,2), -- in Nautical Miles
                extra = extra_json,
                notes = NULL, -- reset pre_log process
                trip = t_rec.trajectory,
                trip_cog = t_rec.courseovergroundtrue,
                trip_sog = t_rec.speedoverground,
                trip_aws = t_rec.windspeedapparent,
                trip_awa = t_rec.windangleapparent,
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
$$;


--
-- Name: FUNCTION process_logbook_queue_fn(_id integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.process_logbook_queue_fn(_id integer) IS 'Update logbook details when completed, logbook_update_avg_fn, logbook_update_geom_distance_fn, reverse_geocode_py_fn';


--
-- Name: process_moorage_queue_fn(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.process_moorage_queue_fn(_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
       	stay_rec record;
        moorage_rec record;
        user_settings jsonb;
        geo jsonb;
    BEGIN
        RAISE NOTICE 'process_moorage_queue_fn';
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_moorage_queue_fn invalid input %', _id;
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
            RAISE WARNING '-> process_moorage_queue_fn invalid stay %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', stay_rec.vessel_id, false);

        -- Do we have an existing stay within 200m of the new moorage
        FOR moorage_rec in
            SELECT
                *
            FROM api.moorages
            WHERE
                latitude IS NOT NULL
                AND longitude IS NOT NULL
                AND geog IS NOT NULL
                AND ST_DWithin(
                    -- Geography(ST_MakePoint(stay_rec._lng, stay_rec._lat)),
                    stay_rec.geog,
                    -- Geography(ST_MakePoint(longitude, latitude)),
                    geog,
                    200 -- in meters ?
                    )
            ORDER BY id ASC
        LOOP
            -- found previous stay within 200m of the new moorage
            IF moorage_rec.id IS NOT NULL AND moorage_rec.id > 0 THEN
                RAISE NOTICE 'Found previous stay within 200m of moorage %', moorage_rec;
                EXIT; -- exit loop
            END IF;
        END LOOP;

        -- if with in 200m update reference count and stay duration
        -- else insert new entry
        IF moorage_rec.id IS NOT NULL AND moorage_rec.id > 0 THEN
            RAISE NOTICE 'Update moorage %', moorage_rec;
            UPDATE api.moorages
                SET
                    reference_count = moorage_rec.reference_count + 1,
                    stay_duration =
                        moorage_rec.stay_duration + 
                        (stay_rec.departed::TIMESTAMPTZ - stay_rec.arrived::TIMESTAMPTZ)
                WHERE id = moorage_rec.id;
        ELSE
            RAISE NOTICE 'Insert new moorage entry from stay %', stay_rec;
            -- Set the moorage name and country if lat,lon
            IF stay_rec.longitude IS NOT NULL AND stay_rec.latitude IS NOT NULL THEN
                geo := reverse_geocode_py_fn('nominatim', stay_rec.longitude::NUMERIC, stay_rec.latitude::NUMERIC);
                moorage_rec.name = geo->>'name';
                moorage_rec.country = geo->>'country_code';
            END IF;
            -- Insert new moorage from stay
            INSERT INTO api.moorages
                    (vessel_id, name, country, stay_id, stay_code, stay_duration, reference_count, latitude, longitude, geog)
                    VALUES (
                        stay_rec.vessel_id,
                        coalesce(moorage_rec.name, null),
                        coalesce(moorage_rec.country, null),
                        stay_rec.id,
                        stay_rec.stay_code,
                        (stay_rec.departed::TIMESTAMPTZ - stay_rec.arrived::TIMESTAMPTZ),
                        1, -- default reference_count
                        stay_rec.latitude,
                        stay_rec.longitude,
                        Geography(ST_MakePoint(stay_rec.longitude, stay_rec.latitude))
                    );
        END IF;

        -- Process badges
        PERFORM badges_moorages_fn();
    END;
$$;


--
-- Name: FUNCTION process_moorage_queue_fn(_id integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.process_moorage_queue_fn(_id integer) IS 'Handle moorage insert or update from stays, deprecated';


--
-- Name: process_notification_queue_fn(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.process_notification_queue_fn(_email text, message_type text) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        account_rec record;
        vessel_rec record;
        user_settings jsonb := null;
        otp_code text;
    BEGIN
        IF _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        SELECT * INTO account_rec
            FROM auth.accounts
            WHERE email = _email;
        IF account_rec.email IS NULL OR account_rec.email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;

        RAISE NOTICE '--> process_notification_queue_fn type [%] [%]', _email, message_type;
        -- set user email variable
        PERFORM set_config('user.email', account_rec.email, false);
        -- Generate user_settings user settings
        IF message_type = 'new_account' THEN
            user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '"}';
        ELSEIF message_type = 'new_vessel' THEN
            -- Gather vessel data
            SELECT * INTO vessel_rec
                FROM auth.vessels
                WHERE owner_email = _email;
            IF vessel_rec.owner_email IS NULL OR vessel_rec.owner_email = '' THEN
                RAISE EXCEPTION 'Invalid email'
                    USING HINT = 'Unknown email';
                RETURN;
            END IF;
            user_settings := '{"email": "' || vessel_rec.owner_email || '", "boat": "' || vessel_rec.name || '"}';
        ELSEIF message_type = 'email_otp' THEN
            otp_code := api.generate_otp_fn(_email);
            user_settings := '{"email": "' || account_rec.email || '", "recipient": "' || account_rec.first || '", "otp_code": "' || otp_code || '"}';
        END IF;
        PERFORM send_notification_fn(message_type::TEXT, user_settings::JSONB);
    END;
$$;


--
-- Name: FUNCTION process_notification_queue_fn(_email text, message_type text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.process_notification_queue_fn(_email text, message_type text) IS 'process new event type notification, new_account, new_vessel, email_otp';


--
-- Name: process_post_logbook_fn(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.process_post_logbook_fn(_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        obs_json jsonb default '{ "seaState": -1, "cloudCoverage": -1, "visibility": -1}'::jsonb;
        logbook_rec record;
        log_settings jsonb;
        user_settings jsonb;
        extra_json jsonb;
        log_img_url text;
        --logs_img_url text;
        log_stats text;
        --extent_bbox text;
		v_ship_type NUMERIC;
    BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_post_logbook_fn invalid input %', _id;
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
            RAISE WARNING '-> process_post_logbook_fn invalid logbook %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', logbook_rec.vessel_id, false);
        --RAISE WARNING 'public.process_post_logbook_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);

        -- Get ship_type from metadata
        SELECT ship_type
          INTO v_ship_type
          FROM api.metadata
          WHERE vessel_id = logbook_rec.vessel_id;

        -- Check if ship_type = 36 Sailing Vessel
        IF v_ship_type = 36 THEN
          -- Update polar user_data in logbook table
          UPDATE api.logbook 
            SET extra = COALESCE(extra, '{}'::jsonb) || jsonb_build_object(
                  'polar', api.export_logbook_polar_csv_fn(logbook_rec.id),
                  'polar_updated_at', to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                )
          WHERE id = logbook_rec.id;
        END IF;

        -- Add observations to user_data in logbook table
        UPDATE api.logbook
          SET user_data = jsonb_build_object('observations', obs_json)
        WHERE id = logbook_rec.id;

        -- Generate logbook image map name from QGIS
        SELECT CONCAT('log_', logbook_rec.vessel_id::TEXT, '_', logbook_rec.id, '.png') INTO log_img_url;
        --SELECT ST_Extent(ST_Transform(logbook_rec.track_geom, 3857))::TEXT AS envelope INTO extent_bbox FROM api.logbook WHERE id = logbook_rec.id;
        --PERFORM public.qgis_getmap_py_fn(logbook_rec.vessel_id::TEXT, logbook_rec.id, extent_bbox::TEXT, False);
        -- Generate logs image map name from QGIS
        --WITH merged AS (
        --    SELECT ST_Union(logbook_rec.track_geom) AS merged_geometry
        --        FROM api.logbook WHERE vessel_id = logbook_rec.vessel_id
        --)
        --SELECT ST_Extent(ST_Transform(merged_geometry, 3857))::TEXT AS envelope INTO extent_bbox FROM merged;
        --SELECT CONCAT('logs_', logbook_rec.vessel_id::TEXT, '_', logbook_rec.id, '.png') INTO logs_img_url;
        --PERFORM public.qgis_getmap_py_fn(logbook_rec.vessel_id::TEXT, logbook_rec.id, extent_bbox::TEXT, True);

        -- Add formatted distance and duration for email notification
        SELECT CONCAT(ROUND(logbook_rec.distance, 2), ' NM / ', ROUND(EXTRACT(epoch FROM logbook_rec.duration)/3600,2), 'H') INTO log_stats;

        -- Prepare notification, gather user settings
        SELECT json_build_object('logbook_name', logbook_rec.name,
            'logbook_link', logbook_rec.id,
            'logbook_img', log_img_url,
            'logbook_stats', log_stats) INTO log_settings;
        user_settings := get_user_settings_from_vesselid_fn(logbook_rec.vessel_id::TEXT);
        SELECT user_settings::JSONB || log_settings::JSONB into user_settings;
        RAISE NOTICE '-> debug process_post_logbook_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        RAISE NOTICE '-> debug process_post_logbook_fn log_settings [%]', log_settings;
        -- Send notification
        PERFORM send_notification_fn('logbook'::TEXT, user_settings::JSONB);
        -- Process badges
        RAISE NOTICE '-> debug process_post_logbook_fn user_settings [%]', user_settings->>'email'::TEXT;
        PERFORM set_config('user.email', user_settings->>'email'::TEXT, false);
        PERFORM badges_logbook_fn(logbook_rec.id, logbook_rec._to_time::TEXT);
        PERFORM badges_geom_fn(logbook_rec.id, logbook_rec._to_time::TEXT);
    END;
$$;


--
-- Name: FUNCTION process_post_logbook_fn(_id integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.process_post_logbook_fn(_id integer) IS 'Notify user for new logbook.';


--
-- Name: process_pre_logbook_fn(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.process_pre_logbook_fn(_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        logbook_rec record;
        avg_rec record;
        geo_rec record;
        _invalid_time boolean;
        _invalid_interval boolean;
        _invalid_distance boolean;
        _invalid_ratio boolean;
        count_metric numeric;
        previous_stays_id numeric;
        current_stays_departed text;
        current_stays_id numeric;
        current_stays_active boolean;
        timebucket boolean;
    BEGIN
        -- If _id is not NULL
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> process_pre_logbook_fn invalid input %', _id;
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
            RAISE WARNING '-> process_pre_logbook_fn invalid logbook %', _id;
            RETURN;
        END IF;

        PERFORM set_config('vessel.id', logbook_rec.vessel_id, false);
        --RAISE WARNING 'public.process_logbook_queue_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);

        -- Check if all metrics are within 50meters base on geo loc
        count_metric := logbook_metrics_dwithin_fn(logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT, logbook_rec._from_lng::NUMERIC, logbook_rec._from_lat::NUMERIC);
        RAISE NOTICE '-> process_pre_logbook_fn logbook_metrics_dwithin_fn count:[%]', count_metric;

        -- Calculate logbook data average and geo
        -- Update logbook entry with the latest metric data and calculate data
        avg_rec := logbook_update_avg_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
        geo_rec := logbook_update_geom_distance_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);

        -- Avoid/ignore/delete logbook stationary movement or time sync issue
        -- Check time start vs end
        SELECT logbook_rec._to_time::TIMESTAMPTZ < logbook_rec._from_time::TIMESTAMPTZ INTO _invalid_time;
        -- Is distance is less than 0.010
        SELECT geo_rec._track_distance < 0.010 INTO _invalid_distance;
        -- Is duration is less than 100sec
        SELECT (logbook_rec._to_time::TIMESTAMPTZ - logbook_rec._from_time::TIMESTAMPTZ) < (100::text||' secs')::interval INTO _invalid_interval;
        -- If we have more than 800NM in less 15h
        IF geo_rec._track_distance >= 800 AND (logbook_rec._to_time::TIMESTAMPTZ - logbook_rec._from_time::TIMESTAMPTZ) < (15::text||' hours')::interval THEN
            _invalid_distance := True;
            _invalid_interval := True;
            --RAISE NOTICE '-> process_pre_logbook_fn invalid logbook data id [%], _invalid_distance [%], _invalid_interval [%]', logbook_rec.id, _invalid_distance, _invalid_interval;
        END IF;
        -- If we have less than 20 metrics or less than 0.5NM or less than avg 0.5knts
        -- Is within metrics represent more or equal than 60% of the total entry
        IF count_metric::NUMERIC <= 20 OR geo_rec._track_distance < 0.5 OR avg_rec.avg_speed < 0.5 THEN
            SELECT (count_metric::NUMERIC / avg_rec.count_metric::NUMERIC) >= 0.60 INTO _invalid_ratio;
        END IF;
        -- if stationary fix data metrics,logbook,stays,moorage
        IF _invalid_time IS True OR _invalid_distance IS True
            OR _invalid_interval IS True OR count_metric = avg_rec.count_metric
            OR _invalid_ratio IS True
            OR avg_rec.count_metric <= 3 THEN
            RAISE NOTICE '-> process_pre_logbook_fn invalid logbook data id [%], _invalid_time [%], _invalid_distance [%], _invalid_interval [%], count_metric_in_zone [%], count_metric_log [%], _invalid_ratio [%]',
                logbook_rec.id, _invalid_time, _invalid_distance, _invalid_interval, count_metric, avg_rec.count_metric, _invalid_ratio;
            -- Update metrics status to moored
            UPDATE api.metrics
                SET status = 'moored'
                WHERE time >= logbook_rec._from_time::TIMESTAMPTZ
                    AND time <= logbook_rec._to_time::TIMESTAMPTZ
                    AND vessel_id = current_setting('vessel.id', false);
            -- Update logbook
            UPDATE api.logbook
                SET notes = 'invalid logbook data, stationary need to fix metrics?'
                WHERE vessel_id = current_setting('vessel.id', false)
                    AND id = logbook_rec.id;
            -- Get related stays
            SELECT id,departed,active INTO current_stays_id,current_stays_departed,current_stays_active
                FROM api.stays s
                WHERE s.vessel_id = current_setting('vessel.id', false)
                    AND s.arrived = logbook_rec._to_time::TIMESTAMPTZ;
            -- Update related stays
            UPDATE api.stays s
                SET notes = 'invalid stays data, stationary need to fix metrics?'
                WHERE vessel_id = current_setting('vessel.id', false)
                    AND arrived = logbook_rec._to_time::TIMESTAMPTZ;
            -- Find previous stays
            SELECT id INTO previous_stays_id
				FROM api.stays s
                WHERE s.vessel_id = current_setting('vessel.id', false)
                    AND s.arrived < logbook_rec._to_time::TIMESTAMPTZ
                    ORDER BY s.arrived DESC LIMIT 1;
            -- Update previous stays with the departed time from current stays
            --  and set the active state from current stays
            UPDATE api.stays
                SET departed = current_stays_departed::TIMESTAMPTZ,
                    active = current_stays_active
                WHERE vessel_id = current_setting('vessel.id', false)
                    AND id = previous_stays_id;
            -- Clean up, remove invalid logbook and stay entry
            DELETE FROM api.logbook WHERE id = logbook_rec.id;
            RAISE WARNING '-> process_pre_logbook_fn delete invalid logbook [%]', logbook_rec.id;
            DELETE FROM api.stays WHERE id = current_stays_id;
            RAISE WARNING '-> process_pre_logbook_fn delete invalid stays [%]', current_stays_id;
            RETURN;
        END IF;

        --IF (logbook_rec.notes IS NULL) THEN -- run one time only
        --    -- If duration is over 24h or number of entry is over 400, check for stays and potential multiple logs with stationary location
        --    IF (logbook_rec._to_time::TIMESTAMPTZ - logbook_rec._from_time::TIMESTAMPTZ) > INTERVAL '24 hours'
        --        OR avg_rec.count_metric > 400 THEN
        --        timebucket := public.logbook_metrics_timebucket_fn('15 minutes'::TEXT, logbook_rec.id, logbook_rec._from_time::TIMESTAMPTZ, logbook_rec._to_time::TIMESTAMPTZ);
        --        -- If true exit current process as the current logbook need to be re-process.
        --        IF timebucket IS True THEN
        --            RETURN;
        --        END IF;
        --    ELSE
        --        timebucket := public.logbook_metrics_timebucket_fn('5 minutes'::TEXT, logbook_rec.id, logbook_rec._from_time::TIMESTAMPTZ, logbook_rec._to_time::TIMESTAMPTZ);
        --        -- If true exit current process as the current logbook need to be re-process.
        --        IF timebucket IS True THEN
        --            RETURN;
        --        END IF;
        --    END IF;
        --END IF;

        -- Add logbook entry to process queue for later processing
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('new_logbook', logbook_rec.id, NOW(), current_setting('vessel.id', true));

    END;
$$;


--
-- Name: FUNCTION process_pre_logbook_fn(_id integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.process_pre_logbook_fn(_id integer) IS 'Detect/Avoid/ignore/delete logbook stationary movement or time sync issue';


--
-- Name: process_stay_queue_fn(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.process_stay_queue_fn(_id integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: FUNCTION process_stay_queue_fn(_id integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.process_stay_queue_fn(_id integer) IS 'Update stay details, reverse_geocode_py_fn';


--
-- Name: process_vessel_queue_fn(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.process_vessel_queue_fn(_email text) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
       	vessel_rec record;
        user_settings jsonb;
        app_settings jsonb;
    BEGIN
        IF _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        SELECT * INTO vessel_rec
            FROM auth.vessels
            WHERE owner_email = _email;
        IF vessel_rec.owner_email IS NULL OR vessel_rec.owner_email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
            RETURN;
        END IF;
        -- Gather email and pushover app settings
        app_settings := get_app_settings_fn();
        -- set user email variable
        PERFORM set_config('user.email', vessel_rec.owner_email, false);
        -- Gather user settings
        user_settings := '{"email": "' || vessel_rec.owner_email || '", "boat": "' || vessel_rec.name || '"}';
        --user_settings := get_user_settings_from_vesselid_fn();
        -- Send notification email, pushover
        --PERFORM send_notification_fn('vessel'::TEXT, vessel_rec::RECORD);
        PERFORM send_email_py_fn('new_vessel'::TEXT, user_settings::JSONB, app_settings::JSONB);
        --PERFORM send_pushover_py_fn('vessel'::TEXT, user_settings::JSONB, app_settings::JSONB);
    END;
$$;


--
-- Name: FUNCTION process_vessel_queue_fn(_email text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.process_vessel_queue_fn(_email text) IS 'process new vessel notification, deprecated';


--
-- Name: radianttodegrees(numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.radianttodegrees(angle numeric) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN ROUND((((angle)::numeric * 57.2958) * 10) / 10);
END
$$;


--
-- Name: FUNCTION radianttodegrees(angle numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.radianttodegrees(angle numeric) IS 'convert radiant To Degrees';


--
-- Name: reverse_geocode_py_fn(text, numeric, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reverse_geocode_py_fn(geocoder text, lon numeric, lat numeric, OUT geo jsonb) RETURNS jsonb
    LANGUAGE plpython3u TRANSFORM FOR TYPE jsonb
    AS $_$
    import requests

    # Use the shared cache to avoid preparing the geocoder metadata
    if geocoder in SD:
        plan = SD[geocoder]
    # A prepared statement from Python
    else:
        plan = plpy.prepare("SELECT reverse_url AS url FROM geocoders WHERE name = $1", ["text"])
        SD[geocoder] = plan

    # Execute the statement with the geocoder param and limit to 1 result
    rv = plpy.execute(plan, [geocoder], 1)
    url = rv[0]['url']

    # Validate input
    if not lon or not lat:
        plpy.notice('reverse_geocode_py_fn Parameters [{}] [{}]'.format(lon, lat))
        plpy.error('Error missing parameters')
        return None

    def georeverse(geocoder, lon, lat, zoom="18"):
	    # Make the request to the geocoder API
	    # https://operations.osmfoundation.org/policies/nominatim/
	    headers = {"Accept-Language": "en-US,en;q=0.5", "User-Agent": "PostgSail", "From": "xbgmsharp@gmail.com"}
	    payload = {"lon": lon, "lat": lat, "format": "jsonv2", "zoom": zoom, "accept-language": "en"}
	    # https://nominatim.org/release-docs/latest/api/Reverse/
	    r = requests.get(url, headers=headers, params=payload)

	    # Parse response
	    # If name is null fallback to address field tags: neighbourhood,suburb
	    # if none repeat with lower zoom level
	    if r.status_code == 200 and "name" in r.json():
	      r_dict = r.json()
	      #plpy.notice('reverse_geocode_py_fn Parameters [{}] [{}] Response'.format(lon, lat, r_dict))
	      output = None
	      country_code = None
	      if "country_code" in r_dict["address"] and r_dict["address"]["country_code"]:
	        country_code = r_dict["address"]["country_code"]
	      if r_dict["name"]:
	        return { "name": r_dict["name"], "country_code": country_code }
	      elif "address" in r_dict and r_dict["address"]:
	        if "neighbourhood" in r_dict["address"] and r_dict["address"]["neighbourhood"]:
	            return { "name": r_dict["address"]["neighbourhood"], "country_code": country_code }
	        elif "hamlet" in r_dict["address"] and r_dict["address"]["hamlet"]:
	            return { "name": r_dict["address"]["hamlet"], "country_code": country_code }
	        elif "suburb" in r_dict["address"] and r_dict["address"]["suburb"]:
	            return { "name": r_dict["address"]["suburb"], "country_code": country_code }
	        elif "residential" in r_dict["address"] and r_dict["address"]["residential"]:
	            return { "name": r_dict["address"]["residential"], "country_code": country_code }
	        elif "village" in r_dict["address"] and r_dict["address"]["village"]:
	            return { "name": r_dict["address"]["village"], "country_code": country_code }
	        elif "town" in r_dict["address"] and r_dict["address"]["town"]:
	            return { "name": r_dict["address"]["town"], "country_code": country_code }
	        elif "amenity" in r_dict["address"] and r_dict["address"]["amenity"]:
	            return { "name": r_dict["address"]["amenity"], "country_code": country_code }
	        else:
	            if (zoom == 15):
	                plpy.notice('georeverse recursive retry with lower zoom than:[{}], Response [{}]'.format(zoom , r.json()))
	                return { "name": "n/a", "country_code": country_code }
	            else:
	                plpy.notice('georeverse recursive retry with lower zoom than:[{}], Response [{}]'.format(zoom , r.json()))
	                return georeverse(geocoder, lon, lat, 15)
	      else:
	        return { "name": "n/a", "country_code": country_code }
	    else:
	      plpy.warning('Failed to received a geo full address %s', r.json())
	      #plpy.error('Failed to received a geo full address %s', r.json())
	      return { "name": "unknown", "country_code": "unknown" }

    return georeverse(geocoder, lon, lat)
$_$;


--
-- Name: FUNCTION reverse_geocode_py_fn(geocoder text, lon numeric, lat numeric, OUT geo jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.reverse_geocode_py_fn(geocoder text, lon numeric, lat numeric, OUT geo jsonb) IS 'query reverse geo service to return location name using plpython3u';


--
-- Name: reverse_geoip_py_fn(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reverse_geoip_py_fn(_ip text) RETURNS jsonb
    LANGUAGE plpython3u TRANSFORM FOR TYPE jsonb IMMUTABLE STRICT
    AS $$
    """
    Return ipapi.co ip details
    """
    import requests
    import json

    # requests
    url = f'https://ipapi.co/{_ip}/json/'
    r = requests.get(url)
    #print(r.text)
    #plpy.notice('IP [{}] [{}]'.format(_ip, r.status_code))
    if r.status_code == 200:
        #plpy.notice('Got [{}] [{}]'.format(r.text, r.status_code))
        return r.json()
    else:
        plpy.error('Failed to get ip details')
    return {}
$$;


--
-- Name: FUNCTION reverse_geoip_py_fn(_ip text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.reverse_geoip_py_fn(_ip text) IS 'Retrieve reverse geo IP location via ipapi.co using plpython3u';


--
-- Name: run_cron_jobs(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.run_cron_jobs() RETURNS void
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: send_email_py_fn(text, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_email_py_fn(email_type text, _user jsonb, app jsonb) RETURNS void
    LANGUAGE plpython3u TRANSFORM FOR TYPE jsonb
    AS $_$
    # Import smtplib for the actual sending function
    import smtplib
    import requests

    # Import the email modules we need
    from email.message import EmailMessage
    from email.utils import formatdate,make_msgid
    from email.mime.text import MIMEText

    # Use the shared cache to avoid preparing the email metadata
    if email_type in SD:
        plan = SD[email_type]
    # A prepared statement from Python
    else:
        plan = plpy.prepare("SELECT * FROM email_templates WHERE name = $1", ["text"])
        SD[email_type] = plan

    # Execute the statement with the email_type param and limit to 1 result
    rv = plpy.execute(plan, [email_type], 1)
    email_subject = rv[0]['email_subject']
    email_content = rv[0]['email_content']

    # Replace fields using input jsonb obj
    if not _user or not app:
        plpy.notice('send_email_py_fn Parameters [{}] [{}]'.format(_user, app))
        plpy.error('Error missing parameters')
        return None

    if 'logbook_name' in _user and _user['logbook_name']:
        email_content = email_content.replace('__LOGBOOK_NAME__', str(_user['logbook_name']))
    if 'logbook_link' in _user and _user['logbook_link']:
        email_content = email_content.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'logbook_img' in _user and _user['logbook_img']:
        email_content = email_content.replace('__LOGBOOK_IMG__', str(_user['logbook_img']))
    if 'logbook_stats' in _user and _user['logbook_stats']:
        email_content = email_content.replace('__LOGBOOK_STATS__', str(_user['logbook_stats']))
    if 'video_link' in _user and _user['video_link']:
        email_content = email_content.replace('__VIDEO_LINK__', str(_user['video_link']))
    if 'recipient' in _user and _user['recipient']:
        email_content = email_content.replace('__RECIPIENT__', _user['recipient'])
    if 'boat' in _user and _user['boat']:
        email_content = email_content.replace('__BOAT__', _user['boat'])
    if 'badge' in _user and _user['badge']:
        email_content = email_content.replace('__BADGE_NAME__', _user['badge'])
    if 'otp_code' in _user and _user['otp_code']:
        email_content = email_content.replace('__OTP_CODE__', _user['otp_code'])
    if 'reset_qs' in _user and _user['reset_qs']:
        email_content = email_content.replace('__RESET_QS__', _user['reset_qs'])
    if 'alert' in _user and _user['alert']:
        email_content = email_content.replace('__ALERT__', _user['alert'])

    if 'app.url' in app and app['app.url']:
        email_content = email_content.replace('__APP_URL__', app['app.url'])

    email_from = 'root@localhost'
    if 'app.email_from' in app and app['app.email_from']:
        email_from = 'PostgSail <' + app['app.email_from'] + '>'
    #plpy.notice('Sending email from [{}] [{}]'.format(email_from, app['app.email_from']))

    email_to = 'root@localhost'
    if 'email' in _user and _user['email']:
        email_to = _user['email']
        #plpy.notice('Sending email to [{}] [{}]'.format(email_to, _user['email']))
    else:
        plpy.error('Error email to')
        return None

    if email_type == 'logbook':
        msg = EmailMessage()
        msg.set_content(email_content)
    else:
        msg = MIMEText(email_content, 'plain', 'utf-8')

    msg["Subject"] = email_subject
    msg["From"] = email_from
    msg["To"] = email_to
    msg["Date"] = formatdate()
    msg["Message-ID"] = make_msgid()

    if email_type == 'logbook' and 'logbook_img' in _user and _user['logbook_img']:
        # Create a Content-ID for the image
        image_cid = make_msgid()
        # Transform HTML template
        logbook_link = '{__APP_URL__}/log/{__LOGBOOK_LINK__}'.format( __APP_URL__=app['app.url'], __LOGBOOK_LINK__=str(_user['logbook_link']))
        timelapse_link = '{__APP_URL__}/timelapse/{__LOGBOOK_LINK__}'.format( __APP_URL__=app['app.url'], __LOGBOOK_LINK__=str(_user['logbook_link']))
        email_content = email_content.replace('\n', '<br/>')
        email_content = email_content.replace(logbook_link, '<a href="{logbook_link}">{logbook_link}</a>'.format(logbook_link=str(logbook_link)))
        email_content = email_content.replace(timelapse_link, '<a href="{timelapse_link}">{timelapse_link}</a>'.format(timelapse_link=str(timelapse_link)))
        email_content = email_content.replace(str(_user['logbook_name']), '<a href="{logbook_link}">{logbook_name}</a>'.format(logbook_link=str(logbook_link), logbook_name=str(_user['logbook_name'])))
        # Set an alternative html body
        msg.add_alternative("""\
<html>
    <body>
        <p>{email_content}</p>
        <img src="cid:{image_cid}">
    </body>
</html>
""".format(email_content=email_content, image_cid=image_cid[1:-1]), subtype='html')
        img_url = 'https://gis.openplotter.cloud/{}'.format(str(_user['logbook_img']))
        response = requests.get(img_url, stream=True)
        if response.status_code == 200:
            msg.get_payload()[1].add_related(response.raw.data,
                                            maintype='image', 
                                            subtype='png', 
                                            cid=image_cid)

    server_smtp = 'localhost'
    if 'app.email_server' in app and app['app.email_server']:
        server_smtp = app['app.email_server']
    #plpy.notice('Sending server [{}] [{}]'.format(server_smtp, app['app.email_server']))

    # Send the message via our own SMTP server.
    try:
        # send your message with credentials specified above
        with smtplib.SMTP(server_smtp, 587) as server:
            if 'app.email_user' in app and app['app.email_user'] \
                and 'app.email_pass' in app and app['app.email_pass']:
                server.starttls()
                server.login(app['app.email_user'], app['app.email_pass'])
            #server.send_message(msg)
            server.sendmail(msg["From"], msg["To"], msg.as_string())
            server.quit()
        # tell the script to report if your message was sent or which errors need to be fixed
        plpy.notice('Sent email successfully to [{}] [{}]'.format(msg["To"], msg["Subject"]))
        return None
    except OSError as error:
        plpy.error('OS Error occurred: ' + str(error))
    except smtplib.SMTPConnectError:
        plpy.error('Failed to connect to the server. Bad connection settings?')
    except smtplib.SMTPServerDisconnected:
        plpy.error('Failed to connect to the server. Wrong user/password?')
    except smtplib.SMTPException as e:
        plpy.error('SMTP error occurred: ' + str(e))
$_$;


--
-- Name: FUNCTION send_email_py_fn(email_type text, _user jsonb, app jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.send_email_py_fn(email_type text, _user jsonb, app jsonb) IS 'Send email notification using plpython3u';


--
-- Name: send_notification_fn(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_notification_fn(email_type text, user_settings jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        app_settings JSONB;
        _email_notifications BOOLEAN := False;
        _phone_notifications BOOLEAN := False;
        _pushover_user_key TEXT := NULL;
        pushover_settings JSONB := NULL;
        _telegram_notifications BOOLEAN := False;
        _telegram_chat_id TEXT := NULL;
        telegram_settings JSONB := NULL;
		_email TEXT := NULL;
    BEGIN
        -- TODO input check
        --RAISE NOTICE '--> send_notification_fn type [%]', email_type;
        -- Gather notification app settings, eg: email, pushover, telegram
        app_settings := get_app_settings_fn();
        --RAISE NOTICE '--> send_notification_fn app_settings [%]', app_settings;
        --RAISE NOTICE '--> user_settings [%]', user_settings->>'email'::TEXT;

        -- Gather notifications settings and merge with user settings
        -- Send notification email
        SELECT preferences['email_notifications'] INTO _email_notifications
            FROM auth.accounts a
            WHERE a.email = user_settings->>'email'::TEXT;
        RAISE NOTICE '--> send_notification_fn email_notifications [%]', _email_notifications;
        -- If email server app settings set and if email user settings set
        IF app_settings['app.email_server'] IS NOT NULL AND _email_notifications IS True THEN
            PERFORM send_email_py_fn(email_type::TEXT, user_settings::JSONB, app_settings::JSONB);
        END IF;

        -- Send notification pushover
        SELECT preferences['phone_notifications'],preferences->>'pushover_user_key' INTO _phone_notifications,_pushover_user_key
            FROM auth.accounts a
            WHERE a.email = user_settings->>'email'::TEXT;
        RAISE NOTICE '--> send_notification_fn phone_notifications [%]', _phone_notifications;
        -- If pushover app settings set and if pushover user settings set
        IF app_settings['app.pushover_app_token'] IS NOT NULL AND _phone_notifications IS True AND _pushover_user_key IS NOT NULL THEN
            SELECT json_build_object('pushover_user_key', _pushover_user_key) into pushover_settings;
            SELECT user_settings::JSONB || pushover_settings::JSONB into user_settings;
            --RAISE NOTICE '--> send_notification_fn user_settings + pushover [%]', user_settings;
            PERFORM send_pushover_py_fn(email_type::TEXT, user_settings::JSONB, app_settings::JSONB);
        END IF;

        -- Send notification telegram
        SELECT (preferences->'telegram'->'chat'->'id') IS NOT NULL,preferences['telegram']['chat']['id'] INTO _telegram_notifications,_telegram_chat_id
            FROM auth.accounts a
            WHERE a.email = user_settings->>'email'::TEXT;
        RAISE NOTICE '--> send_notification_fn telegram_notifications [%]', _telegram_notifications;
        -- If telegram app settings set and if telegram user settings set
        IF app_settings['app.telegram_bot_token'] IS NOT NULL AND _telegram_notifications IS True AND _phone_notifications IS True THEN
            SELECT json_build_object('telegram_chat_id', _telegram_chat_id) into telegram_settings;
            SELECT user_settings::JSONB || telegram_settings::JSONB into user_settings;
            --RAISE NOTICE '--> send_notification_fn user_settings + telegram [%]', user_settings;
            PERFORM send_telegram_py_fn(email_type::TEXT, user_settings::JSONB, app_settings::JSONB);
        END IF;
    END;
$$;


--
-- Name: FUNCTION send_notification_fn(email_type text, user_settings jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.send_notification_fn(email_type text, user_settings jsonb) IS 'Send notifications via email, pushover, telegram to user base on user preferences';


--
-- Name: send_pushover_py_fn(text, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_pushover_py_fn(message_type text, _user jsonb, app jsonb) RETURNS void
    LANGUAGE plpython3u TRANSFORM FOR TYPE jsonb
    AS $_$
    """
    https://pushover.net/api#messages
    Send a notification to a pushover user
    """
    import requests

    # Use the shared cache to avoid preparing the email metadata
    if message_type in SD:
        plan = SD[message_type]
    # A prepared statement from Python
    else:
        plan = plpy.prepare("SELECT * FROM email_templates WHERE name = $1", ["text"])
        SD[message_type] = plan

    # Execute the statement with the message_type param and limit to 1 result
    rv = plpy.execute(plan, [message_type], 1)
    pushover_title = rv[0]['pushover_title']
    pushover_message = rv[0]['pushover_message']

    # Replace fields using input jsonb obj
    if 'logbook_name' in _user and _user['logbook_name']:
        pushover_message = pushover_message.replace('__LOGBOOK_NAME__', _user['logbook_name'])
    if 'logbook_link' in _user and _user['logbook_link']:
        pushover_message = pushover_message.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'video_link' in _user and _user['video_link']:
        pushover_message = pushover_message.replace('__VIDEO_LINK__', str( _user['video_link']))
    if 'recipient' in _user and _user['recipient']:
        pushover_message = pushover_message.replace('__RECIPIENT__', _user['recipient'])
    if 'boat' in _user and _user['boat']:
        pushover_message = pushover_message.replace('__BOAT__', _user['boat'])
    if 'badge' in _user and _user['badge']:
        pushover_message = pushover_message.replace('__BADGE_NAME__', _user['badge'])
    if 'alert' in _user and _user['alert']:
        pushover_message = pushover_message.replace('__ALERT__', _user['alert'])

    if 'app.url' in app and app['app.url']:
        pushover_message = pushover_message.replace('__APP_URL__', app['app.url'])

    pushover_token = None
    if 'app.pushover_app_token' in app and app['app.pushover_app_token']:
        pushover_token = app['app.pushover_app_token']
    else:
        plpy.error('Error no pushover token defined, check app settings')
        return None
    pushover_user = None
    if 'pushover_user_key' in _user and _user['pushover_user_key']:
        pushover_user = _user['pushover_user_key']
    else:
        plpy.error('Error no pushover user token defined, check user settings')
        return None

    if message_type == 'logbook' and 'logbook_img' in _user and _user['logbook_img']:
        # Send notification with gis image logbook as attachment
        img_url = 'https://gis.openplotter.cloud/{}'.format(str(_user['logbook_img']))
        response = requests.get(img_url, stream=True)
        if response.status_code == 200:
            r = requests.post("https://api.pushover.net/1/messages.json", data = {
                "token": pushover_token,
                "user": pushover_user,
                "title": pushover_title,
                "message": pushover_message
            }, files = {
                "attachment": (str(_user['logbook_img']), response.raw.data, "image/png")
            })
    else:
        r = requests.post("https://api.pushover.net/1/messages.json", data = {
                "token": pushover_token,
                "user": pushover_user,
                "title": pushover_title,
                "message": pushover_message
        })

    #print(r.text)
    # Return ?? or None if not found
    #plpy.notice('Sent pushover successfully to [{}] [{}]'.format(r.text, r.status_code))
    if r.status_code == 200:
        plpy.notice('Sent pushover successfully to [{}] [{}] [{}]'.format(pushover_user, pushover_title, r.text))
    else:
        plpy.error('Failed to send pushover')
    return None
$_$;


--
-- Name: FUNCTION send_pushover_py_fn(message_type text, _user jsonb, app jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.send_pushover_py_fn(message_type text, _user jsonb, app jsonb) IS 'Send pushover notification using plpython3u';


--
-- Name: send_telegram_py_fn(text, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.send_telegram_py_fn(message_type text, _user jsonb, app jsonb) RETURNS void
    LANGUAGE plpython3u TRANSFORM FOR TYPE jsonb
    AS $_$
    """
    https://core.telegram.org/bots/api#sendmessage
    Send a message to a telegram user or group specified on chatId
    chat_id must be a number!
    """
    import requests
    import json

    # Use the shared cache to avoid preparing the email metadata
    if message_type in SD:
        plan = SD[message_type]
    # A prepared statement from Python
    else:
        plan = plpy.prepare("SELECT * FROM email_templates WHERE name = $1", ["text"])
        SD[message_type] = plan

    # Execute the statement with the message_type param and limit to 1 result
    rv = plpy.execute(plan, [message_type], 1)
    telegram_title = rv[0]['pushover_title']
    telegram_message = rv[0]['pushover_message']

    # Replace fields using input jsonb obj
    if 'logbook_name' in _user and _user['logbook_name']:
        telegram_message = telegram_message.replace('__LOGBOOK_NAME__', _user['logbook_name'])
    if 'logbook_link' in _user and _user['logbook_link']:
        telegram_message = telegram_message.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'video_link' in _user and _user['video_link']:
        telegram_message = telegram_message.replace('__VIDEO_LINK__', str( _user['video_link']))
    if 'recipient' in _user and _user['recipient']:
        telegram_message = telegram_message.replace('__RECIPIENT__', _user['recipient'])
    if 'boat' in _user and _user['boat']:
        telegram_message = telegram_message.replace('__BOAT__', _user['boat'])
    if 'badge' in _user and _user['badge']:
        telegram_message = telegram_message.replace('__BADGE_NAME__', _user['badge'])
    if 'alert' in _user and _user['alert']:
        telegram_message = telegram_message.replace('__ALERT__', _user['alert'])

    if 'app.url' in app and app['app.url']:
        telegram_message = telegram_message.replace('__APP_URL__', app['app.url'])

    telegram_token = None
    if 'app.telegram_bot_token' in app and app['app.telegram_bot_token']:
        telegram_token = app['app.telegram_bot_token']
    else:
        plpy.error('Error no telegram token defined, check app settings')
        return None
    telegram_chat_id = None
    if 'telegram_chat_id' in _user and _user['telegram_chat_id']:
        telegram_chat_id = _user['telegram_chat_id']
    else:
        plpy.error('Error no telegram user token defined, check user settings')
        return None

    # sendMessage via requests
    headers = {'Content-Type': 'application/json',
            'Proxy-Authorization': 'Basic base64'}
    data_dict = {'chat_id': telegram_chat_id,
                'text': telegram_message,
                'parse_mode': 'HTML',
                'disable_notification': False}
    data = json.dumps(data_dict)
    url = f'https://api.telegram.org/bot{telegram_token}/sendMessage'
    r = requests.post(url, data=data, headers=headers)
    if message_type == 'logbook' and 'logbook_img' in _user and _user['logbook_img']:
        # Send gis image logbook
        # https://core.telegram.org/bots/api#sendphoto
        data_dict['photo'] = 'https://gis.openplotter.cloud/{}'.format(str(_user['logbook_img']))
        del data_dict['text']
        data = json.dumps(data_dict)
        url = f'https://api.telegram.org/bot{telegram_token}/sendPhoto'
        r = requests.post(url, data=data, headers=headers)

    #print(r.text)
    # Return something boolean?
    #plpy.notice('Sent telegram successfully to [{}] [{}]'.format(r.text, r.status_code))
    if r.status_code == 200:
        plpy.notice('Sent telegram successfully to [{}] [{}] [{}]'.format(telegram_chat_id, telegram_title, r.text))
    else:
        plpy.error('Failed to send telegram')
    return None
$_$;


--
-- Name: FUNCTION send_telegram_py_fn(message_type text, _user jsonb, app jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.send_telegram_py_fn(message_type text, _user jsonb, app jsonb) IS 'Send a message to a telegram user or group specified on chatId using plpython3u';


--
-- Name: set_vessel_settings_from_vesselid_fn(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_vessel_settings_from_vesselid_fn(vesselid text, OUT vessel_settings jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
    DECLARE
    BEGIN
        -- If vessel_id is not NULL
        IF vesselid IS NULL OR vesselid = '' THEN
            RAISE WARNING '-> set_vessel_settings_from_vesselid_fn invalid input %', vesselid;
        END IF;
        SELECT
            json_build_object(
                    'name' , v.name,
                    'vessel_id', v.vesselid,
                    'client_id', m.client_id
                    ) INTO vessel_settings
            FROM auth.accounts a, auth.vessels v, api.metadata m
            WHERE m.vessel_id = v.vessel_id
                AND m.vessel_id = vesselid;
        PERFORM set_config('vessel.name', vessel_settings->>'name'::TEXT, false);
        PERFORM set_config('vessel.client_id', vessel_settings->>'client_id'::TEXT, false);
        PERFORM set_config('vessel.id', vessel_settings->>'vessel_id'::TEXT, false);
    END;
$$;


--
-- Name: FUNCTION set_vessel_settings_from_vesselid_fn(vesselid text, OUT vessel_settings jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.set_vessel_settings_from_vesselid_fn(vesselid text, OUT vessel_settings jsonb) IS 'set_vessel settings details from a vesselid, initiate for process queue functions';


--
-- Name: split_logbook_by24h_fn(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.split_logbook_by24h_fn(_id integer) RETURNS TABLE(id integer, name text, segment_num integer, period_start timestamp with time zone, period_end timestamp with time zone, duration interval, distance numeric, avg_speed numeric, max_speed numeric, avg_tws numeric, max_tws numeric, avg_aws numeric, max_aws numeric, trajectory public.geometry, geojson jsonb)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE time_splits AS (
        SELECT
            l.id,
            l.trip,
            l.trip_tws,
            l.trip_twd,
            l.trip_aws,
            startTimestamp(l.trip) AS period_start,
            LEAST(startTimestamp(l.trip) + interval '24 hours', endTimestamp(l.trip)) AS period_end,
            0 AS segment_num
        FROM api.logbook l
        WHERE l.id = _id

        UNION ALL

        SELECT
            ts.id,
            ts.trip,
            ts.trip_tws,
            ts.trip_twd,
            ts.trip_aws,
            ts.period_end,
            LEAST(ts.period_end + interval '24 hours', endTimestamp(ts.trip)),
            ts.segment_num + 1
        FROM time_splits ts
        WHERE ts.period_end < endTimestamp(ts.trip)
    ),
    segmented_trajectories AS (
        SELECT
            l.id,
            l.name,
            ts.segment_num,
            ts.period_start,
            ts.period_end,
            atTime(l.trip, span(ts.period_start, ts.period_end, true, true)) AS segment_trip,
            atTime(l.trip_tws, span(ts.period_start, ts.period_end, true, true)) AS segment_tws,
            atTime(l.trip_twd, span(ts.period_start, ts.period_end, true, true)) AS segment_twd,
            atTime(l.trip_aws, span(ts.period_start, ts.period_end, true, true)) AS segment_aws
        FROM time_splits ts
        JOIN api.logbook l ON l.id = ts.id
    )
    SELECT
        st.id,
        st.name,
        st.segment_num,
        st.period_start,
        st.period_end,
        (st.period_end - st.period_start) AS duration,
        (length(st.segment_trip) / 1852)::numeric(10,2) AS distance,
        (twavg(speed(st.segment_trip)) * 1.94384)::numeric(6,2) AS avg_speed,
        (maxValue(speed(st.segment_trip)) * 1.94384)::numeric(6,2) AS max_speed,
        twavg(st.segment_tws)::numeric(6,2) AS avg_tws,
        maxValue(st.segment_tws)::numeric(6,2) AS max_tws,
        twavg(st.segment_aws)::numeric(6,2) AS avg_aws,
        maxValue(st.segment_aws)::numeric(6,2) AS max_aws,
        trajectory(st.segment_trip)::geometry,
        ST_AsGeoJSON(trajectory(st.segment_trip))::jsonb
    FROM segmented_trajectories st
    WHERE st.segment_trip IS NOT NULL;
END;
$$;


--
-- Name: FUNCTION split_logbook_by24h_fn(_id integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.split_logbook_by24h_fn(_id integer) IS 'Split a logbook trip into multiple segments of maximum 24 hours each';


--
-- Name: split_logbook_by24h_geojson_fn(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.split_logbook_by24h_geojson_fn(_id integer) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
BEGIN
	RETURN (
    WITH RECURSIVE time_splits AS (
        SELECT
            l.id,
            l.trip,
            l.trip_tws,
            l.trip_aws,
            startTimestamp(l.trip) AS period_start,
            LEAST(startTimestamp(l.trip) + interval '24 hours', endTimestamp(l.trip)) AS period_end,
            0 AS segment_num
        FROM api.logbook l
        WHERE l.id = _id

        UNION ALL

        SELECT
            id,
            trip,
            trip_tws,
            trip_aws,
            period_end,
            LEAST(period_end + interval '24 hours', endTimestamp(trip)),
            segment_num + 1
        FROM time_splits
        WHERE period_end < endTimestamp(trip)
    ),
    segmented_trajectories AS (
        SELECT
            l.id,
            l.name,
            ts.segment_num,
            ts.period_start,
            ts.period_end,
            atTime(l.trip, span(ts.period_start, ts.period_end, true, true)) AS segment_trip,
            atTime(l.trip_tws, span(ts.period_start, ts.period_end, true, true)) AS segment_tws,
            atTime(l.trip_aws, span(ts.period_start, ts.period_end, true, true)) AS segment_aws
        FROM time_splits ts
        JOIN api.logbook l ON l.id = ts.id
    ),
    segment_stats AS (
        SELECT
            id,
            name,
            segment_num,
            period_start,
            period_end,
            (period_end - period_start) AS duration,
            (length(segment_trip)/1852)::NUMERIC(10,2) AS distance,
            (twavg(speed(segment_trip)) * 1.94384)::NUMERIC(6,2) AS avg_speed,
            (maxValue(speed(segment_trip)) * 1.94384)::NUMERIC(6,2) AS max_speed,
            -- True Wind Speed stats (already in knots)
            twavg(segment_tws)::NUMERIC(6,2) AS avg_tws,
            maxValue(segment_tws)::NUMERIC(6,2) AS max_tws,
            -- Apparent Wind Speed stats (already in knots)
            twavg(segment_aws)::NUMERIC(6,2) AS avg_aws,
            maxValue(segment_aws)::NUMERIC(6,2) AS max_aws,
            ST_AsGeoJSON(trajectory(segment_trip))::jsonb AS geojson
        FROM segmented_trajectories
        WHERE segment_trip IS NOT NULL
    )
    SELECT
        jsonb_build_object(
            'type', 'FeatureCollection',
            'features', jsonb_agg(
                jsonb_build_object(
                    'type', 'Feature',
                    'properties', jsonb_build_object(
                        'id', id,
                        'name', name,
                        'segment_num', segment_num,
                        'period_start', period_start,
                        'period_end', period_end,
                        'duration', duration,
                        'distance', distance,
                        'avg_speed', avg_speed,
                        'max_speed', max_speed,
                        'avg_tws', avg_tws,
                        'max_tws', max_tws,
                        'avg_aws', avg_aws,
                        'max_aws', max_aws
                    ),
                    'geometry', geojson
                ) ORDER BY segment_num
            )
        ) AS geojson_output
    FROM segment_stats
	);
END;
$$;


--
-- Name: FUNCTION split_logbook_by24h_geojson_fn(_id integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.split_logbook_by24h_geojson_fn(_id integer) IS 'Split a logbook trip into multiple segments of maximum 24 hours each, return a GeoJSON FeatureCollection';


--
-- Name: stay_active_geojson_fn(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stay_active_geojson_fn(_time timestamp with time zone DEFAULT now(), OUT _track_geojson jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
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
                'anchor', l.metrics->'anchor',
                'status', COALESCE(status, NULL::text)
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
$$;


--
-- Name: FUNCTION stay_active_geojson_fn(_time timestamp with time zone, OUT _track_geojson jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.stay_active_geojson_fn(_time timestamp with time zone, OUT _track_geojson jsonb) IS 'Create a GeoJSON with a feature Point with the last position and stay details';


--
-- Name: stay_completed_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stay_completed_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    DECLARE
    BEGIN
        RAISE NOTICE 'stay_completed_trigger_fn [%]', OLD;
        RAISE NOTICE 'stay_completed_trigger_fn [%] [%]', OLD.departed, NEW.departed;
        -- Add stay entry to process queue for later processing
        --IF ( OLD.departed <> NEW.departed ) THEN
            INSERT INTO process_queue (channel, payload, stored, ref_id)
                VALUES ('new_stay', NEW.id, NOW(), current_setting('vessel.id', true));
        --END IF;
        RETURN OLD; -- result is ignored since this is an AFTER trigger
    END;
$$;


--
-- Name: FUNCTION stay_completed_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.stay_completed_trigger_fn() IS 'Automatic process_queue for completed stay.departed';


--
-- Name: stay_delete_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stay_delete_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RAISE NOTICE 'stay_delete_trigger_fn [%]', OLD;
    -- If api.stays is deleted,
    -- Delete process_queue references
    DELETE FROM public.process_queue p
        WHERE p.payload = OLD.id::TEXT
            AND p.ref_id = OLD.vessel_id
            AND p.channel LIKE '%_stays';
    RETURN OLD;
END;
$$;


--
-- Name: FUNCTION stay_delete_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.stay_delete_trigger_fn() IS 'When stays is delete, process_queue references need to deleted as well.';


--
-- Name: stay_in_progress_fn(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.stay_in_progress_fn(_vessel_id text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
    DECLARE
        stay_id INT := NULL;
    BEGIN
        SELECT id INTO stay_id
                FROM api.stays s
                WHERE s.vessel_id IS NOT NULL
                    AND s.vessel_id = _vessel_id
                    AND active IS true
                LIMIT 1;
        RETURN stay_id;
    END;
$$;


--
-- Name: FUNCTION stay_in_progress_fn(_vessel_id text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.stay_in_progress_fn(_vessel_id text) IS 'stay_in_progress';


--
-- Name: timestamp_from_uuid_v7(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.timestamp_from_uuid_v7(_uuid uuid) RETURNS timestamp without time zone
    LANGUAGE sql IMMUTABLE STRICT LEAKPROOF PARALLEL SAFE
    AS $$
  SELECT to_timestamp(('x0000' || substr(_uuid::text, 1, 8) || substr(_uuid::text, 10, 4))::bit(64)::bigint::numeric / 1000);
$$;


--
-- Name: FUNCTION timestamp_from_uuid_v7(_uuid uuid); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.timestamp_from_uuid_v7(_uuid uuid) IS 'extract the timestamp from the uuid.';


--
-- Name: trip_in_progress_fn(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trip_in_progress_fn(_vessel_id text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
    DECLARE
        logbook_id INT := NULL;
    BEGIN
        SELECT id INTO logbook_id
            FROM api.logbook l
            WHERE l.vessel_id IS NOT NULL
                AND l.vessel_id = _vessel_id
                AND active IS true
            LIMIT 1;
        RETURN logbook_id;
    END;
$$;


--
-- Name: FUNCTION trip_in_progress_fn(_vessel_id text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.trip_in_progress_fn(_vessel_id text) IS 'trip_in_progress';


--
-- Name: update_logbook_with_geojson_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_logbook_with_geojson_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    geojson JSONB;
    feature JSONB;
BEGIN
    -- Parse the incoming GeoJSON data from the track_geojson column
    geojson := NEW.track_geojson::jsonb;

    -- Extract the first feature (assume it is the LineString)
    feature := geojson->'features'->0;

	IF geojson IS NOT NULL AND feature IS NOT NULL AND (feature->'properties' ? 'x-update') THEN

	    -- Get properties from the feature to extract avg_speed, and max_speed
	    NEW.avg_speed := (feature->'properties'->>'avg_speed')::FLOAT;
	    NEW.max_speed := (feature->'properties'->>'max_speed')::FLOAT;
        NEW.max_wind_speed := (feature->'properties'->>'max_wind_speed')::FLOAT;
	    NEW.extra := jsonb_set( NEW.extra,
				      '{avg_wind_speed}',
				      to_jsonb((feature->'properties'->>'avg_wind_speed')::FLOAT),
				      true  -- this flag means it will create the key if it does not exist
				    );

	    -- Calculate the LineString's actual spatial distance
	    NEW.track_geom := ST_GeomFromGeoJSON(feature->'geometry'::text);
	    NEW.distance := TRUNC (ST_Length(NEW.track_geom,false)::INT * 0.0005399568, 4);  -- convert to NM

	END IF;
    RETURN NEW;
END;
$$;


--
-- Name: FUNCTION update_logbook_with_geojson_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_logbook_with_geojson_trigger_fn() IS 'Extracts specific properties (distance, duration, avg_speed, max_speed) from a geometry LINESTRING part of a GeoJSON FeatureCollection, and then updates a column in a table named logbook';


--
-- Name: update_metadata_configuration_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_metadata_configuration_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


--
-- Name: FUNCTION update_metadata_configuration_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_metadata_configuration_trigger_fn() IS 'Update the configuration field with current date in ISO format';


--
-- Name: update_metadata_userdata_added_at_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_metadata_userdata_added_at_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Only update user_data if it's a JSONB object and has changed
  IF NEW.user_data IS NOT NULL 
      AND NEW.user_data IS DISTINCT FROM OLD.user_data
      AND jsonb_typeof(NEW.user_data) = 'object' THEN
    -- Check if polar data has changed in user_data
    IF (NEW.user_data->'polar') IS DISTINCT FROM (OLD.user_data->'polar') THEN
      NEW.user_data := jsonb_set(
        COALESCE(NEW.user_data, '{}'::jsonb),
        '{polar_updated_at}',
        to_jsonb(to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
      );
    END IF;

    -- Check if images data has changed in user_data
    IF (NEW.user_data->'images') IS DISTINCT FROM (OLD.user_data->'images') THEN
      NEW.user_data := jsonb_set(
        COALESCE(NEW.user_data, '{}'::jsonb),
        '{image_updated_at}',
        to_jsonb(to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION update_metadata_userdata_added_at_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_metadata_userdata_added_at_trigger_fn() IS 'Update polar_updated_at and image_updated_at timestamps within user_data jsonb when polar or images change';


--
-- Name: update_tbl_userdata_added_at_trigger_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_tbl_userdata_added_at_trigger_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  -- Only update user_data if it's a JSONB object and has changed
  IF NEW.user_data IS NOT NULL 
      AND NEW.user_data IS DISTINCT FROM OLD.user_data
      AND jsonb_typeof(NEW.user_data) = 'object' THEN
    -- Check if images data has changed in user_data
    IF (NEW.user_data->'images') IS DISTINCT FROM (OLD.user_data->'images') THEN
      NEW.user_data := jsonb_set(
        COALESCE(NEW.user_data, '{}'::jsonb),
        '{image_updated_at}',
        to_jsonb(to_char(NOW(), 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: FUNCTION update_tbl_userdata_added_at_trigger_fn(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.update_tbl_userdata_added_at_trigger_fn() IS 'Update image_updated_at timestamps within user_data jsonb when images change';


--
-- Name: urlencode_py_fn(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.urlencode_py_fn(uri text) RETURNS text
    LANGUAGE plpython3u IMMUTABLE STRICT
    AS $$
    import urllib.parse
    return urllib.parse.quote(uri, safe="");
$$;


--
-- Name: FUNCTION urlencode_py_fn(uri text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.urlencode_py_fn(uri text) IS 'python url encode using plpython3u';


--
-- Name: urlescape_py_fn(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.urlescape_py_fn(original text) RETURNS text
    LANGUAGE plpython3u IMMUTABLE STRICT
    AS $$
import urllib.parse
return urllib.parse.quote(original);
$$;


--
-- Name: FUNCTION urlescape_py_fn(original text); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.urlescape_py_fn(original text) IS 'URL-encoding VARCHAR and TEXT values using plpython3u';


--
-- Name: uuid_generate_v7(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.uuid_generate_v7() RETURNS uuid
    LANGUAGE plpgsql
    AS $$
begin
  -- use random v4 uuid as starting point (which has the same variant we need)
  -- then overlay timestamp
  -- then set version 7 by flipping the 2 and 1 bit in the version 4 string
  return encode(
    set_bit(
      set_bit(
        overlay(uuid_send(gen_random_uuid())
                placing substring(int8send(floor(extract(epoch from clock_timestamp()) * 1000)::bigint) from 3)
                from 1 for 6
        ),
        52, 1
      ),
      53, 1
    ),
    'hex')::uuid;
end
$$;


--
-- Name: FUNCTION uuid_generate_v7(); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.uuid_generate_v7() IS 'Generate UUID v7, Based off IETF draft, https://datatracker.ietf.org/doc/draft-peabody-dispatch-new-uuid-format/';


--
-- Name: valtopercent(numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.valtopercent(val numeric) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    RETURN (val * 100);
END
$$;


--
-- Name: FUNCTION valtopercent(val numeric); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.valtopercent(val numeric) IS 'convert radiant To Degrees';


--
-- Name: windy_pws_py_fn(jsonb, jsonb, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.windy_pws_py_fn(metric jsonb, _user jsonb, app jsonb) RETURNS jsonb
    LANGUAGE plpython3u TRANSFORM FOR TYPE jsonb STRICT
    AS $$
    """
    Send environment data from boat instruments to Windy as a Personal Weather Station (PWS).
    Supports station creation and observation updates using Windy Stations API v2.
    Uses API key for authentication and supports historical data via dateutc.
    """
    import requests
    import json
    import decimal
    from datetime import datetime, timedelta

    # Validate inputs
    if not 'app.windy_apikey' in app or not app['app.windy_apikey']:
        plpy.error('Error: No Windy API key defined. Check app settings.')
        return None

    if not 'station' in metric or not metric['station']:
        plpy.error('Error: No station ID defined in metrics.')
        return None

    if not _user:
        plpy.error('Error: No user defined. Check user settings.')
        return None

    # Check if station exists in user settings
    station_exists = 'settings' in _user and 'windy' in _user['settings'] and 'windy_password_station' in _user['settings']

    if not station_exists:
        # Create station using API key
        station_data = {
            "name": metric['name'],
            "share_option": "public",
            "lat": float(decimal.Decimal(metric['lat'])),
            "lon": float(decimal.Decimal(metric['lon'])),
            "elev_m": 1,
            "agl_wind": 10,
            "station_type": "SignalK PostgSail Plugin",
            "operator_text": f"Maintained by {metric['name']} via PostgSail",
            "operator_url": f"https://iot.openplotter.cloud/{metric['name']}/monitoring"
        }
        plpy.notice(f'Windy Personal Weather Station create station: {station_data}')
        headers = {
            'User-Agent': 'PostgSail',
            'From': 'xbgmsharp@gmail.com',
            'windy-api-key': app['app.windy_apikey'],
            'Content-Type': 'application/json'
        }

        api_url = 'https://stations.windy.com/api/v2/pws'

        try:
            r = requests.post(api_url, json=station_data, headers=headers, timeout=(5, 60))
            if r.status_code == 201:
                plpy.notice(f'Windy Personal Weather Station created successfully.')
                return r.json()
            else:
                plpy.error(f'Failed to create station. Status code: {r.status_code}, Response: {r.text}')
                return None
        except Exception as e:
            plpy.error(f'Error creating station: {str(e)}')
            return None
    else:
        # Send observation update using API key
        params = {
            'id': metric['station'],
            'time': metric['dateutc'],
            'softwaretype': 'PostgSail',
        }

        # Add observation parameters
        if 'temp' in metric and metric['temp']:
            params['temp'] = float(decimal.Decimal(metric['temp']))

        if 'wind' in metric and metric['wind']:
            params['wind'] = round(float(decimal.Decimal(metric['wind'])), 1)

        if 'gust' in metric and metric['gust']:
            params['gust'] = round(float(decimal.Decimal(metric['gust'])), 1)

        if 'winddir' in metric and metric['winddir']:
            params['winddir'] = int(decimal.Decimal(metric['winddir']))

        if 'pressure' in metric and metric['pressure']:
            params['pressure'] = int(decimal.Decimal(metric['pressure']))

        if 'rh' in metric and metric['rh']:
            params['humidity'] = float(decimal.Decimal(metric['rh']))

        params['softwaretype'] = f"Vessel {metric['name']} via PostgSail"
        plpy.notice(f'Windy Personal Weather Station update observation: {params}')

        headers = {
            'User-Agent': 'PostgSail',
            'From': 'xbgmsharp@gmail.com',
            'Authorization': f"Bearer {_user['settings']['windy_password_station']}"
        }

        api_url = 'https://stations.windy.com/api/v2/observation/update'

        try:
            r = requests.get(api_url, params=params, headers=headers, timeout=(5, 60))
            if r.status_code == 200:
                plpy.notice(f'Data sent successfully to Windy')
                return json.dumps({
                    'status': 'success',
                    'last_sent': metric['dateutc']
                })
            else:
                plpy.error(f'Failed to send data. Status code: {r.status_code}, Response: {r.text}')
                return None
        except Exception as e:
            plpy.error(f'Error sending data to Windy: {str(e)}')
            return None
$$;


--
-- Name: FUNCTION windy_pws_py_fn(metric jsonb, _user jsonb, app jsonb); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.windy_pws_py_fn(metric jsonb, _user jsonb, app jsonb) IS 'Forward vessel data to Windy as a Personal Weather Station using plpython3u';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: process_queue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.process_queue (
    id integer NOT NULL,
    channel text NOT NULL,
    payload text NOT NULL,
    ref_id text NOT NULL,
    stored timestamp with time zone NOT NULL,
    processed timestamp with time zone
);

ALTER TABLE ONLY public.process_queue FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE process_queue; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.process_queue IS 'process queue for async job';


--
-- Name: COLUMN process_queue.ref_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.process_queue.ref_id IS 'either user_id or vessel_id';


--
-- Name: eventlogs_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.eventlogs_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT id,
    channel,
    payload,
    ref_id,
    stored,
    processed
   FROM public.process_queue pq
  WHERE ((processed IS NOT NULL) AND (channel <> 'new_stay'::text) AND (channel <> 'pre_logbook'::text) AND (channel <> 'post_logbook'::text) AND ((ref_id = current_setting('user.id'::text, false)) OR (ref_id = current_setting('vessel.id'::text, true))))
  ORDER BY id DESC;


--
-- Name: VIEW eventlogs_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.eventlogs_view IS 'Event logs view';


--
-- Name: metrics; Type: TABLE; Schema: api; Owner: -
--

CREATE TABLE api.metrics (
    "time" timestamp with time zone NOT NULL,
    client_id text,
    vessel_id text NOT NULL,
    latitude double precision,
    longitude double precision,
    speedoverground double precision,
    courseovergroundtrue double precision,
    windspeedapparent double precision,
    anglespeedapparent double precision,
    status text,
    metrics jsonb
);

SELECT create_hypertable('api.metrics', 'time', chunk_time_interval => INTERVAL '7 days');

ALTER TABLE api.metrics FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE metrics; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TABLE api.metrics IS 'Stores metrics from vessel';


--
-- Name: COLUMN metrics.client_id; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.metrics.client_id IS 'Deprecated client_id to be removed';


--
-- Name: COLUMN metrics.vessel_id; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.metrics.vessel_id IS 'Unique identifier for the vessel associated with the api.metadata entry';


--
-- Name: COLUMN metrics.latitude; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.metrics.latitude IS 'With CONSTRAINT but allow NULL value to be ignored silently by trigger';


--
-- Name: COLUMN metrics.longitude; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.metrics.longitude IS 'With CONSTRAINT but allow NULL value to be ignored silently by trigger';


--
-- Name: metrics_explore_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.metrics_explore_view WITH (security_invoker='true', security_barrier='true') AS
 WITH raw_metrics AS (
         SELECT m."time",
            m.metrics
           FROM api.metrics m
          ORDER BY m."time" DESC
         LIMIT 1
        )
 SELECT raw_metrics."time",
    jsonb_each_text.key,
    jsonb_each_text.value
   FROM raw_metrics,
    LATERAL jsonb_each_text(raw_metrics.metrics) jsonb_each_text(key, value)
  ORDER BY jsonb_each_text.key;


--
-- Name: VIEW metrics_explore_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.metrics_explore_view IS 'metrics explore view web view';


--
-- Name: logbook; Type: TABLE; Schema: api; Owner: -
--

CREATE TABLE api.logbook (
    id integer NOT NULL,
    vessel_id text NOT NULL,
    active boolean DEFAULT false,
    name text,
    _from_moorage_id integer,
    _from text,
    _from_lat double precision,
    _from_lng double precision,
    _to_moorage_id integer,
    _to text,
    _to_lat double precision,
    _to_lng double precision,
    _from_time timestamp with time zone NOT NULL,
    _to_time timestamp with time zone,
    distance numeric,
    duration interval,
    avg_speed double precision,
    max_speed double precision,
    max_wind_speed double precision,
    notes text,
    extra jsonb,
    trip public.tgeogpoint,
    trip_cog public.tfloat,
    trip_sog public.tfloat,
    trip_aws public.tfloat,
    trip_tws public.tfloat,
    trip_twd public.tfloat,
    trip_notes public.ttext,
    trip_status public.ttext,
    trip_depth public.tfloat,
    trip_batt_charge public.tfloat,
    trip_batt_voltage public.tfloat,
    trip_temp_water public.tfloat,
    trip_temp_out public.tfloat,
    trip_pres_out public.tfloat,
    trip_hum_out public.tfloat,
    trip_heading public.tfloat,
    trip_tank_level public.tfloat,
    trip_solar_voltage public.tfloat,
    trip_solar_power public.tfloat,
    trip_awa public.tfloat,
    user_data jsonb DEFAULT '{}'::jsonb
);

ALTER TABLE ONLY api.logbook FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE logbook; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TABLE api.logbook IS 'Stores generated logbook';


--
-- Name: COLUMN logbook.vessel_id; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.vessel_id IS 'Unique identifier for the vessel associated with the api.metadata entry';


--
-- Name: COLUMN logbook._from_moorage_id; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook._from_moorage_id IS 'Link api.moorages with api.logbook via FOREIGN KEY and REFERENCES';


--
-- Name: COLUMN logbook._from; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook._from IS 'Name of the location where the log started, usually a moorage name';


--
-- Name: COLUMN logbook._to_moorage_id; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook._to_moorage_id IS 'Link api.moorages with api.logbook via FOREIGN KEY and REFERENCES';


--
-- Name: COLUMN logbook._to; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook._to IS 'Name of the location where the log ended, usually a moorage name';


--
-- Name: COLUMN logbook.distance; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.distance IS 'Distance in Nautical Miles converted mobilitydb meters to NM';


--
-- Name: COLUMN logbook.duration; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.duration IS 'Duration in ISO 8601 format';


--
-- Name: COLUMN logbook.avg_speed; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.avg_speed IS 'avg speed in knots';


--
-- Name: COLUMN logbook.max_speed; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.max_speed IS 'max speed in knots';


--
-- Name: COLUMN logbook.max_wind_speed; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.max_wind_speed IS 'true wind speed converted in knots, m/s from signalk plugin';


--
-- Name: COLUMN logbook.extra; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.extra IS 'Computed SignalK metrics such as runtime, current level, etc.';


--
-- Name: COLUMN logbook.trip; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip IS 'MobilityDB trajectory, speed in m/s, distance in meters';


--
-- Name: COLUMN logbook.trip_cog; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_cog IS 'COG - Course Over Ground True in degrees converted from radians by signalk plugin';


--
-- Name: COLUMN logbook.trip_sog; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_sog IS 'SOG - Speed Over Ground in knots converted by signalk plugin';


--
-- Name: COLUMN logbook.trip_aws; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_aws IS 'AWS (Apparent Wind Speed), windSpeedApparent in knots converted by signalk plugin';


--
-- Name: COLUMN logbook.trip_tws; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_tws IS 'TWS - True Wind Speed in knots converted from m/s, raw from signalk plugin';


--
-- Name: COLUMN logbook.trip_twd; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_twd IS 'TWD - True Wind Direction in degrees converted from radians, raw from signalk plugin';


--
-- Name: COLUMN logbook.trip_depth; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_depth IS 'Depth in meters, raw from signalk plugin';


--
-- Name: COLUMN logbook.trip_batt_charge; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_batt_charge IS 'Battery Charge';


--
-- Name: COLUMN logbook.trip_batt_voltage; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_batt_voltage IS 'Battery Voltage';


--
-- Name: COLUMN logbook.trip_temp_water; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_temp_water IS 'Temperature water in Kelvin, raw from signalk plugin';


--
-- Name: COLUMN logbook.trip_temp_out; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_temp_out IS 'Temperature outside in Kelvin, raw from signalk plugin';


--
-- Name: COLUMN logbook.trip_pres_out; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_pres_out IS 'Pressure outside';


--
-- Name: COLUMN logbook.trip_hum_out; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_hum_out IS 'Humidity outside';


--
-- Name: COLUMN logbook.trip_heading; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_heading IS 'Heading True in degrees converted from radians, raw from signalk plugin';


--
-- Name: COLUMN logbook.trip_tank_level; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_tank_level IS 'Tank currentLevel';


--
-- Name: COLUMN logbook.trip_solar_voltage; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_solar_voltage IS 'solar voltage';


--
-- Name: COLUMN logbook.trip_solar_power; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_solar_power IS 'solar powerPanel';


--
-- Name: COLUMN logbook.trip_awa; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.trip_awa IS 'AWA (Apparent Wind Angle) in degrees converted from radians by signalk plugin';


--
-- Name: COLUMN logbook.user_data; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.logbook.user_data IS 'User-defined data Log-specific data including actual tags, observations, images and custom fields';


--
-- Name: log_mat_view; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.log_mat_view AS
 SELECT id,
    name,
    _from AS "from",
    _from_time AS started,
    _to AS "to",
    _to_time AS ended,
    distance,
    duration,
    notes,
    api.export_logbook_geojson_trip_fn(id) AS geojson,
    avg_speed,
    max_speed,
    max_wind_speed,
    extra,
    _from_moorage_id AS from_moorage_id,
    _to_moorage_id AS to_moorage_id,
    (extra -> 'polar'::text) AS polar,
    (user_data -> 'images'::text) AS images,
    (user_data -> 'tags'::text) AS tags,
    (user_data -> 'observations'::text) AS observations,
        CASE
            WHEN (jsonb_array_length((user_data -> 'images'::text)) > 0) THEN true
            ELSE false
        END AS has_images,
    vessel_id
   FROM api.logbook l
  WHERE ((_to_time IS NOT NULL) AND (trip IS NOT NULL))
  ORDER BY _from_time DESC
  WITH NO DATA;


--
-- Name: MATERIALIZED VIEW log_mat_view; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON MATERIALIZED VIEW public.log_mat_view IS 'Log web materialized view';


--
-- Name: log_mat_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.log_mat_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT id,
    name,
    "from",
    started,
    "to",
    ended,
    distance,
    duration,
    notes,
    geojson,
    avg_speed,
    max_speed,
    max_wind_speed,
    extra,
    from_moorage_id,
    to_moorage_id,
    polar,
    images,
    tags,
    observations,
    has_images
   FROM public.log_mat_view
  WHERE (vessel_id = current_setting('vessel.id'::text, true));


--
-- Name: VIEW log_mat_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.log_mat_view IS 'Log web materialized view with RLS applied';


--
-- Name: log_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.log_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT id,
    name,
    _from AS "from",
    _from_time AS started,
    _to AS "to",
    _to_time AS ended,
    distance,
    duration,
    notes,
    api.export_logbook_geojson_trip_fn(id) AS geojson,
    avg_speed,
    max_speed,
    max_wind_speed,
    extra,
    _from_moorage_id AS from_moorage_id,
    _to_moorage_id AS to_moorage_id,
    (extra -> 'polar'::text) AS polar,
    (user_data -> 'images'::text) AS images,
    (user_data -> 'tags'::text) AS tags,
    (user_data -> 'observations'::text) AS observations,
        CASE
            WHEN (jsonb_array_length((user_data -> 'images'::text)) > 0) THEN true
            ELSE false
        END AS has_images
   FROM api.logbook l
  WHERE ((_to_time IS NOT NULL) AND (trip IS NOT NULL))
  ORDER BY _from_time DESC;


--
-- Name: VIEW log_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.log_view IS 'Log web view';


--
-- Name: logbook_id_seq; Type: SEQUENCE; Schema: api; Owner: -
--

ALTER TABLE api.logbook ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME api.logbook_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: logs_geojson_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.logs_geojson_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT id,
    name,
    starttimestamp,
    (public.st_asgeojson(tbl.*))::jsonb AS geojson
   FROM ( SELECT l.id,
            l.name,
            public.starttimestamp(l.trip) AS starttimestamp,
            public.endtimestamp(l.trip) AS endtimestamp,
            public.duration(l.trip) AS duration,
            ((public.length(l.trip) * (0.0005399568)::double precision))::numeric AS distance,
            public.maxvalue(l.trip_sog) AS max_sog,
            public.maxvalue(l.trip_tws) AS max_tws,
            public.maxvalue(l.trip_twd) AS max_twd,
            public.maxvalue(l.trip_depth) AS max_depth,
            public.maxvalue(l.trip_temp_water) AS max_temp_water,
            public.maxvalue(l.trip_temp_out) AS max_temp_out,
            public.maxvalue(l.trip_pres_out) AS max_pres_out,
            public.maxvalue(l.trip_hum_out) AS max_hum_out,
            public.maxvalue(l.trip_batt_charge) AS max_stateofcharge,
            public.maxvalue(l.trip_batt_voltage) AS max_voltage,
            public.maxvalue(l.trip_solar_voltage) AS max_solar_voltage,
            public.maxvalue(l.trip_solar_power) AS max_solar_power,
            public.maxvalue(l.trip_tank_level) AS max_tank_level,
            public.twavg(l.trip_sog) AS avg_sog,
            public.twavg(l.trip_tws) AS avg_tws,
            public.twavg(l.trip_twd) AS avg_twd,
            public.twavg(l.trip_depth) AS avg_depth,
            public.twavg(l.trip_temp_water) AS avg_temp_water,
            public.twavg(l.trip_temp_out) AS avg_temp_out,
            public.twavg(l.trip_pres_out) AS avg_pres_out,
            public.twavg(l.trip_hum_out) AS avg_hum_out,
            public.twavg(l.trip_batt_charge) AS avg_stateofcharge,
            public.twavg(l.trip_batt_voltage) AS avg_voltage,
            public.twavg(l.trip_solar_voltage) AS avg_solar_voltage,
            public.twavg(l.trip_solar_power) AS avg_solar_power,
            public.twavg(l.trip_tank_level) AS avg_tank_level,
            (public.trajectory(l.trip))::public.geometry AS track_geog,
            l.extra,
            l._to_moorage_id,
            l._from_moorage_id,
            (l.extra -> 'polar'::text) AS polar,
            (l.user_data -> 'images'::text) AS images,
            (l.user_data -> 'tags'::text) AS tags,
            (l.user_data -> 'observations'::text) AS observations,
                CASE
                    WHEN (jsonb_array_length((l.user_data -> 'images'::text)) > 0) THEN true
                    ELSE false
                END AS has_images
           FROM api.logbook l
          WHERE ((l._to_time IS NOT NULL) AND (l.trip IS NOT NULL))
          ORDER BY l._from_time DESC) tbl;


--
-- Name: VIEW logs_geojson_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.logs_geojson_view IS 'List logs as geojson';


--
-- Name: logs_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.logs_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT id,
    name,
    _from AS "from",
    _from_time AS started,
    _to AS "to",
    _to_time AS ended,
    distance,
    duration,
    _from_moorage_id,
    _to_moorage_id,
    (user_data -> 'tags'::text) AS tags
   FROM api.logbook l
  WHERE ((name IS NOT NULL) AND (_to_time IS NOT NULL))
  ORDER BY _from_time DESC;


--
-- Name: VIEW logs_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.logs_view IS 'Logs web view';


--
-- Name: metadata; Type: TABLE; Schema: api; Owner: -
--

CREATE TABLE api.metadata (
    name text,
    mmsi text,
    vessel_id text DEFAULT current_setting('vessel.id'::text, false) NOT NULL,
    length double precision,
    beam double precision,
    height double precision,
    ship_type numeric,
    plugin_version text NOT NULL,
    signalk_version text NOT NULL,
    "time" timestamp with time zone NOT NULL,
    platform text,
    configuration jsonb,
    active boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    available_keys jsonb,
    ip text,
    user_data jsonb DEFAULT '{}'::jsonb
);

ALTER TABLE ONLY api.metadata FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE metadata; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TABLE api.metadata IS 'Stores metadata received from vessel, aka signalk plugin';


--
-- Name: COLUMN metadata.mmsi; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.metadata.mmsi IS 'Maritime Mobile Service Identity (MMSI) number associated with the vessel, link to public.mid';


--
-- Name: COLUMN metadata.vessel_id; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.metadata.vessel_id IS 'Link auth.vessels with api.metadata via FOREIGN KEY and REFERENCES';


--
-- Name: COLUMN metadata.ship_type; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.metadata.ship_type IS 'Type of ship associated with the vessel, link to public.aistypes';


--
-- Name: COLUMN metadata.configuration; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.metadata.configuration IS 'User-defined Signalk path mapping for metrics';


--
-- Name: COLUMN metadata.active; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.metadata.active IS 'trigger monitor online/offline';


--
-- Name: COLUMN metadata.available_keys; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.metadata.available_keys IS 'Signalk paths with unit for custom mapping';


--
-- Name: COLUMN metadata.ip; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.metadata.ip IS 'Store vessel ip address';


--
-- Name: COLUMN metadata.user_data; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.metadata.user_data IS 'User-defined data including vessel polar (theoretical performance), make/model, and preferences';


--
-- Name: monitoring_humidity; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.monitoring_humidity WITH (security_invoker='true', security_barrier='true') AS
 SELECT m."time",
    jsonb_each_text.key,
    jsonb_each_text.value
   FROM api.metrics m,
    LATERAL jsonb_each_text(m.metrics) jsonb_each_text(key, value)
  WHERE ((jsonb_each_text.key ~~* 'environment.%.humidity'::text) OR (jsonb_each_text.key ~~* 'environment.%.relativeHumidity'::text))
  ORDER BY m."time" DESC;


--
-- Name: VIEW monitoring_humidity; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.monitoring_humidity IS 'Monitoring environment.%.humidity web view';


--
-- Name: monitoring_live; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.monitoring_live WITH (security_invoker='true', security_barrier='true') AS
 WITH pressure AS (
         SELECT json_agg(json_build_object('time', sub.time_bucket, 'outsidePressure', sub.outsidepressure) ORDER BY sub.time_bucket) AS outsidepressurehistory
           FROM ( SELECT public.time_bucket('00:10:00'::interval, mt_1."time") AS time_bucket,
                    avg((COALESCE(((mt_1.metrics -> 'pressure'::text) ->> 'outside'::text), (mt_1.metrics ->> (md_1.configuration ->> 'outsidePressureKey'::text)), (mt_1.metrics ->> 'environment.outside.pressure'::text)))::double precision) AS outsidepressure
                   FROM (api.metrics mt_1
                     JOIN api.metadata md_1 ON ((md_1.vessel_id = mt_1.vessel_id)))
                  WHERE ((mt_1.vessel_id = current_setting('vessel.id'::text, false)) AND (mt_1."time" > ((now() AT TIME ZONE 'UTC'::text) - '06:00:00'::interval)))
                  GROUP BY (public.time_bucket('00:10:00'::interval, mt_1."time"))
                 HAVING (avg((COALESCE(((mt_1.metrics -> 'pressure'::text) ->> 'outside'::text), (mt_1.metrics ->> (md_1.configuration ->> 'outsidePressureKey'::text)), (mt_1.metrics ->> 'environment.outside.pressure'::text)))::double precision) IS NOT NULL)) sub
        )
 SELECT mt."time",
    ((((now() AT TIME ZONE 'UTC'::text))::timestamp with time zone - mt."time") > '01:10:00'::interval) AS offline,
    mt.metrics AS data,
    jsonb_build_object('type', 'Feature', 'geometry', (public.st_asgeojson(public.st_makepoint(mt.longitude, mt.latitude)))::jsonb, 'properties', jsonb_build_object('name', current_setting('vessel.name'::text, false), 'latitude', mt.latitude, 'longitude', mt.longitude, 'time', mt."time", 'speedoverground', mt.speedoverground, 'windspeedapparent', mt.windspeedapparent, 'truewindspeed', (COALESCE(((mt.metrics -> 'wind'::text) ->> 'speed'::text), (mt.metrics ->> (md.configuration ->> 'windSpeedKey'::text)), (mt.metrics ->> 'environment.wind.speedTrue'::text)))::double precision, 'truewinddirection', (COALESCE(((mt.metrics -> 'wind'::text) ->> 'direction'::text), (mt.metrics ->> (md.configuration ->> 'windDirectionKey'::text)), (mt.metrics ->> 'environment.wind.directionTrue'::text)))::double precision, 'status', COALESCE(mt.status, NULL::text))) AS geojson,
    current_setting('vessel.name'::text, false) AS name,
    mt.status,
    (COALESCE(((mt.metrics -> 'water'::text) ->> 'temperature'::text), (mt.metrics ->> (md.configuration ->> 'waterTemperatureKey'::text)), (mt.metrics ->> 'environment.water.temperature'::text)))::double precision AS watertemperature,
    (COALESCE(((mt.metrics -> 'temperature'::text) ->> 'inside'::text), (mt.metrics ->> (md.configuration ->> 'insideTemperatureKey'::text)), (mt.metrics ->> 'environment.inside.temperature'::text)))::double precision AS insidetemperature,
    (COALESCE(((mt.metrics -> 'temperature'::text) ->> 'outside'::text), (mt.metrics ->> (md.configuration ->> 'outsideTemperatureKey'::text)), (mt.metrics ->> 'environment.outside.temperature'::text)))::double precision AS outsidetemperature,
    (COALESCE(((mt.metrics -> 'wind'::text) ->> 'speed'::text), (mt.metrics ->> (md.configuration ->> 'windSpeedKey'::text)), (mt.metrics ->> 'environment.wind.speedTrue'::text)))::double precision AS windspeedoverground,
    (COALESCE(((mt.metrics -> 'wind'::text) ->> 'direction'::text), (mt.metrics ->> (md.configuration ->> 'windDirectionKey'::text)), (mt.metrics ->> 'environment.wind.directionTrue'::text)))::double precision AS winddirectiontrue,
    (COALESCE(((mt.metrics -> 'humidity'::text) ->> 'inside'::text), (mt.metrics ->> (md.configuration ->> 'insideHumidityKey'::text)), (mt.metrics ->> 'environment.inside.relativeHumidity'::text), (mt.metrics ->> 'environment.inside.humidity'::text)))::double precision AS insidehumidity,
    (COALESCE(((mt.metrics -> 'humidity'::text) ->> 'outside'::text), (mt.metrics ->> (md.configuration ->> 'outsideHumidityKey'::text)), (mt.metrics ->> 'environment.outside.relativeHumidity'::text), (mt.metrics ->> 'environment.outside.humidity'::text)))::double precision AS outsidehumidity,
    (COALESCE(((mt.metrics -> 'pressure'::text) ->> 'outside'::text), (mt.metrics ->> (md.configuration ->> 'outsidePressureKey'::text)), (mt.metrics ->> 'environment.outside.pressure'::text)))::double precision AS outsidepressure,
    (COALESCE(((mt.metrics -> 'pressure'::text) ->> 'inside'::text), (mt.metrics ->> (md.configuration ->> 'insidePressureKey'::text)), (mt.metrics ->> 'environment.inside.pressure'::text)))::double precision AS insidepressure,
    (COALESCE(((mt.metrics -> 'battery'::text) ->> 'charge'::text), (mt.metrics ->> (md.configuration ->> 'stateOfChargeKey'::text)), (mt.metrics ->> 'electrical.batteries.House.capacity.stateOfCharge'::text)))::double precision AS batterycharge,
    (COALESCE(((mt.metrics -> 'battery'::text) ->> 'voltage'::text), (mt.metrics ->> (md.configuration ->> 'voltageKey'::text)), (mt.metrics ->> 'electrical.batteries.House.voltage'::text)))::double precision AS batteryvoltage,
    (COALESCE(((mt.metrics -> 'water'::text) ->> 'depth'::text), (mt.metrics ->> (md.configuration ->> 'depthKey'::text)), (mt.metrics ->> 'environment.depth.belowTransducer'::text)))::double precision AS depth,
    (COALESCE(((mt.metrics -> 'solar'::text) ->> 'power'::text), (mt.metrics ->> (md.configuration ->> 'solarPowerKey'::text)), (mt.metrics ->> 'electrical.solar.Main.panelPower'::text)))::double precision AS solarpower,
    (COALESCE(((mt.metrics -> 'solar'::text) ->> 'voltage'::text), (mt.metrics ->> (md.configuration ->> 'solarVoltageKey'::text)), (mt.metrics ->> 'electrical.solar.Main.panelVoltage'::text)))::double precision AS solarvoltage,
    (COALESCE(((mt.metrics -> 'tank'::text) ->> 'level'::text), (mt.metrics ->> (md.configuration ->> 'tankLevelKey'::text)), (mt.metrics ->> 'tanks.fuel.0.currentLevel'::text)))::double precision AS tanklevel,
        CASE
            WHEN ((mt.status <> 'moored'::text) AND (mt.status <> 'anchored'::text)) THEN ( SELECT public.logbook_active_geojson_fn() AS logbook_active_geojson_fn)
            WHEN ((mt.status = 'moored'::text) OR (mt.status = 'anchored'::text)) THEN ( SELECT public.stay_active_geojson_fn(mt."time") AS stay_active_geojson_fn)
            ELSE NULL::jsonb
        END AS live,
    pressure.outsidepressurehistory
   FROM ((api.metrics mt
     JOIN api.metadata md ON ((md.vessel_id = mt.vessel_id)))
     CROSS JOIN pressure)
  ORDER BY mt."time" DESC
 LIMIT 1;


--
-- Name: VIEW monitoring_live; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.monitoring_live IS 'Dynamic Monitoring web view';


--
-- Name: monitoring_temperatures; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.monitoring_temperatures WITH (security_invoker='true', security_barrier='true') AS
 SELECT m."time",
    jsonb_each_text.key,
    jsonb_each_text.value
   FROM api.metrics m,
    LATERAL jsonb_each_text(m.metrics) jsonb_each_text(key, value)
  WHERE (jsonb_each_text.key ~~* 'environment.%.temperature'::text)
  ORDER BY m."time" DESC;


--
-- Name: VIEW monitoring_temperatures; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.monitoring_temperatures IS 'Monitoring environment.%.temperature web view';


--
-- Name: monitoring_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.monitoring_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT "time",
    ((((now() AT TIME ZONE 'UTC'::text))::timestamp with time zone - "time") > '01:10:00'::interval) AS offline,
    (metrics -> 'environment.water.temperature'::text) AS watertemperature,
    (metrics -> 'environment.inside.temperature'::text) AS insidetemperature,
    (metrics -> 'environment.outside.temperature'::text) AS outsidetemperature,
    (metrics -> 'environment.wind.speedTrue'::text) AS windspeedoverground,
    (metrics -> 'environment.wind.directionTrue'::text) AS winddirectiontrue,
    (metrics -> 'environment.inside.relativeHumidity'::text) AS insidehumidity,
    (metrics -> 'environment.outside.relativeHumidity'::text) AS outsidehumidity,
    (metrics -> 'environment.outside.pressure'::text) AS outsidepressure,
    (metrics -> 'environment.inside.pressure'::text) AS insidepressure,
    (metrics -> 'electrical.batteries.House.capacity.stateOfCharge'::text) AS batterycharge,
    (metrics -> 'electrical.batteries.House.voltage'::text) AS batteryvoltage,
    (metrics -> 'environment.depth.belowTransducer'::text) AS depth,
    jsonb_build_object('type', 'Feature', 'geometry', (public.st_asgeojson(public.st_makepoint(longitude, latitude)))::jsonb, 'properties', jsonb_build_object('name', current_setting('vessel.name'::text, false), 'latitude', latitude, 'longitude', longitude, 'time', "time", 'speedoverground', speedoverground, 'windspeedapparent', windspeedapparent, 'truewindspeed', COALESCE((metrics -> 'environment.wind.speedTrue'::text), NULL::jsonb), 'truewinddirection', COALESCE((metrics -> 'environment.wind.directionTrue'::text), NULL::jsonb), 'status', COALESCE(status, NULL::text))) AS geojson,
    current_setting('vessel.name'::text, false) AS name,
    status,
        CASE
            WHEN ((status <> 'moored'::text) AND (status <> 'anchored'::text)) THEN ( SELECT public.logbook_active_geojson_fn() AS logbook_active_geojson_fn)
            WHEN ((status = 'moored'::text) OR (status = 'anchored'::text)) THEN ( SELECT public.stay_active_geojson_fn(m."time") AS stay_active_geojson_fn)
            ELSE NULL::jsonb
        END AS live
   FROM api.metrics m
  ORDER BY "time" DESC
 LIMIT 1;


--
-- Name: VIEW monitoring_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.monitoring_view IS 'Monitoring static web view';


--
-- Name: monitoring_view2; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.monitoring_view2 WITH (security_invoker='true', security_barrier='true') AS
 SELECT key,
    value
   FROM jsonb_each(( SELECT m.metrics
           FROM api.metrics m
          ORDER BY m."time" DESC
         LIMIT 1)) jsonb_each(key, value);


--
-- Name: VIEW monitoring_view2; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.monitoring_view2 IS 'Monitoring Last whatever data from json web view';


--
-- Name: monitoring_view3; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.monitoring_view3 WITH (security_invoker='true', security_barrier='true') AS
 SELECT m."time",
    jsonb_each_text.key,
    jsonb_each_text.value
   FROM api.metrics m,
    LATERAL jsonb_each_text(m.metrics) jsonb_each_text(key, value)
  ORDER BY m."time" DESC;


--
-- Name: VIEW monitoring_view3; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.monitoring_view3 IS 'Monitoring Timeseries whatever data from json web view';


--
-- Name: monitoring_voltage; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.monitoring_voltage WITH (security_invoker='true', security_barrier='true') AS
 SELECT m."time",
    jsonb_each_text.key,
    jsonb_each_text.value
   FROM api.metrics m,
    LATERAL jsonb_each_text(m.metrics) jsonb_each_text(key, value)
  WHERE (jsonb_each_text.key ~~* 'electrical.%.voltage'::text)
  ORDER BY m."time" DESC;


--
-- Name: VIEW monitoring_voltage; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.monitoring_voltage IS 'Monitoring electrical.%.voltage web view';


--
-- Name: moorages; Type: TABLE; Schema: api; Owner: -
--

CREATE TABLE api.moorages (
    id integer NOT NULL,
    vessel_id text NOT NULL,
    name text,
    country text,
    stay_code integer DEFAULT 1,
    latitude double precision,
    longitude double precision,
    geog public.geography(Point,4326),
    home_flag boolean DEFAULT false,
    notes text,
    overpass jsonb,
    nominatim jsonb,
    user_data jsonb DEFAULT '{}'::jsonb
);

ALTER TABLE ONLY api.moorages FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE moorages; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TABLE api.moorages IS 'Stores generated moorages';


--
-- Name: COLUMN moorages.vessel_id; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.moorages.vessel_id IS 'Unique identifier for the vessel associated with the api.metadata entry';


--
-- Name: COLUMN moorages.stay_code; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.moorages.stay_code IS 'Link api.stays_at with api.moorages via FOREIGN KEY and REFERENCES';


--
-- Name: COLUMN moorages.geog; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.moorages.geog IS 'postgis geography type default SRID 4326 Unit: degres';


--
-- Name: COLUMN moorages.overpass; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.moorages.overpass IS 'Output of the overpass API, see https://wiki.openstreetmap.org/wiki/Overpass_API';


--
-- Name: COLUMN moorages.nominatim; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.moorages.nominatim IS 'Output of the nominatim reverse geocoding service, see https://nominatim.org/release-docs/develop/api/Reverse/';


--
-- Name: COLUMN moorages.user_data; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.moorages.user_data IS 'User-defined data Mooring-specific data including images and custom fields';


--
-- Name: stays; Type: TABLE; Schema: api; Owner: -
--

CREATE TABLE api.stays (
    id integer NOT NULL,
    vessel_id text NOT NULL,
    active boolean DEFAULT false,
    moorage_id integer,
    name text,
    latitude double precision,
    longitude double precision,
    geog public.geography(Point,4326),
    arrived timestamp with time zone NOT NULL,
    departed timestamp with time zone,
    duration interval,
    stay_code integer DEFAULT 1,
    notes text,
    user_data jsonb DEFAULT '{}'::jsonb
);

ALTER TABLE ONLY api.stays FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE stays; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TABLE api.stays IS 'Stores generated stays';


--
-- Name: COLUMN stays.vessel_id; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.stays.vessel_id IS 'Unique identifier for the vessel associated with the api.metadata entry';


--
-- Name: COLUMN stays.moorage_id; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.stays.moorage_id IS 'Link api.moorages with api.stays via FOREIGN KEY and REFERENCES';


--
-- Name: COLUMN stays.geog; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.stays.geog IS 'postgis geography type default SRID 4326 Unit: degres';


--
-- Name: COLUMN stays.duration; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.stays.duration IS 'Best to use standard ISO 8601';


--
-- Name: COLUMN stays.stay_code; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.stays.stay_code IS 'Link api.stays_at with api.stays via FOREIGN KEY and REFERENCES';


--
-- Name: COLUMN stays.user_data; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON COLUMN api.stays.user_data IS 'User-defined data Stay-specific data including images and custom fields';


--
-- Name: stays_at; Type: TABLE; Schema: api; Owner: -
--

CREATE TABLE api.stays_at (
    stay_code integer NOT NULL,
    description text NOT NULL
);


--
-- Name: TABLE stays_at; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TABLE api.stays_at IS 'Stay Type';


--
-- Name: moorage_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.moorage_view WITH (security_invoker='true', security_barrier='true') AS
 WITH stay_details AS (
         SELECT s.moorage_id,
            s.arrived,
            s.departed,
            s.duration,
            s.id AS stay_id,
            first_value(s.id) OVER (PARTITION BY s.moorage_id ORDER BY s.arrived) AS first_seen_id,
            first_value(s.id) OVER (PARTITION BY s.moorage_id ORDER BY s.departed DESC) AS last_seen_id
           FROM api.stays s
          WHERE (s.active = false)
        ), stay_summary AS (
         SELECT stay_details.moorage_id,
            min(stay_details.arrived) AS first_seen,
            max(stay_details.departed) AS last_seen,
            sum(stay_details.duration) AS total_duration,
            count(*) AS stay_count,
            max(stay_details.first_seen_id) AS first_seen_id,
            max(stay_details.last_seen_id) AS last_seen_id
           FROM stay_details
          GROUP BY stay_details.moorage_id
        ), log_summary AS (
         SELECT logs.moorage_id,
            count(DISTINCT logs.id) AS log_count
           FROM ( SELECT l_1._from_moorage_id AS moorage_id,
                    l_1.id
                   FROM api.logbook l_1
                  WHERE (l_1.active = false)
                UNION ALL
                 SELECT l_1._to_moorage_id AS moorage_id,
                    l_1.id
                   FROM api.logbook l_1
                  WHERE (l_1.active = false)) logs
          GROUP BY logs.moorage_id
        )
 SELECT m.id,
    m.name,
    sa.description AS default_stay,
    sa.stay_code AS default_stay_id,
    m.notes,
    m.home_flag AS home,
    m.geog,
    m.latitude,
    m.longitude,
    COALESCE(l.log_count, (0)::bigint) AS logs_count,
    COALESCE(ss.stay_count, (0)::bigint) AS stays_count,
    COALESCE(ss.total_duration, '00:00:00'::interval) AS stays_sum_duration,
    ss.first_seen AS stay_first_seen,
    ss.last_seen AS stay_last_seen,
    ss.first_seen_id AS stay_first_seen_id,
    ss.last_seen_id AS stay_last_seen_id,
        CASE
            WHEN (jsonb_array_length((m.user_data -> 'images'::text)) > 0) THEN true
            ELSE false
        END AS has_images,
    (m.user_data -> 'images'::text) AS images
   FROM (((api.moorages m
     JOIN api.stays_at sa ON ((m.stay_code = sa.stay_code)))
     LEFT JOIN stay_summary ss ON ((m.id = ss.moorage_id)))
     LEFT JOIN log_summary l ON ((m.id = l.moorage_id)))
  WHERE (m.geog IS NOT NULL)
  ORDER BY ss.total_duration DESC;


--
-- Name: VIEW moorage_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.moorage_view IS 'Moorage details web view';


--
-- Name: moorages_geojson_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.moorages_geojson_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT id,
    name,
    (public.st_asgeojson(m.*))::jsonb AS geojson
   FROM ( SELECT m_1.id,
            m_1.name,
            m_1.default_stay,
            m_1.default_stay_id,
            m_1.notes,
            m_1.home,
            m_1.geog,
            m_1.latitude,
            m_1.longitude,
            m_1.logs_count,
            m_1.stays_count,
            m_1.stays_sum_duration,
            m_1.stay_first_seen,
            m_1.stay_last_seen,
            m_1.stay_first_seen_id,
            m_1.stay_last_seen_id,
            m_1.has_images,
            m_1.images
           FROM api.moorage_view m_1
          WHERE (m_1.geog IS NOT NULL)) m;


--
-- Name: VIEW moorages_geojson_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.moorages_geojson_view IS 'List moorages as geojson';


--
-- Name: moorages_id_seq; Type: SEQUENCE; Schema: api; Owner: -
--

ALTER TABLE api.moorages ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME api.moorages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: moorages_stays_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.moorages_stays_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT _to.name AS _to_name,
    _to.id AS _to_id,
    _to._to_time,
    _from.id AS _from_id,
    _from.name AS _from_name,
    _from._from_time,
    s.stay_code,
    s.duration,
    m.id,
    m.name
   FROM api.stays_at sa,
    api.moorages m,
    ((api.stays s
     LEFT JOIN api.logbook _from ON ((_from._from_time = s.departed)))
     LEFT JOIN api.logbook _to ON ((_to._to_time = s.arrived)))
  WHERE ((s.departed IS NOT NULL) AND (s.name IS NOT NULL) AND (s.stay_code = sa.stay_code) AND (s.moorage_id = m.id))
  ORDER BY _to._to_time DESC;


--
-- Name: VIEW moorages_stays_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.moorages_stays_view IS 'Moorages stay listing web view';


--
-- Name: moorages_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.moorages_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT m.id,
    m.name AS moorage,
    sa.description AS default_stay,
    sa.stay_code AS default_stay_id,
    COALESCE(count(DISTINCT l.id), (0)::bigint) AS arrivals_departures,
    COALESCE(sum(DISTINCT s.duration), '00:00:00'::interval) AS total_duration
   FROM (((api.moorages m
     JOIN api.stays_at sa ON ((m.stay_code = sa.stay_code)))
     LEFT JOIN api.stays s ON (((m.id = s.moorage_id) AND (s.active = false))))
     LEFT JOIN api.logbook l ON (((m.id = l._from_moorage_id) OR ((m.id = l._to_moorage_id) AND (l.active = false)))))
  WHERE ((m.geog IS NOT NULL) AND (m.stay_code = sa.stay_code))
  GROUP BY m.id, m.name, sa.description, sa.stay_code
  ORDER BY COALESCE(sum(DISTINCT s.duration), '00:00:00'::interval) DESC;


--
-- Name: VIEW moorages_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.moorages_view IS 'Moorages listing web view';


--
-- Name: stats_logs_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.stats_logs_view WITH (security_invoker='true', security_barrier='true') AS
 WITH meta AS (
         SELECT m_1.name
           FROM api.metadata m_1
        ), last_metric AS (
         SELECT m_1."time"
           FROM api.metrics m_1
          ORDER BY m_1."time" DESC
         LIMIT 1
        ), first_metric AS (
         SELECT m_1."time"
           FROM api.metrics m_1
          ORDER BY m_1."time"
         LIMIT 1
        ), logbook AS (
         SELECT count(*) AS number_of_log_entries,
            max(l_1.max_speed) AS max_speed,
            max(l_1.max_wind_speed) AS max_wind_speed,
            sum(l_1.distance) AS total_distance,
            sum(l_1.duration) AS total_time_underway,
            concat(max(l_1.distance), ' NM, ', max(l_1.duration), ' hours') AS longest_nonstop_sail
           FROM api.logbook l_1
        )
 SELECT m.name,
    fm."time" AS first,
    lm."time" AS last,
    l.number_of_log_entries,
    l.max_speed,
    l.max_wind_speed,
    l.total_distance,
    l.total_time_underway,
    l.longest_nonstop_sail
   FROM first_metric fm,
    last_metric lm,
    logbook l,
    meta m;


--
-- Name: VIEW stats_logs_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.stats_logs_view IS 'Statistics Logs web view';


--
-- Name: stats_moorages_away_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.stats_moorages_away_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT sa.description,
    sum(m.stays_sum_duration) AS time_spent_away_by
   FROM api.moorage_view m,
    api.stays_at sa
  WHERE ((m.home IS FALSE) AND (m.default_stay_id = sa.stay_code))
  GROUP BY m.default_stay_id, sa.description
  ORDER BY m.default_stay_id;


--
-- Name: VIEW stats_moorages_away_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.stats_moorages_away_view IS 'Statistics Moorages Time Spent Away web view';


--
-- Name: stats_moorages_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.stats_moorages_view WITH (security_invoker='true', security_barrier='true') AS
 WITH home_ports AS (
         SELECT count(*) AS home_ports
           FROM api.moorage_view m
          WHERE (m.home IS TRUE)
        ), unique_moorage AS (
         SELECT count(*) AS unique_moorage
           FROM api.moorage_view m
        ), time_at_home_ports AS (
         SELECT sum(m.stays_sum_duration) AS time_at_home_ports
           FROM api.moorage_view m
          WHERE (m.home IS TRUE)
        ), time_spent_away AS (
         SELECT sum(m.stays_sum_duration) AS time_spent_away
           FROM api.moorage_view m
          WHERE (m.home IS FALSE)
        )
 SELECT home_ports.home_ports,
    unique_moorage.unique_moorage AS unique_moorages,
    time_at_home_ports.time_at_home_ports AS "time_spent_at_home_port(s)",
    time_spent_away.time_spent_away
   FROM home_ports,
    unique_moorage,
    time_at_home_ports,
    time_spent_away;


--
-- Name: VIEW stats_moorages_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.stats_moorages_view IS 'Statistics Moorages web view';


--
-- Name: stays_explore_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.stays_explore_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT s.id AS stay_id,
    m.id AS moorage_id,
    m.name AS moorage_name,
    s.name AS stay_name,
    s.arrived,
    s.stay_code,
    s.latitude,
    s.longitude,
    s.notes AS stay_notes,
    m.notes AS moorage_notes,
        CASE
            WHEN (jsonb_array_length((s.user_data -> 'images'::text)) > 0) THEN true
            ELSE false
        END AS has_images,
    (s.user_data -> 'images'::text) AS images,
    s.id,
    s.name
   FROM (api.stays s
     LEFT JOIN api.moorages m ON ((s.moorage_id = m.id)))
  ORDER BY s.arrived DESC;


--
-- Name: VIEW stays_explore_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.stays_explore_view IS 'List moorages notes order by stays';


--
-- Name: stay_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.stay_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT s.id,
    s.name,
    m.name AS moorage,
    m.id AS moorage_id,
    (s.departed - s.arrived) AS duration,
    sa.description AS stayed_at,
    sa.stay_code AS stayed_at_id,
    s.arrived,
    _from.id AS arrived_log_id,
    _from._to_moorage_id AS arrived_from_moorage_id,
    _from._to AS arrived_from_moorage_name,
    s.departed,
    _to.id AS departed_log_id,
    _to._from_moorage_id AS departed_to_moorage_id,
    _to._from AS departed_to_moorage_name,
    s.notes,
        CASE
            WHEN (jsonb_array_length((s.user_data -> 'images'::text)) > 0) THEN true
            ELSE false
        END AS has_images,
    (s.user_data -> 'images'::text) AS images
   FROM ((((api.stays s
     JOIN api.stays_at sa ON ((s.stay_code = sa.stay_code)))
     JOIN api.moorages m ON ((s.moorage_id = m.id)))
     LEFT JOIN api.logbook _from ON ((_from._from_time = s.departed)))
     LEFT JOIN api.logbook _to ON ((_to._to_time = s.arrived)))
  WHERE ((s.departed IS NOT NULL) AND (_from._to_moorage_id IS NOT NULL) AND (s.name IS NOT NULL))
  ORDER BY s.arrived DESC;


--
-- Name: VIEW stay_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.stay_view IS 'Stay web view';


--
-- Name: stays_geojson_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.stays_geojson_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT (public.st_asgeojson(tbl.*))::jsonb AS geojson
   FROM ( SELECT stays_explore_view.stay_id,
            stays_explore_view.moorage_id,
            stays_explore_view.moorage_name,
            stays_explore_view.stay_name,
            stays_explore_view.arrived,
            stays_explore_view.stay_code,
            stays_explore_view.latitude,
            stays_explore_view.longitude,
            stays_explore_view.stay_notes,
            stays_explore_view.moorage_notes,
            stays_explore_view.has_images,
            stays_explore_view.images,
            public.st_makepoint(stays_explore_view.longitude, stays_explore_view.latitude) AS st_makepoint
           FROM api.stays_explore_view) tbl;


--
-- Name: VIEW stays_geojson_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.stays_geojson_view IS 'List stays as geojson';


--
-- Name: stays_id_seq; Type: SEQUENCE; Schema: api; Owner: -
--

ALTER TABLE api.stays ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME api.stays_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: stays_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.stays_view WITH (security_invoker='true', security_barrier='true') AS
 SELECT s.id,
    s.name,
    m.name AS moorage,
    m.id AS moorage_id,
    (s.departed - s.arrived) AS duration,
    sa.description AS stayed_at,
    sa.stay_code AS stayed_at_id,
    s.arrived,
    _from.id AS arrived_log_id,
    _from._to_moorage_id AS arrived_from_moorage_id,
    _from._to AS arrived_from_moorage_name,
    s.departed,
    _to.id AS departed_log_id,
    _to._from_moorage_id AS departed_to_moorage_id,
    _to._from AS departed_to_moorage_name,
    s.notes
   FROM api.stays_at sa,
    api.moorages m,
    ((api.stays s
     LEFT JOIN api.logbook _from ON ((_from._from_time = s.departed)))
     LEFT JOIN api.logbook _to ON ((_to._to_time = s.arrived)))
  WHERE ((s.departed IS NOT NULL) AND (_from._to_moorage_id IS NOT NULL) AND (s.name IS NOT NULL) AND (s.stay_code = sa.stay_code) AND (s.moorage_id = m.id))
  ORDER BY s.arrived DESC;


--
-- Name: VIEW stays_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.stays_view IS 'Stays web view';


--
-- Name: total_info_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.total_info_view WITH (security_invoker='true', security_barrier='true') AS
 WITH l AS (
         SELECT count(*) AS logs
           FROM api.logbook
        ), s AS (
         SELECT count(*) AS stays
           FROM api.stays
        ), m AS (
         SELECT count(*) AS moorages
           FROM api.moorages
        )
 SELECT l.logs,
    s.stays,
    m.moorages
   FROM l,
    s,
    m;


--
-- Name: VIEW total_info_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.total_info_view IS 'total_info_view web view';


--
-- Name: app_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.app_settings (
    name text NOT NULL,
    value text NOT NULL
);


--
-- Name: TABLE app_settings; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.app_settings IS 'application settings';


--
-- Name: COLUMN app_settings.name; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.app_settings.name IS 'application settings name key';


--
-- Name: COLUMN app_settings.value; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.app_settings.value IS 'application settings value';


--
-- Name: versions_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.versions_view AS
 SELECT value AS api_version,
    rtrim("substring"(version(), 0, 17)) AS sys_version,
    ( SELECT pg_extension.extversion AS timescaledb
           FROM pg_extension
          WHERE (pg_extension.extname = 'timescaledb'::name)) AS timescaledb,
    ( SELECT pg_extension.extversion AS postgis
           FROM pg_extension
          WHERE (pg_extension.extname = 'postgis'::name)) AS postgis,
    ( SELECT rtrim("substring"(pg_stat_activity.application_name, 'PostgREST [0-9.]+'::text)) AS postgrest
           FROM pg_stat_activity
          WHERE (pg_stat_activity.application_name ~~* '%postgrest%'::text)
         LIMIT 1) AS postgrest
   FROM public.app_settings
  WHERE (name = 'app.version'::text);


--
-- Name: VIEW versions_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.versions_view IS 'Expose as a table view app and system version to API';


--
-- Name: vessels; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.vessels (
    vessel_id text DEFAULT "right"((gen_random_uuid())::text, 12) NOT NULL,
    owner_email public.citext NOT NULL,
    mmsi numeric,
    name text NOT NULL,
    role name NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT valid_range_mmsi CHECK (((mmsi > (100000000)::numeric) AND (mmsi < (800000000)::numeric))),
    CONSTRAINT vessels_name_check CHECK (((length(name) >= 3) AND (length(name) < 512))),
    CONSTRAINT vessels_role_check CHECK ((length((role)::text) < 512))
);

ALTER TABLE ONLY auth.vessels FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE vessels; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.vessels IS 'vessels table link to accounts email user_id column';


--
-- Name: COLUMN vessels.mmsi; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.vessels.mmsi IS 'MMSI can be optional but if present must be a valid one and unique but must be in numeric range between 100000000 and 800000000';


--
-- Name: vessels_view; Type: VIEW; Schema: api; Owner: -
--

CREATE VIEW api.vessels_view WITH (security_invoker='true', security_barrier='true') AS
 WITH metrics AS (
         SELECT COALESCE((( SELECT m."time"
                   FROM api.metrics m
                  WHERE (m.vessel_id = current_setting('vessel.id'::text))
                  ORDER BY m."time" DESC
                 LIMIT 1))::text, NULL::text) AS last_metrics
        ), metadata AS (
         SELECT COALESCE((( SELECT m."time"
                   FROM api.metadata m
                  WHERE (m.vessel_id = current_setting('vessel.id'::text))))::text, NULL::text) AS last_contact
        )
 SELECT v.name,
    v.mmsi,
    v.created_at,
    metadata.last_contact,
    ((((now() AT TIME ZONE 'UTC'::text))::timestamp with time zone - (metadata.last_contact)::timestamp with time zone) > '01:10:00'::interval) AS offline,
    (((now() AT TIME ZONE 'UTC'::text))::timestamp with time zone - (metadata.last_contact)::timestamp with time zone) AS duration,
    metrics.last_metrics,
    ((((now() AT TIME ZONE 'UTC'::text))::timestamp with time zone - (metrics.last_metrics)::timestamp with time zone) > '01:10:00'::interval) AS metrics_offline,
    (((now() AT TIME ZONE 'UTC'::text))::timestamp with time zone - (metrics.last_metrics)::timestamp with time zone) AS duration_last_metrics
   FROM auth.vessels v,
    metadata,
    metrics
  WHERE ((v.owner_email)::text = current_setting('user.email'::text));


--
-- Name: VIEW vessels_view; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON VIEW api.vessels_view IS 'Expose vessels listing to web api';


--
-- Name: accounts; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.accounts (
    id integer NOT NULL,
    user_id text DEFAULT "right"((gen_random_uuid())::text, 12) NOT NULL,
    email public.citext NOT NULL,
    first text NOT NULL,
    last text NOT NULL,
    pass text NOT NULL,
    role name NOT NULL,
    preferences jsonb DEFAULT '{"email_notifications": true}'::jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    connected_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT accounts_email_check CHECK ((email OPERATOR(public.~*) '^.+@.+\..+$'::public.citext)),
    CONSTRAINT valid_email CHECK ((length((email)::text) > 5)),
    CONSTRAINT valid_first CHECK (((length(first) > 1) AND (length(first) < 512))),
    CONSTRAINT valid_last CHECK (((length(last) > 1) AND (length(last) < 512))),
    CONSTRAINT valid_pass CHECK (((length(pass) > 4) AND (length(pass) < 512)))
);

ALTER TABLE ONLY auth.accounts FORCE ROW LEVEL SECURITY;


--
-- Name: TABLE accounts; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.accounts IS 'users account table';


--
-- Name: COLUMN accounts.first; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.accounts.first IS 'User first name with CONSTRAINT CHECK';


--
-- Name: COLUMN accounts.last; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.accounts.last IS 'User last name with CONSTRAINT CHECK';


--
-- Name: accounts_id_seq; Type: SEQUENCE; Schema: auth; Owner: -
--

ALTER TABLE auth.accounts ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME auth.accounts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: otp; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.otp (
    user_email public.citext NOT NULL,
    otp_pass text NOT NULL,
    otp_timestamp timestamp with time zone DEFAULT now(),
    otp_tries smallint DEFAULT '0'::smallint NOT NULL
);


--
-- Name: TABLE otp; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.otp IS 'Stores temporal otp code for up to 15 minutes';


--
-- Name: aistypes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aistypes (
    id numeric,
    description text
);


--
-- Name: TABLE aistypes; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.aistypes IS 'aistypes AIS Ship Types, https://api.vesselfinder.com/docs/ref-aistypes.html';


--
-- Name: badges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.badges (
    name text,
    description text
);


--
-- Name: TABLE badges; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.badges IS 'Badges descriptions';


--
-- Name: email_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_templates (
    name text,
    email_subject text,
    email_content text,
    pushover_title text,
    pushover_message text
);


--
-- Name: TABLE email_templates; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.email_templates IS 'email/message templates for notifications';


--
-- Name: first_metric; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.first_metric AS
 SELECT "time",
    client_id,
    vessel_id,
    latitude,
    longitude,
    speedoverground,
    courseovergroundtrue,
    windspeedapparent,
    anglespeedapparent,
    status,
    metrics
   FROM api.metrics
  ORDER BY "time"
 LIMIT 1;


--
-- Name: geocoders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.geocoders (
    name text,
    url text,
    reverse_url text
);


--
-- Name: TABLE geocoders; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.geocoders IS 'geo service nominatim url';


--
-- Name: iso3166; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.iso3166 (
    id integer,
    country text,
    alpha_2 text,
    alpha_3 text
);


--
-- Name: TABLE iso3166; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.iso3166 IS 'This is a complete list of all country ISO codes as described in the ISO 3166 international standard. Country Codes Alpha-2 & Alpha-3 https://www.iban.com/country-codes';


--
-- Name: last_metric; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.last_metric AS
 SELECT "time",
    client_id,
    vessel_id,
    latitude,
    longitude,
    speedoverground,
    courseovergroundtrue,
    windspeedapparent,
    anglespeedapparent,
    status,
    metrics
   FROM api.metrics
  ORDER BY "time" DESC
 LIMIT 1;


--
-- Name: mid; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.mid (
    country text,
    id numeric,
    country_id integer
);


--
-- Name: TABLE mid; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.mid IS 'MMSI MID Codes (Maritime Mobile Service Identity) Filtered by Flag of Registration, https://www.marinevesseltraffic.com/2013/11/mmsi-mid-codes-by-flag.html';


--
-- Name: ne_10m_geography_marine_polys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ne_10m_geography_marine_polys (
    gid integer NOT NULL,
    featurecla text,
    name text,
    namealt text,
    changed text,
    note text,
    name_fr text,
    min_label double precision,
    max_label double precision,
    scalerank smallint,
    label text,
    wikidataid text,
    name_ar text,
    name_bn text,
    name_de text,
    name_en text,
    name_es text,
    name_el text,
    name_hi text,
    name_hu text,
    name_id text,
    name_it text,
    name_ja text,
    name_ko text,
    name_nl text,
    name_pl text,
    name_pt text,
    name_ru text,
    name_sv text,
    name_tr text,
    name_vi text,
    name_zh text,
    ne_id bigint,
    name_fa text,
    name_he text,
    name_uk text,
    name_ur text,
    name_zht text,
    geom public.geometry(MultiPolygon,4326)
);


--
-- Name: TABLE ne_10m_geography_marine_polys; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.ne_10m_geography_marine_polys IS 'imperfect but light weight geographic marine areas from https://www.naturalearthdata.com';


--
-- Name: ne_10m_geography_marine_polys_gid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ne_10m_geography_marine_polys ALTER COLUMN gid ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.ne_10m_geography_marine_polys_gid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: process_queue_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.process_queue ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.process_queue_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: stay_in_progress; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.stay_in_progress AS
 SELECT id,
    vessel_id,
    active,
    moorage_id,
    name,
    latitude,
    longitude,
    geog,
    arrived,
    departed,
    duration,
    stay_code,
    notes
   FROM api.stays
  WHERE (active IS TRUE);


--
-- Name: trip_in_progress; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.trip_in_progress AS
 SELECT id,
    vessel_id,
    active,
    name,
    _from_moorage_id,
    _from,
    _from_lat,
    _from_lng,
    _to_moorage_id,
    _to,
    _to_lat,
    _to_lng,
    _from_time,
    _to_time,
    distance,
    duration,
    avg_speed,
    max_speed,
    max_wind_speed,
    notes,
    extra,
    trip,
    trip_cog,
    trip_sog,
    trip_aws AS trip_twa,
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
    trip_heading,
    trip_tank_level,
    trip_solar_voltage,
    trip_solar_power
   FROM api.logbook
  WHERE (active IS TRUE);


--
-- Name: logbook logbook_pkey; Type: CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.logbook
    ADD CONSTRAINT logbook_pkey PRIMARY KEY (id);


--
-- Name: metadata metadata_pkey; Type: CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.metadata
    ADD CONSTRAINT metadata_pkey PRIMARY KEY (vessel_id);


--
-- Name: metadata metadata_vessel_id_key; Type: CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.metadata
    ADD CONSTRAINT metadata_vessel_id_key UNIQUE (vessel_id);


--
-- Name: metrics metrics_pkey; Type: CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE api.metrics
    ADD CONSTRAINT metrics_pkey PRIMARY KEY ("time", vessel_id);


--
-- Name: moorages moorages_pkey; Type: CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.moorages
    ADD CONSTRAINT moorages_pkey PRIMARY KEY (id);


--
-- Name: stays_at stays_at_pkey; Type: CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.stays_at
    ADD CONSTRAINT stays_at_pkey PRIMARY KEY (stay_code);


--
-- Name: stays_at stays_at_stay_code_key; Type: CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.stays_at
    ADD CONSTRAINT stays_at_stay_code_key UNIQUE (stay_code);


--
-- Name: stays stays_pkey; Type: CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.stays
    ADD CONSTRAINT stays_pkey PRIMARY KEY (id);


--
-- Name: accounts accounts_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.accounts
    ADD CONSTRAINT accounts_id_key UNIQUE (id);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (email);


--
-- Name: accounts accounts_user_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.accounts
    ADD CONSTRAINT accounts_user_id_key UNIQUE (user_id);


--
-- Name: otp otp_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.otp
    ADD CONSTRAINT otp_pkey PRIMARY KEY (user_email);


--
-- Name: vessels vessels_mmsi_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.vessels
    ADD CONSTRAINT vessels_mmsi_key UNIQUE (mmsi);


--
-- Name: vessels vessels_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.vessels
    ADD CONSTRAINT vessels_pkey PRIMARY KEY (vessel_id);


--
-- Name: vessels vessels_vessel_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.vessels
    ADD CONSTRAINT vessels_vessel_id_key UNIQUE (vessel_id);


--
-- Name: aistypes aistypes_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aistypes
    ADD CONSTRAINT aistypes_id_key UNIQUE (id);


--
-- Name: app_settings app_settings_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.app_settings
    ADD CONSTRAINT app_settings_name_key UNIQUE (name);


--
-- Name: badges badges_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.badges
    ADD CONSTRAINT badges_name_key UNIQUE (name);


--
-- Name: email_templates email_templates_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_templates
    ADD CONSTRAINT email_templates_name_key UNIQUE (name);


--
-- Name: geocoders geocoders_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.geocoders
    ADD CONSTRAINT geocoders_name_key UNIQUE (name);


--
-- Name: mid mid_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.mid
    ADD CONSTRAINT mid_id_key UNIQUE (id);


--
-- Name: ne_10m_geography_marine_polys ne_10m_geography_marine_polys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ne_10m_geography_marine_polys
    ADD CONSTRAINT ne_10m_geography_marine_polys_pkey PRIMARY KEY (gid);


--
-- Name: process_queue process_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.process_queue
    ADD CONSTRAINT process_queue_pkey PRIMARY KEY (id);


--
-- Name: logbook_active_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_active_idx ON api.logbook USING btree (active);


--
-- Name: logbook_extra_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_extra_idx ON api.logbook USING gin (extra);


--
-- Name: logbook_from_moorage_id_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_from_moorage_id_idx ON api.logbook USING btree (_from_moorage_id);


--
-- Name: logbook_from_moorage_time_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_from_moorage_time_idx ON api.logbook USING btree (_from_moorage_id, _from_time DESC) WHERE (_from_moorage_id IS NOT NULL);


--
-- Name: logbook_from_time_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_from_time_idx ON api.logbook USING btree (_from_time);


--
-- Name: logbook_log_view_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_log_view_idx ON api.logbook USING btree (_from_time DESC) WHERE ((_to_time IS NOT NULL) AND (trip IS NOT NULL));


--
-- Name: logbook_logs_view_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_logs_view_idx ON api.logbook USING btree (_from_time DESC) WHERE ((_to_time IS NOT NULL) AND (name IS NOT NULL));


--
-- Name: logbook_to_moorage_id_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_to_moorage_id_idx ON api.logbook USING btree (_to_moorage_id);


--
-- Name: logbook_to_moorage_time_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_to_moorage_time_idx ON api.logbook USING btree (_to_moorage_id, _to_time DESC) WHERE (_to_moorage_id IS NOT NULL);


--
-- Name: logbook_to_time_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_to_time_idx ON api.logbook USING btree (_to_time);


--
-- Name: logbook_trip_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_trip_idx ON api.logbook USING gist (trip);


--
-- Name: logbook_user_data_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_user_data_idx ON api.logbook USING gin (user_data);


--
-- Name: logbook_vessel_active_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_vessel_active_idx ON api.logbook USING btree (vessel_id, active, _from_time DESC) WHERE (active = true);


--
-- Name: logbook_vessel_id_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_vessel_id_idx ON api.logbook USING btree (vessel_id);


--
-- Name: logbook_vessel_time_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX logbook_vessel_time_idx ON api.logbook USING btree (vessel_id, _from_time DESC, _to_time DESC) INCLUDE (name, distance, duration);


--
-- Name: metadata_user_data_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX metadata_user_data_idx ON api.metadata USING gin (user_data);


--
-- Name: metrics_metrics_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX metrics_metrics_idx ON api.metrics USING gin (metrics);


--
-- Name: metrics_status_time_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX metrics_status_time_idx ON api.metrics USING btree (status, "time" DESC);


--
-- Name: metrics_time_idx; Type: INDEX; Schema: api; Owner: -
--

--CREATE INDEX metrics_time_idx ON api.metrics USING btree ("time" DESC);


--
-- Name: metrics_vessel_id_time_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX metrics_vessel_id_time_idx ON api.metrics USING btree (vessel_id, "time" DESC);


--
-- Name: moorages_geog_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX moorages_geog_idx ON api.moorages USING gist (geog);


--
-- Name: moorages_geog_stay_code_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX moorages_geog_stay_code_idx ON api.moorages USING btree (geog, stay_code) WHERE (geog IS NOT NULL);


--
-- Name: moorages_stay_code_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX moorages_stay_code_idx ON api.moorages USING btree (stay_code);


--
-- Name: moorages_user_data_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX moorages_user_data_idx ON api.moorages USING gin (user_data);


--
-- Name: moorages_vessel_id_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX moorages_vessel_id_idx ON api.moorages USING btree (vessel_id);


--
-- Name: stays_arrived_departed_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX stays_arrived_departed_idx ON api.stays USING btree (arrived DESC, departed, stay_code, moorage_id, name) WHERE ((departed IS NOT NULL) AND (name IS NOT NULL));


--
-- Name: stays_arrived_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX stays_arrived_idx ON api.stays USING btree (arrived);


--
-- Name: stays_departed_arrived_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX stays_departed_arrived_idx ON api.stays USING btree (departed, arrived DESC) WHERE ((departed IS NOT NULL) AND (name IS NOT NULL));


--
-- Name: stays_departed_id_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX stays_departed_id_idx ON api.stays USING btree (departed);


--
-- Name: stays_geog_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX stays_geog_idx ON api.stays USING gist (geog);


--
-- Name: stays_moorage_arrived_departed_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX stays_moorage_arrived_departed_idx ON api.stays USING btree (moorage_id, arrived, departed, active) WHERE (active = false);


--
-- Name: stays_moorage_arrived_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX stays_moorage_arrived_idx ON api.stays USING btree (moorage_id, arrived DESC) WHERE (departed IS NOT NULL);


--
-- Name: stays_moorage_duration_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX stays_moorage_duration_idx ON api.stays USING btree (moorage_id, duration) WHERE (active = false);


--
-- Name: stays_moorage_id_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX stays_moorage_id_idx ON api.stays USING btree (moorage_id);


--
-- Name: stays_stay_code_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX stays_stay_code_idx ON api.stays USING btree (stay_code);


--
-- Name: stays_user_data_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX stays_user_data_idx ON api.stays USING gin (user_data);


--
-- Name: stays_vessel_arrived_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX stays_vessel_arrived_idx ON api.stays USING btree (vessel_id, arrived DESC, departed DESC) INCLUDE (moorage_id, stay_code);


--
-- Name: stays_vessel_id_idx; Type: INDEX; Schema: api; Owner: -
--

CREATE INDEX stays_vessel_id_idx ON api.stays USING btree (vessel_id);


--
-- Name: accounts_preferences_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX accounts_preferences_idx ON auth.accounts USING gin (preferences);


--
-- Name: otp_pass_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX otp_pass_idx ON auth.otp USING btree (otp_pass);


--
-- Name: vessels_owner_email_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX vessels_owner_email_idx ON auth.vessels USING btree (owner_email);


--
-- Name: log_mat_view_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX log_mat_view_id_idx ON public.log_mat_view USING btree (id);


--
-- Name: ne_10m_geography_marine_polys_geom_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ne_10m_geography_marine_polys_geom_idx ON public.ne_10m_geography_marine_polys USING gist (geom);


--
-- Name: process_queue_channel_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX process_queue_channel_idx ON public.process_queue USING btree (channel);


--
-- Name: process_queue_new_logbook_priority_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX process_queue_new_logbook_priority_idx ON public.process_queue USING btree (channel, processed, stored) WHERE (processed IS NULL);


--
-- Name: process_queue_pending_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX process_queue_pending_idx ON public.process_queue USING btree (channel, stored DESC) WHERE (processed IS NULL);


--
-- Name: process_queue_processed_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX process_queue_processed_idx ON public.process_queue USING btree (processed);


--
-- Name: process_queue_ref_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX process_queue_ref_id_idx ON public.process_queue USING btree (ref_id);


--
-- Name: process_queue_stored_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX process_queue_stored_idx ON public.process_queue USING btree (stored);


--
-- Name: logbook logbook_delete_trigger; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER logbook_delete_trigger BEFORE DELETE ON api.logbook FOR EACH ROW EXECUTE FUNCTION public.logbook_delete_trigger_fn();


--
-- Name: TRIGGER logbook_delete_trigger ON logbook; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER logbook_delete_trigger ON api.logbook IS 'BEFORE DELETE ON api.logbook run function public.logbook_delete_trigger_fn to delete reference and logbook_ext need to deleted.';


--
-- Name: logbook logbook_update_user_data_trigger; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER logbook_update_user_data_trigger BEFORE UPDATE ON api.logbook FOR EACH ROW EXECUTE FUNCTION public.update_tbl_userdata_added_at_trigger_fn();


--
-- Name: TRIGGER logbook_update_user_data_trigger ON logbook; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER logbook_update_user_data_trigger ON api.logbook IS 'BEFORE UPDATE ON api.logbook run function public.update_tbl_userdata_added_at_trigger_fn to update the user_data field with current date in ISO format when polar or images change';


--
-- Name: metadata metadata_autodiscovery_trigger; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER metadata_autodiscovery_trigger AFTER INSERT ON api.metadata FOR EACH ROW EXECUTE FUNCTION public.metadata_autodiscovery_trigger_fn();


--
-- Name: TRIGGER metadata_autodiscovery_trigger ON metadata; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER metadata_autodiscovery_trigger ON api.metadata IS 'AFTER INSERT ON api.metadata run function metadata_autodiscovery_trigger_fn for later signalk mapping provisioning on new vessel';


--
-- Name: metadata metadata_grafana_trigger; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER metadata_grafana_trigger AFTER INSERT ON api.metadata FOR EACH ROW EXECUTE FUNCTION public.metadata_grafana_trigger_fn();


--
-- Name: TRIGGER metadata_grafana_trigger ON metadata; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER metadata_grafana_trigger ON api.metadata IS 'AFTER INSERT ON api.metadata run function metadata_grafana_trigger_fn for later grafana provisioning on new vessel';


--
-- Name: metadata metadata_moddatetime; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER metadata_moddatetime BEFORE UPDATE ON api.metadata FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');


--
-- Name: TRIGGER metadata_moddatetime ON metadata; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER metadata_moddatetime ON api.metadata IS 'Automatic update of updated_at on table modification';


--
-- Name: metadata metadata_update_configuration_trigger; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER metadata_update_configuration_trigger BEFORE UPDATE ON api.metadata FOR EACH ROW EXECUTE FUNCTION public.update_metadata_configuration_trigger_fn();


--
-- Name: TRIGGER metadata_update_configuration_trigger ON metadata; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER metadata_update_configuration_trigger ON api.metadata IS 'BEFORE UPDATE ON api.metadata run function api.update_metadata_configuration tp update the configuration field with current date in ISO format';


--
-- Name: metadata metadata_update_user_data_trigger; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER metadata_update_user_data_trigger BEFORE UPDATE ON api.metadata FOR EACH ROW EXECUTE FUNCTION public.update_metadata_userdata_added_at_trigger_fn();


--
-- Name: TRIGGER metadata_update_user_data_trigger ON metadata; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER metadata_update_user_data_trigger ON api.metadata IS 'BEFORE UPDATE ON api.metadata run function public.update_metadata_userdata_added_at_trigger_fn to update the user_data field with current date in ISO format when polar or images change';


--
-- Name: metadata metadata_upsert_trigger; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER metadata_upsert_trigger BEFORE INSERT OR UPDATE ON api.metadata FOR EACH ROW EXECUTE FUNCTION public.metadata_upsert_trigger_fn();


--
-- Name: TRIGGER metadata_upsert_trigger ON metadata; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER metadata_upsert_trigger ON api.metadata IS 'BEFORE INSERT OR UPDATE ON api.metadata run function metadata_upsert_trigger_fn';


--
-- Name: metrics metrics_trigger; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER metrics_trigger BEFORE INSERT ON api.metrics FOR EACH ROW EXECUTE FUNCTION public.metrics_trigger_fn();


--
-- Name: TRIGGER metrics_trigger ON metrics; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER metrics_trigger ON api.metrics IS 'BEFORE INSERT ON api.metrics run function metrics_trigger_fn
Validates: 
- Temporal anomalies (future timestamps, time jumps)
- Coordinate validity
- Generates pre_logbook and new_stay events';


--
-- Name: moorages moorage_delete_trigger; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER moorage_delete_trigger BEFORE DELETE ON api.moorages FOR EACH ROW EXECUTE FUNCTION public.moorage_delete_trigger_fn();


--
-- Name: TRIGGER moorage_delete_trigger ON moorages; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER moorage_delete_trigger ON api.moorages IS 'Automatic delete logbook and stays reference when delete a moorage';


--
-- Name: moorages moorage_update_trigger; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER moorage_update_trigger AFTER UPDATE ON api.moorages FOR EACH ROW EXECUTE FUNCTION public.moorage_update_trigger_fn();


--
-- Name: TRIGGER moorage_update_trigger ON moorages; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER moorage_update_trigger ON api.moorages IS 'Automatic update of name and stay_code on logbook and stays reference';


--
-- Name: moorages moorages_update_user_data_trigger; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER moorages_update_user_data_trigger BEFORE UPDATE ON api.moorages FOR EACH ROW EXECUTE FUNCTION public.update_tbl_userdata_added_at_trigger_fn();


--
-- Name: TRIGGER moorages_update_user_data_trigger ON moorages; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER moorages_update_user_data_trigger ON api.moorages IS 'BEFORE UPDATE ON api.moorages run function public.update_tbl_userdata_added_at_trigger_fn to update the user_data field with current date in ISO format when polar or images change';


--
-- Name: stays stay_delete_trigger; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER stay_delete_trigger BEFORE DELETE ON api.stays FOR EACH ROW EXECUTE FUNCTION public.stay_delete_trigger_fn();


--
-- Name: TRIGGER stay_delete_trigger ON stays; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER stay_delete_trigger ON api.stays IS 'BEFORE DELETE ON api.stays run function public.stay_delete_trigger_fn to delete reference and stay_ext need to deleted.';


--
-- Name: stays stays_update_user_data_trigger; Type: TRIGGER; Schema: api; Owner: -
--

CREATE TRIGGER stays_update_user_data_trigger BEFORE UPDATE ON api.stays FOR EACH ROW EXECUTE FUNCTION public.update_tbl_userdata_added_at_trigger_fn();


--
-- Name: TRIGGER stays_update_user_data_trigger ON stays; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON TRIGGER stays_update_user_data_trigger ON api.stays IS 'BEFORE UPDATE ON api.stays run function public.update_tbl_userdata_added_at_trigger_fn to update the user_data field with current date in ISO format when polar or images change';


--
-- Name: accounts accounts_moddatetime; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE TRIGGER accounts_moddatetime BEFORE UPDATE ON auth.accounts FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');


--
-- Name: TRIGGER accounts_moddatetime ON accounts; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TRIGGER accounts_moddatetime ON auth.accounts IS 'Automatic update of updated_at on table modification';


--
-- Name: accounts encrypt_pass; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE TRIGGER encrypt_pass BEFORE INSERT OR UPDATE ON auth.accounts FOR EACH ROW EXECUTE FUNCTION auth.encrypt_pass();


--
-- Name: TRIGGER encrypt_pass ON accounts; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TRIGGER encrypt_pass ON auth.accounts IS 'execute function auth.encrypt_pass()';


--
-- Name: accounts ensure_user_role_exists; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE CONSTRAINT TRIGGER ensure_user_role_exists AFTER INSERT OR UPDATE ON auth.accounts NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION auth.check_role_exists();


--
-- Name: TRIGGER ensure_user_role_exists ON accounts; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TRIGGER ensure_user_role_exists ON auth.accounts IS 'ensure user role exists';


--
-- Name: vessels ensure_vessel_role_exists; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE CONSTRAINT TRIGGER ensure_vessel_role_exists AFTER INSERT OR UPDATE ON auth.vessels NOT DEFERRABLE INITIALLY IMMEDIATE FOR EACH ROW EXECUTE FUNCTION auth.check_role_exists();


--
-- Name: TRIGGER ensure_vessel_role_exists ON vessels; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TRIGGER ensure_vessel_role_exists ON auth.vessels IS 'ensure vessel role exists';


--
-- Name: accounts new_account_entry; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE TRIGGER new_account_entry AFTER INSERT ON auth.accounts FOR EACH ROW EXECUTE FUNCTION public.new_account_entry_fn();


--
-- Name: TRIGGER new_account_entry ON accounts; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TRIGGER new_account_entry ON auth.accounts IS 'Add new account in process_queue for further processing';


--
-- Name: vessels new_vessel_entry; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE TRIGGER new_vessel_entry AFTER INSERT ON auth.vessels FOR EACH ROW EXECUTE FUNCTION public.new_vessel_entry_fn();


--
-- Name: TRIGGER new_vessel_entry ON vessels; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TRIGGER new_vessel_entry ON auth.vessels IS 'Add new vessel in process_queue for further processing';


--
-- Name: vessels new_vessel_public; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE TRIGGER new_vessel_public AFTER INSERT ON auth.vessels FOR EACH ROW EXECUTE FUNCTION public.new_vessel_public_fn();


--
-- Name: TRIGGER new_vessel_public ON vessels; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TRIGGER new_vessel_public ON auth.vessels IS 'Add new vessel name as public_vessel user configuration';


--
-- Name: vessels new_vessel_trim; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE TRIGGER new_vessel_trim BEFORE INSERT ON auth.vessels FOR EACH ROW EXECUTE FUNCTION public.new_vessel_trim_fn();


--
-- Name: TRIGGER new_vessel_trim ON vessels; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TRIGGER new_vessel_trim ON auth.vessels IS 'Trim space vessel name';


--
-- Name: vessels vessels_moddatetime; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE TRIGGER vessels_moddatetime BEFORE UPDATE ON auth.vessels FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');


--
-- Name: TRIGGER vessels_moddatetime ON vessels; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TRIGGER vessels_moddatetime ON auth.vessels IS 'Automatic update of updated_at on table modification';


--
-- Name: logbook logbook__from_moorage_id_fkey; Type: FK CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.logbook
    ADD CONSTRAINT logbook__from_moorage_id_fkey FOREIGN KEY (_from_moorage_id) REFERENCES api.moorages(id) ON DELETE RESTRICT;


--
-- Name: logbook logbook__to_moorage_id_fkey; Type: FK CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.logbook
    ADD CONSTRAINT logbook__to_moorage_id_fkey FOREIGN KEY (_to_moorage_id) REFERENCES api.moorages(id) ON DELETE RESTRICT;


--
-- Name: logbook logbook_vessel_id_fkey; Type: FK CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.logbook
    ADD CONSTRAINT logbook_vessel_id_fkey FOREIGN KEY (vessel_id) REFERENCES api.metadata(vessel_id) ON DELETE RESTRICT;


--
-- Name: CONSTRAINT logbook_vessel_id_fkey ON logbook; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON CONSTRAINT logbook_vessel_id_fkey ON api.logbook IS 'Link api.stays with api.metadata via vessel_id using FOREIGN KEY and REFERENCES';


--
-- Name: metadata metadata_vessel_id_fkey; Type: FK CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.metadata
    ADD CONSTRAINT metadata_vessel_id_fkey FOREIGN KEY (vessel_id) REFERENCES auth.vessels(vessel_id) ON DELETE RESTRICT;


--
-- Name: CONSTRAINT metadata_vessel_id_fkey ON metadata; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON CONSTRAINT metadata_vessel_id_fkey ON api.metadata IS 'Link api.metadata with auth.vessels via vessel_id using FOREIGN KEY and REFERENCES';


--
-- Name: metrics metrics_vessel_id_fkey; Type: FK CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE api.metrics
    ADD CONSTRAINT metrics_vessel_id_fkey FOREIGN KEY (vessel_id) REFERENCES api.metadata(vessel_id) ON DELETE RESTRICT;


--
-- Name: CONSTRAINT metrics_vessel_id_fkey ON metrics; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON CONSTRAINT metrics_vessel_id_fkey ON api.metrics IS 'Link api.metrics api.metadata via vessel_id using FOREIGN KEY and REFERENCES';


--
-- Name: moorages moorages_stay_code_fkey; Type: FK CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.moorages
    ADD CONSTRAINT moorages_stay_code_fkey FOREIGN KEY (stay_code) REFERENCES api.stays_at(stay_code) ON DELETE RESTRICT;


--
-- Name: moorages moorages_vessel_id_fkey; Type: FK CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.moorages
    ADD CONSTRAINT moorages_vessel_id_fkey FOREIGN KEY (vessel_id) REFERENCES api.metadata(vessel_id) ON DELETE RESTRICT;


--
-- Name: CONSTRAINT moorages_vessel_id_fkey ON moorages; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON CONSTRAINT moorages_vessel_id_fkey ON api.moorages IS 'Link api.stays with api.metadata via vessel_id using FOREIGN KEY and REFERENCES';


--
-- Name: stays stays_moorage_id_fkey; Type: FK CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.stays
    ADD CONSTRAINT stays_moorage_id_fkey FOREIGN KEY (moorage_id) REFERENCES api.moorages(id) ON DELETE RESTRICT;


--
-- Name: stays stays_stay_code_fkey; Type: FK CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.stays
    ADD CONSTRAINT stays_stay_code_fkey FOREIGN KEY (stay_code) REFERENCES api.stays_at(stay_code) ON DELETE RESTRICT;


--
-- Name: stays stays_vessel_id_fkey; Type: FK CONSTRAINT; Schema: api; Owner: -
--

ALTER TABLE ONLY api.stays
    ADD CONSTRAINT stays_vessel_id_fkey FOREIGN KEY (vessel_id) REFERENCES api.metadata(vessel_id) ON DELETE RESTRICT;


--
-- Name: CONSTRAINT stays_vessel_id_fkey ON stays; Type: COMMENT; Schema: api; Owner: -
--

COMMENT ON CONSTRAINT stays_vessel_id_fkey ON api.stays IS 'Link api.stays with api.metadata via vessel_id using FOREIGN KEY and REFERENCES';


--
-- Name: otp otp_user_email_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.otp
    ADD CONSTRAINT otp_user_email_fkey FOREIGN KEY (user_email) REFERENCES auth.accounts(email) ON DELETE RESTRICT;


--
-- Name: vessels vessels_owner_email_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.vessels
    ADD CONSTRAINT vessels_owner_email_fkey FOREIGN KEY (owner_email) REFERENCES auth.accounts(email) ON DELETE RESTRICT;


--
-- Name: logbook admin_all; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY admin_all ON api.logbook to current_user USING (true) WITH CHECK (true);


--
-- Name: metadata admin_all; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY admin_all ON api.metadata to current_user USING (true) WITH CHECK (true);


--
-- Name: metrics admin_all; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY admin_all ON api.metrics to current_user USING (true) WITH CHECK (true);


--
-- Name: moorages admin_all; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY admin_all ON api.moorages to current_user USING (true) WITH CHECK (true);


--
-- Name: stays admin_all; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY admin_all ON api.stays to current_user USING (true) WITH CHECK (true);


--
-- Name: logbook api_anonymous_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_anonymous_role ON api.logbook TO api_anonymous USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK (false);


--
-- Name: metadata api_anonymous_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_anonymous_role ON api.metadata TO api_anonymous USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK (false);


--
-- Name: metrics api_anonymous_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_anonymous_role ON api.metrics TO api_anonymous USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK (false);


--
-- Name: moorages api_anonymous_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_anonymous_role ON api.moorages TO api_anonymous USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK (false);


--
-- Name: stays api_anonymous_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_anonymous_role ON api.stays TO api_anonymous USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK (false);


--
-- Name: logbook api_scheduler_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_scheduler_role ON api.logbook TO scheduler USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));


--
-- Name: metadata api_scheduler_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_scheduler_role ON api.metadata TO scheduler USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));


--
-- Name: metrics api_scheduler_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_scheduler_role ON api.metrics TO scheduler USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));


--
-- Name: moorages api_scheduler_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_scheduler_role ON api.moorages TO scheduler USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));


--
-- Name: stays api_scheduler_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_scheduler_role ON api.stays TO scheduler USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));


--
-- Name: logbook api_user_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_user_role ON api.logbook TO user_role USING ((vessel_id = current_setting('vessel.id'::text, true))) WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));


--
-- Name: metadata api_user_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_user_role ON api.metadata TO user_role USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));


--
-- Name: metrics api_user_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_user_role ON api.metrics TO user_role USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));


--
-- Name: moorages api_user_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_user_role ON api.moorages TO user_role USING ((vessel_id = current_setting('vessel.id'::text, true))) WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));


--
-- Name: stays api_user_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_user_role ON api.stays TO user_role USING ((vessel_id = current_setting('vessel.id'::text, true))) WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));


--
-- Name: logbook api_vessel_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_vessel_role ON api.logbook TO vessel_role USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK (true);


--
-- Name: metadata api_vessel_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_vessel_role ON api.metadata TO vessel_role USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));


--
-- Name: metrics api_vessel_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_vessel_role ON api.metrics TO vessel_role USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));


--
-- Name: moorages api_vessel_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_vessel_role ON api.moorages TO vessel_role USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK (true);


--
-- Name: stays api_vessel_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY api_vessel_role ON api.stays TO vessel_role USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK (true);


--
-- Name: logbook grafana_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY grafana_role ON api.logbook TO grafana USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK (false);


--
-- Name: metadata grafana_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY grafana_role ON api.metadata TO grafana USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK (false);


--
-- Name: metrics grafana_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY grafana_role ON api.metrics TO grafana USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK (false);


--
-- Name: moorages grafana_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY grafana_role ON api.moorages TO grafana USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK (false);


--
-- Name: stays grafana_role; Type: POLICY; Schema: api; Owner: -
--

CREATE POLICY grafana_role ON api.stays TO grafana USING ((vessel_id = current_setting('vessel.id'::text, false))) WITH CHECK (false);


--
-- Name: logbook; Type: ROW SECURITY; Schema: api; Owner: -
--

ALTER TABLE api.logbook ENABLE ROW LEVEL SECURITY;

--
-- Name: metadata; Type: ROW SECURITY; Schema: api; Owner: -
--

ALTER TABLE api.metadata ENABLE ROW LEVEL SECURITY;

--
-- Name: metrics; Type: ROW SECURITY; Schema: api; Owner: -
--

ALTER TABLE api.metrics ENABLE ROW LEVEL SECURITY;

--
-- Name: moorages; Type: ROW SECURITY; Schema: api; Owner: -
--

ALTER TABLE api.moorages ENABLE ROW LEVEL SECURITY;

--
-- Name: stays; Type: ROW SECURITY; Schema: api; Owner: -
--

ALTER TABLE api.stays ENABLE ROW LEVEL SECURITY;

--
-- Name: accounts; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: accounts admin_all; Type: POLICY; Schema: auth; Owner: -
--

CREATE POLICY admin_all ON auth.accounts to current_user USING (true) WITH CHECK (true);


--
-- Name: vessels admin_all; Type: POLICY; Schema: auth; Owner: -
--

CREATE POLICY admin_all ON auth.vessels to current_user USING (true) WITH CHECK (true);


--
-- Name: accounts api_scheduler_role; Type: POLICY; Schema: auth; Owner: -
--

CREATE POLICY api_scheduler_role ON auth.accounts TO scheduler USING (((email)::text = current_setting('user.email'::text, true))) WITH CHECK (((email)::text = current_setting('user.email'::text, true)));


--
-- Name: accounts api_user_role; Type: POLICY; Schema: auth; Owner: -
--

CREATE POLICY api_user_role ON auth.accounts TO user_role USING (((email)::text = current_setting('user.email'::text, true))) WITH CHECK (((email)::text = current_setting('user.email'::text, true)));


--
-- Name: vessels api_user_role; Type: POLICY; Schema: auth; Owner: -
--

CREATE POLICY api_user_role ON auth.vessels TO user_role USING (((vessel_id = current_setting('vessel.id'::text, true)) AND ((owner_email)::text = current_setting('user.email'::text, true)))) WITH CHECK (((vessel_id = current_setting('vessel.id'::text, true)) AND ((owner_email)::text = current_setting('user.email'::text, true))));


--
-- Name: vessels grafana_role; Type: POLICY; Schema: auth; Owner: -
--

CREATE POLICY grafana_role ON auth.vessels TO grafana USING (((owner_email)::text = current_setting('user.email'::text, true))) WITH CHECK (false);


--
-- Name: vessels; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.vessels ENABLE ROW LEVEL SECURITY;

--
-- Name: process_queue admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_all ON public.process_queue to current_user USING (true) WITH CHECK (true);


--
-- Name: process_queue api_scheduler_role; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY api_scheduler_role ON public.process_queue TO scheduler USING (true) WITH CHECK (false);


--
-- Name: process_queue api_user_role; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY api_user_role ON public.process_queue TO user_role USING (((ref_id = current_setting('user.id'::text, true)) OR (ref_id = current_setting('vessel.id'::text, true)))) WITH CHECK (((ref_id = current_setting('user.id'::text, true)) OR (ref_id = current_setting('vessel.id'::text, true))));


--
-- Name: process_queue api_vessel_role; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY api_vessel_role ON public.process_queue TO vessel_role USING (((ref_id = current_setting('user.id'::text, true)) OR (ref_id = current_setting('vessel.id'::text, true)))) WITH CHECK (true);


--
-- Name: process_queue; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.process_queue ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

-- +goose StatementEnd