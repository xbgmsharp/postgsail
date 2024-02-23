'use strict';
/*
* Unit test #1
* Create 2 users and 2 associate vessel with metrics
*
* process.env.PGSAIL_API_URI = from inside the docker 
*
* npm install supertest should mocha mochawesome moment
* alias mocha="./node_modules/mocha/bin/_mocha"
* mocha index.js --reporter mochawesome --reporter-options reportDir=/mnt/postgsail/,reportFilename=report_api.html
*
*/

const sleep = ms => new Promise(r => setTimeout(r, ms));

const supertest = require("supertest");
// Deprecated
const should = require("should");
//const chai = require("chai");
//const should = chai.should();
let request = null;
let user_jwt = null;
let vessel_jwt = null;
var moment = require('moment');
const metrics_kapla = require('./metrics_sample_kapla.json');
const metrics_aava = require('./metrics_sample_aava.json');

const fs = require('fs');


// CNAMEs Array
[
  
  { cname: process.env.PGSAIL_API_URI, name: "PostgSail unit test kapla",
    signin: { email: 'demo+kapla@openplotter.cloud', pass: 'test', firstname:'First_kapla', lastname:'Last_kapla'},
    login: { email: 'demo+kapla@openplotter.cloud', pass: 'test'},
    vessel: { vessel_email: "demo+kapla@openplotter.cloud", vessel_mmsi: "test", vessel_name: " kapla "},
    preferences: { key: '{email_notifications}', value: false }, /* Disable email_notifications */
    vessel_metadata: {
            name: "kapla",
            mmsi: "123456789",
            client_id: "vessels.urn:mrn:signalk:uuid:5b4f7543-7153-4840-b139-761310b242fd",
            length: "12",
            beam: "10",
            height: "24",
            ship_type: "36",
            plugin_version: "0.0.1",
            signalk_version: "signalk_version",
            time: moment.utc().subtract(69, 'minutes').format()
            /* To trigger monitor_offline quickly */
          },
    vessel_metrics: metrics_kapla,
    user_tables: [
        { url: '/stays', res_body_length: 3},
        // not processed yet, { url: '/moorages', res_body_length: 2},
        { url: '/logbook', res_body_length: 2},
        { url: '/metadata', res_body_length: 1}
    ],
    user_views: [
        // not processed yet, { url: '/stays_view', res_body_length: 1},
        // not processed yet, { url: '/moorages_view', res_body_length: 1},
        { url: '/logs_view', res_body_length: 0},
        { url: '/log_view', res_body_length: 2},
        //{ url: '/stats_view', res_body_length: 1},
        { url: '/vessels_view', res_body_length: 1},
    ],
    user_patchs: [
      { url: '/logbook?id=eq.1',
        patch: {
              name: "patch log name",
              notes: "new log note"
            },
      },
      { url: '/stays?id=eq.1',
        patch: {
              name: "patch stay name",
              stay_code: 2,
              notes: "new stay note"
            },
      },
      /* not processed yet, { url: '/moorages?id=eq.1',
        patch: {
              name: "patch moorage name",
              home_flag: true,
              stay_code: 2,
              notes: "new moorage note"
            },
      }
      */
    ],
    user_fn: [
      { url: '/rpc/timelapse_fn',
        payload: {
              start_log: 1
            },
        res: {
          obj_name: 'geojson'
        }
      },
      { url: '/rpc/export_logbook_geojson_fn',
        payload: {
              _id: 1
            },
        res: {
          obj_name: 'geojson'
        }
      },
      { url: '/rpc/export_logbook_gpx_fn',
        payload: {
              _id: 1
            },
        res: {
          obj_name: null
        }
      },
      { url: '/rpc/vessel_fn',
        payload: null,
        res: {
          obj_name: 'vessel'
        }
      },
      { url: '/rpc/settings_fn',
        payload: null,
        res: {
          obj_name: 'settings'
        }
      },
      { url: '/rpc/versions_fn',
        payload: null,
        res: {
          obj_name: 'versions'
        }
      }
    ],
    otp_fn: [
      { url: '/rpc/generate_otp_fn',
        payload: { email: 'demo+kapla@openplotter.cloud' },
        res: {
          otp: 0
        }
      },
      { url: '/rpc/email_fn',
        payload: { token: null },
        res: {
          obj_name: 'settings'
        }
      },
      { url: '/rpc/generate_otp_fn',
        payload: { email: 'demo+kapla@openplotter.cloud' },
        res: {
          otp: 0
        }
      },
      { url: '/rpc/pushover_fn',
        payload: { token: null, pushover_user_key: '1234567890azerty!'},
        res: {
          obj_name: 'settings'
        }
      },
      { url: '/rpc/generate_otp_fn',
        payload: { email: 'demo+kapla@openplotter.cloud' },
        res: {
          otp: 0
        }
      },
      { url: '/rpc/telegram_fn',
        payload: { token: null, telegram_obj: {"chat": {"id": 1234567890, "type": "private", "title": null, "all_members_are_administrators": null}, "date": "NOW", "from": {"id": 1234567890, "is_bot": false, "first_name": "Kapla", "language_code": "en"}} },
        res: {
            obj_name: 'settings'
          }
      }
    ]
  },
  { cname: process.env.PGSAIL_API_URI, name: "PostgSail unit test, aava",
    signin: { email: 'demo+aava@openplotter.cloud', pass: 'test', firstname:'first_aava', lastname:'last_aava'},
    login: { email: 'demo+aava@openplotter.cloud', pass: 'test'},
    vessel: { vessel_email: "demo+aava@openplotter.cloud", vessel_mmsi: "787654321", vessel_name: " aava "},
    preferences: { key: '{email_notifications}', value: false }, /* Disable email_notifications */
    vessel_metadata: {
            name: "aava",
            mmsi: "787654321",
            client_id: "vessels.urn:mrn:imo:mmsi:787654321",
            length: "12",
            beam: "10",
            height: "24",
            ship_type: "37",
            plugin_version: "1.0.2",
            signalk_version: "1.20.0",
            time: moment().subtract(69, 'minutes').format()
          },
    vessel_metrics: metrics_aava,
    user_tables: [
        { url: '/stays', res_body_length: 2},
        // not processed yet, { url: '/moorages', res_body_length: 2},
        { url: '/logbook', res_body_length: 1},
        { url: '/metadata', res_body_length: 1}
    ],
    user_views: [
        // not processed yet, { url: '/stays_view', res_body_length: 1},
        // not processed yet, { url: '/moorages_view', res_body_length: 1},
        { url: '/logs_view', res_body_length: 0},
        { url: '/log_view', res_body_length: 1},
        //{ url: '/stats_view', res_body_length: 1},
        { url: '/vessels_view', res_body_length: 1},
    ],
    user_patchs: [
      { url: '/logbook?id=eq.3',
        patch: {
              name: "patch log name",
              notes: "new log note"
            },
      },
      { url: '/stays?id=eq.4',
        patch: {
              name: "patch stay name",
              stay_code: 2,
              notes: "new stay note"
            },
      },
      /* not processed yet, { url: '/moorages?id=eq.1',
        patch: {
              name: "patch moorage name",
              home_flag: true,
              stay_code: 2,
              notes: "new moorage note"
            },
      }
      */
    ],
    user_fn: [
      { url: '/rpc/timelapse_fn',
        payload: {
              start_log: 3
            },
        res: {
          obj_name: 'geojson'
        }
      },
      { url: '/rpc/export_logbook_geojson_fn',
        payload: {
              _id: 3
            },
        res: {
          obj_name: 'geojson'
        }
      },
      { url: '/rpc/export_logbook_gpx_fn',
        payload: {
              _id: 3
            },
        res: {
          obj_name: null
        }
      },
      { url: '/rpc/vessel_fn',
        payload: null,
        res: {
          obj_name: 'vessel'
        }
      },
      { url: '/rpc/settings_fn',
        payload: null,
        res: {
          obj_name: 'settings'
        }
      }
    ],
    otp_fn: [
      { url: '/rpc/generate_otp_fn',
        payload: { email: 'demo+aava@openplotter.cloud' },
        res: {
          otp: 0
        }
      },
      { url: '/rpc/email_fn',
        payload: { token: null },
        res: {
          obj_name: 'settings'
        }
      },
      { url: '/rpc/generate_otp_fn',
        payload: { email: 'demo+aava@openplotter.cloud' },
        res: {
          otp: 0
        }
      },
      { url: '/rpc/pushover_fn',
        payload: { token: null, pushover_user_key: '0987654321qwerty!'},
        res: {
          obj_name: 'settings'
        }
      },
      { url: '/rpc/generate_otp_fn',
        payload: { email: 'demo+aava@openplotter.cloud' },
        res: {
          otp: 0
        }
      },
      { url: '/rpc/telegram_fn',
        payload: { token: null, telegram_obj: {"chat": {"id": 9876543210, "type": "private", "title": null, "all_members_are_administrators": null}, "date": "NOW", "from": {"id": 9876543210, "is_bot": false, "first_name": "Aava", "language_code": "en"}} },
        res: {
          obj_name: 'settings'
        }
      },
    ]
  }
].forEach( function(test){

//console.log(`${test.cname}`);
describe(`${test.name}`, function(){
request = supertest.agent(test.cname);
request.set('User-Agent', 'PostgSail unit tests');

  describe("OpenAPI description", function(){

    it('/', function(done) {
      request = supertest.agent(test.cname);
      request
        .get('/')
        .end(function(err,res){
          res.status.should.equal(200);
          should.exist(res.header['content-type']);
          should.exist(res.header['server']);
          res.header['content-type'].should.match(new RegExp('json','g'));
          res.header['server'].should.match(new RegExp('postgrest','g'));
          should.exist(res.body.paths['/rpc/signup']);
          should.exist(res.body.paths['/rpc/login']);
          should.exist(res.body.paths['/rpc/reset']);
          should.exist(res.body.paths['/rpc/recover']);
          //should.exist(res.body.paths['/rpc/generate_otp_fn']);
          should.exist(res.body.paths['/rpc/pushover_fn']);
          should.exist(res.body.paths['/rpc/telegram_fn']);
          should.exist(res.body.paths['/rpc/telegram']);
          done(err);
        });
      });

  }); // OpenAPI description

  describe("Get JWT user_role", function(){

      it('/rpc/signup return user_role jwt token', function(done) {
          // Reset agent so we do not save cookies
          request = supertest.agent(test.cname);
          request
            .post('/rpc/signup')
            .send(test.signin)
            .set('Accept', 'application/json')
            .end(function(err,res){
              res.status.should.equal(200);
              should.exist(res.header['content-type']);
              should.exist(res.header['server']);
              res.header['content-type'].should.match(new RegExp('json','g'));
              res.header['server'].should.match(new RegExp('postgrest','g'));
              should.exist(res.body.token);
              user_jwt = res.body.token;
              should.exist(user_jwt);
              done(err);
            });
      });

      it('/rpc/login return user_role jwt token', function(done) {
          // Reset agent so we do not save cookies
          request = supertest.agent(test.cname);
          request
            .post('/rpc/login')
            .send(test.login)
            .set('Accept', 'application/json')
            .end(function(err,res){
              res.status.should.equal(200);
              should.exist(res.header['content-type']);
              should.exist(res.header['server']);
              res.header['content-type'].should.match(new RegExp('json','g'));
              res.header['server'].should.match(new RegExp('postgrest','g'));
              should.exist(res.body.token);
              //res.body.token.should.match(user_jwt);
              console.log(user_jwt);
              should.exist(user_jwt);
              done(err);
            });
      }); 

  }); // JWT user_role

  describe("OpenAPI with JWT user_role", function(){

    it('/', function(done) {
      request = supertest.agent(test.cname);
      request
        .get('/')
        .set('Authorization', `Bearer ${user_jwt}`)
        .end(function(err,res){
          res.status.should.equal(200);
          should.exist(res.header['content-type']);
          should.exist(res.header['server']);
          res.header['content-type'].should.match(new RegExp('json','g'));
          res.header['server'].should.match(new RegExp('postgrest','g'));
          // Functions
          should.exist(res.body.paths['/rpc/register_vessel']);
          should.exist(res.body.paths['/rpc/update_user_preferences_fn']);
          should.exist(res.body.paths['/rpc/settings_fn']);
          should.exist(res.body.paths['/rpc/versions_fn']);
          // Tables
          should.exist(res.body.paths['/metadata']);
          should.exist(res.body.paths['/metrics']);
          should.exist(res.body.paths['/logbook']);
          should.exist(res.body.paths['/stays']);
          should.exist(res.body.paths['/moorages']);
          // Views
          should.exist(res.body.paths['/logs_view']);
          should.exist(res.body.paths['/moorages_view']);
          should.exist(res.body.paths['/stays_view']);
          should.exist(res.body.paths['/vessels_view']);
          //should.exist(res.body.paths['/stats_view']);
          should.exist(res.body.paths['/monitoring_view']);
          done(err);
        });
    });

  }); // OpenAPI JWT user_role

  describe("Set preferences email_notifications, JWT user_role", function(){

      it('/rpc/update_user_preferences_fn return true', function(done) {
          // Reset agent so we do not save cookies
          request = supertest.agent(test.cname);
          request
            .post('/rpc/update_user_preferences_fn')
            .send(test.preferences)
            .set('Authorization', `Bearer ${user_jwt}`)
            .set('Accept', 'application/json')
            .set('Content-Type', 'application/json')
            .end(function(err,res){
              res.status.should.equal(200);
              should.exist(res.header['content-type']);
              should.exist(res.header['server']);
              res.header['content-type'].should.match(new RegExp('json','g'));
              res.header['server'].should.match(new RegExp('postgrest','g'));
              //console.log(res.text);
              should.exist(res.text);
              res.text.should.match('true');
              done(err);
            });
      });
  }); // JWT user_role

  describe("Get versions, JWT user_role", function(){

      it('/rpc/versions_fn return json', function(done) {
          // Reset agent so we do not save cookies
          request = supertest.agent(test.cname);
          request
            .get('/rpc/versions_fn')
            .set('Authorization', `Bearer ${user_jwt}`)
            .set('Accept', 'application/json')
            .end(function(err,res){
              res.status.should.equal(200);
              should.exist(res.header['content-type']);
              should.exist(res.header['server']);
              res.header['content-type'].should.match(new RegExp('json','g'));
              res.header['server'].should.match(new RegExp('postgrest','g'));
              //console.log(res.text);
              should.exist(res.body.api_version);
              should.exist(res.body.sys_version);
              done(err);
            });
      });
  }); // JWT user_role

  describe("Get JWT vessel_role from user_role", function(){

      it('/rpc/register_vessel return vessel_role jwt token', function(done) {
          // Reset agent so we do not save cookies
          request = supertest.agent(test.cname);
          request
            .post('/rpc/register_vessel')
            .send(test.vessel)
            .set('Authorization', `Bearer ${user_jwt}`)
            .set('Accept', 'application/json')
            .end(function(err,res){
              res.status.should.equal(200);
              should.exist(res.header['content-type']);
              should.exist(res.header['server']);
              res.header['content-type'].should.match(new RegExp('json','g'));
              res.header['server'].should.match(new RegExp('postgrest','g'));
              should.exist(res.body.token);
              vessel_jwt = res.body.token;
              console.log(vessel_jwt);
              should.exist(vessel_jwt);
              // Save vessel JWT token for later use.
              fs.writeFile(`vessel_jwt_${test.vessel.vessel_name}.txt`, vessel_jwt, (err) => {
                // In case of a error throw err.
                if (err) throw err;
              })
              done(err);
            });
      });
  }); // JWT user_role

  describe("OpenAPI with JWT vessel_role", function(){

    it('/', function(done) {
      request = supertest.agent(test.cname);
      request
        .get('/')
        .set('Authorization', `Bearer ${vessel_jwt}`)
        .end(function(err,res){
          res.status.should.equal(200);
          should.exist(res.header['content-type']);
          should.exist(res.header['server']);
          res.header['content-type'].should.match(new RegExp('json','g'));
          res.header['server'].should.match(new RegExp('postgrest','g'));
          should.exist(res.body.paths['/metadata']);
          should.exist(res.body.paths['/metrics']);
          should.exist(res.body.paths['/logbook']);
          should.exist(res.body.paths['/stays']);
          should.exist(res.body.paths['/moorages']);
          done(err);
        });
    });

  }); // OpenAPI JWT vessel_role

  describe("Get vessel details view, JWT user_role", function(){

      it('/vessels_view return json', function(done) {
          // Reset agent so we do not save cookies
          request = supertest.agent(test.cname);
          request
            .get('/vessels_view')
            .set('Authorization', `Bearer ${user_jwt}`)
            .end(function(err,res){
              res.status.should.equal(200);
              should.exist(res.header['content-type']);
              should.exist(res.header['server']);
              res.header['content-type'].should.match(new RegExp('json','g'));
              res.header['server'].should.match(new RegExp('postgrest','g'));
              console.log(res.body);
              //res.body.length.should.match(0);
              res.body.length.should.match(1);
              //res.body[0].last_contact.should.match('Never');
              should.equal(res.body[0].last_contact, null);
              done(err);
            });
      });
  }); // JWT user_role

  describe("Get vessel details function, JWT user_role", function(){
    // no metadata from vessel so error - unrecognized configuration parameter "vessel.client_id"
      it('/rpc/vessel_fn return json', function(done) {
          // Reset agent so we do not save cookies
          request = supertest.agent(test.cname);
          request
            .get('/rpc/vessel_fn')
            .set('Authorization', `Bearer ${user_jwt}`)
            .set('Accept', 'application/json')
            .set('Content-Type', 'application/json')
            .end(function(err,res){
              console.log(res.body)
              res.status.should.equal(200);
              should.exist(res.header['content-type']);
              should.exist(res.header['server']);
              res.header['content-type'].should.match(new RegExp('json','g'));
              res.header['server'].should.match(new RegExp('postgrest','g'));
              should.exist(res.body);
              //body = res.body;
              //console.log(res.text);
              done(err);
            });
      });
  }); // JWT user_role

  describe("Vessel POST metadata, JWT vessel_role", function(){

    it('/metadata?on_conflict=vessel_id', function(done) {
      request = supertest.agent(test.cname);
      request
        .post('/metadata?on_conflict=vessel_id')
        .send(test.vessel_metadata)
        .set('Authorization', `Bearer ${vessel_jwt}`)
        .set('Accept', 'application/json')
        .set('Content-Type', 'application/json')
        .set('Prefer', 'return=headers-only,resolution=merge-duplicates')
        .end(function(err,res){
          res.status.should.equal(201);
          //console.log(res.header);
          should.exist(res.header['server']);
          res.header['server'].should.match(new RegExp('postgrest','g'));
          done(err);
        });
    });

  }); // Vessel metadata JWT vessel_role

  describe("Vessel POST metrics, JWT vessel_role", function(){

    let data = [];
    //console.log(vessel_metrics['metrics'][0]);
    let i;
    for (i = 0; i < test.vessel_metrics['metrics'].length; i++) {
      data[i] = test.vessel_metrics['metrics'][i];
      // Override time, -2h to allow to new data later without delay.
      data[i]['time'] = moment.utc().subtract(2, 'hours').add(i, 'minutes').format();
      // Override client_id
      data[i]['client_id'] = test.vessel_metadata.client_id;
    }
    // The last entry are invalid and should be ignore.
    // - Invalid status
    // - Invalid speedoverground
    // - Invalid time previous time is duplicate
    // Force last valid entry to be back in time from previous, it should be ignore silently
    data.at(-1).time = moment.utc(data.at(-3).time).subtract(1, 'minutes').format();
    //console.log(data[0]);

    it('/metrics?select=time', function(done) {
      request = supertest.agent(test.cname);
      request
        .post('/metrics?select=time')
        .send(data)
        .set('Authorization', `Bearer ${vessel_jwt}`)
        .set('Accept', 'application/json')
        .set('Content-Type', 'application/json')
        .set('Prefer', 'return=representation')
        .end(function(err,res){
          //console.log(res.body);
          res.status.should.equal(201);
          should.exist(res.header['content-type']);
          should.exist(res.header['server']);
          res.header['content-type'].should.match(new RegExp('json','g'));
          res.header['server'].should.match(new RegExp('postgrest','g'));
          should.exist(res.body);
          res.body.length.should.match(test.vessel_metrics['metrics'].length-3);
          done(err);
        });
    });

  }); // Vessel POST metrics JWT vessel_role

/*
  describe("run_cron_jobs() JWT vessel_role", function(){

    it('/rpc/run_cron_jobs', function(done) {
      request = supertest.agent(test.cname);
      request
        .get('/rpc/run_cron_jobs')
        .set('Authorization', `Bearer ${vessel_jwt}`)
        .set('Accept', 'application/json')
        .set('Content-Type', 'application/json')
        .end(function(err,res){
          res.status.should.equal(200);
          should.exist(res.header['content-type']);
          should.exist(res.header['server']);
          res.header['content-type'].should.match(new RegExp('json','g'));
          res.header['server'].should.match(new RegExp('postgrest','g'));
          done();
        });
    });

  }); // run_cron_jobs() JWT vessel_role
*/

  describe("Table endpoint, JWT user_role", function(){

    test.user_tables.forEach(function (subtest) {
      it(`${subtest.url}`, function(done) {
        try {
          //console.log(`${subtest.url} ${subtest.res_body_length}`);
          // Reset agent so we do not save cookies
          request = supertest.agent(test.cname);
          request
            .get(`${subtest.url}`)
            .set('Authorization', `Bearer ${user_jwt}`)
            .set('Accept', 'application/json')
            .end(function(err,res){
              res.status.should.equal(200);
              should.exist(res.header['content-type']);
              should.exist(res.header['server']);
              res.header['content-type'].should.match(new RegExp('json','g'));
              res.header['server'].should.match(new RegExp('postgrest','g'));
              should.exist(res.body);
              res.body.length.should.match(subtest.res_body_length);
              done(err);
            });
        }
        catch (error) {
          done();
        }
      });
    });
  }); // Table endpoint

  describe("Views endpoint, JWT user_role", function(){

    test.user_views.forEach(function (subtest) {
      it(`${subtest.url}`, function(done) {
        try {
          //console.log(`${subtest.url} ${subtest.res_body_length}`);
          // Reset agent so we do not save cookies
          request = supertest.agent(test.cname);
          request
            .get(`${subtest.url}`)
            .set('Authorization', `Bearer ${user_jwt}`)
            .set('Accept', 'application/json')
            .end(function(err,res){
              res.status.should.equal(200);
              should.exist(res.header['content-type']);
              should.exist(res.header['server']);
              res.header['content-type'].should.match(new RegExp('json','g'));
              res.header['server'].should.match(new RegExp('postgrest','g'));
              should.exist(res.body);
              res.body.length.should.match(subtest.res_body_length);
              done(err);
            });
        }
        catch (error) {
          done();
        }
      });
    });
  }); // Views endpoint

  describe("Patch endpoint, JWT user_role", function(){

    test.user_patchs.forEach(function (subtest) {
      it(`${subtest.url}`, function(done) {
        try {
          //console.log(`${subtest.url} ${subtest.res_body_length}`);
          // Reset agent so we do not save cookies
          request = supertest.agent(test.cname);
          request
            .patch(subtest.url)
            .send(subtest.patch)
            .set('Content-Type', 'application/json')
            .set('Authorization', `Bearer ${user_jwt}`)
            .set('Accept', 'application/json')
            .end(function(err,res){
              res.status.should.equal(204);
              should.exist(res.header['server']);
              res.header['server'].should.match(new RegExp('postgrest','g'));
              done(err);
            });
        }
        catch (error) {
          done();
        }
      });
    });
  }); // Patch endpoint

  describe("Function endpoint, JWT user_role", function(){

    test.user_fn.forEach(function (subtest) {
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
              //should.exist(res.body);
              done(err);
            });
        }
        catch (error) {
          done();
        }
      });
    });
  }); // Function endpoint

  /*
  describe("Function OTP endpoint, JWT user_role", function(){

    let otp = null;
    test.otp_fn.forEach(function (subtest) {
      otp = null;
      it(`${subtest.url}`, function(done) {
        try {
          //console.log(`${subtest.url} ${subtest.res}`);
          if (otp) {
            subtest.payload.token = otp;
          }
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
              console.log(res.body);
              should.exist(res.body);
              if (subtest.url == '/rpc/generate_otp_fn') {
                otp = res.body;
              } else {
                res.text.should.match('true');
                otp = null;
              }              
              done(err);
            });
        }
        catch (error) {
          done();
        }
      });
    });
  }); // Function OTP endpoint
  */

}); // OpenAPI description

}); // CNAMEs Array
