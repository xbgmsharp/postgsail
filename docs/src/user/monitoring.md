# Monitoring & energy

## Watch your boat live

Open **Monitoring** in the menu to check on your boat from anywhere:

- **Real-Time:** wind, temperatures, battery, humidity, depth and water temperature, barometer with its 24-hour average, solar and tank levels. Sections only show data your boat sends.
- **History:** trends over the last 24 hours, 48 hours, 72 hours or 7 days.
- **Metrics:** every SignalK path PostgSail receives from your boat, with its latest value.

Live monitoring needs your boat to be online. If PostgSail hasn't received anything for 70 minutes, the page tells you your boat is offline.

To share your live position and monitoring, make **Tracking & Monitoring** public. See [Profile, sharing & privacy](settings.md#sharing).

## Monitoring and History pages

The Monitoring and History pages read these SignalK paths:

| SignalK path                                        | Shown as            |
| --------------------------------------------------- | ------------------- |
| `environment.water.temperature`                     | Water temperature   |
| `environment.inside.temperature`                    | Inside temperature  |
| `environment.outside.temperature`                   | Outside temperature |
| `environment.wind.speedTrue`                        | True wind speed     |
| `environment.wind.directionTrue`                    | True wind direction |
| `environment.inside.relativeHumidity`               | Inside humidity     |
| `environment.outside.relativeHumidity`              | Outside humidity    |
| `environment.outside.pressure`                      | Outside pressure    |
| `environment.inside.pressure`                       | Inside pressure     |
| `electrical.batteries.House.capacity.stateOfCharge` | Battery charge      |
| `electrical.batteries.House.voltage`                | Battery voltage     |
| `environment.depth.belowTransducer`                 | Depth               |
| `electrical.solar.Main.panelVoltage`                | Solar voltage       |
| `electrical.solar.Main.panelPower`                  | Solar power         |
| `tanks.fuel.0.currentLevel`                         | Tank level          |

If your boat uses different paths, map them on the **Boat correlation** page in the web app.

## Energy widget

The energy widget looks for these path patterns, where `*` matches any name:

- `electrical.batteries.*.stateOfCharge`
- `electrical.batteries.*.voltage`
- `electrical.batteries.*.current`
- `electrical.solar.*.panelPower`
- `tanks.*.currentLevel.*`

You can choose which paths the widget uses on the **Boat correlation** page.

## Check what your boat sends

The **Metrics** page, under **Monitoring** in the menu, shows the SignalK paths PostgSail receives from your boat. For the meaning of each path, see the [SignalK vessel specification](https://signalk.org/specification/1.7.0/doc/vesselsBranch.html).
