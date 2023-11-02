"use strict";
/*
 * Unit test #4
 * OTP for email, Pushover, Telegram
 *
 * process.env.PGSAIL_API_URI = from inside the docker
 *
 * npm install supertest should mocha mochawesome moment
 * alias mocha="./node_modules/mocha/bin/_mocha"
 * mocha index4.js --reporter mochawesome --reporter-options reportDir=/mnt/postgsail/,reportFilename=report_api.html
 *
 */

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const supertest = require("supertest");
// Deprecated
const should = require("should");
//const chai = require("chai");
//const should = chai.should();
let request = null;
let user_jwt = null;
var moment = require("moment");

// Users Array
[
  {
    cname: process.env.PGSAIL_API_URI,
    name: "PostgSail unit test kapla",
    signin: {
      email: "demo+kapla@openplotter.cloud",
      pass: "test",
      firstname: "First_kapla",
      lastname: "Last_kapla",
    },
    login: { email: "demo+kapla@openplotter.cloud", pass: "test" },
    preferences: { key: "{email_valid}", value: false },
    email_otp: [
      {
        url: "/rpc/generate_otp_fn",
        payload: { email: "demo+kapla@openplotter.cloud" },
        res: {
          otp: 0,
        },
      },
      {
        url: "/rpc/email_fn",
        payload: { token: null },
        res: {
          obj_name: "settings",
        },
      },
    ],
    pushover_otp: [
      {
        //url: '/rpc/generate_otp_fn',
        url: "/rpc/pushover_subscribe_link_fn",
        //payload: { email: 'demo+kapla@openplotter.cloud' },
        res: {
          obj_name: "pushover_link",
        },
      },
      {
        url: "/rpc/pushover_fn",
        payload: { token: null, pushover_user_key: "1234567890azerty!" },
        res: {
          obj_name: "settings",
        },
      },
    ],
    telegram_otp: [
      {
        url: "/rpc/update_user_preferences_fn",
        payload: { key: "{email_notifications}", value: false },
      },
      {
        url: "/rpc/update_user_preferences_fn",
        payload: { key: "{phone_notifications}", value: false },
      },
      {
        //url: '/rpc/generate_otp_fn',
        url: "/rpc/telegram_otp_fn",
        payload: { email: "demo+kapla@openplotter.cloud" },
        res: {
          otp: 0,
        },
      },
      {
        url: "/rpc/telegram_fn",
        payload: {
          token: null,
          telegram_obj: {
            chat: {
              id: 1234567890,
              type: "private",
              title: null,
              all_members_are_administrators: null,
            },
            date: "NOW",
            from: {
              id: 1234567890,
              is_bot: false,
              first_name: "Kapla",
              language_code: "en",
            },
          },
        },
        res: {},
      },
    ],
    telegram: { payload: { user_id: 1234567890 } },
    telegram_fn: [{ url: "/rpc/vessel_fn" }, { url: "/monitoring_view" }],
    badges: {
      url: "/rpc/settings_fn",
      payload: null,
      res: {
        obj_name: "settings",
      },
    },
    monitoring: [
      {
        url: "/monitoring_view",
        payload: null,
        res: {},
      },
      {
        url: "/monitoring_view2",
        payload: null,
        res: {},
      },
      {
        url: "/monitoring_view3",
        payload: null,
        res: {},
      },
      {
        url: "/monitoring_voltage",
        payload: null,
        res: {},
      },
      {
        url: "/monitoring_temperatures",
        payload: null,
        res: {},
      },
      {
        url: "/monitoring_humidity",
        payload: null,
        res: {},
      },
    ],
    eventlogs: {
      url: "/eventlogs_view",
      payload: null,
      res: {},
    },
    public: [
      {
        url: "/rpc/update_user_preferences_fn",
        payload: { key: "{public_logs}", value: true },
      },
      {
        url: "/rpc/update_user_preferences_fn",
        payload: { key: "{public_monitoring}", value: true },
      },
    ],
  },
  {
    cname: process.env.PGSAIL_API_URI,
    name: "PostgSail unit test, aava",
    signin: {
      email: "demo+aava@openplotter.cloud",
      pass: "test",
      firstname: "first_aava",
      lastname: "last_aava",
    },
    login: { email: "demo+aava@openplotter.cloud", pass: "test" },
    preferences: { key: "{email_valid}", value: false },
    email_otp: [
      {
        url: "/rpc/generate_otp_fn",
        payload: { email: "demo+aava@openplotter.cloud" },
        res: {
          otp: 0,
        },
      },
      {
        url: "/rpc/email_fn",
        payload: { token: null },
        res: {
          obj_name: "settings",
        },
      },
    ],
    pushover_otp: [
      {
        //url: '/rpc/generate_otp_fn',
        url: "/rpc/pushover_subscribe_link_fn",
        //payload: { email: 'demo+aava@openplotter.cloud' },
        res: {
          obj_name: "pushover_link",
        },
      },
      {
        url: "/rpc/pushover_fn",
        payload: { token: null, pushover_user_key: "0987654321qwerty!" },
        res: {
          obj_name: "settings",
        },
      },
    ],
    telegram_otp: [
      {
        url: "/rpc/update_user_preferences_fn",
        payload: { key: "{email_notifications}", value: false },
      },
      {
        url: "/rpc/update_user_preferences_fn",
        payload: { key: "{phone_notifications}", value: false },
      },
      {
        //url: '/rpc/generate_otp_fn',
        url: "/rpc/telegram_otp_fn",
        payload: { email: "demo+aava@openplotter.cloud" },
        res: {
          otp: 0,
        },
      },
      {
        url: "/rpc/telegram_fn",
        payload: {
          token: null,
          telegram_obj: {
            chat: {
              id: 9876543210,
              type: "private",
              title: null,
              all_members_are_administrators: null,
            },
            date: "NOW",
            from: {
              id: 9876543210,
              is_bot: false,
              first_name: "Aava",
              language_code: "en",
            },
          },
        },
        res: {},
      },
    ],
    telegram: { payload: { user_id: 9876543210 } },
    telegram_fn: [{ url: "/rpc/vessel_fn" }, { url: "/monitoring_view" }],
    badges: {
      url: "/rpc/settings_fn",
      payload: null,
      res: {
        obj_name: "settings",
      },
    },
    monitoring: [
      {
        url: "/monitoring_view",
        payload: null,
        res: {},
      },
      {
        url: "/monitoring_view2",
        payload: null,
        res: {},
      },
      {
        url: "/monitoring_view3",
        payload: null,
        res: {},
      },
      {
        url: "/monitoring_voltage",
        payload: null,
        res: {},
      },
      {
        url: "/monitoring_temperatures",
        payload: null,
        res: {},
      },
      {
        url: "/monitoring_humidity",
        payload: null,
        res: {},
      },
    ],
    eventlogs: {
      url: "/eventlogs_view",
      payload: null,
      res: {},
    },
    public: [
      {
        url: "/rpc/update_user_preferences_fn",
        payload: { key: "{public_logs}", value: true },
      },
      {
        url: "/rpc/update_user_preferences_fn",
        payload: { key: "{public_monitoring}", value: true },
      },
    ],
  },
].forEach(function (test) {
  //console.log(`${test.cname}`);
  describe(`${test.name}`, function () {
    request = supertest.agent(test.cname);
    request.set("User-Agent", "PostgSail unit tests");

    describe("Get JWT user_role", function () {
      it("/rpc/signup return user_role jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .post("/rpc/signup")
          .send(test.signin)
          .set("Accept", "application/json")
          .end(function (err, res) {
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            should.exist(res.body.token);
            user_jwt = res.body.token;
            should.exist(user_jwt);
            done(err);
          });
      });

      it("/rpc/login return user_role jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .post("/rpc/login")
          .send(test.login)
          .set("Accept", "application/json")
          .end(function (err, res) {
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            should.exist(res.body.token);
            res.body.token.should.match(user_jwt);
            console.log(user_jwt);
            should.exist(user_jwt);
            done(err);
          });
      });
    }); // JWT user_role

    describe("Set preferences email_notifications, JWT user_role", function () {
      it("/rpc/update_user_preferences_fn return true", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .post("/rpc/update_user_preferences_fn")
          .send(test.preferences)
          .set("Authorization", `Bearer ${user_jwt}`)
          .set("Accept", "application/json")
          .set("Content-Type", "application/json")
          .end(function (err, res) {
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            //console.log(res.text);
            should.exist(res.text);
            res.text.should.match("true");
            done(err);
          });
      });
    }); // JWT user_role

    describe("Function email OTP endpoint, JWT user_role", function () {
      let otp = null;
      test.email_otp.forEach(function (subtest) {
        it(`${subtest.url}`, function (done) {
          try {
            //console.log(`${subtest.url} ${subtest.payload}`);
            if (otp) {
              subtest.payload.token = otp;
            }
            // Reset agent so we do not save cookies
            request = supertest.agent(test.cname);
            request
              .post(subtest.url)
              .send(subtest.payload)
              .set("Authorization", `Bearer ${user_jwt}`)
              .set("Accept", "application/json")
              .end(function (err, res) {
                res.status.should.equal(200);
                should.exist(res.header["content-type"]);
                should.exist(res.header["server"]);
                res.header["content-type"].should.match(
                  new RegExp("json", "g")
                );
                res.header["server"].should.match(new RegExp("postgrest", "g"));
                console.log(res.body);
                should.exist(res.body);
                if (subtest.url == "/rpc/generate_otp_fn") {
                  otp = res.body;
                } else {
                  res.text.should.match("true");
                }
                done(err);
              });
          } catch (error) {
            done();
          }
        });
      });
    }); // email OTP endpoint

    describe("Function Pushover OTP endpoint, JWT user_role", function () {
      let otp = null;
      test.pushover_otp.forEach(function (subtest) {
        it(`${subtest.url}`, function (done) {
          try {
            //console.log(`${subtest.url} ${subtest.payload}`);
            if (otp) {
              subtest.payload.token = otp;
            }
            // Reset agent so we do not save cookies
            request = supertest.agent(test.cname);
            request
              .post(subtest.url)
              .send(subtest.payload)
              .set("Authorization", `Bearer ${user_jwt}`)
              .set("Accept", "application/json")
              .end(function (err, res) {
                res.status.should.equal(200);
                should.exist(res.header["content-type"]);
                should.exist(res.header["server"]);
                res.header["content-type"].should.match(
                  new RegExp("json", "g")
                );
                res.header["server"].should.match(new RegExp("postgrest", "g"));
                //console.log(res.body);
                should.exist(res.body);
                if (subtest.url == "/rpc/pushover_subscribe_link_fn") {
                  should.exist(res.body.pushover_link.link);
                  let rx = /3D(\d+)\&/g;
                  //console.log(rx.exec(res.body.pushover_link.link)[1]);
                  let arr = rx.exec(res.body.pushover_link.link);
                  //console.log(arr);
                  console.log(arr[1]);
                  otp = arr[1];
                } else {
                  res.text.should.match("true");
                }
                done(err);
              });
          } catch (error) {
            done();
          }
        });
      });
    }); // pushover OTP endpoint

    describe("Function Telegram OTP endpoint, JWT user_role", function () {
      let otp = null;
      test.telegram_otp.forEach(function (subtest) {
        it(`${subtest.url}`, function (done) {
          try {
            console.log(`${subtest.url} ${subtest.payload.email} ${otp}`);
            if (otp) {
              subtest.payload.token = otp;
              console.log(subtest.payload.telegram_obj.date);
              subtest.payload.telegram_obj.date = moment.utc().format();
            }
            // Reset agent so we do not save cookies
            request = supertest.agent(test.cname);
            request
              .post(subtest.url)
              .send(subtest.payload)
              .set("Authorization", `Bearer ${user_jwt}`)
              .set("Accept", "application/json")
              .end(function (err, res) {
                res.status.should.equal(200);
                should.exist(res.header["content-type"]);
                should.exist(res.header["server"]);
                res.header["content-type"].should.match(
                  new RegExp("json", "g")
                );
                res.header["server"].should.match(new RegExp("postgrest", "g"));
                console.log(res.body);
                should.exist(res.body);
                if (subtest.url == "/rpc/telegram_otp_fn") {
                  console.log(res.body.otp_code);
                  otp = res.body.otp_code;
                } else {
                  console.log(res.text);
                  res.text.should.match("true");
                  otp = null;
                }
                done(err);
              });
          } catch (error) {
            done();
          }
        });
      });
    }); // telegram OTP endpoint

    describe("telegram session, anonymous", function () {
      it("/rpc/telegram return jwt token", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .post("/rpc/telegram")
          .send(test.telegram.payload)
          .set("Accept", "application/json")
          .set("Content-Type", "application/json")
          .end(function (err, res) {
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            should.exist(res.body.token);
            user_jwt = res.body.token;
            console.log(res.body.token);
            done(err);
          });
      });
    }); // anonymous JWT

    describe("Telegram endpoint, JWT user_role", function () {
      let otp = null;
      test.telegram_fn.forEach(function (subtest) {
        it(`${subtest.url}`, function (done) {
          try {
            //console.log(`${subtest.url} ${subtest.res_body_length}`);
            // Reset agent so we do not save cookies
            request = supertest.agent(test.cname);
            request
              .get(subtest.url)
              .set("Authorization", `Bearer ${user_jwt}`)
              .set("Accept", "application/json")
              .end(function (err, res) {
                res.status.should.equal(200);
                should.exist(res.header["content-type"]);
                should.exist(res.header["server"]);
                res.header["content-type"].should.match(
                  new RegExp("json", "g")
                );
                res.header["server"].should.match(new RegExp("postgrest", "g"));
                console.log(res.body);
                should.exist(res.body);
                done(err);
              });
          } catch (error) {
            done();
          }
        });
      });
    }); // Function endpoint

    /*
  describe("Function others endpoint, JWT user_role", function(){

    let otp = null;
    test.others_fn.forEach(function (subtest) {
      it(`${subtest.url}`, function(done) {
        try {
          //console.log(`${subtest.url} ${subtest.res_body_length}`);
          // Reset agent so we do not save cookies
          request = supertest.agent(test.cname);
          request
            .post(subtest.url)
            .send(subtest.payload)
            .set('Authorization', `Bearer ${user_jwt}`)
            .set('Accept', 'application/json')
            .end(function(err,res){
              res.status.should.equal(200);
              should.exist(res.header['content-type']);
              should.exist(res.header['server']);
              res.header['content-type'].should.match(new RegExp('json','g'));
              res.header['server'].should.match(new RegExp('postgrest','g'));
              //console.log(res.body);
              should.exist(res.body);
              if (subtest.url == '/rpc/generate_otp_fn') {
                otp = res.body.text();
              }
              done(err);
            });
        }
        catch (error) {
          done();
        }
      });
    });
  }); // Function endpoint
*/

    describe("Badges, user jwt", function () {
      it("/rpc/settings_fn return user settings", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .post("/rpc/settings_fn")
          .set("Authorization", `Bearer ${user_jwt}`)
          .set("Accept", "application/json")
          .end(function (err, res) {
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            console.log(res.body);
            should.exist(res.body.settings);
            should.exist(res.body.settings.preferences.badges);
            let badges = res.body.settings.preferences.badges;
            //console.log(Object.keys(badges));
            Object.keys(badges).length.should.be.aboveOrEqual(3);
            badges.should.have.properties(
              "Helmsman",
              "Wake Maker",
              "Stormtrooper"
            );
            done(err);
          });
      });
    }); // user JWT

    describe("Function monitoring endpoint, JWT user_role", function () {
      let otp = null;
      test.monitoring.forEach(function (subtest) {
        it(`${subtest.url}`, function (done) {
          try {
            // Reset agent so we do not save cookies
            request = supertest.agent(test.cname);
            request
              .get(subtest.url)
              .set("Authorization", `Bearer ${user_jwt}`)
              .set("Accept", "application/json")
              .end(function (err, res) {
                res.status.should.equal(200);
                should.exist(res.header["content-type"]);
                should.exist(res.header["server"]);
                res.header["content-type"].should.match(
                  new RegExp("json", "g")
                );
                res.header["server"].should.match(new RegExp("postgrest", "g"));
                //console.log(res.body);
                should.exist(res.body);
                //let monitoring = res.body;
                //console.log(monitoring);
                // minimum set for static monitoring page
                // no value for humidity monitoring
                //monitoring.length.should.be.aboveOrEqual(21);
                done(err);
              });
          } catch (error) {
            done();
          }
        });
      });
    }); // Monitoring endpoint

    describe("Event Logs, user jwt", function () {
      it("/eventlogs_view endpoint, list process_queue, JWT user_role", function (done) {
        // Reset agent so we do not save cookies
        request = supertest.agent(test.cname);
        request
          .get("/eventlogs_view")
          .set("Authorization", `Bearer ${user_jwt}`)
          .set("Accept", "application/json")
          .end(function (err, res) {
            res.status.should.equal(200);
            should.exist(res.header["content-type"]);
            should.exist(res.header["server"]);
            res.header["content-type"].should.match(new RegExp("json", "g"));
            res.header["server"].should.match(new RegExp("postgrest", "g"));
            //console.log(res.body);
            should.exist(res.body);
            let event = res.body;
            //console.log(event);
            // minimum events log for kapla & aava 13 + 4 email_otp = 17
            event.length.should.be.aboveOrEqual(13);
            done(err);
          });
      });
    }); // user JWT

    describe("Function update preference for public access endpoint, JWT user_role", function () {
      test.public.forEach(function (subtest) {
        it(`${subtest.url}`, function (done) {
          try {
            // Reset agent so we do not save cookies
            request = supertest.agent(test.cname);
            request
              .post(subtest.url)
              .send(subtest.payload)
              .set("Authorization", `Bearer ${user_jwt}`)
              .set("Accept", "application/json")
              .end(function (err, res) {
                res.status.should.equal(200);
                should.exist(res.header["content-type"]);
                should.exist(res.header["server"]);
                res.header["server"].should.match(new RegExp("postgrest", "g"));
                //console.log(res.body);
                should.exist(res.body);
                //let monitoring = res.body;
                //console.log(monitoring);
                // minimum set for static monitoring page
                // no value for humidity monitoring
                //monitoring.length.should.be.aboveOrEqual(21);
                done(err);
              });
          } catch (error) {
            done();
          }
        });
      });
    }); // Monitoring endpoint

  }); // OpenAPI description
}); // Users Array
