"use strict";
/*
 * Unit test #5
 * Public/Anonymous access
 *
 * process.env.PGSAIL_API_URI = from inside the docker
 *
 * npm install supertest should mocha mochawesome moment
 * alias mocha="./node_modules/mocha/bin/_mocha"
 * mocha index5.js --reporter mochawesome --reporter-options reportDir=/mnt/postgsail/,reportFilename=report_api.html
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
    name: "PostgSail unit test kapla",
    logs: {
      url: "/logs_view",
      header: { name: "x-is-public", value: btoa("kapla,public_logs_list,0") },
      payload: null,
      res: {},
    },
    log: {
      url: "/log_view?id=eq.1",
      header: { name: "x-is-public", value: btoa("kapla,public_logs,1") },
      payload: null,
      res: {},
    },
    monitoring: {
      url: "/monitoring_view",
      header: { name: "x-is-public", value: btoa("kapla,public_monitoring,0") },
      payload: null,
      res: {},
    },
    timelapse: {
      url: "/rpc/timelapse_fn",
      header: { name: "x-is-public", value: btoa("kapla,public_timelapse,1") },
      payload: null,
      res: {},
    },
    export_gpx: {
      url: "/rpc/export_logbook_gpx_fn",
      header: { name: "x-is-public", value: btoa("kapla,public_logs,0") },
      payload: null,
      res: {},
    },
  },
  {
    cname: process.env.PGSAIL_API_URI,
    name: "PostgSail unit test, aava",
    logs: {
      url: "/logs_view",
      header: { name: "x-is-public", value: btoa("aava,public_logs_list,0") },
      payload: null,
      res: {},
    },
    log: {
      url: "/log_view?id=eq.3",
      header: { name: "x-is-public", value: btoa("aava,public_logs,3") },
      payload: null,
      res: {},
    },
    monitoring: {
      url: "/monitoring_view",
      header: { name: "x-is-public", value: btoa("aava,public_monitoring,0") },
      payload: null,
      res: {},
    },
    timelapse: {
      url: "/rpc/timelapse_fn",
      header: { name: "x-is-public", value: btoa("aava,public_timelapse,0") },
      payload: null,
      res: {},
    },
    export_gpx: {
      url: "/rpc/export_logbook_gpx_fn",
      header: { name: "x-is-public", value: btoa("aava,public_logs,0") },
      payload: null,
      res: {},
    },
  },
].forEach(function (test) {
  //console.log(`${test.cname}`);
  describe(`${test.name}`, function () {
    request = supertest.agent(test.cname);
    request.set("User-Agent", "PostgSail unit tests");

    describe("Get JWT api_anonymous", function () {
      it("/logs_view, api_anonymous no jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .get(test.logs.url)
          .set(test.logs.header.name, test.logs.header.value)
          .set("Accept", "application/json")
          .end(function (err, res) {
            res.status.should.equal(404);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            done(err);
          });
      });
      it("/log_view, api_anonymous no jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .get(test.log.url)
          .set(test.log.header.name, test.log.header.value)
          .set("Accept", "application/json")
          .end(function (err, res) {
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            done(err);
          });
      });
      it("/monitoring_view, api_anonymous no jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .get(test.monitoring.url)
          .set(test.monitoring.header.name, test.monitoring.header.value)
          .set("Accept", "application/json")
          .end(function (err, res) {
            console.log(res.text);
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            done(err);
          });
      });
      it("/rpc/timelapse_fn, api_anonymous no jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .post(test.timelapse.url)
          .set(test.timelapse.header.name, test.timelapse.header.value)
          .set("Accept", "application/json")
          .end(function (err, res) {
            console.log(res.text);
            res.status.should.equal(404);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            done(err);
          });
      });
      it("/rpc/export_logbook_gpx_fn, api_anonymous no jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .post(test.export_gpx.url)
          .send({_id: 1})
          .set(test.export_gpx.header.name, test.export_gpx.header.value)
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
