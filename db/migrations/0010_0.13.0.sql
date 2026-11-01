-- +goose Up
-- +goose StatementBegin

set timezone to 'UTC';

-- Migration file
-- Per-vessel custom stay types. One field, extended vocabulary: a stay or
-- moorage still has exactly one stay_code. User-created labels appear in the
-- same picker as the built-ins.

-- Design
-- ------
-- * api.stays_at gains vessel_id. NULL = built-in, visible to everyone.
-- * Custom codes come from a single GLOBAL sequence starting at 1000. That
--   keeps api.stays.stay_code and api.moorages.stay_code as plain
--   single-column integer FKs — no composite FK, no index change, no
--   rewrite of any view beyond adding is_custom.
-- * parent_code is mandatory for custom types and must be a built-in.
--   It is the load-bearing column: analytics, badges, the MCP layer and
--   the community/public views group on the parent, only the UI renders
--   the raw label. Without it the type space fragments across 500 users.

DROP TYPE IF EXISTS public.stays_at_type;

-- -------------------------------------------------------------------------
-- 1. Duplicate index cleanup
--    stays_at_pkey and stays_at_stay_code_key are the same single-column
--    unique index on stay_code. Drop the redundant one.
-- -------------------------------------------------------------------------
ALTER TABLE api.stays    DROP CONSTRAINT stays_stay_code_fkey;
ALTER TABLE api.moorages DROP CONSTRAINT moorages_stay_code_fkey;

ALTER TABLE api.stays_at DROP CONSTRAINT stays_at_stay_code_key;

-- Only stays_at_pkey remains, so the new FKs bind to it.
ALTER TABLE api.stays
    ADD CONSTRAINT stays_stay_code_fkey
    FOREIGN KEY (stay_code) REFERENCES api.stays_at(stay_code) ON DELETE RESTRICT;

ALTER TABLE api.moorages
    ADD CONSTRAINT moorages_stay_code_fkey
    FOREIGN KEY (stay_code) REFERENCES api.stays_at(stay_code) ON DELETE RESTRICT;

-- -------------------------------------------------------------------------
-- 2. Resolver function: IMMUTABLE CASE -> STABLE table lookup
--    Not used in any index expression, so the volatility change is safe.
--    Kept for plpgsql / notification paths only. Views JOIN directly
--    rather than call this per row.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.stay_code_description(code integer)
RETURNS text
LANGUAGE sql
STABLE
PARALLEL SAFE
SET search_path TO 'api', 'public', 'pg_catalog'
AS $$
    SELECT COALESCE(
        (SELECT sa.description FROM api.stays_at sa WHERE sa.stay_code = code),
        'Unknown'
    );
$$;
 
COMMENT ON FUNCTION public.stay_code_description(code integer) IS
'Human-readable label for a stay code, resolved from api.stays_at.
 STABLE (was IMMUTABLE): the label set is data, not a compile-time constant.
 Unresolvable codes return ''Unknown'' rather than NULL.
 Prefer a direct LEFT JOIN on api.stays_at in views and set-returning SQL —
 this function exists for plpgsql and notification payload paths.';

ALTER TABLE api.stays_at
    ADD COLUMN IF NOT EXISTS vessel_id   text DEFAULT current_setting('vessel.id', true),
    ADD COLUMN IF NOT EXISTS parent_code integer,
    ADD COLUMN IF NOT EXISTS icon        text,
    ADD COLUMN IF NOT EXISTS created_at  timestamptz NOT NULL DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS updated_at  timestamptz NOT NULL DEFAULT NOW();

ALTER TABLE api.stays_at
    ADD CONSTRAINT stays_at_vessel_id_fkey
        FOREIGN KEY (vessel_id) REFERENCES api.metadata(vessel_id) ON DELETE CASCADE,
    ADD CONSTRAINT stays_at_parent_code_fkey
        FOREIGN KEY (parent_code) REFERENCES api.stays_at(stay_code) ON DELETE RESTRICT,
    ADD CONSTRAINT stays_at_custom_shape CHECK (
        (vessel_id IS NULL     AND parent_code IS NULL AND stay_code <  1000)
     OR (vessel_id IS NOT NULL                         AND stay_code >= 1000)),
    ADD CONSTRAINT stays_at_parent_is_builtin CHECK (parent_code IS NULL OR parent_code < 1000),
    ADD CONSTRAINT stays_at_description_len   CHECK (length(description) BETWEEN 2 AND 64),
    ADD CONSTRAINT stays_at_description_clean CHECK (description !~ '[[:cntrl:]]');

COMMENT ON TABLE api.stays_at IS
'Stay type lookup table and single source of truth for stay type labels.
   Built-in codes (vessel_id IS NULL, parent_code IS NULL, stay_code < 1000):
     1=Unknown, 2=Anchor, 3=Mooring Buoy, 4=Dock
   Custom codes (vessel_id NOT NULL, stay_code >= 1000) are per-vessel,
   allocated from api.stays_at_custom_code_seq via the column DEFAULT.
   parent_code is optional and rolls a custom type up to a built-in; it is
   populated from context (the stay_code of the moorage or stay being edited
   when the type is created) and read only by public.badges_moorages_fn.
   NULL parent_code means no rollup — the honest fallback, not an error.
   RLS enabled: built-ins readable by all roles, custom rows scoped to
   current_setting(''vessel.id''). Only user_role may write, own rows only.';

COMMENT ON COLUMN api.stays_at.vessel_id IS
'Owning vessel for a custom stay type. NULL = built-in, readable by every role.
 Defaults from current_setting(''vessel.id'', true) so PostgREST inserts need not
 supply it. FK to api.metadata(vessel_id) ON DELETE CASCADE: removing a vessel
 removes its custom types, and the RESTRICT FKs from api.stays/api.moorages
 mean that delete fails while rows still reference them.';

COMMENT ON COLUMN api.stays_at.parent_code IS
'Optional rollup of a custom type to a built-in (< 1000). Populated from the
 stay_code of the stay or moorage being edited when the type is created.
 Read by public.badges_moorages_fn to resolve stay-level codes, and by every
 cross-vessel path to avoid emitting user-entered free text. NULL means no
 rollup — the row counts toward no built-in threshold.';

COMMENT ON COLUMN api.stays_at.icon IS
'Optional icon, not implemented yet.';

CREATE TRIGGER stays_at_moddatetime
    BEFORE UPDATE ON api.stays_at
    FOR EACH ROW EXECUTE FUNCTION public.moddatetime('updated_at');

COMMENT ON TRIGGER stays_at_moddatetime ON api.stays_at IS
'Maintains updated_at on UPDATE via public.moddatetime.';

-- User stays are registered with custome code >= 1000
ALTER TABLE api.stays_at
    ALTER COLUMN stay_code ADD GENERATED BY DEFAULT AS IDENTITY (
        START WITH 1000 MINVALUE 1000 INCREMENT BY 1 CACHE 1
    );

-- Add the two indexes
CREATE INDEX stays_at_vessel_id_idx   ON api.stays_at (vessel_id);
CREATE INDEX stays_at_parent_code_idx ON api.stays_at (parent_code);

-- Enable RLS and force it on for all roles. Built-ins are visible to all, custom rows are scoped to the current vessel.
ALTER TABLE api.stays_at ENABLE ROW LEVEL SECURITY;
ALTER TABLE api.stays_at FORCE ROW LEVEL SECURITY;

-- Update api.moorage_view, rewrite with api.stays_at from array -> join
CREATE OR REPLACE VIEW api.moorage_view
WITH(security_invoker=true,security_barrier=true)
AS WITH stay_details AS (
         SELECT s.moorage_id,
            s.arrived,
            s.departed,
            s.duration,
            s.id AS stay_id,
            first_value(s.id) OVER (PARTITION BY s.moorage_id ORDER BY s.arrived) AS first_seen_id,
            first_value(s.id) OVER (PARTITION BY s.moorage_id ORDER BY s.departed DESC) AS last_seen_id
           FROM api.stays s
          WHERE s.vessel_id = current_setting('vessel.id'::text, true) AND s.active = false
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
                  WHERE l_1.vessel_id = current_setting('vessel.id'::text, true) AND l_1.active = false
                UNION ALL
                 SELECT l_1._to_moorage_id AS moorage_id,
                    l_1.id
                   FROM api.logbook l_1
                  WHERE l_1.vessel_id = current_setting('vessel.id'::text, true) AND l_1.active = false) logs
          GROUP BY logs.moorage_id
        )
 SELECT m.id,
    m.name,
    sa.description AS default_stay,
    m.stay_code AS default_stay_id,
    m.notes,
    m.home_flag AS home,
    m.geog,
    m.latitude,
    m.longitude,
    COALESCE(l.log_count, 0::bigint) AS logs_count,
    COALESCE(ss.stay_count, 0::bigint) AS stays_count,
    COALESCE(ss.total_duration, 'PT0S'::interval) AS stays_sum_duration,
    ss.first_seen AS stay_first_seen,
    ss.last_seen AS stay_last_seen,
    ss.first_seen_id AS stay_first_seen_id,
    ss.last_seen_id AS stay_last_seen_id,
        CASE
            WHEN jsonb_array_length(m.user_data -> 'images'::text) > 0 THEN true
            ELSE false
        END AS has_images,
    m.user_data -> 'images'::text AS images
   FROM api.moorages m
     JOIN api.stays_at sa ON m.stay_code = sa.stay_code
     LEFT JOIN stay_summary ss ON m.id = ss.moorage_id
     LEFT JOIN log_summary l ON m.id = l.moorage_id
  WHERE m.vessel_id = current_setting('vessel.id'::text, true) AND m.geog IS NOT NULL
  ORDER BY ss.total_duration DESC;

COMMENT ON VIEW api.moorage_view IS 'Moorage details web view';

-- Update api.moorages_view, rewrite with api.stays_at from array -> join
CREATE OR REPLACE VIEW api.moorages_view
WITH(security_invoker=true,security_barrier=true)
AS WITH logbook_counts AS (
         SELECT logbook._from_moorage_id AS moorage_id,
            count(*) AS entries
           FROM api.logbook
          WHERE logbook.vessel_id = current_setting('vessel.id'::text, true) AND logbook._from_moorage_id IS NOT NULL AND logbook.active = false
          GROUP BY logbook._from_moorage_id
        UNION ALL
         SELECT logbook._to_moorage_id AS moorage_id,
            count(*) AS entries
           FROM api.logbook
          WHERE logbook.vessel_id = current_setting('vessel.id'::text, true) AND logbook._to_moorage_id IS NOT NULL AND logbook.active = false
          GROUP BY logbook._to_moorage_id
        ), logbook_total AS (
         SELECT logbook_counts.moorage_id,
            sum(logbook_counts.entries) AS total_arrivals_departures
           FROM logbook_counts
          GROUP BY logbook_counts.moorage_id
        ), stays_agg AS (
         SELECT stays.moorage_id,
            sum(stays.duration) AS total_duration
           FROM api.stays
          WHERE stays.vessel_id = current_setting('vessel.id'::text, true) AND stays.active = false
          GROUP BY stays.moorage_id
        )
 SELECT m.id,
    m.name AS moorage,
    sa.description AS default_stay,
    m.stay_code AS default_stay_id,
    COALESCE(lt.total_arrivals_departures, 0::numeric) AS arrivals_departures,
    COALESCE(st.total_duration, 'PT0S'::interval) AS total_duration
   FROM api.moorages m
     JOIN api.stays_at sa ON m.stay_code = sa.stay_code
     LEFT JOIN logbook_total lt ON lt.moorage_id = m.id
     LEFT JOIN stays_agg st ON st.moorage_id = m.id
  WHERE m.vessel_id = current_setting('vessel.id'::text, true) AND m.geog IS NOT NULL
  ORDER BY (COALESCE(st.total_duration, 'PT0S'::interval)) DESC;

COMMENT ON VIEW api.moorages_view IS 'Moorages listing web view';

-- Update api.stay_view, rewrite with api.stays_at from array -> join
CREATE OR REPLACE VIEW api.stay_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT s.id,
    s.name,
    m.name AS moorage,
    m.id AS moorage_id,
    s.departed - s.arrived AS duration,
    sa.description AS stayed_at,
    s.stay_code AS stayed_at_id,
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
     JOIN api.moorages m ON s.moorage_id = m.id
     JOIN api.stays_at sa ON s.stay_code = sa.stay_code
     LEFT JOIN api.logbook "from" ON "from"._from_time = s.departed AND "from"._to_moorage_id IS NOT NULL
     LEFT JOIN api.logbook "to" ON "to"._to_time = s.arrived
  WHERE s.departed IS NOT NULL AND s.name IS NOT NULL
  ORDER BY s.arrived DESC;

COMMENT ON VIEW api.stay_view IS 'Stay listing web view';

-- Update api.stays_view, rewrite with api.stays_at from array -> join
CREATE OR REPLACE VIEW api.stays_view
WITH(security_invoker=true,security_barrier=true)
AS SELECT s.id,
    s.name,
    m.name AS moorage,
    m.id AS moorage_id,
    s.departed - s.arrived AS duration,
    sa.description AS stayed_at,
    s.stay_code AS stayed_at_id,
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
     JOIN api.moorages m ON s.moorage_id = m.id
     JOIN api.stays_at sa ON s.stay_code = sa.stay_code
     LEFT JOIN api.logbook "from" ON "from"._from_time = s.departed AND "from"._to_moorage_id IS NOT NULL
     LEFT JOIN api.logbook "to" ON "to"._to_time = s.arrived
  WHERE s.departed IS NOT NULL AND s.name IS NOT NULL
  ORDER BY s.arrived DESC;

COMMENT ON VIEW api.stays_view IS 'Stays listing web view';

-- Rewrite api.stats_stays_fn — array -> join

CREATE OR REPLACE FUNCTION api.stats_stays_fn(start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, end_date timestamp with time zone DEFAULT NULL::timestamp with time zone, OUT stats jsonb)
 RETURNS jsonb
 LANGUAGE sql
AS $function$
WITH
_vessel AS (
    SELECT current_setting('vessel.id', true) AS vessel_id
),
-- Base: all completed stays in the requested window
stays_base AS (
    SELECT
        s.moorage_id,
        s.duration,
        s.stay_code
    FROM api.stays s, _vessel
    WHERE s.vessel_id = _vessel.vessel_id
      AND s.active    = false
      AND s.arrived   >= COALESCE(start_date, '1980-01-01'::timestamptz)
      AND s.departed  <= COALESCE(end_date, NOW()) + INTERVAL '23 hours 59 minutes'
),
-- Moorage-level aggregation — one row per unique moorage visited
moorage_agg AS (
    SELECT
        s.moorage_id,
        SUM(s.duration) AS total_duration,
        COUNT(*)        AS stay_count
    FROM stays_base s
    GROUP BY s.moorage_id
),
-- Enrich with moorage metadata (home_flag, stay_code, country)
moorage_detail AS (
    SELECT
        m.id,
        m.home_flag,
        m.stay_code,
        ma.total_duration
    FROM api.moorages m
    JOIN moorage_agg ma ON ma.moorage_id = m.id
    , _vessel
    WHERE m.vessel_id = _vessel.vessel_id
),
-- Scalar aggregates
agg AS (
    SELECT
        COUNT(*)         FILTER (WHERE home_flag IS TRUE)  AS home_ports,
        COUNT(*)                                           AS unique_moorages,
        COALESCE(SUM(total_duration) FILTER (WHERE home_flag IS TRUE),  '0'::interval) AS time_at_home_ports,
        COALESCE(SUM(total_duration) FILTER (WHERE home_flag IS FALSE), '0'::interval) AS time_spent_away
    FROM moorage_detail
),
-- Stay-type breakdown for away time
away_by_type AS (
    SELECT
        sa.description AS description,
        SUM(md.total_duration) AS duration
    FROM moorage_detail md
    JOIN api.stays_at sa ON md.stay_code = sa.stay_code
    WHERE md.home_flag IS FALSE
    GROUP BY md.stay_code, sa.description
    ORDER BY md.stay_code
)
SELECT jsonb_build_object(
    'home_ports',         a.home_ports,
    'unique_moorages',    a.unique_moorages,
    'time_at_home_ports', a.time_at_home_ports,
    'time_spent_away',    a.time_spent_away,
    -- Replaces stats_moorages_away_view (was a separate multi-row endpoint)
    'time_spent_away_by', COALESCE(
        (SELECT jsonb_agg(
            jsonb_build_object(
                'description', t.description,
                'duration',    t.duration
            )
            ORDER BY t.description
        ) FROM away_by_type t),
        '[]'::jsonb
    )
)
FROM agg a;
$function$
;

COMMENT ON FUNCTION api.stats_stays_fn(in timestamptz, in timestamptz, out jsonb) IS 'Stays and moorage statistics for the current vessel within a date range (NULL = all-time).
     Replaces api.stats_moorages_view and api.stats_moorages_away_view:
       - date range filter
       - time_spent_away_by breakdown by stay type folded in as a JSONB array
         [ { description, duration }, ... ] ordered by stay_code
     Reads api.stays + api.moorages directly — no moorage_view dependency.
     Explicit vessel_id filter on all CTEs.';

-- RLS Admin
CREATE POLICY admin_all ON api.stays_at TO current_user
    USING (true) WITH CHECK (true);

-- RLS Allow user_role to update and select select based on the vessel.id
CREATE POLICY api_user_role_select ON api.stays_at FOR SELECT TO user_role
    USING (vessel_id IS NULL OR vessel_id = current_setting('vessel.id', true));

CREATE POLICY api_user_role_write ON api.stays_at FOR ALL TO user_role
    USING      (vessel_id = current_setting('vessel.id', true))
    WITH CHECK (vessel_id = current_setting('vessel.id', false));

-- RLS Allow bot_role, grafana select based on the vessel.id
-- read-only roles
CREATE POLICY api_anonymous_role ON api.stays_at TO api_anonymous
    USING (vessel_id IS NULL OR vessel_id = current_setting('vessel.id', true))
    WITH CHECK (false);
CREATE POLICY api_bot_role   ON api.stays_at TO bot_role
   USING (vessel_id IS NULL OR vessel_id = current_setting('vessel.id', true))
   WITH CHECK (false);
CREATE POLICY grafana_role   ON api.stays_at TO grafana
    USING (vessel_id IS NULL OR vessel_id = current_setting('vessel.id', true))
    WITH CHECK (false);
CREATE POLICY api_scheduler_role ON api.stays_at TO scheduler
    USING (vessel_id IS NULL OR vessel_id = current_setting('vessel.id', true))
    WITH CHECK (false);
CREATE POLICY api_vessel_role ON api.stays_at TO vessel_role
    USING (vessel_id IS NULL OR vessel_id = current_setting('vessel.id', true))
    WITH CHECK (false);
-- SaaS only
--CREATE POLICY api_mcp_role   ON api.stays_at TO mcp_role
--    USING (vessel_id IS NULL OR vessel_id = current_setting('vessel.id', true))
--    WITH CHECK (false);

-- Allow insert, update and delete for user_role on their own rows
GRANT INSERT, UPDATE, DELETE ON TABLE api.stays_at TO user_role;

-- Rewrite public.badges_moorages_fn
CREATE OR REPLACE FUNCTION public.badges_moorages_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    _vessel_id    TEXT  := current_setting('vessel.id', false);
    _email        TEXT;
    user_settings JSONB;
    _badges       JSONB;
    _new          JSONB := '{}'::JSONB;
    _now          TEXT  := NOW()::TIMESTAMP::TEXT;
    _s            RECORD;
    _b            RECORD;
BEGIN
    user_settings := get_user_settings_from_vesselid_fn(_vessel_id);
    _email        := user_settings->>'email';
    PERFORM set_config('user.email', _email, false);

    SELECT COALESCE(a.preferences->'badges', '{}'::JSONB)
      INTO _badges
      FROM auth.accounts a
     WHERE a.email = _email;

    -- One pass over completed stays. The rollup happens at STAY level:
    -- s.stay_code is the type the user actually assigned to that stay.
    -- Custom types (>= 1000) inherit their built-in parent; a custom type
    -- with no parent keeps its own code and matches no threshold.
    WITH stay_days AS (
        SELECT
            COALESCE(m.home_flag, false)             AS home_flag,
            COALESCE(sa.parent_code, s.stay_code)    AS eff_code,
            EXTRACT(EPOCH FROM s.duration) / 86400.0 AS days
        FROM api.stays s
        JOIN api.moorages m
          ON  m.id        = s.moorage_id
          AND m.vessel_id = s.vessel_id
          AND m.geog IS NOT NULL
        LEFT JOIN api.stays_at sa
          ON  sa.stay_code = s.stay_code
        WHERE s.vessel_id = _vessel_id
          AND s.active    = false
          AND s.duration IS NOT NULL
    )
    SELECT
        -- Explorer: cumulative, away from home port
        COALESCE(SUM(d.days) FILTER (WHERE NOT d.home_flag), 0) AS away_days,
        -- Mooring Buoy (built-in 3)
        COALESCE(MAX(d.days) FILTER (WHERE d.eff_code = 3), 0)  AS buoy_max,
        COALESCE(SUM(d.days) FILTER (WHERE d.eff_code = 3), 0)  AS buoy_total,
        COUNT(*)             FILTER (WHERE d.eff_code = 3)      AS buoy_stays,
        -- Anchor (built-in 2)
        COALESCE(MAX(d.days) FILTER (WHERE d.eff_code = 2), 0)  AS anchor_max,
        COALESCE(SUM(d.days) FILTER (WHERE d.eff_code = 2), 0)  AS anchor_total,
        COUNT(*)             FILTER (WHERE d.eff_code = 2)      AS anchor_stays,
        -- Traveler: unchanged semantics, all moorages with a country
        (SELECT COUNT(DISTINCT mo.country)
           FROM api.moorages mo
          WHERE mo.vessel_id = _vessel_id
            AND mo.country IS NOT NULL)                         AS countries
      INTO _s
      FROM stay_days d;

    FOR _b IN
        SELECT t.name, t.value
        FROM (VALUES
            ('Explorer',     (_s.away_days  >= 10), ROUND(_s.away_days::numeric,  1)),
            -- single longest buoy stay >= 10 nights
            ('Mooring Pro',  (_s.buoy_max   >= 10), ROUND(_s.buoy_max::numeric,   1)),
            --   cumulative alternative : (_s.buoy_total >= 10), ROUND(_s.buoy_total::numeric, 1)
            --   pickup-count alternative: (_s.buoy_stays >= 10), _s.buoy_stays::numeric
            ('Anchormaster', (_s.anchor_max >= 25), ROUND(_s.anchor_max::numeric, 1)),
            --   cumulative alternative : (_s.anchor_total >= 25), ROUND(_s.anchor_total::numeric, 1)
            ('Traveler',     (_s.countries  >= 2),  _s.countries::numeric)
        ) AS t(name, earned, value)
        WHERE t.earned
          AND NOT jsonb_exists(_badges, t.name)
    LOOP
        _new := _new || jsonb_build_object(
                    _b.name,
                    jsonb_build_object('date', _now, 'value', _b.value));
    END LOOP;

    IF _new = '{}'::JSONB THEN
        RETURN;
    END IF;

    PERFORM api.update_user_preferences_fn(
                '{badges}'::TEXT,
                public.jsonb_recursive_merge(_new, _badges)::TEXT);

    FOR _b IN SELECT key FROM jsonb_each(_new) LOOP
        PERFORM send_notification_fn('new_badge'::TEXT,
                    user_settings || jsonb_build_object('badge', _b.key));
    END LOOP;
END;
$function$;

COMMENT ON FUNCTION public.badges_moorages_fn() IS
'Check stays/moorages for new badges: Explorer, Mooring Pro, Anchormaster, Traveler.
 Rollup is at stay level: api.stays.stay_code resolved through
 api.stays_at.parent_code, so per-vessel custom types count toward the
 built-in they descend from. Custom types with a NULL parent match nothing.
 Explorer is cumulative; Mooring Pro and Anchormaster are single-stay maxima.
 Requires SELECT on api.stays_at for the executing role (scheduler).';

-- =========================================================================
-- SaaS-side consumers of stay_code.
--
-- Three classes of problem:
--
-- A. HARDCODED ARRAY (silent NULL for any code > 4)
--      1008__mcp.sql      'type', (ARRAY[...])[m.stay_code]
--      1016__community.sql (ARRAY[...])[m.stay_code] AS description   (x1)
--      1016__community.sql 'stay_type', (ARRAY[...])[m.stay_code]      (x1)
--
-- B. CROSS-VESSEL LEAK  <- the important one
--    The api.mcp_community_* functions are SECURITY DEFINER, so the RLS on
--    api.stays_at does NOT apply to them. Left as-is they would:
--      - return one vessel's private custom label to every other vessel
--      - let mcp_community_moorages_fn(_stay_type => 'Bruno''s secret cove')
--        probe for the existence of another user's label via ILIKE
--    Every cross-vessel path must use public.stay_code_public_description(),
--    which resolves custom codes to their built-in parent and never emits
--    user-entered free text.
--
-- C. ANALYTICS FRAGMENTATION -> done
--    admin.mb_stay_type_distribution groups on sa.description. With 500
--    users creating up to 10 labels each that becomes a 5000-slice pie
--    chart. Group on the parent instead. The INNER JOIN is also swapped for
--    a LEFT JOIN so an unresolvable code shows as Unknown rather than
--    dropping the row out of the totals.
--
-- NOT changed here: 1009__users_helpers.sql emits raw s.stay_code in a
-- per-user export. That is the user's own data, so the raw code is correct.
-- =========================================================================


CREATE OR REPLACE FUNCTION public.check_jwt()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
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
    SELECT current_setting('request.path', true) into _path;
    -- Function allow for anonymous role
    IF _path ~ '^(\/|\/rpc\/(login|signup|recover|reset|pushover_fn|telegram(_fn|_otp_fn)?|ispublic_fn|telemetry_fn))$' THEN
        RETURN;
    END IF;
    --RAISE WARNING 'public.check_jwt() api_anonymous path[%] vid:[%]', current_setting('request.path', true), current_setting('vessel.id', false); 
    -- Check if path is the a valid allow anonymous path
    SELECT _path ~ '^/(logs_view|log_view|vessel_view|stays_explore_view|rpc/timelapse_fn|rpc/timelapse2_fn|monitoring_live|monitoring_view|rpc/stats_fn|rpc/export_logbooks_geojson_point_trips_fn|rpc/export_logbooks_geojson_linestring_trips_fn|rpc/vessel_fn)$' INTO _ppath;
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
            ELSIF _ptype ~ '^public_(logs_list|stats|monitoring|timelapse)$' AND _pid = 0 THEN
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
    ELSE -- If path is not allow for anonymous role, block access
        RAISE sqlstate 'PT404' using message = 'unknown resource';
    END IF;
  ELSIF _role <> 'api_anonymous' THEN
    RAISE EXCEPTION 'Invalid role'
      USING HINT = 'Stop being so evil and maybe you can log in';
  END IF;
END
$function$
;

COMMENT ON FUNCTION public.check_jwt() IS 'PostgREST API db-pre-request check, set_config according to role (api_anonymous,vessel_role,user_role)';

-- Refresh permissions user_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO user_role;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO user_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO user_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO user_role;
-- Refresh permissions bot_role
GRANT SELECT ON ALL TABLES IN SCHEMA api TO bot_role;
GRANT SELECT ON ALL TABLES IN SCHEMA auth TO bot_role;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO bot_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO bot_role;
-- Refresh permissions grafana
GRANT SELECT ON ALL TABLES IN SCHEMA api TO grafana;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO grafana;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO grafana;
-- Refresh permissions api_anonymous
GRANT SELECT ON ALL TABLES IN SCHEMA api TO api_anonymous;

GRANT EXECUTE ON FUNCTION api.stats_logs_fn TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.stats_stays_fn TO api_anonymous;
GRANT EXECUTE ON FUNCTION api.stats_fn TO api_anonymous;

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
REVOKE SELECT ON public.app_settings FROM bot_role;

-- +goose StatementEnd
