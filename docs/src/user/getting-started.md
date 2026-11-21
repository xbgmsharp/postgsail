# Getting started

You need:

- **A SignalK server on your boat**, for example OpenPlotter on a Raspberry Pi, or a Victron GX device running Venus OS Large, which includes SignalK;
- **A GPS position** in SignalK. PostgSail needs it for both the logbook and monitoring;
- **An Internet connection**, at least from time to time.

From there, it takes five steps to get your boat into PostgSail.

Want to look around first? Open the [demo](https://iot.openplotter.cloud/demo); the demo login is already filled in.

## 1. Create your account

Sign up at [iot.openplotter.cloud](https://iot.openplotter.cloud/signup) with your name, email and a password.

## 2. Verify your email

PostgSail emails you a verification code. Enter it when the app asks for it. This confirms it's you before you connect a boat.

## 3. Add your boat

Enter your boat's name, with at least 4 characters, and pick a prefix if you like. The MMSI is optional: leave it blank if you're not sure. You can sync it from SignalK later on the [boat page](boat.md).

## 4. Connect SignalK

1. In PostgSail, open **Boats**, click **Get token** and copy the token.
2. In the SignalK Server admin, open **Appstore** and install the **signalk-postgsail** plugin.
3. Go to **Server → Plugin Config → PostgSail**. Keep the server URL `https://api.openplotter.cloud/`, paste your token, enable the plugin and click **Submit**.
4. Recommended: install the [signalk-autostate](https://github.com/meri-imperiumi/signalk-autostate) plugin as well. It tells PostgSail whether you're sailing, motoring, anchored or moored. Without it, PostgSail can only guess from your speed. See [How it works](how-it-works.md).

More details on the plugin: [SignalK plugin](../plugin.md).

## 5. Check that your boat is online

Open your boat on the **Boats** page. Within a few minutes, its status should change to **Online**. Then open **Monitoring** to see your live data.

Nothing arriving? See [Troubleshooting](troubleshooting.md).

## How your data reaches PostgSail

The plugin stores your data on board and sends it to PostgSail every 10 minutes:

- **No connection at sea?** Your data waits on board and goes out as soon as the connection comes back. Your logbook stays complete.
- **Live monitoring** needs a connection. If PostgSail receives nothing for 70 minutes, your boat shows as offline. That's normal when you switch everything off.

## What's next

- Go sailing. When you're back at anchor or at the dock, your trip appears in the [Logbook](logbook.md) on its own. Leave your boat powered and online for a little while after you arrive, so the end of the trip gets sent.
- Complete your [boat profile](boat.md): photo, make and model, specifications.
- Set up [notifications](notifications.md) by email, Pushover or Telegram.
