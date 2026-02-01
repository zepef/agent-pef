# Detailed Setup Guide

This document provides step-by-step instructions for setting up the Agent PEF dual-bot Telegram system.

## Prerequisites

- Node.js 22+
- npm or pnpm
- Cloudflare account with Workers Paid plan ($5/month)
- Anthropic API key
- Two Telegram bots created via @BotFather
- Docker Desktop (for local container builds)

## Part 1: Create Telegram Bots

### Step 1.1: Create Bots via @BotFather

1. Open Telegram and message @BotFather
2. Send `/newbot` and follow prompts for each bot:
   - **Local bot**: e.g., `agent-pef-bot-laptop` → `@agentpeflaptopbot`
   - **Cloud bot**: e.g., `agent-pef-bot-cloud` → `@agentpefbot`
3. Save both bot tokens securely

### Step 1.2: Disable Privacy Mode

For each bot:

1. Message @BotFather
2. Send `/mybots`
3. Select your bot
4. Go to **Bot Settings** → **Group Privacy** → **Turn off**

This allows bots to receive all group messages without @mention.

### Step 1.3: Verify Bot Settings

```bash
# Check bot can read all group messages
curl -s "https://api.telegram.org/bot<TOKEN>/getMe" | jq '.result.can_read_all_group_messages'
# Should return: true
```

## Part 2: Local Clawdbot Setup

### Step 2.1: Install Clawdbot

```bash
npm install -g clawdbot
clawdbot --version
```

### Step 2.2: Run Initial Setup

```bash
clawdbot doctor --fix
```

### Step 2.3: Configure Telegram

Edit `~/.clawdbot/clawdbot.json`:

```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "botToken": "<YOUR_LOCAL_BOT_TOKEN>",
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

**Important**: Do NOT set `webhookUrl` - this forces polling mode.

### Step 2.4: Start Local Gateway

```bash
clawdbot gateway --port 18789 --verbose
```

You should see:
```
[telegram] [default] starting provider (@agentpeflaptopbot)
[gateway] listening on ws://127.0.0.1:18789
```

## Part 3: MoltWorker (Cloudflare) Setup

### Step 3.1: Clone and Install

```bash
cd E:\Projects\agent-pef
git clone <moltworker-repo> moltworker
cd moltworker
npm install
```

### Step 3.2: Login to Wrangler

```bash
npx wrangler login
```

### Step 3.3: Configure Secrets

```bash
# Required secrets
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put MOLTBOT_GATEWAY_TOKEN  # Generate a random 64-char hex string
npx wrangler secret put TELEGRAM_BOT_TOKEN     # Cloud bot token

# Cloudflare Access (required for admin UI protection)
npx wrangler secret put CF_ACCESS_TEAM_DOMAIN  # e.g., "yourteam.cloudflareaccess.com"
npx wrangler secret put CF_ACCESS_AUD          # Application AUD tag

# R2 Storage (for persistence)
npx wrangler secret put R2_ACCESS_KEY_ID
npx wrangler secret put R2_SECRET_ACCESS_KEY
npx wrangler secret put CF_ACCOUNT_ID

# Development mode (optional)
npx wrangler secret put DEV_MODE               # "true" for dev features
npx wrangler secret put DEBUG_ROUTES           # "true" to enable /debug/* routes
```

### Step 3.4: Create R2 Bucket

1. Go to Cloudflare Dashboard → R2
2. Create bucket named `moltbot-data`
3. Create API token with Object Read & Write permissions

### Step 3.5: Enable Cloudflare Access

1. Go to Cloudflare Dashboard → Zero Trust → Access → Applications
2. Create self-hosted application for your worker URL
3. Add your email as authorized user
4. Copy the Application AUD tag

### Step 3.6: Deploy

```bash
npm run deploy
```

### Step 3.7: Verify Deployment

```bash
# Check sandbox health
curl https://moltbot-sandbox.<subdomain>.workers.dev/sandbox-health

# Check gateway status
curl https://moltbot-sandbox.<subdomain>.workers.dev/api/status

# Check Telegram configuration
curl https://moltbot-sandbox.<subdomain>.workers.dev/api/telegram-status
```

## Part 4: Telegram Polling Configuration

### Why Polling Instead of Webhooks?

Clawdbot version 2026.1.24-3 has a bug where the webhook endpoint returns HTTP 405 (Method Not Allowed) for POST requests. This affects both:
- Direct clawdbot webhook endpoints
- Proxied webhooks through MoltWorker

**Solution**: Use long polling mode instead of webhooks.

### How Polling is Configured

#### Local Bot

Simply don't set `webhookUrl` in the config. Clawdbot defaults to polling.

#### MoltWorker

The `start-moltbot.sh` script explicitly removes any webhook config:

```javascript
// In the Node.js config update section
if (process.env.TELEGRAM_BOT_TOKEN) {
    config.channels.telegram = config.channels.telegram || {};
    config.channels.telegram.botToken = process.env.TELEGRAM_BOT_TOKEN;
    config.channels.telegram.enabled = true;
    config.channels.telegram.dmPolicy = process.env.TELEGRAM_DM_POLICY || 'open';
    config.channels.telegram.allowFrom = ['*'];
    config.channels.telegram.groupPolicy = 'open';
    // Force polling mode by removing any existing webhook config
    delete config.channels.telegram.webhookUrl;
    delete config.channels.telegram.webhookPath;
}
```

### Verifying Polling Mode

```bash
# Check webhook is not set (url should be empty)
curl -s "https://api.telegram.org/bot<TOKEN>/getWebhookInfo" | jq '.result.url'
# Should return: ""

# Check pending updates are being consumed (should be 0 or decreasing)
curl -s "https://api.telegram.org/bot<TOKEN>/getWebhookInfo" | jq '.result.pending_update_count'
```

## Part 5: Group Chat Setup

### Step 5.1: Create Telegram Group

1. Create a new Telegram group (e.g., "pef-agents")
2. Add both bots to the group

### Step 5.2: Verify Bots Can See Messages

1. Send a test message in the group
2. Check both bots' logs for the message

For MoltWorker, use the debug endpoint:
```bash
curl "https://moltbot-sandbox.<subdomain>.workers.dev/api/start-debug?token=<GATEWAY_TOKEN>"
```

## Part 6: Troubleshooting

### Issue: Bot Not Receiving Messages

**Symptoms**: Messages sent to bot are not being processed

**Solutions**:
1. Check privacy mode is disabled (see Step 1.2)
2. Verify polling is active:
   ```bash
   curl -s "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"
   # url should be empty, pending_update_count should be 0
   ```
3. Check gateway is running

### Issue: MoltWorker Gateway Fails to Start

**Symptoms**: `/api/status` returns `not_running`

**Solutions**:
1. Check process logs:
   ```bash
   curl "https://moltbot-sandbox.<subdomain>.workers.dev/api/telegram-status"
   # Look at the "processes" array for failed processes
   ```
2. Get detailed logs from failed process:
   ```bash
   curl "https://moltbot-sandbox.<subdomain>.workers.dev/api/process-logs/<process_id>?token=<TOKEN>"
   ```
3. Force restart:
   ```bash
   curl -X POST "https://moltbot-sandbox.<subdomain>.workers.dev/api/restart?token=<TOKEN>"
   ```

### Issue: Secrets Not Available in Container

**Symptoms**: `hasTelegramTokenEnv: false` in telegram-status

**Solutions**:
1. Re-set the secret:
   ```bash
   npx wrangler secret put TELEGRAM_BOT_TOKEN
   ```
2. Redeploy:
   ```bash
   npm run deploy
   ```
3. Restart gateway to pick up new env vars

### Issue: Webhook Returns 405

**Symptoms**: Telegram webhook fails with "Method Not Allowed"

**Solution**: This is a known clawdbot bug. Switch to polling mode by:
1. Remove `webhookUrl` from config
2. Delete webhook from Telegram:
   ```bash
   curl "https://api.telegram.org/bot<TOKEN>/deleteWebhook"
   ```

## Part 7: API Reference

### Public Endpoints (No Auth Required)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/sandbox-health` | GET | Basic health check |
| `/api/status` | GET | Gateway process status |
| `/api/telegram-status` | GET | Telegram configuration debug |
| `/telegram/webhook` | POST | Telegram webhook (unused) |

### Token-Protected Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/start-debug?token=<T>` | GET | Start gateway with debug output |
| `/api/restart?token=<T>` | POST | Kill and restart gateway |
| `/api/process-logs/<id>?token=<T>` | GET | Get logs from specific process |

### Cloudflare Access Protected Endpoints

| Endpoint | Description |
|----------|-------------|
| `/_admin/` | Admin UI for device management |
| `/api/admin/*` | Admin API endpoints |
| `/debug/*` | Debug routes (if DEBUG_ROUTES=true) |

## Part 8: Files Modified

### `moltworker/start-moltbot.sh`

Key changes:
- Added Telegram polling mode configuration
- Explicitly delete webhookUrl/webhookPath to force polling
- Set open policies for DM and groups

### `moltworker/src/routes/public.ts`

Added debug endpoints:
- `/api/telegram-status` - Check Telegram config in container
- `/api/start-debug` - Manual gateway start with error logging
- `/api/restart` - Force gateway restart
- `/api/process-logs/:id` - Get logs from specific processes

### `moltworker/src/gateway/env.ts`

Environment variable mapping for container:
- Maps `TELEGRAM_BOT_TOKEN` to container env
- Maps `MOLTBOT_GATEWAY_TOKEN` to `CLAWDBOT_GATEWAY_TOKEN`

## Part 9: Security Considerations

1. **Bot Tokens**: Never commit bot tokens to git. Use secrets/environment variables.

2. **Gateway Token**: Generate a strong random token:
   ```powershell
   $token = -join ((48..57) + (97..102) | Get-Random -Count 64 | % {[char]$_})
   ```

3. **Cloudflare Access**: Always enable Cloudflare Access for admin endpoints in production.

4. **R2 Credentials**: Store R2 API tokens securely and rotate regularly.

5. **Open Policies**: The `allowFrom: ["*"]` and `dmPolicy: "open"` settings allow anyone to message the bots. Restrict these in production if needed.
