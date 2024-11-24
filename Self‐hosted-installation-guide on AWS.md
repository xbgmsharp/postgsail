##Self AWS cloud hosted setup example

In this guide we install, setup and run a postgsail project on an AWS instance in the cloud.

##On AWS
Launch an instance on AWS EC2 with the following settings: 
+ Ubuntu
+ Instance type: t2.small
+ Create security group and open the following ports:443, 8080, 80, 3000, 5432, 22, 5050
+ Allow SSH traffic

##Connect to instance with SSH
+ Open an SSH client.
+ Locate your private key file. 
+ Run this command, if necessary, to ensure your key is not publicly viewable: 
```chmod 400 "yourname.pem"```
+ Connect to your instance using its Public DNS, Example: 
```ssh -i "yourname.pem" ubuntu@ec2-11-234-567-890.eu-west-1.compute.amazonaws.com```

##Install Postgsail 
+ Install docker
+ Git clone the postgsail repo:
```$ git clone https://github.com/xbgmsharp/postgsail.git```

##Edit environment variables
Copy the example.env file and edit the environment variables:
```cd postgsail```
```cp .env.example .env```
```nano .env```

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

***PGSAIL_APP_URL***
This is the URL to the APP on your instance on port 8080:
```
PGSAIL_APP_URL=http://localhost:8080
PGSAIL_API_URL=http://localhost:3000
```

***PGSAIL_API_URL***
This is the URL to your API on your instance on port 3000 eg:
```
PGSAIL_API_URL=http://ec2-11-234-567-890.eu-west-1.compute.amazonaws.com:3000
```

***PGSAIL_AUTHENTICATOR_PASSWORD***
This password is used as part of the database access configuration. It’s used as part of the access URI later on. (Put the same password in both lines.)

***PGSAIL_GRAFANA_PASSWORD***
This password is used for the grafana service

***PGSAIL_GRAFANA_AUTH_PASSWORD***
??This password is used for user authentication on grafana?

***PGSAIL_EMAIL_FROM***
***PGSAIL_EMAIL_SERVER***
Pgsail does not include a built in email service - only hooks to send email via an existing server.
You can install an email service on the ubuntu host or use a third party service like gmail. If you chose to use a local service, be aware that some email services will filter it as spam unless you’ve properly configured it.

***PGSAIL_APP_URL***
This is the full url (with domain name or IP) that you access PGSAIL via. Once nginx ssl proxy is added this may need to be updated. (Service restart required after changing?)

***PGSAIL_API_URL***
This is the API URL that’s used for the boat and user access. Once apache or nginx ssl proxy is added this may need to be updated. (same restart?)

***Other ENV variables***
```
PGSAIL_PUSHOVER_APP_TOKEN
PGSAIL_PUSHOVER_APP
PGSAIL_TELEGRAM_BOT_TOKEN
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
```




##Edit the docker-compose.yml file
Add all correct credentials to the yml file, example:

```
version: "3.9"

services:
  db:
    image: xbgmsharp/timescaledb-postgis
    container_name: db
    hostname: db
    restart: unless-stopped
    env_file: .env
    environment:
      - TIMESCALEDB_TELEMETRY=off
      - PGDATA=/var/lib/postgresql/data/pgdata
      - TZ=UTC
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=user
      - PGSAIL_AUTHENTICATOR_PASSWORD=password
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./initdb:/docker-entrypoint-initdb.d
    logging:
      options:
        max-size: 10m
    healthcheck:
      test: ["CMD-SHELL", "sh -c 'pg_isready -U ${POSTGRES_USER} -d signalk'"]
      interval: 60s
      timeout: 10s
      retries: 5
      start_period: 100s

  api:
    image: postgrest/postgrest
    container_name: api
    hostname: api
    restart: unless-stopped
    links:
      - "db:database"
    ports:
      - "3000:3000"
      - "3003:3003"
    env_file: .env
    environment:
      PGRST_DB_SCHEMA: api
      PGRST_DB_ANON_ROLE: api_anonymous
      PGRST_OPENAPI_SERVER_PROXY_URI: http://127.0.0.1:3000
      PGRST_DB_PRE_REQUEST: public.check_jwt
      PGRST_DB_POOL: 20
      PGRST_DB_POOL_MAX_IDLETIME: 60
      PGRST_DB_POOL_ACQUISITION_TIMEOUT: 20
      PGRST_DB_URI: postgres://user:password@db:5432/user
      PGRST_JWT_SECRET: ab2345678901cd2222222233333333331234567890
      PGRST_SERVER_TIMING_ENABLED: 1
      PGRST_DB_MAX_ROWS: 500
      PGRST_JWT_CACHE_MAX_LIFETIME: 3600
    depends_on:
      - db
    logging:
      options:
        max-size: 10m
    #healthcheck:
    #  test: ["CMD-SHELL", "sh -c 'curl --fail http://localhost:3003/live || exit 1'"]
    #  interval: 60s
    #  timeout: 10s
    #  retries: 5
    #  start_period: 100s

  app:
    image: grafana/grafana:latest
    container_name: app
    restart: unless-stopped
    links:
      - "db:database"
    volumes:
      - grafana-data:/var/lib/grafana
      - grafana-data:/var/log/grafana
      - ./grafana:/etc/grafana
    ports:
      - "3001:3000"
    env_file: .env
    environment:
      - GF_INSTALL_PLUGINS=pr0ps-trackmap-panel,fatcloud-windrose-panel
      - GF_SECURITY_ADMIN_PASSWORD=password
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SMTP_ENABLED=false
    depends_on:
      - db
    logging:
      options:
        max-size: 10m
    #healthcheck:
    #  test: ["CMD-SHELL", "sh -c 'curl --fail http://localhost:3000/healthz || exit 1'"]
    #  interval: 60s
    #  timeout: 10s
    #  retries: 5
    #  start_period: 100s

  web:
    image: vuestic-postgsail
    build:
      context: https://github.com/xbgmsharp/vuestic-postgsail.git#live
      dockerfile: Dockerfile
      args:
        - VITE_PGSAIL_URL=http://localhost:3000
        - VITE_APP_INCLUDE_DEMOS=false
        - VITE_APP_BUILD_VERSION=true
        - VITE_APP_TITLE=${VITE_APP_TITLE}
        - VITE_GRAFANA_URL=${VITE_GRAFANA_URL}
    hostname: web
    container_name: web
    restart: unless-stopped
    links:
      - "api:postgrest"
    ports:
      - 8080:8080
    env_file: .env
    environment:
      - VITE_PGSAIL_URL=http://localhost:3000
      - VITE_APP_INCLUDE_DEMOS=false
      - VITE_APP_BUILD_VERSION=true
      - VITE_APP_TITLE=${VITE_APP_TITLE}
      - VITE_GRAFANA_URL=${VITE_GRAFANA_URL}
    depends_on:
      - db
      - api
    logging:
      options:
        max-size: 10m

  pgadmin:
      image: dpage/pgadmin4:latest
      container_name: pgadmin
      restart: unless-stopped
      volumes:
        - data:/var/lib/pgadmin
        - ./pgadmin_servers.json:/servers.json:ro
      links:
        - "db:database"
      ports:
        - 5050:5050
      environment:
        - PGADMIN_DEFAULT_EMAIL=test@user.com
        - PGADMIN_DEFAULT_PASSWORD=password
        - PGADMIN_LISTEN_ADDRESS=0.0.0.0
        - PGADMIN_LISTEN_PORT=5050
        - PGADMIN_SERVER_JSON_FILE=/servers.json
        - PGADMIN_DISABLE_POSTFIX=true
      depends_on:
        - db
      logging:
        options:
          max-size: 10m



volumes:
  grafana-data: {}
  postgres-data: {}
  data: {}

```



##Run the project

Make sure your user has the right permission:
Add Your User to the docker Group:
```sudo usermod -aG docker ubuntu```
Restart Your Session:
```newgrp docker```

Startup the db, api and web
```docker-compose up```

Open browser and navigate to your PGSAIL_APP_URL, you should see the postgsail login screen now:
http://ec2-11-234-567-890.eu-west-1.compute.amazonaws.com::8080



