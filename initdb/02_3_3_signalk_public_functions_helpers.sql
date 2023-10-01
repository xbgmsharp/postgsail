---------------------------------------------------------------------------
-- singalk db public schema
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

CREATE SCHEMA IF NOT EXISTS public;

---------------------------------------------------------------------------
-- basic helpers to check type and more
--
CREATE OR REPLACE FUNCTION public.isdouble(text) RETURNS BOOLEAN AS
$isdouble$
DECLARE x DOUBLE PRECISION;
BEGIN
    x = $1::DOUBLE PRECISION;
    RETURN TRUE;
EXCEPTION WHEN others THEN
    RETURN FALSE;
END;
$isdouble$
STRICT
LANGUAGE plpgsql IMMUTABLE;
-- Description
COMMENT ON FUNCTION
    public.isdouble
    IS 'Check typeof value is double';

CREATE OR REPLACE FUNCTION public.isnumeric(text) RETURNS BOOLEAN AS
$isnumeric$
DECLARE x NUMERIC;
BEGIN
    x = $1::NUMERIC;
    RETURN TRUE;
EXCEPTION WHEN others THEN
    RETURN FALSE;
END;
$isnumeric$
STRICT
LANGUAGE plpgsql IMMUTABLE;
-- Description
COMMENT ON FUNCTION
    public.isnumeric
    IS 'Check typeof value is numeric';

CREATE OR REPLACE FUNCTION public.isboolean(text) RETURNS BOOLEAN AS
$isboolean$
DECLARE x BOOLEAN;
BEGIN
    x = $1::BOOLEAN;
    RETURN TRUE;
EXCEPTION WHEN others THEN
    RETURN FALSE;
END;
$isboolean$
STRICT
LANGUAGE plpgsql IMMUTABLE;
-- Description
COMMENT ON FUNCTION
    public.isboolean
    IS 'Check typeof value is boolean';

CREATE OR REPLACE FUNCTION public.isdate(s varchar) returns boolean as $$
BEGIN
  perform s::date;
  return true;
exception when others then
  return false;
END;
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION
    public.isdate
    IS 'Check typeof value is date';

CREATE OR REPLACE FUNCTION public.istimestamptz(text) RETURNS BOOLEAN AS
$isdate$
DECLARE x TIMESTAMP WITHOUT TIME ZONE;
BEGIN
    x = $1::TIMESTAMP WITHOUT TIME ZONE;
    RETURN TRUE;
EXCEPTION WHEN others THEN
    RETURN FALSE;
END;
$isdate$
STRICT
LANGUAGE plpgsql IMMUTABLE;
-- Description
COMMENT ON FUNCTION
    public.istimestamptz
    IS 'Check typeof value is TIMESTAMP WITHOUT TIME ZONE';

---------------------------------------------------------------------------
-- JSON helpers
--
CREATE FUNCTION jsonb_key_exists(some_json jsonb, outer_key text)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN (some_json->outer_key) IS NOT NULL;
END;
$$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.jsonb_key_exists
    IS 'function that checks if an outer key exists in some_json and returns a boolean';

-- https://stackoverflow.com/questions/42944888/merging-jsonb-values-in-postgresql
CREATE OR REPLACE FUNCTION public.jsonb_recursive_merge(A jsonb, B jsonb)
RETURNS jsonb LANGUAGE SQL AS $$
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
-- Description
COMMENT ON FUNCTION
    public.jsonb_recursive_merge
    IS 'Merging JSONB values';

-- https://stackoverflow.com/questions/36041784/postgresql-compare-two-jsonb-objects
CREATE OR REPLACE FUNCTION public.jsonb_diff_val(val1 JSONB,val2 JSONB)
RETURNS JSONB AS $jsonb_diff_val$
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
$jsonb_diff_val$ LANGUAGE plpgsql;
-- Description
COMMENT ON FUNCTION
    public.jsonb_diff_val
    IS 'Compare two jsonb objects';
