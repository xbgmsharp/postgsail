# Notifications & Telegram bot

PostgSail keeps you posted about your boat by email, Pushover or Telegram. You set all of this up in your **Profile**, from the user menu.

## What you're notified about

For example:

- a new log, when a trip ends;
- a new moorage;
- your boat going offline or coming back online;
- a replay video of your trip, once it's ready;
- a new 24-hour distance record;
- your weekly summary;
- your own alerts (see below).

To see everything that happened recently, open **Event Logs** in the menu. It lists your last 500 events.

## Email

In the **Notifications** tab, turn **E-mail Notifications** on or off.

## Pushover

[Pushover](https://pushover.net) sends notifications to your phone or desktop.

1. In the **Notifications** tab, turn on **Phone Notifications**.
2. Click **Link Your Pushover Account to Enable** and authorize PostgSail on the Pushover page.
3. Back in PostgSail, the tab shows that your user is connected to Pushover.

## Telegram bot

The PostgSail Telegram bot sends you notifications and answers questions about your boat.

1. In the **Notifications** tab, turn on **Phone Notifications**.
2. Open the bot at [t.me/pgsail_bot](https://t.me/pgsail_bot), in a direct chat or in a group, and send `/start`.
3. Enter the email of your PostgSail account. PostgSail emails you a code.
4. Send the code to the bot. Your Telegram account is now linked.

### Commands

| Command       | What it does           |
| ------------- | ---------------------- |
| `/boat`       | Your boat's details    |
| `/monitoring` | Live monitoring data   |
| `/logs`       | Your trips             |
| `/moorages`   | Your moorages          |
| `/stays`      | Your stays             |
| `/settings`   | Your profile           |
| `/help`       | Help                   |
| `/cancel`     | Cancel what's running  |

You can also just ask in plain words, in your language, for example "Where is my boat?", "Show me my last trip" or "What's my battery voltage?". A complete [boat profile](boat.md) helps the bot answer questions about your boat.

## Alerts

Alerts warn you when something on board crosses a limit you set:

1. In the **Alerting** tab, turn on **Alerting Enabled**.
2. Set the thresholds you care about.
3. Set **Min Notification Interval (h)** so the same alert doesn't flood you.

| Threshold                     | Alerts you when it goes   |
| ----------------------------- | ------------------------- |
| Wind Speed (kts)              | above                     |
| Outdoor Temperature (C)       | below                     |
| Indoor Temperature (C)        | below                     |
| Water Temperature             | below                     |
| Water Depth (m)               | below                     |
| Pressure (hpa)                | below                     |
| Pressure Drop in 12 hours (hpa) | above                   |
| Battery Charge (%)            | below                     |
| Battery Voltage (V)           | below                     |

Alerts use your monitoring data, so check that the right SignalK paths are mapped. See [Monitoring & energy](monitoring.md).

To get notified when a friend's boat arrives, leaves or comes close, see [Friends](friends.md).
