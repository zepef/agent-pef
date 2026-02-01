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
clawdbot gateway --port 18789 --verbose
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
| [IDENTITY_LOCAL.md](docs/IDENTITY_LOCAL.md) | Local bot persona |
| [IDENTITY_CLOUD.md](docs/IDENTITY_CLOUD.md) | Cloud bot persona |
| [AGENTS.md](AGENTS.md) | Safety rules and boundaries |

## Project Structure

```
agent-pef/
├── README.md              # This file
├── AGENTS.md              # Safety rules (used by bots)
├── .claude/               # Claude Code project settings
├── docs/                  # Documentation
│   ├── INSTALL.md         # Installation guide
│   ├── SETUP.md           # Configuration details
│   ├── USER_MANUAL.md     # Operations manual
│   ├── IDENTITY_LOCAL.md  # Local bot persona
│   └── IDENTITY_CLOUD.md  # Cloud bot persona
└── moltworker/            # Cloudflare Workers project
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
