-- +goose Up
-- +goose StatementBegin
---------------------------------------------------------------------------
-- Copyright 2021-2026 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration March/April 2026
--

set timezone to 'UTC';

-- Only the authenticator needs a connection limit (for PostgREST pool)
ALTER ROLE authenticator CONNECTION LIMIT 40;

-- Remove limits from roles that cannot login (they inherit from authenticator)
ALTER ROLE api_anonymous CONNECTION LIMIT -1;  -- -1 = unlimited
ALTER ROLE user_role CONNECTION LIMIT -1;
ALTER ROLE vessel_role CONNECTION LIMIT -1;

-- Silence the high-frequency ingestion roles entirely
ALTER ROLE vessel_role SET log_min_duration_statement = -1;

-- Bot role
-- nologin, api only
-- read-only for all with read on logbook, stays and moorages
CREATE ROLE bot_role WITH NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS NOREPLICATION;
ALTER ROLE bot_role CONNECTION LIMIT -1;
comment on role bot_role is
    'Role as user_role in Read-Only for connecting Bot applications (Telegram) to PostgSail.';
GRANT bot_role to authenticator;
GRANT USAGE ON SCHEMA api TO bot_role;
-- Allow read on SEQUENCE on API schema
GRANT USAGE, SELECT ON SEQUENCE api.logbook_id_seq,api.moorages_id_seq,api.stays_id_seq TO bot_role;
-- Allow read on TABLES on API schema
GRANT SELECT ON TABLE api.metrics,api.logbook,api.moorages,api.stays,api.metadata,api.stays_at TO bot_role;
GRANT SELECT ON TABLE public.process_queue TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO bot_role;

-- pg15 feature security_invoker=true,security_barrier=true
GRANT SELECT ON TABLE api.logs_view,api.moorages_view,api.stays_view TO bot_role;
GRANT SELECT ON TABLE api.log_view,api.moorage_view,api.stay_view,api.vessels_view TO bot_role;
GRANT SELECT ON TABLE api.monitoring_view,api.monitoring_live TO bot_role;
GRANT SELECT ON TABLE api.stats_moorages_away_view,api.versions_view TO bot_role;
GRANT SELECT ON TABLE api.total_info_view TO bot_role;
GRANT SELECT ON TABLE api.stats_logs_view TO bot_role;
GRANT SELECT ON TABLE api.stats_moorages_view TO bot_role;
GRANT SELECT ON TABLE api.eventlogs_view TO bot_role;
GRANT SELECT ON TABLE api.vessels_view TO bot_role;
GRANT SELECT ON TABLE api.moorages_stays_view TO bot_role;
GRANT SELECT ON TABLE api.vessels_view TO bot_role;

-- Allow bot_role to update and select based on the vessel.id
CREATE POLICY api_bot_role ON api.logbook TO bot_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (false);
CREATE POLICY api_bot_role ON api.moorages TO bot_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (false);
CREATE POLICY api_bot_role ON api.stays TO bot_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (false);
CREATE POLICY api_bot_role ON api.metadata TO bot_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (false);
CREATE POLICY api_bot_role ON api.metrics TO bot_role
    USING (vessel_id = current_setting('vessel.id', false))
    WITH CHECK (false);

-- Add missing comment on functions
COMMENT ON FUNCTION api.register_vessel IS 'Register a vessel for the current user, return vessel JWT token';
COMMENT ON FUNCTION api.signup IS 'Register a user, return user JWT token';
COMMENT ON FUNCTION auth.user_role IS 'user_role is a role for authenticated users, allows access to user-specific data and actions';
COMMENT ON FUNCTION auth.check_role_exists IS 'Ensure role_exists';
COMMENT ON FUNCTION public.new_vessel_entry_fn IS 'Add new_vessel in process_queue, for later notification';
COMMENT ON FUNCTION public.new_vessel_public_fn IS 'Update user settings with a public vessel name';
COMMENT ON FUNCTION public.valtopercent IS 'Convert a fraction [0.0–1.0] to a percentage [0–100]. Example: 0.75 → 75.';
COMMENT ON FUNCTION public.generate_uid_fn(size integer) IS
    'Generate a random numeric-only string of given length (digits 0-9). '
    'INTENTIONALLY digit-only: used by generate_otp_fn to produce numeric OTP codes. '
    'Do NOT replace with nanoid() which includes letters.';

COMMENT ON FUNCTION public.nanoid(size integer) IS
    'Generate a random alphanumeric ID (0-9A-Za-z) of given length. Default size=12. '
    'For numeric-only IDs (e.g. OTP codes) use generate_uid_fn() instead.';

-- Add Missing UNIQUE Constraint on auth.accounts.email
ALTER TABLE auth.accounts ADD CONSTRAINT accounts_email_unique UNIQUE (email);

-- Add missing index on accounts email for authentication
CREATE INDEX accounts_email_idx ON auth.accounts (email);

-- Add Missing Primary Keys on Reference Tables.
ALTER TABLE public.badges          ADD PRIMARY KEY (name);
ALTER TABLE public.email_templates ADD PRIMARY KEY (name);

-- Update tables comments
COMMENT ON TABLE api.logbook IS 'The logbook table stores vessel navigation entries with timestamps, locations, and trip metrics. RLS policies filter by vessel_id automatically.
These indexes optimize different query patterns while minimizing storage.';
COMMENT ON TABLE api.stays IS 'The stays table records time spent at moorages. Each stay links a moorage with arrival/departure timestamps. RLS policies filter by vessel_id.';
COMMENT ON TABLE api.moorages IS 'The moorages table stores locations where vessels can stay (marinas, anchorages, etc.). Each moorage has geographic coordinates and metadata.';
COMMENT ON TABLE api.metadata IS 'Stores metadata received from vessel, aka signalk plugin. single-row-per-vessel store';

-- Replace the existing function comment:
COMMENT ON FUNCTION public.metadata_upsert_trigger_fn() IS
  'process metadata from vessel, upsert.
   MMSI: stored as text (intentionally permissive) because SignalK delivers raw user
   input which may be invalid (wrong length, non-numeric, etc.).
   The trigger silently nulls any value not matching ^\d{9}$.
   This intentionally differs from auth.vessels.mmsi (numeric, validated, range-constrained).';

COMMENT ON COLUMN api.metadata.mmsi IS
  'MMSI as reported by the SignalK plugin. Stored as text because raw user input
   may be non-numeric or malformed. Silently nulled by metadata_upsert_trigger_fn
   if it does not match the 9-digit pattern ^\d{9}$.
   Intentionally differs from auth.vessels.mmsi (numeric, validated).
   Never JOIN this column to auth.vessels.mmsi — use vessel_id instead.';

-- Optionally reinforce on auth.vessels.mmsi (already has a good comment, minor addition):
COMMENT ON COLUMN auth.vessels.mmsi IS
  'MMSI as a validated numeric value with CHECK constraint enforcing range.
   Intentionally differs from api.metadata.mmsi (text, permissive).
   This is the authoritative MMSI — api.metadata.mmsi is the raw SignalK input.';

COMMENT ON TABLE api.metrics IS
  'Stores time-series metrics from vessel via SignalK plugin.
   TimescaleDB hypertable partitioned by time.

   COMPRESSION NOTE: TimescaleDB columnar compression is intentionally NOT enabled.
   This table uses FORCE ROW LEVEL SECURITY for multi-tenant isolation — TimescaleDB
   Community Edition does not support compression on hypertables with RLS enabled.
   Enabling compression here will silently break RLS enforcement on compressed chunks.
   Do not add add_compression_policy() to this table without first migrating to
   a separate-database-per-tenant model or TimescaleDB Enterprise.';

-- api.eventlogs_view source
DROP VIEW IF EXISTS api.eventlogs_view;
-- Convert process_queue.id is still integer — bigint to avoid sequence exhaustion at sustained load. This is a multi-step process that requires dropping and re-adding the identity property, which is only supported in PG 16+ without a table rewrite. For older versions, this will cause a table rewrite, but it's necessary to avoid future issues with sequence exhaustion.
-- Step 1: detach the identity so we can retype the column
ALTER TABLE public.process_queue
    ALTER COLUMN id DROP IDENTITY IF EXISTS;
 -- Step 2: retype — requires table rewrite on PG < 16
ALTER TABLE public.process_queue
    ALTER COLUMN id TYPE bigint;
-- Step 3: reattach identity as bigint
ALTER TABLE public.process_queue
    ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
        SEQUENCE NAME public.process_queue_id_seq
        START WITH 1
        INCREMENT BY 1
        NO MINVALUE
        NO MAXVALUE
        CACHE 1
    );
-- resync the sequence as a safety measure after any identity DDL:
SELECT setval(
    pg_get_serial_sequence('public.process_queue', 'id'),
    (SELECT MAX(id) FROM public.process_queue),
    true
);
COMMENT ON COLUMN public.process_queue.id IS
    'bigint primary key (upgraded from integer to avoid sequence exhaustion at sustained load).';
-- Re create view with bigint id
CREATE OR REPLACE VIEW api.eventlogs_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT id,
    channel,
    payload,
    ref_id,
    stored,
    processed
   FROM process_queue pq
  WHERE processed IS NOT NULL AND channel <> 'new_stay'::text AND channel <> 'pre_logbook'::text AND channel <> 'post_logbook'::text AND (ref_id = current_setting('user.id'::text, true) OR ref_id = current_setting('vessel.id'::text, true))
  ORDER BY id DESC;
COMMENT ON VIEW api.eventlogs_view IS 'Event logs view';

-- Addd updated_at on api.logbook, api.stays, api.moorages
-- --- api.logbook ---
ALTER TABLE api.logbook
    ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
 
COMMENT ON COLUMN api.logbook.updated_at IS
    'Timestamp of last row modification, maintained automatically by logbook_moddatetime trigger. Use for incremental sync.';

CREATE INDEX IF NOT EXISTS logbook_vessel_updated_at_idx
    ON api.logbook USING btree (vessel_id, updated_at DESC);

COMMENT ON INDEX api.logbook_vessel_updated_at_idx IS
    'Supports incremental sync: WHERE vessel_id = $1 AND updated_at > $cursor';

CREATE TRIGGER logbook_moddatetime
    BEFORE UPDATE ON api.logbook
    FOR EACH ROW
    EXECUTE FUNCTION public.moddatetime('updated_at');

COMMENT ON TRIGGER logbook_moddatetime ON api.logbook IS
    'Automatic update of updated_at on table modification';

-- --- api.stays ---
ALTER TABLE api.stays
    ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

COMMENT ON COLUMN api.stays.updated_at IS
    'Timestamp of last row modification, maintained automatically by stays_moddatetime trigger. Use for incremental sync.';

CREATE INDEX IF NOT EXISTS stays_vessel_updated_at_idx
    ON api.stays USING btree (vessel_id, updated_at DESC);

COMMENT ON INDEX api.stays_vessel_updated_at_idx IS
    'Supports incremental sync: WHERE vessel_id = $1 AND updated_at > $cursor';

CREATE TRIGGER stays_moddatetime
    BEFORE UPDATE ON api.stays
    FOR EACH ROW
    EXECUTE FUNCTION public.moddatetime('updated_at');

COMMENT ON TRIGGER stays_moddatetime ON api.stays IS
    'Automatic update of updated_at on table modification';

-- --- api.moorages ---
ALTER TABLE api.moorages
    ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
    ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

COMMENT ON COLUMN api.moorages.updated_at IS
    'Timestamp of last row modification, maintained automatically by moorages_moddatetime trigger. Use for incremental sync.';

CREATE INDEX IF NOT EXISTS moorages_vessel_updated_at_idx
    ON api.moorages USING btree (vessel_id, updated_at DESC);

COMMENT ON INDEX api.moorages_vessel_updated_at_idx IS
    'Supports incremental sync: WHERE vessel_id = $1 AND updated_at > $cursor';

CREATE TRIGGER moorages_moddatetime
    BEFORE UPDATE ON api.moorages
    FOR EACH ROW
    EXECUTE FUNCTION public.moddatetime('updated_at');

COMMENT ON TRIGGER moorages_moddatetime ON api.moorages IS
    'Automatic update of updated_at on table modification';

-- --- api.metadata ---
ALTER TABLE api.metadata ALTER COLUMN ip TYPE inet USING ip::inet;

-- DROP unused/unneeded materialized views
DROP VIEW IF EXISTS api.log_mat_view CASCADE;
DROP VIEW IF EXISTS api.logs_mat_view CASCADE;
DROP MATERIALIZED VIEW IF EXISTS public.log_mat_view CASCADE;
DROP MATERIALIZED VIEW IF EXISTS public.logs_mat_view CASCADE;

-- iso3166 currently has NO primary key at all
ALTER TABLE public.iso3166 ADD PRIMARY KEY (id);
ALTER TABLE public.aistypes ADD PRIMARY KEY (id);  -- already has UNIQUE, promote to PK

-- These tables never change, so no WAL needed
ALTER TABLE public.iso3166 SET UNLOGGED;
ALTER TABLE public.aistypes SET UNLOGGED;
ALTER TABLE public.mid SET UNLOGGED;

-- Enforce non-nullable columns with defaults to prevent future nulls and simplify queries
ALTER TABLE api.metadata
  ALTER COLUMN plugin_version  SET DEFAULT 'unknown',
  ALTER COLUMN signalk_version SET DEFAULT 'unknown',
  ALTER COLUMN time            SET DEFAULT NOW();

-- Standardise on m.geog directly
ALTER TABLE api.moorages ADD CONSTRAINT moorages_geog_consistent
  CHECK (geog = Geography(ST_MakePoint(longitude, latitude)));
COMMENT ON CONSTRAINT moorages_geog_consistent ON api.moorages IS
    'Ensure geog column is consistent with longitude and latitude columns';
ALTER TABLE api.stays ADD CONSTRAINT stays_geog_consistent
  CHECK (geog = Geography(ST_MakePoint(longitude, latitude)));
COMMENT ON CONSTRAINT stays_geog_consistent ON api.stays IS
    'Ensure geog column is consistent with longitude and latitude columns';

-- DROP FUNCTION unused orphan trigger functions
DROP FUNCTION IF EXISTS public.stay_completed_trigger_fn;
DROP FUNCTION IF EXISTS public.logbook_completed_trigger_fn;
DROP FUNCTION IF EXISTS public.update_logbook_with_geojson_trigger_fn;
DROP TRIGGER IF EXISTS metadata_grafana_trigger ON api.metadata;
DROP FUNCTION IF EXISTS public.metadata_grafana_trigger_fn;
DROP FUNCTION IF EXISTS public.grafana_py_fn;
DROP FUNCTION IF EXISTS public.cron_process_grafana_fn;
DROP FUNCTION IF EXISTS public.dump_account_fn;
DROP VIEW IF EXISTS api.noteshistory_view;
DROP FUNCTION IF EXISTS public.process_account_queue_fn;
DROP FUNCTION IF EXISTS public.process_vessel_queue_fn;
DROP FUNCTION IF EXISTS public.telegram_user_exists_fn;
DROP FUNCTION IF EXISTS public.geojson_py_fn;
DROP FUNCTION IF EXISTS public.set_vessel_settings_from_vesselid_fn;
DROP FUNCTION IF EXISTS public.reverse_geoip_py_fn;

-- active Columns Not Uniformly Constrained
ALTER TABLE api.logbook  ALTER COLUMN active SET NOT NULL;
ALTER TABLE api.stays    ALTER COLUMN active SET NOT NULL, ALTER COLUMN active SET DEFAULT false;
ALTER TABLE api.metadata ALTER COLUMN active SET NOT NULL;

-- Drop unused/unneeded index - bad performance and not used by any query - zero-scan indexes
ALTER TABLE auth.accounts DROP CONSTRAINT accounts_id_key;
DROP INDEX IF EXISTS auth.accounts_id_key;
DROP INDEX IF EXISTS auth.accounts_preferences_idx;
DROP INDEX IF EXISTS api.stays_geog_idx; -- per-vessel stays volume is small enough for seq scan to win
DROP INDEX IF EXISTS api.moorages_geog_idx; -- per-vessel stays volume is small enough for seq scan to win
DROP INDEX IF EXISTS api.metrics_metrics_idx; -- The GIN index is genuinely unused and consuming serious disk space. 

-- Drop redundant index - zero-scan indexes
DROP INDEX IF EXISTS api.logbook_trip_idx;
DROP INDEX IF EXISTS api.logbook_extra_idx;
DROP INDEX IF EXISTS api.logbook_from_time_idx;
DROP INDEX IF EXISTS api.logbook_logs_view_idx;
DROP INDEX IF EXISTS api.logbook_user_data_idx;
DROP INDEX IF EXISTS api.logbook_vessel_active_idx;
DROP INDEX IF EXISTS api.stays_user_data_idx;
DROP INDEX IF EXISTS api.stays_vessel_active_idx;
DROP INDEX IF EXISTS api.moorages_user_data_idx;
DROP INDEX IF EXISTS api.metadata_user_data_idx;
--DROP INDEX IF EXISTS api.logbook_from_moorage_id_idx;
--DROP INDEX IF EXISTS api.logbook_to_moorage_id_idx;
COMMENT ON INDEX api.logbook_from_moorage_id_idx IS
    'This index is redundant with logbook_vessel_from_moorage_idx which is more selective and used by all queries needing from_moorage_id filtering protect the FK enforcement path that PostgreSQL uses when a moorage row is deleted or its id is updated';
COMMENT ON INDEX api.logbook_to_moorage_id_idx IS
    'This index is redundant with logbook_vessel_to_moorage_idx which is more selective and used by all queries needing to_moorage_id filtering protect the FK enforcement path that PostgreSQL uses when a moorage row is deleted or its id is updated';

-- Logbook duplicates
DROP INDEX IF EXISTS api.logbook_vessel_timeline_idx;
DROP INDEX IF EXISTS api.logbook_logs_view_idx;
DROP INDEX IF EXISTS api.logbook_log_view_idx;
DROP INDEX IF EXISTS api.logbook_from_moorage_time_idx;
DROP INDEX IF EXISTS api.logbook_to_moorage_time_idx;
DROP INDEX IF EXISTS api.logbook_vessel_from_moorage_time_idx;
DROP INDEX IF EXISTS api.logbook_vessel_to_moorage_time_idx;

-- Stays duplicates
DROP INDEX IF EXISTS api.stays_departed_arrived_idx;
DROP INDEX IF EXISTS api.stays_arrived_departed_idx;
DROP INDEX IF EXISTS api.stays_moorage_arrived_departed_idx;
DROP INDEX IF EXISTS api.stays_moorage_duration_idx;
DROP INDEX IF EXISTS api.stays_vessel_departed_arrived_idx;
DROP INDEX IF EXISTS api.stays_vessel_arrived_departed_idx;
DROP INDEX IF EXISTS api.stays_vessel_moorage_duration_idx;
DROP INDEX IF EXISTS api.stays_moorage_arrived_idx;

-- Moorages duplicates
DROP INDEX IF EXISTS api.moorages_geog_stay_code_idx;

-- Process queue duplicate
DROP INDEX IF EXISTS public.process_queue_new_logbook_priority_idx;

-- Update indexes
-- ============ LOGBOOK TABLE ============
CREATE INDEX IF NOT EXISTS logbook_vessel_timeline_idx 
ON api.logbook (vessel_id, _from_time DESC)
INCLUDE (id, name, _from, _to, _to_time)
WHERE _to_time IS NOT NULL AND name IS NOT NULL;

COMMENT ON INDEX api.logbook_vessel_timeline_idx IS 
'Optimizes: api.logs_view - Full timeline of completed, named log entries
Query pattern: SELECT * FROM logs WHERE vessel_id=X AND _to_time IS NOT NULL AND name IS NOT NULL ORDER BY _from_time DESC
Key strategy: vessel_id first (RLS filter), then time DESC (sort order)
INCLUDE clause: Enables index-only scans for basic timeline queries
Partial index: Filters out incomplete entries (NULL _to_time) and unnamed entries
Size: ~200-300 bytes per entry
Used by: Main logs list view, timeline displays';

CREATE INDEX IF NOT EXISTS logbook_vessel_trip_idx 
ON api.logbook (vessel_id, _from_time DESC)
INCLUDE (id, _to_time, distance, duration, avg_speed, max_speed, max_wind_speed)
WHERE _to_time IS NOT NULL AND trip IS NOT NULL;

COMMENT ON INDEX api.logbook_vessel_trip_idx IS 
'Optimizes: api.log_view - Single log entry detail with trip metrics
Query pattern: SELECT * FROM log_view WHERE vessel_id=X AND id=Y (with trip data)
Key strategy: vessel_id + time ordering for trip-based queries
INCLUDE clause: Core trip metrics (distance, duration, speeds) for analytics
Partial index: Only entries with completed trips (trip IS NOT NULL)
Size: ~80 bytes per entry
Used by: Log detail view, trip statistics, performance analytics';

CREATE INDEX IF NOT EXISTS logbook_vessel_active_idx 
ON api.logbook (vessel_id, active, _from_time DESC)
WHERE active = true;

COMMENT ON INDEX api.logbook_vessel_active_idx IS 
'Optimizes: Active/in-progress trip lookups
Query pattern: SELECT * FROM logbook WHERE vessel_id=X AND active=true
Key strategy: vessel_id + active flag for current trip tracking
Partial index: Only active entries (typically 0-1 per vessel)
Size: Very small (~40 bytes per active trip)
Used by: Current trip status, real-time navigation displays
Performance: Sub-millisecond lookups due to high selectivity';

CREATE INDEX IF NOT EXISTS logbook_vessel_from_moorage_idx 
ON api.logbook (vessel_id, _from_moorage_id, _from_time DESC)
INCLUDE (id, active)
WHERE _from_moorage_id IS NOT NULL;

COMMENT ON INDEX api.logbook_vessel_from_moorage_idx IS 
'Optimizes: Departure aggregations by moorage (WHERE did we leave from?)
Query pattern: SELECT COUNT(*) FROM logbook WHERE vessel_id=X AND _from_moorage_id=Y
Key strategy: vessel_id + moorage_id for grouping, time DESC for ordering
INCLUDE clause: id for distinct counts, active for filtering
Partial index: Only entries with known departure moorages
Size: ~40 bytes per entry
Used by: Moorage statistics (departures count), visit frequency analysis';

CREATE INDEX IF NOT EXISTS logbook_vessel_to_moorage_idx 
ON api.logbook (vessel_id, _to_moorage_id, _to_time DESC)
INCLUDE (id, active)
WHERE _to_moorage_id IS NOT NULL;

COMMENT ON INDEX api.logbook_vessel_to_moorage_idx IS 
'Optimizes: Arrival aggregations by moorage (WHERE did we arrive at?)
Query pattern: SELECT COUNT(*) FROM logbook WHERE vessel_id=X AND _to_moorage_id=Y
Key strategy: vessel_id + moorage_id for grouping, time DESC for ordering
INCLUDE clause: id for distinct counts, active for filtering
Partial index: Only entries with known arrival moorages
Size: ~40 bytes per entry
Used by: Moorage statistics (arrivals count), visit frequency analysis';

CREATE INDEX IF NOT EXISTS logbook_id_vessel_idx 
ON api.logbook (vessel_id, id)
INCLUDE (_from_time, _to_time);

COMMENT ON INDEX api.logbook_id_vessel_idx IS 
'Optimizes: Direct lookup by ID with RLS enforcement
Query pattern: SELECT * FROM logbook WHERE vessel_id=X AND id=Y
Key strategy: vessel_id first (RLS), then unique id
INCLUDE clause: Timestamps for quick time-based filtering
Size: ~32 bytes per entry
Used by: Single log entry retrieval, foreign key lookups
Performance: O(1) lookup with RLS filter';

CREATE INDEX IF NOT EXISTS logbook_from_time_join_idx
ON api.logbook (_from_time DESC, vessel_id)
INCLUDE (id, _to_moorage_id, _to)
WHERE _to_moorage_id IS NOT NULL;

COMMENT ON INDEX api.logbook_from_time_join_idx IS 
'Optimizes: stays_view join on departure timestamps
Query pattern: JOIN logbook ON stays.departed = logbook._from_time
Key strategy: _from_time FIRST (join condition), vessel_id for RLS filtering
INCLUDE clause: Minimal join data (id, destination moorage, location name)
Partial index: Only departures with known destinations
Why time-first: Enables efficient merge join when stays are sorted by departed time
Index-only scan: Avoids heap access for join operations
Size: ~60 bytes per entry
Used by: stays_view to correlate stays with subsequent log entries
Performance: Critical for stays_view (~50ms execution time)';

CREATE INDEX IF NOT EXISTS logbook_to_time_join_idx
ON api.logbook (_to_time DESC, vessel_id)
INCLUDE (id, _from_moorage_id, _from);

COMMENT ON INDEX api.logbook_to_time_join_idx IS 
'Optimizes: stays_view join on arrival timestamps
Query pattern: JOIN logbook ON stays.arrived = logbook._to_time
Key strategy: _to_time FIRST (join condition), vessel_id for RLS filtering
INCLUDE clause: Minimal join data (id, origin moorage, location name)
Why time-first: Enables efficient merge join when stays are sorted by arrived time
Index-only scan: Avoids heap access for join operations
Size: ~60 bytes per entry
Used by: stays_view to correlate stays with preceding log entries
Performance: Critical for stays_view (~50ms execution time)
Note: Complements logbook_from_time_join_idx for bi-directional stay correlation';

-- ============ STAYS TABLE ============
CREATE INDEX IF NOT EXISTS stays_vessel_moorage_timeline_idx
ON api.stays (vessel_id, moorage_id, arrived DESC, departed DESC)
INCLUDE (id, name, duration, stay_code, active)
WHERE departed IS NOT NULL;

COMMENT ON INDEX api.stays_vessel_moorage_timeline_idx IS 
'Optimizes: Per-moorage stay queries and aggregations
Query pattern: SELECT * FROM stays WHERE vessel_id=X AND moorage_id=Y ORDER BY arrived DESC
Key strategy: vessel_id (RLS) + moorage_id (grouping) + times (ordering)
INCLUDE clause: Core stay attributes for index-only scans
Partial index: Completed stays only (departed IS NOT NULL)
Size: ~60 bytes per entry
Used by: Moorage detail view, stay history at specific locations, duration aggregations
Performance: Enables efficient GROUP BY moorage_id queries';

CREATE INDEX IF NOT EXISTS stays_vessel_active_idx
ON api.stays (vessel_id, active, arrived DESC)
WHERE active = true;

COMMENT ON INDEX api.stays_vessel_active_idx IS 
'Optimizes: Current/active stay lookup
Query pattern: SELECT * FROM stays WHERE vessel_id=X AND active=true
Key strategy: vessel_id + active flag for current stay
Partial index: Only active stays (typically 0-1 per vessel)
Size: Very small (~40 bytes per active stay)
Used by: Current location status, "where am I now" queries
Performance: Sub-millisecond due to high selectivity (one row per vessel)';

CREATE INDEX IF NOT EXISTS stays_vessel_timeline_idx 
ON api.stays (vessel_id, arrived DESC)
INCLUDE (id, departed, moorage_id, stay_code, name, duration, notes)
WHERE departed IS NOT NULL AND name IS NOT NULL;

COMMENT ON INDEX api.stays_vessel_timeline_idx IS 
'Optimizes: Full stay timeline sorted by arrival time
Query pattern: SELECT * FROM stays_view WHERE vessel_id=X ORDER BY arrived DESC
Key strategy: vessel_id (RLS) + arrived DESC (primary sort order for stays_view)
INCLUDE clause: All columns needed for stays_view to enable index-only scans
Partial index: Named, completed stays only (filters out incomplete/unnamed entries)
Size: ~100 bytes per entry
Used by: stays_view (primary index), timeline displays, stay history
Performance: Reduces stays_view time by eliminating sort operation
Note: This index directly supports the main stays_view query pattern';

CREATE INDEX IF NOT EXISTS stays_timeline_covering_idx 
ON api.stays (arrived DESC, departed DESC)
INCLUDE (id, name, moorage_id, stay_code, notes, vessel_id)
WHERE departed IS NOT NULL AND name IS NOT NULL;

COMMENT ON INDEX api.stays_timeline_covering_idx IS 
'Optimizes: Time-range queries across all vessels (admin/reporting)
Query pattern: SELECT * FROM stays WHERE arrived BETWEEN X AND Y (without vessel_id filter)
Key strategy: Time-first ordering for global timeline queries
INCLUDE clause: vessel_id in INCLUDE (filtered after index scan via RLS)
Partial index: Named, completed stays
Size: ~100 bytes per entry
Used by: Admin dashboards, cross-vessel analytics, reporting
When used: When RLS filter is applied AFTER time-based index scan
Alternative to: stays_vessel_timeline_idx when vessel_id is not in WHERE clause
Note: RLS policies will filter vessel_id from INCLUDE clause after index scan';

-- ============ MOORAGES TABLE ============
CREATE INDEX IF NOT EXISTS moorages_vessel_idx
ON api.moorages (vessel_id, id)
INCLUDE (name, stay_code, notes, home_flag, geog, latitude, longitude, user_data)
WHERE geog IS NOT NULL;

COMMENT ON INDEX api.moorages_vessel_idx IS 
'Optimizes: Vessel-specific moorage list and lookups
Query pattern: SELECT * FROM moorages WHERE vessel_id=X
Key strategy: vessel_id (RLS) + id (unique lookup)
INCLUDE clause: All display columns for index-only scans
Partial index: Only moorages with valid geographic coordinates
Size: ~200-300 bytes per entry (due to user_data JSONB)
Used by: Moorage list view, map displays, moorage detail lookups
Performance: Enables index-only scans for most moorage queries
Note: Large INCLUDE clause but justified by query patterns (small table, ~10-100 moorages per vessel)';

CREATE INDEX IF NOT EXISTS moorages_stay_code_idx
ON api.moorages (stay_code, vessel_id)
WHERE geog IS NOT NULL;

COMMENT ON INDEX api.moorages_stay_code_idx IS 
'Optimizes: Join with stays_at reference table
Query pattern: JOIN stays_at ON moorages.stay_code = stays_at.stay_code
Key strategy: stay_code first (join condition), vessel_id for RLS
Partial index: Valid moorages with coordinates only
Size: ~20 bytes per entry
Used by: Moorage views joining stay type descriptions
Performance: Enables efficient hash joins with stays_at lookup table';

CREATE INDEX IF NOT EXISTS stays_vessel_moorage_duration_idx
ON api.stays (vessel_id, moorage_id)
INCLUDE (duration, active)
WHERE NOT active;

COMMENT ON INDEX api.stays_vessel_moorage_duration_idx IS 
'Optimizes: Total time spent at each moorage (aggregation queries)
Query pattern: SELECT moorage_id, SUM(duration) FROM stays WHERE vessel_id=X AND NOT active GROUP BY moorage_id
Key strategy: vessel_id (RLS) + moorage_id (GROUP BY key)
INCLUDE clause: duration (for SUM), active (for additional filtering)
Partial index: Completed stays only (active=false)
Size: ~32 bytes per entry
Used by: moorages_view aggregations, "total time at location" calculations
Performance: Eliminates sequential scans for duration rollups
Note: Complements stays_vessel_moorage_timeline_idx with different optimization target';

-- ============ PROCESS QUEUE TABLE ============
CREATE INDEX IF NOT EXISTS process_queue_pending_idx 
ON public.process_queue (channel, processed, stored ASC)
WHERE processed IS NULL;

COMMENT ON INDEX public.process_queue_pending_idx IS 
'Optimizes: Background job queue processing (FIFO order)
Query pattern: SELECT * FROM process_queue WHERE channel=X AND processed IS NULL ORDER BY stored ASC LIMIT N
Key strategy: channel (partition key) + processed (status filter) + stored ASC (FIFO ordering)
Partial index: Only unprocessed items (processed IS NULL) - dramatically reduces index size
Size: ~24 bytes per pending item
Used by: Background workers polling for jobs, task queue processors
Performance: O(1) lookup for next job in channel, hot index (fully cached)
Queue behavior: FIFO (First In First Out) via stored ASC ordering
Why partial: Processed items are never queried again, excluding them saves ~95% index space
Maintenance: Consider VACUUM to reclaim space from processed/deleted items';

-- Add function, public.stay_code_description for stay code descriptions
-- Immutable lookup — zero table access, result cached by planner
CREATE OR REPLACE FUNCTION public.stay_code_description(code integer)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE code
        WHEN 1 THEN 'Unknown'
        WHEN 2 THEN 'Anchor'
        WHEN 3 THEN 'Mooring Buoy'
        WHEN 4 THEN 'Dock'
        ELSE 'unknown'
    END;
$$;
-- Description
COMMENT ON FUNCTION public.stay_code_description IS 'Returns a human-readable description for a given stay code. This is an immutable function that can be used in SQL queries to translate stay codes into text descriptions.';

-- Add a stay types, stays_at, with stay_code and stay_type
CREATE TYPE public.stays_at_type AS ENUM (
    'Unknown',        -- default: not yet geocoded by overpass
    'Anchor',         -- seamark:type ~ anchorage|anchor_berth|berth
    'Mooring Buoy',   -- seamark:type ~ mooring|harbour
    'Dock'            -- leisure = marina
);
-- Description
COMMENT ON TYPE public.stays_at_type IS
    'Stay/moorage type. Starts as Unknown until process_lat_lon_fn '
    'resolves the location via overpass. User can override at any time.';

-- DROP FUNCTION public.check_jwt();
-- Update public.check_jwt() allow vessel_fn for anonymous role, add mcp_role and bot_role
CREATE OR REPLACE FUNCTION public.check_jwt()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = api, public, pg_catalog
AS $function$
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
  _headers json := NULL;
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
  --RAISE WARNING 'jwt email %', current_setting('request.jwt.claims.email', true);
  --RAISE WARNING 'jwt role %', current_setting('request.jwt.claims', true)::json->>'role';
  --RAISE WARNING 'cur_user %', current_user;
  --RAISE WARNING 'user.id [%], user.email [%]', current_setting('user.id', true), current_setting('user.email', true);
  --RAISE WARNING 'vessel.id [%], vessel.name [%]', current_setting('vessel.id', true), current_setting('vessel.name', true);

  --TODO SELECT current_setting('request.jwt.uid', true)::json->>'uid' INTO _user_id;
  --TODO RAISE WARNING 'jwt user_id %', current_setting('request.jwt.uid', true)::json->>'uid';
  --TODO SELECT current_setting('request.jwt.vid', true)::json->>'vid' INTO _vessel_id;
  --TODO RAISE WARNING 'jwt vessel_id %', current_setting('request.jwt.vid', true)::json->>'vid';

  IF _role = 'user_role' OR _role = 'bot_role' OR _role = 'mcp_role' THEN
    -- Check the user exist in the accounts table
    SELECT * INTO account_rec
        FROM auth.accounts
        WHERE auth.accounts.email = _email;
    IF account_rec.email IS NULL THEN
        RAISE WARNING 'public.check_jwt() Invalid user Unknown user or password [%]', _email;
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
    /*-- Check a vessel and user exist
    SELECT auth.vessels.* INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = auth.accounts.email
            AND auth.accounts.email = _email;
    */
    SELECT * INTO vessel_rec
        FROM auth.vessels
        WHERE owner_email = _email;
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
    /*
    -- Check the vessel and user exist
    SELECT auth.vessels.* INTO vessel_rec
        FROM auth.vessels, auth.accounts
        WHERE auth.vessels.owner_email = auth.accounts.email
            AND auth.accounts.email = _email
            AND auth.vessels.vessel_id = _vid;
    */
    -- vessel_role vessel lookup  
    SELECT * INTO vessel_rec
        FROM auth.vessels
        WHERE owner_email = _email
            AND vessel_id = _vid;
    IF vessel_rec.owner_email IS NULL THEN
        RAISE WARNING 'public.check_jwt() Invalid vessel Unknown vessel owner_email [%]', _email;
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
    SELECT current_setting('request.path', true) ~ '^/(logs_view|log_view|rpc/timelapse_fn|rpc/timelapse2_fn|monitoring_live|monitoring_view|stats_logs_view|stats_moorages_view|rpc/stats_logs_fn|rpc/export_logbooks_geojson_point_trips_fn|rpc/export_logbooks_geojson_linestring_trips_fn|rpc/vessel_fn)$' INTO _ppath;
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
            /*
                SELECT v.vessel_id, v.name into anonymous_rec
                    FROM auth.accounts a, auth.vessels v, jsonb_each_text(a.preferences) as prefs
                    WHERE a.email = v.owner_email
                        AND a.preferences->>'public_vessel'::text ~* boat
                        AND prefs.key = _ptype::TEXT
                        AND prefs.value::BOOLEAN = true;
            */
                -- Replace the ELSE branch anonymous lookup with:
                SELECT v.vessel_id, v.name INTO anonymous_rec
                    FROM auth.vessels v
                    JOIN auth.accounts a ON a.email = v.owner_email
                    WHERE a.preferences->>'public_vessel' = _pvessel   -- exact match, index-able
                    AND a.preferences->>_ptype::TEXT = 'true'
                    LIMIT 1;
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
$function$
;
-- Description
COMMENT ON FUNCTION public.check_jwt() IS 'PostgREST API db-pre-request check, set_config according to role (api_anonymous,vessel_role,user_role)';

--DROP FUNCTION IF EXISTS public.overpass_py_fn(in numeric, in numeric, out jsonb);
-- Update public.overpass_py_fn, update exceptions error handling
CREATE OR REPLACE FUNCTION public.overpass_py_fn(lon numeric, lat numeric, retry boolean DEFAULT false, OUT geo jsonb)
 RETURNS jsonb
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
 IMMUTABLE STRICT
AS $function$
    """
    Return https://overpass-turbo.eu seamark details within 400m
    https://overpass-turbo.eu/s/1EaG
    https://wiki.openstreetmap.org/wiki/Key:seamark:type
    """
    import requests
    import json
    import urllib.parse

    headers = {'User-Agent': 'PostgSail', 'From': 'postgsail@localhost'}
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
            #plpy.notice('overpass-api Failed to get overpass-api details')
            plpy.notice('overpass-api Failed to get overpass-api details with status code: {}'.format(r.status_code))
            #plpy.notice('overpass-api Failed Response text: {}'.format(r.text))
            return { "error": "failed_request" };

    except requests.exceptions.Timeout:
        plpy.warning('overpass-api Request timed out after 60s')
        return {"error": "timeout"}
        
    except requests.exceptions.RequestException as e:
        plpy.warning('overpass-api Request exception: {}'.format(str(e)))
        return {"error": "request_exception"}
        
    except Exception as e:
        plpy.error('overpass-api Unexpected exception: {}'.format(str(e)))
        return {"error": "unexpected_exception"}
$function$
;
-- Description
COMMENT ON FUNCTION public.overpass_py_fn IS 'Return https://overpass-turbo.eu seamark details within 400m using plpython3u';

-- Default timeout if 5 minutes
-- Increase timeout
ALTER FUNCTION public.overpass_py_fn SET statement_timeout = '10min';
ALTER FUNCTION public.windy_pws_py_fn SET statement_timeout = '10min';
ALTER FUNCTION public.cron_windy_fn SET statement_timeout = '10min';
ALTER FUNCTION public.cron_alerts_fn SET statement_timeout = '10min';

DROP VIEW IF EXISTS api.logs_view;
-- Expose updated_at in PostgREST views used by MCP read-only role
CREATE OR REPLACE VIEW api.logs_view
    WITH (security_invoker='true', security_barrier='true') AS
SELECT
    id,
    name,
    _from          AS "from",
    _from_time     AS started,
    _to            AS "to",
    _to_time       AS ended,
    distance,
    duration,
    _from_moorage_id,
    _to_moorage_id,
    (user_data -> 'tags') AS tags,
    updated_at
FROM api.logbook l
WHERE name IS NOT NULL
  AND _to_time IS NOT NULL
ORDER BY _from_time DESC;
COMMENT ON VIEW api.logs_view IS 'Logs web view';

DROP VIEW IF EXISTS api.stays_view;
-- Expose updated_at in PostgREST views used by MCP read-only role
CREATE OR REPLACE VIEW api.stays_view
    WITH (security_invoker='true', security_barrier='true') AS
SELECT
    id,
    moorage_id,
    name,
    latitude,
    longitude,
    arrived,
    departed,
    duration,
    stay_code,
    notes,
    updated_at
FROM api.stays s
WHERE departed IS NOT NULL
  AND name IS NOT NULL
ORDER BY arrived DESC;
COMMENT ON VIEW api.stays_view IS 'Stays web view';

DROP VIEW IF EXISTS api.moorages_view;
-- Expose updated_at in PostgREST views used by MCP read-only role
CREATE OR REPLACE VIEW api.moorages_view
    WITH (security_invoker='true', security_barrier='true') AS
SELECT
    id,
    name,
    country,
    stay_code,
    latitude,
    longitude,
    geog,
    home_flag,
    notes,
    updated_at
FROM api.moorages m
ORDER BY id;
COMMENT ON VIEW api.moorages_view IS 'Moorages web view';

DROP VIEW IF EXISTS api.log_view;
-- Update api.log_view, add vessel_id
CREATE OR REPLACE VIEW api.log_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT id, vessel_id,
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
    extra -> 'polar'::text AS polar,
    user_data -> 'images'::text AS images,
    user_data -> 'tags'::text AS tags,
    user_data -> 'observations'::text AS observations,
    CASE
        WHEN jsonb_array_length(user_data -> 'images'::text) > 0 THEN true
        ELSE false
    END AS has_images
   FROM api.logbook l
  WHERE _to_time IS NOT NULL AND trip IS NOT NULL
  ORDER BY _from_time DESC;
-- Description
COMMENT ON VIEW api.log_view IS 'Log web view';

DROP VIEW IF EXISTS api.stays_view;
-- Update api.stays_view, optimize query with index
CREATE OR REPLACE VIEW api.stays_view
WITH (security_invoker=true, security_barrier=true)
AS 
SELECT 
    s.id,
    s.name,
    m.name AS moorage,
    m.id AS moorage_id,
    s.departed - s.arrived AS duration,
    (ARRAY['Unknown','Anchor','Mooring Buoy','Dock'])[s.stay_code] AS stayed_at,
    s.stay_code AS stayed_at_id,
    --sa.description AS stayed_at,
    --sa.stay_code AS stayed_at_id,
    s.arrived,
    "from".id AS arrived_log_id,
    "from"._to_moorage_id AS arrived_from_moorage_id,
    "from"._to AS arrived_from_moorage_name,
    s.departed,
    "to".id AS departed_log_id,
    "to"._from_moorage_id AS departed_to_moorage_id,
    "to"._from AS departed_to_moorage_name,
    s.notes
FROM api.stays s
INNER JOIN api.moorages m 
    ON s.moorage_id = m.id
--INNER JOIN api.stays_at sa 
--    ON s.stay_code = sa.stay_code
LEFT JOIN api.logbook "from" 
    ON "from"._from_time = s.departed 
    AND "from"._to_moorage_id IS NOT NULL
LEFT JOIN api.logbook "to" 
    ON "to"._to_time = s.arrived
WHERE s.departed IS NOT NULL 
  AND s.name IS NOT NULL
ORDER BY s.arrived DESC;
-- Description
COMMENT ON VIEW api.stays_view IS 'Stays listing web view';

DROP VIEW IF EXISTS api.stay_view;
-- Update api.stay_view, optimize query with index
CREATE OR REPLACE VIEW api.stay_view
WITH (security_invoker=true, security_barrier=true)
AS 
SELECT 
    s.id,
    s.name,
    m.name AS moorage,
    m.id AS moorage_id,
    s.departed - s.arrived AS duration,
    (ARRAY['Unknown','Anchor','Mooring Buoy','Dock'])[s.stay_code] AS stayed_at,
    s.stay_code AS stayed_at_id,
    --sa.description AS stayed_at,
    --sa.stay_code AS stayed_at_id,
    s.arrived,
    "from".id AS arrived_log_id,
    "from"._to_moorage_id AS arrived_from_moorage_id,
    "from"._to AS arrived_from_moorage_name,
    s.departed,
    "to".id AS departed_log_id,
    "to"._from_moorage_id AS departed_to_moorage_id,
    "to"._from AS departed_to_moorage_name,
    s.notes,
    CASE
        WHEN jsonb_array_length(s.user_data -> 'images'::text) > 0 THEN true
        ELSE false
    END AS has_images,
    s.user_data -> 'images'::text AS images
FROM api.stays s
INNER JOIN api.moorages m 
    ON s.moorage_id = m.id
--INNER JOIN api.stays_at sa 
--    ON s.stay_code = sa.stay_code
LEFT JOIN api.logbook "from" 
    ON "from"._from_time = s.departed 
    AND "from"._to_moorage_id IS NOT NULL
LEFT JOIN api.logbook "to" 
    ON "to"._to_time = s.arrived
WHERE s.departed IS NOT NULL 
  AND s.name IS NOT NULL
ORDER BY s.arrived DESC;
-- Description
COMMENT ON VIEW api.stay_view IS 'Stay listing web view';

DROP VIEW IF EXISTS api.moorages_view;
-- Update api.moorages_view, optimize query with index
CREATE OR REPLACE VIEW api.moorages_view
WITH (security_invoker=true, security_barrier=true)
AS 
WITH logbook_counts AS (
    -- Count departures (from)
    SELECT 
        _from_moorage_id AS moorage_id,
        COUNT(*) AS entries
    FROM api.logbook
    WHERE vessel_id = current_setting('vessel.id', true)
      AND _from_moorage_id IS NOT NULL
      AND active = false
    GROUP BY _from_moorage_id
    
    UNION ALL
    
    -- Count arrivals (to)
    SELECT 
        _to_moorage_id AS moorage_id,
        COUNT(*) AS entries
    FROM api.logbook
    WHERE vessel_id = current_setting('vessel.id', true)
      AND _to_moorage_id IS NOT NULL
      AND active = false
    GROUP BY _to_moorage_id
),
logbook_total AS (
    SELECT 
        moorage_id,
        SUM(entries) AS total_arrivals_departures
    FROM logbook_counts
    GROUP BY moorage_id
),
stays_agg AS (
    SELECT 
        moorage_id,
        SUM(duration) AS total_duration
    FROM api.stays
    WHERE vessel_id = current_setting('vessel.id', true)
      AND active = false
    GROUP BY moorage_id
)
SELECT 
    m.id,
    m.name AS moorage,
    (ARRAY['Unknown','Anchor','Mooring Buoy','Dock'])[m.stay_code] AS default_stay,
    m.stay_code AS default_stay_id,
    --sa.description AS default_stay,
    --sa.stay_code AS default_stay_id,
    COALESCE(lt.total_arrivals_departures, 0) AS arrivals_departures,
    COALESCE(st.total_duration, 'PT0S'::interval) AS total_duration
FROM api.moorages m
--INNER JOIN api.stays_at sa ON m.stay_code = sa.stay_code
LEFT JOIN logbook_total lt ON lt.moorage_id = m.id
LEFT JOIN stays_agg st ON st.moorage_id = m.id
WHERE m.vessel_id = current_setting('vessel.id', true)
  AND m.geog IS NOT NULL
ORDER BY COALESCE(st.total_duration, 'PT0S'::interval) DESC;
-- Description
COMMENT ON VIEW api.moorages_view IS 'Moorages listing web view';

DROP VIEW IF EXISTS api.moorage_view CASCADE;
-- api.moorages_geojson_view
-- api.stats_moorages_view
-- api.stats_moorages_away_view

-- Update api.moorage_view, optimize query with index
CREATE OR REPLACE VIEW api.moorage_view
WITH (security_invoker=true, security_barrier=true)
AS 
WITH stay_summary AS (
    SELECT 
        moorage_id,
        MIN(arrived) AS first_seen,
        MAX(departed) AS last_seen,
        SUM(duration) AS total_duration,
        COUNT(*) AS stay_count,
        MIN(id) FILTER (WHERE arrived = (SELECT MIN(arrived) FROM api.stays WHERE moorage_id = s.moorage_id AND vessel_id = current_setting('vessel.id', true) AND active = false)) AS first_seen_id,
        MAX(id) FILTER (WHERE departed = (SELECT MAX(departed) FROM api.stays WHERE moorage_id = s.moorage_id AND vessel_id = current_setting('vessel.id', true) AND active = false)) AS last_seen_id
    FROM api.stays s
    WHERE s.vessel_id = current_setting('vessel.id', true)
      AND s.active = false
    GROUP BY moorage_id, id, arrived, departed
),
log_summary AS (
    SELECT 
        moorage_id,
        COUNT(DISTINCT id) AS log_count
    FROM (
        SELECT _from_moorage_id AS moorage_id, id
        FROM api.logbook
        WHERE vessel_id = current_setting('vessel.id', true)
          AND active = false 
          AND _from_moorage_id IS NOT NULL
        
        UNION ALL
        
        SELECT _to_moorage_id AS moorage_id, id
        FROM api.logbook
        WHERE vessel_id = current_setting('vessel.id', true)
          AND active = false 
          AND _to_moorage_id IS NOT NULL
    ) logs
    GROUP BY moorage_id
)
SELECT 
    m.id,
    m.name,
    (ARRAY['Unknown','Anchor','Mooring Buoy','Dock'])[m.stay_code] AS default_stay,
    m.stay_code AS default_stay_id,
    --sa.description AS default_stay,
    --sa.stay_code AS default_stay_id,
    m.notes,
    m.home_flag AS home,
    m.geog,
    m.latitude,
    m.longitude,
    COALESCE(l.log_count, 0) AS logs_count,
    COALESCE(ss.stay_count, 0) AS stays_count,
    COALESCE(ss.total_duration, 'PT0S'::interval) AS stays_sum_duration,
    ss.first_seen AS stay_first_seen,
    ss.last_seen AS stay_last_seen,
    ss.first_seen_id AS stay_first_seen_id,
    ss.last_seen_id AS stay_last_seen_id,
    (jsonb_array_length(m.user_data -> 'images') > 0) AS has_images,
    m.user_data -> 'images' AS images
FROM api.moorages m
--INNER JOIN api.stays_at sa ON m.stay_code = sa.stay_code
LEFT JOIN stay_summary ss ON m.id = ss.moorage_id
LEFT JOIN log_summary l ON m.id = l.moorage_id
WHERE m.vessel_id = current_setting('vessel.id', true)
  AND m.geog IS NOT NULL
ORDER BY ss.total_duration DESC;
-- Description
COMMENT ON VIEW api.moorage_view IS 'Moorage details web view';

CREATE OR REPLACE VIEW api.stats_moorages_view
WITH(security_invoker=true,security_barrier=true)
AS WITH home_ports AS (
         SELECT count(*) AS home_ports
           FROM api.moorage_view m
          WHERE m.home IS TRUE
        ), unique_moorage AS (
         SELECT count(*) AS unique_moorage
           FROM api.moorage_view m
        ), time_at_home_ports AS (
         SELECT sum(m.stays_sum_duration) AS time_at_home_ports
           FROM api.moorage_view m
          WHERE m.home IS TRUE
        ), time_spent_away AS (
         SELECT sum(m.stays_sum_duration) AS time_spent_away
           FROM api.moorage_view m
          WHERE m.home IS FALSE
        )
 SELECT home_ports.home_ports,
    unique_moorage.unique_moorage AS unique_moorages,
    time_at_home_ports.time_at_home_ports AS "time_spent_at_home_port(s)",
    time_spent_away.time_spent_away
   FROM home_ports,
    unique_moorage,
    time_at_home_ports,
    time_spent_away;
-- Description
COMMENT ON VIEW api.stats_moorages_view IS 'Statistics Moorages web view';

CREATE OR REPLACE VIEW api.stats_moorages_away_view
WITH (security_invoker=true, security_barrier=true)
AS
SELECT
    m.default_stay AS description,
    sum(m.stays_sum_duration) AS time_spent_away_by
FROM api.moorage_view m
WHERE m.home IS FALSE
GROUP BY m.default_stay, m.default_stay_id
ORDER BY m.default_stay_id;

COMMENT ON VIEW api.stats_moorages_away_view IS 'Statistics Moorages Time Spent Away web view';

-- api.moorages_geojson_view source
CREATE OR REPLACE VIEW api.moorages_geojson_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT id,
    name,
    st_asgeojson(m.*)::jsonb AS geojson
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
          WHERE m_1.geog IS NOT NULL) m;
-- Description
COMMENT ON VIEW api.moorages_geojson_view IS 'List moorages as geojson';

--DROP TABLE IF EXISTS public.metrics_rejected;
-- Create a table to log rejected metrics entries with reason
CREATE TABLE IF NOT EXISTS public.metrics_rejected (
    LIKE api.metrics,
    rejected_at timestamptz DEFAULT NOW(),
    rejection_reason text
);
-- Description
COMMENT ON TABLE public.metrics_rejected IS 'Table to store rejected metrics entries with reason';
CREATE INDEX metrics_anomalies_vessel_idx ON public.metrics_rejected(vessel_id, rejected_at DESC);
CREATE INDEX metrics_anomalies_type_idx ON public.metrics_rejected(rejection_reason, rejected_at DESC);

-- DROP FUNCTION public.metrics_trigger_fn();
-- Update public.metrics_trigger_fn, add AWS check and add distance check, log rejections
CREATE OR REPLACE FUNCTION public.metrics_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
    DECLARE
        previous_metric record;
        stay_code INTEGER;
        logbook_id INTEGER;
        stay_id INTEGER;
        valid_status BOOLEAN := False;
        _vessel_id TEXT;
        distance double precision := 0;
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
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Duplicate time';
            RETURN NULL;
        END IF;
        IF previous_metric.time > NEW.time THEN
            -- Ignore entry if new time is later than previous time
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], new time is older than previous_metric.time [%] > [%]', NEW.vessel_id, previous_metric.time, NEW.time;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'New time is in the past from previous time';
            RETURN NULL;
        END IF;
        IF NEW.time > NOW() THEN
            -- Ignore entry if new time is in the future.
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], new time is in the future [%] > [%]', NEW.vessel_id, NEW.time, NOW();
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'New time is in the future';
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
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Null latitude or longitude';
            RETURN NULL;
        END IF;
        -- Check if valid latitude
        IF NEW.latitude >= 90 OR NEW.latitude <= -90 THEN
            -- Ignore entry if invalid latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid latitude >= 90 OR <= -90 [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Invalid latitude >= 90 OR <= -90';
            RETURN NULL;
        END IF;
        -- Check if valid longitude
        IF NEW.longitude >= 180 OR NEW.longitude <= -180 THEN
            -- Ignore entry if invalid latitude,longitude
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid longitude >= 180 OR <= -180 [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Invalid longitude >= 180 OR <= -180';
            RETURN NULL;
        END IF;
        -- Check for null island (0,0) — invalid GPS fix
        IF NEW.latitude = 0.0 AND NEW.longitude = 0.0 THEN
            -- Ignore entry if latitude,longitude are equal to 0.0
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], latitude and longitude are equal to 0.0 [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Null island position (0,0)';
            RETURN NULL;
        END IF;
        -- Check for suspiciously equal coordinates (GPS glitch)
        IF NEW.latitude = NEW.longitude AND ABS(NEW.latitude) > 1 THEN
            -- Ignore entry if latitude,longitude are equal
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], latitude and longitude are equal [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Latitude and longitude are equal';
            RETURN NULL;
        END IF;
/*
        -- Check for impossible position jumps (teleportation detection)
        --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], new latitude and longitude [%] [%]', NEW.vessel_id, NEW.latitude, NEW.longitude;
        --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], prev latitude and longitude [%] [%]', NEW.vessel_id, previous_metric.latitude, previous_metric.longitude;
        IF previous_metric.longitude IS NOT NULL AND previous_metric.latitude IS NOT NULL
            AND (previous_metric.latitude <> NEW.latitude
            OR previous_metric.longitude <> NEW.longitude) THEN
            -- Calculate distance in meters
            distance := ST_Distance(
                ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography,
                ST_SetSRID(ST_MakePoint(previous_metric.longitude, previous_metric.latitude), 4326)::geography
            );
            --RAISE WARNING 'Metrics distance check, vessel_id [%], distance [% m]', NEW.vessel_id, distance;
            -- Check distance from previous point is > 500km, if yes ignore entry as it is likely a GPS glitch or data error
            IF distance::NUMERIC > 500000 THEN
                -- 'ANOMALY: Distance > 500km'
                RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], distance between previous metric and new metric is too long >500km, distance [% km]', 
                    NEW.vessel_id, ROUND((distance/1000)::numeric, 2);
                INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Distance from previous point is > 500km';
                RETURN NULL;
            END IF;
        END IF;
*/
        -- Check if speedOverGround is valid value
        IF NEW.speedoverground >= 40 THEN
            -- Ignore entry as speedOverGround is invalid
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], speedOverGround is invalid, over 40 < [%]', NEW.vessel_id, NEW.speedoverground;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Invalid speedOverGround over 40';
            RETURN NULL;
        END IF;
        -- Check if windSpeedApparent is valid value
        IF NEW.windspeedapparent >= 200 THEN
            -- Ignore entry as windSpeedApparent is invalid
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], windSpeedApparent is invalid, over 200 < [%]', NEW.vessel_id, NEW.windspeedapparent;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Invalid windSpeedApparent over 200';
            RETURN NULL;
        END IF;

        -- Debug If status NULL, what should we do ?
        --RAISE WARNING 'Metrics status, vessel_id [%], New:[%] Previous:[%]', NEW.vessel_id, NEW.status, previous_metric.status;
/*
        Problematic...
        -- Check if status is null but speed is over 3knots set status to sailing
        IF NEW.status IS NULL AND NEW.speedoverground >= 3 THEN
            RAISE WARNING 'Metrics Unknown NEW.status from vessel_id [%], null status, set to sailing because of speedoverground is +3 from [%]', NEW.vessel_id, NEW.status;
            NEW.status := 'sailing';
        -- Check if status is null then set status to default moored
        ELSIF NEW.status IS NULL THEN
            RAISE WARNING 'Metrics Unknown NEW.status from vessel_id [%], null status, set to default moored from [%]', NEW.vessel_id, NEW.status;
            NEW.status := 'moored';
        END IF;
*/
        IF NEW.status IS NULL AND previous_metric.status IS NOT NULL THEN
            RAISE WARNING 'Metrics Unknown NEW.status from vessel_id [%], null new status [%], set to previous_metric.status from [%]', NEW.vessel_id, NEW.status, previous_metric.status;
            NEW.status := previous_metric.status;
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
            --    VALUES ('new_stay', stay_id, NOW(), current_setting('vessel.id', true));
            --RAISE WARNING 'Metrics Insert first stay as no previous metrics exist, stay_id stay_id [%] [%] [%]', stay_id, NEW.status, NEW.time;
        END IF;
        -- Check if status is valid enum
        SELECT NEW.status::name = any(enum_range(null::status_type)::name[]) INTO valid_status;
        IF valid_status IS False THEN
            -- Ignore entry if status is invalid
            --RAISE WARNING 'Metrics Ignoring metric, vessel_id [%], invalid status [%]', NEW.vessel_id, NEW.status;
            INSERT INTO public.metrics_rejected SELECT NEW.*, NOW(), 'Invalid status';
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
$function$
;
-- Description
COMMENT ON FUNCTION public.metrics_trigger_fn() IS 'process metrics from vessel, generate pre_logbook and new_stay.';

-- DROP FUNCTION api.split_logbook_fn;
-- Add api.split_logbook_fn, Split in 2 logbook by id and a timestamp, update the first logbook with new end time and location, insert new logbook with new start time and location, insert stay record for the new logbook entry
CREATE OR REPLACE FUNCTION api.split_logbook_fn(id_start integer, split_time text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
    -- TODO 
    DECLARE
        logbook_rec_start record;
        logbook_rec_end record;
    BEGIN
        -- If id_start or split_time is not NULL
        IF (id_start IS NULL OR id_start < 1) OR (split_time IS NULL OR split_time = '') THEN
            RAISE WARNING '-> split_logbook_fn invalid input % %', id_start, split_time;
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
            RAISE WARNING '-> split_logbook_fn invalid logbook %', id_start;
            RETURN;
        END IF;
        -- Ensure timestamp is inside a logbook entry
        IF split_time::TIMESTAMPTZ <= logbook_rec_start._from_time OR split_time::TIMESTAMPTZ >= logbook_rec_start._to_time THEN
            --RAISE WARNING '-> split_logbook_fn invalid split_time, should be between _from_time and _to_time % % %', id_start, split_time, logbook_rec_start._from_time, logbook_rec_start._to_time;
            RETURN;
        END IF;

        -- Update the start logbook record with new end time and location
        UPDATE api.logbook
            SET
                _to_time = split_time::TIMESTAMPTZ
                -- todo update _to_lat and _to_lng with location at split_time
            WHERE id = id_start;

        -- Insert new logbook record with new start time and location
        /*
        INSERT INTO api.logbook
            (vessel_id, active, _from_time, _from_lat, _from_lng, _to_time, _to_lat, _to_lng)
                VALUES  
            (logbook_rec_start.vessel_id, false, split_time::TIMESTAMPTZ, NULL, NULL, logbook_rec_start._to_time, logbook_rec_start._to_lat, logbook_rec_start._to_lng)
                RETURNING id INTO id_end;
        */
        -- Insert stay record for the new logbook entry

    END;
$function$
;
-- Description
COMMENT ON FUNCTION api.split_logbook_fn(int4, text) IS 'Split 2 logbook by id and a timestamp. TODO';

-- DROP FUNCTION public.reverse_geocode_py_fn(in text, in numeric, in numeric, out jsonb);
-- Update public.reverse_geocode_py_fn, add request timeout and headers for identification
CREATE OR REPLACE FUNCTION public.reverse_geocode_py_fn(geocoder text, lon numeric, lat numeric, OUT geo jsonb)
 RETURNS jsonb
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
AS $function$
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

    if not rv or len(rv) == 0:
        plpy.error(f'Error fetching url from geocoders table for name [{geocoder}]')
        return None

    url = rv[0]['url']

    # Validate input
    if not lon or not lat:
        plpy.notice('reverse_geocode_py_fn Parameters [{}] [{}]'.format(lon, lat))
        plpy.error('Error missing parameters')
        return None

    def georeverse(geocoder, lon, lat, zoom="18"):
	    # Make the request to the geocoder API
	    # https://operations.osmfoundation.org/policies/nominatim/
	    headers = {"Accept-Language": "en-US,en;q=0.5", "User-Agent": "PostgSail", "From": "postgsail@localhost"}
	    payload = {"lon": lon, "lat": lat, "format": "jsonv2", "zoom": zoom, "accept-language": "en"}
	    # https://nominatim.org/release-docs/latest/api/Reverse/
	    r = requests.get(url, headers=headers, params=payload, timeout=(60, 60))

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
$function$
;
-- Description
COMMENT ON FUNCTION public.reverse_geocode_py_fn(in text, in numeric, in numeric, out jsonb) IS 'query reverse geo service to return location name using plpython3u';

-- DROP FUNCTION public.send_pushover_py_fn(text, jsonb, jsonb);
-- Update public.send_pushover_py_fn, add request timeout and headers for identification
CREATE OR REPLACE FUNCTION public.send_pushover_py_fn(message_type text, _user jsonb, app jsonb)
 RETURNS void
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
AS $function$
    """
    https://pushover.net/api#messages
    Send a notification to a pushover user
    """
    import requests
    from urllib.parse import urljoin

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

    def clean_url(base, path):
        base = base.rstrip('/') + '/'
        path = '/' + '/'.join(filter(None, path.split('/')))
        return urljoin(base, path)

    # Replace fields using input jsonb obj
    if 'logbook_name' in _user and _user['logbook_name']:
        pushover_message = pushover_message.replace('__LOGBOOK_NAME__', _user['logbook_name'])
    if 'logbook_link' in _user and _user['logbook_link']:
        pushover_message = pushover_message.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'video_link' in _user and _user['video_link'] and 'app.videos_url' in _user and _user['app.videos_url']:
        pushover_message = pushover_message.replace('__VIDEO_LINK__', clean_url(_user['app.videos_url'], str(_user['video_link'])))
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

    headers = {"User-Agent": "PostgSail", "From": "postgsail@localhost"}
    if 'ua' in _user and _user['ua']:
        headers["User-Agent"] = _user['ua']
        headers["From"] = _user['app.email_from']

    if message_type == 'logbook' and 'logbook_img' in _user and _user['logbook_img'] and 'app.gis_url' in _user and _user['app.gis_url']:
        # Send notification with gis image logbook as attachment
        img_url = '{}'.format(clean_url(_user['app.gis_url'], str(_user['logbook_img'])))
        response = requests.get(img_url, headers=headers, stream=True, timeout=(5, 60))
        if response.status_code == 200:
            r = requests.post("https://api.pushover.net/1/messages.json", data = {
                "token": pushover_token,
                "user": pushover_user,
                "title": pushover_title,
                "message": pushover_message
            }, files = {
                "attachment": (str(_user['logbook_img']), response.raw.data, "image/png")
            }, headers=headers, timeout=(60, 60))
    else:
        r = requests.post("https://api.pushover.net/1/messages.json", data = {
                "token": pushover_token,
                "user": pushover_user,
                "title": pushover_title,
                "message": pushover_message
        }, headers=headers, timeout=(60, 60))

    #print(r.text)
    # Return ?? or None if not found
    #plpy.notice('Sent pushover successfully to [{}] [{}]'.format(r.text, r.status_code))
    if r.status_code == 200:
        plpy.notice('Sent pushover successfully to [{}] [{}] [{}]'.format(pushover_user, pushover_title, r.text))
    else:
        plpy.error('Failed to send pushover')
    return None
$function$
;
-- Description
COMMENT ON FUNCTION public.send_pushover_py_fn(text, jsonb, jsonb) IS 'Send pushover notification using plpython3u';

-- DROP FUNCTION public.send_telegram_py_fn(text, jsonb, jsonb);
-- Update public.send_telegram_py_fn, add request timeout and headers for identification
CREATE OR REPLACE FUNCTION public.send_telegram_py_fn(message_type text, _user jsonb, app jsonb)
 RETURNS void
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
AS $function$
    """
    https://core.telegram.org/bots/api#sendmessage
    Send a message to a telegram user or group specified on chatId
    chat_id must be a number!
    """
    import requests
    import json
    from urllib.parse import urljoin

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

    def clean_url(base, path):
        base = base.rstrip('/') + '/'
        path = '/' + '/'.join(filter(None, path.split('/')))
        return urljoin(base, path)

    # Replace fields using input jsonb obj
    if 'logbook_name' in _user and _user['logbook_name']:
        telegram_message = telegram_message.replace('__LOGBOOK_NAME__', _user['logbook_name'])
    if 'logbook_link' in _user and _user['logbook_link']:
        telegram_message = telegram_message.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'video_link' in _user and _user['video_link'] and 'app.videos_url' in _user and _user['app.videos_url']:
        telegram_message = telegram_message.replace('__VIDEO_LINK__', clean_url(_user['app.videos_url'], str(_user['video_link'])))
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
            'Proxy-Authorization': 'Basic base64',
            'User-Agent': 'PostgSail',
            'From': 'postgsail@localhost'}
    if 'ua' in _user and _user['ua']:
        headers["User-Agent"] = _user['ua']
        headers["From"] = _user['app.email_from']

    data_dict = {'chat_id': telegram_chat_id,
                'text': telegram_message,
                'parse_mode': 'HTML',
                'disable_notification': False}
    data = json.dumps(data_dict)
    url = f'https://api.telegram.org/bot{telegram_token}/sendMessage'
    r = requests.post(url, data=data, headers=headers, timeout=(60, 60))
    if message_type == 'logbook' and 'logbook_img' in _user and _user['logbook_img'] and 'app.gis_url' in _user and _user['app.gis_url']:
        # Send gis image logbook
        # https://core.telegram.org/bots/api#sendphoto
        data_dict['photo'] = '{}'.format(clean_url(_user['app.gis_url'], str(_user['logbook_img'])))
        del data_dict['text']
        data = json.dumps(data_dict)
        url = f'https://api.telegram.org/bot{telegram_token}/sendPhoto'
        r = requests.post(url, data=data, headers=headers, timeout=(60, 60))

    #print(r.text)
    # Return something boolean?
    #plpy.notice('Sent telegram successfully to [{}] [{}]'.format(r.text, r.status_code))
    if r.status_code == 200:
        plpy.notice('Sent telegram successfully to [{}] [{}] [{}]'.format(telegram_chat_id, telegram_title, r.text))
    else:
        plpy.error('Failed to send telegram')
    return None
$function$
;
-- Description
COMMENT ON FUNCTION public.send_telegram_py_fn(text, jsonb, jsonb) IS 'Send a message to a telegram user or group specified on chatId using plpython3u';

-- Update public.cron_process_grafana_fn, cleanup - remove keycloak provisioning
CREATE OR REPLACE FUNCTION public.cron_process_grafana_fn() RETURNS void
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
-- Description
COMMENT ON FUNCTION public.cron_process_grafana_fn() IS 'init by pg_cron to check for new vessel pending grafana provisioning, if so perform grafana_py_fn';

-- DROP FUNCTION api.telegram(int8, text);
-- Update api.telegram, generate a JWT bot_role token based on chat_id from telegram
CREATE OR REPLACE FUNCTION api.telegram(user_id bigint, email text DEFAULT NULL::text)
 RETURNS auth.jwt_token
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = api, public, pg_catalog
AS $function$
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
                select 'bot_role' as role,
                (select lower(_email)) as email,
                _uid as uid,
                extract(epoch from now())::integer + 60*60 as exp
            ) r
            into result;
        return result;
    END;
$function$
;
-- Description
COMMENT ON FUNCTION api.telegram(int8, text) IS 'Generate a JWT bot_role token based on chat_id from telegram, check if the telegram session exist for the chat_id, if so get the email and user_id, then generate a JWT token with role bot_role and return it, if not return null';

-- api.eventlogs_view source
-- Update api.eventlogs_view, ensure the current settings is transaction-local only
CREATE OR REPLACE VIEW api.eventlogs_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT id,
    channel,
    payload,
    ref_id,
    stored,
    processed
   FROM process_queue pq
  WHERE processed IS NOT NULL
  AND channel NOT IN ('new_stay', 'pre_logbook', 'post_logbook')
  AND (ref_id = current_setting('user.id'::text, true) OR ref_id = current_setting('vessel.id'::text, true))
  ORDER BY id DESC;
-- Description
COMMENT ON VIEW api.eventlogs_view IS 'Event logs view';

-- Update api.logs_by_day_fn, Fix logs_by_day_fn: 'D' returns '1'-'7' (no leading zero) but template uses '01'-'07'
-- Use ISO day ('ID') 1=Mon..7=Sun, with lpad for leading zero
CREATE OR REPLACE FUNCTION api.logs_by_day_fn(OUT charts jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
    DECLARE
        data JSONB;
    BEGIN
        SELECT json_object_agg(day, count) INTO data
            FROM (
                SELECT
                    lpad(to_char(_from_time, 'ID'), 2, '0') AS day,
                    count(*) AS count
                FROM api.logbook
                WHERE _from_time IS NOT NULL
                GROUP BY day
                ORDER BY day
            ) AS t;
        -- 01=Mon .. 07=Sun (ISO)
        SELECT '{"01": 0, "02": 0, "03": 0, "04": 0, "05": 0, "06": 0, "07": 0}'::jsonb ||
            data::jsonb INTO charts;
    END;
$function$;
-- Description
COMMENT ON FUNCTION api.logs_by_day_fn(OUT charts jsonb) IS 'logbook stats by day of week for web charts (01=Mon..07=Sun)';

-- Add api.logs_by_year_fn: logs by year for web charts
-- Years are unbounded so no fixed template; returns only years present in data
CREATE OR REPLACE FUNCTION api.logs_by_year_fn(OUT charts jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
    BEGIN
        SELECT json_object_agg(year, count) INTO charts
            FROM (
                SELECT
                    to_char(_from_time, 'YYYY') AS year,
                    count(*) AS count
                FROM api.logbook
                WHERE _from_time IS NOT NULL
                GROUP BY year
                ORDER BY year
            ) AS t;
    END;
$function$;
-- Description
COMMENT ON FUNCTION api.logs_by_year_fn(OUT charts jsonb) IS 'logbook stats by year for web charts';

-- Add api.profile_fn, return user profile information based on current user email, including email, first name, last name, created_at, username (first initial + last name), has_vessel (boolean), and preferences (json with some keys removed for security)
CREATE OR REPLACE FUNCTION api.profile_fn(OUT profile json)
    RETURNS json
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = api, public, pg_catalog
    AS $function$
BEGIN                                                                                                                                                                                                                             
    SELECT row_to_json(row)::json INTO profile                                                                                                                                                                                            
    FROM (
        SELECT a.email, a.first, a.last, a.created_at,
                INITCAP(CONCAT(LEFT(first, 1), ' ', last)) AS username,                                                                                                                                                                      
                public.has_vessel_fn() AS has_vessel,                                                                                                                                                                                        
                (a.preferences::jsonb - ARRAY[                                                                                                                                                                                               
                    'ip',
                    'windy',
                    'telegram',
                    'public_password',
                    'pushover_user_key',
                    'windy_password_station'
                ])::json AS preferences                                                                                                                                                                                                      
        FROM auth.accounts a
        WHERE email = current_setting('user.email')
        ) row;
END;
$function$;            
-- Description
COMMENT ON FUNCTION api.profile_fn(out json) IS 'Return user profile information based on current user email';

REVOKE EXECUTE ON FUNCTION api.profile_fn() FROM PUBLIC;                                                                                                                                                                        
GRANT EXECUTE ON FUNCTION api.profile_fn() TO bot_role;

-- Add api.badges_fn, return earned badges for the current user based on badges defined in public.badges and user preferences->badges, including badge name, description, earned_at (timestamp from preferences->badges->key->date), and logbook_id (int from preferences->badges->key->log)
CREATE OR REPLACE FUNCTION api.badges_fn(OUT badges json)                                                                                                                                                                               
    RETURNS json
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = api, public, pg_catalog
    AS $function$
BEGIN                                                                                                                                                                                           
    SELECT json_agg(row_to_json(b)) INTO badges
    FROM (                                                                                                                                                                                           
    SELECT 
        b.name,
        b.description,
        (e.value->>'date')::timestamptz AS earned_at,
        (e.value->>'log')::int          AS logbook_id
    FROM auth.accounts a,
        jsonb_each(a.preferences->'badges') e
    JOIN public.badges b ON b.name = e.key                                                                                                                                                                                              
    WHERE a.email = current_setting('user.email')
    ORDER BY earned_at                                                                                                                                                                                                                  
    ) b;          
END;
$function$;
-- Description
COMMENT ON FUNCTION api.badges_fn(out json) IS 'Return earned badges for the current user';                                                                                                                                             

REVOKE EXECUTE ON FUNCTION api.badges_fn() FROM PUBLIC;                                                                                                                                                                                 
GRANT EXECUTE ON FUNCTION api.badges_fn() TO user_role, bot_role;

--DROP FUNCTION IF EXISTS public.cron_prune_otp_fn();
-- Update public.cron_prune_otp_fn, Single DELETE replaces previous N+1 row loop.
CREATE OR REPLACE FUNCTION public.cron_prune_otp_fn()
    RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    _deleted_count integer;
BEGIN
    RAISE NOTICE 'cron_prune_otp_fn';
 
    DELETE FROM auth.otp
    WHERE otp_timestamp < NOW() AT TIME ZONE 'UTC' - INTERVAL '15 MINUTES';
 
    GET DIAGNOSTICS _deleted_count = ROW_COUNT;
 
    IF _deleted_count > 0 THEN
        RAISE NOTICE '-> cron_prune_otp_fn deleted % expired OTP row(s)', _deleted_count;
    END IF;
END;
$$;
-- Description
COMMENT ON FUNCTION public.cron_prune_otp_fn() IS
    'Called by pg_cron to purge OTP tokens older than 15 minutes';

--DROP FUNCTION IF EXISTS api.generate_otp_fn(text);
-- Update api.generate_otp_fn, replaces otp_pass, resets otp_timestamp and otp_tries to 0.
CREATE OR REPLACE FUNCTION api.generate_otp_fn(email text)
    RETURNS text
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path TO 'api', 'auth', 'public', 'pg_catalog'
    AS $$
DECLARE
    _email CITEXT := email;
    _email_check  text  := NULL;
    _otp_pass     VARCHAR(10) := NULL;
BEGIN
    IF email IS NULL OR _email IS NULL OR _email = '' THEN
        RAISE EXCEPTION 'invalid input' USING HINT = 'check your parameter';
    END IF;
 
    SELECT a.email INTO _email_check
        FROM auth.accounts a
        WHERE a.email = _email;
 
    IF _email_check IS NULL THEN
        RAISE WARNING '-> generate_otp_fn: unknown email [%]', email;
        RETURN NULL;
    END IF;
 
    SELECT public.generate_uid_fn(6) INTO _otp_pass;
 
    INSERT INTO auth.otp (user_email, otp_pass)
        VALUES (_email_check, _otp_pass)
        ON CONFLICT (user_email) DO UPDATE
            SET otp_pass      = EXCLUDED.otp_pass,
                otp_timestamp = NOW(),
                otp_tries     = 0;  -- reset attempt counter for the new token
 
    RETURN _otp_pass;
END;
$$;
-- Description
COMMENT ON FUNCTION api.generate_otp_fn(text) IS 'Generate a 6-character numeric OTP for the given email. On conflict resets otp_pass, otp_timestamp, and otp_tries = 0 so the new token gets a full 3 attempts.';

--DROP FUNCTION IF EXISTS api.delete_logbook_fn;
-- Update api.delete_logbook_fn, Update casting, avoid NULL active.
CREATE OR REPLACE FUNCTION api.delete_logbook_fn(_id integer)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$
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
                AND s.arrived = logbook_rec._to_time::TIMESTAMPTZ;
        -- Update related stays
        UPDATE api.stays s
            SET notes = 'mark for deletion'
            WHERE s.vessel_id = current_setting('vessel.id', false)
                AND s.arrived = logbook_rec._to_time::TIMESTAMPTZ;
        -- Find previous stays
        SELECT id INTO previous_stays_id
            FROM api.stays s
            WHERE s.vessel_id = current_setting('vessel.id', false)
                AND s.arrived < logbook_rec._to_time::TIMESTAMPTZ
                ORDER BY s.arrived DESC LIMIT 1;
        -- Update previous stays with the departed time from current stays
        --  and set the active state from current stays
        IF previous_stays_id IS NOT NULL AND current_stays_active IS NOT NULL THEN
            UPDATE api.stays
                SET departed = current_stays_departed::TIMESTAMPTZ,
                    active = current_stays_active
                WHERE vessel_id = current_setting('vessel.id', false)
                    AND id = previous_stays_id;
        ELSE
            RAISE WARNING '-> delete_logbook_fn skipping previous stay update: previous_stays_id=%, current_stays_active=%',
                previous_stays_id, current_stays_active;
        END IF;
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
$function$
;
-- Description
COMMENT ON FUNCTION api.delete_logbook_fn(int4) IS 'Delete a logbook and dependency stay';

-- DROP FUNCTION public.process_pre_logbook_fn(int4);
-- Update public.process_pre_logbook_fn, Update casting, avoid NULL active.
CREATE OR REPLACE FUNCTION public.process_pre_logbook_fn(_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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
	        IF previous_stays_id IS NOT NULL AND current_stays_active IS NOT NULL THEN
	            UPDATE api.stays
	                SET departed = current_stays_departed::TIMESTAMPTZ,
	                    active = current_stays_active
	                WHERE vessel_id = current_setting('vessel.id', false)
	                    AND id = previous_stays_id
                        AND departed IS NULL;
	        ELSE
	            RAISE WARNING '-> process_pre_logbook_fn skipping previous stay update: previous_stays_id=%, current_stays_active=%',
	                previous_stays_id, current_stays_active;
	        END IF;
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
$function$
;

COMMENT ON FUNCTION public.process_pre_logbook_fn(int4) IS 'Detect/Avoid/ignore/delete logbook stationary movement or time sync issue';

--DROP FUNCTION IF EXISTS public.stay_delete_trigger_fn();
-- Fix channel patner
CREATE OR REPLACE FUNCTION public.stay_delete_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    RAISE NOTICE 'stay_delete_trigger_fn [%]', OLD;
    -- If api.stays is deleted,
    -- Delete process_queue references
    DELETE FROM public.process_queue p
        WHERE p.payload = OLD.id::TEXT
            AND p.ref_id = OLD.vessel_id
            AND p.channel = 'new_stay';
    RETURN OLD;
END;
$function$
;
-- Description
COMMENT ON FUNCTION public.stay_delete_trigger_fn() IS 'When stays is delete, process_queue references need to deleted as well.';

CREATE OR REPLACE FUNCTION public.vessel_status_trigger_fn()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    avg_sog        NUMERIC;
    cog_stddev     NUMERIC;
    displacement_m DOUBLE PRECISION;
    anchor_pos     RECORD;
    moving_signals INT := 0;
BEGIN
    -- Has auto-state plugin, trust it — nothing to do
    IF NEW.status IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Layer 1 & 2 — Temporal smoothing + COG consistency (3-minute rolling window)
    SELECT 
        AVG(speedoverground),
        STDDEV(courseovergroundtrue)
    INTO avg_sog, cog_stddev
    FROM api.metrics
    WHERE vessel_id = NEW.vessel_id
      AND time BETWEEN NEW.time - INTERVAL '3 minutes' AND NEW.time
      AND speedoverground IS NOT NULL;

    -- Layer 3 — Spatial displacement (position 5 minutes ago)
    SELECT latitude, longitude INTO anchor_pos
    FROM api.metrics
    WHERE vessel_id = NEW.vessel_id
      AND time < NEW.time - INTERVAL '5 minutes'
    ORDER BY time DESC LIMIT 1;

    IF anchor_pos IS NOT NULL THEN
        displacement_m := ST_Distance(
            ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::geography,
            ST_SetSRID(ST_MakePoint(anchor_pos.longitude, anchor_pos.latitude), 4326)::geography
        );
    END IF;

    -- Decision: need at least 2 of 3 signals to confirm movement
    IF avg_sog >= 2.5 THEN
        moving_signals := moving_signals + 1;
    END IF;
    IF cog_stddev IS NOT NULL AND cog_stddev < 0.4 AND avg_sog >= 1.5 THEN
        moving_signals := moving_signals + 1;
    END IF;
    IF displacement_m IS NOT NULL AND displacement_m > 150 THEN
        moving_signals := moving_signals + 1;
    END IF;

    IF moving_signals >= 2 THEN
        NEW.status := 'sailing';
    ELSE
        NEW.status := 'moored';
    END IF;

    RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.vessel_status_trigger_fn() IS 
    'Trigger function to set vessel status based on recent metrics when status is null. '
    'Uses a 2-of-3 decision matrix: rolling avg SOG (3min), COG stddev stability (3min), '
    'and spatial displacement vs position 5 minutes ago.';

CREATE OR REPLACE FUNCTION public.best_24h_distance_fn(_vessel_id TEXT)
RETURNS TABLE (
    best_distance_nm        NUMERIC,
    window_start            TIMESTAMPTZ,
    window_end              TIMESTAMPTZ,
    -- The log that OPENED the window (anchor log)
    anchor_log_id           INTEGER,
    anchor_log_name         TEXT,
    -- All log ids contributing to that window (for map highlight)
    contributing_log_ids    INTEGER[],
    -- Human-readable "from → to" string
    route_summary           TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
/*
  Algorithm (sliding window over sorted logbook):
  For each completed log entry L[i] (ordered by _from_time):
    window_start  = L[i]._from_time
    window_end    = window_start + INTERVAL '24 hours'
    window_dist   = SUM(distance) of all logs whose _from_time is in [window_start, window_end)
                    Note: we include partial legs by capping at window_end proportionally.
    Track best (window_start, window_dist, log_ids).
*/
DECLARE
    rec             RECORD;
    best_nm         NUMERIC  := 0;
    best_wstart     TIMESTAMPTZ;
    best_wend       TIMESTAMPTZ;
    best_anchor_id  INTEGER;
    best_anchor_nm  TEXT;
    best_log_ids    INTEGER[];
    best_route      TEXT;
    w_nm            NUMERIC;
    w_log_ids       INTEGER[];
    w_route         TEXT;
    inner_rec       RECORD;
BEGIN
    -- Outer loop: each log as potential window anchor
    FOR rec IN
        SELECT id, name, _from_time, _to_time, distance, _from, _to
        FROM api.logbook
        WHERE vessel_id = _vessel_id
          AND active    = false
          AND distance  IS NOT NULL
          AND distance  > 0
          AND _from_time IS NOT NULL
          AND _to_time   IS NOT NULL
        ORDER BY _from_time ASC
    LOOP
        w_nm       := 0;
        w_log_ids  := ARRAY[]::INTEGER[];
        w_route    := rec._from;
 
        -- Inner loop: accumulate all logs within 24h of this anchor's start
        FOR inner_rec IN
            SELECT id, name, _from_time, _to_time, distance, _to,
                   -- Proportion of leg that falls within the 24h window
                   CASE
                       WHEN _to_time <= rec._from_time + INTERVAL '24 hours'
                           THEN distance
                       ELSE distance * EXTRACT(EPOCH FROM (rec._from_time + INTERVAL '24 hours' - _from_time))
                                     / NULLIF(EXTRACT(EPOCH FROM (_to_time - _from_time)), 0)
                   END AS prorated_distance
            FROM api.logbook
            WHERE vessel_id  = _vessel_id
              AND active     = false
              AND distance   IS NOT NULL
              AND distance   > 0
              AND _from_time >= rec._from_time
              AND _from_time <  rec._from_time + INTERVAL '24 hours'
              AND _to_time   IS NOT NULL
            ORDER BY _from_time ASC
        LOOP
            w_nm      := w_nm + COALESCE(inner_rec.prorated_distance, 0);
            w_log_ids := w_log_ids || inner_rec.id;
            w_route   := inner_rec._to;  -- last destination becomes route end
        END LOOP;
 
        -- Update best if this window beats the current record
        IF w_nm > best_nm THEN
            best_nm        := ROUND(w_nm, 2);
            best_wstart    := rec._from_time;
            best_wend      := LEAST(rec._from_time + INTERVAL '24 hours',
                                    (SELECT _to_time FROM api.logbook
                                     WHERE id = w_log_ids[array_length(w_log_ids,1)]));
            best_anchor_id := rec.id;
            best_anchor_nm := rec.name;
            best_log_ids   := w_log_ids;
            best_route     := rec._from || ' → ' || w_route;
        END IF;
    END LOOP;
 
    -- Return the best window (empty set if no completed logs)
    IF best_nm > 0 THEN
        best_distance_nm     := best_nm;
        window_start         := best_wstart;
        window_end           := best_wend;
        anchor_log_id        := best_anchor_id;
        anchor_log_name      := best_anchor_nm;
        contributing_log_ids := best_log_ids;
        route_summary        := best_route;
        RETURN NEXT;
    END IF;
END;
$$;
 
COMMENT ON FUNCTION public.best_24h_distance_fn(TEXT) IS
'Computes the best rolling 24-hour distance window for a vessel by summing
all completed logbook legs that start within any 24h window (with pro-rating
for legs extending beyond the window). Returns the anchor log id, all
contributing log ids for map highlighting, and the route summary.';

-- Add api.best_24h_record_fn, PostgREST RPC ENDPOINT
--    Callable as: POST /rpc/best_24h_record_fn
--    Secured with RLS / vessel.id session variable (same pattern as other RPCs)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.best_24h_record_fn()
RETURNS TABLE (
    best_distance_nm        NUMERIC,
    window_start            TIMESTAMPTZ,
    window_end              TIMESTAMPTZ,
    anchor_log_id           INTEGER,
    anchor_log_name         TEXT,
    contributing_log_ids    INTEGER[],
    route_summary           TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = api, public
AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM public.best_24h_distance_fn(
        current_setting('vessel.id', true)
    );
END;
$$;
 
COMMENT ON FUNCTION api.best_24h_record_fn() IS
'PostgREST RPC: returns the best 24-hour rolling distance record for the
currently authenticated vessel. Exposes best_distance_nm, window_start/end,
anchor_log_id (for deep-link), contributing_log_ids (for map highlight) and
route_summary.  Call via POST /rpc/best_24h_record_fn.';

-- Update  api.stats_logs_view, extend the existing api.stats_logs_view to include the best 24h record.
--  We use a lateral subquery so it stays cheap on large datasets.
CREATE OR REPLACE VIEW api.stats_logs_view
WITH (security_invoker='true', security_barrier='true') AS
WITH meta AS (
    SELECT m.name
    FROM api.metadata m
), last_metric AS (
    SELECT m."time"
    FROM api.metrics m
    WHERE vessel_id = current_setting('vessel.id', true)
    ORDER BY m."time" DESC
    LIMIT 1
), first_metric AS (
    SELECT m."time"
    FROM api.metrics m
    WHERE vessel_id = current_setting('vessel.id', true)
    ORDER BY m."time"
    LIMIT 1
), logbook AS (
    SELECT
        count(*)                    AS number_of_log_entries,
        max(l.max_speed)            AS max_speed,
        max(l.max_wind_speed)       AS max_wind_speed,
        sum(l.distance)             AS total_distance,
        sum(l.duration)             AS total_time_underway,
        concat(max(l.distance), ' NM, ', max(l.duration), ' hours')
                                    AS longest_nonstop_sail
    FROM api.logbook l
    WHERE l.vessel_id = current_setting('vessel.id', true)
      AND l.active = false
), best24h AS (
    SELECT
        b.best_distance_nm,
        b.window_start,
        b.anchor_log_id,
        b.route_summary
    FROM public.best_24h_distance_fn(
        current_setting('vessel.id', true)
    ) b
)
SELECT
    m.name,
    fm."time"                       AS first,
    lm."time"                       AS last,
    l.number_of_log_entries,
    l.max_speed,
    l.max_wind_speed,
    l.total_distance,
    l.total_time_underway,
    l.longest_nonstop_sail,
    -- New columns for "best 24h" record
    b.best_distance_nm              AS best_24h_distance_nm,
    b.window_start                  AS best_24h_window_start,
    b.anchor_log_id                 AS best_24h_log_id,
    b.route_summary                 AS best_24h_route
FROM first_metric fm,
     last_metric lm,
     logbook l,
     meta m,
     best24h b;
 
COMMENT ON VIEW api.stats_logs_view IS
'Statistics Logs web view. Includes best_24h_distance_nm, best_24h_window_start,
best_24h_log_id (for deep-link to the logbook entry), and best_24h_route.';

-- Update public.badges_logbook_fn, extend badges_logbook_fn to check for Speed Demon
--
-- NOTE: We REPLACE the whole function here. The new block is appended just
-- before the final END; — all existing logic is preserved verbatim.
--
-- The badge JSONB structure for Speed Demon follows the existing pattern:
--   {"Speed Demon": {"log": <id>, "date": "<ts>", "distance_nm": <nm>}}
-- Unlike other one-time badges, we ALWAYS update this one when a new PB is set
-- (we store the new distance and overwrite the existing key).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.badges_logbook_fn(logbook_id integer, logbook_time text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    _badges             jsonb;
    _exist              BOOLEAN := null;
    total               integer;
    max_wind_speed      integer;
    distance            numeric;
    badge               text;
    user_settings       jsonb;
    -- Speed Demon specific
    _current_best_nm    numeric  := 0;
    _new_best_nm        numeric  := 0;
    _new_best_log       integer;
BEGIN
    -- -----------------------------------------------------------------------
    -- Helmsman: first logbook entry
    -- -----------------------------------------------------------------------
    SELECT (preferences->'badges'->'Helmsman') IS NOT NULL INTO _exist
    FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
    IF _exist IS false THEN
        SELECT count(*) INTO total FROM api.logbook l
        WHERE vessel_id = current_setting('vessel.id', false);
        IF total >= 1 THEN
            badge := '{"Helmsman": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
            SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) INTO badge;
            PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
            user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
            SELECT user_settings::JSONB || '{"badge": "Helmsman"}'::JSONB INTO user_settings;
            PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
        END IF;
    END IF;
 
    -- -----------------------------------------------------------------------
    -- Wake Maker: max wind speed ≥ 15 kn
    -- -----------------------------------------------------------------------
    SELECT (preferences->'badges'->'Wake Maker') IS NOT NULL INTO _exist
    FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
    IF _exist IS false THEN
        SELECT l.max_wind_speed INTO max_wind_speed FROM api.logbook l
        WHERE l.id = logbook_id AND l.max_wind_speed >= 15
          AND vessel_id = current_setting('vessel.id', false);
        IF max_wind_speed >= 15 THEN
            badge := '{"Wake Maker": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
            SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) INTO badge;
            PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
            user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
            SELECT user_settings::JSONB || '{"badge": "Wake Maker"}'::JSONB INTO user_settings;
            PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
        END IF;
    END IF;
 
    -- -----------------------------------------------------------------------
    -- Stormtrooper: max wind speed ≥ 30 kn
    -- -----------------------------------------------------------------------
    SELECT (preferences->'badges'->'Stormtrooper') IS NOT NULL INTO _exist
    FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
    IF _exist IS false THEN
        SELECT l.max_wind_speed INTO max_wind_speed FROM api.logbook l
        WHERE l.id = logbook_id AND l.max_wind_speed >= 30
          AND vessel_id = current_setting('vessel.id', false);
        IF max_wind_speed >= 30 THEN
            badge := '{"Stormtrooper": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
            SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) INTO badge;
            PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
            user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
            SELECT user_settings::JSONB || '{"badge": "Stormtrooper"}'::JSONB INTO user_settings;
            PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
        END IF;
    END IF;
 
    -- -----------------------------------------------------------------------
    -- Navigator Award: single leg distance ≥ 100 NM
    -- -----------------------------------------------------------------------
    SELECT (preferences->'badges'->'Navigator Award') IS NOT NULL INTO _exist
    FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
    IF _exist IS false THEN
        SELECT l.distance INTO distance FROM api.logbook l
        WHERE l.id = logbook_id AND l.distance >= 100
          AND vessel_id = current_setting('vessel.id', false);
        IF distance >= 100 THEN
            badge := '{"Navigator Award": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
            SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) INTO badge;
            PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
            user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
            SELECT user_settings::JSONB || '{"badge": "Navigator Award"}'::JSONB INTO user_settings;
            PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
        END IF;
    END IF;
 
    -- -----------------------------------------------------------------------
    -- Captain Award: cumulative distance ≥ 1000 NM
    -- -----------------------------------------------------------------------
    SELECT (preferences->'badges'->'Captain Award') IS NOT NULL INTO _exist
    FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
    IF _exist IS false THEN
        SELECT sum(l.distance) INTO distance FROM api.logbook l
        WHERE vessel_id = current_setting('vessel.id', false);
        IF distance >= 1000 THEN
            badge := '{"Captain Award": {"log": '|| logbook_id ||', "date":"' || logbook_time || '"}}';
            SELECT preferences->'badges' INTO _badges FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) INTO badge;
            PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
            user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
            SELECT user_settings::JSONB || '{"badge": "Captain Award"}'::JSONB INTO user_settings;
            PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
        END IF;
    END IF;
 
    -- -----------------------------------------------------------------------
    -- NEW: Speed Demon — best rolling 24-hour distance record
    --
    --  Logic:
    --    1. Compute the current best 24h window including today's newly
    --       completed log (the function re-runs on ALL logs, so it is always
    --       up to date after this log's processing is committed).
    --    2. Compare against the previously stored badge distance (if any).
    --    3a. If no badge exists and new best ≥ 100 NM → award badge + notify.
    --    3b. If badge exists and new best > stored best → update badge + notify
    --        with a "new_record" notification variant so the UI can show a
    --        "🎉 You broke your own record!" toast.
    -- -----------------------------------------------------------------------
    -- Retrieve current best 24h result for this vessel
    SELECT b.best_distance_nm, b.anchor_log_id
    INTO   _new_best_nm, _new_best_log
    FROM   public.best_24h_distance_fn(current_setting('vessel.id', false)) b;
 
    IF _new_best_nm IS NOT NULL AND _new_best_nm >= 100 THEN
        -- Read current stored badge distance (0 if badge not yet awarded)
        SELECT COALESCE(
                   (preferences->'badges'->'Speed Demon'->>'distance_nm')::numeric,
                   0
               )
        INTO   _current_best_nm
        FROM   auth.accounts a
        WHERE  a.email = current_setting('user.email', false);
 
        -- Award or update when the new window beats the stored record
        IF _new_best_nm > _current_best_nm THEN
            badge := json_build_object(
                'Speed Demon', json_build_object(
                    'log',          _new_best_log,
                    'date',         logbook_time,
                    'distance_nm',  _new_best_nm
                )
            )::text;
 
            SELECT preferences->'badges' INTO _badges
            FROM auth.accounts a WHERE a.email = current_setting('user.email', false);
            SELECT public.jsonb_recursive_merge(badge::jsonb, _badges::jsonb) INTO badge;
            PERFORM api.update_user_preferences_fn('{badges}'::TEXT, badge::TEXT);
 
            user_settings := get_user_settings_from_vesselid_fn(current_setting('vessel.id', false));
 
            IF _current_best_nm = 0 THEN
                -- First-time award
                SELECT user_settings::JSONB || '{"badge": "Speed Demon"}'::JSONB INTO user_settings;
                PERFORM send_notification_fn('new_badge'::TEXT, user_settings::JSONB);
            ELSE
                -- Record beaten — use a dedicated notification so the frontend
                -- can show "🎉 New 24h record: X NM (was Y NM)!"
                SELECT user_settings::JSONB
                    || json_build_object(
                           'badge',           'Speed Demon',
                           'new_distance_nm', _new_best_nm,
                           'old_distance_nm', _current_best_nm
                       )::JSONB
                INTO user_settings;
                PERFORM send_notification_fn('new_24h_record'::TEXT, user_settings::JSONB);
            END IF;
        END IF;
    END IF;

END;
$$;
 
COMMENT ON FUNCTION public.badges_logbook_fn(integer, text) IS
'Check for new logbook-based badges: Helmsman, Wake Maker, Stormtrooper,
Navigator Award, Captain Award, Speed Demon (best 24h rolling distance ≥ 100 NM,
updates badge each time user beats their own record).';

-- Insert badge metadata into the reference table
INSERT INTO public.badges (name, description)
VALUES (
    'Speed Demon',
    'Awarded for achieving a best 24-hour distance of 100 NM or more in a single rolling window. Badge is updated each time you beat your own record.'
)
ON CONFLICT (name) DO UPDATE
    SET description = EXCLUDED.description;

-- Add new EMAIL TEMPLATE for the new "new_24h_record" notification channel
INSERT INTO public.email_templates (name, email_subject, email_content, pushover_title, pushover_message)
VALUES (
    'new_24h_record',
    '🚀 New 24-Hour Distance Record!',
    E'Hi __RECIPIENT__,\n\nYour vessel __BOAT__ just set a new personal best for 24-hour distance.\n'
    || E'See more details at __APP_URL__/badges\n'
    || E'View the logbook entry: __APP_URL__/log/__LOGBOOK_LINK__\n\n'
    || E'Keep sailing!\nFrancois',
    '🚀 New 24h Record!',
    'New personal best! __BADGE_NAME__'
)
ON CONFLICT (name) DO UPDATE
    SET email_subject    = EXCLUDED.email_subject,
        email_content    = EXCLUDED.email_content,
        pushover_title   = EXCLUDED.pushover_title,
        pushover_message = EXCLUDED.pushover_message;

-- DROP FUNCTION public.cron_windy_fn();
-- Update public.cron_windy_fn, Reduce debug
CREATE OR REPLACE FUNCTION public.cron_windy_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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
    --RAISE NOTICE 'cron_windy_fn: Starting Windy data upload process.';

    -- Fetch app settings
    app_settings := get_app_settings_fn();
    --RAISE NOTICE '-> cron_windy_fn: app settings: %', app_settings;

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
        --RAISE NOTICE '-> cron_windy_fn: Processing vessel: [%]', windy_rec.name;

        -- Set vessel context
        PERFORM set_config('vessel.id', windy_rec.vessel_id, FALSE);

        -- Fetch user settings
        user_settings := get_user_settings_from_vesselid_fn(windy_rec.vessel_id::TEXT);
        --RAISE NOTICE '-> cron_windy_fn: windy_rec: [%]', windy_rec;
        --RAISE NOTICE '-> cron_windy_fn: checking user_settings [%]', user_settings;

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
            --RAISE NOTICE '-> cron_windy_fn: metric_rec: [%]', metric_rec;
            -- Skip invalid metrics
            IF metric_rec.temperature IS NULL
               OR metric_rec.pressure IS NULL
               OR metric_rec.rh IS NULL
               OR metric_rec.wind IS NULL
               OR metric_rec.winddir IS NULL
               OR metric_rec.time_bucket < NOW() - INTERVAL '2 days' THEN
               --RAISE NOTICE '-> cron_windy_fn: ignoring invalid metric: [%]', metric_rec;
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

            --RAISE NOTICE '-> cron_windy_fn: Sending metric at % to Windy: %', metric_rec.time_bucket, windy_metric;
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
                --RAISE NOTICE '-> cron_windy_fn: %', error_message;
            END;
        END LOOP;

        -- Update last metric time in user preferences
        PERFORM api.update_user_preferences_fn(
            '{windy_last_metric}'::TEXT,
            last_metric::TEXT
        );
        -- Windy is rate limiting the requests, there is no bulk processing
        PERFORM pg_sleep(2);
    END LOOP;

    --RAISE NOTICE '-> cron_windy_fn: Windy data upload process completed.';
END;
$function$
;

COMMENT ON FUNCTION public.cron_windy_fn() IS 'init by pg_cron to create (or update) station and uploading observations to Windy Personal Weather Station observations';

-- DROP FUNCTION public.cron_alerts_fn();
-- Update public.cron_alerts_fn, Reduce debug
CREATE OR REPLACE FUNCTION public.cron_alerts_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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
    --RAISE NOTICE 'cron_alerts_fn';
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
        --RAISE NOTICE '-> cron_alerts_fn for [%]', alert_rec;
        PERFORM set_config('vessel.id', alert_rec.vessel_id, false);
        PERFORM set_config('user.email', alert_rec.email, false);
        --RAISE WARNING 'public.cron_process_alert_rec_fn() scheduler vessel.id %, user.id', current_setting('vessel.id', false), current_setting('user.id', false);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(alert_rec.vessel_id::TEXT);
        --RAISE NOTICE '-> cron_alerts_fn checking user_settings [%]', user_settings;
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
            --RAISE NOTICE '-> cron_alerts_fn checking metrics [%]', metric_rec;
            --RAISE NOTICE '-> cron_alerts_fn checking alerting [%]', alert_rec.alerting;
            --RAISE NOTICE '-> cron_alerts_fn checking debug [%] [%]', kelvinToCel(metric_rec.intemp), (alert_rec.alerting->'low_indoor_temperature_threshold');
            IF metric_rec.intemp IS NOT NULL AND public.kelvintocel(metric_rec.intemp::NUMERIC) < (alert_rec.alerting->'low_indoor_temperature_threshold')::NUMERIC then
                --RAISE NOTICE '-> cron_alerts_fn checking debug indoor_temp [%]', (alert_rec.alarms->'low_indoor_temperature_threshold'->>'date')::TIMESTAMPTZ;
                --RAISE NOTICE '-> cron_alerts_fn checking debug indoor_temp [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
                    --RAISE NOTICE '-> cron_alerts_fn checking debug low_indoor_temperature_threshold +interval';
                END IF;
                --RAISE NOTICE '-> cron_alerts_fn checking debug low_indoor_temperature_threshold';
            END IF;
            IF metric_rec.outtemp IS NOT NULL AND public.kelvintocel(metric_rec.outtemp::NUMERIC) < (alert_rec.alerting->>'low_outdoor_temperature_threshold')::NUMERIC then
                --RAISE NOTICE '-> cron_alerts_fn checking debug outdoor_temp [%]', (alert_rec.alarms->'low_outdoor_temperature_threshold'->>'date')::TIMESTAMPTZ;
                --RAISE NOTICE '-> cron_alerts_fn checking debug outdoor_temp [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
                    --RAISE NOTICE '-> cron_alerts_fn checking debug low_outdoor_temperature_threshold +interval';
                END IF;
                --RAISE NOTICE '-> cron_alerts_fn checking debug low_outdoor_temperature_threshold';
            END IF;
            IF metric_rec.wattemp IS NOT NULL AND public.kelvintocel(metric_rec.wattemp::NUMERIC) < (alert_rec.alerting->>'low_water_temperature_threshold')::NUMERIC then
                --RAISE NOTICE '-> cron_alerts_fn checking debug water_temp [%]', (alert_rec.alarms->'low_water_temperature_threshold'->>'date')::TIMESTAMPTZ;
                --RAISE NOTICE '-> cron_alerts_fn checking debug water_temp [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
                    --RAISE NOTICE '-> cron_alerts_fn checking debug low_water_temperature_threshold +interval';
                END IF;
                --RAISE NOTICE '-> cron_alerts_fn checking debug low_water_temperature_threshold';
            END IF;
            IF metric_rec.watdepth IS NOT NULL AND metric_rec.watdepth::NUMERIC < (alert_rec.alerting->'low_water_depth_threshold')::NUMERIC then
                --RAISE NOTICE '-> cron_alerts_fn checking debug water_depth [%]', (alert_rec.alarms->'low_water_depth_threshold'->>'date')::TIMESTAMPTZ;
                --RAISE NOTICE '-> cron_alerts_fn checking debug water_depth [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
                    --RAISE NOTICE '-> cron_alerts_fn checking debug low_water_depth_threshold +interval';
                END IF;
                --RAISE NOTICE '-> cron_alerts_fn checking debug low_water_depth_threshold';
            END IF;
            if metric_rec.pressure IS NOT NULL AND metric_rec.pressure::NUMERIC < (alert_rec.alerting->'high_pressure_drop_threshold')::NUMERIC then
                --RAISE NOTICE '-> cron_alerts_fn checking debug pressure [%]', (alert_rec.alarms->'high_pressure_drop_threshold'->>'date')::TIMESTAMPTZ;
                --RAISE NOTICE '-> cron_alerts_fn checking debug pressure [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
                    --RAISE NOTICE '-> cron_alerts_fn checking debug high_pressure_drop_threshold +interval';
                END IF;
                --RAISE NOTICE '-> cron_alerts_fn checking debug high_pressure_drop_threshold';
            END IF;
            IF metric_rec.wind IS NOT NULL AND metric_rec.wind::NUMERIC > (alert_rec.alerting->'high_wind_speed_threshold')::NUMERIC then
                --RAISE NOTICE '-> cron_alerts_fn checking debug wind [%]', (alert_rec.alarms->'high_wind_speed_threshold'->>'date')::TIMESTAMPTZ;
                --RAISE NOTICE '-> cron_alerts_fn checking debug wind [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
                    --RAISE NOTICE '-> cron_alerts_fn checking debug high_wind_speed_threshold +interval';
                END IF;
                --RAISE NOTICE '-> cron_alerts_fn checking debug high_wind_speed_threshold';
            END IF;
            IF metric_rec.voltage IS NOT NULL AND metric_rec.voltage::NUMERIC < (alert_rec.alerting->'low_battery_voltage_threshold')::NUMERIC then
                --RAISE NOTICE '-> cron_alerts_fn checking debug voltage [%]', (alert_rec.alarms->'low_battery_voltage_threshold'->>'date')::TIMESTAMPTZ;
                --RAISE NOTICE '-> cron_alerts_fn checking debug voltage [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
                    --RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_voltage_threshold +interval';
                END IF;
                --RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_voltage_threshold';
            END IF;
            IF metric_rec.charge IS NOT NULL AND (metric_rec.charge::NUMERIC*100) < (alert_rec.alerting->'low_battery_charge_threshold')::NUMERIC then
                --RAISE NOTICE '-> cron_alerts_fn checking debug [%]', (alert_rec.alarms->'low_battery_charge_threshold'->>'date')::TIMESTAMPTZ;
                --RAISE NOTICE '-> cron_alerts_fn checking debug [%]', metric_rec.time_bucket::TIMESTAMPTZ;
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
                    --RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_charge_threshold +interval';
                END IF;
                --RAISE NOTICE '-> cron_alerts_fn checking debug low_battery_charge_threshold';
            END IF;
            -- Record last metrics time
            SELECT metric_rec.time_bucket INTO last_metric;
        END LOOP;
        PERFORM api.update_user_preferences_fn('{alert_last_metric}'::TEXT, last_metric::TEXT);
    END LOOP;
END;
$function$
;

COMMENT ON FUNCTION public.cron_alerts_fn() IS 'init by pg_cron to check for alerts';

-- DROP FUNCTION IF EXISTS public.cron_process_autodiscovery_fn;
-- Update public.cron_process_autodiscovery_fn, Reduce debug and add notification when no navigation keys found in metadata available_keys, which is a common issue when the GPS/AIS source is not properly connected
CREATE OR REPLACE FUNCTION public.cron_process_autodiscovery_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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
    _has_navigation BOOLEAN := FALSE;
BEGIN
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
            v.owner_email, coalesce(m.name, v.name) as name, m.vessel_id, m.configuration,
            m.available_keys into data_rec
            FROM auth.vessels v
            LEFT JOIN api.metadata m ON v.vessel_id = m.vessel_id
            WHERE m.vessel_id = process_rec.payload::TEXT;
        IF data_rec.vessel_id IS NULL OR data_rec.name IS NULL THEN
            RAISE WARNING '-> DEBUG cron_process_autodiscovery_fn error unknow vessel_id [%] [%]', process_rec.payload, data_rec;
            CONTINUE; -- Continue to the next vessel
        END IF;
        -- Set vessel.id for the functions that need it
        PERFORM set_config('vessel.id', data_rec.vessel_id::TEXT, false);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(data_rec.vessel_id::TEXT);
        -- Check available_keys contains at least one actionable navigation key
        -- before looking for metrics. Vessels with only design.* / sensors.gps.*
        -- keys have no GPS/AIS source connected and will never produce metrics.
        -- Send a notification so the owner knows what to fix for 1day until marking as processed and removing from the queue to avoid spamming notifications in case the vessel shows up later with valid keys when the GPS/AIS source is properly connected.
        SELECT EXISTS (
            SELECT 1
            FROM jsonb_array_elements(
                CASE
                    WHEN data_rec.available_keys IS NULL THEN '[]'::jsonb
                    ELSE data_rec.available_keys
                END
            ) AS k
            WHERE k->>'key' ~ '^(navigation|environment|propulsion)\.'
        ) INTO _has_navigation;
        IF _has_navigation IS FALSE THEN
            RAISE WARNING '-> cron_process_autodiscovery_fn, vessel_id: [%], no actionable navigation keys in available_keys: [%], sending notification',
                data_rec.vessel_id, data_rec.available_keys;
            -- Notify the owner so they know to check their GPS/AIS source in SignalK
            --user_settings := get_user_settings_from_vesselid_fn(data_rec.vessel_id::TEXT);
            PERFORM send_notification_fn('autodiscovery_no_navigation'::TEXT, user_settings::JSONB);
            -- Mark as processed so this entry does not loop forever.
            -- When the vessel re-registers with valid navigation keys the
            -- metadata insert trigger will queue a new autodiscovery entry.
            UPDATE process_queue
                SET processed = NOW()
                WHERE id = process_rec.id
                AND stored > current_timestamp - interval '1 d'; -- Avoid marking old entries as processed in case the vessel shows up later with valid keys
            RAISE NOTICE '-> cron_process_autodiscovery_fn, No navigation keys  found for vessel_id:[%] process_queue [%]', data_rec.vessel_id, process_rec.id;
            /*
            DELETE FROM api.metadata
                WHERE vessel_id = data_rec.vessel_id::TEXT;
            RAISE NOTICE '-> cron_process_autodiscovery_fn, deleted metadata for vessel_id [%] (no navigation keys)', data_rec.vessel_id;
            */
            CONTINUE; -- No navigation keys, keep waiting for 1day before marking as processed and notifying about missing navigation keys in case the vessel shows up later with valid keys    
        END IF;
        -- Check for metrics
        SELECT metrics INTO latest_metrics
            FROM api.metrics
            WHERE vessel_id = current_setting('vessel.id', false)
            ORDER BY time DESC
            LIMIT 1;
        IF NOT FOUND THEN
            RAISE WARNING '-> cron_process_autodiscovery_fn, No metrics found for vessel_id:[%] process_queue [%]', current_setting('vessel.id', false), process_rec.id;
            PERFORM send_notification_fn('autodiscovery_no_navigation'::TEXT, user_settings::JSONB);
            UPDATE process_queue
                SET processed = NOW()
                WHERE id = process_rec.id
                AND stored > current_timestamp - interval '1 d'; -- Avoid marking old entries as processed in case the vessel shows up later with valid keys
            CONTINUE; -- No metrics yet, keep waiting for 1day before marking as processed and notifying about missing navigation keys in case the vessel shows up later with valid keys
        END IF;
        -- We have both navigation keys and metrics: proceed with provisioning
        IF data_rec.configuration IS NULL THEN
            data_rec.configuration := '{}'::JSONB;
        END IF;
        SELECT public.autodiscovery_config_fn(config_default || data_rec.configuration) INTO config;
        IF config IS NULL OR config = '{}'::JSONB THEN
            RAISE WARNING '-> DEBUG cron_process_autodiscovery_fn, vessel.id [%], autodiscovery_config_fn error [%]', current_setting('vessel.id', false), config;
            UPDATE process_queue
                SET processed = NOW()
                WHERE id = process_rec.id;
            RAISE NOTICE '-> cron_process_autodiscovery_fn updated process_queue table [%]', process_rec.id;
            CONTINUE;
        END IF;
        RAISE NOTICE '-> cron_process_autodiscovery_fn, vessel.id [%], update api.metadata configuration', current_setting('vessel.id', false);
        UPDATE api.metadata
            SET configuration = config
            WHERE vessel_id = current_setting('vessel.id', false);
        --user_settings := get_user_settings_from_vesselid_fn(data_rec.vessel_id::TEXT);
        PERFORM send_notification_fn('autodiscovery'::TEXT, user_settings::JSONB);
        UPDATE process_queue
            SET processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_autodiscovery_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$function$
;

COMMENT ON FUNCTION public.cron_process_autodiscovery_fn() IS
'init by pg_cron to check for new vessel pending autodiscovery config provisioning.
Vessels with no actionable navigation/environment/propulsion keys in available_keys
are notified via autodiscovery_no_navigation and remain in the queue for 1day.
notification so the owner knows to check their GPS/AIS source in SignalK.
Vessels with valid keys but no metrics yet remain in the queue for 1day.';

-- Insert new message template for missing navigation keys
INSERT INTO public.email_templates ("name",email_subject,email_content,pushover_title,pushover_message)
	VALUES ('autodiscovery_no_navigation','PostgSail almost done','Hello __RECIPIENT__,

Your boat __BOAT__ is connected to PostgSail ⚓ — but we noticed it is not sending any navigation data yet.

To start recording logbooks, tracks and staying data, PostgSail needs these SignalK paths to be active on your vessel:

  • navigation.position         — GPS position (required)
  • navigation.speedOverGround
  • navigation.courseOverGroundTrue
  • navigation.headingTrue
  • navigation.status           - auto-state plugin (required)

These are typically provided by a GPS or AIS receiver connected to SignalK.
Here is how to check:

1. Open your SignalK dashboard → Data Browser
2. Search for navigation.position
3. If it is missing or shows no value, your GPS/AIS source is not publishing to SignalK

Common causes:
  • GPS/AIS device not connected or powered off
  • SignalK data provider not configured for the device
  • NMEA sentences not being parsed (check SignalK server logs)

Once navigation.position is live in SignalK, PostgSail will automatically detect it
and complete your vessel setup. No action needed on your side beyond fixing the source.

If you are not ready yet, just disable the plugin while you finish your setup.

Make sure you also install the auto-state plugin

If you need help, feel free to reply to this email or visit our documentation:
__APP_URL__/faq

Happy sailing! 🌊
Francois','PostgSail almost done!','__BOAT__ is connected to PostgSail ⚓ — but missing navigation data yet.')
ON CONFLICT (name) DO UPDATE
    SET email_subject    = EXCLUDED.email_subject,
        email_content    = EXCLUDED.email_content,
        pushover_title   = EXCLUDED.pushover_title,
        pushover_message = EXCLUDED.pushover_message;


CREATE OR REPLACE FUNCTION public.process_lat_lon_fn(lon numeric, lat numeric, OUT moorage_id integer, OUT moorage_type integer, OUT moorage_name text, OUT moorage_country text)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
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
            -- Determine stay type from Overpass tags
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
            moorage_name := COALESCE(
                NULLIF(overpass->>'name:en', ''),
                NULLIF(overpass->>'name', ''),
                geo->>'name'
            );
            RAISE NOTICE '-> process_lat_lon_fn output name:[%] type:[%]', moorage_name, moorage_type;
            RAISE NOTICE '-> process_lat_lon_fn insert new moorage for [%] name:[%] type:[%]', current_setting('vessel.id', false), moorage_name, moorage_type;
            -- Insert new moorage from stay
            INSERT INTO api.moorages
                (vessel_id, name, country, stay_code, latitude, longitude, geog, overpass, nominatim)
                VALUES (
                    current_setting('vessel.id', false),
                    NULLIF(replace(COALESCE(moorage_name, ''), '"', ''), ''),
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
                VALUES ('new_moorage', moorage_id, NOW(), current_setting('vessel.id', true), NOW());
        END IF;
        --return json_build_object(
        --        'id', moorage_id,
        --        'name', moorage_name,
        --        'type', moorage_type
        --        )::jsonb;
    END;
$function$
;

COMMENT ON FUNCTION public.process_lat_lon_fn(in numeric, in numeric, out int4, out int4, out text, out text) IS 'Add or Update moorage base on lat/lon';

CREATE OR REPLACE FUNCTION public.moorage_update_trigger_fn()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'moorages_update_trigger_fn [%]', NEW;
    IF OLD.name IS DISTINCT FROM NEW.name THEN
        UPDATE api.logbook SET _from = NEW.name
            WHERE vessel_id = NEW.vessel_id
              AND _from_moorage_id = NEW.id;
        UPDATE api.logbook SET _to = NEW.name
            WHERE vessel_id = NEW.vessel_id
              AND _to_moorage_id = NEW.id;
    END IF;
    IF OLD.stay_code IS DISTINCT FROM NEW.stay_code THEN
        UPDATE api.stays SET stay_code = NEW.stay_code
            WHERE vessel_id = NEW.vessel_id
              AND moorage_id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.moorage_update_trigger_fn() IS 'Automatic update of name and stay_code on logbook and stays reference';

-- Update public.moorage_delete_trigger_fn, add vessel_id scope for optimize index use
CREATE OR REPLACE FUNCTION public.moorage_delete_trigger_fn()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE NOTICE 'moorages_delete_trigger_fn [%]', OLD;
    DELETE FROM api.stays
        WHERE vessel_id = OLD.vessel_id
          AND moorage_id = OLD.id;
    DELETE FROM api.logbook
        WHERE vessel_id = OLD.vessel_id
          AND _from_moorage_id = OLD.id;
    DELETE FROM api.logbook
        WHERE vessel_id = OLD.vessel_id
          AND _to_moorage_id = OLD.id;
    DELETE FROM public.process_queue
        WHERE payload = OLD.id::TEXT
          AND ref_id  = OLD.vessel_id
          AND channel = 'new_moorage';
    RETURN OLD;
END;
$$;
COMMENT ON FUNCTION public.moorage_delete_trigger_fn() IS 'Automatic delete logbook and stays reference when delete a moorage';

DROP VIEW IF EXISTS api.vessels_view;
-- Update api.vessels_view, optimize index use
CREATE OR REPLACE VIEW api.vessels_view
  WITH (security_invoker='true', security_barrier='true') AS
SELECT
    v.name,
    v.mmsi,
    v.created_at,
    md.time                                        AS last_contact,
    md.active,
    (now() - md.time > INTERVAL '1 hour 10 min')   AS offline,
    (now() - md.time)                              AS duration,
    lm.last_metric_time,
    (now() - lm.last_metric_time > INTERVAL '1 hour 10 min') AS metrics_offline,
    (now() - lm.last_metric_time)                  AS duration_last_metrics,
    -- NULL-safe: never-seen vessel is explicitly offline
    CASE WHEN md.time IS NULL THEN true
         WHEN now() - md.time > INTERVAL '1 hour 10 min' THEN true
         ELSE false END                            AS is_offline
FROM auth.vessels v
LEFT JOIN api.metadata md
       ON md.vessel_id = v.vessel_id
LEFT JOIN LATERAL (
    SELECT "time" AS last_metric_time
    FROM api.metrics
    WHERE vessel_id = v.vessel_id          -- explicit filter for chunk exclusion
    ORDER BY "time" DESC
    LIMIT 1
) lm ON true
WHERE v.owner_email = current_setting('user.email');
-- Description
COMMENT ON VIEW api.vessels_view IS 'Expose vessels listing to web api';

DROP VIEW IF EXISTS public.first_metric;
-- Update public.first_metric view, add explicit vessel_id filter for index use and reduce result to used columns
CREATE OR REPLACE VIEW public.first_metric
    WITH (security_invoker='true', security_barrier='true') AS
    SELECT "time",
        --client_id,
        vessel_id,
        latitude,
        longitude,
        speedoverground,
        courseovergroundtrue,
        windspeedapparent,
        anglespeedapparent,
        status
        --metrics
    FROM api.metrics
    WHERE vessel_id = current_setting('vessel.id', false)
    ORDER BY "time"
    LIMIT 1;
-- Description
COMMENT ON VIEW public.first_metric IS 'First metric ever recorded across all vessels, used for debugging and to trigger provisioning of new vessels when the first ever metric is inserted';

DROP VIEW IF EXISTS public.last_metric;
-- Update public.last_metric view, add explicit vessel_id filter for index use and reduce result to used columns for faster query and to avoid exposing unnecessary data in the logs and in grafana when used as datasource for the last metric panel, which is used to trigger provisioning of new vessels when the first ever metric is inserted and should be as lightweight as possible to avoid performance issues on large datasets with many vessels and metrics
CREATE OR REPLACE VIEW public.last_metric
    WITH (security_invoker='true', security_barrier='true') AS
    SELECT "time",
        --client_id,
        vessel_id,
        latitude,
        longitude,
        speedoverground,
        courseovergroundtrue,
        windspeedapparent,
        anglespeedapparent,
        status
        --metrics
    FROM api.metrics
    WHERE vessel_id = current_setting('vessel.id', false)
    ORDER BY "time" DESC
    LIMIT 1;
-- Description
COMMENT ON VIEW public.last_metric IS 'Last metric ever recorded across all vessels, used for debugging and to trigger provisioning of new vessels when the last ever metric is inserted';

-- DROP FUNCTION public.badges_moorages_fn();
-- Update public.badges_moorages_fn, rewrite query badges_moorages_tbl and add safe guard to drop the table.
CREATE OR REPLACE FUNCTION public.badges_moorages_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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
        -- Guard against leftover table from a prior iteration or failed run
        DROP TABLE IF EXISTS badges_moorages_tbl;
        -- Get moorages with total duration
        CREATE TEMP TABLE badges_moorages_tbl AS
            SELECT
                m.id,
                m.home_flag,
                m.stay_code                                                          AS default_stay_id,
                COALESCE(SUM(s.duration), INTERVAL 'PT0S')                          AS total_duration,
                EXTRACT(day FROM COALESCE(SUM(s.duration), INTERVAL 'PT0S'))::int   AS total_duration_days
            FROM api.moorages m
            LEFT JOIN api.stays s
                ON  s.moorage_id = m.id
                AND s.active     = false
                AND s.vessel_id  = current_setting('vessel.id', false)
            WHERE m.geog       IS NOT NULL
            AND m.vessel_id   = current_setting('vessel.id', false)
            GROUP BY m.id, m.home_flag, m.stay_code
            ORDER BY total_duration_days DESC;

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
$function$
;
COMMENT ON FUNCTION public.badges_moorages_fn() IS 'check moorages for new badges, eg: Explorer, Mooring Pro, Anchormaster';

-- Update api.find_log_to_moorage_fn, fix warning output and comment within 1000m
CREATE OR REPLACE FUNCTION api.find_log_to_moorage_fn(_id integer, OUT geojson jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
        moorage_rec record;
        _geojson jsonb;
    BEGIN
        -- If _id is is not NULL and > 0
        IF _id IS NULL OR _id < 1 THEN
            RAISE WARNING '-> find_log_to_moorage_fn invalid input %', _id;
            RETURN;
        END IF;
        -- Gather moorage details
        SELECT * INTO moorage_rec
            FROM api.moorages m
            WHERE m.id = _id;
        -- Find all log from and to moorage geopoint within 1000m
        SELECT api.export_logbook_geojson_linestring_trip_fn(id)::JSON->'features' INTO _geojson
            FROM api.logbook l
            WHERE ST_DWithin(
                    Geography(ST_MakePoint(l._to_lng, l._to_lat)),
                    moorage_rec.geog,
                    1000 -- in meters - 1 nautical mile, which is 1852m
                );
        -- Return a GeoJSON filter on LineString
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', _geojson ) INTO geojson;
    END;
$function$
;

COMMENT ON FUNCTION api.find_log_to_moorage_fn(in int4, out jsonb) IS 'Find all log to moorage geopoint within 1000m';

-- Update api.find_log_to_moorage_fn, Update comment within 1000m
CREATE OR REPLACE FUNCTION api.find_log_from_moorage_fn(_id integer, OUT geojson jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
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
        -- Find all log from and to moorage geopoint within 1000m
        SELECT api.export_logbook_geojson_linestring_trip_fn(id)::JSON->'features' INTO _geojson
            FROM api.logbook l
            WHERE ST_DWithin(
                    Geography(ST_MakePoint(l._from_lng, l._from_lat)),
                    moorage_rec.geog,
                    1000 -- in meters - 1 nautical mile, which is 1852m
                );
        -- Return a GeoJSON filter on LineString
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', _geojson ) INTO geojson;
    END;
$function$
;

COMMENT ON FUNCTION api.find_log_from_moorage_fn(in int4, out jsonb) IS 'Find all log from moorage geopoint within 1000m';

DROP FUNCTION IF EXISTS api.export_stays_geojson_fn;
DROP VIEW IF EXISTS api.stays_geojson_view;
DROP VIEW IF EXISTS api.stays_explore_view;
-- Update api.stays_explore_view, Clean up 
CREATE OR REPLACE VIEW api.stays_explore_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT s.id AS stay_id,
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
        WHEN jsonb_array_length(s.user_data -> 'images'::text) > 0 THEN true
        ELSE false
    END AS has_images,
    s.user_data -> 'images'::text AS images
   FROM api.stays s
     LEFT JOIN api.moorages m ON s.moorage_id = m.id
  ORDER BY s.arrived DESC;

COMMENT ON VIEW api.stays_explore_view IS 'List moorages notes order by stays';

CREATE OR REPLACE VIEW api.stays_geojson_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT st_asgeojson(tbl.*)::jsonb AS geojson
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
            st_makepoint(stays_explore_view.longitude, stays_explore_view.latitude) AS st_makepoint
           FROM api.stays_explore_view) tbl;

COMMENT ON VIEW api.stays_geojson_view IS 'List stays as geojson';

-- Update api.export_stays_geojson_fn, Remove old table reference
CREATE OR REPLACE FUNCTION api.export_stays_geojson_fn(OUT geojson jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
    BEGIN
        SELECT jsonb_build_object(
            'type', 'FeatureCollection',
            'features', jsonb_agg(v.geojson)
        ) INTO geojson
        FROM api.stays_geojson_view v;
    END;
$function$
;

COMMENT ON FUNCTION api.export_stays_geojson_fn(out jsonb) IS 'Export stays as geojson';

-- Update public.get_app_settings_fn, Clean up query
CREATE OR REPLACE FUNCTION public.get_app_settings_fn(OUT app_settings jsonb)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
    _url      TEXT;
    _version  TEXT;
    _instance TEXT;
    _email    TEXT;
BEGIN
    SELECT
        MAX(value) FILTER (WHERE name = 'app.url'),
        MAX(value) FILTER (WHERE name = 'app.version')
    INTO _url, _version
    FROM public.app_settings
    WHERE name IN ('app.url', 'app.version');

    SELECT
        jsonb_build_object(
            'ua',   CONCAT(
                        'PostgSail postgsail-backend/', COALESCE(_version,  'unknown'),
                        ' (',         COALESCE(_url,      'unknown'), ')'
                    )
        )
        || jsonb_object_agg(name, value)
    INTO app_settings
    FROM public.app_settings
    WHERE
        name LIKE 'app.email%'
        OR name LIKE 'app.pushover%'
        OR name LIKE 'app.url'
        OR name LIKE 'app.telegram%'
        OR name LIKE 'app.windy_apikey'
        OR name LIKE 'app.%_uri'
        OR name LIKE 'app.%_url';
END;
$$;
COMMENT ON FUNCTION public.get_app_settings_fn(OUT app_settings jsonb)
    IS 'get application settings details, email, pushover, telegram, windy, etc. Includes computed ua (User-Agent) and from (contact email) keys for use in outbound plpython3u HTTP requests.';

-- Update public.process_notification_queue_fn, Rewrite to avoid cast and clean up code
CREATE OR REPLACE FUNCTION public.process_notification_queue_fn(_email text, message_type text)
    RETURNS void
    LANGUAGE plpgsql
    AS $$
    DECLARE
        account_rec record;
        vessel_rec  record;
        user_settings jsonb := NULL;
        otp_code    text;
    BEGIN
        -- Validate input
        IF _email IS NULL OR _email = '' THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
        END IF;

        -- Lookup account
        SELECT * INTO account_rec
            FROM auth.accounts
            WHERE email = _email;
        IF account_rec.email IS NULL THEN
            RAISE EXCEPTION 'Invalid email'
                USING HINT = 'Unknown email';
        END IF;

        -- Set session email for RLS / audit
        PERFORM set_config('user.email', account_rec.email, false);

        RAISE NOTICE '--> process_notification_queue_fn type [%] [%]', _email, message_type;

        -- Build user_settings based on message type
        IF message_type = 'new_account' THEN
            user_settings := jsonb_build_object(
                'email',     account_rec.email,
                'recipient', account_rec.first
            );

        ELSIF message_type = 'new_vessel' THEN
            SELECT * INTO vessel_rec
                FROM auth.vessels
                WHERE owner_email = _email;
            IF vessel_rec.owner_email IS NULL THEN
                RAISE EXCEPTION 'Invalid vessel for email [%]', _email
                    USING HINT = 'Unknown vessel';
            END IF;
            user_settings := jsonb_build_object(
                'email', vessel_rec.owner_email,
                'boat',  vessel_rec.name
            );

        ELSIF message_type = 'email_otp' THEN
            otp_code := api.generate_otp_fn(_email);
            user_settings := jsonb_build_object(
                'email',     account_rec.email,
                'recipient', account_rec.first,
                'otp_code',  otp_code
            );

        ELSE
            RAISE WARNING '-> process_notification_queue_fn unknown message_type [%]', message_type;
            RETURN;
        END IF;

        PERFORM send_notification_fn(message_type, user_settings);
    END;
$$;

COMMENT ON FUNCTION public.process_notification_queue_fn(_email text, message_type text)
    IS 'Process new event type notification: new_account, new_vessel, email_otp';

-- DROP FUNCTION public.process_logbook_queue_fn(int4);
-- Update public.process_logbook_queue_fn, Backfill the active stay that started at this logbook's arrival point
CREATE OR REPLACE FUNCTION public.process_logbook_queue_fn(_id integer)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
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

        -- Backfill the active stay that started at this logbook's arrival point
        UPDATE api.stays
            SET
              moorage_id = to_moorage.moorage_id,
              stay_code  = to_moorage.moorage_type
            WHERE vessel_id = logbook_rec.vessel_id
              AND arrived  = logbook_rec._to_time::TIMESTAMPTZ
              AND active IS true
              AND moorage_id IS NULL;

        -- Add post logbook entry to process queue for notification and QGIS processing
        -- Require as we need the logbook to be updated with SQL commit
        INSERT INTO process_queue (channel, payload, stored, ref_id)
            VALUES ('post_logbook', logbook_rec.id, NOW(), current_setting('vessel.id', true));

    END;
$function$
;

COMMENT ON FUNCTION public.process_logbook_queue_fn(int4) IS 'Update logbook details when completed, logbook_update_avg_fn, logbook_update_geom_distance_fn, reverse_geocode_py_fn';

-- DROP FUNCTION public.send_email_py_fn(text, jsonb, jsonb);

CREATE OR REPLACE FUNCTION public.send_email_py_fn(email_type text, _user jsonb, app jsonb)
 RETURNS void
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
AS $function$
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

    def clean_url(base, path):
        base = base.rstrip('/') + '/'
        path = '/' + '/'.join(filter(None, path.split('/')))
        return urljoin(base, path)

    if 'logbook_name' in _user and _user['logbook_name']:
        email_content = email_content.replace('__LOGBOOK_NAME__', str(_user['logbook_name']))
    if 'logbook_link' in _user and _user['logbook_link']:
        email_content = email_content.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'logbook_stats' in _user and _user['logbook_stats']:
        email_content = email_content.replace('__LOGBOOK_STATS__', str(_user['logbook_stats']))
    if 'video_link' in _user and _user['video_link'] and 'app.videos_url' in _user and _user['app.videos_url']:
        email_content = email_content.replace('__VIDEO_LINK__', clean_url(_user['app.videos_url'], str(_user['video_link'])))
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

    if email_type == 'logbook' and 'logbook_img' in _user and _user['logbook_img'] and 'app.gis_url' in _user and _user['app.gis_url']:
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
        # sendMessage via requests
        headers = { 'User-Agent': 'PostgSail', 'From': 'postgsail@localhost'}
        if 'ua' in _user and _user['ua']:
            headers["User-Agent"] = _user['ua']
            headers["From"] = _user['app.email_from']
        img_url = '{}'.format(clean_url(_user['app.gis_url'], str(_user['logbook_img'])))
        response = requests.get(img_url, headers=headers, stream=True, timeout=(5, 60))
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
$function$
;

COMMENT ON FUNCTION public.send_email_py_fn(text, jsonb, jsonb) IS 'Send email notification using plpython3u';

-- DROP FUNCTION public.windy_pws_py_fn(jsonb, jsonb, jsonb);
-- Update public.windy_pws_py_fn, Add User-Agent and From headers, Clean up code
CREATE OR REPLACE FUNCTION public.windy_pws_py_fn(metric jsonb, _user jsonb, app jsonb)
 RETURNS jsonb
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
 STRICT
 SET statement_timeout TO '10min'
AS $function$
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

    # Base headers
    headers = {
        'User-Agent': app['ua'] if 'ua' in app and app['ua'] else 'PostgSail',
        'From': app['app.email_from'] if 'app.email_from' in app and app['app.email_from'] else 'postgsail@localhost',
    }

    def clean_url(base, path):
        base = base.rstrip('/') + '/'
        path = '/' + '/'.join(filter(None, path.split('/')))
        return urljoin(base, path)

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
            "operator_url": clean_url(app['app.url'], f"{metric['name']}/monitoring")
        }
        plpy.notice(f'Windy Personal Weather Station create station: {station_data}')
        headers |= {
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

        headers |= {
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
$function$
;

COMMENT ON FUNCTION public.windy_pws_py_fn(jsonb, jsonb, jsonb) IS 'Forward vessel data to Windy as a Personal Weather Station using plpython3u';

-- Update public.get_user_settings_from_vesselid_fn, fix JSON string concatenation to jsonb_build_object
CREATE OR REPLACE FUNCTION public.get_user_settings_from_vesselid_fn(vesselid text, OUT user_settings jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
    DECLARE
    BEGIN
        -- If vessel_id is not NULL
        IF vesselid IS NULL OR vesselid = '' THEN
            RAISE WARNING '-> get_user_settings_from_vesselid_fn invalid input %', vesselid;
            RETURN;
        END IF;

        SELECT jsonb_build_object(
                    'boat',      v.name,
                    'recipient', a.first,
                    'email',     v.owner_email,
                    'settings',  a.preferences
               ) INTO user_settings
            FROM auth.vessels v
            JOIN auth.accounts a ON a.email = v.owner_email
            JOIN api.metadata  m ON m.vessel_id = v.vessel_id
            WHERE v.vessel_id = vesselid;

        IF user_settings IS NULL THEN
            RAISE WARNING '-> get_user_settings_from_vesselid_fn no result for vessel %', vesselid;
            RETURN;
        END IF;

        PERFORM set_config('user.email', user_settings->>'email'::TEXT, false);
        PERFORM set_config('user.recipient', user_settings->>'recipient'::TEXT, false);
    END;
$function$
;

COMMENT ON FUNCTION public.get_user_settings_from_vesselid_fn(in text, out jsonb) IS 'get user settings details from a vesselid initiate for notifications';

-- Update api.recover, fix JSON string concatenation to jsonb_build_object
CREATE OR REPLACE FUNCTION api.recover(email text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
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
        user_settings := jsonb_build_object('email', _email, 'reset_qs', _reset_qs);
        PERFORM send_notification_fn('email_reset'::TEXT, user_settings::JSONB);
        RETURN TRUE;
    END;
$function$
;

COMMENT ON FUNCTION api.recover(text) IS 'Send recover password email to reset password';

-- api schema
ALTER FUNCTION api.badges_fn(OUT badges json) SET search_path = public, pg_catalog;
ALTER FUNCTION api.best_24h_record_fn() SET search_path = public, pg_catalog;
ALTER FUNCTION api.email_fn(token text) SET search_path = public, pg_catalog;
ALTER FUNCTION api.generate_otp_fn(email text) SET search_path = public, pg_catalog;
ALTER FUNCTION api.ispublic_fn(boat text, _type text, _id integer) SET search_path = public, pg_catalog;
ALTER FUNCTION api.login(email text, pass text) SET search_path = public, pg_catalog;
ALTER FUNCTION api.profile_fn(OUT profile json) SET search_path = public, pg_catalog;
ALTER FUNCTION api.pushover_fn(token text, pushover_user_key text) SET search_path = public, pg_catalog;
ALTER FUNCTION api.pushover_subscribe_link_fn(OUT pushover_link json) SET search_path = public, pg_catalog;
ALTER FUNCTION api.recover(email text) SET search_path = public, pg_catalog;
ALTER FUNCTION api.register_vessel(vessel_email text, vessel_mmsi text, vessel_name text) SET search_path = public, pg_catalog;
ALTER FUNCTION api.reset(pass text, token text, uuid text) SET search_path = public, pg_catalog;
ALTER FUNCTION api.settings_fn(OUT settings json) SET search_path = public, pg_catalog;
ALTER FUNCTION api.signup(email text, pass text, firstname text, lastname text) SET search_path = public, pg_catalog;
ALTER FUNCTION api.telegram(user_id bigint, email text) SET search_path = public, pg_catalog;
ALTER FUNCTION api.telegram_fn(token text, telegram_obj text) SET search_path = public, pg_catalog;
ALTER FUNCTION api.telegram_otp_fn(email text, OUT otp_code text) SET search_path = public, pg_catalog;
ALTER FUNCTION api.update_user_preferences_fn(key text, value text) SET search_path = public, pg_catalog;
ALTER FUNCTION api.versions_fn() SET search_path = public, pg_catalog;
ALTER FUNCTION api.vessel_fn(OUT vessel jsonb) SET search_path = public, pg_catalog;

-- auth schema
ALTER FUNCTION auth.telegram_session_exists_fn(user_id bigint) SET search_path = auth, public, pg_catalog;
ALTER FUNCTION auth.telegram_user_exists_fn(email text, user_id bigint) SET search_path = auth, public, pg_catalog;
ALTER FUNCTION auth.verify_otp_fn(token text) SET search_path = auth, public, pg_catalog;

-- public schema
ALTER FUNCTION public.best_24h_distance_fn(_vessel_id text) SET search_path = public, pg_catalog;
ALTER FUNCTION public.check_jwt() SET search_path = public, pg_catalog;
ALTER FUNCTION public.get_app_url_fn(OUT app_settings jsonb) SET search_path = public, pg_catalog;
ALTER FUNCTION public.has_vessel_fn() SET search_path = public, pg_catalog;
ALTER FUNCTION public.has_vessel_metadata_fn() SET search_path = public, pg_catalog;

-- Allow api.vessel_fn to api_anonymous
GRANT EXECUTE ON FUNCTION api.vessel_fn TO api_anonymous;

-- Allow vessel_role to insert rejected logs.
GRANT INSERT, SELECT ON TABLE public.metrics_rejected TO vessel_role;

-- Refresh permissions user_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
-- Refresh permissions grafana
GRANT SELECT ON ALL TABLES IN SCHEMA api TO grafana;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO grafana;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO grafana;
-- Refresh permissions api_anonymous
GRANT SELECT ON ALL TABLES IN SCHEMA api TO api_anonymous;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO api_anonymous;
-- Refresh permissions bot_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO bot_role;

REVOKE EXECUTE ON FUNCTION api.settings_fn() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION api.settings_fn() TO user_role;

-- Restrict app_settings access to sql users
REVOKE SELECT ON public.app_settings FROM grafana;
REVOKE SELECT ON public.app_settings FROM scheduler;

-- Fix RLS Policy Gaps for vessel_role
DROP POLICY api_vessel_role ON api.logbook;
CREATE POLICY api_vessel_role ON api.logbook TO vessel_role 
    USING (vessel_id = current_setting('vessel.id', false)) 
    WITH CHECK (vessel_id = current_setting('vessel.id', false));

DROP POLICY api_vessel_role ON api.stays;
CREATE POLICY api_vessel_role ON api.stays TO vessel_role 
    USING (vessel_id = current_setting('vessel.id', false)) 
    WITH CHECK (vessel_id = current_setting('vessel.id', false));

DROP POLICY api_vessel_role ON api.moorages;
CREATE POLICY api_vessel_role ON api.moorages TO vessel_role 
    USING (vessel_id = current_setting('vessel.id', false)) 
    WITH CHECK (vessel_id = current_setting('vessel.id', false));

DROP POLICY api_vessel_role ON public.process_queue;
CREATE POLICY api_vessel_role ON public.process_queue TO vessel_role 
    USING (ref_id = current_setting('vessel.id', false)) 
    WITH CHECK (ref_id = current_setting('vessel.id', false));

-- Enforce RLS on auth.otp and add policy for user_role
ALTER TABLE auth.otp ENABLE ROW LEVEL SECURITY;
CREATE POLICY otp_user_role ON auth.otp TO user_role
    USING (user_email = current_setting('user.email', true))
    WITH CHECK (user_email = current_setting('user.email', true));

-- Fix RLS missing_ok inconsistency across all tables
DROP POLICY IF EXISTS api_user_role ON api.metadata;
CREATE POLICY api_user_role ON api.metadata
    TO user_role
    USING  ((vessel_id = current_setting('vessel.id'::text, true)))
    WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));
COMMENT ON POLICY api_user_role ON api.metadata IS
    'user_role RLS: USING missing_ok=true (silent empty on stale JWT), WITH CHECK missing_ok=false (hard error on write without vessel context)';

DROP POLICY IF EXISTS api_user_role ON api.metrics;
CREATE POLICY api_user_role ON api.metrics
    TO user_role
    USING  ((vessel_id = current_setting('vessel.id'::text, true)))
    WITH CHECK ((vessel_id = current_setting('vessel.id'::text, false)));
COMMENT ON POLICY api_user_role ON api.metrics IS
    'user_role RLS: USING missing_ok=true (silent empty on stale JWT), WITH CHECK missing_ok=false (hard error on write without vessel context)';

DROP POLICY IF EXISTS api_scheduler_role ON auth.accounts;
CREATE POLICY api_scheduler_role ON auth.accounts
    TO scheduler
    USING  (((email)::text = current_setting('user.email'::text, true)))
    WITH CHECK (((email)::text = current_setting('user.email'::text, false)));
COMMENT ON POLICY api_scheduler_role ON auth.accounts IS
    'scheduler RLS: USING missing_ok=true (skip row if no email context), WITH CHECK missing_ok=false (error loudly if writing without email context)';

DROP POLICY IF EXISTS api_user_role ON public.process_queue;
CREATE POLICY api_user_role ON public.process_queue
    TO user_role
    USING  (((ref_id = current_setting('user.id'::text,   true))
          OR (ref_id = current_setting('vessel.id'::text, true))))
    WITH CHECK (((ref_id = current_setting('user.id'::text,   false))
              OR (ref_id = current_setting('vessel.id'::text, false))));
COMMENT ON POLICY api_user_role ON public.process_queue IS
    'user_role RLS: USING missing_ok=true (silent empty on stale JWT), WITH CHECK missing_ok=false (hard error on write without user/vessel context)';

-- +goose StatementEnd
