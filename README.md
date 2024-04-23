<br/>
<p align="center">
  <a href="https://github.com/xbgmsharp/postgsail">
    <img src="https://iot.openplotter.cloud/android-chrome-192x192.png" alt="Logo" width="80" height="80">
  </a>

  <h3 align="center">PostgSail</h3>

  <p align="center">
    PostgSail is an open-source alternative to traditional vessel data management!
    <br/>
    <br/>
    <a href="https://github.com/xbgmsharp/postgsail/blob/main/docs/README.md"><strong>Explore the docs »</strong></a>
    <br/>
    <br/>
    <a href="https://iot.openplotter.cloud/demo">View Demo</a>
    .
    <a href="https://github.com/xbgmsharp/postgsail/issues">Report Bug</a>
    .
    <a href="https://github.com/xbgmsharp/postgsail/issues">Request Feature</a>
  </p>
</p>

[![release](https://img.shields.io/github/release/xbgmsharp/postgsail?include_prereleases=&sort=semver&color=blue)](https://github.com/xbgmsharp/postgsail/releases/latest)
[![License](https://img.shields.io/github/license/xbgmsharp/postgsail)](#license)
[![issues - postgsail](https://img.shields.io/github/issues/xbgmsharp/postgsail)](https://github.com/xbgmsharp/postgsail/issues)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)
![Contributors](https://img.shields.io/github/contributors/xbgmsharp/postgsail?color=dark-green) 

[![Test services db, api](https://github.com/xbgmsharp/postgsail/actions/workflows/db-test.yml/badge.svg)](https://github.com/xbgmsharp/postgsail/actions/workflows/db-test.yml)
[![Test services db, api, web](https://github.com/xbgmsharp/postgsail/actions/workflows/frontend-test.yml/badge.svg)](https://github.com/xbgmsharp/postgsail/actions/workflows/frontend-test.yml)
[![Test services db, grafana](https://github.com/xbgmsharp/postgsail/actions/workflows/grafana-test.yml/badge.svg)](https://github.com/xbgmsharp/postgsail/actions/workflows/grafana-test.yml)

signalk-postgsail:
[![GitHub Release](https://img.shields.io/github/release/xbgmsharp/signalk-postgsail.svg)](https://github.com/xbgmsharp/signalk-postgsail/releases/latest)

postgsail-frontend:
[![GitHub Release](https://img.shields.io/github/release/xbgmsharp/vuestic-postgsail.svg)](https://github.com/xbgmsharp/vuestic-postgsail/releases/latest)

postgsail-telegram-bot:
[![GitHub Release](https://img.shields.io/github/release/xbgmsharp/postgsail-telegram-bot.svg)](https://github.com/xbgmsharp/postgsail-telegram-bot/releases/latest)

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/8124/badge)](https://www.bestpractices.dev/projects/8124)


## Table Of Contents

- [Table Of Contents](#table-of-contents)
- [About The Project](#about-the-project)
- [Features](#features)
- [Cloud-hosted PostgSail](#cloud-hosted-postgsail)
- [On-Premise (for free)](#on-premise-for-free)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
  - [Creating A Pull Request](#creating-a-pull-request)
- [License](#license)
- [Acknowledgements](#acknowledgements)

## About The Project

https://github.com/xbgmsharp/signalk-postgsail/assets/1498985/b2669c39-11ad-4a50-9f91-9397f9057ee8

Effortless cloud based solution for storing and sharing your SignalK data. Allow you to effortlessly log your sails and monitor your boat with historical data.

Here's how:

It is all about SQL, object-relational, time-series, spatial databases with a bit of python.

PostgSail is an open-source alternative to traditional vessel data management.
It is based on a well known open-source technology stack, Signalk, PostgreSQL, TimescaleDB, PostGIS, PostgREST. It does perfectly integrate with standard monitoring tool stack like Grafana.

To understand the why and how, you might want to read [Why.md](https://github.com/xbgmsharp/postgsail/blob/main/Why.md)

## Features

- Automatically log your voyages without manually starting or stopping a trip.
- Automatically capture the details of your voyages (boat speed, heading, wind speed, etc).
- Timelapse video your trips, with or without time control.
- Add custom notes to your logs.
- Export to CSV, GPX, GeoJSON, KML and download your logs.
- Aggregate your trip statistics: Longest voyage, time spent at anchorages, home ports etc.
- See your moorages on a global map, with incoming and outgoing voyages from each trip.
- Monitor your boat (position, depth, wind, temperature, battery charge status, etc.) remotely.
- History: view trends.
- Alert monitoring: get notification on low voltage or low fuel remotely.
- Notification via email or PushOver, Telegram.
- Offline mode.
- Low Bandwidth mode.
- Awesome statistics and graphs.
- Create and manage your own dashboards.
- Windy PWS (Personal Weather Station).
- Engine Hours Logger.
- Polar performance.
- Anything missing? just ask!

## Cloud-hosted PostgSail

Remove the hassle of running PostgSail yourself. Here you can skip the technical setup, the maintenance work and server costs by getting PostgSail on our reliable and secure PostgSail Cloud. Register and try for free at https://iot.openplotter.cloud/.

## On-Premise (for free)

Self host postgSail where you want and how you want. There are no restrictions, you’re in full control. [Install Guide](https://github.com/xbgmsharp/postgsail/blob/main/docs/README.md)

## Roadmap

See the [open issues](https://github.com/xbgmsharp/postgsail/issues) for a list of proposed features (and known issues).

Join the community, Get support and exchange on [Discord](https://discord.gg/uuZrwz4dCS). Missing a feature? just ask!

## Contributing

Contributions are what make the open source community such an amazing place to be learn, inspire, and create. Any contributions you make are **greatly appreciated**.
* If you have suggestions for features, feel free to [open an issue](https://github.com/xbgmsharp/postgsail/issues/new) to discuss it, or directly create a pull request with necessary changes.
* Please make sure you check your spelling and grammar.
* Create individual PR for each suggestion.
* Please also read through the [Code Of Conduct](https://github.com/xbgmsharp/postgsail/blob/main/CODE_OF_CONDUCT.md) before posting your first idea as well.

### Creating A Pull Request

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

Distributed under the Apache License Version 2.0. See [LICENSE](https://github.com/xbgmsharp/postgsail/blob/main/LICENSE) for more information.

## Acknowledgements

An out of the box IoT platform using Docker (could be extend to K3 or K8) with the following software:

- [Signal K server, a Free and Open Source universal marine data exchange format](https://signalk.org)
- [PostgreSQL, open source object-relational database system](https://postgresql.org)
- [TimescaleDB, Time-series data extends PostgreSQL](https://www.timescale.com)
- [PostGIS, a spatial database extender for PostgreSQL object-relational database.](https://postgis.net/)
- [Grafana, open observability platform | Grafana Labs](https://grafana.com)
- And many more
