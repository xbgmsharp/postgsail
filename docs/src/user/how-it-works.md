# How it works: logs, stays & moorages

PostgSail turns the data your boat sends into three things:

- **Logs:** your trips, from departure to arrival.
- **Stays:** the time you spend in one place between two trips.
- **Moorages:** the places themselves, which you visit again and again.

You never start or stop anything. Everything below happens on its own.

## Your boat's state

Detection relies on the `navigation.state` path in SignalK. The [signalk-autostate](https://github.com/meri-imperiumi/signalk-autostate) plugin sets it to one of four values:

| State      | Meaning                    |
| ---------- | -------------------------- |
| `sailing`  | Underway under sail        |
| `motoring` | Underway under engine      |
| `anchored` | At anchor                  |
| `moored`   | At a dock or on a mooring  |

Without `navigation.state`, PostgSail guesses from your speed: 3 knots or more counts as sailing, anything slower as moored. It can't tell anchored from moored, or sailing from motoring, so installing autostate is worth it.

## Logs

A log starts when your boat goes from anchored or moored to sailing or motoring. It ends when your boat is anchored or moored again. Switching between sailing and motoring during a trip doesn't split the log.

When a log ends, PostgSail calculates its distance, duration, speeds and wind, and links it to its departure and arrival moorages. It then appears in your [Logbook](logbook.md).

PostgSail also throws away trips that aren't real, such as:

- trips shorter than about 100 seconds, or with almost no distance;
- "trips" where the boat barely moved, like swinging at anchor or a GPS glitch;
- impossible trips, like 800 NM in less than 15 hours.

If one real trip ends up split in two, for example after a short stop, you can [merge the two logs](logbook.md#merge-two-logs).

## Stays

A stay starts when a trip ends, and lasts until you leave again. Each stay has a stay type:

| Stay type    | Meaning                   |
| ------------ | ------------------------- |
| Unknown      | Not classified yet        |
| Anchor       | At anchor                 |
| Mooring Buoy | On a mooring buoy         |
| Dock         | At a dock or in a marina  |

PostgSail picks the type from your boat's state and from the moorage. You can change it at any time, and add your own types, like "Marina" or "Raft-up". See [Stays & moorages](stays-moorages.md).

## Moorages

Each stay belongs to a moorage:

- **A place you've been before:** if you stop within 300 m of an existing moorage, PostgSail reuses it, with its name and stay type. That's how PostgSail remembers how you like to stay somewhere.
- **A new place:** PostgSail creates a new moorage. It takes the name from OpenStreetMap and OpenSeaMap, or from the nearest address. It also guesses the stay type from the map: a marina becomes Dock, a mooring becomes Mooring Buoy, and an anchorage, bay or beach becomes Anchor.

Rename a moorage or change its stay type once, and PostgSail updates every log and stay linked to it.
