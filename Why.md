
#### Why not InfluxDB vs TimescaleDB
I had an InfluxDBv1 on my RPI that kill the sdcard/usbkey. I had an InfluxDBv2, but there is no more ARM support and had to learn flux. Also could not find a good way to store data when offline. How do you export your data from a InfluxDBv2? Still looking for a solution.

With TimescaleDB, we already know SQL and there is a lot of tools and libraries that work with Postgres.
However, InfluxDB does simplify things like schema and provide an http endpoint.
With TimescaleDB, you are using a standard SQL table schema to store data from Signalk.

#### Why not MQTT vs HTTP 
Having MQTT, makes your application micro service approach. however you multiple the components and dependency. HTTP seem a more reliable solution specially for offline support as MQTT library have a buffer limitation.
Using PostgREST is an alternative to manual CRUD programming. Custom API servers suffer problems. Writing business logic often duplicates, ignores or hobbles database structure. Object-relational mapping is a leaky abstraction leading to slow imperative code. The PostgREST philosophy establishes a single declarative source of truth: the data itself.

#### PostgreSQL got it all!
No additional dependencies other than PostgreSQL, thanks to the extensions ecosystem.
With PostgSail is based on PostGis and TimescaleDB and a few other pg extensions, https://github.com/xbgmsharp/timescaledb-postgis, fore more details.
