---------------------------------------------------------------------------
-- singalk db public schema tables
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

CREATE SCHEMA IF NOT EXISTS public;
COMMENT ON SCHEMA public IS 'backend functions';

---------------------------------------------------------------------------
-- Table geocoders
--
-- https://github.com/CartoDB/labs-postgresql/blob/master/workshop/plpython.md
--
CREATE TABLE IF NOT EXISTS geocoders(
    name TEXT UNIQUE, 
    url TEXT, 
    reverse_url TEXT
);
-- Description
COMMENT ON TABLE
    public.geocoders
    IS 'geo service nominatim url';

INSERT INTO geocoders VALUES
('nominatim',
    NULL,
    'https://nominatim.openstreetmap.org/reverse');

---------------------------------------------------------------------------
-- Tables for message template email/pushover/telegram
--
CREATE TABLE IF NOT EXISTS email_templates(
    name TEXT UNIQUE, 
    email_subject TEXT,
    email_content TEXT,
    pushover_title TEXT,
    pushover_message TEXT
);
-- Description
COMMENT ON TABLE
    public.email_templates
    IS 'email/message templates for notifications';

-- with escape value, eg: E'A\nB\r\nC'
-- https://stackoverflow.com/questions/26638615/insert-line-break-in-postgresql-when-updating-text-field
-- TODO Update notification subject for log entry to 'logbook #NB ...'
INSERT INTO email_templates VALUES
('logbook',
    'New Logbook Entry',
    E'Hello __RECIPIENT__,\n\nWe just wanted to let you know that you have a new entry on openplotter.cloud: "__LOGBOOK_NAME__"\r\n\r\nSee more details at __APP_URL__/log/__LOGBOOK_LINK__\n\nHappy sailing!\nThe PostgSail Team',
    'New Logbook Entry',
    E'We just wanted to let you know that you have a new entry on openplotter.cloud: "__LOGBOOK_NAME__"\r\n\r\nSee more details at __APP_URL__/log/__LOGBOOK_LINK__\n\nHappy sailing!\nThe PostgSail Team'),
('user',
    'Welcome',
    E'Hello __RECIPIENT__,\nCongratulations!\nYou successfully created an account.\nKeep in mind to register your vessel.\nHappy sailing!',
    'Welcome',
    E'Hi!\nYou successfully created an account\nKeep in mind to register your vessel.\nHappy sailing!'),
('vessel',
    'New vessel',
    E'Hi!\nHow are you?\n__BOAT__ is now linked to your account.',
    'New vessel',
    E'Hi!\nHow are you?\n__BOAT__ is now linked to your account.'),
('monitor_offline',
    'Offline',
    E'__BOAT__ has been offline for more than an hour\r\nFind more details at __APP_URL__/boats/\n',
    'Offline',
    E'__BOAT__ has been offline for more than an hour\r\nFind more details at __APP_URL__/boats/\n'),
('monitor_online',
    'Online',
    E'__BOAT__ just came online\nFind more details at __APP_URL__/boats/\n',
    'Online',
    E'__BOAT__ just came online\nFind more details at __APP_URL__/boats/\n'),
('badge',
    'New Badge!',
    E'Hello __RECIPIENT__,\nCongratulations! You have just unlocked a new badge: __BADGE_NAME__\nSee more details at __APP_URL__/badges\nHappy sailing!\nThe PostgSail Team',
    'New Badge!',
    E'Congratulations!\nYou have just unlocked a new badge: __BADGE_NAME__\nSee more details at __APP_URL__/badges\nHappy sailing!\nThe PostgSail Team'),
('pushover',
    'Pushover integration',
    E'Hello __RECIPIENT__,\nCongratulations! You have just connect your account to pushover.\n\nThe PostgSail Team',
    'Pushover integration!',
    E'Congratulations!\nYou have just connect your account to pushover.\n\nThe PostgSail Team'),
('email_otp',
    'Email verification',
    E'Hello __RECIPIENT__,\nPlease active your account using the following code: __OTP_CODE__.\nThe code is valid 15 minutes.\nThe PostgSail Team',
    'Email verification',
    E'Congratulations!\nPlease validate your account. Check your email!'),
('telegram_otp',
    'Telegram bot',
    E'Hello __RECIPIENT__,\nTo connect your account to a @postgsail_bot. Please type this verification code __OTP_CODE__ back to the bot.\nThe code is valid 15 minutes.\nThe PostgSail Team',
    'Telegram bot',
    E'Congratulations!\nTo connect your account to a @postgsail_bot. Check your email!'),
('telegram_valid',
    'Telegram bot',
    E'Hello __RECIPIENT__,\nCongratulations! You have just connect your account to a @postgsail_bot.\n\nThe PostgSail Team',
    'Telegram bot!',
    E'Congratulations!\nYou have just connect your account to a @postgsail_bot.\n\nHappy sailing!\nThe PostgSail Team');

---------------------------------------------------------------------------
-- Queue handling
--
-- https://gist.github.com/kissgyorgy/beccba1291de962702ea9c237a900c79
-- https://www.depesz.com/2012/06/13/how-to-send-mail-from-database/

-- Listen/Notify way
--create function new_logbook_entry() returns trigger as $$
--begin
--    perform pg_notify('new_logbook_entry', NEW.id::text);
--    return NEW;
--END;
--$$ language plpgsql;

-- table way
CREATE TABLE IF NOT EXISTS public.process_queue (
    id SERIAL PRIMARY KEY,
    channel TEXT NOT NULL,
    payload TEXT NOT NULL,
    stored TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    processed TIMESTAMP WITHOUT TIME ZONE DEFAULT NULL
);
-- Description
COMMENT ON TABLE
    public.process_queue
    IS 'process queue for async job';
-- Index
CREATE INDEX ON public.process_queue (channel);
CREATE INDEX ON public.process_queue (stored);
CREATE INDEX ON public.process_queue (processed);

-- Function process_queue helpers
create function new_account_entry_fn() returns trigger as $new_account_entry$
begin
    insert into process_queue (channel, payload, stored) values ('new_account', NEW.email, now());
    return NEW;
END;
$new_account_entry$ language plpgsql;

create function new_account_otp_validation_entry_fn() returns trigger as $new_account_otp_validation_entry$
begin
    insert into process_queue (channel, payload, stored) values ('new_account_otp', NEW.email, now());
    return NEW;
END;
$new_account_otp_validation_entry$ language plpgsql;

create function new_vessel_entry_fn() returns trigger as $new_vessel_entry$
begin
    insert into process_queue (channel, payload, stored) values ('new_vessel', NEW.owner_email, now());
    return NEW;
END;
$new_vessel_entry$ language plpgsql;

---------------------------------------------------------------------------
-- Tables Application Settings
-- https://dba.stackexchange.com/questions/27296/storing-application-settings-with-different-datatypes#27297
-- https://stackoverflow.com/questions/6893780/how-to-store-site-wide-settings-in-a-database
-- http://cvs.savannah.gnu.org/viewvc/*checkout*/gnumed/gnumed/gnumed/server/sql/gmconfiguration.sql

CREATE TABLE IF NOT EXISTS public.app_settings (
  name TEXT NOT NULL UNIQUE,
  value TEXT NOT NULL
);
-- Description
COMMENT ON TABLE public.app_settings IS 'application settings';
COMMENT ON COLUMN public.app_settings.name IS 'application settings name key';
COMMENT ON COLUMN public.app_settings.value IS 'application settings value';

---------------------------------------------------------------------------
-- Badges descriptions
-- TODO add contiditions
--
CREATE TABLE IF NOT EXISTS badges(
    name TEXT UNIQUE, 
    description TEXT
);
-- Description
COMMENT ON TABLE
    public.badges
    IS 'Badges descriptions';

INSERT INTO badges VALUES
('Helmsman',
    'Nice work logging your first sail! You are officially a helmsman now!'),
('Wake Maker',
    'Yowzers! Welcome to the 15 knot+ club ya speed demon skipper!'),
('Explorer',
    'It looks like home is where the helm is. Cheers to 10 days away from home port!'),
('Mooring Pro',
    'It takes a lot of skill to "thread that floating needle" but seems like you have mastered mooring with 10 nights on buoy!'),
('Anchormaster',
    'Hook, line and sinker, you have this anchoring thing down! 25 days on the hook for you!'),
('Traveler',
    'Who needs to fly when one can sail! You are an international sailor. À votre santé!'),
('Stormtrooper',
    'Just like the elite defenders of the Empire, here you are, our braving your own hydro-empire in windspeeds above 30kts. Nice work trooper! '),
('Club Alaska',
    'Home to the bears, glaciers, midnight sun and high adventure. Welcome to the Club Alaska Captain!'),
('Tropical Traveler',
    'Look at you with your suntan, tropical drink and southern latitude!'), 
('Aloha Award',
    'Ticking off over 2300 NM across the great blue Pacific makes you the rare recipient of the Aloha Award. Well done and Aloha sailor!'), 
('Tyee',
    'You made it to the Tyee Outstation, the friendliest dock in Pacific Northwest!'), 
-- TODO the sea is big and the world is not limited to the US
('Mediterranean Traveler',
    'You made it trought the Mediterranean!');
