---------------------------------------------------------------------------
-- Listing
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

-- output display format
\x on

\echo 'Validate anonymous access'
SELECT api.ispublic_fn('kapla', 'public_test');
SELECT api.ispublic_fn('kapla', 'public_logs_list');
SELECT api.ispublic_fn('kapla', 'public_logs', 1);
SELECT api.ispublic_fn('kapla', 'public_logs', 3);
SELECT api.ispublic_fn('kapla', 'public_monitoring');
SELECT api.ispublic_fn('kapla', 'public_timelapse');

SELECT api.ispublic_fn('aava', 'public_test');
SELECT api.ispublic_fn('aava', 'public_logs_list');
SELECT api.ispublic_fn('aava', 'public_logs', 1);
SELECT api.ispublic_fn('aava', 'public_logs', 3);
SELECT api.ispublic_fn('aava', 'public_monitoring');
SELECT api.ispublic_fn('aava', 'public_timelapse');