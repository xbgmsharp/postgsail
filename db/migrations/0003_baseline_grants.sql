-- +goose Up
-- +goose StatementBegin

SET default_transaction_read_only = off;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

-- =====================================================
-- api_anonymous
-- =====================================================

GRANT api_anonymous TO authenticator;
GRANT USAGE ON SCHEMA api TO api_anonymous;
-- explicitly limit EXECUTE privileges to only signup and login and reset functions
GRANT EXECUTE ON FUNCTION api.login(text,text) TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.signup(text,text,text,text) TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.recover(text) TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.reset(text,text,text) TO api_anonymous;
-- explicitly limit EXECUTE privileges to pgrest db-pre-request function
GRANT EXECUTE ON FUNCTION public.check_jwt() TO api_anonymous;
-- explicitly limit EXECUTE privileges to only telegram jwt auth function
GRANT EXECUTE ON FUNCTION api.telegram(bigint,text) TO api_anonymous;
-- explicitly limit EXECUTE privileges to only pushover subscription validation function
GRANT EXECUTE ON FUNCTION api.email_fn(text) to api_anonymous;
GRANT EXECUTE ON FUNCTION api.pushover_fn(text,text) TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.telegram_fn(text,text) TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.telegram_otp_fn(text) TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.ispublic_fn(text,text,integer) TO api_anonymous;
-- explicitly limit EXECUTE privileges to only public stats functions
GRANT EXECUTE ON FUNCTION api.stats_logs_fn TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.stats_stays_fn TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.status_fn TO api_anonymous;
-- explicitly limit EXECUTE privileges to only replay functions
GRANT EXECUTE ON FUNCTION api.export_logbooks_geojson_linestring_trips_fn to api_anonymous;
GRANT EXECUTE ON FUNCTION api.export_logbooks_geojson_point_trips_fn to api_anonymous;
GRANT EXECUTE ON FUNCTION api.export_logbook_geojson_trip_fn to api_anonymous;
GRANT EXECUTE ON FUNCTION api.export_logbook_metrics_trip_fn to api_anonymous;
GRANT EXECUTE ON FUNCTION api.logbook_update_geojson_trip_fn TO api_anonymous;
-- Allow read on tables and views on API schema
GRANT SELECT ON ALL TABLES IN SCHEMA api TO api_anonymous;
-- Allow all public schema functions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO api_anonymous;

-- =====================================================
-- user_role
-- =====================================================

GRANT user_role to authenticator;
GRANT USAGE ON SCHEMA api TO user_role;
-- Allow read on SEQUENCE on API schema
GRANT USAGE, SELECT ON SEQUENCE api.logbook_id_seq,api.moorages_id_seq,api.stays_id_seq TO user_role;
-- Allow read on TABLES on API schema
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
-- Allow users to update certain columns on specific TABLES on API schema
GRANT UPDATE ON api.logbook TO user_role;
GRANT UPDATE (name, notes, stay_code, active, departed, user_data) ON api.stays TO user_role;
GRANT UPDATE (name, notes, stay_code, home_flag, user_data) ON api.moorages TO user_role;
GRANT UPDATE (configuration, user_data) ON api.metadata TO user_role;
GRANT UPDATE (status) ON api.metrics TO user_role;
-- Allow users to remove logs, stays and moorages
GRANT DELETE ON api.logbook,api.stays,api.moorages TO user_role;
GRANT DELETE ON TABLE public.process_queue TO user_role;
-- Allow EXECUTE on all FUNCTIONS on API schema
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
-- auth schema, vessels read only
GRANT USAGE ON SCHEMA auth TO user_role;
GRANT SELECT ON TABLE auth.vessels TO user_role;
-- process_queue table read only
GRANT SELECT ON TABLE public.process_queue TO user_role;
-- public schema with temporal tables
GRANT USAGE, CREATE ON SCHEMA public TO user_role;
-- Allow EXECUTE on all FUNCTIONS on public schema
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;

-- =====================================================
-- vessel_role
-- =====================================================

GRANT vessel_role to authenticator;
GRANT USAGE ON SCHEMA api TO vessel_role;
-- Allow read on SEQUENCE on API schema
GRANT USAGE, SELECT ON SEQUENCE api.logbook_id_seq,api.moorages_id_seq,api.stays_id_seq TO vessel_role;
-- Allow read/write on TABLES on API schema
GRANT INSERT, UPDATE, SELECT ON TABLE api.metrics,api.logbook,api.moorages,api.stays,api.metadata TO vessel_role;
GRANT INSERT ON TABLE public.process_queue TO vessel_role;
GRANT USAGE, SELECT ON SEQUENCE public.process_queue_id_seq TO vessel_role;
-- explicitly limit EXECUTE privileges to pgrest db-pre-request function
GRANT EXECUTE ON FUNCTION public.check_jwt() to vessel_role;
-- explicitly limit EXECUTE privileges to api.metrics triggers function
GRANT EXECUTE ON FUNCTION public.trip_in_progress_fn(text) to vessel_role;
GRANT EXECUTE ON FUNCTION public.stay_in_progress_fn(text) to vessel_role;
-- hypertable get_partition_hash ?!?
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA _timescaledb_internal TO vessel_role;
-- on metrics st_makepoint
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO vessel_role;

-- =====================================================
-- grafana
-- =====================================================

-- Allow API schema and Tables
GRANT USAGE ON SCHEMA api TO grafana;
-- Allow read on SEQUENCE on API schema
GRANT USAGE, SELECT ON SEQUENCE api.logbook_id_seq,api.moorages_id_seq,api.stays_id_seq TO grafana;
-- Allow read on TABLES on API schema
GRANT SELECT ON TABLE api.metrics,api.logbook,api.moorages,api.stays,api.metadata,api.stays_at TO grafana;
-- Allow read on VIEWS on API schema
GRANT SELECT ON TABLE api.logs_view,api.moorages_view,api.stays_view TO grafana;
GRANT SELECT ON TABLE api.log_view,api.moorage_view,api.stay_view,api.vessels_view TO grafana;
GRANT SELECT ON TABLE api.monitoring_view,api.monitoring_view2,api.monitoring_view3 TO grafana;
GRANT SELECT ON TABLE api.monitoring_humidity,api.monitoring_voltage,api.monitoring_temperatures TO grafana;
-- Allow Auth schema and Tables
GRANT USAGE ON SCHEMA auth TO grafana;
GRANT SELECT ON TABLE auth.vessels TO grafana;
GRANT EXECUTE ON FUNCTION public.citext_eq(citext, citext) TO grafana;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO grafana;

-- =====================================================
-- scheduler
-- =====================================================

GRANT scheduler to authenticator;
-- Allow API schema and Tables
GRANT USAGE ON SCHEMA api TO scheduler;
GRANT SELECT ON TABLE api.metrics,api.metadata TO scheduler;
GRANT INSERT, UPDATE, SELECT ON TABLE api.logbook,api.moorages,api.stays TO scheduler;
-- Allow public schema and Tables
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO scheduler;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO scheduler;
GRANT SELECT,UPDATE ON TABLE public.process_queue TO scheduler;
-- Allow Auth schema and Tables
GRANT USAGE ON SCHEMA auth TO scheduler;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO scheduler;
GRANT SELECT,UPDATE,DELETE ON TABLE auth.otp TO scheduler;

-- +goose StatementEnd
