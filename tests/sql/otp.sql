---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

--
-- 
\echo 'Count auth.accounts'
SELECT count(*) from auth.accounts;
\echo 'Settings auth.accounts'
SELECT preferences->'email_notifications' as email_notifications from auth.accounts;
SELECT preferences->'phone_notifications' as phone_notifications from auth.accounts;
SELECT preferences->'telegram'->'chat'->'id' as telegram from auth.accounts;
--SELECT preferences->'telegram'->'date' - INTERVAL 5 minutes from auth.accounts;

SELECT count(*)
    FROM auth.accounts
    WHERE preferences->'telegram'->'chat'->'id' is null; 