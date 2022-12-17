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
-- https://photon.komoot.io/reverse?lat=48.30587233333333&lon=14.3040525
-- https://docs.mapbox.com/playground/geocoding/?search_text=-3.1457869856990897,51.35921326434686&limit=1

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
('new_account',
    'Welcome',
    E'Hello __RECIPIENT__,\nCongratulations!\nYou successfully created an account.\nKeep in mind to register your vessel.\nHappy sailing!',
    'Welcome',
    E'Hi!\nYou successfully created an account\nKeep in mind to register your vessel.\nHappy sailing!'),
('new_vessel',
    'New vessel',
    E'Hi!\nHow are you?\n__BOAT__ is now linked to your account.',
    'New vessel',
    E'Hi!\nHow are you?\n__BOAT__ is now linked to your account.'),
('monitor_offline',
    'Vessel Offline',
    E'__BOAT__ has been offline for more than an hour\r\nFind more details at __APP_URL__/boats/\n',
    'Vessel Offline',
    E'__BOAT__ has been offline for more than an hour\r\nFind more details at __APP_URL__/boats/\n'),
('monitor_online',
    'Vessel Online',
    E'__BOAT__ just came online\nFind more details at __APP_URL__/boats/\n',
    'Vessel Online',
    E'__BOAT__ just came online\nFind more details at __APP_URL__/boats/\n'),
('new_badge',
    'New Badge!',
    E'Hello __RECIPIENT__,\nCongratulations! You have just unlocked a new badge: __BADGE_NAME__\nSee more details at __APP_URL__/badges\nHappy sailing!\nThe PostgSail Team',
    'New Badge!',
    E'Congratulations!\nYou have just unlocked a new badge: __BADGE_NAME__\nSee more details at __APP_URL__/badges\nHappy sailing!\nThe PostgSail Team'),
('pushover_valid',
    'Pushover integration',
    E'Hello __RECIPIENT__,\nCongratulations! You have just connect your account to Pushover.\n\nThe PostgSail Team',
    'Pushover integration!',
    E'Congratulations!\nYou have just connect your account to Pushover.\n\nThe PostgSail Team'),
('email_otp',
    'Email verification',
    E'Hello __RECIPIENT__,\nPlease active your account using the following code: __OTP_CODE__.\nThe code is valid 15 minutes.\nThe PostgSail Team',
    'Email verification',
    E'Congratulations!\nPlease validate your account. Check your email!'),
('email_valid',
    'Email verified',
    E'Hello __RECIPIENT__,\nCongratulations!\nYou successfully validate your account.\nThe PostgSail Team',
    'Email verified',
    E'Hi!\nYou successfully validate your account.\nHappy sailing!'),
('telegram_otp',
    'Telegram bot',
    E'Hello __RECIPIENT__,\nTo connect your account to a @postgsail_bot. Please type this verification code __OTP_CODE__ back to the bot.\nThe code is valid 15 minutes.\nThe PostgSail Team',
    'Telegram bot',
    E'Congratulations!\nTo connect your account to a @postgsail_bot. Check your email!'),
('telegram_valid',
    'Telegram bot',
    E'Hello __RECIPIENT__,\nCongratulations! You have just connect your account to your vessel, @postgsail_bot.\n\nThe PostgSail Team',
    'Telegram bot!',
    E'Congratulations!\nYou have just connect your account to your vessel, @postgsail_bot.\n\nHappy sailing!\nThe PostgSail Team');

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
    insert into process_queue (channel, payload, stored) values ('email_otp', NEW.email, now());
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
-- Badges description
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

---------------------------------------------------------------------------
-- aistypes description
--
CREATE TABLE IF NOT EXISTS aistypes(
    id NUMERIC UNIQUE,
    description TEXT
);
-- Description
COMMENT ON TABLE
    public.aistypes
    IS 'aistypes AIS Ship Types, https://api.vesselfinder.com/docs/ref-aistypes.html';

INSERT INTO aistypes VALUES
(0, 'Not available (default)'),
(20, 'Wing in ground (WIG), all ships of this type'),
(21, 'Wing in ground (WIG), Hazardous category A'),
(22, 'Wing in ground (WIG), Hazardous category B'),
(23, 'Wing in ground (WIG), Hazardous category C'),
(24, 'Wing in ground (WIG), Hazardous category D'),
(25, 'Wing in ground (WIG), Reserved for future use'),
(26, 'Wing in ground (WIG), Reserved for future use'),
(27, 'Wing in ground (WIG), Reserved for future use'),
(28, 'Wing in ground (WIG), Reserved for future use'),
(29, 'Wing in ground (WIG), Reserved for future use'),
(30, 'Fishing'),
(31, 'Towing'),
(32, 'Towing: length exceeds 200m or breadth exceeds 25m'),
(33, 'Dredging or underwater ops'),
(34, 'Diving ops'),
(35, 'Military ops'),
(36, 'Sailing'),
(37, 'Pleasure Craft'),
(38, 'Reserved'),
(39, 'Reserved'),
(40, 'High speed craft (HSC), all ships of this type'),
(41, 'High speed craft (HSC), Hazardous category A'),
(42, 'High speed craft (HSC), Hazardous category B'),
(43, 'High speed craft (HSC), Hazardous category C'),
(44, 'High speed craft (HSC), Hazardous category D'),
(45, 'High speed craft (HSC), Reserved for future use'),
(46, 'High speed craft (HSC), Reserved for future use'),
(47, 'High speed craft (HSC), Reserved for future use'),
(48, 'High speed craft (HSC), Reserved for future use'),
(49, 'High speed craft (HSC), No additional information'),
(50, 'Pilot Vessel'),
(51, 'Search and Rescue vessel'),
(52, 'Tug'),
(53, 'Port Tender'),
(54, 'Anti-pollution equipment'),
(55, 'Law Enforcement'),
(56, 'Spare - Local Vessel'),
(57, 'Spare - Local Vessel'),
(58, 'Medical Transport'),
(59, 'Noncombatant ship according to RR Resolution No. 18'),
(60, 'Passenger, all ships of this type'),
(61, 'Passenger, Hazardous category A'),
(62, 'Passenger, Hazardous category B'),
(63, 'Passenger, Hazardous category C'),
(64, 'Passenger, Hazardous category D'),
(65, 'Passenger, Reserved for future use'),
(66, 'Passenger, Reserved for future use'),
(67, 'Passenger, Reserved for future use'),
(68, 'Passenger, Reserved for future use'),
(69, 'Passenger, No additional information'),
(70, 'Cargo, all ships of this type'),
(71, 'Cargo, Hazardous category A'),
(72, 'Cargo, Hazardous category B'),
(73, 'Cargo, Hazardous category C'),
(74, 'Cargo, Hazardous category D'),
(75, 'Cargo, Reserved for future use'),
(76, 'Cargo, Reserved for future use'),
(77, 'Cargo, Reserved for future use'),
(78, 'Cargo, Reserved for future use'),
(79, 'Cargo, No additional information'),
(80, 'Tanker, all ships of this type'),
(81, 'Tanker, Hazardous category A'),
(82, 'Tanker, Hazardous category B'),
(83, 'Tanker, Hazardous category C'),
(84, 'Tanker, Hazardous category D'),
(85, 'Tanker, Reserved for future use'),
(86, 'Tanker, Reserved for future use'),
(87, 'Tanker, Reserved for future use'),
(88, 'Tanker, Reserved for future use'),
(89, 'Tanker, No additional information'),
(90, 'Other Type, all ships of this type'),
(91, 'Other Type, Hazardous category A'),
(92, 'Other Type, Hazardous category B'),
(93, 'Other Type, Hazardous category C'),
(94, 'Other Type, Hazardous category D'),
(95, 'Other Type, Reserved for future use'),
(96, 'Other Type, Reserved for future use'),
(97, 'Other Type, Reserved for future use'),
(98, 'Other Type, Reserved for future use'),
(99, 'Other Type, no additional information');

---------------------------------------------------------------------------
-- MMSI MID Codes
--
CREATE TABLE IF NOT EXISTS mid(
    country TEXT,
    id NUMERIC UNIQUE
);
-- Description
COMMENT ON TABLE
    public.mid
    IS 'MMSI MID Codes (Maritime Mobile Service Identity) Filtered by Flag of Registration, https://www.marinevesseltraffic.com/2013/11/mmsi-mid-codes-by-flag.html';

INSERT INTO mid VALUES
('Adelie Land', 501),
('Afghanistan', 401),
('Alaska', 303),
('Albania', 201),
('Algeria', 605),
('American Samoa', 559),
('Andorra', 202),
('Angola', 603),
('Anguilla', 301),
('Antigua and Barbuda', 304),
('Antigua and Barbuda', 305),
('Argentina', 701),
('Armenia', 216),
('Aruba', 307),
('Ascension Island', 608),
('Australia', 503),
('Austria', 203),
('Azerbaijan', 423),
('Azores', 204),
('Bahamas', 308),
('Bahamas', 309),
('Bahamas', 311),
('Bahrain', 408),
('Bangladesh', 405),
('Barbados', 314),
('Belarus', 206),
('Belgium', 205),
('Belize', 312),
('Benin', 610),
('Bermuda', 310),
('Bhutan', 410),
('Bolivia', 720),
('Bosnia and Herzegovina', 478),
('Botswana', 611),
('Brazil', 710),
('British Virgin Islands', 378),
('Brunei Darussalam', 508),
('Bulgaria', 207),
('Burkina Faso', 633),
('Burundi', 609),
('Cambodia', 514),
('Cambodia', 515),
('Cameroon', 613),
('Canada', 316),
('Cape Verde', 617),
('Cayman Islands', 319),
('Central African Republic', 612),
('Chad', 670),
('Chile', 725),
('China', 412),
('China', 413),
('China', 414),
('Christmas Island', 516),
('Cocos Islands', 523),
('Colombia', 730),
('Comoros', 616),
('Comoros', 620),
('Congo', 615),
('Cook Islands', 518),
('Costa Rica', 321),
(E'Côte d\'Ivoire', 619),
('Croatia', 238),
('Crozet Archipelago', 618),
('Cuba', 323),
('Cyprus', 209),
('Cyprus', 210),
('Cyprus', 212),
('Czech Republic', 270),
('Denmark', 219),
('Denmark', 220),
('Djibouti', 621),
('Dominica', 325),
('Dominican Republic', 327),
('DR Congo', 676),
('Ecuador', 735),
('Egypt', 622),
('El Salvador', 359),
('Equatorial Guinea', 631),
('Eritrea', 625),
('Estonia', 276),
('Ethiopia', 624),
('Falkland Islands', 740),
('Faroe Islands', 231),
('Fiji', 520),
('Finland', 230),
('France', 226),
('France', 227),
('France', 228),
('French Polynesia', 546),
('Gabonese Republic', 626),
('Gambia', 629),
('Georgia', 213),
('Germany', 211),
('Germany', 218),
('Ghana', 627),
('Gibraltar', 236),
('Greece', 237),
('Greece', 239),
('Greece', 240),
('Greece', 241),
('Greenland', 331),
('Grenada', 330),
('Guadeloupe', 329),
('Guatemala', 332),
('Guiana', 745),
('Guinea', 632),
('Guinea-Bissau', 630),
('Guyana', 750),
('Haiti', 336),
('Honduras', 334),
('Hong Kong', 477),
('Hungary', 243),
('Iceland', 251),
('India', 419),
('Indonesia', 525),
('Iran', 422),
('Iraq', 425),
('Ireland', 250),
('Israel', 428),
('Italy', 247),
('Jamaica', 339),
('Japan', 431),
('Japan', 432),
('Jordan', 438),
('Kazakhstan', 436),
('Kenya', 634),
('Kerguelen Islands', 635),
('Kiribati', 529),
('Kuwait', 447),
('Kyrgyzstan', 451),
('Lao', 531),
('Latvia', 275),
('Lebanon', 450),
('Lesotho', 644),
('Liberia', 636),
('Liberia', 637),
('Libya', 642),
('Liechtenstein', 252),
('Lithuania', 277),
('Luxembourg', 253),
('Macao', 453),
('Madagascar', 647),
('Madeira', 255),
('Makedonia', 274),
('Malawi', 655),
('Malaysia', 533),
('Maldives', 455),
('Mali', 649),
('Malta', 215),
('Malta', 229),
('Malta', 248),
('Malta', 249),
('Malta', 256),
('Marshall Islands', 538),
('Martinique', 347),
('Mauritania', 654),
('Mauritius', 645),
('Mexico', 345),
('Micronesia', 510),
('Moldova', 214),
('Monaco', 254),
('Mongolia', 457),
('Montenegro', 262),
('Montserrat', 348),
('Morocco', 242),
('Mozambique', 650),
('Myanmar', 506),
('Namibia', 659),
('Nauru', 544),
('Nepal', 459),
('Netherlands', 244),
('Netherlands', 245),
('Netherlands', 246),
('Netherlands Antilles', 306),
('New Caledonia', 540),
('New Zealand', 512),
('Nicaragua', 350),
('Niger', 656),
('Nigeria', 657),
('Niue', 542),
('North Korea', 445),
('Northern Mariana Islands', 536),
('Norway', 257),
('Norway', 258),
('Norway', 259),
('Oman', 461),
('Pakistan', 463),
('Palau', 511),
('Palestine', 443),
('Panama', 351),
('Panama', 352),
('Panama', 353),
('Panama', 354),
('Panama', 355),
('Panama', 356),
('Panama', 357),
('Panama', 370),
('Panama', 371),
('Panama', 372),
('Panama', 373),
('Papua New Guinea', 553),
('Paraguay', 755),
('Peru', 760),
('Philippines', 548),
('Pitcairn Island', 555),
('Poland', 261),
('Portugal', 263),
('Puerto Rico', 358),
('Qatar', 466),
('Reunion', 660),
('Romania', 264),
('Russian Federation', 273),
('Rwanda', 661),
('Saint Helena', 665),
('Saint Kitts and Nevis', 341),
('Saint Lucia', 343),
('Saint Paul and Amsterdam Islands', 607),
('Saint Pierre and Miquelon', 361),
('Samoa', 561),
('San Marino', 268),
('Sao Tome and Principe', 668),
('Saudi Arabia', 403),
('Senegal', 663),
('Serbia', 279),
('Seychelles', 664),
('Sierra Leone', 667),
('Singapore', 563),
('Singapore', 564),
('Singapore', 565),
('Singapore', 566),
('Slovakia', 267),
('Slovenia', 278),
('Solomon Islands', 557),
('Somalia', 666),
('South Africa', 601),
('South Korea', 440),
('South Korea', 441),
('South Sudan', 638),
('Spain', 224),
('Spain', 225),
('Sri Lanka', 417),
('St Vincent and the Grenadines', 375),
('St Vincent and the Grenadines', 376),
('St Vincent and the Grenadines', 377),
('Sudan', 662),
('Suriname', 765),
('Swaziland', 669),
('Sweden', 265),
('Sweden', 266),
('Switzerland', 269),
('Syria', 468),
('Taiwan', 416),
('Tajikistan', 472),
('Tanzania', 674),
('Tanzania', 677),
('Thailand', 567),
('Togolese', 671),
('Tonga', 570),
('Trinidad and Tobago', 362),
('Tunisia', 672),
('Turkey', 271),
('Turkmenistan', 434),
('Turks and Caicos Islands', 364),
('Tuvalu', 572),
('Uganda', 675),
('Ukraine', 272),
('United Arab Emirates', 470),
('United Kingdom', 232),
('United Kingdom', 233),
('United Kingdom', 234),
('United Kingdom', 235),
('Uruguay', 770),
('US Virgin Islands', 379),
('USA', 338),
('USA', 366),
('USA', 367),
('USA', 368),
('USA', 369),
('Uzbekistan', 437),
('Vanuatu', 576),
('Vanuatu', 577),
('Vatican City', 208),
('Venezuela', 775),
('Vietnam', 574),
('Wallis and Futuna Islands', 578),
('Yemen', 473),
('Yemen', 475),
('Zambia', 678),
('Zimbabwe', 679);
