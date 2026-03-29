#!/bin/bash
set -e

# 1. Copy shared auth into user's writable ~/.claude/
#    -n = no clobber (don't overwrite existing user settings)
mkdir -p /home/user/.claude
if [ -d /opt/hermes/auth ] && [ "$(ls -A /opt/hermes/auth 2>/dev/null)" ]; then
    cp -n /opt/hermes/auth/* /home/user/.claude/ 2>/dev/null || true
fi

# 2. Copy shared global settings (if not already present)
if [ -f /opt/hermes/settings/settings.json ]; then
    cp -n /opt/hermes/settings/settings.json /home/user/.claude/settings.json 2>/dev/null || true
fi

# 3. Start tmux session and keep container alive
tmux new-session -d -s hermes -c /home/user/hermes
exec sleep infinity
