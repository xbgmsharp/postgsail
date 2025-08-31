# Self hosted update guide

In this guide we are updating a self hosted installation version 0.7.2 to version 0.9.3. When updating from or to other versions principle remain the same.

The installation we are upgrading was installed in April 2024 using the installation instructions found on the pgsail github site. Platform is an Ubuntu 22.04 Virtual Machine.
Before the upgrade, around 120 trips were logged. Needless to say we don't want to loose our data.

Unfortunately, there is no automatic update path available, this may change but for now we had to follow the general update instuctions.

## General update instructions

- Make a backup
- Update the containers.
- Update possible extensions.
- Run database migrations.
- Additional data migration.
- Update SignalK client.

## Let's go

### Tools used

In addition to the tools that are already installed as part of Unbuntu and PostgSail, I used DBeaver to examine the database from my Windows desktop.

<https://dbeaver.io/download/>

### Make a backup

Start by making a backup of the database, the docker-compose.yml and .env files. Note that in my case the database was stored in a host folder, later versions are using a docker volume. To copy the database it neccesary the containers are stopped.

```bash
cd postgsail
mkdir backup
docker compose stop
cp .env docker-compose.yml backup/
docker compose cp -a db:/var/lib/postgresql/data backup/db-data
```

### Update the containers

Make a note of the last migration in the initdb folder, in my case this was 99_migrations_202404.sql. Because I used git clone, the migration file was a bit inbetween 0.7.1 and 0.7.2, therefore I decided 99_migrations_202404.sql was the first migration to run.

Remove the containers:

```bash
docker compose down
```

Get the latest PostgSail from github, we checkout a specific tag to ensure we have a stable release version. If you installed it from a binary release, just update from the latest binary release.

```bash
git pull remote main
git fetch --all --tags
git checkout tags/v0.9.3
```

```text
Note: switching to 'tags/v0.9.3'.

You are in 'detached HEAD' state. You can look around, make experimental
changes and commit them, and you can discard any commits you make in this
state without impacting any branches by switching back to a branch.

If you want to create a new branch to retain commits you create, you may
do so (now or later) by using -c with the switch command. Example:

  git switch -c <new-branch-name>

Or undo this operation with:

  git switch -

Turn off this advice by setting config variable advice.detachedHead to false

HEAD is now at 12e4baf Release PostgSail 0.9.3
```

**Ensure new docker-compose.yml file matches your database folder or volume setting, adjust as needed.**

Get the latest containers.

```bash
docker compose pull
```

### Update possible extentions

Start database container.

```bash
docker compose up -d db
```

Excec psql shell in databse container.

```bash
docker compose exec db sh
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB"
\c signalk;
```

Check extensions which can be updated, be sure to run from the signalk database:

```sql
SELECT name, default_version, installed_version FROM pg_available_extensions where default_version <> installed_version;
```

The postgis extention can be upgraded with this SQL query:

```sql
SELECT postgis_extensions_upgrade();
```

Updating the timescaledb requires running from a new session, use following commands (note the -X options, that is neccesary):

```bash
docker compose exec db sh
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -X
```

Then run following SQL commands from the psql shell:

```sql
ALTER EXTENSION timescaledb UPDATE;
CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit;
ALTER EXTENSION timescaledb_toolkit UPDATE;
```

For others, to be checked. In my case, the postgis extension was essential.

### Run datbabase migrations

Then run the migrations, adjust start and end for first and last migration file to execute.

```bash
start=202404; end=202507; for f in $(ls ./docker-entrypoint-initdb.d/99_migrations_*.sql | sort); do s=$(basename "$f" | sed -E 's/^99_migrations_([0-9]{6})\.sql$/\1/'); if [[ "$s" < "$start" || "$s" > "$end" ]]; then continue; fi; echo "Running $f"; psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < "$f"; done
```

Or line by line

```bash
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < ./docker-entrypoint-initdb.d/99_migrations_202404.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < ./docker-entrypoint-initdb.d/99_migrations_202405.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < ./docker-entrypoint-initdb.d/99_migrations_202406.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < ./docker-entrypoint-initdb.d/99_migrations_202407.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < ./docker-entrypoint-initdb.d/99_migrations_202408.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < ./docker-entrypoint-initdb.d/99_migrations_202409.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < ./docker-entrypoint-initdb.d/99_migrations_202410.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < ./docker-entrypoint-initdb.d/99_migrations_202411.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < ./docker-entrypoint-initdb.d/99_migrations_202412.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < ./docker-entrypoint-initdb.d/99_migrations_202501.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < ./docker-entrypoint-initdb.d/99_migrations_202504.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < ./docker-entrypoint-initdb.d/99_migrations_202505.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < ./docker-entrypoint-initdb.d/99_migrations_202507.sql
```

Now rebuild the web app.

```bash
docker compose build web
```

Maybe need to run 99env.sh - check.

Then we can start the other containers.

```bash
docker compose up -d
```

After everything is started, the web site should be accesible.

### Additional data migration

Depending on the starting version, additional data migration may be needed.
If the old trips are visible, but the routes are not, we need to run an SQL Script to re-calculate the trip metadata.

```sql
DO $$
declare
	-- Re calculate the trip metadata
    logbook_rec record;
    avg_rec record;
	t_rec record;
    batch_size INTEGER := 20;
    offset_value INTEGER := 0;
    done BOOLEAN := FALSE;
    processed INTEGER := 0;
begin
	WHILE NOT done LOOP
        processed := 0;
	    FOR logbook_rec IN
	        SELECT *
	        FROM api.logbook
	        WHERE _from IS NOT NULL
	          AND _to IS NOT NULL
	          AND active IS FALSE
			  AND trip IS NULL
	          --AND trip_heading IS NULL
			  --AND vessel_id = '06b6d311ccfe'
	        ORDER BY id DESC
	        LIMIT batch_size -- OFFSET offset_value  -- don's use offset as causes entries to skip
	    LOOP
		processed := processed + 1;
		-- Update logbook entry with the latest metric data and calculate data
		PERFORM set_config('vessel.id', logbook_rec.vessel_id, false);
        
		-- Calculate trip metadata
		avg_rec := logbook_update_avg_fn(logbook_rec.id, logbook_rec._from_time::TEXT, logbook_rec._to_time::TEXT);
		--UPDATE api.logbook
		--	SET extra = jsonb_recursive_merge(extra, jsonb_build_object('avg_wind_speed', avg_rec.avg_wind_speed))
		-- WHERE id = logbook_rec.id;
		if avg_rec.count_metric IS NULL OR avg_rec.count_metric = 0 then
			-- We don't have the orignal metrics, we should read the geojson
			continue; -- return current row of SELECT
		end if;

        -- mobilitydb, add spaciotemporal sequence
        -- reduce the numbers of metrics by skipping row or aggregate time-series
        -- By default the signalk plugin report one entry every minute.
        IF avg_rec.count_metric < 30 THEN -- if less ~20min trip we keep it all data
            t_rec := logbook_update_metrics_short_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        ELSIF avg_rec.count_metric < 2000 THEN -- if less ~33h trip we skip data
            t_rec := logbook_update_metrics_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        ELSE -- As we have too many data, we time-series aggregate data
            t_rec := logbook_update_metrics_timebucket_fn(avg_rec.count_metric, logbook_rec._from_time, logbook_rec._to_time);
        END IF;
        --RAISE NOTICE 'mobilitydb [%]', t_rec;
        IF t_rec.trajectory IS NULL THEN
            RAISE WARNING '-> process_logbook_queue_fn, vessel_id [%], invalid mobilitydb data [%] [%]', logbook_rec.vessel_id, _id, t_rec;
            RETURN;
        END IF;

        RAISE NOTICE '-> process_logbook_queue_fn, vessel_id [%], update entry logbook id:[%] start:[%] end:[%]', logbook_rec.vessel_id, logbook_rec.id, logbook_rec._from_time, logbook_rec._to_time;
        UPDATE api.logbook
            SET
                trip = t_rec.trajectory,
                trip_cog = t_rec.courseovergroundtrue,
                trip_sog = t_rec.speedoverground,
                trip_twa = t_rec.windspeedapparent,
                trip_tws = t_rec.truewindspeed,
                trip_twd = t_rec.truewinddirection,
                trip_notes = t_rec.notes, -- don't overwrite existing user notes. **** Must set trip_notes otherwise replay is not working.
                trip_status = t_rec.status,
                trip_depth = t_rec.depth,
                trip_batt_charge = t_rec.stateofcharge,
                trip_batt_voltage = t_rec.voltage,
                trip_temp_water = t_rec.watertemperature,
                trip_temp_out = t_rec.outsidetemperature,
                trip_pres_out = t_rec.outsidepressure,
                trip_hum_out = t_rec.outsidehumidity,
				trip_heading = t_rec.heading, -- heading True
				trip_tank_level = t_rec.tankLevel, -- Tank currentLevel
				trip_solar_voltage = t_rec.solarVoltage, -- solar voltage
				trip_solar_power = t_rec.solarPower -- solar powerPanel
            WHERE id = logbook_rec.id;

        END LOOP;

        RAISE NOTICE '-> Processed:[%]', processed;
        IF processed = 0 THEN
          done := TRUE; 
        ELSE
            offset_value := offset_value + batch_size;
        END IF;
    END LOOP;

END $$;
```

### Update SignalK client

The SignalK client can be updated from the SignalK Web UI. After the migration we updated this to version v0.5.0

### Trouble shooting

During this migration, several issues came up, they eventually boiled down to an extension not updated and permissions issues.
