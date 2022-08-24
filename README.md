# PostgSail
Effortless cloud based solution for storing and sharing your SignalK data. Allow to effortlessly log your sails and monitor your boat. 

### Context
It is all about SQL, object-relational, time-series, spatial database with a bit python.

### Features
- Automatically log your voyages without manually starting or stopping a trip.
- Automatically capture the details of your voyages (boat speed, heading, wind speed, etc).
- Timelapse video your trips!
- Add custom notes to your logs.
- Export to CSV or GPX and download your logs.
- Aggregate your trip statistics: Longest voyage, time spent at anchorages, home ports etc.
- See your moorages on a global map, with incoming and outgoing voyages from each trip.
- Monitor your boat (position, depth, wind, temperature, battery charge status, etc.) remotely.
- History: view trends.
- Alert monitoring: get notification on low voltage or low fuel remotely.
- Notification via email or PushOver.

### Cloud
The cloud advantage.

Hosted and fully–managed options for PostgSail, designed for all your deployment and business needs. Register and try for free at https://iot.openplotter.cloud/.

### pre-deploy configuration

To get these running, copy `.env.example` and rename to `.env` then set the value accordinly.

Notice, that `PGRST_JWT_SECRET` must be at least 32 characters long.

`$ head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32 ; echo ''`

### Deploy
By default there is no network set and the postgresql data are store in a docker volume.
You can update the default settings by editing `docker-compose.yml` to your need.
Then simply excecute:
```
$ docker-compose up
```

### PostgSail Configuration

Check and update your postgsail settings via SQL in the table `app_settings`:

```
select * from app_settings;
```

```
UPDATE app_settings
    SET
        value = 'new_value'
    WHERE name = 'app.email_server';
```

### Ingest data
Next, to ingest data from signalk, you need to install [signalk-postgsail](https://github.com/xbgmsharp/signalk-postgsail) plugin on your signalk server instance.

Also, if you like, you can import saillogger data using the postgsail helpers, [postgsail-helpers](https://github.com/xbgmsharp/postgsail-helpers).

You might want to import your influxdb1 data as weel, [outflux](https://github.com/timescale/outflux).
Any taker on influxdb2 to PostgSail? It is definitly possible.

Last, if you like, you can import the sample data from Signalk NMEA Plaka by running the tests.
If everything goes well all tests pass sucessfully and you should recieve a few notifications by email or PushOver.
```
$ docker-compose up tests
```

### API Documentation
The OpenAPI description output depends on the permissions of the role that is contained in the JWT role claim.

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

Check the [unit test sample](https://github.com/xbgmsharp/PostgSail/blob/main/tests/index.js).

### Docker dependencies

`docker-compose` is used to start environment dependencies. Dependencies consist of 2 containers:

- `timescaledb-postgis` alias `db`, PostgreSQL with TimescaleDB extension along with the PostGIS extension.
- `postgrest` alias `api`, Standalone web server that turns your PostgreSQL database directly into a RESTful API.

### Optional docker images
- [Grafana](https://hub.docker.com/r/grafana/grafana), visualize and monitor your data
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

To get support, please create new [issue](https://github.com/xbgmsharp/PostgSail/issues).

There is more likely security flows and bugs.

### Contribution

I'm happy to accept Pull Requests!
Feel free to contribute.

### License

This script is free software, Apache License Version 2.0.
