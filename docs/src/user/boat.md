# Your boat

The boat page holds everything PostgSail knows about your boat: its identity from SignalK, a photo, make and model, full specifications and its polar. Open the [Boats](https://iot.openplotter.cloud/boats) page and select your boat.

A complete profile shows up across PostgSail: in tracking views, in your friends' views and in fleet views. It also helps your AI assistant answer questions about your boat, such as its hull speed or theoretical performance under sail, through the [Telegram bot](https://t.me/pgsail_bot) or the [MCP server](../mcp.md).

## Connection status

At the top, the page tells you whether your boat is connected:

| Status  | Meaning                                                                    |
| ------- | -------------------------------------------------------------------------- |
| Pending | Your boat hasn't sent any data yet. It should be fine once she connects.  |
| Offline | Your boat is set up but hasn't sent data since the date shown.            |
| Online  | Your boat is sending data. The page shows when it last received some.     |

If the **Plugin version** is flagged as a warning, you're running an older version of the PostgSail plugin. Upgrade it in SignalK.

To connect a boat, use **Get token** and paste the token into the PostgSail plugin in SignalK. See [SignalK plugin](../plugin.md).

## Identity: SignalK is the source of truth

PostgSail reads your boat's identity from the **Vessel Base Data** in SignalK. Fill it in as completely as you can, including call sign and draft.

| Field      | SignalK path                 |
| ---------- | ---------------------------- |
| Name       | `self.name`                  |
| MMSI       | `self.mmsi`                  |
| Length     | `self.design.length.overall` |
| Beam       | `self.design.beam`           |
| Height     | `self.design.airHeight`      |
| Ship type  | `self.design.aisShipType`    |

The page compares what you registered in PostgSail with what SignalK reports:

- **Differs from SignalK:** the name or MMSI in PostgSail doesn't match SignalK. Click **Sync from SignalK** to update PostgSail with the SignalK values.
- **Not set in SignalK:** the field is empty in SignalK. The page shows the path to fill in, or a link to look up your boat's specifications instead.

Once your MMSI is set, the page also links to your boat on VesselFinder and MarineVesselTraffic.

## Make, model and photo

- **Make and Model:** enter it the way builders name it, for example "Beneteau Oceanis 40.1".
- **Photo:** upload a picture of your boat, under sail or at the dock, as JPG or PNG, up to 5 MB.

## Specifications from sailboatdata.com

PostgSail can import your boat's full specifications, so you don't type or convert anything:

1. Find your boat on [sailboatdata.com](https://sailboatdata.com).
2. Copy the address of its page, for example `https://sailboatdata.com/sailboat/...`.
3. On the boat page, open **Boat Specifications** and paste it into **Sailboatdata.com Permalink**.
4. Click **Save Specifications**.

PostgSail then fetches:

- **Dimensions:** LOA, LWL, beam, draft, displacement and ballast
- **Rig and hull:** sail area, rig type, hull type and designer
- **Engine**, and the first and last years built
- **Ratios:** comfort ratio, capsize screening formula, sail area/displacement and hull speed

## Polar

Add your boat's polar so PostgSail knows its theoretical performance:

1. Open **Boat's Polar** from the boat page.
2. Paste the polar as CSV, in the [ORC data](http://jieter.github.io/orc-data/site/) format.
3. Click **Save Polar**.

The boat page shows the polar as **Present** or **Missing**.

## SignalK mapping

If your boat sends its data on non-standard SignalK paths, map them under **Configuration Signalk Mapping**. See [Monitoring & energy](monitoring.md) for the paths each page uses.
