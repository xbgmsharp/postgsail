# PostgSail

Effortless cloud based solution for storing and sharing your SignalK data. Allow you to effortlessly log your sails and monitor your boat with historical data.

[![release](https://img.shields.io/github/release/xbgmsharp/postgsail?include_prereleases=&sort=semver&color=blue)](https://github.com/xbgmsharp/postgsail/releases/latest)
[![License](https://img.shields.io/badge/License-MIT-blue)](#license)
[![issues - postgsail](https://img.shields.io/github/issues/xbgmsharp/postgsail)](https://github.com/xbgmsharp/postgsail/issues)

[![Test services db, api](https://github.com/xbgmsharp/postgsail/actions/workflows/db-test.yml/badge.svg)](https://github.com/xbgmsharp/postgsail/actions/workflows/db-test.yml)
[![Test services db, api, web](https://github.com/xbgmsharp/postgsail/actions/workflows/frontend-test.yml/badge.svg)](https://github.com/xbgmsharp/postgsail/actions/workflows/frontend-test.yml)
[![Test services db, grafana](https://github.com/xbgmsharp/postgsail/actions/workflows/grafana-test.yml/badge.svg)](https://github.com/xbgmsharp/postgsail/actions/workflows/grafana-test.yml)

signalk-postgsail:
[![GitHub Release](https://img.shields.io/github/release/xbgmsharp/signalk-postgsail.svg)](https://github.com/xbgmsharp/signalk-postgsail/releases/latest)

postgsail-frontend:
[![GitHub Release](https://img.shields.io/github/release/xbgmsharp/vuestic-postgsail.svg)](https://github.com/xbgmsharp/vuestic-postgsail/releases/latest)

postgsail-telegram-bot:
[![GitHub Release](https://img.shields.io/github/release/xbgmsharp/postgsail-telegram-bot.svg)](https://github.com/xbgmsharp/postgsail-telegram-bot/releases/latest)

## Features

- Automatically log your voyages without manually starting or stopping a trip.
- Automatically capture the details of your voyages (boat speed, heading, wind speed, etc).
- Timelapse video your trips, with or without time control.
- Add custom notes to your logs.
- Export to CSV, GPX, GeoJSON, KML and download your logs.
- Aggregate your trip statistics: Longest voyage, time spent at anchorages, home ports etc.
- See your moorages on a global map, with incoming and outgoing voyages from each trip.
- Monitor your boat (position, depth, wind, temperature, battery charge status, etc.) remotely.
- History: view trends.
- Alert monitoring: get notification on low voltage or low fuel remotely.
- Notification via email or PushOver, Telegram.
- Offline mode.
- Low Bandwidth mode.
- Awesome statistics and graphs.
- Anything missing? just ask!

## Context

It is all about SQL, object-relational, time-series, spatial databases with a bit of python.

PostgSail is an open-source alternative to traditional vessel data management.
It is based on a well known open-source technology stack, Signalk, PostgreSQL, TimescaleDB, PostGIS, PostgREST. It does perfectly integrate with standard monitoring tool stack like Grafana.

To understand the why and how, you might want to read [Why.md](https://github.com/xbgmsharp/postgsail/tree/main/Why.md)

## Architecture
A simple scalable architecture:

![Architecture overview](https://raw.githubusercontent.com/xbgmsharp/postgsail/main/PostgSail.png "Architecture overview")

For more clarity and visibility the complete [Entity-Relationship Diagram (ERD)](https://github.com/xbgmsharp/postgsail/tree/main/ERD/README.md) is export as PNG and SVG file.

## Cloud

If you prefer not to install or administer your instance of PostgSail, hosted versions of PostgSail are available in the cloud of your choice.

### The cloud advantage.

Hosted and fully–managed options for PostgSail, designed for all your deployment and business needs. Register and try for free at https://iot.openplotter.cloud/.

## Using PostgSail

A full-featured development environment.

#### With CodeSandbox

- Develop on [![CodeSandbox Ready-to-Code](https://img.shields.io/badge/CodeSandbox-Ready--to--Code-blue?logo=codesandbox)](https://codesandbox.io/p/github/xbgmsharp/postgsail/main)
  - or via [direct link](https://codesandbox.io/p/github/xbgmsharp/postgsail/main)

#### With DevPod

- [![Open in DevPod!](https://devpod.sh/assets/open-in-devpod.svg)](https://devpod.sh/open#https://github.com/xbgmsharp/postgsail/&workspace=postgsail&provider=docker&ide=openvscode)
  - or via [direct link](https://devpod.sh/open#https://github.com/xbgmsharp/postgsail&workspace=postgsail&provider=docker&ide=openvscode)

#### With Docker Dev Environments
- [Open in Docker dev-envs!](https://open.docker.com/dashboard/dev-envs?url=https://github.com/xbgmsharp/postgsail/)

### pre-deploy configuration

To get these running, copy `.env.example` and rename to `.env` then set the value accordingly.

```bash
# cp .env.example .env
```

Notice, that `PGRST_JWT_SECRET` must be at least 32 characters long.

`$ head /dev/urandom | tr -dc A-Za-z0-9 | head -c 42 ; echo ''`

```bash
# nano .env
```

### Deploy

By default there is no network set and all data are store in a docker volume.
You can update the default settings by editing `docker-compose.yml` and `docker-compose.dev.yml` to your need.

First let's initialize the database.

#### Step 1. Initialize database

First let's import the SQL schema, execute:

```bash
$ docker-compose up db
```

#### Step 2. Start backend (db, api)

Then launch the full stack (db, api) backend, execute:

```bash
$ docker-compose up db api
```

The API should be accessible via port HTTP/3000.
The database should be accessible via port TCP/5432.

You can connect to the database via a web gui like [pgadmin](https://www.pgadmin.org/) or you can use a client [dbeaver](https://dbeaver.io/).

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

### Software reference

Out of the box iot platform using docker with the following software:

- [Signal K server, a Free and Open Source universal marine data exchange format](https://signalk.org)
- [PostgreSQL, open source object-relational database system](https://postgresql.org)
- [TimescaleDB, Time-series data extends PostgreSQL](https://www.timescale.com)
- [PostGIS, a spatial database extender for PostgreSQL object-relational database.](https://postgis.net/)
- [Grafana, open observability platform | Grafana Labs](https://grafana.com)

### Support

To get support, please create new [issue](https://github.com/xbgmsharp/postgsail/issues).

There is more likely security flows and bugs.

### Contribution

I'm happy to accept Pull Requests!
Feel free to contribute.

### License

This script is free software, Apache License Version 2.0.
