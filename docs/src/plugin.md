# SignalK PostgSail plugin

SignalK server plugin to send all self SignalK numeric data and navigation entry to a PostgSail server.

[SignalK PostgSail plugin](https://github.com/xbgmsharp/signalk-postgsail)

Send, monitor, alert, observe all numeric values & positions & status to a self-hosted or cloud instances of PostgSail (PostgreSQL, Grafana).

## Dependencies
[signalk-autostate](https://www.npmjs.com/package/@meri-imperiumi/signalk-autostate) by @meri-imperiumi. Used to determine the vessel's state based on sensor values, and updates the `navigation.state` value accordingly.

The [signalk-derived-data](https://github.com/SignalK/signalk-derived-data) and [signalk-path-mapper](https://github.com/sbender9/signalk-path-mapper) plugins are both useful to remap available data to the required canonical paths.

## Source data

|SignalK path|Timeline name|Notes|
|-|-|-|
|`navigation.state`||use for trip start/end and motoring vs sailing|
|`navigation.courseOverGroundTrue`|Course||
|`navigation.headingTrue`|Heading||
|`navigation.speedThroughWater`|||
|`navigation.speedOverGround`|Speed||
|`environment.wind.directionTrue`|Wind||
|`environment.wind.speedTrue`|Wind||
|`environment.wind.speedOverGround`|Wind|||
|`environment.*.pressure`|Baro|Pressure in zone|
|`environment.*.temperature`|Temp||
|`environment.*.relativeHumidity`|Ratio|1 = 100%|
|`environment.water.swell.state`|Sea||
|`navigation.position`|Coordinates||
|`navigation.log`|Log|If present, used to calculate distance|
|`propulsion.*.runTime`|Engine|If present, used to calculate engine hour usage|
|`steering.autopilot.state`||Autopilot changes are logged.|
|`navigation.state`||If present, used to start and stop automated hourly entries. Changes are logged.|
|`propulsion.*.state`||Propulsion changes are logged.|
|`electrical.batteries.*.voltage`||Voltage measured|
|`electrical.batteries.*.current`||Current measured|
|`electrical.batteries.*.stateOfCharge`|ratio|State of charge, 1 = 100%|
|`electrical.solar.*`||Solar measured|
|`tanks.*.currentLevel`||Level of fluid in tank 0-100%|
|`tanks.*.capacity.*`||Total capacity|

The [signalk-derived-data](https://github.com/sbender9/signalk-derived-data) and [signalk-path-mapper](https://github.com/sbender9/signalk-path-mapper) plugins are both useful to remap available data to the required canonical paths.
