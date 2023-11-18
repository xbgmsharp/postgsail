---------------------------------------------------------------------------
-- singalk db public schema
--

-- List current database
select current_database();

-- connect to the DB
\c signalk

CREATE SCHEMA IF NOT EXISTS public;

---------------------------------------------------------------------------
-- python reverse_geocode
--
-- https://github.com/CartoDB/labs-postgresql/blob/master/workshop/plpython.md
--
DROP FUNCTION IF EXISTS reverse_geocode_py_fn;
CREATE OR REPLACE FUNCTION reverse_geocode_py_fn(IN geocoder TEXT, IN lon NUMERIC, IN lat NUMERIC,
    OUT geo JSONB)
AS $reverse_geocode_py$
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
    url = rv[0]['url']

    # Validate input
    if not lon or not lat:
        plpy.notice('reverse_geocode_py_fn Parameters [{}] [{}]'.format(lon, lat))
        plpy.error('Error missing parameters')
        return None

    def georeverse(geocoder, lon, lat, zoom="18"):
	    # Make the request to the geocoder API
	    # https://operations.osmfoundation.org/policies/nominatim/
	    headers = {"Accept-Language": "en-US,en;q=0.5", "User-Agent": "PostgSail", "From": "xbgmsharp@gmail.com"}
	    payload = {"lon": lon, "lat": lat, "format": "jsonv2", "zoom": zoom, "accept-language": "en"}
	    # https://nominatim.org/release-docs/latest/api/Reverse/
	    r = requests.get(url, headers=headers, params=payload)

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
$reverse_geocode_py$ TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION 
    public.reverse_geocode_py_fn
    IS 'query reverse geo service to return location name using plpython3u';

---------------------------------------------------------------------------
-- python send email
--
-- https://www.programcreek.com/python/example/3684/email.utils.formatdate
DROP FUNCTION IF EXISTS send_email_py_fn;
CREATE OR REPLACE FUNCTION send_email_py_fn(IN email_type TEXT, IN _user JSONB, IN app JSONB) RETURNS void
AS $send_email_py$
    # Import smtplib for the actual sending function
    import smtplib
    
    # Import the email modules we need
    #from email.message import EmailMessage
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
    if 'logbook_name' in _user and _user['logbook_name']:
        email_content = email_content.replace('__LOGBOOK_NAME__', _user['logbook_name'])
    if 'logbook_link' in _user and _user['logbook_link']:
        email_content = email_content.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
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

    msg = MIMEText(email_content, 'plain', 'utf-8')
    msg["Subject"] = email_subject
    msg["From"] = email_from
    msg["To"] = email_to
    msg["Date"] = formatdate()
    msg["Message-ID"] = make_msgid()

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
$send_email_py$ TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.send_email_py_fn
    IS 'Send email notification using plpython3u';

---------------------------------------------------------------------------
-- python send pushover message
-- https://pushover.net/
DROP FUNCTION IF EXISTS send_pushover_py_fn;
CREATE OR REPLACE FUNCTION send_pushover_py_fn(IN message_type TEXT, IN _user JSONB, IN app JSONB) RETURNS void
AS $send_pushover_py$
    import requests

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

    # Replace fields using input jsonb obj
    if 'logbook_name' in _user and _user['logbook_name']:
        pushover_message = pushover_message.replace('__LOGBOOK_NAME__', _user['logbook_name'])
    if 'logbook_link' in _user and _user['logbook_link']:
        pushover_message = pushover_message.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'recipient' in _user and _user['recipient']:
        pushover_message = pushover_message.replace('__RECIPIENT__', _user['recipient'])
    if 'boat' in _user and _user['boat']:
        pushover_message = pushover_message.replace('__BOAT__', _user['boat'])
    if 'badge' in _user and _user['badge']:
        pushover_message = pushover_message.replace('__BADGE_NAME__', _user['badge'])

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

    # requests
    r = requests.post("https://api.pushover.net/1/messages.json", data = {
        "token": pushover_token,
        "user": pushover_user,
        "title": pushover_title,
        "message": pushover_message
    })

    #print(r.text)
    # Return ?? or None if not found
    #plpy.notice('Sent pushover successfully to [{}] [{}]'.format(r.text, r.status_code))
    if r.status_code == 200:
        plpy.notice('Sent pushover successfully to [{}] [{}] [{}]'.format(pushover_user, pushover_title, r.text))
    else:
        plpy.error('Failed to send pushover')
    return None
$send_pushover_py$ TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.send_pushover_py_fn
    IS 'Send pushover notification using plpython3u';

---------------------------------------------------------------------------
-- python send telegram message
-- https://core.telegram.org/
DROP FUNCTION IF EXISTS send_telegram_py_fn;
CREATE OR REPLACE FUNCTION send_telegram_py_fn(IN message_type TEXT, IN _user JSONB, IN app JSONB) RETURNS void
AS $send_telegram_py$
    """
    Send a message to a telegram user or group specified on chatId
    chat_id must be a number!
    """
    import requests
    import json

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

    # Replace fields using input jsonb obj
    if 'logbook_name' in _user and _user['logbook_name']:
        telegram_message = telegram_message.replace('__LOGBOOK_NAME__', _user['logbook_name'])
    if 'logbook_link' in _user and _user['logbook_link']:
        telegram_message = telegram_message.replace('__LOGBOOK_LINK__', str(_user['logbook_link']))
    if 'recipient' in _user and _user['recipient']:
        telegram_message = telegram_message.replace('__RECIPIENT__', _user['recipient'])
    if 'boat' in _user and _user['boat']:
        telegram_message = telegram_message.replace('__BOAT__', _user['boat'])
    if 'badge' in _user and _user['badge']:
        telegram_message = telegram_message.replace('__BADGE_NAME__', _user['badge'])

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

    # requests
    headers = {'Content-Type': 'application/json',
            'Proxy-Authorization': 'Basic base64'}
    data_dict = {'chat_id': telegram_chat_id,
                'text': telegram_message,
                'parse_mode': 'HTML',
                'disable_notification': False}
    data = json.dumps(data_dict)
    url = f'https://api.telegram.org/bot{telegram_token}/sendMessage'
    r = requests.post(url,
                        data=data,
                        headers=headers)
    #print(r.text)
    # Return something boolean?
    #plpy.notice('Sent telegram successfully to [{}] [{}]'.format(r.text, r.status_code))
    if r.status_code == 200:
        plpy.notice('Sent telegram successfully to [{}] [{}] [{}]'.format(telegram_chat_id, telegram_title, r.text))
    else:
        plpy.error('Failed to send telegram')
    return None
$send_telegram_py$ TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.send_telegram_py_fn
    IS 'Send a message to a telegram user or group specified on chatId using plpython3u';

---------------------------------------------------------------------------
-- python url encode
CREATE OR REPLACE FUNCTION urlencode_py_fn(uri text) RETURNS text
AS $urlencode_py$
    import urllib.parse
    return urllib.parse.quote(uri, safe="");
$urlencode_py$ LANGUAGE plpython3u IMMUTABLE STRICT;

---------------------------------------------------------------------------
-- python
-- https://ipapi.co/
DROP FUNCTION IF EXISTS reverse_geoip_py_fn;
CREATE OR REPLACE FUNCTION reverse_geoip_py_fn(IN _ip TEXT) RETURNS JSONB
AS $reverse_geoip_py$
    """
    Return ipapi.co ip details
    """
    import requests
    import json

    # requests
    url = f'https://ipapi.co/{_ip}/json/'
    r = requests.get(url)
    #print(r.text)
    #plpy.notice('IP [{}] [{}]'.format(_ip, r.status_code))
    if r.status_code == 200:
        #plpy.notice('Got [{}] [{}]'.format(r.text, r.status_code))
        return r.json();
    else:
        plpy.error('Failed to get ip details')
    return '{}'
$reverse_geoip_py$ LANGUAGE plpython3u;

-- Description
COMMENT ON FUNCTION
    public.reverse_geoip_py_fn
    IS 'Retrieve reverse geo IP location via ipapi.co using plpython3u';

---------------------------------------------------------------------------
-- python url escape
--
DROP FUNCTION IF EXISTS urlescape_py_fn;
CREATE OR REPLACE FUNCTION urlescape_py_fn(original text) RETURNS text LANGUAGE plpython3u AS $$
import urllib.parse
return urllib.parse.quote(original);
$$
IMMUTABLE STRICT;
-- Description
COMMENT ON FUNCTION
    public.urlescape_py_fn
    IS 'URL-encoding VARCHAR and TEXT values using plpython3u';

---------------------------------------------------------------------------
-- python geojson parser
--
--CREATE TYPE geometry_type AS ENUM ('LineString', 'Point');
DROP FUNCTION IF EXISTS geojson_py_fn;
CREATE OR REPLACE FUNCTION geojson_py_fn(IN original JSONB, IN geometry_type TEXT) RETURNS JSONB LANGUAGE plpython3u
AS $geojson_py$
    import json
    parsed = json.loads(original)
    output = []
    #plpy.notice(parsed)
    # [None, None]
    if None not in parsed:
        for idx, x in enumerate(parsed):
            #plpy.notice(idx, x)
            for feature in x:
                #plpy.notice(feature)
                if (feature['geometry']['type'] != geometry_type):
                    output.append(feature)
                #elif (feature['properties']['id']): TODO
                #    output.append(feature)
                #else:
                #    plpy.notice('ignoring')
    return json.dumps(output)
$geojson_py$ -- TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
IMMUTABLE STRICT;
-- Description
COMMENT ON FUNCTION
    public.geojson_py_fn
    IS 'Parse geojson using plpython3u (should be done in PGSQL)';

DROP FUNCTION IF EXISTS overpass_py_fn;
CREATE OR REPLACE FUNCTION overpass_py_fn(IN lon NUMERIC, IN lat NUMERIC,
    OUT geo JSONB) RETURNS JSONB
AS $overpass_py$
    """
    Return https://overpass-turbo.eu seamark details within 400m
    https://overpass-turbo.eu/s/1D91
    https://wiki.openstreetmap.org/wiki/Key:seamark:type
    """
    import requests
    import json
    import urllib.parse

    headers = {'User-Agent': 'PostgSail', 'From': 'xbgmsharp@gmail.com'}
    payload = """
    [out:json][timeout:20];
    nwr(around:400.0,{0},{1})->.all;
    (
        nwr.all["seamark:type"~"(mooring|harbour)"][~"^seamark:.*:category$"~"."];
        nwr.all["seamark:type"~"(anchorage|anchor_berth|berth)"];
        nwr.all["leisure"="marina"];
        nwr.all["natural"~"(bay|beach)"];
    );
    out tags qt;
    """.format(lat, lon)
    data = urllib.parse.quote(payload, safe="");
    url = f'https://overpass-api.de/api/interpreter?data={data}'.format(data)
    r = requests.get(url, headers)
    #print(r.text)
    #plpy.notice(url)
    plpy.notice('overpass-api coord lon[{}] lat[{}] [{}]'.format(lon, lat, r.status_code))
    if r.status_code == 200 and "elements" in r.json():
        r_dict = r.json()
        plpy.notice('overpass-api Got [{}]'.format(r_dict["elements"]))
        if r_dict["elements"]:
            if "tags" in r_dict["elements"][0] and r_dict["elements"][0]["tags"]:
                return r_dict["elements"][0]["tags"]; # return the first element
        return '{}'
    else:
        plpy.notice('overpass-api Failed to get overpass-api details')
    return '{}'
$overpass_py$ IMMUTABLE strict TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.overpass_py_fn
    IS 'Return https://overpass-turbo.eu seamark details within 300m using plpython3u';
