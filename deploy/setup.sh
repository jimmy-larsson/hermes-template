#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Hermes Multi-User Deployment Setup
# ============================================================================
# Two modes:
#
#   Full deploy — reads config.yml and generates a complete deployment:
#     ./setup.sh              # Interactive (prompts for deploy location)
#     ./setup.sh /path/to/dir # Non-interactive
#
#   Connect only — install just the wrapper for remote access:
#     ./setup.sh --connect user@host --user jimmy [--port 22] [--key ~/.ssh/id]
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PARSER="$SCRIPT_DIR/parse_config.py"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}==>${NC} $1"; }
warn()  { echo -e "${YELLOW}==>${NC} $1"; }
error() { echo -e "${RED}==>${NC} $1" >&2; }
pass()  { echo -e "  ${GREEN}✓${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; }

# ── Validation functions ──────────────────────────────────────────────────

validate_config() {
    local config="$1"
    local errors=0
    echo ""
    info "Validating config.yml..."

    # YAML parses at all
    if ! python3 "$PARSER" "$config" mimir.enabled >/dev/null 2>&1; then
        fail "config.yml failed to parse"; return 1
    fi
    pass "YAML parses successfully"

    # Mimir section exists
    local mimir_enabled
    mimir_enabled=$(python3 "$PARSER" "$config" mimir.enabled 2>/dev/null || echo "")
    if [ -z "$mimir_enabled" ]; then
        fail "Missing mimir.enabled"; errors=$((errors + 1))
    elif [ "$mimir_enabled" != "true" ] && [ "$mimir_enabled" != "false" ]; then
        fail "mimir.enabled must be true or false, got: $mimir_enabled"; errors=$((errors + 1))
    else
        pass "mimir.enabled: $mimir_enabled"
    fi

    if [ "$mimir_enabled" = "true" ]; then
        local mimir_port
        mimir_port=$(python3 "$PARSER" "$config" mimir.port 2>/dev/null || echo "")
        if [ -z "$mimir_port" ] || ! [[ "$mimir_port" =~ ^[0-9]+$ ]]; then
            fail "mimir.port must be a number, got: '$mimir_port'"; errors=$((errors + 1))
        else
            pass "mimir.port: $mimir_port"
        fi
    fi

    # Users exist and are valid
    local user_ids
    user_ids=$(python3 "$PARSER" "$config" user_ids 2>/dev/null || echo "")
    if [ -z "$user_ids" ]; then
        fail "No users defined"; errors=$((errors + 1))
    else
        local user_count=$(echo $user_ids | wc -w)
        pass "Users: $user_ids ($user_count total)"
    fi

    # Each user has required fields
    for uid in $user_ids; do
        local uname
        uname=$(python3 "$PARSER" "$config" "user.$uid.name" 2>/dev/null || echo "")
        if [ -z "$uname" ]; then
            fail "User '$uid' missing name"; errors=$((errors + 1))
        fi

        local uadmin
        uadmin=$(python3 "$PARSER" "$config" "user.$uid.admin" 2>/dev/null || echo "")
        if [ -z "$uadmin" ]; then
            fail "User '$uid' missing admin field"; errors=$((errors + 1))
        fi

        # User ID format: lowercase, no spaces
        if ! [[ "$uid" =~ ^[a-z][a-z0-9_-]*$ ]]; then
            fail "User ID '$uid' invalid (must be lowercase, start with letter, no spaces)"; errors=$((errors + 1))
        fi
    done

    # Scopes exist
    local scopes_json
    scopes_json=$(python3 "$PARSER" "$config" scopes 2>/dev/null || echo "[]")
    local scope_ids
    scope_ids=$(echo "$scopes_json" | python3 -c "import json,sys; [print(s['id']) for s in json.load(sys.stdin)]" 2>/dev/null)
    if [ -z "$scope_ids" ]; then
        if [ "$mimir_enabled" = "true" ]; then
            fail "No scopes defined but Mimir is enabled"; errors=$((errors + 1))
        fi
    else
        pass "Scopes: $(echo $scope_ids | tr '\n' ' ')"
    fi

    # Each user's scopes reference existing scopes
    if [ "$mimir_enabled" = "true" ] && [ -n "$scope_ids" ]; then
        local users_json
        users_json=$(python3 "$PARSER" "$config" users 2>/dev/null || echo "[]")
        local bad_refs
        bad_refs=$(echo "$users_json" | python3 -c "
import json, sys
users = json.load(sys.stdin)
scope_set = set('''$scope_ids'''.split())
for u in users:
    for s in u.get('scopes', []):
        if s not in scope_set:
            print(f\"User '{u['id']}' references undefined scope '{s}'\")
" 2>/dev/null)
        if [ -n "$bad_refs" ]; then
            while IFS= read -r line; do
                fail "$line"; errors=$((errors + 1))
            done <<< "$bad_refs"
        else
            pass "All user scope references are valid"
        fi
    fi

    # Check for duplicate user IDs
    local dupes
    dupes=$(echo $user_ids | tr ' ' '\n' | sort | uniq -d)
    if [ -n "$dupes" ]; then
        fail "Duplicate user IDs: $dupes"; errors=$((errors + 1))
    fi

    # Check for duplicate scope IDs
    if [ -n "$scope_ids" ]; then
        dupes=$(echo "$scope_ids" | sort | uniq -d)
        if [ -n "$dupes" ]; then
            fail "Duplicate scope IDs: $dupes"; errors=$((errors + 1))
        fi
    fi

    if [ $errors -gt 0 ]; then
        error "Config validation failed with $errors error(s)"
        return 1
    fi
    pass "Config validation passed"
    echo ""
    return 0
}

validate_generated_files() {
    local deploy_dir="$1"
    local user_ids="$2"
    local mimir_enabled="$3"
    local errors=0
    echo ""
    info "Validating generated files..."

    # .env has API keys for all users
    local env_file="$deploy_dir/.env"
    if [ ! -f "$env_file" ]; then
        fail "Missing .env file"; errors=$((errors + 1))
    else
        for uid in $user_ids; do
            local key_var="API_KEY_$(echo "$uid" | tr '[:lower:]' '[:upper:]')"
            if grep -q "^${key_var}=" "$env_file" 2>/dev/null; then
                pass ".env has API key for $uid"
            else
                fail ".env missing API key for $uid ($key_var)"; errors=$((errors + 1))
            fi
        done
    fi

    # docker-compose.yml has all services
    local compose="$deploy_dir/docker-compose.yml"
    if [ ! -f "$compose" ]; then
        fail "Missing docker-compose.yml"; errors=$((errors + 1))
    else
        for uid in $user_ids; do
            if grep -q "${uid}-hermes:" "$compose"; then
                pass "docker-compose.yml has ${uid}-hermes service"
            else
                fail "docker-compose.yml missing ${uid}-hermes service"; errors=$((errors + 1))
            fi
        done
        if [ "$mimir_enabled" = "true" ]; then
            if grep -q "mimir:" "$compose"; then
                pass "docker-compose.yml has mimir service"
            else
                fail "docker-compose.yml missing mimir service"; errors=$((errors + 1))
            fi
        fi
    fi

    # Each user has workspace and .mcp.json
    for uid in $user_ids; do
        local workspace="$deploy_dir/data/users/$uid/workspace"
        if [ -d "$workspace" ]; then
            pass "$uid workspace exists"
        else
            fail "$uid workspace missing at $workspace"; errors=$((errors + 1))
        fi

        if [ -f "$workspace/CLAUDE.md" ]; then
            pass "$uid CLAUDE.md exists"
        else
            fail "$uid CLAUDE.md missing"; errors=$((errors + 1))
        fi

        if [ "$mimir_enabled" = "true" ]; then
            local mcp_json="$workspace/.mcp.json"
            if [ -f "$mcp_json" ]; then
                # Verify it contains a valid API key (not a placeholder)
                if grep -q "%%API_KEY%%" "$mcp_json" 2>/dev/null; then
                    fail "$uid .mcp.json still has placeholder %%API_KEY%%"; errors=$((errors + 1))
                else
                    pass "$uid .mcp.json configured"
                fi
            else
                fail "$uid .mcp.json missing"; errors=$((errors + 1))
            fi
        fi
    done

    # Seed file (if Mimir enabled)
    if [ "$mimir_enabled" = "true" ]; then
        local seed="$deploy_dir/data/mimir/seed.sql"
        if [ ! -f "$seed" ]; then
            fail "Missing seed.sql"; errors=$((errors + 1))
        else
            for uid in $user_ids; do
                if grep -q "'$uid'" "$seed"; then
                    pass "seed.sql has user $uid"
                else
                    fail "seed.sql missing user $uid"; errors=$((errors + 1))
                fi
            done
            # Check activity cursors exist for all users
            for uid in $user_ids; do
                if grep -q "activity_cursor.*'$uid'" "$seed"; then
                    pass "seed.sql has activity cursor for $uid"
                else
                    fail "seed.sql missing activity cursor for $uid"; errors=$((errors + 1))
                fi
            done
        fi
    fi

    if [ $errors -gt 0 ]; then
        error "File validation failed with $errors error(s)"
        return 1
    fi
    pass "File validation passed"
    echo ""
    return 0
}

validate_runtime() {
    local deploy_dir="$1"
    local user_ids="$2"
    local mimir_enabled="$3"
    local mimir_port="$4"
    local errors=0
    echo ""
    info "Validating runtime..."

    # All containers are running
    for uid in $user_ids; do
        local status
        status=$(docker inspect -f '{{.State.Status}}' "${uid}-hermes" 2>/dev/null || echo "not found")
        if [ "$status" = "running" ]; then
            pass "${uid}-hermes container running"
        else
            fail "${uid}-hermes container: $status"; errors=$((errors + 1))
        fi
    done

    if [ "$mimir_enabled" = "true" ]; then
        # Mimir container running
        local status
        status=$(docker inspect -f '{{.State.Status}}' mimir 2>/dev/null || echo "not found")
        if [ "$status" = "running" ]; then
            pass "mimir container running"
        else
            fail "mimir container: $status"; errors=$((errors + 1))
        fi

        # Mimir health check
        sleep 2  # give it a moment to start
        local health
        health=$(docker inspect --format='{{.State.Health.Status}}' mimir 2>/dev/null || echo "no healthcheck")
        if [ "$health" = "healthy" ]; then
            pass "mimir healthcheck: healthy"
        elif [ "$health" = "starting" ]; then
            warn "mimir healthcheck: starting (may need a few more seconds)"
        else
            fail "mimir healthcheck: $health"; errors=$((errors + 1))
        fi

        # Each user's API key exists in seed data
        local env_file="$deploy_dir/.env"
        set -a; source "$env_file"; set +a
        for uid in $user_ids; do
            local key_var="API_KEY_$(echo "$uid" | tr '[:lower:]' '[:upper:]')"
            local api_key="${!key_var}"
            local db_user
            db_user=$(docker exec mimir python3 -c "
import sqlite3
c = sqlite3.connect('/data/mimir.db')
r = c.execute('SELECT id FROM users WHERE api_key = ?', ('$api_key',)).fetchone()
print(r[0] if r else '')
" 2>/dev/null || echo "")
            if [ "$db_user" = "$uid" ]; then
                pass "$uid API key resolves correctly in DB"
            else
                fail "$uid API key not found or mismatched (got: '$db_user')"; errors=$((errors + 1))
            fi
        done

        # Seed data loaded — check via Mimir API by querying the DB directly
        local user_count
        user_count=$(docker exec mimir python3 -c "
import sqlite3
c = sqlite3.connect('/data/mimir.db')
print(c.execute('SELECT COUNT(*) FROM users').fetchone()[0])
" 2>/dev/null || echo "0")
        local expected_count=$(echo $user_ids | wc -w)
        if [ "$user_count" = "$expected_count" ]; then
            pass "Seed data loaded ($user_count users in DB)"
        else
            fail "Seed data: expected $expected_count users, found $user_count"; errors=$((errors + 1))
        fi
    fi

    # tmux session exists in each container
    for uid in $user_ids; do
        if docker exec "${uid}-hermes" tmux has-session -t hermes 2>/dev/null; then
            pass "${uid}-hermes tmux session exists"
        else
            fail "${uid}-hermes tmux session missing"; errors=$((errors + 1))
        fi
    done

    if [ $errors -gt 0 ]; then
        error "Runtime validation failed with $errors error(s)"
        return 1
    fi
    pass "Runtime validation passed"
    echo ""
    return 0
}

# ── Connect mode: install remote wrapper only ─────────────────────────────

if [ "${1:-}" = "--connect" ]; then
    REMOTE_HOST=""
    CONNECT_USER=""
    SSH_PORT=""
    SSH_KEY=""

    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            --user)  CONNECT_USER="$2"; shift 2 ;;
            --port)  SSH_PORT="$2"; shift 2 ;;
            --key)   SSH_KEY="$2"; shift 2 ;;
            *)
                if [ -z "$REMOTE_HOST" ]; then
                    REMOTE_HOST="$1"; shift
                else
                    error "Unknown argument: $1"; exit 1
                fi
                ;;
        esac
    done

    if [ -z "$REMOTE_HOST" ] || [ -z "$CONNECT_USER" ]; then
        echo "Usage: $0 --connect user@host --user container-user [--port 22] [--key ~/.ssh/id]"
        echo ""
        echo "  user@host       SSH target (e.g., jimmy@vps.example.com)"
        echo "  --user NAME     Container user ID (e.g., jimmy)"
        echo "  --port PORT     SSH port (default: 22)"
        echo "  --key PATH      SSH key path (default: ssh default)"
        exit 1
    fi

    CONTAINER="${CONNECT_USER}-hermes"
    WRAPPER_TEMPLATE="$SCRIPT_DIR/templates/host-wrapper.sh.tmpl"

    if [ ! -f "$WRAPPER_TEMPLATE" ]; then
        error "Template not found: $WRAPPER_TEMPLATE"
        exit 1
    fi

    # Detect shell and choose install location
    CURRENT_SHELL=$(basename "${SHELL:-bash}")
    if [ "$CURRENT_SHELL" = "fish" ]; then
        INSTALL_DIR="$HOME/.config/fish/conf.d"
        INSTALL_FILE="$INSTALL_DIR/hermes.fish"
        # Generate fish wrapper
        mkdir -p "$INSTALL_DIR"
        cat > "$INSTALL_FILE" << FISHEOF
# hermes — remote access to ${CONNECT_USER}'s Hermes AI assistant
# Generated by setup.sh --connect

function __hermes_exec
    set -l flags \$argv[1]
    set -e argv[1]
    set -l ssh_opts -t
    test -n "$SSH_PORT"; and set ssh_opts \$ssh_opts -p $SSH_PORT
    test -n "$SSH_KEY"; and set ssh_opts \$ssh_opts -i $SSH_KEY
    ssh \$ssh_opts $REMOTE_HOST docker exec \$flags $CONTAINER \$argv
end

function hermes
    set -l cmd \$argv[1]

    switch "\$cmd"
        case shell
            __hermes_exec -it bash -l
        case list
            __hermes_exec -i tmux list-windows -t hermes -F '  #{window_index}: #{window_name}' 2>/dev/null
            or echo 'No Hermes session running.'
        case ''
            __hermes_exec -it tmux attach -t hermes 2>/dev/null
            or __hermes_exec -it bash -lc hermes
        case '*'
            __hermes_exec -it bash -lc "hermes \$cmd"
    end
end
FISHEOF
        info "Installed fish wrapper: $INSTALL_FILE"
    else
        INSTALL_DIR="$HOME/.config/hermes"
        INSTALL_FILE="$INSTALL_DIR/wrapper.sh"
        mkdir -p "$INSTALL_DIR"

        # Generate bash wrapper from template
        sed -e "s/%%USER_ID%%/$CONNECT_USER/g" "$WRAPPER_TEMPLATE" > "$INSTALL_FILE"

        # Fill in SSH config
        sed -i "s|^HERMES_REMOTE=\"\"|HERMES_REMOTE=\"$REMOTE_HOST\"|" "$INSTALL_FILE"
        [ -n "$SSH_PORT" ] && sed -i "s|^HERMES_SSH_PORT=\"\"|HERMES_SSH_PORT=\"$SSH_PORT\"|" "$INSTALL_FILE"
        [ -n "$SSH_KEY" ] && sed -i "s|^HERMES_SSH_KEY=\"\"|HERMES_SSH_KEY=\"$SSH_KEY\"|" "$INSTALL_FILE"

        info "Installed bash wrapper: $INSTALL_FILE"

        # Add to shell config if not already sourced
        SHELL_RC="$HOME/.bashrc"
        [ -f "$HOME/.zshrc" ] && SHELL_RC="$HOME/.zshrc"
        SOURCE_LINE="source $INSTALL_FILE"
        if ! grep -qF "$SOURCE_LINE" "$SHELL_RC" 2>/dev/null; then
            echo "" >> "$SHELL_RC"
            echo "# Hermes remote wrapper" >> "$SHELL_RC"
            echo "$SOURCE_LINE" >> "$SHELL_RC"
            info "Added to $SHELL_RC"
        fi
    fi

    echo ""
    info "Connected to $REMOTE_HOST as $CONNECT_USER"
    echo ""
    echo "  hermes            — AI assistant (tmux + Claude Code)"
    echo "  hermes <name>     — named Claude Code session"
    echo "  hermes shell      — plain bash shell in container"
    echo "  hermes list       — show active sessions"
    echo ""
    echo "  Restart your shell or run: source $INSTALL_FILE"
    exit 0
fi

# ── Full deploy mode ──────────────────────────────────────────────────────

# ── Phase 1: Determine deploy location ──────────────────────────────────────

if [ -n "${1:-}" ]; then
    DEPLOY_DIR="$1"
else
    read -rp "Deploy location [${HOME}/hermes]: " DEPLOY_DIR
    DEPLOY_DIR="${DEPLOY_DIR:-${HOME}/hermes}"
fi

DEPLOY_DIR="$(realpath -m "$DEPLOY_DIR")"
info "Deploy location: $DEPLOY_DIR"

# ── Phase 2: Initialize deploy directory ────────────────────────────────────

mkdir -p "$DEPLOY_DIR/build" "$DEPLOY_DIR/data/shared/claude-settings"

# Copy build files
cp "$SCRIPT_DIR/Dockerfile" "$DEPLOY_DIR/build/Dockerfile"
cp "$SCRIPT_DIR/entrypoint.sh" "$DEPLOY_DIR/build/entrypoint.sh"
cp "$SCRIPT_DIR/hermes.sh" "$DEPLOY_DIR/build/hermes.sh"
chmod +x "$DEPLOY_DIR/build/entrypoint.sh"

# Copy config if first run
if [ ! -f "$DEPLOY_DIR/config.yml" ]; then
    cp "$SCRIPT_DIR/config.yml.example" "$DEPLOY_DIR/config.yml"
    warn "Created config.yml — edit it now, then re-run setup.sh"
    warn "File: $DEPLOY_DIR/config.yml"
    exit 0
fi

# ── Phase 3: Parse config ───────────────────────────────────────────────────

CONFIG="$DEPLOY_DIR/config.yml"
info "Reading config from $CONFIG"

AUTH_SHARED=$(python3 "$PARSER" "$CONFIG" auth.shared)
MIMIR_ENABLED=$(python3 "$PARSER" "$CONFIG" mimir.enabled)
MIMIR_PORT=$(python3 "$PARSER" "$CONFIG" mimir.port)
USER_IDS=$(python3 "$PARSER" "$CONFIG" user_ids)
USERS_JSON=$(python3 "$PARSER" "$CONFIG" users)
SCOPES_JSON=$(python3 "$PARSER" "$CONFIG" scopes)

info "Auth: $([ "$AUTH_SHARED" = "true" ] && echo "shared credentials" || echo "per-container login")"
info "Mimir: $MIMIR_ENABLED"
info "Users: $(echo $USER_IDS | sed 's/ /, /g')"

# ── Checkpoint: Validate config ────────────────────────────────────────────

validate_config "$CONFIG" || exit 1

# ── Phase 4: Generate API keys (.env) ───────────────────────────────────────

ENV_FILE="$DEPLOY_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "# Generated by setup.sh — API keys and ports" > "$ENV_FILE"
    echo "MIMIR_PORT=$MIMIR_PORT" >> "$ENV_FILE"
    echo "" >> "$ENV_FILE"
fi

for user_id in $USER_IDS; do
    KEY_VAR="API_KEY_$(echo "$user_id" | tr '[:lower:]' '[:upper:]')"
    if ! grep -q "^${KEY_VAR}=" "$ENV_FILE" 2>/dev/null; then
        API_KEY=$(python3 -c "import uuid; print(uuid.uuid4())")
        echo "${KEY_VAR}=${API_KEY}" >> "$ENV_FILE"
        info "Generated API key for $user_id"
    fi
done

# Source the .env for variable access
set -a
source "$ENV_FILE"
set +a

# ── Phase 5: Generate docker-compose.yml ────────────────────────────────────

COMPOSE_FILE="$DEPLOY_DIR/docker-compose.yml"
info "Generating docker-compose.yml"

# Header
cat > "$COMPOSE_FILE" << 'HEADER'
# Generated by setup.sh — do not edit manually.
# Re-run setup.sh to regenerate after config.yml changes.

networks:
  hermes-net:
    driver: bridge

services:
HEADER

# Mimir service (if enabled) — pulls from GitHub Container Registry
if [ "$MIMIR_ENABLED" = "true" ]; then
    cat >> "$COMPOSE_FILE" << 'MIMIR'
  mimir:
    image: ghcr.io/jimmy-larsson/mimir:latest
    container_name: mimir
    networks: [hermes-net]
    restart: unless-stopped
MIMIR
    cat >> "$COMPOSE_FILE" << MIMIR
    ports: ["\${MIMIR_PORT:-$MIMIR_PORT}:8100"]
    volumes:
      - ./data/mimir/data:/data
      - ./data/mimir/seed.sql:/data/seed.sql:ro
    environment:
      - MIMIR_DB_PATH=/data/mimir.db
      - MIMIR_SEED_FILE=/data/seed.sql
      - MIMIR_PORT=8100

MIMIR
fi

# User services
for user_id in $USER_IDS; do
    KEY_VAR="API_KEY_$(echo "$user_id" | tr '[:lower:]' '[:upper:]')"
    AUTH_VOL=""
    if [ "$AUTH_SHARED" = "true" ]; then
        AUTH_VOL="
      - ${HOME}/.claude/.credentials.json:/opt/hermes/auth/.credentials.json:ro"
    fi
    cat >> "$COMPOSE_FILE" << USER
  ${user_id}-hermes:
    build:
      context: ./build
      dockerfile: Dockerfile
    container_name: ${user_id}-hermes
    networks: [hermes-net]
    restart: unless-stopped
    volumes:
      - ./data/users/${user_id}/workspace:/home/user/hermes
      - ./data/users/${user_id}/claude-state:/home/user/.claude
      - ./data/shared/claude-settings:/opt/hermes/settings:ro${AUTH_VOL}
    environment:
      - USER_NAME=${user_id}
    stdin_open: true
    tty: true

USER
done

# ── Phase 6: Create per-user workspaces ─────────────────────────────────────

for user_id in $USER_IDS; do
    USER_DIR="$DEPLOY_DIR/data/users/$user_id"
    WORKSPACE="$USER_DIR/workspace"

    if [ -d "$WORKSPACE/.claude" ]; then
        info "Workspace for $user_id already exists — skipping"
    else
        info "Creating workspace for $user_id"
        mkdir -p "$WORKSPACE" "$USER_DIR/claude-state"

        # Copy template files
        cp -r "$TEMPLATE_DIR/.claude" "$WORKSPACE/.claude"
        cp -r "$TEMPLATE_DIR/state" "$WORKSPACE/state"
        cp "$TEMPLATE_DIR/.env.example" "$WORKSPACE/.env.example"
        mkdir -p "$WORKSPACE/sessions" "$WORKSPACE/reports" "$WORKSPACE/content" \
                 "$WORKSPACE/meetings" "$WORKSPACE/research" "$WORKSPACE/decisions"

        # Generate personalized CLAUDE.md
        USER_NAME=$(python3 "$PARSER" "$CONFIG" "user.$user_id.name")
        sed "s/\[Your Name\]/$USER_NAME/g" "$TEMPLATE_DIR/CLAUDE.md" > "$WORKSPACE/CLAUDE.md"
    fi

    # Generate .mcp.json (if Mimir enabled) — always update, even for existing workspaces
    if [ "$MIMIR_ENABLED" = "true" ]; then
        KEY_VAR="API_KEY_$(echo "$user_id" | tr '[:lower:]' '[:upper:]')"
        API_KEY="${!KEY_VAR}"
        sed -e "s/%%API_KEY%%/$API_KEY/g" \
            "$SCRIPT_DIR/templates/mcp.json.tmpl" > "$USER_DIR/.mcp.json"
        # Copy into workspace for Claude Code to find
        cp "$USER_DIR/.mcp.json" "$WORKSPACE/.mcp.json"
    fi
done

# ── Phase 7: Generate Mimir seed data ───────────────────────────────────────

if [ "$MIMIR_ENABLED" = "true" ]; then
    SEED_FILE="$DEPLOY_DIR/data/mimir/seed.sql"
    mkdir -p "$DEPLOY_DIR/data/mimir/data"

    if [ ! -f "$SEED_FILE" ]; then
        info "Generating Mimir seed data"
        echo "-- Generated by setup.sh" > "$SEED_FILE"
        echo "" >> "$SEED_FILE"

        # Insert scopes
        echo "$SCOPES_JSON" | python3 -c "
import json, sys
for s in json.load(sys.stdin):
    sid = s['id'].replace(\"'\", \"''\")
    name = s['name'].replace(\"'\", \"''\")
    desc = s.get('description', '').replace(\"'\", \"''\")
    print(f\"INSERT INTO scopes (id, name, description) VALUES ('{sid}', '{name}', '{desc}');\")
" >> "$SEED_FILE"
        echo "" >> "$SEED_FILE"

        # Insert users
        for user_id in $USER_IDS; do
            KEY_VAR="API_KEY_$(echo "$user_id" | tr '[:lower:]' '[:upper:]')"
            API_KEY="${!KEY_VAR}"
            USER_NAME=$(python3 "$PARSER" "$CONFIG" "user.$user_id.name")
            IS_ADMIN=$(python3 "$PARSER" "$CONFIG" "user.$user_id.admin")
            IS_ADMIN_SQL="FALSE"
            [ "$IS_ADMIN" = "True" ] && IS_ADMIN_SQL="TRUE"

            echo "INSERT INTO users (id, name, is_admin, api_key) VALUES ('$user_id', '$USER_NAME', $IS_ADMIN_SQL, '$API_KEY');" >> "$SEED_FILE"
        done
        echo "" >> "$SEED_FILE"

        # Insert scope memberships
        echo "$USERS_JSON" | python3 -c "
import json, sys
for u in json.load(sys.stdin):
    for scope in u.get('scopes', []):
        print(f\"INSERT INTO scope_members (scope_id, user_id) VALUES ('{scope}', '{u['id']}');\")
" >> "$SEED_FILE"
        echo "" >> "$SEED_FILE"

        # Insert activity cursors
        for user_id in $USER_IDS; do
            echo "INSERT INTO activity_cursor (user_id, last_seen_history_id) VALUES ('$user_id', 0);" >> "$SEED_FILE"
        done

        info "Seed file: $SEED_FILE"
    fi
fi

# ── Checkpoint: Validate generated files ───────────────────────────────────

validate_generated_files "$DEPLOY_DIR" "$USER_IDS" "$MIMIR_ENABLED" || exit 1

# ── Phase 8: Claude auth ────────────────────────────────────────────────────

if [ "$AUTH_SHARED" = "true" ]; then
    # Ensure the credentials file exists so Docker doesn't create a directory
    CRED_FILE="$HOME/.claude/.credentials.json"
    if [ -f "$CRED_FILE" ]; then
        info "Shared auth: credentials found at $CRED_FILE"
    else
        mkdir -p "$HOME/.claude"
        touch "$CRED_FILE"
        warn "Shared auth enabled but no credentials at $CRED_FILE"
        warn "Run 'claude login' on the host, then restart containers."
    fi
else
    info "Per-container auth: users will run 'claude login' on first connect"
fi

# ── Phase 9: Generate host wrapper scripts ────────────────────────────────

for user_id in $USER_IDS; do
    WRAPPER_SH="$DEPLOY_DIR/data/users/$user_id/hermes-wrapper.sh"
    WRAPPER_FISH="$DEPLOY_DIR/data/users/$user_id/hermes-wrapper.fish"
    sed "s/%%USER_ID%%/$user_id/g" \
        "$SCRIPT_DIR/templates/host-wrapper.sh.tmpl" > "$WRAPPER_SH"
    sed "s/%%USER_ID%%/$user_id/g" \
        "$SCRIPT_DIR/templates/host-wrapper.fish.tmpl" > "$WRAPPER_FISH"
    info "Generated wrappers for $user_id (bash + fish)"
done

# ── Phase 10: Build and start ───────────────────────────────────────────────

if command -v docker &>/dev/null && docker compose version &>/dev/null; then
    info "Building containers..."
    cd "$DEPLOY_DIR"
    docker compose build

    info "Starting all containers..."
    docker compose up -d
else
    warn "Docker not available — skipping build and start."
    warn "Run 'docker compose up -d' from $DEPLOY_DIR when ready."
fi

# ── Checkpoint: Validate runtime ───────────────────────────────────────────

if command -v docker &>/dev/null; then
    validate_runtime "$DEPLOY_DIR" "$USER_IDS" "$MIMIR_ENABLED" "${MIMIR_PORT:-8100}" || warn "Runtime validation had failures — check above."
fi

# ── Phase 11: Initialize git ────────────────────────────────────────────────

if [ ! -d "$DEPLOY_DIR/.git" ]; then
    cd "$DEPLOY_DIR"
    cat > .gitignore << 'GITIGNORE'
.env
data/shared/claude-auth/
data/users/*/claude-state/
data/mimir/data/
GITIGNORE
    git init
    git add .
    git commit -m "Initial Hermes multi-user deployment"
fi

# ── Done ────────────────────────────────────────────────────────────────────

echo ""
info "Deployment ready at $DEPLOY_DIR"
echo ""
echo "  Containers:"
for user_id in $USER_IDS; do
    echo "    $user_id: docker exec -it ${user_id}-hermes tmux attach -t hermes"
done
if [ "$MIMIR_ENABLED" = "true" ]; then
    echo "    mimir: http://localhost:$MIMIR_PORT"
fi
echo ""
echo "  Wrapper scripts generated for each user (bash + fish)."
echo "  Available at: $DEPLOY_DIR/data/users/<user-id>/"
echo ""
echo "  To stop:  cd $DEPLOY_DIR && docker compose down"
echo "  To start: cd $DEPLOY_DIR && docker compose up -d"
echo ""
