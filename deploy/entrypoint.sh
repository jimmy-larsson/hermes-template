#!/bin/bash
set -e

# 1. Copy shared auth into user's writable ~/.claude/
#    The host's credentials file is mounted read-only at /opt/hermes/auth/.credentials.json.
#    Copy it into the writable ~/.claude/ so Claude Code can use it.
#    -n = no clobber (don't overwrite if user already logged in locally)
mkdir -p /home/user/.claude
if [ -f /opt/hermes/auth/.credentials.json ] && [ -s /opt/hermes/auth/.credentials.json ]; then
    cp -n /opt/hermes/auth/.credentials.json /home/user/.claude/.credentials.json 2>/dev/null || true
fi

# 2. Copy shared global settings (if not already present)
if [ -f /opt/hermes/settings/settings.json ]; then
    cp -n /opt/hermes/settings/settings.json /home/user/.claude/settings.json 2>/dev/null || true
fi

# 3. Start tmux session and keep container alive
tmux new-session -d -s hermes -c /home/user/hermes
exec sleep infinity
