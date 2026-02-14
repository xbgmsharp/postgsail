-- +goose Up
-- +goose StatementBegin

SET default_transaction_read_only = off;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Roles
--

CREATE ROLE authenticator WITH NOSUPERUSER NOINHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 40;
COMMENT ON ROLE authenticator IS 'Role that serves as an entry-point for API servers such as PostgREST.';
CREATE ROLE api_anonymous WITH NOSUPERUSER NOINHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 40;
COMMENT ON ROLE api_anonymous IS 'Role that PostgREST will switch to when a user is not authenticated.';
CREATE ROLE user_role WITH NOSUPERUSER NOINHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION NOBYPASSRLS;
COMMENT ON ROLE user_role IS 'Role that PostgREST will switch to for authenticated web users.';
CREATE ROLE vessel_role WITH NOSUPERUSER NOINHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION NOBYPASSRLS;
COMMENT ON ROLE vessel_role IS 'Role that PostgREST will switch to for authenticated web vessels.';
CREATE ROLE grafana WITH NOSUPERUSER NOINHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 30;
COMMENT ON ROLE grafana IS 'Role that grafana will use for authenticated web users.';
CREATE ROLE scheduler WITH NOSUPERUSER NOINHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS CONNECTION LIMIT 10;
COMMENT ON ROLE scheduler IS 'Role that pgcron will use to process logbook,moorages,stays,monitoring and notification.';

--
-- Role memberships
--

GRANT api_anonymous TO authenticator;
GRANT user_role TO authenticator;
GRANT vessel_role TO authenticator;

-- +goose StatementEnd
