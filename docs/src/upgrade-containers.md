# Updating Containers

Most PostgSail images are built from source and are not available in a public registry. To update to the latest version, rebuild the images from their upstream sources:

```bash
docker compose build --pull --no-cache
docker compose up -d
```

- `--pull` — fetches the latest base images before building
- `--no-cache` — forces a full rebuild (avoids stale cached layers)

The two services that use official upstream images (`api` and `app`) can be updated with:

```bash
docker compose pull api app
docker compose up -d api app
```
