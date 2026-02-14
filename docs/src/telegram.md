# Telegram Integration

Telegram is a **cloud-based messaging app** known for its focus on **security, speed, and cross-platform accessibility**. Creating a bot does not require a mobile phone number.

To create a bot, use **[@BotFather](https://t.me/botfather)** and paste the bot token into the `PGSAIL_TELEGRAM_BOT_TOKEN` environment variable.

### Environment Variables

To enable Telegram integration, configure the following environment variable:

- `PPGSAIL_TELEGRAM_BOT_TOKEN`

## Overview

PostgSail integrates with **Telegram** to send notifications to users via a custom bot. This integration supports:

- **OTP-based user linking**
- **Message templating with HTML formatting**
- **Rich media attachments** (photos, videos, etc.)

## Configuration

Telegram integration requires the following setup:

- A **bot token** configured via the `PGSAIL_TELEGRAM_BOT_TOKEN` environment variable. This token is stored in `app_settings` as `app.telegram_bot_token`.
- A **dedicated Telegram bot service** running in Docker.

## User Linking Flow

Users link their accounts to Telegram through an **OTP-based process**:

1. A **one-time code** is generated and sent via email notification.
2. The user sends the OTP to the bot, which processes the token and Telegram user object.
3. The system **validates the OTP** and stores the Telegram chat details in the user’s preferences.
4. Users can then **authenticate via Telegram** to receive a JWT token.

## Notification Requirements

The notification dispatcher requires both `phone_notifications` and `telegram_notifications` to be enabled.

## Advanced Features

- **Photo Attachments**: Logbook notifications can include map images as photos.
- **Timelapse Notifications**: Messages can include video URLs.
- **JWT Authentication**: Direct bot-based authentication using the API.

## Notes

- Telegram integration requires **app-level bot token configuration** and **user-level chat linking**.
- The system uses the **Telegram Bot API with HTML parse mode** for message formatting.
- All notifications are **logged in PostgreSQL** for audit purposes.
