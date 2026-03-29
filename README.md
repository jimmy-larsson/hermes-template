# Hermes - AI Assistant Template

**Hermes** -- AI Assistant Template

An AI assistant that remembers your conversations, tracks your goals, and helps you stay organized. Like having a personal chief of staff who never forgets anything.

## Why Hermes?

Hermes extends Claude Code with capabilities designed for getting things done:

- **Session continuity** - Pick up where you left off, even days later. Every conversation builds on the last.
- **Goal tracking** - Set work and personal goals, Hermes monitors progress and nudges you forward.
- **Tool integrations** - Connect to Google Workspace, Microsoft 365, Atlassian, Slack, Linear, Notion, Telegram, and more.
- **Extensibility** - Add commands, agents, and skills tailored to your workflow. Create new capabilities with simple markdown files.
- **Thought partner** - Hermes pushes back on weak ideas, asks probing questions, and helps you think through decisions. Not just a yes-man.

## Quick Start with Claude Code

1. Clone this repository:
   ```bash
   git clone https://github.com/SterlingChin/marvin-template.git
   cd marvin-template
   ```

2. Open in Claude Code:
   ```bash
   claude
   ```

3. Ask Hermes to help you set up:
   > "Help me set up Hermes"

That's it. Hermes walks you through the rest: your profile, goals, workspace location, and optional integrations.

## Getting Started with GitHub Copilot CLI

Want to use Copilot CLI to set up Hermes quickly? Here's how:

### Prerequisites

- [GitHub Copilot CLI](https://cli.github.com/) installed and authenticated

### Quick Setup

Use these Copilot commands to get started:

```bash
# Navigate to your projects directory
gh copilot suggest "clone hermes template repository"

# Run the setup script
gh copilot suggest "run setup script for hermes"

# Start Hermes
gh copilot suggest "start hermes AI assistant"
```

The `.hermes/setup.sh` script handles the complete installation: prerequisites, workspace creation, profile setup, and shell aliases. Just follow the prompts to configure your AI assistant.

For additional integrations (Google Workspace, Slack, etc.), use:

```bash
gh copilot suggest "configure hermes integrations"
```

## What You Get

### Daily Workflow

Start your day with `/start` for a briefing: priorities, deadlines, progress toward goals. Work naturally throughout the day, Hermes remembers everything. End with `/end` to save context for next time.

Between sessions, `/update` saves progress without ending. `/sync` pulls new features from this template into your workspace.

### Commands

| Command | What It Does |
|---------|--------------|
| `/start` | Start your day with a briefing |
| `/end` | End session and save everything |
| `/update` | Quick checkpoint (save progress) |
| `/report` | Generate a weekly summary |
| `/commit` | Review and commit git changes |
| `/status` | Check integration & workspace health |
| `/sync` | Get updates from the template |
| `/help` | Show all commands and integrations |

### Integrations

Hermes connects to tools you already use:

| Integration | What It Provides |
|-------------|------------------|
| [Google Workspace](.hermes/integrations/google-workspace/) | Gmail, Calendar, Drive |
| [Microsoft 365](.hermes/integrations/ms365/) | Outlook, Calendar, OneDrive, Teams |
| [Atlassian](.hermes/integrations/atlassian/) | Jira, Confluence |
| [Slack](.hermes/integrations/slack/) | Channel monitoring, posting |
| [Linear](.hermes/integrations/linear/) | Issue tracking |
| [Notion](.hermes/integrations/notion/) | Page reading, database queries |
| [Telegram](.hermes/integrations/telegram/) | Chat with Hermes from your phone |
| [Parallel Search](.hermes/integrations/parallel-search/) | Web search capabilities |

Each integration includes setup instructions in its directory.

### Skills and Agents

Hermes uses a `.claude/` directory structure for extensibility:

- **Commands** (`.claude/commands/`) - User-triggered workflows you invoke with slash commands
- **Agents** (`.claude/agents/`) - Specialized subagents Hermes spawns for delegated work
- **Skills** (`.claude/skills/`) - Reusable capabilities Claude Code invokes contextually

Templates are included for each type. Just say "create a skill for X" and Hermes generates the file.

## How It Works

Hermes separates your workspace from the template:

```
~/hermes/                    Your workspace (your data lives here)
├── CLAUDE.md               Your profile and preferences
├── state/                  Your goals and priorities
├── sessions/               Your daily session logs
└── ...

~/marvin-template/          Template (get updates here)
├── .hermes/                Setup scripts and integrations
├── .claude/                Command and agent templates
└── ...
```

Your workspace holds all personal data. The template provides updates. Run `/sync` from your workspace to pull new features without overwriting your data.

## Migrating from Older Versions

If you were using Hermes before the workspace separation:

```bash
cd marvin-template
./.hermes/migrate.sh
```

The script copies your profile, goals, sessions, reports, and custom skills to a new workspace. Nothing is deleted from your old installation. Verify the new workspace works, then clean up the old one.

## Multi-User Deployment

Run multiple isolated Hermes instances on a single server with optional shared memory.

### Quick Start

```bash
# First run — creates config
./deploy/setup.sh ~/hermes

# Edit config
vim ~/hermes/config.yml

# Second run — generates and starts everything
./deploy/setup.sh ~/hermes
```

### Requirements

- Docker and Docker Compose v2
- Python 3 (for config parsing)
- SSH access to the host (for user access)

### What setup.sh does

1. Reads `config.yml` — users, scopes, Mimir toggle
2. Generates `docker-compose.yml` — one container per user + optional Mimir
3. Creates per-user workspaces — Hermes template copy with personalized CLAUDE.md
4. Generates API keys and `.mcp.json` (if Mimir enabled)
5. Builds and starts Docker containers

### Accessing your container

```bash
# From the host — attach to tmux session
docker exec -it jimmy-hermes tmux attach -t hermes

# Or source the wrapper and use the hermes command
source ~/hermes/data/users/jimmy/hermes-wrapper.sh
hermes            # attach to tmux
hermes research   # open named Claude Code session
```

### Adding a user

1. Edit `~/hermes/config.yml` — add user entry
2. Re-run `./deploy/setup.sh ~/hermes`
3. New container starts, existing ones untouched

### Enabling Mimir (shared memory)

Set `mimir.enabled: true` in config.yml and re-run setup.sh. See [Mimir docs](https://github.com/jimmy-larsson/mimir) for details.

## Contributing

Hermes welcomes contributions in three areas:

1. **Integrations** - Add support for new tools. See [.hermes/integrations/CLAUDE.md](.hermes/integrations/CLAUDE.md) for patterns and security requirements.
2. **Commands, agents, skills** - Extend Hermes capabilities. Templates are in `.claude/commands/`, `.claude/agents/`, and `.claude/skills/`.
3. **Bug fixes** - Found an issue? Submit a PR with the fix and a test case.

Fork the repo, create a branch, and submit a PR. All contributions are reviewed.

## About

Based on the MARVIN template, created by [Sterling Chin](https://sterlingchin.com).
