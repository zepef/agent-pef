# Agent PEF - Multi-Bot Telegram Orchestration

A dual-bot architecture for AI-powered Telegram automation using Cloudflare Workers and local Clawdbot instances.

## Overview

This project sets up two complementary Telegram bots that can communicate in a shared group for inter-bot orchestration:

| Bot | Username | Platform | Purpose |
|-----|----------|----------|---------|
| **Local Clawdbot** | `@agentpeflaptopbot` | Local Machine | Uses Pro/Max subscription, can access local files |
| **MoltWorker** | `@agentpefbot` | Cloudflare Workers | Always-on cloud orchestrator, API-billed |

Both bots are configured to:
- Receive all messages in the "pef-agents" group (no @mention required)
- Use polling mode for Telegram updates (no webhooks)
- Have open DM and group policies

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Telegram Group: pef-agents                   │
│                                                                  │
│  ┌──────────────┐                         ┌──────────────────┐  │
│  │    User      │ ◄─────────────────────► │  @agentpefbot    │  │
│  │              │                         │  (MoltWorker)    │  │
│  └──────────────┘                         └────────┬─────────┘  │
│         │                                          │            │
│         │                                          │            │
│         ▼                                          ▼            │
│  ┌──────────────────┐                    ┌──────────────────┐   │
│  │ @agentpeflaptopbot│ ◄───────────────► │ Cloudflare       │   │
│  │ (Local Clawdbot) │    Group Messages  │ Workers Container│   │
│  └────────┬─────────┘                    └────────┬─────────┘   │
│           │                                       │             │
└───────────┼───────────────────────────────────────┼─────────────┘
            │                                       │
            ▼                                       ▼
    ┌───────────────┐                      ┌───────────────┐
    │ Local Machine │                      │ Cloudflare    │
    │ - File Access │                      │ - R2 Storage  │
    │ - Pro/Max Sub │                      │ - Always On   │
    │ - Dev Tools   │                      │ - API Billing │
    └───────────────┘                      └───────────────┘
```

## Project Structure

```
agent-pef/
├── README.md                    # This file
├── docs/
│   └── SETUP.md                # Detailed setup guide
└── moltworker/                  # Cloudflare Workers project
    ├── Dockerfile              # Container image for sandbox
    ├── start-moltbot.sh        # Container startup script
    ├── moltbot.json.template   # Clawdbot config template
    ├── wrangler.jsonc          # Wrangler configuration
    ├── src/
    │   ├── index.ts            # Main worker entry
    │   ├── config.ts           # Configuration constants
    │   ├── types.ts            # TypeScript types
    │   ├── auth/               # Cloudflare Access middleware
    │   ├── gateway/            # Gateway management (process, R2, env)
    │   └── routes/             # API routes (public, admin, debug)
    └── skills/                 # Custom skills directory
```

## Key Components

### MoltWorker (Cloudflare)

The MoltWorker runs Clawdbot in a Cloudflare Workers Container with:

- **Sandbox Container**: Runs clawdbot gateway in an isolated environment
- **R2 Storage**: Persistent storage for config and conversations
- **Cloudflare Access**: Authentication for admin UI
- **Telegram Polling**: Receives messages without webhook complexity

### Local Clawdbot

The local instance runs directly on your machine:

- **Direct File Access**: Can read/write local files
- **Pro/Max Subscription**: Uses Anthropic's subscription-based billing
- **Development Tools**: Full access to local development environment

## Configuration

### Local Bot Configuration

Location: `C:\Users\<username>\.clawdbot\clawdbot.json`

```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "<YOUR_BOT_TOKEN>",
      "dmPolicy": "open",
      "groupPolicy": "open",
      "allowFrom": ["*"],
      "streamMode": "partial"
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local"
  }
}
```

### MoltWorker Secrets

Set via `wrangler secret put`:

| Secret | Description |
|--------|-------------|
| `ANTHROPIC_API_KEY` | Anthropic API key |
| `MOLTBOT_GATEWAY_TOKEN` | Gateway authentication token |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token for @agentpefbot |
| `CF_ACCESS_TEAM_DOMAIN` | Cloudflare Access team domain |
| `CF_ACCESS_AUD` | Cloudflare Access application AUD |
| `R2_ACCESS_KEY_ID` | R2 storage access key |
| `R2_SECRET_ACCESS_KEY` | R2 storage secret key |
| `CF_ACCOUNT_ID` | Cloudflare account ID |

## Setup Summary

### What Was Done

1. **Created MoltWorker Project**
   - Cloned and configured Cloudflare Workers container setup
   - Built Docker container with clawdbot@2026.1.24-3
   - Configured startup script for environment-based configuration

2. **Configured Telegram Polling Mode**
   - Both bots use polling instead of webhooks
   - Webhooks were problematic (clawdbot 2026.1.24-3 returns 405 on POST)
   - Polling mode works reliably in both local and container environments

3. **Set Up Group Messaging**
   - Disabled privacy mode via @BotFather for both bots
   - Set `can_read_all_group_messages: true`
   - Configured `groupPolicy: "open"` and `allowFrom: ["*"]`

4. **Cloudflare Access Integration**
   - Protected admin UI with Cloudflare Access authentication
   - Public endpoints for health checks and Telegram webhook (unused)

5. **Debugging Infrastructure**
   - Added public debug endpoints for troubleshooting
   - `/api/status` - Gateway status check
   - `/api/telegram-status` - Telegram configuration debug
   - `/api/start-debug` - Manual gateway start with logs
   - `/api/process-logs/:id` - Get logs from specific processes

## Usage

### Starting Local Bot

```bash
clawdbot gateway --port 18789 --verbose
```

### Deploying MoltWorker

```bash
cd moltworker
npm install
npm run deploy
```

### Accessing MoltWorker Admin UI

Visit: `https://moltbot-sandbox.<subdomain>.workers.dev/_admin/`

### Testing Bots

1. Send a DM to either bot
2. Add both bots to the "pef-agents" group
3. Messages in the group are visible to both bots

## Troubleshooting

### Bot Not Receiving Messages

1. Check privacy mode is disabled via @BotFather
2. Verify `can_read_all_group_messages: true` with Telegram API
3. Check gateway is running: `/api/status`

### MoltWorker Process Failing

1. Check process logs: `/api/process-logs/<id>?token=<token>`
2. Restart gateway: `POST /api/restart?token=<token>`
3. Check Telegram status: `/api/telegram-status`

### Webhook vs Polling

Clawdbot 2026.1.24-3 has a bug where webhook POST endpoints return 405. Use polling mode by:
- Not setting `webhookUrl` in config
- Explicitly deleting any existing webhookUrl: `delete config.channels.telegram.webhookUrl`

## License

MIT
