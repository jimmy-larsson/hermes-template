# Hermes Onboarding Redesign

**Date:** 2026-04-01
**Status:** Approved

## Summary

Redesign the `/deploy` onboarding from 12 implementation-focused steps to 7 user-focused steps. Fix 3 HIGH bugs, 2 MEDIUM bugs in setup.sh. Update managing.md for consistency with new auth config and GHCR-based Mimir.

## Motivation

Team review (5 agents: flow-tester, edge-case, script-auditor, ux-reviewer, managing-auditor) identified:
- The 12-step flow maps to implementation details, not user decisions
- 3 HIGH bugs that cause silent failures (hyphenated user IDs, seed.sql not regenerated, wrong Mimir port in MCP config)
- managing.md is inconsistent with recent auth, Mimir, and wrapper changes

## Design

### 1. Seven-Step Onboarding Flow

The current 12 steps collapse into 7 that map to the user's mental model:

| Step | User sees | LLM does internally |
|------|----------|-------------------|
| **1. Welcome + Scaffold** | Greeting, deploy path question | Run first setup.sh to create directory and config template, read the generated config |
| **2. Users** | Name, admin/regular per user, review checkpoint | Collect user list, derive IDs (underscores, not hyphens) |
| **3. Shared Access + Mimir** | "Do users need to share data?" → scope collection → Mimir auto-enabled or asked | Merge old Steps 5+6 into one natural conversation |
| **4. Auth** | "Share host credentials or per-container login?" | Store auth.shared for config |
| **5. Deploy** | "Here's your config — ready?" → progress output | Write config.yml, run setup.sh, relay validation results |
| **6. Wrapper** | "Want the hermes command? Which shell?" | Install fish/bash/zsh wrapper |
| **7. Summary** | Verification, connection commands, management commands | Present structured summary |

Changes from current flow:
- Scaffold + read config + write config: invisible bookkeeping (Steps 1 and 5)
- Scopes + Mimir: one conversation (Step 3)
- Verify + wrap up: merged (Step 7)
- "Read the generated config": removed (LLM internal)

### 2. User ID Derivation Rules

User IDs must be valid bash variable name suffixes (used in .env as `API_KEY_USERID`):
- Lowercase letters, numbers, underscores only
- Spaces → underscores, hyphens → underscores
- Strip special characters
- Must start with a letter
- Examples: "Mary Jane" → `mary_jane`, "O'Brien" → `obrien`

### 3. Bug Fixes — setup.sh

#### BUG 1 (HIGH): Hyphens in user IDs break .env variable expansion

All occurrences of:
```bash
KEY_VAR="API_KEY_$(echo "$user_id" | tr '[:lower:]' '[:upper:]')"
```
Must become:
```bash
KEY_VAR="API_KEY_$(echo "$user_id" | tr '[:lower:]-' '[:upper:]_')"
```

Affects: Phase 4 (.env generation), Phase 5 (compose generation), Phase 6 (.mcp.json), Phase 7 (seed.sql), validate_generated_files(), validate_runtime().

#### BUG 2 (HIGH): seed.sql not regenerated on re-run

Current: `if [ ! -f "$SEED_FILE" ]` skips seed generation when file exists. Adding users to config.yml and re-running setup.sh silently fails — new users have no Mimir auth.

Fix: Always regenerate seed.sql. Use `INSERT OR IGNORE INTO` for idempotency:
```sql
INSERT OR IGNORE INTO scopes (id, name, description) VALUES (...);
INSERT OR IGNORE INTO users (id, name, is_admin, api_key) VALUES (...);
INSERT OR IGNORE INTO scope_members (scope_id, user_id) VALUES (...);
INSERT OR IGNORE INTO activity_cursor (user_id, last_seen_history_id) VALUES (...);
```

#### BUG 3 (HIGH): .mcp.json uses external port instead of internal Docker port

`templates/mcp.json.tmpl` has `"url": "http://mimir:%%MIMIR_PORT%%/sse"` which substitutes the host-exposed port. Containers communicate over the Docker bridge where Mimir always listens on 8100.

Fix: Hardcode internal port:
```json
"url": "http://mimir:8100/sse"
```
Remove `%%MIMIR_PORT%%` substitution from setup.sh.

#### BUG 4 (MEDIUM): .env MIMIR_PORT not updated on re-run

.env is only created if it doesn't exist. If user changes `mimir.port` and re-runs, MIMIR_PORT is stale.

Fix: After the creation guard, update the port:
```bash
sed -i "s/^MIMIR_PORT=.*/MIMIR_PORT=$MIMIR_PORT/" "$ENV_FILE"
```

#### BUG 5 (LOW): Boolean normalization in parse_config.py

`user.X.admin` returns Python `True`/`False` (capital). setup.sh compensates with `[ "$IS_ADMIN" = "True" ]` — works but fragile.

Fix: Normalize in parse_config.py:
```python
if isinstance(val, bool):
    print("true" if val else "false")
```
Update setup.sh to compare `"true"` (lowercase).

### 4. managing.md Fixes

| # | Issue | Fix |
|---|-------|-----|
| 1 | References "onboarding.md Step 7" | Update to "Step 8" (or the new step number after redesign) |
| 2 | Auth check references `data/shared/claude-auth/` directory | Check `auth.shared` from config instead |
| 3 | `docker compose restart` for all containers | Use `docker compose up -d` to apply config changes |
| 4 | Health check curls SSE endpoint from user container | Use `docker inspect --format='{{.State.Health.Status}}' mimir` |
| 5 | Editing config.yml doesn't mention preserving auth section | Add to constraints: "preserve all top-level sections" |
| 6 | Adding a user doesn't offer wrapper install | Add wrapper install prompt after user addition |
| 7 | No scope management when adding users | Ask about new shared scopes for new user |
| 8 | User ID derivation uses hyphens | Match onboarding: underscores |

### 5. Config Template Update

Add comment to config.yml.example clarifying scopes are only relevant with Mimir enabled, since the example shows scopes with `mimir.enabled: false`.

## Scope

### In scope
- Rewrite onboarding.md to 7-step flow
- Fix 5 bugs in setup.sh
- Fix boolean normalization in parse_config.py
- Update managing.md (8 fixes)
- Update mcp.json.tmpl (hardcode internal port)
- Update config.yml.example (clarifying comment)

### Out of scope
- Wrapper template changes (already working)
- setup.sh validation function rewrites (working, just need the KEY_VAR fix)
- CI/CD changes

## Files affected

| File | Changes |
|------|---------|
| `deploy/onboarding.md` | Full rewrite — 7-step flow |
| `deploy/setup.sh` | 5 bug fixes (KEY_VAR, seed.sql, MIMIR_PORT) |
| `deploy/parse_config.py` | Boolean normalization |
| `deploy/managing.md` | 8 consistency fixes |
| `deploy/templates/mcp.json.tmpl` | Hardcode internal port |
| `deploy/config.yml.example` | Clarifying comment |
