# Timelapse

PostgSail replays your trips as an animated track on a map, in 2D or in 3D. You can replay a single log, a series of logs or a date range, then share the replay.

## Create a replay

Open **Timelapse** in the menu to customize your replay:

1. **Choose Trips:** pick the start and end trip.
2. **Base Map:** Satellite, OpenStreetMap, CartoDB Positron, CartoDB Dark Matter, Eniro (Scandinavia), Nautical charts (USA) or EMODnet Bathymetry.
3. **Show Boat As:** a sailboat, a sailboat with sails, a powerboat or a dot.
4. **Track Color**, **Zoom Level**, **Animation Speed** and **Initial Delay**.
5. **Show Moorage Overlay** and **Show Instruments**, if you want them on the map.
6. Click **Replay (2D)**, or **Replay 3D** if you turned on 3D (see below).

To replay a single trip, you can also click **Replay** in the [log list](logbook.md).

## Replay in 3D

Turn on **3D Visualization** in the Timelapse form for a 3D replay with a tilted camera:

- **Camera View Mode:** **Standard**, **Follow Vessel** to keep the camera on your boat, or **Globe** to see your track on the globe.
- **Camera Pitch (Tilt):** from 0° (top down) to 60°.

Then click **Replay 3D**.

## Share a replay

From the Timelapse form, copy the replay's link, or share it by email, on Facebook or on X. Others can open it only if you make your timelapse public. See [Profile, sharing & privacy](settings.md#sharing).

## Options in the URL

You can also set the options directly in the replay's address, for example to embed it or share a specific view.

| Parameter                | What it does                                                                                                       | Default             |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------ | ------------------- |
| `start_log`, `end_log`   | First and last log to include. If you give only `start_log`, the replay shows that one log.                        | None                |
| `start_date`, `end_date` | Date range. If you give only `start_date`, the replay shows that day.                                              | None                |
| `map_type`               | Base map, by name: `Satellite`, `OpenStreetMap`, `CartoDB.Positron`, `CartoDB.DarkMatter`, `Eniro (Scandinavia)`, `Nautical charts (USA)` or `EMODnet Bathymetry`. The old values `0` (OpenStreetMap) and `1` (Satellite) still work. | `Satellite`         |
| `boat_type`              | `Sailboat`, `SailboatSails`, `Powerboat` or `Dot`                                                                  | Based on your boat  |
| `color`                  | Track color                                                                                                        | `dodgerblue`        |
| `speed`                  | Animation speed in milliseconds. Lower is faster.                                                                  | `250`               |
| `delay`                  | Pause before the animation starts, handy for screen recordings                                                     | `0`                 |
| `zoom`                   | Initial zoom level                                                                                                 | `13`                |
| `moorage_overlay`        | Show moorages: `true` or `false`                                                                                   | `true`              |
| `instruments`            | Show instruments: `true` or `false`                                                                                | `true`              |

The 3D replay lives at `/timelapse3d` and accepts the same trip, date, speed, delay, zoom and overlay options, plus:

| Parameter   | What it does                                          | Default  |
| ----------- | ----------------------------------------------------- | -------- |
| `view_mode` | `standard`, `follow_vessel` or `globe`                | `globe`  |
| `pitch`     | Camera tilt in degrees, from `0` (top down) to `60`   | `55`     |

### Example

This address replays Elysian's season from May to November 2021, as a yellow track on a satellite map:

<https://iot.openplotter.cloud/Elysian/timelapse?color=yellow&start_date=2021-05-01&end_date=2021-11-01&map_type=Satellite&speed=90&delay=1&zoom=11>
