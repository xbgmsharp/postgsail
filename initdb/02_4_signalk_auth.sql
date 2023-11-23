---------------------------------------------------------------------------
-- SQL User Management - Storing Users and Passwords and Vessels
-- We put things inside the auth schema to hide
-- them from public view. Certain public procs/views will
-- refer to helpers and tables inside.
-- base on https://postgrest.org/en/stable/auth.html#sql-user-management

-- List current database
select current_database();

-- connect to the DB
\c signalk

CREATE SCHEMA IF NOT EXISTS auth;
COMMENT ON SCHEMA auth IS 'auth postgrest for users and vessels';

CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; -- provides functions to generate universally unique identifiers (UUIDs)
CREATE EXTENSION IF NOT EXISTS "moddatetime"; -- provides functions for tracking last modification time
CREATE EXTENSION IF NOT EXISTS "citext"; -- provides data type for case-insensitive character strings
CREATE EXTENSION IF NOT EXISTS "pgcrypto"; -- provides cryptographic functions

DROP TABLE IF EXISTS auth.accounts CASCADE;
CREATE TABLE IF NOT EXISTS auth.accounts (
  public_id     INT UNIQUE NOT NULL GENERATED ALWAYS AS IDENTITY,
  user_id       TEXT NOT NULL UNIQUE DEFAULT RIGHT(gen_random_uuid()::text, 12),
  email         CITEXT PRIMARY KEY CHECK ( email ~* '^.+@.+\..+$' ),
  first         TEXT NOT NULL CHECK (length(pass) < 512),
  last          TEXT NOT NULL CHECK (length(pass) < 512),
  pass          TEXT NOT NULL CHECK (length(pass) < 512),
  role          name NOT NULL CHECK (length(role) < 512),
  preferences   JSONB NULL DEFAULT '{"email_notifications":true}',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  connected_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT valid_email CHECK (length(email) > 5), -- Enforce at least 5 char, eg: a@b.io
  CONSTRAINT valid_first CHECK (length(first) > 1),
  CONSTRAINT valid_last CHECK (length(last) > 1),
  CONSTRAINT valid_pass CHECK (length(pass) > 4)
);
-- Description
COMMENT ON TABLE
    auth.accounts
    IS 'users account table';
-- Indexes
CREATE INDEX accounts_preferences_idx ON auth.accounts USING GIN (preferences);
COMMENT ON COLUMN auth.accounts.first IS 'User first name with CONSTRAINT CHECK';
COMMENT ON COLUMN auth.accounts.last IS 'User last name with CONSTRAINT CHECK';

CREATE TRIGGER accounts_moddatetime
	BEFORE UPDATE ON auth.accounts
	FOR EACH ROW
	EXECUTE PROCEDURE moddatetime (updated_at);
-- Description
COMMENT ON TRIGGER accounts_moddatetime
  ON auth.accounts
  IS 'Automatic update of updated_at on table modification';

DROP TABLE IF EXISTS auth.vessels;
CREATE TABLE IF NOT EXISTS auth.vessels (
  vessel_id   TEXT NOT NULL UNIQUE DEFAULT RIGHT(gen_random_uuid()::text, 12),
--  user_id       TEXT NOT NULL REFERENCES auth.accounts(user_id) ON DELETE RESTRICT,
  owner_email CITEXT PRIMARY KEY REFERENCES auth.accounts(email) ON DELETE RESTRICT,
--  mmsi		    TEXT UNIQUE, -- Should be a numeric range between 100000000 and 800000000.
  mmsi        NUMERIC UNIQUE, -- MMSI can be optional but if present must be a valid one and unique
  name        TEXT NOT NULL CHECK (length(name) >= 3 AND length(name) < 512),
--  pass        text not null check (length(pass) < 512), -- unused
  role        name not null check (length(role) < 512),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
--  CONSTRAINT valid_length_mmsi CHECK (length(mmsi) < 10 OR length(mmsi) = 0)
  CONSTRAINT valid_range_mmsi CHECK (mmsi > 100000000 AND mmsi < 800000000)
);
-- Description
COMMENT ON TABLE
    auth.vessels
    IS 'vessels table link to accounts email user_id column';
-- Indexes
CREATE INDEX vessels_vesselid_idx ON auth.vessels (vessel_id);

CREATE TRIGGER vessels_moddatetime
	BEFORE UPDATE ON auth.vessels
	FOR EACH ROW
	EXECUTE PROCEDURE moddatetime (updated_at);
-- Description
COMMENT ON TRIGGER vessels_moddatetime
  ON auth.vessels
  IS 'Automatic update of updated_at on table modification';

create or replace function
auth.check_role_exists() returns trigger as $$
begin
  if not exists (select 1 from pg_roles as r where r.rolname = new.role) then
    raise foreign_key_violation using message =
      'unknown database role: ' || new.role;
    return null;
  end if;
  return new;
end
$$ language plpgsql;

-- trigger check role on account
drop trigger if exists ensure_user_role_exists on auth.accounts;
create constraint trigger ensure_user_role_exists
  after insert or update on auth.accounts
  for each row
  execute procedure auth.check_role_exists();
-- Description
COMMENT ON TRIGGER ensure_user_role_exists
  ON auth.accounts
  IS 'ensure user role exists';

-- trigger add queue new account
CREATE TRIGGER new_account_entry AFTER INSERT ON auth.accounts
    FOR EACH ROW EXECUTE FUNCTION public.new_account_entry_fn();
-- Description
COMMENT ON TRIGGER new_account_entry
  ON auth.accounts
  IS 'Add new account in process_queue for further processing';

-- trigger add queue new account OTP validation
CREATE TRIGGER new_account_otp_validation_entry AFTER INSERT ON auth.accounts
    FOR EACH ROW EXECUTE FUNCTION public.new_account_otp_validation_entry_fn();
-- Description
COMMENT ON TRIGGER new_account_otp_validation_entry
  ON auth.accounts
  IS 'Add new account OTP validation in process_queue for further processing';

-- trigger check role on vessel
drop trigger if exists ensure_vessel_role_exists on auth.vessels;
create constraint trigger ensure_vessel_role_exists
  after insert or update on auth.vessels
  for each row
  execute procedure auth.check_role_exists();
-- trigger add queue new vessel
CREATE TRIGGER new_vessel_entry AFTER INSERT ON auth.vessels
    FOR EACH ROW EXECUTE FUNCTION public.new_vessel_entry_fn();
-- Description
COMMENT ON TRIGGER new_vessel_entry
  ON auth.vessels
  IS 'Add new vessel in process_queue for further processing';

-- trigger add new vessel name as public_vessel user configuration
CREATE TRIGGER new_vessel_public AFTER INSERT ON auth.vessels
    FOR EACH ROW EXECUTE FUNCTION public.new_vessel_public_fn();
-- Description
COMMENT ON TRIGGER new_vessel_public
  ON auth.vessels
  IS 'Add new vessel name as public_vessel user configuration';

create or replace function
auth.encrypt_pass() returns trigger as $$
begin
  if tg_op = 'INSERT' or new.pass <> old.pass then
    new.pass = crypt(new.pass, gen_salt('bf'));
  end if;
  return new;
end
$$ language plpgsql;
-- Description
COMMENT ON FUNCTION 
    auth.encrypt_pass 
    IS 'encrypt user pass on insert or update';

drop trigger if exists encrypt_pass on auth.accounts;
create trigger encrypt_pass
  before insert or update on auth.accounts
  for each row
  execute procedure auth.encrypt_pass();

create or replace function
auth.user_role(email text, pass text) returns name
  language plpgsql
  as $$
begin
  return (
  select role from auth.accounts
   where accounts.email = user_role.email
     and user_role.pass is NOT NULL
     and accounts.pass = crypt(user_role.pass, accounts.pass)
  );
end;
$$;

-- add type
CREATE TYPE auth.jwt_token AS (
  token text
);

---------------------------------------------------------------------------
-- API account helper functions
--
-- login should be on your exposed schema
create or replace function
api.login(in email text, in pass text) returns auth.jwt_token as $$
declare
  _role name;
  result auth.jwt_token;
  app_jwt_secret text;
  _email_valid boolean := false;
  _email text := email;
  _user_id text := null;
begin
  -- check email and password
  select auth.user_role(email, pass) into _role;
  if _role is null then
    -- HTTP/403
    --raise invalid_password using message = 'invalid user or password';
    -- HTTP/401
    raise insufficient_privilege using message = 'invalid user or password';
  end if;

  -- Get app_jwt_secret
  SELECT value INTO app_jwt_secret
    FROM app_settings
    WHERE name = 'app.jwt_secret';

  -- Check email_valid and generate OTP
  SELECT preferences['email_valid'],user_id INTO _email_valid,_user_id
              FROM auth.accounts a
              WHERE a.email = _email;
  IF _email_valid is null or _email_valid is False THEN
    INSERT INTO process_queue (channel, payload, stored, ref_id)
      VALUES ('email_otp', email, now(), _user_id);
  END IF;

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
$$ language plpgsql security definer;

-- signup should be on your exposed schema
create or replace function
api.signup(in email text, in pass text, in firstname text, in lastname text) returns auth.jwt_token as $$
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
$$ language plpgsql security definer;

---------------------------------------------------------------------------
-- API vessel helper functions
-- register_vessel should be on your exposed schema
create or replace function
api.register_vessel(in vessel_email text, in vessel_mmsi text, in vessel_name text) returns auth.jwt_token as $$
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
$$ language plpgsql security definer;
