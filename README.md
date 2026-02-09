# Agent PEF

Three-bot Telegram orchestration with Cloudflare Workers and local Clawdbot instances.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                      Telegram Group: pef-agents                          │
│                                                                          │
│   @agentpeflaptopbot       @agentpefstationbot       @agentpefbot        │
│   (Laptop)                 (Station PC)              (Cloud)             │
│   Port 18790               Port 18791                Port 18789          │
│         │                        │                        │              │
└─────────┼────────────────────────┼────────────────────────┼──────────────┘
          │                        │                        │
          ▼                        ▼                        ▼
   ┌─────────────┐          ┌─────────────┐         ┌──────────────────┐
   │ Laptop      │          │ Station PC  │         │ Cloudflare       │
   │ • Files     │          │ • Files     │         │ • Always-on      │
   │ • Pro sub   │          │ • Pro sub   │         │ • R2 storage     │
   │ • Dev tools │          │ • Dev tools │         │ • API billing    │
   └─────────────┘          └─────────────┘         └──────────────────┘
```

## Cloning

Each bot directory is a **git submodule**. Clone with all submodules:

```bash
git clone --recurse-submodules https://github.com/zepef/agent-pef.git
```

Or clone a single bot repo directly:

```bash
git clone https://github.com/zepef/pefstationbot.git
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

## Quick Start

### Laptop Bot

```powershell
cd peflaptopbot
.\scripts\openclawd.ps1 start peflaptopbot
```

### Station Bot

```powershell
cd pefstationbot
.\scripts\openclawd.ps1 start pefstationbot
```

### Cloud Bot

```powershell
cd pefcloudbot
npm run deploy
```

## Documentation

| Document | Description |
|----------|-------------|
| [INSTALL.md](docs/INSTALL.md) | **Full installation guide** - start here |
| [SETUP.md](docs/SETUP.md) | Detailed configuration reference |
| [USER_MANUAL.md](docs/USER_MANUAL.md) | Daily operations guide |
| [Laptop bot identity](peflaptopbot/docs/IDENTITY.md) | Laptop bot persona |
| [Station bot identity](pefstationbot/docs/IDENTITY.md) | Station bot persona |
| [Cloud bot identity](pefcloudbot/docs/IDENTITY.md) | Cloud bot persona |
| [Laptop bot setup](peflaptopbot/docs/SETUP.md) | Laptop bot setup guide |
| [Station bot setup](pefstationbot/docs/SETUP.md) | Station bot setup guide |
| [OpenClawd CLI](peflaptopbot/docs/CLI.md) | Local bot CLI reference |
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
├── peflaptopbot/          # ⟶ submodule: github.com/zepef/peflaptopbot
├── pefstationbot/         # ⟶ submodule: github.com/zepef/pefstationbot
└── pefcloudbot/           # ⟶ submodule: github.com/zepef/pefcloudbot
```

## Requirements

- Node.js 22+
- Git for Windows
- Cloudflare Workers Paid ($5/mo)
- Anthropic API key
- Three Telegram bots (via @BotFather)

## License

MIT
