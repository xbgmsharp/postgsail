# FAQ

Quick answers to common questions. Most answers link to a page with the details.

## What is PostgSail?

PostgSail is a logbook for your boat, built by boaters for boaters. You can use the cloud service or host it yourself. It logs every trip automatically: track, speed, distance, wind and more. You never start or stop a trip; PostgSail detects each one on its own.

At the end of a trip, PostgSail creates a log entry with the departure and arrival moorages. Time spent at a moorage is logged as a stay, for example "Stayed 3 days in Eagle Harbor at anchor". You can classify a stay as anchor, mooring buoy or dock. This is optional, and it's the only manual step. PostgSail remembers your choice the next time you visit the same moorage.

From your trips, PostgSail builds statistics: number of trips, moorages and countries visited, longest passages, time spent at anchor or on a mooring buoy, and more. It also creates a [timelapse](timelapse.md) that replays your trips on a map.

Your data stays private unless you make your profile public. Then friends and others can see your logs, monitoring, statistics and timelapse.

To see what it looks like, open the [demo](https://iot.openplotter.cloud/demo). For the details of how trips and stays are detected, see [How it works](how-it-works.md).

## What do I need to use PostgSail?

A SignalK server on your boat with a GPS position, such as OpenPlotter on a Raspberry Pi or a Victron GX device running Venus OS Large, plus the free PostgSail plugin and an Internet connection from time to time. The [signalk-autostate](https://github.com/meri-imperiumi/signalk-autostate) plugin is recommended. See [Getting started](getting-started.md).

## Is PostgSail free?

PostgSail Cloud is free for personal use with one boat. To manage several boats, [contact us](mailto:info@openplotter.cloud). PostgSail is also open source, so you can host it yourself.

## How do I add a photo and specifications for my boat?

On the boat page. You can upload a photo, set the make and model, import the full specifications from sailboatdata.com and sync your boat's identity from SignalK. See [Your boat](boat.md).

## Which units does PostgSail use?

| Data        | Stored as      | Shown as                                           |
| ----------- | -------------- | -------------------------------------------------- |
| Time        | UTC            | Your local time                                    |
| Distance    | Nautical miles | Nautical miles                                     |
| Temperature | Kelvin         | Celsius, or Fahrenheit with **Use Imperial Units** |
| Depth       | Meters         | Meters, or feet with **Use Imperial Units**        |

## Why don't I see any data?

PostgSail ignores metrics without a valid GPS position, with a timestamp in the future, or with out-of-range values. See [Troubleshooting](troubleshooting.md) for the full list and how to fix each one.

## Does PostgSail work without Internet?

Yes for the logbook: the plugin stores your data on board and sends it once you're connected again, so no trip is lost. Live monitoring needs a connection. If PostgSail receives nothing for 70 minutes, your boat shows as offline.

## When does my trip appear in the logbook?

Once your boat is anchored or moored again and has sent the data from the end of the trip. The plugin sends data every 10 minutes, so leave your boat powered and online for a little while after you arrive.

## Is PostgSail an emergency tracker?

No. PostgSail is a logbook and monitoring tool. Don't rely on it for safety at sea.

## Which SignalK paths do the monitoring pages use?

Monitoring, History and the energy widget each read a set of SignalK paths, and you can map your own. See [Monitoring & energy](monitoring.md).

## Can I customize the timelapse?

Yes: track color, date or log range, map type, animation speed, start delay and zoom. See [Timelapse](timelapse.md).

## Can my boat report weather to Windy?

Yes. With a public profile and the right SignalK paths, PostgSail publishes your observations as a personal weather station on Windy.com. See [Windy weather station](windy.md).

## Can my boat show up on noforeignland?

Yes. Paste your noforeignland Boat API Key in PostgSail, and your boat appears on the noforeignland community map. See [NoForeignland](noforeignland.md).

## Can I use PostgSail with an AI assistant?

Yes. PostgSail provides an MCP server with read-only access to your data. [Claude](https://claude.ai), [Le Chat](https://chat.mistral.ai) and other assistants can then search your logs, moorages and stays, and monitor and analyze your boat. See [AI assistant (MCP)](../mcp.md).

## Where is my data stored?

PostgSail is hosted in a European sovereign cloud. It complies with GDPR and isn't subject to the US CLOUD Act. You own your data: you can export it, or ask for it to be deleted, at any time.

## Where do I find each PostgSail service?

| Service      | URL                                                  |
| ------------ | ---------------------------------------------------- |
| Web app      | <https://iot.openplotter.cloud/>                     |
| API          | <https://api.openplotter.cloud/>                     |
| Grafana      | <https://app.openplotter.cloud/>                     |
| Telegram bot | <https://t.me/pgsail_bot>                            |

## Is PostgSail open source?

Yes. PostgSail is free and open source, and contributions are welcome. The stack stays simple on purpose: SQL and JavaScript with a bit of Python, and no middleware. Trip detection in the SignalK plugin relies on the auto-state plugin.

| Component      | Repository                                                                          |
| -------------- | ----------------------------------------------------------------------------------- |
| SignalK plugin | [xbgmsharp/signalk-postgsail](https://github.com/xbgmsharp/signalk-postgsail)       |
| Backend        | [xbgmsharp/postgsail](https://github.com/xbgmsharp/postgsail)                       |
| Web app        | [xbgmsharp/vuestic-postgsail](https://github.com/xbgmsharp/vuestic-postgsail)       |
| Telegram bot   | [xbgmsharp/postgsail-telegram-bot](https://github.com/xbgmsharp/postgsail-telegram-bot) |

To contribute, see [Development](../development.md).

## How do I get help?

Ask on [Discord](https://discord.gg/uuZrwz4dCS), open a [GitHub issue](https://github.com/xbgmsharp/postgsail/issues), or email [info@openplotter.cloud](mailto:info@openplotter.cloud).

## How can I support PostgSail?

PostgSail is free to use, but it isn't free to build or host. You can sponsor it through [GitHub Sponsors](https://github.com/sponsors/xbgmsharp) with a monthly or one-time donation. Spreading the word, reporting bugs and contributing code or documentation also help.
