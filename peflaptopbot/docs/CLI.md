# OpenClawd CLI

A comprehensive orchestration system for running Clawdbot locally with automatic Cloudflare Tunnel management, dynamic config updates, health monitoring with auto-recovery, and multi-profile support.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     OpenClawd Orchestrator                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐          │
│  │ cloudflared │───►│   Config    │───►│   Gateway   │          │
│  │   Tunnel    │    │   Manager   │    │   Process   │          │
│  └─────────────┘    └─────────────┘    └─────────────┘          │
│         │                  │                  │                   │
│         ▼                  ▼                  ▼                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                   Health Monitor                         │    │
│  │  • Tunnel URL ping (every 30s)                          │    │
│  │  • Gateway process check                                 │    │
│  │  • Webhook validation                                    │    │
│  │  • Auto-recovery on failure                             │    │
│  └─────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

## Quick Start

```powershell
# 1. First time setup - create a profile
.\scripts\openclawd.ps1 create-profile

# 2. Start your bot
.\scripts\openclawd.ps1 start peflaptopbot

# 3. Check status
.\scripts\openclawd.ps1 status peflaptopbot

# 4. Stop when done
.\scripts\openclawd.ps1 stop peflaptopbot
```

## Commands

| Command | Description |
|---------|-------------|
| `start [profile]` | Start orchestrator with profile |
| `stop [profile]` | Graceful stop (deletes webhook first) |
| `restart [profile]` | Stop then start |
| `status [profile]` | Show status, tunnel URL, webhook info |
| `health [profile]` | Run comprehensive health check with pass/fail diagnostics |
| `logs [profile]` | Tail orchestrator logs |
| `profiles` | List available profiles |
| `create-profile` | Interactive profile creation |

## Daily Usage

### Start Bot

```powershell
cd E:\Projects\agent-pef
.\scripts\openclawd.ps1 start peflaptopbot
```

Output shows:
- Tunnel URL (auto-generated)
- Webhook registration status
- Gateway process status

### Check Status

```powershell
.\scripts\openclawd.ps1 status peflaptopbot
```

Shows:
- Profile name and port
- Tunnel URL (current)
- Gateway process status
- Webhook registration status
- Last health check result

### Run Health Check

Use the `health` command to verify everything is properly configured and working:

```powershell
.\scripts\openclawd.ps1 health peflaptopbot
```

This runs 8 comprehensive checks and reports pass/fail for each:

| Check | What It Verifies |
|-------|------------------|
| Profile Configuration | Bot token format, port validity |
| Tunnel Process | cloudflared process is running |
| Tunnel URL Configuration | URL is saved and in correct format |
| Tunnel Reachability | HTTP request to tunnel succeeds, webhook endpoint accessible |
| Tunnel Log Errors | No recent connection errors in cloudflared log |
| Gateway Process | Gateway is running and listening on port |
| Telegram Webhook | Webhook registered and matches current tunnel URL |
| Health Monitor | Background health monitor is running |

**Example Output:**
```
========================================
  OpenClawd Health Check
========================================

[1/8] Profile Configuration
  [PASS] Profile Configuration
  Bot token: Valid format
  Port: 18790

[2/8] Tunnel Process
  [PASS] Tunnel Process
  Process: Running (PID: 12345)

[3/8] Tunnel URL Configuration
  [PASS] Tunnel URL Configuration
  URL: https://abc-123-xyz.trycloudflare.com
  Format: Valid Cloudflare tunnel URL

[4/8] Tunnel Reachability
  [PASS] Tunnel Reachability
  HTTP GET: 200 OK
  Webhook endpoint: Reachable (405)

[5/8] Tunnel Log Errors
  [PASS] Tunnel Log Errors
  No recent errors detected

[6/8] Gateway Process
  [PASS] Gateway Process
  Process: Running (PID: 12346)
  Port 18790: Listening

[7/8] Telegram Webhook
  [PASS] Telegram Webhook
  Registered URL: https://abc-123-xyz.trycloudflare.com/telegram-webhook
  URL Match: YES - webhook matches tunnel

[8/8] Health Monitor
  [PASS] Health Monitor
  Process: Running (PID: 12347)
  Check Interval: 30 seconds

========================================
  Summary
========================================

Checks Passed: 8/8

HEALTH STATUS: HEALTHY

All systems operational. Bot should be receiving messages.
```

**Health Status Levels:**
- **HEALTHY** - All checks passed, bot is fully operational
- **DEGRADED** - Bot is running but some checks failed (review warnings)
- **UNHEALTHY** - Critical failures, bot is not operational

### View Logs

```powershell
# Tail orchestrator log
.\scripts\openclawd.ps1 logs peflaptopbot

# View specific log file
Get-Content "$env:USERPROFILE\.clawdbot\logs\peflaptopbot\gateway.log" -Tail 50 -Wait
```

### Stop Bot

```powershell
.\scripts\openclawd.ps1 stop peflaptopbot
```

This will:
1. Stop health monitor
2. Delete Telegram webhook (prevents queued messages)
3. Stop gateway process
4. Stop cloudflared tunnel

### Restart

```powershell
.\scripts\openclawd.ps1 restart peflaptopbot
```

## Multi-Profile Support

### List Profiles

```powershell
.\scripts\openclawd.ps1 profiles
```

### Create New Profile

```powershell
.\scripts\openclawd.ps1 create-profile
```

Interactive prompts:
- Profile name: `testbot`
- Bot token: `123456:ABC...`
- Port: `18791`
- Display name: `Test Bot`

### Run Multiple Bots

Each bot needs a different port:

```powershell
.\scripts\openclawd.ps1 start peflaptopbot  # port 18790
.\scripts\openclawd.ps1 start testbot       # port 18791
```

## Profile Configuration

Profiles are stored at `%USERPROFILE%\.clawdbot\profiles\<name>.json`:

```json
{
  "name": "peflaptopbot",
  "displayName": "PEF Laptop Bot",
  "port": 18790,
  "botToken": "8594075695:AAE...",
  "telegram": {
    "dmPolicy": "open",
    "groupPolicy": "open",
    "allowFrom": ["*"],  // SECURITY: Replace "*" with specific Telegram user IDs in production
    "groups": {
      "*": {
        "requireMention": false,
        "enabled": true
      }
    },
    "replyToMode": "first",
    "streamMode": "partial"
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-opus-4-5"
      }
    }
  }
}
```

### Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `name` | Profile identifier | Required |
| `displayName` | Human-readable name | Same as name |
| `port` | Gateway port | 18790 |
| `botToken` | Telegram bot token | Required |
| `telegram.dmPolicy` | DM access policy | "open" |
| `telegram.groupPolicy` | Group access policy | "open" |
| `telegram.allowFrom` | Allowed user IDs (restrict to specific IDs in production) | ["*"] |
| `telegram.replyToMode` | Reply threading mode | "first" |
| `telegram.streamMode` | Streaming mode | "partial" |

## Windows Service

### Install as Service

```powershell
# Run as Administrator
.\scripts\install-openclawd-service.ps1 -Profile peflaptopbot
```

The service will:
- Auto-start on Windows boot
- Auto-restart on crash
- Run as the current user

### Manage Service

```powershell
# Check status
nssm status openclawd-peflaptopbot

# Stop service
nssm stop openclawd-peflaptopbot

# Start service
nssm start openclawd-peflaptopbot

# Restart service
nssm restart openclawd-peflaptopbot
```

### Remove Service

```powershell
# Run as Administrator
.\scripts\uninstall-openclawd-service.ps1 -Profile peflaptopbot
```

## Log Files

Logs are stored at `%USERPROFILE%\.clawdbot\logs\<profile>\`:

| File | Content |
|------|---------|
| `orchestrator.log` | Health checks, restarts, errors |
| `gateway.log` | Clawdbot gateway output, message processing |
| `gateway-error.log` | Gateway stderr output |
| `tunnel.log` | Cloudflared output, tunnel URL |

### View Logs

```powershell
# Orchestrator log (health checks, restarts)
Get-Content "$env:USERPROFILE\.clawdbot\logs\peflaptopbot\orchestrator.log" -Tail 100

# Gateway log (message processing)
Get-Content "$env:USERPROFILE\.clawdbot\logs\peflaptopbot\gateway.log" -Tail 100

# Tunnel log
Get-Content "$env:USERPROFILE\.clawdbot\logs\peflaptopbot\tunnel.log" -Tail 50
```

## Health Monitoring

The orchestrator runs a background health monitor that checks every 30 seconds:

1. **Tunnel Health**: HTTP GET to tunnel URL (expect 200 or 405)
2. **Gateway Health**: Check process by PID
3. **Webhook Validation**: Verify registered URL matches current tunnel

### Auto-Recovery

| Condition | Action |
|-----------|--------|
| Tunnel unreachable (3 consecutive failures) | Full restart (new tunnel URL) |
| Tunnel log errors (3+ errors in 60s) | Full restart (new tunnel URL) |
| Gateway process died | Restart gateway only |
| Webhook URL mismatch | Re-register webhook |

**Detected Tunnel Errors:**
The health monitor watches the tunnel log for these error patterns:
- `ERR Serve tunnel error`
- `control stream encountered a failure`
- `connection refused`
- `context deadline exceeded`

When 3 or more of these errors occur within 60 seconds, the orchestrator automatically triggers a full restart with a new tunnel URL.

### Tunnel URL Propagation

When a tunnel restarts (manually or via auto-recovery), the URL changes (e.g., `https://old-abc.trycloudflare.com` → `https://new-xyz.trycloudflare.com`). The orchestrator automatically:

1. **Detects new URL** - Parses cloudflared output for the new `.trycloudflare.com` URL
2. **Updates config** - Regenerates `~/.clawdbot/clawdbot.json` with new webhook URL
3. **Re-registers webhook** - Calls Telegram API to update webhook to new URL
4. **Verifies webhook** - Confirms Telegram received the update
5. **Restarts gateway** - Gateway loads fresh config with correct URL

This ensures messages continue flowing after any tunnel restart.

## Environment Variables

Override default settings via environment variables:

```powershell
$env:OPENCLAWD_PROFILE = "peflaptopbot"    # Default profile
$env:OPENCLAWD_HEALTH_INTERVAL = "60"       # Health check interval (seconds)
$env:OPENCLAWD_LOG_LEVEL = "debug"          # Log verbosity: debug, info, warn, error
```

## Troubleshooting

### Bot Not Responding

```powershell
# Run health check first to diagnose
.\scripts\openclawd.ps1 health peflaptopbot

# Check status
.\scripts\openclawd.ps1 status peflaptopbot

# Check webhook is registered
$token = "YOUR_BOT_TOKEN"
Invoke-RestMethod "https://api.telegram.org/bot$token/getWebhookInfo"

# Restart
.\scripts\openclawd.ps1 restart peflaptopbot
```

### Tunnel Keeps Dying

The health monitor automatically detects and recovers from tunnel failures. If issues persist:

- Run health check to see recent errors:
  ```powershell
  .\scripts\openclawd.ps1 health peflaptopbot
  ```
- Check internet connection
- Verify cloudflared is installed: `cloudflared --version`
- Check tunnel log for errors:
  ```powershell
  Get-Content "$env:USERPROFILE\.clawdbot\logs\peflaptopbot\tunnel.log" -Tail 50
  ```

**Common tunnel errors and what they mean:**
- `control stream encountered a failure` - Connection to Cloudflare dropped, will auto-reconnect
- `Serve tunnel error` - Tunnel service failed, triggers auto-restart
- `context deadline exceeded` - Timeout, usually recovers automatically

### Port Already in Use

```powershell
# Find process using port
netstat -ano | findstr :18790

# Kill it
taskkill /PID <PID> /F
```

### Health Monitor Not Recovering

```powershell
# Check orchestrator log
Get-Content "$env:USERPROFILE\.clawdbot\logs\peflaptopbot\orchestrator.log" -Tail 50

# Force full restart
.\scripts\openclawd.ps1 stop peflaptopbot
.\scripts\openclawd.ps1 start peflaptopbot
```

### Webhook Not Receiving Messages After Restart

If messages stop arriving after a tunnel restart, verify the webhook URL was updated:

```powershell
# Check current tunnel URL
Get-Content "$env:USERPROFILE\.clawdbot\pids\peflaptopbot-tunnel.url"

# Check webhook registered with Telegram
$token = "YOUR_BOT_TOKEN"
(Invoke-RestMethod "https://api.telegram.org/bot$token/getWebhookInfo").result.url

# They should match (with /telegram-webhook suffix)
# If not, restart to fix:
.\scripts\openclawd.ps1 restart peflaptopbot
```

Check orchestrator log for URL propagation:
```powershell
# Look for these log entries after restart:
# "New tunnel URL: https://..."
# "Updating clawdbot.json with new tunnel URL..."
# "Webhook registered: https://..."
# "Webhook verified - Telegram will send updates to new URL"
Get-Content "$env:USERPROFILE\.clawdbot\logs\peflaptopbot\orchestrator.log" -Tail 30
```

### Service Won't Start

```powershell
# Check service logs
Get-Content "$env:USERPROFILE\.clawdbot\logs\peflaptopbot\service-stderr.log" -Tail 50

# Check Windows Event Viewer for service errors
Get-EventLog -LogName Application -Source "openclawd-*" -Newest 10
```

## Dependencies

- **PowerShell 5.1+** (built into Windows)
- **cloudflared** - Cloudflare tunnel client
  ```powershell
  npm install -g cloudflared
  # or download from https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/
  ```
- **openclaw** - Telegram bot gateway
  ```powershell
  npm install -g openclaw
  ```
- **NSSM** (for Windows service) - Auto-downloaded during service installation

## File Structure

```
~/.clawdbot/
├── profiles/
│   ├── peflaptopbot.json    # Profile config
│   └── testbot.json         # Another profile
├── logs/
│   ├── peflaptopbot/
│   │   ├── orchestrator.log
│   │   ├── gateway.log
│   │   ├── gateway-error.log
│   │   └── tunnel.log
│   └── testbot/
│       └── ...
├── pids/
│   ├── peflaptopbot-tunnel.pid
│   ├── peflaptopbot-tunnel.url
│   ├── peflaptopbot-gateway.pid
│   └── peflaptopbot-health.pid
└── clawdbot.json            # Active config (managed by orchestrator)
```

## Startup Sequence

1. Load profile config
2. Start cloudflared tunnel in background
3. Parse output for tunnel URL (regex: `https://.*\.trycloudflare\.com`)
4. Wait for tunnel URL (timeout: 60s)
5. Generate `clawdbot.json` from profile + tunnel URL
6. Register webhook with Telegram API
7. Verify webhook registered
8. Start gateway process
9. Start health monitor background job
10. Write PID files for management

## Shutdown Sequence

1. Stop health monitor
2. Delete Telegram webhook (prevents queued messages)
3. Stop gateway process (graceful, then force after 10s)
4. Stop cloudflared process
5. Remove PID files
6. Log shutdown complete
