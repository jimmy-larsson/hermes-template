# Onboarding Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the `/deploy` onboarding from 12 implementation-focused steps to 7 user-focused steps, fix 6 bugs across setup.sh and parse_config.py, and update managing.md for consistency.

**Architecture:** Bug fixes first (parse_config.py, setup.sh, mcp.json.tmpl), then doc rewrites (onboarding.md, managing.md, config.yml.example). Each bug fix is independently verifiable before moving to docs.

**Tech Stack:** Bash (setup.sh), Python 3 (parse_config.py), Markdown (onboarding/managing docs)

**Spec:** `docs/specs/2026-04-01-onboarding-redesign.md`

**Repo:** `/home/marvin/repositories/private/hermes`

---

## File Structure

```
hermes/deploy/
├── parse_config.py          # MODIFY — boolean normalization (BUG 5)
├── setup.sh                 # MODIFY — 5 bug fixes (BUGs 1, 2, 4, 5-companion, 6)
├── onboarding.md            # REWRITE — 7-step flow
├── managing.md              # MODIFY — 8 fixes
├── config.yml.example       # MODIFY — clarifying comment
└── templates/
    └── mcp.json.tmpl        # MODIFY — hardcode internal port (BUG 3)
```

No new files. No test framework exists in this repo — verification via inline commands.

---

### Task 1: Fix parse_config.py boolean normalization (BUG 5)

**Files:**
- Modify: `deploy/parse_config.py:127-133`

The `user.*` query branch outputs Python's native `True`/`False` via `print(u.get(field, ""))`. The `auth.shared` and `mimir.enabled` paths already output lowercase. Only the `user.*` path has this issue.

- [ ] **Step 1: Verify the current bug**

```bash
cd /home/marvin/repositories/private/hermes
# Create a test config with a boolean admin field
cat > /tmp/test-config.yml << 'EOF'
auth:
  shared: false
mimir:
  enabled: false
  port: 8100
users:
  - id: testuser
    name: Test User
    admin: true
    scopes:
      - testuser
scopes:
  - id: testuser
    name: Test User
    description: Test scope
EOF
python3 deploy/parse_config.py /tmp/test-config.yml user.testuser.admin
```

Expected: Outputs `True` (capital T — the bug).

- [ ] **Step 2: Fix the user.* branch**

In `deploy/parse_config.py`, replace lines 127-133:

```python
    elif query.startswith("user."):
        parts = query.split(".")
        user_id, field = parts[1], parts[2]
        for u in config["users"]:
            if u["id"] == user_id:
                print(u.get(field, ""))
                break
```

With:

```python
    elif query.startswith("user."):
        parts = query.split(".")
        user_id, field = parts[1], parts[2]
        for u in config["users"]:
            if u["id"] == user_id:
                val = u.get(field, "")
                if isinstance(val, bool):
                    print("true" if val else "false")
                else:
                    print(val)
                break
```

- [ ] **Step 3: Verify the fix**

```bash
cd /home/marvin/repositories/private/hermes
python3 deploy/parse_config.py /tmp/test-config.yml user.testuser.admin
```

Expected: Outputs `true` (lowercase).

Also verify non-boolean fields still work:

```bash
python3 deploy/parse_config.py /tmp/test-config.yml user.testuser.name
```

Expected: Outputs `Test User`.

- [ ] **Step 4: Commit**

```bash
cd /home/marvin/repositories/private/hermes
git add deploy/parse_config.py
git commit -m "fix: normalize boolean output in parse_config.py user queries"
```

---

### Task 2: Fix mcp.json.tmpl — hardcode internal Docker port (BUG 3)

**Files:**
- Modify: `deploy/templates/mcp.json.tmpl`
- Modify: `deploy/setup.sh:649` (remove MIMIR_PORT substitution)

Containers communicate over the Docker bridge network where Mimir always listens on port 8100. The `%%MIMIR_PORT%%` placeholder substitutes the host-exposed port, which is wrong inside containers.

- [ ] **Step 1: Fix the template**

In `deploy/templates/mcp.json.tmpl`, replace the entire file content:

```json
{
  "mcpServers": {
    "mimir": {
      "url": "http://mimir:8100/sse",
      "headers": {
        "x-api-key": "%%API_KEY%%"
      }
    }
  }
}
```

The only remaining placeholder is `%%API_KEY%%` which is per-user.

- [ ] **Step 2: Remove the MIMIR_PORT substitution from setup.sh**

In `deploy/setup.sh`, find the `sed` command in Phase 6 (around line 649):

```bash
        sed -e "s/%%MIMIR_PORT%%/$MIMIR_PORT/g" \
            -e "s/%%API_KEY%%/$API_KEY/g" \
            "$SCRIPT_DIR/templates/mcp.json.tmpl" > "$USER_DIR/.mcp.json"
```

Replace with:

```bash
        sed -e "s/%%API_KEY%%/$API_KEY/g" \
            "$SCRIPT_DIR/templates/mcp.json.tmpl" > "$USER_DIR/.mcp.json"
```

- [ ] **Step 3: Verify**

```bash
cd /home/marvin/repositories/private/hermes
cat deploy/templates/mcp.json.tmpl | grep "8100"
grep "MIMIR_PORT" deploy/templates/mcp.json.tmpl
```

Expected: First grep returns the `http://mimir:8100/sse` line. Second grep returns nothing.

- [ ] **Step 4: Commit**

```bash
cd /home/marvin/repositories/private/hermes
git add deploy/templates/mcp.json.tmpl deploy/setup.sh
git commit -m "fix: hardcode internal Mimir port in MCP template"
```

---

### Task 3: Fix setup.sh bugs (BUGs 1, 2, 4, 6 + BUG 5 companion)

**Files:**
- Modify: `deploy/setup.sh` (6 locations for BUG 1, plus BUGs 2, 4, 6, and BUG 5 companion)

This task fixes 5 bugs in setup.sh. Do them in order — each fix is independent.

#### BUG 6: validate_config regex allows hyphens

- [ ] **Step 1: Fix the user ID validation regex**

In `deploy/setup.sh`, find line 93:

```bash
        if ! [[ "$uid" =~ ^[a-z][a-z0-9_-]*$ ]]; then
```

Replace with:

```bash
        if ! [[ "$uid" =~ ^[a-z][a-z0-9_]*$ ]]; then
```

Remove the `-` from the character class. User IDs must only contain lowercase letters, digits, and underscores.

#### BUG 1: Hyphens in user IDs break .env variable expansion

All occurrences of `tr '[:lower:]' '[:upper:]'` that build KEY_VAR must also translate hyphens to underscores. There are **6 locations** in setup.sh. Fix all of them.

- [ ] **Step 2: Fix all 6 KEY_VAR locations**

Find every occurrence of this pattern in `deploy/setup.sh`:

```bash
KEY_VAR="API_KEY_$(echo "$user_id" | tr '[:lower:]' '[:upper:]')"
```

or the lowercase-variable variant:

```bash
local key_var="API_KEY_$(echo "$uid" | tr '[:lower:]' '[:upper:]')"
```

Replace `tr '[:lower:]' '[:upper:]'` with `tr '[:lower:]-' '[:upper:]_'` in each.

The 6 locations are:

1. **validate_generated_files** (~line 172):
   ```bash
   local key_var="API_KEY_$(echo "$uid" | tr '[:lower:]-' '[:upper:]_')"
   ```

2. **validate_runtime** (~line 311):
   ```bash
   local key_var="API_KEY_$(echo "$uid" | tr '[:lower:]-' '[:upper:]_')"
   ```

3. **Phase 4: .env generation** (~line 541):
   ```bash
   KEY_VAR="API_KEY_$(echo "$user_id" | tr '[:lower:]-' '[:upper:]_')"
   ```

4. **Phase 5: docker-compose generation** (~line 595):
   ```bash
   KEY_VAR="API_KEY_$(echo "$user_id" | tr '[:lower:]-' '[:upper:]_')"
   ```

5. **Phase 6: .mcp.json generation** (~line 647):
   ```bash
   KEY_VAR="API_KEY_$(echo "$user_id" | tr '[:lower:]-' '[:upper:]_')"
   ```

6. **Phase 7: seed.sql generation** (~line 681):
   ```bash
   KEY_VAR="API_KEY_$(echo "$user_id" | tr '[:lower:]-' '[:upper:]_')"
   ```

- [ ] **Step 3: Verify all 6 locations are fixed**

```bash
cd /home/marvin/repositories/private/hermes
# Should find 0 occurrences of the old pattern
grep -n "tr '\[:lower:\]' '\[:upper:\]'" deploy/setup.sh | head -20
# Should find 6 occurrences of the new pattern
grep -c "tr '\[:lower:\]-' '\[:upper:\]_'" deploy/setup.sh
```

Expected: First command returns nothing. Second command returns `6`.

#### BUG 4: .env MIMIR_PORT not updated on re-run

- [ ] **Step 4: Add MIMIR_PORT update after .env creation guard**

In `deploy/setup.sh`, find the .env creation block in Phase 4 (~lines 533-538):

```bash
ENV_FILE="$DEPLOY_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "# Generated by setup.sh — API keys and ports" > "$ENV_FILE"
    echo "MIMIR_PORT=$MIMIR_PORT" >> "$ENV_FILE"
    echo "" >> "$ENV_FILE"
fi
```

Add after the `fi`:

```bash
# Update MIMIR_PORT in case config changed
sed -i "s/^MIMIR_PORT=.*/MIMIR_PORT=$MIMIR_PORT/" "$ENV_FILE"
```

The result should be:

```bash
ENV_FILE="$DEPLOY_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "# Generated by setup.sh — API keys and ports" > "$ENV_FILE"
    echo "MIMIR_PORT=$MIMIR_PORT" >> "$ENV_FILE"
    echo "" >> "$ENV_FILE"
fi

# Update MIMIR_PORT in case config changed
sed -i "s/^MIMIR_PORT=.*/MIMIR_PORT=$MIMIR_PORT/" "$ENV_FILE"
```

#### BUG 2: seed.sql not regenerated on re-run

- [ ] **Step 5: Remove the seed.sql existence guard and use INSERT OR IGNORE**

In `deploy/setup.sh`, find Phase 7 (~lines 659-708). The current code has:

```bash
    if [ ! -f "$SEED_FILE" ]; then
```

This guard skips seed generation when the file exists. Replace the entire Phase 7 block with:

```bash
if [ "$MIMIR_ENABLED" = "true" ]; then
    SEED_FILE="$DEPLOY_DIR/data/mimir/seed.sql"
    mkdir -p "$DEPLOY_DIR/data/mimir/data"

    info "Generating Mimir seed data"
    echo "-- Generated by setup.sh" > "$SEED_FILE"
    echo "" >> "$SEED_FILE"

    # Insert scopes (idempotent)
    echo "$SCOPES_JSON" | python3 -c "
import json, sys
for s in json.load(sys.stdin):
    sid = s['id'].replace(\"'\", \"''\")
    name = s['name'].replace(\"'\", \"''\")
    desc = s.get('description', '').replace(\"'\", \"''\")
    print(f\"INSERT OR IGNORE INTO scopes (id, name, description) VALUES ('{sid}', '{name}', '{desc}');\")
" >> "$SEED_FILE"
    echo "" >> "$SEED_FILE"

    # Insert users (idempotent)
    for user_id in $USER_IDS; do
        KEY_VAR="API_KEY_$(echo "$user_id" | tr '[:lower:]-' '[:upper:]_')"
        API_KEY="${!KEY_VAR}"
        USER_NAME=$(python3 "$PARSER" "$CONFIG" "user.$user_id.name")
        IS_ADMIN=$(python3 "$PARSER" "$CONFIG" "user.$user_id.admin")
        IS_ADMIN_SQL="FALSE"
        [ "$IS_ADMIN" = "true" ] && IS_ADMIN_SQL="TRUE"

        echo "INSERT OR IGNORE INTO users (id, name, is_admin, api_key) VALUES ('$user_id', '$USER_NAME', $IS_ADMIN_SQL, '$API_KEY');" >> "$SEED_FILE"
    done
    echo "" >> "$SEED_FILE"

    # Insert scope memberships (idempotent)
    echo "$USERS_JSON" | python3 -c "
import json, sys
for u in json.load(sys.stdin):
    for scope in u.get('scopes', []):
        print(f\"INSERT OR IGNORE INTO scope_members (scope_id, user_id) VALUES ('{scope}', '{u['id']}');\")
" >> "$SEED_FILE"
    echo "" >> "$SEED_FILE"

    # Insert activity cursors (idempotent)
    for user_id in $USER_IDS; do
        echo "INSERT OR IGNORE INTO activity_cursor (user_id, last_seen_history_id) VALUES ('$user_id', 0);" >> "$SEED_FILE"
    done

    info "Seed file: $SEED_FILE"
fi
```

Key changes:
- Removed `if [ ! -f "$SEED_FILE" ]` guard — always regenerate
- All `INSERT INTO` → `INSERT OR IGNORE INTO` for idempotency
- `IS_ADMIN` comparison changed from `"True"` to `"true"` (BUG 5 companion — parse_config.py now outputs lowercase)

- [ ] **Step 6: Verify all fixes**

```bash
cd /home/marvin/repositories/private/hermes
# BUG 6: regex should NOT contain hyphen
grep -n 'a-z0-9_-' deploy/setup.sh
# BUG 1: should have 6 occurrences of the new tr pattern
grep -c "tr '\[:lower:\]-' '\[:upper:\]_'" deploy/setup.sh
# BUG 4: sed for MIMIR_PORT should exist
grep -n 'sed -i.*MIMIR_PORT' deploy/setup.sh
# BUG 2: no existence guard on seed file
grep -n 'if \[ ! -f "$SEED_FILE" \]' deploy/setup.sh
# BUG 2: INSERT OR IGNORE used
grep -c 'INSERT OR IGNORE' deploy/setup.sh
# BUG 5 companion: lowercase true comparison
grep -n '"True"' deploy/setup.sh
```

Expected:
- BUG 6: No output (hyphen removed from regex)
- BUG 1: `6`
- BUG 4: One match for the sed command
- BUG 2: No output (guard removed)
- BUG 2: At least 4 (scopes, users, scope_members, activity_cursor)
- BUG 5: No output (no more `"True"` comparisons)

- [ ] **Step 7: Commit**

```bash
cd /home/marvin/repositories/private/hermes
git add deploy/setup.sh
git commit -m "fix: 5 bugs in setup.sh — KEY_VAR hyphens, seed.sql regen, MIMIR_PORT update, regex, bool comparison"
```

---

### Task 4: Update config.yml.example

**Files:**
- Modify: `deploy/config.yml.example`

Add a clarifying comment that scopes are only relevant when Mimir is enabled.

- [ ] **Step 1: Add clarifying comment**

In `deploy/config.yml.example`, find the scopes header comment (line 38):

```yaml
# Scopes: Access groups for organizing shared data.
# Only relevant when Mimir is enabled.
```

Replace with:

```yaml
# Scopes: Access groups for organizing shared data.
# Only relevant when Mimir is enabled — ignored when mimir.enabled is false.
# Included here to show the format; remove or leave as-is if not using Mimir.
```

- [ ] **Step 2: Commit**

```bash
cd /home/marvin/repositories/private/hermes
git add deploy/config.yml.example
git commit -m "docs: clarify scopes section in config example"
```

---

### Task 5: Rewrite onboarding.md — 7-step flow

**Files:**
- Rewrite: `deploy/onboarding.md`

This is a full rewrite. Replace the entire file with the 7-step flow from the spec. The new flow merges the current 12 steps into 7 user-focused steps.

- [ ] **Step 1: Write the new onboarding.md**

Replace the entire contents of `deploy/onboarding.md` with:

````markdown
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
````

- [ ] **Step 2: Verify the new file**

```bash
cd /home/marvin/repositories/private/hermes
# Exactly 7 steps
grep -c '^## Step' deploy/onboarding.md
# No references to old step numbers (Step 8, Step 9, etc.)
grep -n 'Step [89]' deploy/onboarding.md
grep -n 'Step 1[0-2]' deploy/onboarding.md
# User ID derivation says underscores, not hyphens
grep -n 'hyphen' deploy/onboarding.md
# Constraints mention underscore rule
grep -n 'underscore' deploy/onboarding.md
```

Expected:
- Step count: `7`
- No references to Steps 8-12
- No "hyphen" in ID derivation context
- "underscore" appears in constraints and Step 2

- [ ] **Step 3: Commit**

```bash
cd /home/marvin/repositories/private/hermes
git add deploy/onboarding.md
git commit -m "feat: rewrite onboarding to 7 user-focused steps"
```

---

### Task 6: Update managing.md — 8 fixes

**Files:**
- Modify: `deploy/managing.md`

The spec identifies 8 issues. Apply each fix in order.

- [ ] **Step 1: Fix #1 — Remove step number reference for YAML format**

In `deploy/managing.md`, find in the Important Constraints section (line 10):

```markdown
- **YAML format matters** — the config parser (`deploy/parse_config.py`) is hand-rolled and expects exact formatting. Follow the structure from onboarding.md Step 7 precisely.
```

Replace with:

```markdown
- **YAML format matters** — the config parser (`deploy/parse_config.py`) is hand-rolled and expects exact formatting. Follow the YAML format rules in onboarding.md (Step 5, "Format rules" section).
```

- [ ] **Step 2: Fix #5 — Add "preserve all top-level sections" to constraints**

In `deploy/managing.md`, after the YAML format constraint (line 10), add a new constraint:

```markdown
- **Preserve all top-level sections** — when editing config.yml, keep all top-level keys (`auth:`, `mimir:`, `users:`, `scopes:`) intact. Only modify values within sections.
```

- [ ] **Step 3: Fix #8 — User ID derivation uses underscores, not hyphens**

In `deploy/managing.md`, find in Option 1 (around line 48):

```markdown
Wait for the name. Derive the user ID (lowercase, spaces to hyphens). Then ask:
```

Replace with:

```markdown
Wait for the name. Derive the user ID using onboarding rules: lowercase, spaces to underscores, strip special characters, must start with a letter. Then ask:
```

- [ ] **Step 4: Fix #2 — Auth check uses config instead of directory listing**

In `deploy/managing.md`, find in Option 4 (around lines 159-163):

```markdown
Check auth:

```bash
ls -la DEPLOY_PATH/data/shared/claude-auth/
```
```

Replace with:

```markdown
Check auth mode:

```bash
python3 deploy/parse_config.py DEPLOY_PATH/config.yml auth.shared
```

If `true`, auth is shared (host credentials mounted). If `false`, per-container login.
```

- [ ] **Step 5: Fix #4 — Health check uses docker inspect instead of curl from container**

In `deploy/managing.md`, find in Option 4 (around lines 165-169):

```markdown
If Mimir enabled, check connectivity from a user container:

```bash
docker exec USER-hermes curl -sf http://mimir:8100/health 2>/dev/null && echo "OK" || echo "UNREACHABLE"
```
```

Replace with:

```markdown
If Mimir enabled, check health:

```bash
docker inspect --format='{{.State.Health.Status}}' mimir 2>/dev/null || echo "no healthcheck"
```
```

- [ ] **Step 6: Fix #3 — Use `docker compose up -d` instead of `docker compose restart` for config changes**

In `deploy/managing.md`, find in Option 5 (around line 194):

```bash
# All
cd DEPLOY_PATH && docker compose restart
```

Replace with:

```bash
# All (applies config changes)
cd DEPLOY_PATH && docker compose up -d
```

Also update the specific user restart to keep `restart` (that's fine for individual containers):

Leave `docker compose restart {id}-hermes` and `docker compose restart mimir` unchanged — those are per-container restarts that don't need config changes.

- [ ] **Step 7: Fix #6 — Add wrapper install prompt after adding a user**

In `deploy/managing.md`, find the end of Option 1 (after the "Report what happened" block, around line 77). Add after the report:

```markdown
Then ask about the wrapper:

> "Want me to install the `hermes` wrapper for {name}?
> 1. **fish** — installs to `~/.config/fish/conf.d/`
> 2. **bash** — adds to `~/.bashrc`
> 3. **zsh** — adds to `~/.zshrc`
> 4. **Skip**"

Install using the same method as onboarding Step 6.
```

- [ ] **Step 8: Fix #7 — Ask about scopes when adding users (if Mimir enabled)**

In `deploy/managing.md`, in Option 1, find the scope access question (around lines 55-58):

```markdown
If Mimir is enabled, ask about scope access:

> "{name} will automatically get a personal scope (`{id}`). Should they have access to any shared scopes?
> Current shared scopes: {list of non-personal scopes}"

Present options as a numbered list of existing shared scopes plus "None".
```

Add after "Present options as a numbered list of existing shared scopes plus 'None'.":

```markdown
Also ask if they want to create any new shared scopes for this user:

> "Want to create a new shared scope for {name}? (Or just say 'no' to continue.)"

If yes, collect the scope name, description, and which existing users should also get access. Add the new scope to both the `scopes:` and relevant `users:` sections in config.yml.
```

- [ ] **Step 9: Verify all 8 fixes**

```bash
cd /home/marvin/repositories/private/hermes
# Fix 1: No "Step 7" reference (old step number)
grep -n 'Step 7' deploy/managing.md
# Fix 5: "preserve all top-level sections" constraint exists
grep -n 'Preserve all top-level' deploy/managing.md
# Fix 8: "underscores" in ID derivation
grep -n 'underscore' deploy/managing.md
# Fix 2: No claude-auth directory listing
grep -n 'claude-auth' deploy/managing.md
# Fix 4: docker inspect for health
grep -n 'docker inspect.*Health' deploy/managing.md
# Fix 3: "up -d" for all containers
grep -n 'compose up -d' deploy/managing.md
# Fix 6: wrapper install prompt in Option 1
grep -n 'wrapper' deploy/managing.md
# Fix 7: new shared scope question
grep -n 'new shared scope' deploy/managing.md
```

Expected:
- Fix 1: No output (no "Step 7")
- Fix 5: One match
- Fix 8: At least one match
- Fix 2: No output
- Fix 4: At least one match
- Fix 3: At least one match
- Fix 6: At least one match in the add-user section
- Fix 7: At least one match

- [ ] **Step 10: Commit**

```bash
cd /home/marvin/repositories/private/hermes
git add deploy/managing.md
git commit -m "docs: 8 fixes to managing.md — auth check, health check, scopes, wrappers, ID rules"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] 7-step onboarding flow — Task 5
- [x] User ID derivation rules (underscores, not hyphens) — Tasks 3 (BUG 6), 5, 6
- [x] BUG 1: KEY_VAR hyphens in .env — Task 3
- [x] BUG 2: seed.sql not regenerated — Task 3
- [x] BUG 3: .mcp.json wrong Mimir port — Task 2
- [x] BUG 4: .env MIMIR_PORT stale — Task 3
- [x] BUG 5: Boolean normalization — Task 1
- [x] BUG 6: Regex allows hyphens — Task 3
- [x] managing.md fix 1: Step number reference — Task 6
- [x] managing.md fix 2: Auth check directory — Task 6
- [x] managing.md fix 3: docker compose restart → up -d — Task 6
- [x] managing.md fix 4: Health check curl → docker inspect — Task 6
- [x] managing.md fix 5: Preserve top-level sections — Task 6
- [x] managing.md fix 6: Wrapper install after adding user — Task 6
- [x] managing.md fix 7: Scope management for new users — Task 6
- [x] managing.md fix 8: User ID hyphens → underscores — Task 6
- [x] config.yml.example clarifying comment — Task 4

**Placeholder scan:** No TBD, TODO, "implement later", or "similar to Task N" patterns.

**Type consistency:** `tr '[:lower:]-' '[:upper:]_'` used consistently across all 6 KEY_VAR locations. `INSERT OR IGNORE` used for all 4 seed.sql insert types. `"true"` (lowercase) used for IS_ADMIN comparison.
