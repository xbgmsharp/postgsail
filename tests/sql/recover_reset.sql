---------------------------------------------------------------------------
-- SQL test approach for recover/reset (add to a new recover_reset.sql)
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

-- Step 1: generate_otp_fn works (already tested in index4, but validate directly)
SELECT api.generate_otp_fn('demo+kapla@openplotter.cloud') IS NOT NULL AS otp_generated;

-- Step 2: OTP is stored in auth.otp with correct expiry
SELECT
    user_email = 'demo+kapla@openplotter.cloud'               AS correct_email,
    otp_pass IS NOT NULL                                       AS otp_stored,
    otp_timestamp > NOW() - INTERVAL '1 minute'               AS freshly_created,
    otp_tries = 0                                              AS tries_zero
FROM auth.otp
WHERE user_email = 'demo+kapla@openplotter.cloud';

-- Step 3: auth.verify_otp_fn with correct token returns email
SELECT otp_pass AS "otp_token" FROM auth.otp
    WHERE user_email = 'demo+kapla@openplotter.cloud' \gset
SELECT auth.verify_otp_fn(:'otp_token') = 'demo+kapla@openplotter.cloud' AS verify_otp_valid;

-- Step 4: api.reset with valid token + uuid changes the password
SELECT user_id AS "user_uuid" FROM auth.accounts
    WHERE email = 'demo+kapla@openplotter.cloud' \gset
-- Re-generate since verify_otp consumed it
SELECT api.generate_otp_fn('demo+kapla@openplotter.cloud') AS "otp_token" \gset
SELECT api.reset('new_test_pass', :'otp_token', :'user_uuid') IS TRUE AS reset_succeeds;

-- Step 5: new password actually works (auth.user_role validates bcrypt)
SELECT auth.user_role('demo+kapla@openplotter.cloud', 'new_test_pass') IS NOT NULL AS new_pass_valid;

-- Step 6: OTP is consumed — second use must fail
SELECT auth.verify_otp_fn(:'otp_token') IS NULL AS otp_consumed;

-- Step 7: restore original password
UPDATE auth.accounts SET pass = 'test' WHERE email = 'demo+kapla@openplotter.cloud';
-- Verify restore (encrypt_pass trigger re-hashes on UPDATE)
SELECT auth.user_role('demo+kapla@openplotter.cloud', 'test') IS NOT NULL AS pass_restored;