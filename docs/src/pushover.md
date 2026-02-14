# Pushover Integration

PostgSail seamlessly integrates with **Pushover** to deliver real-time push notifications to users’ devices via a REST API. This integration supports **message templating**, **user subscription management**, and **multi-channel notification dispatching**.

## User Subscription Process

Users can subscribe to Pushover notifications through a simple web-based flow:

1. **Generate a subscription link** containing a one-time token.
2. **User authorizes** the subscription via Pushover’s dedicated page.
3. **On successful authorization**, Pushover redirects the user to your API endpoint, providing the user key.
4. **PostgSail validates** the token and securely stores the `pushover_user_key` in the user’s preferences.

## Notification Requirements

The notification dispatcher requires both `phone_notifications` and `pushover_notifications` to be enabled.

## Configuration

For detailed technical guidance, refer to the **[Pushover Message API documentation](https://pushover.net/api)**.

### Environment Variables

To enable Pushover integration, configure the following environment variables:

- `PGSAIL_PUSHOVER_APP_TOKEN`
- `PGSAIL_PUSHOVER_APP_URL`

## Key Features

- **App-Level and User-Level Configuration**: Pushover integration requires both system-wide setup and individual user subscriptions.
- **Unified Notification Pipeline**: Messages are dispatched through the same pipeline as email and Telegram notifications.
- **API Compatibility**: The system leverages **Pushover’s Messages API (v1)** for reliable message delivery.
