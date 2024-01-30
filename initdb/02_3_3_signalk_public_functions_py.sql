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
-- Description
COMMENT ON FUNCTION
    public.urlencode_py_fn
    IS 'python url encode using plpython3u';

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
        return r.json()
    else:
        plpy.error('Failed to get ip details')
    return {}
$reverse_geoip_py$ IMMUTABLE strict TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
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
    IS 'Parse geojson using plpython3u (should be done in PGSQL), deprecated';

DROP FUNCTION IF EXISTS overpass_py_fn;
CREATE OR REPLACE FUNCTION overpass_py_fn(IN lon NUMERIC, IN lat NUMERIC,
    OUT geo JSONB) RETURNS JSONB
AS $overpass_py$
    """
    Return https://overpass-turbo.eu seamark details within 400m
    https://overpass-turbo.eu/s/1EaG
    https://wiki.openstreetmap.org/wiki/Key:seamark:type
    """
    import requests
    import json
    import urllib.parse

    headers = {'User-Agent': 'PostgSail', 'From': 'xbgmsharp@gmail.com'}
    payload = """
    [out:json][timeout:20];
    is_in({0},{1})->.result_areas;
    (
      area.result_areas["seamark:type"~"(mooring|harbour)"][~"^seamark:.*:category$"~"."];
      area.result_areas["leisure"="marina"][~"name"~"."];
    );
    out tags;
    nwr(around:400.0,{0},{1})->.all;
    (
        nwr.all["seamark:type"~"(mooring|harbour)"][~"^seamark:.*:category$"~"."];
        nwr.all["seamark:type"~"(anchorage|anchor_berth|berth)"];
        nwr.all["leisure"="marina"];
        nwr.all["natural"~"(bay|beach)"];
    );
    out tags;
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
        return {}
    else:
        plpy.notice('overpass-api Failed to get overpass-api details')
    return {}
$overpass_py$ IMMUTABLE strict TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.overpass_py_fn
    IS 'Return https://overpass-turbo.eu seamark details within 400m using plpython3u';

---------------------------------------------------------------------------
-- Provision Grafana SQL
--
CREATE OR REPLACE FUNCTION grafana_py_fn(IN _v_name TEXT, IN _v_id TEXT,
    IN _u_email TEXT, IN app JSONB) RETURNS VOID
AS $grafana_py$
	"""
	https://grafana.com/docs/grafana/latest/developers/http_api/
	Create organization base on vessel name
	Create user base on user email
	Add user to organization
	Add data_source to organization
	Add dashboard to organization
    Update organization preferences
	"""
	import requests
	import json
	import re

	grafana_uri = None
	if 'app.grafana_admin_uri' in app and app['app.grafana_admin_uri']:
		grafana_uri = app['app.grafana_admin_uri']
	else:
		plpy.error('Error no grafana_admin_uri defined, check app settings')
		return None

	# add vessel org
	headers = {'User-Agent': 'PostgSail', 'From': 'xbgmsharp@gmail.com',
	'Accept': 'application/json', 'Content-Type': 'application/json'}
	path = 'api/orgs'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	data_dict = {'name':_v_name}
	data = json.dumps(data_dict)
	r = requests.post(url, data=data, headers=headers)
	#print(r.text)
	plpy.notice(r.json())
	if r.status_code == 200 and "orgId" in r.json():
		org_id = r.json()['orgId']
	else:
		plpy.error('Error grafana add vessel org %', r.json())
		return None

	# add user to vessel org
	path = 'api/admin/users'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	data_dict = {'orgId':org_id, 'email':_u_email, 'password':'asupersecretpassword'}
	data = json.dumps(data_dict)
	r = requests.post(url, data=data, headers=headers)
	#print(r.text)
	plpy.notice(r.json())
	if r.status_code == 200 and "id" in r.json():
		user_id = r.json()['id']
	else:
		plpy.error('Error grafana add user to vessel org')
		return

	# read data_source
	path = 'api/datasources/1'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	r = requests.get(url, headers=headers)
	#print(r.text)
	plpy.notice(r.json())
	data_source = r.json()
	data_source['id'] = 0
	data_source['orgId'] = org_id
	data_source['uid'] = "ds_" + _v_id
	data_source['name'] = "ds_" + _v_id
	data_source['secureJsonData'] = {}
	data_source['secureJsonData']['password'] = 'password'
	data_source['readOnly'] = True
	del data_source['secureJsonFields']

	# add data_source to vessel org
	path = 'api/datasources'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	data = json.dumps(data_source)
	headers['X-Grafana-Org-Id'] = str(org_id)
	r = requests.post(url, data=data, headers=headers)
	plpy.notice(r.json())
	del headers['X-Grafana-Org-Id']
	if r.status_code != 200 and "id" not in r.json():
		plpy.error('Error grafana add data_source to vessel org')
		return

	dashboards_tpl = [ 'pgsail_tpl_electrical', 'pgsail_tpl_logbook', 'pgsail_tpl_monitor', 'pgsail_tpl_rpi', 'pgsail_tpl_solar', 'pgsail_tpl_weather', 'pgsail_tpl_home']
	for dashboard in dashboards_tpl:
		# read dashboard template by uid
		path = 'api/dashboards/uid'
		url = f'{grafana_uri}/{path}/{dashboard}'.format(grafana_uri,path,dashboard)
		if 'X-Grafana-Org-Id' in headers:
			del headers['X-Grafana-Org-Id']
		r = requests.get(url, headers=headers)
		plpy.notice(r.json())
		if r.status_code != 200 and "id" not in r.json():
			plpy.error('Error grafana read dashboard template')
			return
		new_dashboard = r.json()
		del new_dashboard['meta']
		new_dashboard['dashboard']['version'] = 0
		new_dashboard['dashboard']['id'] = 0
		new_uid = re.sub(r'pgsail_tpl_(.*)', r'postgsail_\1', new_dashboard['dashboard']['uid'])
		new_dashboard['dashboard']['uid'] = f'{new_uid}_{_v_id}'.format(new_uid,_v_id)
		# add dashboard to vessel org
		path = 'api/dashboards/db'
		url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
		data = json.dumps(new_dashboard)
		new_data = data.replace('PCC52D03280B7034C', data_source['uid'])
		headers['X-Grafana-Org-Id'] = str(org_id)
		r = requests.post(url, data=new_data, headers=headers)
		plpy.notice(r.json())
		if r.status_code != 200 and "id" not in r.json():
			plpy.error('Error grafana add dashboard to vessel org')
			return

	# Update Org Prefs
	path = 'api/org/preferences'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	home_dashboard = {}
	home_dashboard['timezone'] = 'utc'
	home_dashboard['homeDashboardUID'] = f'postgsail_home_{_v_id}'.format(_v_id)
	data = json.dumps(home_dashboard)
	headers['X-Grafana-Org-Id'] = str(org_id)
	r = requests.patch(url, data=data, headers=headers)
	plpy.notice(r.json())
	if r.status_code != 200:
		plpy.error('Error grafana update org preferences')
		return

	plpy.notice('Done')
$grafana_py$ TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.grafana_py_fn
    IS 'Grafana Organization,User,data_source,dashboards provisioning via HTTP API using plpython3u';

-- https://stackoverflow.com/questions/65517230/how-to-set-user-attribute-value-in-keycloak-using-api
DROP FUNCTION IF EXISTS keycloak_py_fn;
CREATE OR REPLACE FUNCTION keycloak_py_fn(IN user_id TEXT, IN vessel_id TEXT,
    IN app JSONB) RETURNS JSONB
AS $keycloak_py$
    """
    Add vessel_id user attribute to keycloak user {user_id}
    """
    import requests
    import json
    import urllib.parse

    safe_uri = host = user = pwd = None
    if 'app.keycloak_uri' in app and app['app.keycloak_uri']:
        #safe_uri = urllib.parse.quote(app['app.keycloak_uri'], safe=':/?&=')
        _ = urllib.parse.urlparse(app['app.keycloak_uri'])
        host = _.netloc.split('@')[-1]
        user = _.netloc.split(':')[0]
        pwd = _.netloc.split(':')[1].split('@')[0]
    else:
        plpy.error('Error no keycloak_uri defined, check app settings')
        return None

    if not host or not user or not pwd:
        plpy.error('Error parsing keycloak_uri, check app settings')
        return None

    _headers = {'User-Agent': 'PostgSail', 'From': 'xbgmsharp@gmail.com'}
    _payload = {'client_id':'admin-cli','grant_type':'password','username':user,'password':pwd}
    url = f'{_.scheme}://{host}/realms/master/protocol/openid-connect/token'.format(_.scheme, host)
    r = requests.post(url, headers=_headers, data=_payload, timeout=(5, 60))
    #print(r.text)
    #plpy.notice(url)
    if r.status_code == 200 and 'access_token' in r.json():
        response = r.json()
        plpy.notice(response)
        _headers['Authorization'] = 'Bearer '+ response['access_token']
        _headers['Content-Type'] = 'application/json'
        _payload = { 'attributes': {'vessel_id': vessel_id} }
        url = f'{keycloak_uri}/admin/realms/postgsail/users/{user_id}'.format(keycloak_uri,user_id)
        #plpy.notice(url)
        #plpy.notice(_payload)
        data = json.dumps(_payload)
        r = requests.put(url, headers=_headers, data=data, timeout=(5, 60))
        if r.status_code != 204:
            plpy.notice("Error updating user: {status} [{text}]".format(
                status=r.status_code, text=r.text))
            return None
        else:
            plpy.notice("Updated user : {user} [{text}]".format(user=user_id, text=r.text))
    else:
        plpy.notice(f'Error getting admin access_token: {status} [{text}]'.format(
                status=r.status_code, text=r.text))
    return None
$keycloak_py$ strict TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.keycloak_py_fn
    IS 'Return set oauth user attribute into keycloak using plpython3u';

DROP FUNCTION IF EXISTS keycloak_auth_py_fn;
CREATE OR REPLACE FUNCTION keycloak_auth_py_fn(IN _v_id TEXT,
    IN _user JSONB, IN app JSONB) RETURNS JSONB
AS $keycloak_auth_py$
    """
    Addkeycloak user
    """
    import requests
    import json
    import urllib.parse

    safe_uri = host = user = pwd = None
    if 'app.keycloak_uri' in app and app['app.keycloak_uri']:
        #safe_uri = urllib.parse.quote(app['app.keycloak_uri'], safe=':/?&=')
        _ = urllib.parse.urlparse(app['app.keycloak_uri'])
        host = _.netloc.split('@')[-1]
        user = _.netloc.split(':')[0]
        pwd = _.netloc.split(':')[1].split('@')[0]
    else:
        plpy.error('Error no keycloak_uri defined, check app settings')
        return none

    if not host or not user or not pwd:
        plpy.error('Error parsing keycloak_uri, check app settings')
        return None

    if not 'email' in _user and _user['email']:
        plpy.error('Error parsing user email, check user settings')
        return none

    if not _v_id:
        plpy.error('Error parsing vessel_id')
        return none

    _headers = {'User-Agent': 'PostgSail', 'From': 'xbgmsharp@gmail.com'}
    _payload = {'client_id':'admin-cli','grant_type':'password','username':user,'password':pwd}
    url = f'{_.scheme}://{host}/realms/master/protocol/openid-connect/token'.format(_.scheme, host)
    r = requests.post(url, headers=_headers, data=_payload, timeout=(5, 60))
    #print(r.text)
    #plpy.notice(url)
    if r.status_code == 200 and 'access_token' in r.json():
        response = r.json()
        plpy.notice(response)
        _headers['Authorization'] = 'Bearer '+ response['access_token']
        _headers['Content-Type'] = 'application/json'
        url = f'{_.scheme}://{host}/admin/realms/postgsail/users'.format(_.scheme, host)
        _payload = {
            "enabled": "true",
            "email": _user['email'],
            "firstName": _user['recipient'],
            "attributes": {"vessel_id": _v_id},
            "emailVerified": True,
            "requiredActions":["UPDATE_PASSWORD"]
        }
        plpy.notice(_payload)
        data = json.dumps(_payload)
        r = requests.post(url, headers=_headers, data=data, timeout=(5, 60))
        if r.status_code != 201:
            #print("Error creating user: {status}".format(status=r.status_code))
            plpy.error(f'Error creating user: {user} {status}'.format(user=_payload['email'], status=r.status_code))
            return None
        else:
            #print("Created user : {u}]".format(u=_payload['email']))
            plpy.notice('Created user : {u} {t}, {l}'.format(u=_payload['email'], t=r.text, l=r.headers['location']))
            user_url = "{user_url}/execute-actions-email".format(user_url=r.headers['location'])
            _payload = ["UPDATE_PASSWORD"]
            plpy.notice(_payload)
            data = json.dumps(_payload)
            r = requests.put(user_url, headers=_headers, data=data, timeout=(5, 60))
            if r.status_code != 204:
              plpy.error('Error execute-actions-email: {u} {s}'.format(u=_user['email'], s=r.status_code))
            else:
              plpy.notice('execute-actions-email: {u} {s}'.format(u=_user['email'], s=r.status_code))
            return None
    else:
        plpy.error(f'Error getting admin access_token: {status}'.format(status=r.status_code))
    return None
$keycloak_auth_py$ strict TRANSFORM FOR TYPE jsonb LANGUAGE plpython3u;
-- Description
COMMENT ON FUNCTION
    public.keycloak_auth_py_fn
    IS 'Return set oauth user attribute into keycloak using plpython3u';
