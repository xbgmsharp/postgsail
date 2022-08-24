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
-- api_anonymous role in the database with which to execute anonymous web requests.
-- api_anonymous allows JWT token generation with an expiration time via function api.login() from auth.accounts table
create role api_anonymous nologin noinherit;
grant usage on schema api to api_anonymous;
-- explicitly limit EXECUTE privileges to only signup and login functions
grant execute on function api.login(text,text) to api_anonymous;
grant execute on function api.signup(text,text,text,text) to api_anonymous;
-- explicitly limit EXECUTE privileges to pgrest db-pre-request function
grant execute on function public.check_jwt() to api_anonymous;

-- authenticator
-- login role
create role authenticator noinherit login password 'mysecretpassword';
grant api_anonymous to authenticator;

-- Grafana user and role with login, read-only
CREATE ROLE grafana WITH LOGIN PASSWORD 'mysecretpassword';
GRANT USAGE ON SCHEMA api TO grafana;
GRANT USAGE, SELECT ON SEQUENCE api.logbook_id_seq,api.metadata_id_seq,api.moorages_id_seq,api.stays_id_seq TO grafana;
GRANT SELECT ON TABLE api.metrics,api.logbook,api.moorages,api.stays,api.metadata TO grafana;

-- User:
-- nologin
-- read-only for all and Read-Write on logbook, stays and moorage except for name COLUMN ?
CREATE ROLE user_role WITH NOLOGIN;
GRANT user_role to authenticator;
GRANT USAGE ON SCHEMA api TO user_role;
GRANT USAGE, SELECT ON SEQUENCE api.logbook_id_seq,api.metadata_id_seq,api.moorages_id_seq,api.stays_id_seq TO user_role;
GRANT SELECT ON TABLE api.metrics,api.logbook,api.moorages,api.stays,api.metadata TO user_role;
-- Allow update on table for notes
GRANT UPDATE ON TABLE api.logbook,api.moorages,api.stays TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
-- explicitly limit EXECUTE privileges to pgrest db-pre-request function
GRANT EXECUTE ON FUNCTION public.check_jwt() to user_role;
-- Allow read on VIEWS
GRANT SELECT ON TABLE api.logs_view,api.moorages_view,api.stays_view TO user_role;

-- Vessel:
-- nologin
-- insert-update-only for api.metrics,api.logbook,api.moorages,api.stays,api.metadata and sequences and process_queue
CREATE ROLE vessel_role WITH NOLOGIN;
GRANT vessel_role to authenticator;
GRANT USAGE ON SCHEMA api TO vessel_role;
GRANT INSERT, UPDATE, SELECT ON TABLE api.metrics,api.logbook,api.moorages,api.stays,api.metadata TO vessel_role;
GRANT USAGE, SELECT ON SEQUENCE api.logbook_id_seq,api.metadata_id_seq,api.moorages_id_seq,api.stays_id_seq TO vessel_role;
GRANT INSERT ON TABLE public.process_queue TO vessel_role;
GRANT USAGE, SELECT ON SEQUENCE public.process_queue_id_seq TO vessel_role;
-- explicitly limit EXECUTE privileges to pgrest db-pre-request function
GRANT EXECUTE ON FUNCTION public.check_jwt() to vessel_role;

-- TODO: currently cron function are run as super user, switch to scheduler role.
-- Scheduler read-only all, and write on logbook, stays, moorage, process_queue
-- Crons
CREATE ROLE scheduler WITH NOLOGIN;
GRANT scheduler to authenticator;
GRANT EXECUTE ON FUNCTION api.run_cron_jobs() to scheduler;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO scheduler;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO scheduler;
GRANT SELECT,UPDATE ON TABLE process_queue TO scheduler;
GRANT USAGE ON SCHEMA auth TO scheduler;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO scheduler;

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
    USING (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%')
    WITH CHECK (true);
-- Allow user_role to update and select on their own records
CREATE POLICY api_user_role ON api.metadata TO user_role
    USING (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%')
    WITH CHECK (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%');

ALTER TABLE api.metrics ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.metrics TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow vessel_role to insert and select on their own records
CREATE POLICY api_vessel_role ON api.metrics TO vessel_role
    USING (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%')
    WITH CHECK (true);
-- Allow user_role to update and select on their own records
CREATE POLICY api_user_role ON api.metrics TO user_role
    USING (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%')
    WITH CHECK (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%');

-- Be sure to enable row level security on the table
ALTER TABLE api.logbook ENABLE ROW LEVEL SECURITY;
-- Create policies
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.logbook TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow vessel_role to insert and select on their own records
CREATE POLICY api_vessel_role ON api.logbook TO vessel_role
    USING (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%')
    WITH CHECK (true);
-- Allow user_role to update and select on their own records
CREATE POLICY api_user_role ON api.logbook TO user_role
    USING (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%')
    WITH CHECK (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%');

-- Be sure to enable row level security on the table
ALTER TABLE api.stays ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.stays TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow vessel_role to insert and select on their own records
CREATE POLICY api_vessel_role ON api.stays TO vessel_role
    USING (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%')
    WITH CHECK (true);
-- Allow user_role to update and select on their own records
CREATE POLICY api_user_role ON api.stays TO user_role
    USING (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%')
    WITH CHECK (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%');

-- Be sure to enable row level security on the table
ALTER TABLE api.moorages ENABLE ROW LEVEL SECURITY;
-- Administrator can see all rows and add any rows
CREATE POLICY admin_all ON api.moorages TO current_user
    USING (true)
    WITH CHECK (true);
-- Allow vessel_role to insert and select on their own records
CREATE POLICY api_vessel_role ON api.moorages TO vessel_role
    USING (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%')
    WITH CHECK (true);
-- Allow user_role to update and select on their own records
CREATE POLICY api_user_role ON api.moorages TO user_role
    USING (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%')
    WITH CHECK (client_id LIKE '%' || current_setting('vessel.mmsi', false) || '%');
