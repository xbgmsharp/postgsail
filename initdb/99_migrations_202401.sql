---------------------------------------------------------------------------
-- Copyright 2021-2024 Francois Lacroix <xbgmsharp@gmail.com>
-- This file is part of PostgSail which is released under Apache License, Version 2.0 (the "License").
-- See file LICENSE or go to http://www.apache.org/licenses/LICENSE-2.0 for full license details.
--
-- Migration January 2024
--
-- List current database
select current_database();

-- connect to the DB
\c signalk

\echo 'Force timezone, just in case'
set timezone to 'UTC';

COMMENT ON FUNCTION
    public.cron_process_new_moorage_fn
    IS 'Deprecated, init by pg_cron to check for new moorage pending update, if so perform process_moorage_queue_fn';

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

CREATE OR REPLACE FUNCTION get_app_settings_fn(OUT app_settings jsonb)
    RETURNS jsonb
    AS $get_app_settings$
DECLARE
BEGIN
    SELECT
        jsonb_object_agg(name, value) INTO app_settings
    FROM
        public.app_settings
    WHERE
        name LIKE 'app.email%'
        OR name LIKE 'app.pushover%'
        OR name LIKE 'app.url'
        OR name LIKE 'app.telegram%'
        OR name LIKE 'app.grafana_admin_uri'
        OR name LIKE 'app.keycloak_uri';
END;
$get_app_settings$
LANGUAGE plpgsql;

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
            "requiredActions":["UPDATE_PROFILE", "UPDATE_PASSWORD"]
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

UPDATE public.email_templates
	SET pushover_message='Congratulations!
You unlocked Grafana dashboard.
See more details at https://app.openplotter.cloud
',email_content='Hello __RECIPIENT__,
Congratulations! You unlocked Grafana dashboard.
See more details at https://app.openplotter.cloud
Happy sailing!
Francois'
	WHERE "name"='grafana';

CREATE OR REPLACE FUNCTION public.cron_process_grafana_fn()
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    process_rec record;
    data_rec record;
    app_settings jsonb;
    user_settings jsonb;
BEGIN
    -- We run grafana provisioning only after the first received vessel metadata
    -- Check for new vessel metadata pending grafana provisioning
    RAISE NOTICE 'cron_process_grafana_fn';
    FOR process_rec in
        SELECT * from process_queue
            where channel = 'grafana' and processed is null
            order by stored asc
    LOOP
        RAISE NOTICE '-> cron_process_grafana_fn [%]', process_rec.payload;
        -- Gather url from app settings
        app_settings := get_app_settings_fn();
        -- Get vessel details base on metadata id
        SELECT * INTO data_rec
            FROM api.metadata m, auth.vessels v
            WHERE m.id = process_rec.payload::INTEGER
                AND m.vessel_id = v.vessel_id;
        -- as we got data from the vessel we can do the grafana provisioning.
        PERFORM grafana_py_fn(data_rec.name, data_rec.vessel_id, data_rec.owner_email, app_settings);
        -- Gather user settings
        user_settings := get_user_settings_from_vesselid_fn(data_rec.vessel_id::TEXT);
        RAISE DEBUG '-> DEBUG cron_process_grafana_fn get_user_settings_from_vesselid_fn [%]', user_settings;
        -- add user in keycloak
        PERFORM keycloak_auth_py_fn(data_rec.vessel_id, user_settings, app_settings);
        -- Send notification
        PERFORM send_notification_fn('grafana'::TEXT, user_settings::JSONB);
        -- update process_queue entry as processed
        UPDATE process_queue
            SET
                processed = NOW()
            WHERE id = process_rec.id;
        RAISE NOTICE '-> cron_process_grafana_fn updated process_queue table [%]', process_rec.id;
    END LOOP;
END;
$function$
;
COMMENT ON FUNCTION public.cron_process_grafana_fn() IS 'init by pg_cron to check for new vessel pending grafana provisioning, if so perform grafana_py_fn';

-- DROP FUNCTION public.grafana_py_fn(text, text, text, jsonb);

CREATE OR REPLACE FUNCTION public.grafana_py_fn(_v_name text, _v_id text, _u_email text, app jsonb)
 RETURNS void
 TRANSFORM FOR TYPE jsonb
 LANGUAGE plpython3u
AS $function$
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

	b_name = None
	if not _v_name:
		b_name = _v_id
	else:
		b_name = _v_name

	# add vessel org
	headers = {'User-Agent': 'PostgSail', 'From': 'xbgmsharp@gmail.com',
	'Accept': 'application/json', 'Content-Type': 'application/json'}
	path = 'api/orgs'
	url = f'{grafana_uri}/{path}'.format(grafana_uri,path)
	data_dict = {'name':b_name}
	data = json.dumps(data_dict)
	r = requests.post(url, data=data, headers=headers)
	#print(r.text)
	plpy.notice(r.json())
	if r.status_code == 200 and "orgId" in r.json():
		org_id = r.json()['orgId']
	else:
		plpy.error('Error grafana add vessel org %', r.json())
		return none

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
	data_source['secureJsonData']['password'] = 'mysecretpassword'
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
$function$
;

COMMENT ON FUNCTION public.grafana_py_fn(text, text, text, jsonb) IS 'Grafana Organization,User,data_source,dashboards provisioning via HTTP API using plpython3u';

UPDATE public.app_settings
	SET value='0.6.1'
	WHERE "name"='app.version';