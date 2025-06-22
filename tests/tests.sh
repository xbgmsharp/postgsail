# PostgSail Unit test

if [[ -z "${PGSAIL_DB_URI}" ]]; then
  echo "PGSAIL_DB_URI is undefined"
  exit 1
fi
if [[ -z "${PGSAIL_API_URI}" ]]; then
  echo "PGSAIL_API_URI is undefined"
  exit 1
fi

# psql
if [[ ! -x "/usr/bin/psql" ]]; then
    apt update && apt -y install postgresql-client
fi

# go install
if [[ ! -x "/usr/bin/go" || ! -x "/root/go/bin/mermerd" ]]; then
    #wget -q https://go.dev/dl/go1.21.4.linux-arm64.tar.gz && \
    #rm -rf /usr/local/go && tar -C /usr/local -xzf go1.21.4.linux-arm64.tar.gz && \
    apt update && apt -y install golang-go && \
    #go install github.com/KarnerTh/mermerd@latest require latest go version
    go install github.com/KarnerTh/mermerd@v0.11.0
fi

# pnpm install
if [[ ! -x "/usr/local/bin/pnpm" ]]; then
    npm install -g pnpm
fi
pnpm install || exit 1

# settings
export mymocha="./node_modules/mocha/bin/_mocha"
mkdir -p output/ && rm -rf output/*

$mymocha index.js --reporter ./node_modules/mochawesome --reporter-options reportDir=output/,reportFilename=report1.html
if [ $? -eq 0 ]; then
    echo OK
else
    echo mocha index.js
    exit 1
fi

$mymocha index2.js --reporter ./node_modules/mochawesome --reporter-options reportDir=output/,reportFilename=report2.html
if [ $? -eq 0 ]; then
    echo OK
else
    echo mocha index2.js
    exit 1
fi

# metadata and vessel configuration unit tests
psql ${PGSAIL_DB_URI} < sql/metadata.sql > output/metadata.sql.output
diff sql/metadata.sql.output output/metadata.sql.output > /dev/null
#diff -u sql/metadata.sql.output output/metadata.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo OK
else
    echo SQL metadata.sql FAILED
    diff -u sql/metadata.sql.output output/metadata.sql.output
    exit 1
fi

# https://www.postgresql.org/docs/current/app-psql.html
# run cron jobs
#psql -U ${POSTGRES_USER} -h 172.30.0.1 signalk < sql/cron_run_jobs.sql > output/cron_run_jobs.sql.output
psql ${PGSAIL_DB_URI} < sql/cron_run_jobs.sql > output/cron_run_jobs.sql.output
diff sql/cron_run_jobs.sql.output output/cron_run_jobs.sql.output > /dev/null
#diff -u sql/cron_run_jobs.sql.output output/cron_run_jobs.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo OK
else
    echo SQL cron_run_jobs.sql FAILED
    diff -u sql/cron_run_jobs.sql.output output/cron_run_jobs.sql.output
    exit 1
fi

# handle post processing
#psql -U ${POSTGRES_USER} -h 172.30.0.1 signalk < sql/cron_post_jobs.sql > output/cron_post_jobs.sql.output
psql ${PGSAIL_DB_URI} < sql/cron_post_jobs.sql > output/cron_post_jobs.sql.output
diff sql/cron_post_jobs.sql.output output/cron_post_jobs.sql.output > /dev/null
#diff -u sql/cron_post_jobs.sql.output output/cron_post_jobs.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo OK
else
    echo SQL cron_post_jobs.sql FAILED
    diff -u sql/cron_post_jobs.sql.output output/cron_post_jobs.sql.output
    exit 1
fi

$mymocha index3.js --reporter ./node_modules/mochawesome --reporter-options reportDir=output/,reportFilename=report3.html
#echo 0
if [ $? -eq 0 ]; then
    echo OK
else
    echo mocha index3.js
    exit 1
fi

# Grafana Auth Proxy and role unit tests
psql ${PGSAIL_DB_URI} < sql/grafana.sql > output/grafana.sql.output
diff sql/grafana.sql.output output/grafana.sql.output > /dev/null
#diff -u sql/grafana.sql.output output/grafana.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo OK
else
    echo SQL grafana.sql FAILED
    diff -u sql/grafana.sql.output output/grafana.sql.output
    exit 1
fi

# Telegram and role unit tests
psql ${PGSAIL_DB_URI} < sql/telegram.sql > output/telegram.sql.output
diff sql/telegram.sql.output output/telegram.sql.output > /dev/null
#diff -u sql/telegram.sql.output output/telegram.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo OK
else
    echo SQL telegram.sql FAILED
    diff -u sql/telegram.sql.output output/telegram.sql.output
    exit 1
fi

# Badges unit tests
psql ${PGSAIL_DB_URI} < sql/badges.sql > output/badges.sql.output
diff sql/badges.sql.output output/badges.sql.output > /dev/null
#diff -u sql/badges.sql.output output/badges.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo OK
else
    echo SQL badges.sql FAILED
    diff -u sql/badges.sql.output output/badges.sql.output
    exit
fi

# Stays extended unit tests
psql ${PGSAIL_DB_URI} < sql/stays_ext.sql > output/stays_ext.sql.output
diff sql/stays_ext.sql.output output/stays_ext.sql.output > /dev/null
#diff -u sql/stays_ext.sql.output output/stays_ext.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo OK
else
    echo SQL stays_ext.sql FAILED
    diff -u sql/stays_ext.sql.output output/stays_ext.sql.output
    exit 1
fi

# Summary unit tests
psql ${PGSAIL_DB_URI} < sql/summary.sql > output/summary.sql.output
diff sql/summary.sql.output output/summary.sql.output > /dev/null
#diff -u sql/summary.sql.output output/summary.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo OK
else
    echo SQL summary.sql FAILED
    diff -u sql/summary.sql.output output/summary.sql.output
    exit 1
fi

# Monitoring API unit tests
$mymocha index4.js --reporter ./node_modules/mochawesome --reporter-options reportDir=output/,reportFilename=report4.html
if [ $? -eq 0 ]; then
    echo OK
else
    echo mocha index4.js
    exit 1
fi

# Monitoring SQL unit tests
psql ${PGSAIL_DB_URI} < sql/monitoring.sql > output/monitoring.sql.output
diff sql/monitoring.sql.output output/monitoring.sql.output > /dev/null
#diff -u sql/monitoring.sql.output output/monitoring.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo SQL monitoring.sql OK
else
    echo SQL monitoring.sql FAILED
    diff -u sql/monitoring.sql.output output/monitoring.sql.output
    exit 1
fi

# Anonymous API unit tests
$mymocha index5.js --reporter ./node_modules/mochawesome --reporter-options reportDir=output/,reportFilename=report5.html
if [ $? -eq 0 ]; then
    echo OK
else
    echo mocha index5.js
    exit 1
fi
# Anonymous API unit tests
$mymocha index6.js --reporter ./node_modules/mochawesome --reporter-options reportDir=output/,reportFilename=report6.html
if [ $? -eq 0 ]; then
    echo OK
else
    echo mocha index6.js
    exit 1
fi

# Anonymous SQL unit tests
psql ${PGSAIL_DB_URI} < sql/anonymous.sql > output/anonymous.sql.output
diff sql/anonymous.sql.output output/anonymous.sql.output > /dev/null
#diff -u sql/anonymous.sql.output output/anonymous.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo SQL anonymous.sql OK
else
    echo SQL anonymous.sql FAILED
    diff -u sql/anonymous.sql.output output/anonymous.sql.output
    exit 1
fi

# logbook SQL unit tests
psql ${PGSAIL_DB_URI} < sql/logbook.sql > output/logbook.sql.output
diff sql/logbook.sql.output output/logbook.sql.output > /dev/null
#diff -u sql/logbook.sql.output output/logbook.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo SQL logbook.sql OK
else
    echo SQL logbook.sql FAILED
    diff -u sql/logbook.sql.output output/logbook.sql.output
    exit 1
fi

# Stats SQL unit tests
#psql ${PGSAIL_DB_URI} < sql/stats.sql > output/stats.sql.output
#diff sql/stats.sql.output output/stats.sql.output > /dev/null
#diff -u sql/stats.sql.output output/stats.sql.output | wc -l
#echo 0
#if [ $? -eq 0 ]; then
#    echo SQL stats.sql OK
#else
#    echo SQL stats.sql FAILED
#    diff -u sql/stats.sql.output output/stats.sql.output
#    exit 1
#fi

# MobilityDB SQL unit tests
psql ${PGSAIL_DB_URI} < sql/mobilitydb.sql > output/mobilitydb.sql.output
diff sql/mobilitydb.sql.output output/mobilitydb.sql.output > /dev/null
#diff -u sql/mobilitydb.sql.output output/mobilitydb.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo SQL mobilitydb.sql OK
else
    echo SQL mobilitydb.sql FAILED
    diff -u sql/mobilitydb.sql.output output/mobilitydb.sql.output
    exit 1
fi

# qgis SQL unit tests
psql ${PGSAIL_DB_URI} < sql/qgis.sql > output/qgis.sql.output
diff sql/qgis.sql.output output/qgis.sql.output > /dev/null
#diff -u sql/qgis.sql.output output/qgis.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo SQL qgis.sql OK
else
    echo SQL qgis.sql FAILED
    diff -u sql/qgis.sql.output output/qgis.sql.output
    exit 1
fi

# maplapse SQL unit tests
psql ${PGSAIL_DB_URI} < sql/maplapse.sql > output/maplapse.sql.output
diff sql/maplapse.sql.output output/maplapse.sql.output > /dev/null
#diff -u sql/maplapse.sql.output output/maplapse.sql.output | wc -l
#echo 0
if [ $? -eq 0 ]; then
    echo SQL maplapse.sql OK
else
    echo SQL maplapse.sql FAILED
    diff -u sql/maplapse.sql.output output/maplapse.sql.output
    exit 1
fi

# Download and update openapi documentation
wget ${PGSAIL_API_URI} -O openapi.json
#echo 0
if [ $? -eq 0 ]; then
    cp openapi.json ../openapi.json
    echo openapi.json OK
else
    echo openapi.json FAILED
    exit 1
fi

# Generate and update mermaid schema documentation
/root/go/bin/mermerd --runConfig ../docs/ERD/mermerdConfig.yaml
#echo $?
echo 0 # not working in github-actions
if [ $? -eq 0 ]; then
    cp postgsail.md ../docs/ERD/postgsail.md
    echo postgsail.md OK
else
    echo postgsail.md FAILED
    exit 1
fi

#npm i -D schemalint && npx schemalint
