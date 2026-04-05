# Telegram Integration

Telegram is a **cloud-based messaging app** known for its focus on **security, speed, and cross-platform accessibility**. Creating a bot does not require a mobile phone number.

To create a bot, use **[@BotFather](https://t.me/botfather)** and paste the bot token into the `PGSAIL_TELEGRAM_BOT_TOKEN` environment variable.

### Environment Variables

To enable Telegram integration, configure the following environment variable:

- `PGSAIL_TELEGRAM_BOT_TOKEN`

## Overview

PostgSail integrates with **Telegram** in two modes:

1. **Bot commands** — structured commands and notifications for vessel monitoring and alerts
2. **Natural language (LLM)** — conversational queries about your vessel data powered by a Large Language Model

## Bot Command Mode

The Telegram bot supports:

- **OTP-based user linking** — securely connecting your Telegram account to PostgSail
- **Push notifications** — voyage start/end, alerts, and monitoring events
- **Message templating with HTML formatting**
- **Rich media attachments** — map images, timelapse videos

### User Linking Flow

Users link their accounts to Telegram through an **OTP-based process**:

1. A **one-time code** is generated and sent via email notification.
2. The user sends the OTP to the bot, which processes the token and Telegram user object.
3. The system **validates the OTP** and stores the Telegram chat details in the user's preferences.
4. Users can then **authenticate via Telegram** to receive a JWT token.

### Notification Requirements

The notification dispatcher requires both `phone_notifications` and `telegram_notifications` to be enabled in the user's preferences.

## Natural Language Mode (LLM Integration)

In addition to structured bot commands, the Telegram bot provides a **natural language interface** powered by a Large Language Model. Once authenticated, users can ask free-form questions about their vessel data directly in the chat.

### Example queries

- _"What was my longest trip last month?"_
- _"Where did I anchor last week?"_
- _"What's my current battery voltage?"_
- _"Show me a summary of my voyages this year."_
- _"How many hours did I spend at sea in March?"_

### How it works

The bot forwards natural language messages to an LLM backend that has read-only access to your PostgSail data via the [MCP server](mcp.md) or the PostgREST API. The LLM interprets the query, retrieves the relevant data, and returns a human-readable answer in the Telegram chat.

Authentication is JWT-based — the same token issued during the OTP linking flow is used to scope all data access to the authenticated user's vessels.

## Configuration

Telegram integration requires the following setup:

- A **bot token** configured via the `PGSAIL_TELEGRAM_BOT_TOKEN` environment variable. This token is stored in `app_settings` as `app.telegram_bot_token`.
- A **dedicated Telegram bot service** running as the `telegram` Docker service.

## Advanced Features

- **Photo Attachments**: Logbook notifications can include map images as photos.
- **Timelapse Notifications**: Messages can include video URLs.
- **JWT Authentication**: Direct bot-based authentication using the API.

## Notes

- Telegram integration requires **app-level bot token configuration** and **user-level chat linking**.
- The system uses the **Telegram Bot API with HTML parse mode** for message formatting.
- All notifications are **logged in PostgreSQL** for audit purposes.
- The LLM natural language feature requires the MCP server or direct API access to be reachable from the bot service.
