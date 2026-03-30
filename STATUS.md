# Hermes — Project Status

Last updated: 2026-03-30

## Phase 1: Product Separation (Complete)

Hermes and Mimir split into independent products.

- [x] Sync fork to upstream release-2-agents-skills
- [x] Rebrand MARVIN to Hermes (.hermes/, .hermes-source, CLAUDE.md, setup.sh, all commands)
- [x] Mimir package rename (assistant_mcp -> mimir_mcp) — repo at `/home/marvin/repositories/private/mimir/`
- [x] Mimir Dockerfile, README, integration docs, seed CLI
- [x] 144 Mimir tests passing

Specs: `docs/specs/2026-03-26-hermes-mimir-separation-design.md` (in marvin repo)

## Phase 2: Multi-User Deployment (Complete — pending Docker test)

Config-driven multi-user container orchestration.

- [x] `deploy/setup.sh` — config-driven setup (11 phases, idempotent)
- [x] `deploy/config.yml.example` — template config
- [x] `deploy/parse_config.py` — lightweight YAML parser (stdlib only)
- [x] `deploy/Dockerfile` — user container (Debian + Claude Code + tmux)
- [x] `deploy/entrypoint.sh` — auth copy + tmux start
- [x] `deploy/hermes.sh` — named session management function
- [x] `deploy/templates/` — docker-compose, mcp.json, host-wrapper templates
- [x] `/deploy` slash command with LLM-guided onboarding (`deploy/onboarding.md`)
- [x] `/help` updated with `/deploy`
- [x] Local testing passed (file generation, config parsing, idempotency)
- [ ] **Docker build test** — needs Docker Compose v2 (local host only has v1)
- [ ] **Production deployment** — run `/deploy` on ai-assistant-private-1

Specs: `docs/specs/2026-03-28-hermes-multi-user-deployment-design.md`, `docs/specs/2026-03-30-deploy-onboarding-design.md` (in marvin repo)

## Phase 3: Ark Rules (Not Started)

Safety layer with pattern-matching on tool calls.

- [ ] Design spec
- [ ] Mount point exists in containers (`/opt/hermes/rules/`), ready for rules
- [ ] Config could extend with `profiles:` section (developer, standard, etc.)

## Known Issues

- Docker Compose v2 required for `docker compose` commands. Host has v1 (`docker-compose`). Setup.sh uses v2 syntax.
- Claude Code installation method in Dockerfile (`npm install -g @anthropic-ai/claude-code`) should be verified against current recommended installation at build time.
- `.marvin-source` in Jimmy's MARVIN instance points to upstream `SterlingChin/marvin-template` (at `/home/marvin/repositories/contributions/marvin-template/`), not to the Hermes fork. This is intentional — MARVIN syncs from upstream, Hermes is a separate product.

## Repos

| Repo | Location | Remote |
|------|----------|--------|
| Hermes | `/home/marvin/repositories/private/hermes/` | `jimmy-larsson/hermes-template` |
| Mimir | `/home/marvin/repositories/private/mimir/` | `jimmy-larsson/mimir` |
| Upstream | `/home/marvin/repositories/contributions/marvin-template/` | `SterlingChin/marvin-template` |
