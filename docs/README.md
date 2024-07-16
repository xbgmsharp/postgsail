

## Architecture

Efficient, simple and scalable architecture.

![Architecture overview](https://raw.githubusercontent.com/xbgmsharp/postgsail/main/PostgSail.png "Architecture overview")


For more clarity and visibility the complete [Entity-Relationship Diagram (ERD)](https://github.com/xbgmsharp/postgsail/blob/main/docs/ERD/README.md) is export as Mermaid, PNG and SVG file.

## Using PostgSail
### Development

A full-featured development environment.

#### With CodeSandbox

- Develop on [![CodeSandbox Ready-to-Code](https://img.shields.io/badge/CodeSandbox-Ready--to--Code-blue?logo=codesandbox)](https://codesandbox.io/p/github/xbgmsharp/postgsail/main)
  - or via [direct link](https://codesandbox.io/p/github/xbgmsharp/postgsail/main)

#### With DevPod

- [![Open in DevPod!](https://devpod.sh/assets/open-in-devpod.svg)](https://devpod.sh/open#https://github.com/xbgmsharp/postgsail/&workspace=postgsail&provider=docker&ide=openvscode)
  - or via [direct link](https://devpod.sh/open#https://github.com/xbgmsharp/postgsail&workspace=postgsail&provider=docker&ide=openvscode)

#### With Docker Dev Environments
- [Open in Docker dev-envs!](https://open.docker.com/dashboard/dev-envs?url=https://github.com/xbgmsharp/postgsail/)


### On-premise (self-hosted)

This kind of deployment needs the [docker application](https://www.docker.com/) to be installed and running. Check this [tutorial](https://www.docker.com/101-tutorial).

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

There is two compose files used. You can update the default settings by editing `docker-compose.yml` and `docker-compose.dev.yml` to your need.

Now let's initialize the database.

#### Step 1. Initialize database

First let's import the SQL schema, execute:

```bash
$ docker compose up db
```

#### Step 2. Start backend (db, api)

Then launch the full backend stack (db, api), execute:

```bash
$ docker compose up db api
```

The API should be accessible via port HTTP/3000.
The database should be accessible via port TCP/5432.

You can connect to the database via a web gui like [pgadmin](https://www.pgadmin.org/) or you can use a client [dbeaver](https://dbeaver.io/).
```bash
$ docker compose -f docker-compose.yml -f docker-compose.dev.yml pgadmin
```
Then connect to the web UI on port HTTP/5050.

#### Step 3. Start frontend (web)

Then launch the web frontend, execute:

```bash
$ docker compose up web
```
This step can take some time as it will first do a build to generate the static website based on your settings.

The frontend should be accessible via port HTTP/8080.

Users are collaborating on an installation guide, [Self-hosted-installation-guide](https://github.com/xbgmsharp/postgsail/wiki/Self-hosted-installation-guide)

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

```
$ docker-compose up tests
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

### Docker dependencies

`docker-compose` is used to start environment dependencies. Dependencies consist of 3 containers:

- `timescaledb-postgis` alias `db`, PostgreSQL with TimescaleDB extension along with the PostGIS extension.
- `postgrest` alias `api`, Standalone web server that turns your PostgreSQL database directly into a RESTful API.
- `grafana` alias `app`, visualize and monitor your data

### Optional docker images

- [pgAdmin](https://hub.docker.com/r/dpage/pgadmin4), web UI to monitor and manage multiple PostgreSQL
- [Swagger](https://hub.docker.com/r/swaggerapi/swagger-ui), web UI to visualize documentation from PostgREST

```
docker-compose -f docker-compose-optional.yml up
```