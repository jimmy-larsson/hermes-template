# Hermes Multi-User Deployment — Onboarding Guide

This guide is read by Claude Code when the user runs `/deploy`. Follow these steps in order to guide the user through setting up multi-user Hermes deployment.

---

## Important Constraints

- **DO NOT use interactive bash prompts** (`read`, `select`, etc.) — they don't work from Claude Code. All user interaction must be conversational.
- **Remember the deploy path** chosen in Step 2. Use it in all subsequent steps.
- **YAML format matters** — the config parser (`deploy/parse_config.py`) is hand-rolled and expects exact formatting. Follow the structure shown in Step 7 precisely.

---

## Step 1: Welcome

Greet the user and explain what multi-user deployment does:

> "Let's set up multi-user Hermes deployment. Here's what this gives you:
>
> - **Separate Docker container per user** — each running Claude Code with tmux for multiple sessions
> - **Optional shared memory** via Mimir — tasks, facts, and projects shared across users
> - **Config-driven** — one YAML file defines your entire deployment
> - **SSH access** — users SSH into the host and get dropped into their container
>
> I'll walk you through the whole thing."

---

## Step 2: Scaffold the deployment directory

Ask the user where they want to deploy:

> "Where should I set up the deployment? The default is `~/hermes`.
> Just confirm or give me a different path."

Wait for the user's response. Store their chosen path as DEPLOY_PATH (default: `~/hermes`).

Then run:

```bash
./deploy/setup.sh DEPLOY_PATH
```

Replace DEPLOY_PATH with the actual path the user chose.

This first run:
- Creates the deployment directory
- Copies build files (Dockerfile, entrypoint.sh, hermes.sh)
- Creates `config.yml` from the example template
- Exits (this is expected behavior on first run)

Tell the user:

> "The deployment directory is ready at `DEPLOY_PATH`. Now let's configure it."

---

## Step 3: Read the generated config

Read the generated config file:

```bash
cat DEPLOY_PATH/config.yml
```

This shows the default example config. Use it as reference for the structure but don't present it to the user — just proceed to ask questions.

---

## Step 4: Configure users

Collect users one at a time. Ask for **one piece of information per message** — don't bundle multiple questions.

Start with:

> "First, let's set up the users. What's the name of the first user?"

Wait for the name. Then **automatically derive the user ID** (lowercase, spaces replaced with hyphens) and ask about their role:

> "Got it — I'll use `jimmy` as the user ID. Is Jimmy an admin or a regular user?
> 1. **Admin** — can manage scopes and users in Mimir
> 2. **Regular** — standard access"

Wait for the answer. Then confirm and ask for more:

> "Added Jimmy (`jimmy`, admin). Any more users?"

If yes, repeat:
> "What's the next user's name?"

Then derive ID, ask admin/regular, confirm, ask for more. Continue until the user says they're done. Require at least one user.

Store the collected users as a list. Each user has: id (auto-derived from name), name, admin (true/false).

---

## Step 5: Configure scopes

Ask about shared access groups first (this informs whether Mimir is needed):

> "Do any of your users need to share data — tasks, facts, projects — with each other?
>
> For example, a `household` scope that both Jimmy and Alex can see, or a `team` scope for work items.
>
> 1. **Yes** — I'll set up shared scopes (requires Mimir)
> 2. **No** — each user keeps their own private data"

If yes, collect shared scopes:

> "What should the first shared scope be called? (e.g., 'household', 'team')"

For each shared scope, collect:
- Name (used as the scope ID, lowercased with hyphens for spaces)
- Description (one line)
- Which users should have access (default: all users)

Continue until the user is done adding scopes.

**Note:** Each user always gets a personal scope automatically (matching their user ID). You only need to ask about shared scopes here.

---

## Step 6: Configure Mimir

If the user created shared scopes in Step 5, Mimir is required — inform them:

> "Since you have shared scopes, I'll enable **Mimir** — the shared memory server. It stores tasks, facts, projects, and reminders with scope-based access control."

If the user said no shared scopes in Step 5, ask:

> "Even without shared scopes, **Mimir** gives each user structured memory — tasks, facts, projects, reminders — that persists across conversations.
>
> Without it, each user has independent file-based state.
>
> Enable Mimir? (Recommended, but optional.)"

If Mimir is disabled, skip the scopes section when writing config in Step 7.

---

## Step 7: Write config.yml

Assemble the final YAML from the collected answers and write it to `DEPLOY_PATH/config.yml`.

**The YAML must follow this exact format** (parse_config.py depends on it):

```yaml
# Hermes Multi-User Deployment Configuration

mimir:
  enabled: MIMIR_ENABLED
  port: 8100

users:
  - id: USER_ID
    name: USER_NAME
    admin: USER_ADMIN
    scopes:
      - USER_ID
      - SHARED_SCOPE_1

scopes:
  - id: USER_ID
    name: USER_NAME
    description: USER_NAME's personal scope
  - id: SHARED_SCOPE_ID
    name: Shared Scope Name
    description: Scope description
```

**Format rules:**
- Top-level keys (`mimir:`, `users:`, `scopes:`) start at column 0
- Sub-keys use 2-space indentation
- List items use `  - id:` format (2-space indent before dash)
- Nested scope lists use 6-space indentation (`      - scope_id`)
- Boolean values must be lowercase `true` or `false`
- Only include the `scopes:` section if Mimir is enabled
- Each user's `scopes:` list must include their own ID (personal scope) plus any shared scopes they have access to

Use the Write tool to write the file. **Do NOT use bash echo/cat** — use the Write tool for accurate formatting.

Show the user what was written:

> "Config written. Here's what I set up:
>
> - **Users:** {list of names}
> - **Mimir:** {enabled/disabled}
> - **Scopes:** {list of scopes if applicable}
>
> Ready to generate the deployment?"

Wait for confirmation before proceeding.

---

## Step 8: Run setup.sh again (generate everything)

Run:

```bash
./deploy/setup.sh DEPLOY_PATH
```

This time config.yml exists, so the script will:
- Parse the config
- Generate API keys per user
- Generate docker-compose.yml
- Create per-user workspaces (CLAUDE.md, commands, state files)
- Generate .mcp.json per user (if Mimir enabled)
- Generate Mimir seed.sql (if Mimir enabled)
- Generate host wrapper scripts
- Build Docker images (if Docker available)
- Seed Mimir database (if enabled and Docker available)
- Start containers (if Docker available)
- Git init the deployment directory

Report progress to the user as the script runs. If Docker isn't available, note that containers need to be built and started manually later.

---

## Step 9: Claude Code authentication

The compose file automatically mounts `~/.claude/.credentials.json` (read-only) from the host into every user container. **No manual copy is needed.**

Check if credentials exist on the host:

```bash
test -f ~/.claude/.credentials.json && echo "Found" || echo "Not found"
```

If found:

> "Your Claude Code credentials (`~/.claude/.credentials.json`) are automatically shared with all containers via a read-only mount. When you re-authenticate on the host (`claude login`), containers pick up the new credentials on restart. No action needed."

If not found:

> "No Claude Code credentials found on the host. Each user will need to run `claude login` inside their container on first connect.
>
> To share credentials later, run `claude login` on the host — the containers mount `~/.claude/.credentials.json` automatically."

---

## Step 10: Verify

The `setup.sh` script already runs three validation checkpoints automatically:
1. **Config validation** — after parsing config.yml
2. **Generated files validation** — after generating .env, compose, workspaces, seed
3. **Runtime validation** — after starting containers (containers up, Mimir healthy, API keys work, seed loaded, tmux sessions exist)

**Do NOT re-run these checks manually.** The script output already contains all validation results with pass/fail indicators.

Read the script output and relay the results to the user. If all checkpoints passed:

> "All validation checks passed — {summary of what was verified}."

If any checkpoint failed, relay the specific failures and suggest fixes.

---

## Step 11: Install wrapper command

List the available wrapper formats that were generated:

```bash
ls DEPLOY_PATH/data/users/*/hermes-wrapper.*
```

Ask the user:

> "Want me to install the `hermes` command? This gives you quick access to your containers:
> - `hermes` — AI assistant (tmux + Claude Code)
> - `hermes <name>` — named session
> - `hermes shell` — plain bash shell in container
> - `hermes list` — show active sessions
>
> Available formats:
> 1. **fish** — installs to `~/.config/fish/conf.d/`
> 2. **bash** — adds to `~/.bashrc`
> 3. **zsh** — adds to `~/.zshrc`
> 4. **Skip** — I'll set it up myself"

If the user has multiple user IDs configured, also ask which user to install for.

Based on their choice:

**fish:**
```bash
cp DEPLOY_PATH/data/users/USER/hermes-wrapper.fish ~/.config/fish/conf.d/hermes.fish
```

**bash:**
```bash
WRAPPER="DEPLOY_PATH/data/users/USER/hermes-wrapper.sh"
if ! grep -qF "source $WRAPPER" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# Hermes wrapper" >> ~/.bashrc
    echo "source $WRAPPER" >> ~/.bashrc
fi
```

**zsh:**
```bash
WRAPPER="DEPLOY_PATH/data/users/USER/hermes-wrapper.sh"
if ! grep -qF "source $WRAPPER" ~/.zshrc 2>/dev/null; then
    echo "" >> ~/.zshrc
    echo "# Hermes wrapper" >> ~/.zshrc
    echo "source $WRAPPER" >> ~/.zshrc
fi
```

After installing:

> "Installed. Restart your shell or run `exec {shell}` to activate it."

If the user skips, tell them where the files are:

> "Wrapper files are at `DEPLOY_PATH/data/users/USER/` — both `.sh` (bash/zsh) and `.fish` formats."

---

## Step 12: Wrap up

Present a summary covering verification results, how to connect, and how to manage. Replace USER and DEPLOY_PATH with actual values:

> "**Deployment complete!**
>
> **Verification:**
> - Containers: {list each container and status — running/stopped}
> - tmux sessions: {active for each user}
> - Mimir: {healthy/disabled}
>
> **Connect:**
> ```
> hermes              # AI assistant (tmux + Claude Code)
> hermes <name>       # named session (e.g., hermes research)
> hermes shell        # plain bash shell in container
> hermes list         # show active sessions
> ```
>
> **Manage:**
> ```
> cd DEPLOY_PATH
> docker compose ps      # check status
> docker compose down    # stop everything
> docker compose up -d   # start everything
> ```
>
> **Add a user later:** edit `DEPLOY_PATH/config.yml`, then re-run `./deploy/setup.sh DEPLOY_PATH`
>
> **Remote access (from another machine):**
> ```
> ./deploy/setup.sh --connect user@this-host --user <user-id>
> ```"
