# OpenClaw Local Bot

Run [@agentpeflaptopbot](https://t.me/agentpeflaptopbot) locally using [OpenClaw](https://github.com/openclaw/openclaw) with Cloudflare Tunnel for Telegram webhook support.

## Prerequisites

- **Node.js** 22+
- **openclaw** installed globally: `npm install -g openclaw`
- **cloudflared** installed: `npm install -g cloudflared` or [download](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/)

## Quick Start

```powershell
# Create a bot profile
.\scripts\openclawd.ps1 create-profile

# Start the bot (launches tunnel + gateway + health monitor)
.\scripts\openclawd.ps1 start peflaptopbot

# Check status
.\scripts\openclawd.ps1 status peflaptopbot

# Stop
.\scripts\openclawd.ps1 stop peflaptopbot
```

## Documentation

| Document | Description |
|----------|-------------|
| [docs/SETUP.md](docs/SETUP.md) | Full local bot setup guide (tunnel, webhook, service) |
| [docs/CLI.md](docs/CLI.md) | OpenClawd CLI reference (commands, profiles, health monitoring) |
| [docs/IDENTITY.md](docs/IDENTITY.md) | Bot persona and interaction guidelines |

## How It Works

The orchestrator script (`scripts/openclawd.ps1`) manages three processes:

1. **Cloudflare Tunnel** -- exposes the local gateway to the internet
2. **OpenClaw Gateway** -- runs the bot and connects to Telegram
3. **Health Monitor** -- checks tunnel, gateway, and webhook every 30 seconds with auto-recovery
