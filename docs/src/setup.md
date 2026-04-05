

## Architecture

Efficient, simple and scalable architecture.

```mermaid
flowchart TD
    %% User
    user([User])

    %% Frontend and Auth
    user -->|HTTPS| frontend[Frontend VueJS]
    user -->|HTTPS| grafana[Grafana]

    %% Web Server Layer
    frontend -->|HTTPS| postgrest[PostgREST]

    %% Database
    postgrest --> |SQL|postgres[(PostgreSQL / TimescaleDB / PostGIS / MobilityDB)]
    grafana --> |SQL|postgres

    %% External System
    postgres -->|HTTPS|telegram[Telegram API]
    postgres -->|HTTPS|pushover[Pushover API]
    postgres -->|SMTP|email[Email]
    postgres -->|HTTPS|overpass[Overpass API]
    postgres -->|HTTPS|nominatim[Nominatim API]

    %% Boat (External Client)
    vessel([Boat])
    vessel -->|HTTPS| postgrest

    %% MCP (External Client)
    mcp([AI-Agent])
    mcp -->|HTTPS| postgrest

    %% Telegram Bot (External Client)
    telegram_bot([Telegram Bot])
    telegram_bot -->|HTTPS| postgrest

    %% Groupings

    subgraph Clients
        user
        vessel
        mcp
        telegram_bot
    end

    subgraph PostgSail
        frontend
        grafana
        postgrest
        postgres
    end

    subgraph "Notification endpoint"
        telegram
        pushover
        email
    end

    subgraph "Data endpoint"
        overpass
        nominatim
    end
```

For more clarity and visibility the complete [Entity-Relationship Diagram (ERD)](postgsail.md) is export as Mermaid file.

## Using PostgSail
### On-premise (self-hosted)

This deployment needs the [docker application](https://www.docker.com/) to be installed and running. Check this [tutorial](https://www.docker.com/101-tutorial).

Docker run pre packaged application (aka images) which can be retrieved as sources (Dockerfile and resources) to build or already built from registries (private or public).

PostgSail depends heavily on [PostgreSQL](https://www.postgresql.org/). Check this [tutorial](https://www.postgresql.org/docs/current/tutorial.html).

#### pre-deploy configuration

To get these running, copy `.env.example` and rename to `.env` then set the value accordingly.

```bash
# cp .env.example .env
```

```bash
# nano .env
```

Notice, that `PGRST_JWT_SECRET` must be at least 32 characters long.

`$ cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 42 | head -n 1`

`PGSAIL_APP_URL` is the URL you connect to from your browser.

`PGSAIL_API_URL` is the URL where `PGSAIL_APP_URL` connect to.

`PGRST_DB_URI` is the URI where the `PGSAIL_API_URL` connect to.

For more details check the [Environment Variables](env-vars.md).

To summarize:
```mermaid
flowchart LR
    subgraph frontend
        direction TB
        A(PGSAIL_APP_URL)
        B(PGSAIL_API_URL)
    end
    subgraph backend
        direction TB
        B(PGSAIL_API_URL) -- SQL --> C(PGRST_DB_URI)
    end
    %% ^ These subgraphs are identical, except for the links to them:

    %% Link *to* subgraph1: subgraph1 direction is maintained

    User -- HTTP --> A
    User -- HTTP --> B
    %% Link *within* subgraph2:
    %% subgraph2 inherits the direction of the top-level graph (LR)

    Boat -- HTTP --> B
```

### Deploy

There are two compose files. You can update the default settings by editing `docker-compose.yml` and `docker-compose.dev.yml` to your need.

> [!NOTE]
> Most PostgSail images are **not available in a public registry** — they must be built from source. Only `api` (PostgREST) and `app` (Grafana) use official upstream images.

#### Step 0. Build the images

```bash
docker compose build
```

This builds `db`, `migrate`, `web`, and `telegram` from their upstream git repositories. The `web` build takes a few minutes as it compiles the Vue 3 frontend.

#### Step 1. Initialize database

First start the database and wait for it to be ready:

```bash
docker compose up db
```

#### Step 2. Run migrations

Run the database migrations (applies the schema, roles, grants, and seed data):

```bash
docker compose up migrate
```

The migrate service will run once and exit when complete.

#### Step 3. Start backend (db, api)

Then launch the full backend stack (db, api):

```bash
docker compose up -d db api
```

The API is accessible on port HTTP/3000.
The database is accessible on port TCP/5432.

You can connect to the database via a web GUI like [pgadmin](https://www.pgadmin.org/) or a client like [dbeaver](https://dbeaver.io/).
```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d pgadmin
```
Then connect to the web UI on port HTTP/5050.

#### Step 4. Start frontend (web)

Build and launch the web frontend:

```bash
docker compose build web
docker compose up -d web
```

The first step can take some time as it will first run a build to generate the static website based on your settings.

The frontend is a SPA (Single-Page Application). With SPA, the server provides the user with an empty HTML page and Javascript. The latter is where the magic happens. When the browser receives the HTML + Javascript, it loads the Javascript. Once loaded, the JS takes place and, through a set of operations in the DOM, renders the necessary components to the page. The routing is then handled by the browser itself, not hitting the server. 

The frontend should be accessible via port HTTP/8080.

Users are collaborating on two installation guide:
- [Self-hosted-installation-guide](https://github.com/xbgmsharp/postgsail/blob/main/docs/install_guide.md)
- [Self-hosted-installation-guide on AWS EC2](https://github.com/xbgmsharp/postgsail/blob/main/docs/Self%E2%80%90hosted-installation-guide%20on%20AWS.md)
- [Self-hosted-installation-guide](https://github.com/xbgmsharp/postgsail/blob/main/docs/Self%E2%80%90hosted-installation-guide.md)

### SQL Configuration

Check and update your postgsail settings via SQL in the table `app_settings`:

```sql
SELECT * FROM app_settings;
```

```sql
UPDATE app_settings
    SET
        value = 'new_value'
    WHERE name = 'app.email_server';
```

As it is all about SQL, [Read more](https://github.com/xbgmsharp/postgsail/blob/main/docs/ERD/README.md) about the database to configure your instance and explore your data.

### Ingest data

Next, to ingest data from signalk, you need to install [signalk-postgsail](https://github.com/xbgmsharp/signalk-postgsail) plugin on your signalk server instance.

Also, if you like, you can import saillogger data using the postgsail helpers, [postgsail-helpers](https://github.com/xbgmsharp/postgsail-helpers).

You might want to import your influxdb1 data as well, [outflux](https://github.com/timescale/outflux).
For InfluxDB 2.x and 3.x. You will need to enable the 1.x APIs to use them. Consult the InfluxDB documentation for more details.

Last, if you like, you can import the sample data from Signalk NMEA Plaka by running the tests.
If everything goes well all tests pass successfully and you should receive a few notifications by email or PushOver or Telegram.
[End-to-End (E2E) Testing.](https://github.com/xbgmsharp/postgsail/blob/main/tests/)

```bash
docker compose up tests
```

### API Documentation

The OpenAPI description output depends on the permissions of the role that is contained in the JWT role claim.

Other applications can also use the [PostgSAIL API](https://petstore.swagger.io/?url=https://raw.githubusercontent.com/xbgmsharp/postgsail/main/openapi.json).

API anonymous:

```
$ curl http://localhost:3000/
```

API user_role:

```
$ curl http://localhost:3000/ -H 'Authorization: Bearer my_token_from_login_or_signup_fn'
```

API vessel_role:

```
$ curl http://localhost:3000/ -H 'Authorization: Bearer my_token_from_register_vessel_fn'
```

#### API main workflow

Check the [End-to-End (E2E) test sample](https://github.com/xbgmsharp/postgsail/blob/main/tests/).

### Docker services

`docker compose` is used to start all services. The core services are:

| Service | Alias | Description |
|---------|-------|-------------|
| `db` | database | PostgreSQL with TimescaleDB, PostGIS, and MobilityDB extensions |
| `migrate` | — | One-shot Goose migration runner (schema, roles, seed data) |
| `api` | postgrest | PostgREST — turns the PostgreSQL `api` schema into a REST API |
| `app` | grafana | Grafana dashboards for monitoring and visualization |
| `web` | — | Vue 3 frontend (built from vuestic-postgsail) |
| `telegram` | — | Telegram bot service for notifications |

### Development services (docker-compose.dev.yml)

Additional services available with the dev compose file:

| Service | Port | Description |
|---------|------|-------------|
| `pgadmin` | 5050 | Web UI for managing PostgreSQL |
| `swagger` | 8181 | Swagger UI for browsing the PostgREST OpenAPI spec |
| `tests` | — | Mocha + SQL integration tests |

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d pgadmin swagger
```