
#------------------------------------------------------------------------------
# ENV Settings
#------------------------------------------------------------------------------
echo "Set password and settings from environment variables"

PGSAIL_VERSION=`cat /docker-entrypoint-initdb.d/PGSAIL_VERSION`

psql -U ${POSTGRES_USER} signalk <<-END
-- Application settings default
INSERT INTO app_settings (name, value) VALUES
        ('app.jwt_secret', '${PGRST_JWT_SECRET}'),
        ('app.email_server', '${PGSAIL_EMAIL_SERVER}'),
        ('app.email_user', '${PGSAIL_EMAIL_USER}'),
        ('app.email_pass', '${PGSAIL_EMAIL_PASS}'),
        ('app.email_from', '${PGSAIL_EMAIL_FROM}'),
        ('app.pushover_app_token', '${PGSAIL_PUSHOVER_APP_TOKEN}'),
        ('app.pushover_app_url', '${PGSAIL_PUSHOVER_APP_URL}'),
        ('app.telegram_bot_token', '${PGSAIL_TELEGRAM_BOT_TOKEN}'),
        ('app.grafana_admin_uri', '${PGSAIL_GRAFANA_ADMIN_URI}'),
        ('app.keycloak_uri', '${PGSAIL_KEYCLOAK_URI}'),
        ('app.gis_url', '${PGSAIL_QGIS_URL}'),
        ('app.videos_url', '${PGSAIL_VIDEOS_URL}'),
        ('app.url', '${PGSAIL_APP_URL}'),
        ('app.version', '${PGSAIL_VERSION}');
-- Update comment with version
COMMENT ON DATABASE signalk IS 'PostgSail version ${PGSAIL_VERSION}';
-- Update password from env
ALTER ROLE authenticator WITH PASSWORD '${PGSAIL_AUTHENTICATOR_PASSWORD}';
ALTER ROLE grafana WITH PASSWORD '${PGSAIL_GRAFANA_PASSWORD}';
ALTER ROLE grafana_auth WITH PASSWORD '${PGSAIL_GRAFANA_AUTH_PASSWORD}';
ALTER ROLE qgis_role WITH PASSWORD '${PGSAIL_GRAFANA_AUTH_PASSWORD}';
ALTER ROLE maplapse_role WITH PASSWORD '${PGSAIL_GRAFANA_AUTH_PASSWORD}';
END

curl -s -XPOST -Hx-pgsail:${PGSAIL_VERSION} https://api.openplotter.cloud/rpc/telemetry_fn
