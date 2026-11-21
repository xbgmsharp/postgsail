# Windy weather station

PostgSail can publish your boat's weather observations to Windy.com as a personal weather station (PWS). The more marine observations Windy gets, the better the forecasts for everyone.

## Requirements

- **A public profile.** The Windy option only appears once your profile is public.
- **These SignalK paths:**

| SignalK path                           | Notes                                                                                 |
| -------------------------------------- | ------------------------------------------------------------------------------------- |
| `environment.outside.temperature`      | Required. Windy rejects observations without a temperature, so PostgSail skips them. |
| `environment.wind.speedTrue`           |                                                                                       |
| `environment.wind.directionTrue`       | True wind, not apparent. See below.                                                   |
| `environment.outside.relativeHumidity` |                                                                                       |
| `environment.outside.pressure`         |                                                                                       |

To check which paths your boat sends, open **Monitoring → Metrics** in the web app.

## True wind direction

Windy needs the true wind direction; apparent wind would confuse anyone using the data. Make sure your wind direction source is `environment.wind.directionTrue`.

Most NMEA networks don't provide true wind direction, which is expected. The [derived-data plugin](https://github.com/SignalK/signalk-derived-data) for SignalK can calculate it.

## Turn it on

1. Open your **Profile** from the user menu, select the **Sharing** tab and turn on **Public Profile**.
2. Turn on the option to publish your observations to Windy.
3. Wait up to one hour. PostgSail sends you a notification when your station is live on Windy.

## See also

- [SignalK vessel specification](https://signalk.org/specification/1.7.0/doc/vesselsBranch.html)
- [Report your weather station data to Windy](https://stations.windy.com/)
