# User Manual - Agent PEF Bots

Quick reference guide for launching, deploying, and managing the Agent PEF Telegram bots.

## Quick Start

### Starting Local Bot

```bash
# Start the local clawdbot gateway
clawdbot gateway --port 18789 --verbose
```

The bot will be available at `ws://127.0.0.1:18789` and will start receiving Telegram messages.

### Deploying MoltWorker

```bash
cd E:\Projects\agent-pef\moltworker

# Deploy to Cloudflare
npm run deploy
```

The MoltWorker will be available at `https://moltbot-sandbox.<your-subdomain>.workers.dev`

---

## Daily Operations

### Checking Bot Status

#### Local Bot

Look for these lines in the terminal:
```
[telegram] [default] starting provider (@agentpeflaptopbot)
[gateway] listening on ws://127.0.0.1:18789
```

#### MoltWorker

```bash
# Quick status check
curl https://moltbot-sandbox.zepef.workers.dev/api/status

# Expected response when running:
{"ok":true,"status":"running","processId":"proc_xxx"}

# Response when not running:
{"ok":false,"status":"not_running"}
```

### Stopping Bots

#### Local Bot

Press `Ctrl+C` in the terminal running the gateway.

#### MoltWorker

```bash
# Force stop (will auto-restart on next request)
curl -X POST "https://moltbot-sandbox.zepef.workers.dev/api/restart?token=YOUR_GATEWAY_TOKEN"
```

---

## Deployment Commands

### MoltWorker Deployment

```bash
cd E:\Projects\agent-pef\moltworker

# Full deployment (build + deploy + container image)
npm run deploy

# Build only (for testing)
npm run build

# View deployment logs
npx wrangler tail
```

### Updating Secrets

```bash
cd E:\Projects\agent-pef\moltworker

# Update a secret
npx wrangler secret put SECRET_NAME
# Enter the value when prompted

# List all secrets
npx wrangler secret list

# After updating secrets, redeploy:
npm run deploy
```

### Common Secrets to Update

| Secret | When to Update |
|--------|----------------|
| `ANTHROPIC_API_KEY` | API key rotation |
| `TELEGRAM_BOT_TOKEN` | Bot token regeneration |
| `MOLTBOT_GATEWAY_TOKEN` | Security rotation |

---

## Monitoring & Debugging

### View Telegram Configuration

```bash
curl https://moltbot-sandbox.zepef.workers.dev/api/telegram-status
```

Response includes:
- `hasTelegramTokenEnv`: Whether token secret is set
- `containerConfig`: Current Telegram config in container
- `telegramProviderStarted`: Whether Telegram provider initialized
- `processes`: List of container processes

### View Process Logs

```bash
# Get logs from a specific process
curl "https://moltbot-sandbox.zepef.workers.dev/api/process-logs/PROCESS_ID?token=YOUR_TOKEN"
```

### Force Start Gateway with Debug Output

```bash
curl "https://moltbot-sandbox.zepef.workers.dev/api/start-debug?token=YOUR_TOKEN"
```

Returns full startup logs including any errors.

### Check Telegram API Status

```bash
# Check if bot is receiving messages (pending_update_count should be 0)
curl "https://api.telegram.org/botYOUR_TOKEN/getWebhookInfo"

# Get bot info
curl "https://api.telegram.org/botYOUR_TOKEN/getMe"
```

---

## Configuration Changes

### Modify Local Bot Config

1. Edit `C:\Users\<username>\.clawdbot\clawdbot.json`
2. Restart the gateway: `clawdbot gateway --port 18789 --verbose`

### Modify MoltWorker Config

1. Edit files in `E:\Projects\agent-pef\moltworker\`
   - `start-moltbot.sh` for startup configuration
   - `moltbot.json.template` for default config template
2. Redeploy: `npm run deploy`

---

## Common Tasks

### Add Bot to New Group

1. Open Telegram
2. Create or open the group
3. Add the bot by username (`@agentpeflaptopbot` or `@agentpefbot`)
4. Verify bot can see messages (privacy mode must be off)

### Regenerate Bot Token

1. Message @BotFather on Telegram
2. Send `/mybots` → Select bot → API Token → Revoke
3. Copy new token
4. Update configuration:
   - **Local**: Edit `~/.clawdbot/clawdbot.json`
   - **MoltWorker**: `npx wrangler secret put TELEGRAM_BOT_TOKEN`
5. Restart/redeploy

### Check Bot Privacy Mode

1. Message @BotFather
2. `/mybots` → Select bot → Bot Settings → Group Privacy
3. Should show "Privacy mode is disabled"

---

## Troubleshooting Quick Reference

| Problem | Solution |
|---------|----------|
| Bot not responding | Check gateway is running |
| `not_running` status | Call `/api/start-debug?token=X` |
| `hasTelegramTokenEnv: false` | Re-set secret and redeploy |
| Process keeps failing | Check `/api/process-logs/<id>` |
| No group messages | Disable privacy mode via @BotFather |
| Webhook 405 error | Already using polling mode (correct) |

---

## URLs Reference

### Local Bot

| URL | Description |
|-----|-------------|
| `ws://127.0.0.1:18789` | Gateway WebSocket |
| `http://127.0.0.1:18789` | Gateway HTTP |

### MoltWorker

| URL | Description |
|-----|-------------|
| `https://moltbot-sandbox.zepef.workers.dev/` | Main UI |
| `https://moltbot-sandbox.zepef.workers.dev/_admin/` | Admin panel |
| `https://moltbot-sandbox.zepef.workers.dev/api/status` | Status check |
| `https://moltbot-sandbox.zepef.workers.dev/api/telegram-status` | Telegram debug |

---

## Environment Variables

### Local Bot

Set in shell or use `.env` file:
```bash
export ANTHROPIC_API_KEY="your-key"
```

### MoltWorker Secrets

All configured via `wrangler secret put`:

```bash
ANTHROPIC_API_KEY        # Required - Anthropic API key
MOLTBOT_GATEWAY_TOKEN    # Required - Gateway auth token
TELEGRAM_BOT_TOKEN       # Required - Telegram bot token
CF_ACCESS_TEAM_DOMAIN    # Required - Cloudflare Access domain
CF_ACCESS_AUD            # Required - Cloudflare Access AUD
R2_ACCESS_KEY_ID         # Optional - R2 persistence
R2_SECRET_ACCESS_KEY     # Optional - R2 persistence
CF_ACCOUNT_ID            # Optional - R2 persistence
DEV_MODE                 # Optional - Enable dev features
DEBUG_ROUTES             # Optional - Enable /debug/* routes
```

---

## Backup & Recovery

### Local Bot Data

Location: `C:\Users\<username>\.clawdbot\`

Backup the entire `.clawdbot` directory.

### MoltWorker Data

Data is automatically synced to R2 every 5 minutes (if R2 is configured).

Manual backup:
1. Access admin UI at `/_admin/`
2. Export configuration

### Restore from R2

MoltWorker automatically restores from R2 on container startup if:
- R2 is configured
- R2 backup exists and is newer than local data
