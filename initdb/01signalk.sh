#------------------------------------------------------------------------------
# CUSTOMIZED OPTIONS
#------------------------------------------------------------------------------

echo "CUSTOMIZED OPTIONS"
echo $PGDATA
echo "${PGDATA}/postgresql.conf"

cat << 'EOF'  >> ${PGDATA}/postgresql.conf
# Add settings for extensions here
shared_preload_libraries = 'timescaledb,pg_stat_statements,pg_cron'
timescaledb.telemetry_level=off
# pg_cron database
#cron.database_name = 'signalk'
# pg_cron connect via a unix domain socket
cron.host = '/var/run/postgresql/'
# monitoring https://www.postgresql.org/docs/current/runtime-config-statistics.html#GUC-TRACK-IO-TIMING
track_io_timing = on
stats_temp_directory = '/tmp'

# Postgrest
# send logs where the collector can access them
#log_destination = 'stderr'
# collect stderr output to log files
#logging_collector = on
# save logs in pg_log/ under the pg data directory
#log_directory = 'pg_log'
# (optional) new log file per day
#log_filename = 'postgresql-%Y-%m-%d.log'
# log every kind of SQL statement
#log_statement = 'all'

EOF