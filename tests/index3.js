'use strict';
/*
* Unit test #3, check post cron results, moorages, stays and stats
*
* process.env.PGSAIL_API_URI = from inside the docker 
*
* npm install supertest should mocha mochawesome moment
* alias mocha="./node_modules/mocha/bin/_mocha"
* mocha index.js --reporter mochawesome --reporter-options reportDir=/mnt/postgsail/,reportFilename=report_api.html
*
*/

const supertest = require("supertest");
// Deprecated
const should = require("should");
//const chai = require("chai");
//const should = chai.should();
let request = null;
let user_jwt = null;
let vessel_jwt = null;
var moment = require('moment');

// CNAMEs Array
[
  
  { cname: process.env.PGSAIL_API_URI, name: "PostgSail unit test kapla",
    signin: { email: 'demo+kapla@openplotter.cloud', pass: 'test', firstname:'First_kapla', lastname:'Last_kapla'},
    login: { email: 'demo+kapla@openplotter.cloud', pass: 'test'},
    vessel: { vessel_email: "demo+kapla@openplotter.cloud", vessel_mmsi: null, vessel_name: "kapla"},
    preferences: { key: '{email_notifications}', value: false }, /* Disable email_notifications */
    vessel_metadata: {
            name: "kapla",
            mmsi: "123456789",
            client_id: "vessels.urn:mrn:imo:mmsi:123456789",
            length: "12",
            beam: "10",
            height: "24",
            ship_type: "36",
            plugin_version: "0.0.1",
            signalk_version: "1.12.0",
            time: moment().subtract(69, 'minutes').format()
            /* To trigger monitor_offline quickly */
          },
    user_tables: [
        { url: '/stays', res_body_length: 3},
        { url: '/moorages', res_body_length: 3},
        { url: '/logbook', res_body_length: 2},
        { url: '/metadata', res_body_length: 1}
    ],
    user_views: [
        { url: '/stays_view', res_body_length: 2},
        { url: '/moorages_view', res_body_length: 2},
        { url: '/logs_view', res_body_length: 2},
        { url: '/log_view', res_body_length: 2},
        //{ url: '/stats_view', res_body_length: 1},
        { url: '/vessels_view', res_body_length: 1},
    ],
    user_patchs: [
      { url: '/logbook?id=eq.1',
        patch: {
              name: "patch log name 3",
              notes: "new log note 3"
            },
      },
      { url: '/stays?id=eq.1',
        patch: {
              name: "patch stay name 3",
              stay_code: 2,
              notes: "new stay note 3"
            },
      },
      { url: '/moorages?id=eq.1',
        patch: {
              name: "patch moorage name 3",
              home_flag: true,
              stay_code: 2,
              notes: "new moorage note 3"
            },
      }
    ],
    user_fn: [
      { url: '/rpc/timelapse_fn',
        payload: {
              start_log: 2
            },
        res: {
          obj_name: 'geojson'
        }
      },
      { url: '/rpc/export_logbook_geojson_fn',
        payload: {
              _id: 2
            },
        res: {
          obj_name: 'geojson'
        }
      },
      { url: '/rpc/export_logbook_gpx_fn',
        payload: {
              _id: 2
            },
        res: {
          obj_name: null
        }
      },
      { url: '/rpc/export_logbook_kml_fn',
        payload: {
              _id: 2
            },
        res: {
          obj_name: null
        }
      },
      { url: '/rpc/export_moorages_geojson_fn',
        payload: {},
        res: {
          obj_name: 'geojson'
        }
      },
      { url: '/rpc/export_moorages_gpx_fn',
        payload: {},
        res: {
          obj_name: null
        }
      },
      { url: '/rpc/find_log_from_moorage_fn',
        payload: {
          _id: 2
        },
        res: {
          obj_name: 'geojson'
        }
      },
      { url: '/rpc/find_log_to_moorage_fn',
        payload: {
          _id: 2
        },
        res: {
          obj_name: 'geojson'
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
      },
      { url: '/rpc/stats_logs_fn',
        payload: {},
        res: {
          obj_name: 'stats'
        }
      },
      { url: '/rpc/stats_logs_fn',
        payload: {
              start_date: '2022-01-01',
              end_date: '2022-06-12'
            },
        res: {
          obj_name: null
        }
      },
    ],
    email_otp_fn: [
      { url: '/rpc/generate_otp_fn',
        payload: { email: 'demo+kapla@openplotter.cloud' },
        res: {
          otp: 0
        }
      },
      { url: '/rpc/email_fn',
        //payload: { token: 'abc', pushover_user_key: '123qwerty!'},
        // invalid key to avoid trigger notification
        payload: { token: '123456' },
        res: {
          obj_name: 'settings'
        }
      }
    ],
    pushover_fn: [
      { url: '/rpc/generate_otp_fn',
        payload: { email: 'demo+kapla@openplotter.cloud' },
        res: {
          otp: 0
        }
      },
      { url: '/rpc/pushover_fn',
        //payload: { token: 'abc', pushover_user_key: '123qwerty!'},
        // invalid key to avoid trigger notification
        payload: { token: null, pushover_test_key: '123qwerty!'},
        res: {
          obj_name: 'settings'
        }
      }
    ],
    telegram_fn: [
      { url: '/rpc/generate_otp_fn',
        payload: { email: 'demo+kapla@openplotter.cloud' },
        res: {
          otp: 0
        }
      },
      { url: '/rpc/telegram_fn',
        //payload: { key: '{abc}', value: {"a": "1", "b": 2, "c": true}},
        // invalid key to avoid trigger notification
        payload: { token: null, telegram_test: '{"id": 123456789, "is_bot": false, "first_name": "kaplA", "language_code": "en"}' },
        res: {
          obj_name: 'settings'
        }
      }
    ]
  },
  { cname: process.env.PGSAIL_API_URI, name: "PostgSail unit test, aava",
    signin: {email: 'demo+aava@openplotter.cloud', pass: 'test', firstname:'first_aava', lastname:'last_aava'},
    login: {email: 'demo+aava@openplotter.cloud', pass: 'test'},
    vessel: {vessel_email: "demo+aava@openplotter.cloud", vessel_mmsi: null, vessel_name: "aava"},
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
    user_tables: [
        { url: '/stays', res_body_length: 3},
        { url: '/moorages', res_body_length: 4},
        { url: '/logbook', res_body_length: 2},
        { url: '/metadata', res_body_length: 1}
    ],
    user_views: [
        { url: '/stays_view', res_body_length: 2},
        { url: '/moorages_view', res_body_length: 2},
        { url: '/logs_view', res_body_length: 2},
        { url: '/log_view', res_body_length: 2},
        //{ url: '/stats_view', res_body_length: 1},
        { url: '/vessels_view', res_body_length: 1},
    ],
    user_patchs: [
      { url: '/logbook?id=eq.4',
        patch: {
              name: "patch log name 4",
              notes: "new log note 4"
            },
      },
      { url: '/stays?id=eq.4',
        patch: {
              name: "patch stay name 4",
              stay_code: 2,
              notes: "new stay note 4"
            },
      },
      { url: '/moorages?id=eq.4',
        patch: {
              name: "patch moorage name",
              home_flag: true,
              stay_code: 2,
              notes: "new moorage note"
            },
      }
    ],
    user_fn: [
      { url: '/rpc/timelapse_fn',
        payload: {
              start_log: 4
            },
        res: {
          obj_name: 'geojson'
        }
      },
      { url: '/rpc/export_logbook_geojson_fn',
        payload: {
              _id: 4
            },
        res: {
          obj_name: 'geojson'
        }
      },
      { url: '/rpc/export_logbook_gpx_fn',
        payload: {
              _id: 4
            },
        res: {
          obj_name: null
        }
      },
      { url: '/rpc/export_logbook_kml_fn',
        payload: {
              _id: 4
            },
        res: {
          obj_name: null
        }
      },
      { url: '/rpc/export_logbooks_gpx_fn',
        payload: {
            start_log: 3,
            end_log: 4
            },
        res: {
          obj_name: null
        }
      },
      { url: '/rpc/export_logbooks_kml_fn',
        payload: {
            start_log: 3,
            end_log: 4
            },
        res: {
          obj_name: null
        }
      },
      { url: '/rpc/export_moorages_geojson_fn',
        payload: {},
        res: {
          geojson: { type: 'FeatureCollection', features: [ [Object], [Object] ] }
        }
      },
      { url: '/rpc/export_moorages_gpx_fn',
        payload: {},
        res: {
          obj_name: null
        }
      },
      { url: '/rpc/find_log_from_moorage_fn',
        payload: {
          _id: 4
        },
        res: { geojson: { type: 'FeatureCollection', features: [ [Object] ] } }
      },
      { url: '/rpc/find_log_to_moorage_fn',
        payload: {
          _id: 4
        },
        res: { geojson: { type: 'FeatureCollection', features: [ [Object] ] } }
      },
      { url: '/rpc/vessel_fn',
        payload: null,
        res: {
          vessel: {
            beam: 10,
            mmsi: 787654321,
            name: 'aava',
            height: 24,
            length: 37,
            alpha_2: null,
            country: null,
            geojson: { type: 'Feature', geometry: [Object], properties: [Object] },
            ship_type: 'Pleasure Craft',
            created_at: '2023-08-17T16:32:13',
            last_contact: '2023-08-17T15:23:14'
          }
        }
      },
      { url: '/rpc/settings_fn',
        payload: null,
        res: {
          settings: {
            email: 'demo+aava@openplotter.cloud',
            first: 'first_aava',
            last: 'last_aava',
            preferences: { badges: [Object], email_notifications: false },
            created_at: '2023-08-17T16:32:12.701788',
            username: 'F Last_Aava',
            has_vessel: true
          }
        }
      },
      { url: '/rpc/stats_logs_fn',
        payload: {},
        res: { // Compare keys only
          stats: {
            count: 2,
            max_speed: 7.1,
            max_distance: 8.2365,
            max_duration: '01:11:00',
            max_speed_id: 3,
            sum_duration: '01:54:00',
            max_wind_speed: 44.2,
            max_distance_id: 3,
            max_wind_speed_id: 4
          }
        }
      },
      { url: '/rpc/stats_logs_fn',
        payload: {
              start_date: '2022-01-01',
              end_date: '2022-06-12'
            },
        res: { stats: null }
      },
    ],
    others_fn: [
      { url: '/rpc/generate_otp_fn',
        payload: { email: 'demo+aava@openplotter.cloud' },
        res: {
          obj_name: 'settings'
        }
      },
      { url: '/rpc/pushover_fn',
        // invalid key to avoid trigger notification
        payload: { token: 'zxy', pushover_test_key: '987azerty#'},
        res: {
          obj_name: 'settings'
        }
      },
      { url: '/rpc/update_user_preferences_fn',
        //payload: { key: '{xyz}', value: '987azerty#'},
        // invalid key to avoid trigger notification
        payload: { key: '{telegram_test}', value: '{"id": 987654321, "is_bot": false, "first_name": "aaVa", "language_code": "en"}' },
        res: {
          obj_name: 'settings'
        }
      },
      { url: '/rpc/bot',
        payload: { email: 'demo+aava@openplotter.cloud', chat_id: 987654321},
        res: {
          obj_name: 'settings'
        }
      }
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
          //should.exist(res.body.paths['/rpc/generate_otp_fn']);
          should.exist(res.body.paths['/rpc/pushover_fn']);
          should.exist(res.body.paths['/rpc/telegram_fn']);
          //should.exist(res.body.paths['/rpc/bot']);
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
              //console.log(user_jwt);
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
          // Function
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
              done(err);
            });
      });
  }); // JWT user_role

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
              should.exist(res.body[0].last_contact);
              done(err);
            });
      });
  }); // JWT user_role

  describe("Get vessel details function, JWT user_role", function(){

      it('/rpc/vessel_fn return json', function(done) {
          // Reset agent so we do not save cookies
          request = supertest.agent(test.cname);
          request
            .post('/rpc/vessel_fn')
            .set('Authorization', `Bearer ${user_jwt}`)
            .set('Accept', 'application/json')
            .set('Content-Type', 'application/json')
            .end(function(err,res){
              res.status.should.equal(200);
              should.exist(res.header['content-type']);
              should.exist(res.header['server']);
              res.header['content-type'].should.match(new RegExp('json','g'));
              res.header['server'].should.match(new RegExp('postgrest','g'));
              //should.exist(res.body);
              //body = res.body;
              console.log(res.text);
              done(err);
            });
      });
  }); // JWT user_role

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
              console.log(res.body);
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
              //console.log(res.body);
              res.status.should.equal(200);
              should.exist(res.header['content-type']);
              should.exist(res.header['server']);
              res.header['content-type'].should.match(new RegExp('json','g'));
              res.header['server'].should.match(new RegExp('postgrest','g'));
              should.exist(res.body);
              res.body.length.should.match(subtest.res_body_length);
              console.log(res.body);
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
              console.log(res.body);
              done(err);
            });
        }
        catch (error) {
          done();
        }
      });
    });
  }); // Patch endpoint

  describe("Function user_fn endpoint, JWT user_role", function(){

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
              console.log(res.body);
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

}); // OpenAPI description

}); // CNAMEs Array
