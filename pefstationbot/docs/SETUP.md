# pefstationbot Local Setup Guide

This guide explains how to run `@agentpefstationbot` locally on the station PC using openclaw with Cloudflare Tunnel for Telegram webhook support.

## Prerequisites

- Node.js installed
- openclaw installed globally: `npm install -g openclaw`
- cloudflared installed: `npm install -g cloudflared` or download from https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/

## Configuration

The openclaw config is located at `C:\Users\clt\.clawdbot\clawdbot.json`.

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
      "allowFrom": ["*"],
      "groupPolicy": "open",
      "streamMode": "partial",
      "webhookUrl": "<TUNNEL_URL>/telegram-webhook"
    }
  },
  "gateway": {
    "port": 18791,
    "mode": "local"
  }
}
```

**Important:** The webhook path must be `/telegram-webhook` (with hyphen), NOT `/webhooks/telegram` or `/telegram/webhook`.

## Setup Steps

### 1. Start Cloudflare Tunnel (Terminal 1)

```powershell
cloudflared tunnel --url http://localhost:18791
```

This creates a temporary public URL like:
```
https://random-words-here.trycloudflare.com
```

Copy this URL - you'll need it for the next steps.

### 2. Update openclaw Config

Edit `C:\Users\clt\.clawdbot\clawdbot.json` and update the `webhookUrl`:

```json
"webhookUrl": "https://<YOUR-TUNNEL-URL>/telegram-webhook"
```

### 3. Start openclaw Gateway (Terminal 2)

```powershell
openclaw gateway --port 18791 --verbose
```

Look for this line to confirm Telegram is active:
```
[telegram] [default] starting provider (@agentpefstationbot)
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

Send a DM to `@agentpefstationbot` in Telegram. You should see activity in the gateway logs and receive a response.

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

### Gateway won't start - port in use

Kill existing processes:
```powershell
taskkill /f /im node.exe
```

Or find and kill the specific process:
```powershell
netstat -ano | findstr :18791
taskkill /PID <PID> /F
```

## Quick Start Commands

```powershell
# Terminal 1 - Tunnel
cloudflared tunnel --url http://localhost:18791

# Terminal 2 - Gateway
openclaw gateway --port 18791 --verbose

# Terminal 3 - Set webhook (replace URL and TOKEN)
Invoke-RestMethod -Method Post "https://api.telegram.org/bot<BOT_TOKEN>/setWebhook?url=https://<TUNNEL-URL>/telegram-webhook"
```

## Running as Windows Service (Auto-Restart)

To run the gateway as a Windows service that auto-restarts on crash and starts on boot:

### Install Service

Run PowerShell as Administrator:

```powershell
.\scripts\install-gateway-service.ps1
```

This will:
- Download NSSM (Non-Sucking Service Manager) if needed
- Create a Windows service named `pefstationbot`
- Configure auto-restart on crash (5 second delay)
- Set up log rotation
- Start the service

### Service Management

```powershell
# Check status
nssm status pefstationbot

# View logs
Get-Content "$env:USERPROFILE\.clawdbot\logs\gateway.log" -Tail 50

# Restart
nssm restart pefstationbot

# Stop
nssm stop pefstationbot

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
