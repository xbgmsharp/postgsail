# Running with Docker Compose

Docker Compose is the recommended way to run PostgSail locally or on a single server.

## Prerequisites

- [Docker](https://docs.docker.com/engine/install/) and the Compose plugin installed
- The repository cloned: `git clone https://github.com/xbgmsharp/postgsail`

> [!NOTE]
> Most PostgSail images are **not available in a public registry** and must be built locally.
> The only exceptions are `api` (PostgREST) and `app` (Grafana), which use official upstream images.

## Configuration

Copy the example environment file and edit it with your settings:

```bash
cd postgsail
cp .env.example .env
```

At minimum, set a strong `PGRST_JWT_SECRET` (at least 32 characters):

```bash
cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 42 | head -n 1
```

Paste the output into `.env` as the value for `PGRST_JWT_SECRET`.

## Building the Images

Before starting the stack, build all custom images:

```bash
docker compose build
```

This builds the following services from source:

| Service | Source |
|---------|--------|
| `db` | [postgsail-db](https://github.com/xbgmsharp/postgsail-db) |
| `migrate` | `./db/Dockerfile` |
| `web` | [vuestic-postgsail](https://github.com/xbgmsharp/vuestic-postgsail) |
| `telegram` | [postgsail-telegram-bot](https://github.com/xbgmsharp/postgsail-telegram-bot) |

The `web` build in particular takes time as it compiles the Vue 3 frontend with your environment variables baked in.

## Starting the Stack

The `migrate` service waits for `db` to be healthy automatically, so a single command starts everything in the correct order:

```bash
docker compose up -d
```

Or start services step by step:

```bash
# 1. Start the database (waits until healthy)
docker compose up -d db

# 2. Run migrations (exits when complete)
docker compose up migrate

# 3. Start the rest
docker compose up -d api app web telegram
```

The services will be available at:
- Web UI: [http://localhost:8080](http://localhost:8080)
- API: [http://localhost:3000](http://localhost:3000)
- Grafana: [http://localhost:3001](http://localhost:3001)
- Telegram bot: [http://localhost:3005](http://localhost:3005)

## Verifying the Installation

```bash
# Check running containers
docker compose ps

# Check API is responding
curl http://localhost:3000

# Check API logs
docker compose logs api

# Check database logs
docker compose logs db
```

## Development Stack

The development stack adds pgAdmin, Swagger UI, and hot-reload frontend support:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

Additional services:
- pgAdmin: [http://localhost:5050](http://localhost:5050)
- Swagger UI: [http://localhost:8181](http://localhost:8181)

## Updating

Rebuild images from the latest upstream sources and restart:

```bash
docker compose build --pull --no-cache
docker compose up -d
```

The `--pull` flag fetches the latest base images; `--no-cache` forces a full rebuild of each layer.

## Stopping

```bash
docker compose down
```

To also remove volumes (destructive — deletes all data):

```bash
docker compose down -v
```
