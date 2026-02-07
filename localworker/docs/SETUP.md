# peflaptopbot Local Setup Guide

This guide explains how to run `@peflaptopbot` locally using openclaw with Cloudflare Tunnel for Telegram webhook support.

## Prerequisites

- Node.js installed
- openclaw installed globally: `npm install -g openclaw`
- cloudflared installed: `npm install -g cloudflared` or download from https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/

## Configuration

The openclaw config is located at `C:\Users\zepef\.clawdbot\clawdbot.json`.

### Key Telegram Settings

```json
{
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "open",
      "botToken": "<BOT_TOKEN>",
      "replyToMode": "first",
      "groups": {
        "*": {
          "requireMention": false,
          "enabled": true
        }
      },
      "allowFrom": ["*"],  // SECURITY: Replace "*" with specific Telegram user IDs in production
      "groupPolicy": "open",
      "streamMode": "partial",
      "webhookUrl": "<TUNNEL_URL>/telegram-webhook"
    }
  },
  "gateway": {
    "port": 18790,
    "mode": "local"
  }
}
```

**Important:** The webhook path must be `/telegram-webhook` (with hyphen), NOT `/webhooks/telegram` or `/telegram/webhook`.

## Setup Steps

### 1. Start Cloudflare Tunnel (Terminal 1)

```powershell
cloudflared tunnel --url http://localhost:18790
```

This creates a temporary public URL like:
```
https://random-words-here.trycloudflare.com
```

Copy this URL - you'll need it for the next steps.

### 2. Update openclaw Config

Edit `C:\Users\zepef\.clawdbot\clawdbot.json` and update the `webhookUrl`:

```json
"webhookUrl": "https://<YOUR-TUNNEL-URL>/telegram-webhook"
```

### 3. Start openclaw Gateway (Terminal 2)

```powershell
openclaw gateway --port 18790 --verbose
```

Look for this line to confirm Telegram is active:
```
[telegram] [default] starting provider (@peflaptopbot)
```

### 4. Set Telegram Webhook (Terminal 3)

```powershell
Invoke-RestMethod -Method Post "https://api.telegram.org/bot<BOT_TOKEN>/setWebhook?url=https://<YOUR-TUNNEL-URL>/telegram-webhook"
```

### 5. Verify Webhook

```powershell
Invoke-RestMethod "https://api.telegram.org/bot<BOT_TOKEN>/getWebhookInfo" | ConvertTo-Json -Depth 3
```

Check that:
- `url` matches your tunnel URL
- `last_error_message` is empty or null
- `pending_update_count` is 0 (after successful delivery)

### 6. Test

Send a DM to `@peflaptopbot` in Telegram. You should see activity in the gateway logs and receive a response.

## Stopping

1. **Delete webhook first** (so Telegram doesn't queue messages):
   ```powershell
   Invoke-RestMethod "https://api.telegram.org/bot<BOT_TOKEN>/deleteWebhook"
   ```

2. Stop the gateway (Ctrl+C in Terminal 2)
3. Stop cloudflared (Ctrl+C in Terminal 1)

## Troubleshooting

### 405 Method Not Allowed

Wrong webhook path. Use `/telegram-webhook` (with hyphen).

### No webhook activity in gateway logs

1. Check cloudflared is running and shows the tunnel URL
2. Verify webhook URL matches tunnel URL exactly
3. Check `getWebhookInfo` for errors

### Messages received but not dispatched (polling mode)

This is a known issue with older clawdbot polling mode (fixed in openclaw v2026.2.3+). Use webhook mode with Cloudflare Tunnel instead.

### Gateway won't start - port in use

Kill existing processes:
```powershell
taskkill /f /im node.exe
```

Or find and kill the specific process:
```powershell
netstat -ano | findstr :18790
taskkill /PID <PID> /F
```

## Quick Start Commands

```powershell
# Terminal 1 - Tunnel
cloudflared tunnel --url http://localhost:18790

# Terminal 2 - Gateway
openclaw gateway --port 18790 --verbose

# Terminal 3 - Set webhook (replace URL)
Invoke-RestMethod -Method Post "https://api.telegram.org/bot8594075695:AAEbsUx01Yu9GO7iUcxT7PQMM0D2ATlMWP4/setWebhook?url=https://<TUNNEL-URL>/telegram-webhook"
```

## Bot Token

- **Bot:** @peflaptopbot
- **Token:** `8594075695:AAEbsUx01Yu9GO7iUcxT7PQMM0D2ATlMWP4`

## Running as Windows Service (Auto-Restart)

To run the gateway as a Windows service that auto-restarts on crash and starts on boot:

### Install Service

Run PowerShell as Administrator:

```powershell
.\scripts\install-gateway-service.ps1
```

This will:
- Download NSSM (Non-Sucking Service Manager) if needed
- Create a Windows service named `peflaptopbot`
- Configure auto-restart on crash (5 second delay)
- Set up log rotation
- Start the service

### Service Management

```powershell
# Check status
nssm status peflaptopbot

# View logs
Get-Content "$env:USERPROFILE\.clawdbot\logs\gateway.log" -Tail 50

# Restart
nssm restart peflaptopbot

# Stop
nssm stop peflaptopbot

# Uninstall
.\scripts\uninstall-gateway-service.ps1
```

### Log Files

- `%USERPROFILE%\.clawdbot\logs\gateway.log` - Standard output
- `%USERPROFILE%\.clawdbot\logs\gateway-error.log` - Error output

## Notes

- The Cloudflare quick tunnel URL changes each time you restart cloudflared
- For a permanent URL, create a named Cloudflare Tunnel with your Cloudflare account
- The gateway must be running before setting the webhook, otherwise Telegram will get connection errors
- When using the Windows service, logs go to `%USERPROFILE%\.clawdbot\logs\` instead of the terminal
