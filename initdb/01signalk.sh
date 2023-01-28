#------------------------------------------------------------------------------
# CUSTOMIZED OPTIONS
#------------------------------------------------------------------------------

echo "CUSTOMIZED OPTIONS"
echo $PGDATA
echo "${PGDATA}/postgresql.conf"

cat << 'EOF'  >> ${PGDATA}/postgresql.conf
# PostgSail pg15
# Add settings for extensions here
shared_preload_libraries = 'timescaledb,pg_stat_statements,pg_cron'
# TimescaleDB - time series database
# Disable timescaleDB telemetry
timescaledb.telemetry_level=off

# pg_cron - Run periodic jobs in PostgreSQL
# pg_cron database
#cron.database_name = 'signalk'
# pg_cron connect via a unix domain socket
cron.host = '/var/run/postgresql/'
# Increase the number of available background workers from the default of 8
#max_worker_processes = 8

# monitoring https://www.postgresql.org/docs/current/runtime-config-statistics.html#GUC-TRACK-IO-TIMING
track_io_timing = on
track_functions = all
# Remove in pg-15, does not exist anymore
#stats_temp_directory = '/tmp'

# PostgREST - turns your PostgreSQL database directly into a RESTful API
# send logs where the collector can access them
log_destination = 'stderr'
# collect stderr output to log files
#logging_collector = on
# save logs in pg_log/ under the pg data directory
#log_directory = 'pg_log'
# (optional) new log file per day
#log_filename = 'postgresql-%Y-%m-%d.log'
# log every kind of SQL statement
#log_statement = 'all'
# Do not enable log_statement as its log format will not be parsed by pgBadger.

# pgBadger - a fast PostgreSQL log analysis report
# log all the queries that are taking more than 1 second:
#log_min_duration_statement = 1000
#log_checkpoints = on
#log_connections = on
#log_disconnections = on
#log_lock_waits = on
#log_temp_files = 0
#log_autovacuum_min_duration = 0
#log_error_verbosity = default

# Francois
log_min_messages = NOTICE
EOF