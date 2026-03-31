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

## Step 5: Configure Mimir

Explain and ask:

> "Next: **Mimir** — shared memory.
>
> With Mimir enabled, all your users share a structured memory system — tasks, facts, projects, reminders — with scope-based access control (who can see what).
>
> Without it, each user has independent file-based state.
>
> Enable Mimir? (Most multi-user setups benefit from it, but it's optional.)"

If the user enables Mimir, proceed to Step 6.
If disabled, skip to Step 7 (scopes section won't be needed).

---

## Step 6: Configure scopes (Mimir only)

If Mimir is enabled, explain scopes:

> "Mimir uses **scopes** to control who sees what.
>
> I'll automatically create a **personal scope** for each user (e.g., `jimmy` scope for Jimmy's private items).
>
> You can also add **shared scopes** — for example, a `household` scope that both Jimmy and Alex can see.
>
> Want to add any shared scopes? (Give me a name like 'household' or 'team', or say 'no' to skip.)"

For each shared scope, collect:
- Name (used as the scope ID, lowercased with hyphens for spaces)
- Description (one line)
- Which users should have access (default: all users)

Continue until the user is done adding scopes.

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

Check if the shared auth directory has files:

```bash
ls -A DEPLOY_PATH/data/shared/claude-auth/
```

If empty, ask conversationally:

> "Next up: Claude Code authentication for the containers.
>
> How would you like to handle auth?
> 1. **Share your current login** — copies your credentials to all containers
> 2. **Login per container** — each user runs `claude login` the first time they connect"

If the user chooses option 1, copy the credentials:

```bash
cp ~/.claude/.credentials.json DEPLOY_PATH/data/shared/claude-auth/
```

Verify the copy worked:

```bash
ls -la DEPLOY_PATH/data/shared/claude-auth/
```

If the file exists, restart containers to pick up the auth:

```bash
cd DEPLOY_PATH && docker compose restart
```

If the user chooses option 2, no action needed — just note that users will need to run `claude login` inside their container on first connect.

If files already exist in the auth directory, skip this step.

---

## Step 10: Verify

If Docker is available, run verification checks:

```bash
cd DEPLOY_PATH && docker compose ps
```

For each user container that's running:

```bash
docker exec USER-hermes tmux list-sessions
```

```bash
docker exec USER-hermes claude --version
```

If Mimir is enabled:

```bash
docker exec USER-hermes curl -sf http://mimir:8100/sse && echo "Mimir reachable" || echo "Mimir not reachable"
```

Report results:

> "Verification results:
> - Containers: {running/not running}
> - tmux sessions: {active/not active}
> - Claude Code: {version or not found}
> - Mimir: {reachable/not reachable/disabled}"

If Docker isn't available, tell the user:

> "Docker isn't available on this machine. Once you're on the deployment server with Docker Compose v2, run:
> ```
> cd DEPLOY_PATH && docker compose up -d
> ```"

---

## Step 11: Wrap up

> "You're all set! Here's how to use your deployment:
>
> **Connect to a container:**
> ```
> docker exec -it USER-hermes tmux attach -t hermes
> ```
>
> **Or use the hermes shortcut** (add to your shell config):
> ```
> source DEPLOY_PATH/data/users/USER/hermes-wrapper.sh
> hermes              # attach to tmux session
> hermes research     # open a named Claude Code session
> ```
>
> **Manage the deployment:**
> ```
> cd DEPLOY_PATH
> docker compose ps      # check status
> docker compose down    # stop everything
> docker compose up -d   # start everything
> ```
>
> **Add a user later:**
> 1. Edit `DEPLOY_PATH/config.yml` — add the new user
> 2. Re-run: `./deploy/setup.sh DEPLOY_PATH`
> 3. New container starts, existing ones untouched"

Replace USER and DEPLOY_PATH with actual values throughout.
