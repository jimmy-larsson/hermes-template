# Hermes Multi-User Deployment — Onboarding Guide

This guide is read by Claude Code when the user runs `/deploy` and chooses **new deployment**. Follow these 7 steps in order.

---

## Important Constraints

- **DO NOT use interactive bash prompts** (`read`, `select`, etc.) — they don't work from Claude Code. All user interaction must be conversational.
- **Remember the deploy path** chosen in Step 1. Use it in all subsequent steps.
- **YAML format matters** — the config parser (`deploy/parse_config.py`) is hand-rolled and expects exact formatting. Follow the structure shown in Step 5 precisely.
- **User IDs** — lowercase letters, numbers, underscores only. Spaces become underscores, hyphens become underscores, strip special characters. Must start with a letter. Examples: "Mary Jane" → `mary_jane`, "O'Brien" → `obrien`.

---

## Step 1: Welcome + Scaffold

Greet the user and explain what they're getting:

> "Let's set up multi-user Hermes deployment. Here's what this gives you:
>
> - **Separate Docker container per user** — each running Claude Code with tmux for multiple sessions
> - **Optional shared memory** via Mimir — tasks, facts, and projects shared across users
> - **Config-driven** — one YAML file defines your entire deployment
> - **SSH access** — users SSH into the host and get dropped into their container
>
> First — where should I set up the deployment? The default is `~/hermes`."

Wait for the user's response. Store their chosen path as DEPLOY_PATH (default: `~/hermes`).

Run the first setup.sh invocation to scaffold the directory:

```bash
./deploy/setup.sh DEPLOY_PATH
```

This first run creates the directory structure, copies build files, and generates `config.yml` from the template. It exits after this — that's expected.

Then silently read the generated config to understand the template structure:

```bash
cat DEPLOY_PATH/config.yml
```

Do NOT show the config to the user. Just proceed to collect their answers.

Tell the user:

> "Deployment directory ready at `DEPLOY_PATH`. Let's configure it."

---

## Step 2: Users

Collect users one at a time. Ask for **one piece of information per message**.

Start:

> "Who will be using this? Let's add users one at a time. What's the first user's name?"

Wait for the name. **Derive the user ID automatically** using the ID rules from the constraints section. Then ask about their role:

> "Got it — I'll use `USER_ID` as the user ID. Is USER_NAME an admin or regular?
> 1. **Admin** — can manage scopes and users in Mimir
> 2. **Regular** — standard access"

Wait for the answer. Confirm and ask for more:

> "Added USER_NAME (`USER_ID`, admin/regular). Anyone else?"

Repeat until the user is done. Require at least one user.

**Review checkpoint** — before moving on, confirm the full user list:

> "Here's everyone:
>
> | # | Name | ID | Role |
> |---|------|----|------|
> | 1 | Jimmy | jimmy | Admin |
> | 2 | Alex | alex | Regular |
>
> Look good?"

Wait for confirmation before proceeding.

---

## Step 3: Shared Access + Mimir

Ask about shared access first — this determines whether Mimir is needed:

> "Do any of your users need to share data — tasks, facts, projects — with each other?
>
> For example, a `household` scope that both Jimmy and Alex can see, or a `team` scope for work items.
>
> 1. **Yes** — I'll set up shared scopes
> 2. **No** — each user keeps their own private data"

**If yes (shared scopes):**

Collect scopes:

> "What should the first shared scope be called? (e.g., 'household', 'team')"

For each shared scope, collect:
- Name (lowercase with underscores for the ID)
- Description (one line)
- Which users should have access (present as numbered list, default: all users)

Continue until done. Then inform about Mimir:

> "Since you have shared scopes, I'll enable **Mimir** — the shared memory server. It stores tasks, facts, projects, and reminders with scope-based access control.
>
> Each user also gets a personal scope automatically (matching their user ID)."

**If no (no shared scopes):**

Ask about Mimir standalone:

> "Even without shared scopes, **Mimir** gives each user structured memory — tasks, facts, projects, reminders — that persists across conversations.
>
> Without it, each user has independent file-based state.
>
> Enable Mimir? (Recommended, but optional.)"

If Mimir enabled without shared scopes, note that each user still gets a personal scope.

If Mimir disabled, no scopes section is needed in the config.

---

## Step 4: Auth

> "How should containers authenticate with Claude Code?
>
> 1. **Shared credentials** — mounts your host's `~/.claude/.credentials.json` (read-only) into all containers. All users share one Anthropic account. Credentials update automatically when you re-authenticate on the host.
> 2. **Per-container login** — each user runs `claude login` inside their container on first connect. Use this if users have separate Anthropic accounts."

Store the answer as `auth.shared: true` or `auth.shared: false`.

---

## Step 5: Deploy

Assemble the final YAML from all collected answers and show it to the user for confirmation.

> "Here's your configuration:
>
> - **Users:** {list of names with roles}
> - **Auth:** {shared credentials / per-container login}
> - **Mimir:** {enabled / disabled}
> - **Scopes:** {list of scopes, or "N/A"}
>
> Ready to deploy?"

Wait for confirmation. Then:

**Write config.yml** using the Write tool to `DEPLOY_PATH/config.yml`. The YAML must follow this exact format (parse_config.py depends on it):

```yaml
# Hermes Multi-User Deployment Configuration

auth:
  shared: AUTH_SHARED

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
- Top-level keys (`auth:`, `mimir:`, `users:`, `scopes:`) start at column 0
- Sub-keys use 2-space indentation
- List items use `  - id:` format (2-space indent before dash)
- Nested scope lists use 6-space indentation (`      - scope_id`)
- Boolean values must be lowercase `true` or `false`
- Only include the `scopes:` section if Mimir is enabled
- Each user's `scopes:` list must include their own ID (personal scope) plus any shared scopes they have access to

Use the Write tool. **Do NOT use bash echo/cat.**

**Run setup.sh** to generate the full deployment:

```bash
./deploy/setup.sh DEPLOY_PATH
```

This time config.yml exists, so the script will:
- Parse and validate config
- Generate API keys and .env
- Generate docker-compose.yml (with conditional credentials mount)
- Create per-user workspaces (CLAUDE.md, commands, state)
- Generate .mcp.json per user (if Mimir enabled)
- Generate Mimir seed.sql (if Mimir enabled)
- Generate host wrapper scripts (bash + fish)
- Validate generated files
- Build Docker images and start containers (if Docker available)
- Validate runtime
- Git init the deployment directory

**Relay results** — the script prints pass/fail for three validation checkpoints (config, files, runtime). Read the output and relay to the user. If all passed, say so. If any failed, relay specific failures.

If Docker isn't available, note that containers need to be built and started manually later:

> "Docker isn't available on this machine. Once you're on the deployment server with Docker Compose v2, run:
> ```
> cd DEPLOY_PATH && docker compose up -d
> ```"

---

## Step 6: Wrapper

List the generated wrapper formats:

```bash
ls DEPLOY_PATH/data/users/*/hermes-wrapper.*
```

Ask:

> "Want me to install the `hermes` command? This gives you quick access:
> - `hermes` — AI assistant (tmux + Claude Code)
> - `hermes <name>` — named session (e.g., hermes research)
> - `hermes shell` — plain bash shell in container
> - `hermes list` — show active sessions
>
> Available formats:
> 1. **fish** — installs to `~/.config/fish/conf.d/`
> 2. **bash** — adds to `~/.bashrc`
> 3. **zsh** — adds to `~/.zshrc`
> 4. **Skip** — I'll set it up myself"

If the user has multiple user IDs, also ask which user to install for.

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

After install: "Restart your shell or run `exec {shell}` to activate it."

If skipped: "Wrapper files are at `DEPLOY_PATH/data/users/USER/` — both `.sh` (bash/zsh) and `.fish` formats."

---

## Step 7: Summary

Present a structured summary with verification results and reference commands:

> "**Deployment complete!**
>
> **Verification:**
> - Containers: {list each container and status}
> - tmux sessions: {active for each user}
> - Mimir: {healthy / disabled}
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

Replace USER and DEPLOY_PATH with actual values throughout.
