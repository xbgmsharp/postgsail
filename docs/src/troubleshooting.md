# Troubleshooting

This page covers problems with a self-hosted installation. For problems with a boat or the web app, see the user guide's [Troubleshooting](user/troubleshooting.md).

## Check the services

```bash
# All containers should be running
docker compose ps

# The API should answer
curl http://localhost:3000

# Read the logs of a service: db, migrate, api, app, telegram or web
docker compose logs api
docker compose logs db
```

If the database schema looks incomplete, run the migrations again:

```bash
docker compose up migrate
```

## A boat sends data, but nothing shows up

PostgSail drops metrics that fail its checks, and records each one with a reason. List the latest rejections:

```sql
SELECT vessel_id, rejected_at, rejection_reason
FROM public.metrics_rejected
ORDER BY rejected_at DESC
LIMIT 20;
```

Common reasons include a missing position, a position at 0,0, a timestamp in the future or older than the previous metric, an invalid status, and out-of-range speed or wind. See the user guide's [Troubleshooting](user/troubleshooting.md) for how to fix each one on the boat.

## Logs, stays or moorages aren't processed

Trips, stays, moorages and notifications go through a processing queue, run on a schedule by pg_cron. List the entries still waiting:

```sql
SELECT id, channel, ref_id, stored
FROM public.process_queue
WHERE processed IS NULL
ORDER BY stored;
```

If entries pile up, check the database logs with `docker compose logs db` for errors from the scheduled jobs.

## Emails or phone notifications don't arrive

Check the related environment variables in [Environment Variables](env-vars.md), then the setup pages for [Email (SMTP)](smtp.md), [Telegram](telegram.md) and [Pushover](pushover.md).

## Still stuck?

Ask on [Discord](https://discord.gg/uuZrwz4dCS) or open a [GitHub issue](https://github.com/xbgmsharp/postgsail/issues). Include your PostgSail version, the output of `docker compose ps` and the relevant logs. Don't post your tokens or passwords.
