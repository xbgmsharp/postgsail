
#------------------------------------------------------------------------------
# ENV Settings
#------------------------------------------------------------------------------
echo "Set password and settings from environment variables"

PGSAIL_VERSION=`cat /initdb/PGSAIL_VERSION`

psql ${PGSAIL_DB_URI} signalk <<-END
BEGIN;
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
        ('app.url', '${PGSAIL_APP_URL}'),
        ('app.version', '${PGSAIL_VERSION}')
ON CONFLICT (name)
DO UPDATE SET value = EXCLUDED.value
WHERE app_settings.value IS DISTINCT FROM EXCLUDED.value;
-- Update comment with version
COMMENT ON DATABASE signalk IS 'PostgSail version ${PGSAIL_VERSION}';
-- Update password from env
ALTER ROLE authenticator WITH PASSWORD '${PGSAIL_AUTHENTICATOR_PASSWORD}';
ALTER ROLE grafana WITH PASSWORD '${PGSAIL_GRAFANA_PASSWORD}';
COMMIT;
END

curl -s -XPOST -Hx-pgsail:${PGSAIL_VERSION} https://api.openplotter.cloud/rpc/telemetry_fn
