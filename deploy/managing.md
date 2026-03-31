# Hermes Deployment — Management Guide

This guide is read by Claude Code when the user runs `/deploy` on an **existing deployment**. Follow these steps to help the user manage their deployment.

---

## Important Constraints

- **DO NOT use interactive bash prompts** (`read`, `select`, etc.) — they don't work from Claude Code. All user interaction must be conversational.
- **YAML format matters** — the config parser (`deploy/parse_config.py`) is hand-rolled and expects exact formatting. Follow the structure from onboarding.md Step 7 precisely.

---

## Step 1: Detect current state

Read the existing config:

```bash
cat DEPLOY_PATH/config.yml
```

Check container status:

```bash
cd DEPLOY_PATH && docker compose ps 2>/dev/null
```

Present the current state and ask what they'd like to do:

> "Your deployment at `DEPLOY_PATH` has **N users**: {list of names}.
> Mimir is **enabled/disabled**.
>
> What would you like to do?
> 1. **Add a user**
> 2. **Remove a user**
> 3. **Enable/disable Mimir**
> 4. **Check status** — verify containers, auth, and connectivity
> 5. **Restart containers**"

---

## Option 1: Add a user

Ask one question at a time, same as onboarding:

> "What's the new user's name?"

Wait for the name. Derive the user ID (lowercase, spaces to hyphens). Then ask:

> "Got it — I'll use `{id}` as the user ID. Is {name} an admin or a regular user?
> 1. **Admin** — can manage scopes and users in Mimir
> 2. **Regular** — standard access"

If Mimir is enabled, ask about scope access:

> "{name} will automatically get a personal scope (`{id}`). Should they have access to any shared scopes?
> Current shared scopes: {list of non-personal scopes}"

Present options as a numbered list of existing shared scopes plus "None".

Then update the config:

1. Read the current `DEPLOY_PATH/config.yml`
2. Add the new user entry to the `users:` section
3. If Mimir enabled, add the user's personal scope to `scopes:` and add scope memberships
4. Write the updated config using the Write tool (**not bash echo/cat**)
5. Run setup.sh to apply:

```bash
./deploy/setup.sh DEPLOY_PATH
```

Report what happened:

> "Added {name} (`{id}`, {role}). Container `{id}-hermes` is starting.
>
> To connect: `docker exec -it {id}-hermes tmux attach -t hermes`"

---

## Option 2: Remove a user

Show current users as a numbered list:

> "Which user should I remove?
> 1. Jimmy (`jimmy`, admin)
> 2. Alex (`alex`, regular)
>
> **Warning:** This removes the user from config and stops their container. Their workspace data is preserved in `DEPLOY_PATH/data/users/{id}/`."

Wait for selection. Then:

1. Read the current `DEPLOY_PATH/config.yml`
2. Remove the user from `users:` section
3. If Mimir enabled, remove their personal scope from `scopes:` and scope memberships
4. Write the updated config using the Write tool
5. Stop and remove the user's container:

```bash
cd DEPLOY_PATH && docker compose stop {id}-hermes && docker compose rm -f {id}-hermes
```

6. Regenerate docker-compose.yml by running setup.sh:

```bash
./deploy/setup.sh DEPLOY_PATH
```

Report:

> "Removed {name} from the deployment. Container stopped.
> Workspace data is preserved at `DEPLOY_PATH/data/users/{id}/` — delete manually if no longer needed."

---

## Option 3: Enable/disable Mimir

If enabling Mimir:

> "Enabling Mimir. I'll set up personal scopes for each existing user.
> Want to add any shared scopes? (e.g., `household`, `team`)"

Follow the same scope collection flow from onboarding.md Step 6.

If disabling Mimir:

> "Disabling Mimir. Existing memory data will be preserved in `DEPLOY_PATH/data/mimir/` but won't be accessible.
> Proceed?"

Wait for confirmation. Then:

1. Read and update `DEPLOY_PATH/config.yml` — toggle `mimir.enabled`
2. If enabling, add scopes section
3. If disabling, leave scopes in config (harmless, preserved for re-enable)
4. Write the config using the Write tool
5. Run setup.sh:

```bash
./deploy/setup.sh DEPLOY_PATH
```

---

## Option 4: Check status

Run diagnostics:

```bash
cd DEPLOY_PATH && docker compose ps
```

For each running container:

```bash
docker exec USER-hermes tmux list-sessions 2>/dev/null
docker exec USER-hermes claude --version 2>/dev/null
```

Check auth:

```bash
ls -la DEPLOY_PATH/data/shared/claude-auth/
```

If Mimir enabled, check connectivity from a user container:

```bash
docker exec USER-hermes curl -sf http://mimir:8100/health 2>/dev/null && echo "OK" || echo "UNREACHABLE"
```

Present results in a table:

> | User | Container | tmux | Claude Code | Auth |
> |------|-----------|------|-------------|------|
> | Jimmy | running | active | v1.x.x | shared |
> | Alex | running | active | v1.x.x | shared |
> | Mimir | running | — | — | — |

---

## Option 5: Restart containers

Ask what to restart:

> "What should I restart?
> 1. **All containers**
> 2. **A specific user** — pick from the list
> 3. **Mimir only**"

Then run the appropriate command:

```bash
# All
cd DEPLOY_PATH && docker compose restart

# Specific user
cd DEPLOY_PATH && docker compose restart {id}-hermes

# Mimir
cd DEPLOY_PATH && docker compose restart mimir
```

Report when done.
