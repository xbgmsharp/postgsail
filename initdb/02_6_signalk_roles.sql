---------------------------------------------------------------------------
-- singalk db permissions
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

---------------------------------------------------------------------------
-- Permissions roles
-- Users Sharing Role
-- https://postgrest.org/en/stable/auth.html#web-users-sharing-role
--
-- api_anonymous
-- nologin
-- api_anonymous role in the database with which to execute anonymous web requests, limit 10 connections
-- api_anonymous allows JWT token generation with an expiration time via function api.login() from auth.accounts table
create role api_anonymous WITH NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOLOGIN NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 10;
comment on role api_anonymous is
    'The role that PostgREST will switch to when a user is not authenticated.';
-- Limit to 10 connections
--alter user api_anonymous connection limit 10;
grant usage on schema api to api_anonymous;
-- explicitly limit EXECUTE privileges to only signup and login and reset functions
grant execute on function api.login(text,text) to api_anonymous;
grant execute on function api.signup(text,text,text,text) to api_anonymous;
grant execute on function api.recover(text) to api_anonymous;
grant execute on function api.reset(text,text,text) to api_anonymous;
-- explicitly limit EXECUTE privileges to pgrest db-pre-request function
grant execute on function public.check_jwt() to api_anonymous;
-- explicitly limit EXECUTE privileges to only telegram jwt auth function
grant execute on function api.telegram(bigint,text) to api_anonymous;
-- explicitly limit EXECUTE privileges to only pushover subscription validation function
grant execute on function api.email_fn(text) to api_anonymous;
grant execute on function api.pushover_fn(text,text) to api_anonymous;
grant execute on function api.telegram_fn(text,text) to api_anonymous;
grant execute on function api.telegram_otp_fn(text) to api_anonymous;
--grant execute on function api.generate_otp_fn(text) to api_anonymous;

-- authenticator
-- login role
create role authenticator NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT login password 'mysecretpassword';
comment on role authenticator is
    'Role that serves as an entry-point for API servers such as PostgREST.';
grant api_anonymous to authenticator;

-- Grafana user and role with login, read-only, limit 15 connections
CREATE ROLE grafana WITH NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 15 LOGIN PASSWORD 'mysecretpassword';
comment on role grafana is
    'Role that grafana will use for authenticated web users.';
-- Allow API schema and Tables
GRANT USAGE ON SCHEMA api TO grafana;
GRANT USAGE, SELECT ON SEQUENCE api.logbook_id_seq,api.metadata_id_seq,api.moorages_id_seq,api.stays_id_seq TO grafana;
GRANT SELECT ON TABLE api.metrics,api.logbook,api.moorages,api.stays,api.metadata TO grafana;
-- Allow read on VIEWS on API schema
GRANT SELECT ON TABLE api.logs_view,api.moorages_view,api.stays_view TO grafana;
GRANT SELECT ON TABLE api.log_view,api.moorage_view,api.stay_view,api.vessels_view TO grafana;
GRANT SELECT ON TABLE api.metrics,api.logbook,api.moorages,api.stays,api.metadata,api.stays_at TO grafana;
GRANT SELECT ON TABLE api.monitoring_view,api.monitoring_view2,api.monitoring_view3 TO grafana;
GRANT SELECT ON TABLE api.monitoring_humidity,api.monitoring_voltage,api.monitoring_temperatures TO grafana;
-- Allow Auth schema and Tables
GRANT USAGE ON SCHEMA auth TO grafana;
GRANT SELECT ON TABLE auth.vessels TO grafana;
GRANT EXECUTE ON FUNCTION public.citext_eq(citext, citext) TO grafana;

-- Grafana_auth authenticator user and role with login, read-only on auth.accounts, limit 15 connections
CREATE ROLE grafana_auth WITH NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 15 LOGIN PASSWORD 'mysecretpassword';
comment on role grafana_auth is
    'Role that grafana auth proxy authenticator via apache.';
-- Allow read on VIEWS on API schema
GRANT USAGE ON SCHEMA api TO grafana_auth;
GRANT SELECT ON TABLE api.metadata TO grafana_auth;
-- Allow Auth schema and Tables
GRANT USAGE ON SCHEMA auth TO grafana_auth;
GRANT SELECT ON TABLE auth.accounts TO grafana_auth;
GRANT SELECT ON TABLE auth.vessels TO grafana_auth;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO grafana_auth;
GRANT EXECUTE ON FUNCTION public.citext_eq(citext, citext) TO grafana_auth;

-- User:
-- nologin, web api only
-- read-only for all and Read-Write on logbook, stays and moorage except for specific (name, notes) COLUMNS
CREATE ROLE user_role WITH NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION;
comment on role user_role is
    'Role that PostgREST will switch to for authenticated web users.';
GRANT user_role to authenticator;
GRANT USAGE ON SCHEMA api TO user_role;
GRANT USAGE, SELECT ON SEQUENCE api.logbook_id_seq,api.metadata_id_seq,api.moorages_id_seq,api.stays_id_seq TO user_role;
GRANT SELECT ON TABLE api.metrics,api.logbook,api.moorages,api.stays,api.metadata,api.stays_at TO user_role;
GRANT SELECT ON TABLE public.process_queue TO user_role;
-- To check?
GRANT SELECT ON TABLE auth.vessels TO user_role;
-- Allow users to update certain columns
GRANT UPDATE (name, notes) ON api.logbook TO user_role;
GRANT UPDATE (name, notes, stay_code) ON api.stays TO user_role;
GRANT UPDATE (name, notes, stay_code, home_flag) ON api.moorages TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
-- explicitly limit EXECUTE privileges to pgrest db-pre-request function
--GRANT EXECUTE ON FUNCTION public.check_jwt() TO user_role;
-- Allow others functions or allow all in public !! ??
--GRANT EXECUTE ON FUNCTION api.export_logbook_geojson_linestring_fn(int4) TO user_role;
--GRANT EXECUTE ON FUNCTION public.st_asgeojson(text) TO user_role;
--GRANT EXECUTE ON FUNCTION public.geography_eq(geography, geography) TO user_role;
-- TODO should not be need !! ??
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;

-- pg15 feature security_invoker=true,security_barrier=true
GRANT SELECT ON TABLE api.logs_view,api.moorages_view,api.stays_view TO user_role;
GRANT SELECT ON TABLE api.log_view,api.moorage_view,api.stay_view,api.vessels_view TO user_role;
GRANT SELECT ON TABLE api.monitoring_view,api.monitoring_view2,api.monitoring_view3 TO user_role;
GRANT SELECT ON TABLE api.monitoring_humidity,api.monitoring_voltage,api.monitoring_temperatures TO user_role;
GRANT SELECT ON TABLE api.total_info_view TO user_role;
GRANT SELECT ON TABLE api.stats_logs_view TO user_role;
GRANT SELECT ON TABLE api.stats_moorages_view TO user_role;
GRANT SELECT ON TABLE api.eventlogs_view TO user_role;
GRANT SELECT ON TABLE api.vessels_view TO user_role;

-- Vessel:
-- nologin
-- insert-update-only for api.metrics,api.logbook,api.moorages,api.stays,api.metadata and sequences and process_queue
CREATE ROLE vessel_role WITH NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION;
comment on role vessel_role is
    'Role that PostgREST will switch to for authenticated web vessels.';
GRANT vessel_role to authenticator;
GRANT USAGE ON SCHEMA api TO vessel_role;
GRANT INSERT, UPDATE, SELECT ON TABLE api.metrics,api.logbook,api.moorages,api.stays,api.metadata TO vessel_role;
GRANT USAGE, SELECT ON SEQUENCE api.logbook_id_seq,api.metadata_id_seq,api.moorages_id_seq,api.stays_id_seq TO vessel_role;
GRANT INSERT ON TABLE public.process_queue TO vessel_role;
GRANT USAGE, SELECT ON SEQUENCE public.process_queue_id_seq TO vessel_role;
-- explicitly limit EXECUTE privileges to pgrest db-pre-request function
GRANT EXECUTE ON FUNCTION public.check_jwt() to vessel_role;
-- explicitly limit EXECUTE privileges to api.metrics triggers function
GRANT EXECUTE ON FUNCTION public.trip_in_progress_fn(text) to vessel_role;
GRANT EXECUTE ON FUNCTION public.stay_in_progress_fn(text) to vessel_role;
-- hypertable get_partition_hash ?!?
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA _timescaledb_internal TO vessel_role;


--- Scheduler:
-- TODO: currently cron function are run as super user, switch to scheduler role.
-- Scheduler read-only all, and write on api.logbook, api.stays, api.moorages, public.process_queue, auth.otp
-- Crons
--CREATE ROLE scheduler WITH NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION;
CREATE ROLE scheduler WITH NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION CONNECTION LIMIT 10 LOGIN;
comment on role scheduler is
    'Role that pgcron will use to process logbook,moorages,stays,monitoring and notification.';
GRANT scheduler to authenticator;
GRANT USAGE ON SCHEMA api TO scheduler;
GRANT SELECT ON TABLE api.metrics,api.metadata TO scheduler;
GRANT INSERT, UPDATE, SELECT ON TABLE api.logbook,api.moorages,api.stays TO scheduler;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO scheduler;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO scheduler;
GRANT SELECT,UPDATE ON TABLE public.process_queue TO scheduler;
GRANT USAGE ON SCHEMA auth TO scheduler;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO scheduler;
GRANT SELECT,UPDATE,DELETE ON TABLE auth.otp TO scheduler;

---------------------------------------------------------------------------
-- Security policy
-- ROW LEVEL Security policy

ALTER TABLE api.metadata ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.metadata TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow vessel_role to insert and select on their own records
CREATE POLICY api_vessel_role ON api.metadata TO vessel_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (true);
-- Allow user_role to update and select on their own records
CREATE POLICY api_user_role ON api.metadata TO user_role
    USING (vessel_id = current_setting('vessel.id', true))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow scheduler to update and select based on the vessel.id
CREATE POLICY api_scheduler_role ON api.metadata TO scheduler
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow grafana to select based on email
CREATE POLICY grafana_role ON api.metadata TO grafana
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (false);
-- Allow grafana_auth to select
CREATE POLICY grafana_proxy_role ON api.metadata TO grafana_auth
    USING (true)
    WITH CHECK (false);

ALTER TABLE api.metrics ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.metrics TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow vessel_role to insert and select on their own records
CREATE POLICY api_vessel_role ON api.metrics TO vessel_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (true);
-- Allow user_role to update and select on their own records
CREATE POLICY api_user_role ON api.metrics TO user_role
    USING (vessel_id = current_setting('vessel.id', true))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow scheduler to update and select based on the vessel.id
CREATE POLICY api_scheduler_role ON api.metrics TO scheduler
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow grafana to select based on the vessel.id
CREATE POLICY grafana_role ON api.metrics TO grafana
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (false);

-- Be sure to enable row level security on the table
ALTER TABLE api.logbook ENABLE ROW LEVEL SECURITY;
-- Create policies
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.logbook TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow vessel_role to insert and select on their own records
CREATE POLICY api_vessel_role ON api.logbook TO vessel_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (true);
-- Allow user_role to update and select on their own records
CREATE POLICY api_user_role ON api.logbook TO user_role
    USING (vessel_id = current_setting('vessel.id', true))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow scheduler to update and select based on the vessel.id
CREATE POLICY api_scheduler_role ON api.logbook TO scheduler
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow grafana to select based on the vessel.id
CREATE POLICY grafana_role ON api.logbook TO grafana
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (false);

-- Be sure to enable row level security on the table
ALTER TABLE api.stays ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.stays TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow vessel_role to insert and select on their own records
CREATE POLICY api_vessel_role ON api.stays TO vessel_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (true);
-- Allow user_role to update and select on their own records
CREATE POLICY api_user_role ON api.stays TO user_role
    USING (vessel_id = current_setting('vessel.id', true))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow scheduler to update and select based on the vessel_id
CREATE POLICY api_scheduler_role ON api.stays TO scheduler
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow grafana to select based on the vessel_id
CREATE POLICY grafana_role ON api.stays TO grafana
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (false);

-- Be sure to enable row level security on the table
ALTER TABLE api.moorages ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.moorages TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow vessel_role to insert and select on their own records
CREATE POLICY api_vessel_role ON api.moorages TO vessel_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (true);
-- Allow user_role to update and select on their own records
CREATE POLICY api_user_role ON api.moorages TO user_role
    USING (vessel_id = current_setting('vessel.id', true))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow scheduler to update and select based on the vessel_id
CREATE POLICY api_scheduler_role ON api.moorages TO scheduler
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));
-- Allow grafana to select based on the vessel_id
CREATE POLICY grafana_role ON api.moorages TO grafana
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (false);

-- Be sure to enable row level security on the table
ALTER TABLE auth.vessels ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON auth.vessels TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow user_role to update and select on their own records
CREATE POLICY api_user_role ON auth.vessels TO user_role
    USING (vessel_id = current_setting('vessel.id', true)
        AND owner_email = current_setting('user.email', true)
    )
    WITH CHECK (vessel_id = current_setting('vessel.id', true)
        AND owner_email = current_setting('user.email', true)
    );
-- Allow grafana to select based on email
CREATE POLICY grafana_role ON auth.vessels TO grafana
    USING (owner_email = current_setting('user.email', true))
    WITH CHECK (false);
-- Allow grafana to select
CREATE POLICY grafana_proxy_role ON auth.vessels TO grafana_auth
    USING (true)
    WITH CHECK (false);

-- Be sure to enable row level security on the table
ALTER TABLE auth.accounts ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON auth.accounts TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow user_role to update and select on their own records
CREATE POLICY api_user_role ON auth.accounts TO user_role
    USING (email = current_setting('user.email', true))
    WITH CHECK (email = current_setting('user.email', true));
-- Allow scheduler see all rows and add any rows
CREATE POLICY api_scheduler_role ON auth.accounts TO scheduler
    USING (email = current_setting('user.email', true))
    WITH CHECK (email = current_setting('user.email', true));
-- Allow grafana_auth to select
CREATE POLICY grafana_proxy_role ON auth.accounts TO grafana_auth
    USING (true)
    WITH CHECK (false);

-- Be sure to enable row level security on the table
ALTER TABLE public.process_queue ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON public.process_queue TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow vessel_role to insert and select on their own records
CREATE POLICY api_vessel_role ON public.process_queue TO vessel_role
    USING (ref_id = current_setting('user.id', true) OR ref_id = current_setting('vessel.id', true))
    WITH CHECK (true);
-- Allow user_role to update and select on their own records
CREATE POLICY api_user_role ON public.process_queue TO user_role
    USING (ref_id = current_setting('user.id', true) OR ref_id = current_setting('vessel.id', true))
    WITH CHECK (ref_id = current_setting('user.id', true) OR ref_id = current_setting('vessel.id', true));
-- Allow scheduler see all rows and updates any rows
CREATE POLICY api_scheduler_role ON public.process_queue TO scheduler
    USING (true)
    WITH CHECK (false);
