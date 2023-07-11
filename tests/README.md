# PostgSail Unit Tests
The Unit Tests allow to automatically validate the workflow.

## A global overview
Based on `mocha` & `psql`

## get started
```bash
$ npm i
$ alias mocha="./node_modules/mocha/bin/_mocha"
$ bash tests.sh
```

## docker
```bash
$ docker-compose up -d db && sleep 15 && docker-compose up -d api && sleep 5
$ docker-compose -f docker-compose.dev.yml -f docker-compose.yml up tests
```