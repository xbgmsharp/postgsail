
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
        ('app.pushover_token', '${PGSAIL_PUSHOVER_TOKEN}'),
        ('app.pushover_app', '_todo_'),
        ('app.version', '${PGSAIL_VERSION}');
-- Update comment with version
COMMENT ON DATABASE signalk IS 'version ${PGSAIL_VERSION}';
-- Update password from env
ALTER ROLE authenticator WITH PASSWORD '${PGSAIL_AUTHENTICATOR_PASSWORD}';
ALTER ROLE grafana WITH PASSWORD '${PGSAIL_GRAFANA_PASSWORD}';
END
