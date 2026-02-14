#!/bin/sh
set -e

echo "Waiting for database..."
until pg_isready -h db -U "$POSTGRES_USER"; do
  sleep 2
done

echo "Running baseline migrations..."
goose -dir /db/migrations postgres "$PGSAIL_DB_URI" up

echo "Running pg_cron migrations..."
GOOSE_TABLE=goose_db_version_cron \
  goose -dir /db/migrations_cron postgres "$PGSAIL_CRONDB_URI" up

echo "Running environment..."
/db/env/20-env-config.sh

echo "Database ready."
