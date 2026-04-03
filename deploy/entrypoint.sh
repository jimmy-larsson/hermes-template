#!/bin/bash
set -e

# Runs as root to set up the user, then drops privileges via gosu.
# USER_NAME is set per-container in docker-compose.yml.
HERMES_USER="hermes_${USER_NAME}"
HOME_DIR="/home/${HERMES_USER}"

# 1. Create user (idempotent)
if ! id "$HERMES_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$HERMES_USER"
    echo "$HERMES_USER ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi

# 2. Ensure home directory structure
mkdir -p "$HOME_DIR/.claude" "$HOME_DIR/hermes"

# 3. Copy shared auth credentials (if mounted)
#    -n = no clobber (don't overwrite if user already logged in locally)
if [ -f /opt/hermes/auth/.credentials.json ] && [ -s /opt/hermes/auth/.credentials.json ]; then
    cp -n /opt/hermes/auth/.credentials.json "$HOME_DIR/.claude/.credentials.json" 2>/dev/null || true
fi

# 4. Copy shared global settings (if mounted)
if [ -f /opt/hermes/settings/settings.json ]; then
    cp -n /opt/hermes/settings/settings.json "$HOME_DIR/.claude/settings.json" 2>/dev/null || true
fi

# 5. Fix ownership
chown -R "$HERMES_USER:$HERMES_USER" "$HOME_DIR"

# 6. Keep container alive — tmux session is created on first connect
#    by the hermes() wrapper in /etc/profile.d/hermes.sh
exec gosu "$HERMES_USER" sleep infinity
