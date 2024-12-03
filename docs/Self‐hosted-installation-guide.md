# Self hosted setup example environment:

Virtual machine with Ubuntu 22.04 LTS minimal server installation.

Install openssh, update and install docker-ce manually (ubuntu docker repo is lame)
The following ports are exposed to the internet either using a static public IP address or port forwarding via your favorite firewall platform. (not need by default docker will expose all ports to all IPs)
The base install uses ports 5432 (db) and 3000 (api) and 8080 (web).

We’ll add https using Apache or Nginx proxy once everything is tested. At that point you’ll want to open 443 or whatever other port you want to use for secure communication.

For docker-ce installation, this is a decent guide to installation:
https://www.digitalocean.com/community/tutorials/how-to-install-and-use-docker-on-ubuntu-20-04

Third party services and options:
Emails
For email notifications you may want to install a local email handler like postfix or use a third party service like gmail.

Pushover
Add more here

Telegram Bot
Add more here


```
$ git clone https://github.com/xbgmsharp/postgsail.git
cd postgsail
cp .env.example .env
nano .env
```

Login to your docker host once it’s setup.
Clone the repo to your user directory
Git clone https://github.com/xbgmsharp/postgsail.git
Copy the example file and edit the environment variables

The example has the following:
```
# POSTGRESQL ENV Settings
POSTGRES_USER=username
POSTGRES_PASSWORD=password
POSTGRES_DB=postgres
# PostgSail ENV Settings
PGSAIL_AUTHENTICATOR_PASSWORD=password
PGSAIL_GRAFANA_PASSWORD=password
PGSAIL_GRAFANA_AUTH_PASSWORD=password
# SMTP server settings
PGSAIL_EMAIL_FROM=root@localhost
PGSAIL_EMAIL_SERVER=localhost
#PGSAIL_EMAIL_USER= Comment if not use
#PGSAIL_EMAIL_PASS= Comment if not use
# Pushover settings
#PGSAIL_PUSHOVER_APP_TOKEN= Comment if not use
#PGSAIL_PUSHOVER_APP_URL= Comment if not use
# TELEGRAM BOT, ask BotFather
#PGSAIL_TELEGRAM_BOT_TOKEN= Comment if not use
# webapp entrypoint, typically the public DNS or IP
PGSAIL_APP_URL=http://localhost:8080
# API entrypoint from the webapp, typically the public DNS or IP
PGSAIL_API_URL=http://localhost:3000
# 
POSTGREST ENV Settings
PGRST_DB_URI=postgres://authenticator:${PGSAIL_AUTHENTICATOR_PASSWORD}@db:5432/signalk
# % cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 42 | head -n 1
PGRST_JWT_SECRET=_at_least_32__char__long__random
# Grafana ENV Settings
GF_SECURITY_ADMIN_PASSWORD=password
```

All of these need to be configured.

Step by step:

## POSTGRESQL ENV Settings

***POSTGRES_USER***
Come up with a unique username for the database user. This will be used in the docker image when it’s started up. Nothing beyond creating a unique username and password is required here.
This environment variable is used in conjunction with `POSTGRES_PASSWORD` to set a user and its password. This variable will create the specified user with superuser power and a database with the same name.

https://github.com/docker-library/docs/blob/master/postgres/README.md

***POSTGRES_PASSWORD***
This should be a good password. It will be used for the postgres user above. Again this is used in the docker image.
This environment variable is required for you to use the PostgreSQL image. It must not be empty or undefined. This environment variable sets the superuser password for PostgreSQL. The default superuser is defined by the POSTGRES_USER environment variable.

***POSTGRES_DB***
This is the name of the database within postgres. Give it a unique name if you like. The schema will be loaded into this database and all data will be stored within it. Since this is used inside the docker image the name really doesn’t matter. If you plan to run additional databases within the image, then you might care.
This environment variable can be used to define a different name for the default database that is created when the image is first started. If it is not specified, then the value of `POSTGRES_USER` will be used.


```
# PostgSail ENV Settings
PGSAIL_AUTHENTICATOR_PASSWORD=password
PGSAIL_GRAFANA_PASSWORD=password
PGSAIL_GRAFANA_AUTH_PASSWORD=password
PGSAIL_EMAIL_FROM=root@localhost
PGSAIL_EMAIL_SERVER=localhost
#PGSAIL_EMAIL_USER= Comment if not use
#PGSAIL_EMAIL_PASS= Comment if not use
#PGSAIL_PUSHOVER_APP_TOKEN= Comment if not use
#PGSAIL_PUSHOVER_APP_URL= Comment if not use
#PGSAIL_TELEGRAM_BOT_TOKEN= Comment if not use
PGSAIL_APP_URL=http://localhost:8080
PGSAIL_API_URL=http://localhost:3000
```

PGSAIL_AUTHENTICATOR_PASSWORD
This password is used as part of the database access configuration. It’s used as part of the access URI later on. (Put the same password in both lines.)

PGSAIL_GRAFANA_PASSWORD
This password is used for the grafana service

PGSAIL_GRAFANA_AUTH_PASSWORD
??This password is used for user authentication on grafana?

PGSAIL_EMAIL_FROM
PGSAIL_EMAIL_SERVER
Pgsail does not include a built in email service - only hooks to send email via an existing server.
You can install an email service on the ubuntu host or use a third party service like gmail. If you chose to use a local service, be aware that some email services will filter it as spam unless you’ve properly configured it.

PGSAIL_PUSHOVER_APP_TOKEN
PGSAIL_PUSHOVER_APP
PGSAIL_TELEGRAM_BOT_TOKEN

Add more info here
PGSAIL_APP_URL
This is the full url (with domain name or IP) that you access PGSAIL via. Once nginx ssl proxy is added this may need to be updated. (Service restart required after changing?)


PGSAIL_API_URL
This is the API URL that’s used for the boat and user access. Once apache or nginx ssl proxy is added this may need to be updated. (same restart?)

Network configuration example:
It is a docker question but in general no special network config should be need, docker created and assign one automatically. all images will be bind to all IPs on the host.
The volume can be on disk or should be a docker volume prefer.
```
# docker compose -f docker-compose.yml -f docker-compose.dev.yml ps -a
NAME       IMAGE                              COMMAND                                                                  SERVICE    CREATED        STATUS                  PORTS
api        postgrest/postgrest                "/bin/postgrest"                                                         api        2 months ago   Up 2 months             0.0.0.0:3000->3000/tcp, :::3000->3000/tcp, 0.0.0.0:3003->3003/tcp, :::3003->3003/tcp
app        grafana/grafana:latest             "/run.sh"                                                                app        3 months ago   Up 12 days              0.0.0.0:3001->3000/tcp, :::3001->3000/tcp
db         xbgmsharp/timescaledb-postgis      "docker-entrypoint.sh postgres"                                          db         2 months ago   Up 2 months (healthy)   0.0.0.0:5432->5432/tcp, :::5432->5432/tcp
```
All services (db,api,web) will be accessible via localhost and others IPs, hence the default configuration.

```bash
# telnet localhost 5432
```
and 
```bash
# curl  localhost:3000
```

```bash
# docker network ls
NETWORK ID     NAME                DRIVER    SCOPE
...
14f30223ebf2   postgsail_default   bridge    local
```

Volumes:
```bash
% docker volume ls    
DRIVER    VOLUME NAME
local     postgsail_grafana-data
local     postgsail_postgres-data
```
