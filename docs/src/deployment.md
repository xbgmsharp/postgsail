# Deployment

PostgSail supports both cloud-hosted and self-hosted deployment options:

#### Cloud-based SaaS [iot.openplotter.cloud](https://iot.openplotter.cloud/)
- Managed PostgreSQL
- Managed infrastructure
- Automatic scaling and backup
- Free for single vessel use
- Multi-vessel commercial plans available
- Generate video(s) of trip(s)
- Generate image(s) of trip(s)
- AI assistant
- Image gallery support

#### Self-Hosted (Infrastructure you manage)
- Docker Compose orchestration
- Kubernetes orchestration
- Full control over data and configuration
- Requires Docker and basic Linux administration
- Requires PostgreSQL administration
- Custom integration capabilities

## Cloud-hosted PostgSail

Remove the hassle of running PostgSail yourself. Here you can skip the technical setup, the maintenance work and server costs by getting PostgSail on our reliable and secure PostgSail Cloud. Register and try for free at [iot.openplotter.cloud](https://iot.openplotter.cloud/).

PostgSail Cloud is Open Source and free for personal use with a single vessel. If wish to manage multiple boats contact us.

PostgSail is free to use, but is not free to make or host. The stability and accuracy of PostgSail depends on its volunteers and donations from its users. Please consider [sponsoring](https://github.com/sponsors/xbgmsharp) PostgSail.

## Infrastructure you manage

Self host postgSail where you want and how you want. There are no restrictions, you’re in full control. [Install Guide](setup.md)

PostgSail is free to use, but is not free to make or host. The stability and accuracy of PostgSail depends on its volunteers and donations from its users. Please consider [sponsoring](https://github.com/sponsors/xbgmsharp) PostgSail.

### Self-Hosting the PostgSail Control Plane

Self-hosting PostgSail means running your own instance of the PostgSail Control Plane.

When you self-host PostgSail, you’re deploying:
- **Database** — PostgreSQL with TimescaleDB (time-series metrics), PostGIS (spatial data), MobilityDB (vessel trajectories), and pg_cron (background jobs)
- **Migrations** — Goose migration runner that applies the schema, roles, grants, and seed data
- **API Server** — PostgREST, which auto-generates a REST API directly from the `api` schema
- **Frontend** — Vue 3 SPA for monitoring and visualizing logbook entries, stays, and moorages
- **Grafana** — Monitoring dashboards connected directly to the database
- **Telegram Bot** — Optional notification service for vessel alerts
