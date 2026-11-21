# Upgrade

There's no automatic upgrade path for a self-hosted PostgSail yet. Upgrade in this order, and always take a backup first:

1. Stop the containers.
2. Back up your database.
3. Update the containers. See [Containers](upgrade-containers.md).
4. Update the PostgreSQL extensions, if new versions are available. See [PostgreSQL](upgrade-pg.md).
5. Run the database migrations.
6. Run any additional data migration the release needs.
7. Update the PostgSail plugin on your SignalK server.

For a complete walkthrough of a real upgrade, from version 0.7.2 to 0.9.3, see [PostgSail](upgrade-pgsail.md).
