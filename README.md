# Agent PEF

Dual-bot Telegram orchestration with Cloudflare Workers and local Clawdbot.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Telegram Group: pef-agents                  │
│                                                          │
│    @agentpeflaptopbot          @agentpefbot              │
│    (Local Clawdbot)            (MoltWorker)              │
│          │                          │                    │
└──────────┼──────────────────────────┼────────────────────┘
           │                          │
           ▼                          ▼
    ┌─────────────┐           ┌──────────────────┐
    │ Local PC    │           │ Cloudflare       │
    │ • Files     │           │ • Always-on      │
    │ • Pro sub   │           │ • R2 storage     │
    │ • Dev tools │           │ • API billing    │
    └─────────────┘           └──────────────────┘
```

## Quick Start

### Local Bot

```powershell
cd localworker
.\scripts\openclawd.ps1 start peflaptopbot
```

### Cloud Bot

```powershell
cd moltworker
npm run deploy
```

## Documentation

| Document | Description |
|----------|-------------|
| [INSTALL.md](docs/INSTALL.md) | **Full installation guide** - start here |
| [SETUP.md](docs/SETUP.md) | Detailed configuration reference |
| [USER_MANUAL.md](docs/USER_MANUAL.md) | Daily operations guide |
| [Local bot identity](localworker/docs/IDENTITY.md) | Local bot persona |
| [Cloud bot identity](moltworker/docs/IDENTITY.md) | Cloud bot persona |
| [Local bot setup](localworker/docs/SETUP.md) | Local bot setup guide |
| [OpenClawd CLI](localworker/docs/CLI.md) | Local bot CLI reference |
| [AGENTS.md](AGENTS.md) | Safety rules and boundaries |

## Project Structure

```
agent-pef/
├── README.md              # This file
├── AGENTS.md              # Safety rules (used by bots)
├── .claude/               # Claude Code project settings
├── docs/                  # Shared documentation
│   ├── INSTALL.md         # Installation guide
│   ├── SETUP.md           # Configuration details
│   └── USER_MANUAL.md     # Operations manual
├── localworker/           # Local bot (openclaw + Cloudflare Tunnel)
│   ├── README.md          # Local bot overview
│   ├── docs/              # Local bot documentation
│   │   ├── IDENTITY.md    # Bot persona
│   │   ├── SETUP.md       # Setup guide
│   │   └── CLI.md         # CLI reference
│   └── scripts/           # Orchestration scripts
│       ├── openclawd.ps1
│       └── openclawd-lib.ps1
└── moltworker/            # Cloud bot (Cloudflare Workers)
    ├── docs/
    │   └── IDENTITY.md    # Bot persona
    ├── Dockerfile
    ├── start-moltbot.sh
    ├── wrangler.jsonc
    └── src/
```

## Requirements

- Node.js 22+
- Git for Windows
- Cloudflare Workers Paid ($5/mo)
- Anthropic API key
- Two Telegram bots (via @BotFather)

## License

MIT
