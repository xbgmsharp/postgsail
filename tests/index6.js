"use strict";
/*
 * Unit test #6
 * Public/Anonymous access
 *
 * process.env.PGSAIL_API_URI = from inside the docker
 *
 * npm install supertest should mocha mochawesome moment
 * alias mocha="./node_modules/mocha/bin/_mocha"
 * mocha index6.js --reporter mochawesome --reporter-options reportDir=/mnt/postgsail/,reportFilename=report_api.html
 *
 */

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const supertest = require("supertest");
// Deprecated
const should = require("should");
//const chai = require("chai");
//const should = chai.should();
let request = null;
var moment = require("moment");

// Users Array
[
  {
    cname: process.env.PGSAIL_API_URI,
    name: "PostgSail unit test anonymous, no x-is-public header",
    moorages: {
      url: "/moorages_view",
      payload: null,
      res: {},
    },
    stays: {
      url: "/stays_view",
      payload: null,
      res: {},
    },
    logs: {
      url: "/logs_view",
      payload: null,
      res: {},
    },
    log: {
      url: "/log_view?id=eq.1",
      payload: null,
      res: {},
    },
    monitoring: {
      url: "/monitoring_view",
      payload: null,
      res: {},
    },
    timelapse: {
      url: "/rpc/export_logbooks_geojson_linestring_trips_fn",
      payload: null,
      res: {},
    },
    timelapse_full: {
      url: "/rpc/export_logbooks_geojson_linestring_trips_fn",
      payload: null,
      res: {},
    },
    replay_full: {
      url: "/rpc/export_logbooks_geojson_point_trips_fn",
      payload: null,
      res: {},
    },
    stats_logs: {
      url: "/rpc/stats_logs_fn",
      payload: null,
      res: {},
    },
    stats_stays: {
      url: "/rpc/stats_stay_fn",
      payload: null,
      res: {},
    },
    export_gpx: {
      url: "/rpc/export_logbook_gpx_trip_fn",
      payload: null,
      res: {},
    },
  },
].forEach(function (test) {
  //console.log(`${test.cname}`);
  describe(`${test.name}`, function () {
    request = supertest.agent(test.cname);
    request.set("User-Agent", "PostgSail unit tests");

    describe("With no JWT as api_anonymous, no x-is-public", function () {
      it("/stays_view, api_anonymous no jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .get(test.stays.url)
          .set("Accept", "application/json")
          .end(function (err, res) {
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            res.body.length.should.be.equal(0);
            done(err);
          });
      });
      it("/moorages_view, api_anonymous no jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .get(test.log.url)
          .set("Accept", "application/json")
          .end(function (err, res) {
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            res.body.length.should.be.equal(0);
            done(err);
          });
      });
      it("/logs_view, api_anonymous no jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .get(test.logs.url)
          .set("Accept", "application/json")
          .end(function (err, res) {
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            res.body.length.should.be.equal(0);
            done(err);
          });
      });
      it("/log_view, api_anonymous no jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .get(test.log.url)
          .set("Accept", "application/json")
          .end(function (err, res) {
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            res.body.length.should.be.equal(0);
            done(err);
          });
      });
      it("/monitoring_view, api_anonymous no jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .get(test.monitoring.url)
          .set("Accept", "application/json")
          .end(function (err, res) {
            console.log(res.text);
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            res.body.length.should.be.equal(0);
            done(err);
          });
      });
      it("/rpc/export_logbooks_geojson_linestring_trips_fn, api_anonymous no jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .post(test.timelapse.url)
          .set("Accept", "application/json")
          .end(function (err, res) {
            console.log(res.text);
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            should.exist(res.body.geojson);
            done(err);
          });
      });
      it("/rpc/export_logbooks_geojson_point_trips_fn, api_anonymous no jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .post(test.replay_full.url)
          .set("Accept", "application/json")
          .end(function (err, res) {
            console.log(res.body);
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            should.exist(res.body.geojson);
            done(err);
          });
      });
      it("/rpc/export_logbook_gpx_trip_fn, api_anonymous no jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .post(test.export_gpx.url)
          .send({_id: 1})
          .set("Accept", "application/json")
          .end(function (err, res) {
            console.log(res.text)
            res.status.should.equal(401);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            done(err);
          });
      });
    }); // user JWT
  }); // OpenAPI description
}); // Users Array
