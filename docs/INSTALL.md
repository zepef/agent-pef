# Installation Guide - Agent PEF

Complete step-by-step guide to replicate this setup on a new machine.

## Prerequisites

### Required Software

| Software | Version | Download |
|----------|---------|----------|
| Node.js | 22+ | https://nodejs.org/ |
| Git for Windows | Latest | https://git-scm.com/download/win |
| Docker Desktop | Latest | https://www.docker.com/products/docker-desktop/ |
| Wrangler CLI | Latest | `npm install -g wrangler` |

### Required Accounts

| Service | Purpose | URL |
|---------|---------|-----|
| Cloudflare | Workers hosting | https://dash.cloudflare.com/ |
| Anthropic | API access | https://console.anthropic.com/ |
| Telegram | Bot creation | https://t.me/BotFather |
| GitHub | Code repository | https://github.com/ |

---

## Part 1: System Configuration (Windows)

### 1.1 Set Environment Variables

Open PowerShell as Administrator and run:

```powershell
# Add npm global binaries to PATH
[Environment]::SetEnvironmentVariable("PATH", "$([Environment]::GetEnvironmentVariable('PATH', 'User'));C:\Users\$env:USERNAME\AppData\Roaming\npm", "User")

# Set Git Bash path for Claude Code
[Environment]::SetEnvironmentVariable("CLAUDE_CODE_GIT_BASH_PATH", "D:\Program Files\Git\bin\bash.exe", "User")
```

> **Note**: Adjust `D:\Program Files\Git` if Git is installed elsewhere.

### 1.2 Restart Terminal

Close and reopen PowerShell for changes to take effect.

### 1.3 Verify

```powershell
# Check npm is in PATH
npm --version

# Check Git Bash path
echo $env:CLAUDE_CODE_GIT_BASH_PATH
```

---

## Part 2: Clone Repository

```powershell
cd E:\Projects  # or your preferred directory
git clone https://github.com/zepef/agent-pef.git
cd agent-pef
```

---

## Part 3: Install Clawdbot (Local Bot)

### 3.1 Install Globally

```powershell
npm install -g clawdbot
```

### 3.2 Verify Installation

```powershell
clawdbot --version
# Expected: 2026.1.24-3 or newer
```

### 3.3 Run Initial Setup

```powershell
clawdbot doctor --fix
```

---

## Part 4: Create Telegram Bots

### 4.1 Create Bots via @BotFather

1. Open Telegram, message @BotFather
2. Send `/newbot` for each bot:

| Bot | Suggested Name | Purpose |
|-----|----------------|---------|
| Local | `agent-pef-bot-laptop` | Local machine bot |
| Cloud | `agent-pef-bot-cloud` | Cloudflare Workers bot |

3. **Save both tokens securely**

### 4.2 Disable Privacy Mode (REQUIRED)

For **each** bot:

1. Message @BotFather
2. `/mybots` → Select bot → **Bot Settings** → **Group Privacy** → **Turn off**

### 4.3 Verify Privacy Mode

```bash
# Replace <TOKEN> with your bot token
curl -s "https://api.telegram.org/bot<TOKEN>/getMe" | grep can_read_all_group_messages
# Should show: "can_read_all_group_messages":true
```

---

## Part 5: Configure Local Bot

### 5.1 Edit Configuration

Location: `C:\Users\<username>\.clawdbot\clawdbot.json`

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

> **Important**: Do NOT set `webhookUrl` - polling mode is required.

### 5.2 Start Local Gateway

```powershell
clawdbot gateway --port 18789 --verbose
```

Expected output:
```
[telegram] [default] starting provider (@yourbotname)
[gateway] listening on ws://127.0.0.1:18789
```

---

## Part 6: Deploy MoltWorker (Cloud Bot)

### 6.1 Install Dependencies

```powershell
cd E:\Projects\agent-pef\moltworker
npm install
```

### 6.2 Login to Cloudflare

```powershell
npx wrangler login
```

### 6.3 Create R2 Bucket

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/) → R2
2. Create bucket named `moltbot-data`
3. Create API token with **Object Read & Write** permissions
4. Save the Access Key ID and Secret Access Key

### 6.4 Configure Secrets

Run each command and enter the value when prompted:

```powershell
# Required
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put TELEGRAM_BOT_TOKEN        # Cloud bot token
npx wrangler secret put MOLTBOT_GATEWAY_TOKEN     # Generate: 64 random hex chars

# Cloudflare Access (for admin UI protection)
npx wrangler secret put CF_ACCESS_TEAM_DOMAIN     # e.g., yourteam.cloudflareaccess.com
npx wrangler secret put CF_ACCESS_AUD             # Application AUD from Zero Trust

# R2 Storage (for persistence)
npx wrangler secret put R2_ACCESS_KEY_ID
npx wrangler secret put R2_SECRET_ACCESS_KEY
npx wrangler secret put CF_ACCOUNT_ID

# Optional
npx wrangler secret put DEV_MODE                  # "true" for dev features
npx wrangler secret put DEBUG_ROUTES              # "true" for /debug/* routes
```

#### Generate Gateway Token

```powershell
# PowerShell - generate 64-char hex token
-join ((48..57) + (97..102) | Get-Random -Count 64 | % {[char]$_})
```

### 6.5 Setup Cloudflare Access

1. Go to [Zero Trust Dashboard](https://one.dash.cloudflare.com/) → Access → Applications
2. Create **Self-hosted** application
3. Application domain: `moltbot-sandbox.<your-subdomain>.workers.dev`
4. Add policy: Allow your email
5. Copy **Application Audience (AUD)** tag

### 6.6 Deploy

```powershell
npm run deploy
```

### 6.7 Verify Deployment

```powershell
# Check status
curl https://moltbot-sandbox.<subdomain>.workers.dev/api/status

# Check Telegram config
curl https://moltbot-sandbox.<subdomain>.workers.dev/api/telegram-status
```

---

## Part 7: Create Telegram Group

1. Create new Telegram group (e.g., "pef-agents")
2. Add both bots to the group
3. Send a test message
4. Verify both bots receive it

---

## Part 8: Verification Checklist

### Local Bot
- [ ] `clawdbot --version` works
- [ ] Gateway starts without errors
- [ ] `[telegram] starting provider` appears in logs
- [ ] DM to bot gets response
- [ ] Group messages visible (privacy mode off)

### Cloud Bot
- [ ] `npm run deploy` succeeds
- [ ] `/api/status` returns `{"ok":true,"status":"running"}`
- [ ] `/api/telegram-status` shows `hasTelegramTokenEnv: true`
- [ ] DM to bot gets response
- [ ] Group messages visible

### Integration
- [ ] Both bots in same Telegram group
- [ ] Both bots see group messages
- [ ] Bots can respond to each other

---

## Troubleshooting

### "clawdbot: command not found"

```powershell
# Add npm to PATH for current session
$env:PATH += ";C:\Users\$env:USERNAME\AppData\Roaming\npm"

# Or use full path
& "C:\Users\$env:USERNAME\AppData\Roaming\npm\clawdbot.cmd" --version
```

### "cygpath: command not found"

```powershell
# Set Git Bash path
$env:CLAUDE_CODE_GIT_BASH_PATH = "D:\Program Files\Git\bin\bash.exe"
```

### PTY spawn failed

```powershell
# Reinstall clawdbot with optional dependencies
npm install -g clawdbot

# Install Windows PTY manually if needed
npm install --prefix "$env:APPDATA\npm\node_modules\clawdbot" @lydell/node-pty-win32-x64
```

### Gateway already running

```powershell
# Find and kill existing process
Get-Process -Name node | Where-Object {$_.CommandLine -like "*clawdbot*"} | Stop-Process -Force

# Or by PID (shown in error message)
Stop-Process -Id <PID> -Force
```

### Bot not receiving group messages

1. Check privacy mode is **OFF** via @BotFather
2. Verify with API: `curl "https://api.telegram.org/bot<TOKEN>/getMe"`
3. `can_read_all_group_messages` must be `true`

### MoltWorker process keeps failing

```powershell
# Check detailed logs
curl "https://moltbot-sandbox.<subdomain>.workers.dev/api/telegram-status"

# Force restart
curl -X POST "https://moltbot-sandbox.<subdomain>.workers.dev/api/restart?token=<GATEWAY_TOKEN>"
```

---

## Quick Reference

### URLs

| Resource | URL |
|----------|-----|
| GitHub Repo | https://github.com/zepef/agent-pef |
| MoltWorker | https://moltbot-sandbox.zepef.workers.dev |
| Admin UI | https://moltbot-sandbox.zepef.workers.dev/_admin/ |
| Local Gateway | ws://127.0.0.1:18789 |

### Key Files

| File | Purpose |
|------|---------|
| `~/.clawdbot/clawdbot.json` | Local bot config |
| `moltworker/start-moltbot.sh` | Container startup |
| `moltworker/wrangler.jsonc` | Cloudflare config |
| `AGENTS.md` | Safety rules |

### Commands

```powershell
# Start local bot
clawdbot gateway --port 18789 --verbose

# Deploy cloud bot
cd moltworker && npm run deploy

# View cloud logs
npx wrangler tail
```
