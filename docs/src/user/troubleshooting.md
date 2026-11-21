# Troubleshooting

Start with two safe checks: update the PostgSail plugin to its latest version, then restart your SignalK server. They solve many problems on their own. The boat page warns you when your plugin is out of date: see [Your boat](boat.md#connection-status).

To see what PostgSail actually receives from your boat, open **Monitoring → Metrics** in the web app.

## My boat shows Pending or Offline

**Pending** means PostgSail has never received data from your boat. **Offline** means it hasn't received anything for 70 minutes. Offline is normal when your boat's electronics are switched off.

If your boat should be online, check:

- that the SignalK server is powered and connected to the Internet;
- that the PostgSail plugin is enabled, with the right token. You can copy it again with **Get token** on the **Boats** page;
- that SignalK has a GPS position. Without one, PostgSail ignores the data (see below).

## Monitoring works, but no trips are logged

- **Check `navigation.state`.** Logs start and end when your boat's state changes. Install the [signalk-autostate](https://github.com/meri-imperiumi/signalk-autostate) plugin, and check in the SignalK Data Browser that `navigation.state` changes when you leave and arrive. See [How it works](how-it-works.md).
- **Check that your position updates** in the SignalK Data Browser while you move.
- **Give it time.** A log appears once your boat has sent the data from the end of the trip.

## My last trip is missing

The end of the trip is probably still on board. Switch your boat's electronics back on and connect them to the Internet. The plugin sends the waiting data and PostgSail finishes the log.

## One trip is split in two

This usually happens after a short stop, when your boat's state goes to anchored or moored for a moment. [Merge the two logs](logbook.md#merge-two-logs).

## Zigzag tracks, positions far away, or false trips

These usually come from a bad GPS source, or from two sources sending positions at the same time. Check your GPS antenna has a clear view of the sky, then check in SignalK how many sources send `navigation.position`, and set source priorities so only one is used. To clean up, delete the false logs.

## A reading is missing, zero or wrong

1. Open **Monitoring → Metrics** and check that the value and its time look right.
2. If the right value sits on a different path, map it on the **Boat correlation** page. See [Monitoring & energy](monitoring.md).

## Why PostgSail ignores some data

PostgSail ignores a metric when:

- **It has no valid GPS position.** Make sure your GPS is connected to OpenPlotter and sends data to the SignalK server.
- **Its position is 0,0, or latitude and longitude are equal.** These are typical GPS glitches.
- **Its position is more than 500 km from the previous one.**
- **Its timestamp is in the future.** Sync your system clock with GPS or an NTP server.
- **It's older than, or has the same time as, the last metric PostgSail received.**
- **Its status is invalid.** `navigation.state` must be `sailing`, `motoring`, `anchored` or `moored`.
- **Speed over ground (SOG) is 40 knots or more.**
- **Apparent wind speed (AWS) is 200 knots or more.**

## Asking for help

Ask on [Discord](https://discord.gg/uuZrwz4dCS) or open a [GitHub issue](https://github.com/xbgmsharp/postgsail/issues). Include:

- what you see, what you expected, and when it started;
- your plugin and SignalK versions, from the boat page;
- a link to the log concerned, if any.

Never post your token publicly: anyone with it can send data as your boat.
