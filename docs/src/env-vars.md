## Environment Variables

You need to configure PostgSail using environment variables. Copy the example file.
```
cp .env.example .env
```

## Environment Variables Documentation

This document describes all environment variables used in the PostgSail system, organized by category and usage context.

### Database Configuration

| Environment Variable | Example | Description |
|---------------------|---------|-------------|
| `POSTGRES_USER` | `postgres` | PostgreSQL superuser username for database administration |
| `POSTGRES_PASSWORD` | `changeme` | Password for the PostgreSQL superuser for database administration |
| `PGSAIL_AUTHENTICATOR_PASSWORD` | `generated_password` | Password for the PostgREST authenticator role |

### API Configuration

| Environment Variable | Example | Description |
|---------------------|---------|-------------|
| `PGRST_JWT_SECRET` | `generated_secret_min_32_chars` | JWT secret for PostgREST authentication (minimum 32 characters) |
| `PGSAIL_API_URL` | `http://localhost:3000` or `https://api.example.com` | Base URL for the PostgSail API endpoint, API entrypoint from the webapp |

### Frontend Configuration

| Environment Variable | Example | Description |
|---------------------|---------|-------------|
| `VITE_APP_TITLE` | `PostgSail` | Application title displayed in the frontend |
| `VITE_PGSAIL_URL` | `${PGSAIL_API_URL}` | API URL used by the Vue.js frontend, same as ${PGSAIL_API_URL} |
| `VITE_GRAFANA_URL` | `http://localhost:3001` or `https://grafana.example.com`  | Grafana dashboard URL for frontend integration |

### Grafana Configuration

| Environment Variable | Example | Description |
|---------------------|---------|-------------|
| `PGSAIL_GRAFANA_PASSWORD` | `admin_password` | Admin password for Grafana dashboard access |

### External Integrations

| Environment Variable | Example | Description |
|---------------------|---------|-------------|
| `PGSAIL_TELEGRAM_BOT_TOKEN` | `bot_token_from_botfather` | Telegram bot token for notifications |
| `PGSAIL_EMAIL_SERVER` | `smtp.example.com` | SMTP server for email notifications |
| `PGSAIL_EMAIL_USER` | `notifications@example.com` | Email username for SMTP authentication |
| `PGSAIL_EMAIL_PASS` | `email_password` | Email password for SMTP authentication |
| `PGSAIL_EMAIL_FROM` | `PostgSail <noreply@example.com>` | From address for outgoing emails |

### Push Notifications

| Environment Variable | Example | Description |
|---------------------|---------|-------------|
| `PGSAIL_PUSHOVER_APP_TOKEN` | `pushover_token` | Pushover application token for push notifications |
| `PGSAIL_PUSHOVER_APP_URL` | `https://pushover.net/subscribe/qwerty` | Pushover subscribe endpoint URL |

### Development Tools

| Environment Variable | Example | Description |
|---------------------|---------|-------------|
| `PGADMIN_DEFAULT_EMAIL` | `admin@example.com` | Default email for pgAdmin web interface |
| `PGADMIN_DEFAULT_PASSWORD` | `admin_password` | Default password for pgAdmin access |

### Additional Services

| Environment Variable | Example | Description |
|---------------------|---------|-------------|
| `PGSAIL_APP_URL` | `http://localhost:8080` or `http://www.example.com` | Main application URL |

Additional parameters are directly set in the [docker-compose.yml](https://github.com/xbgmsharp/postgsail/blob/main/docker-compose.yml)
