FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl git tmux ca-certificates python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Node.js (Claude Code dependency)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code
RUN npm install -g @anthropic-ai/claude-code

# hermes session wrapper
COPY hermes.sh /etc/profile.d/hermes.sh

# Ark-ready mount point (Phase 3)
RUN mkdir -p /opt/hermes/rules

# User workspace and config mount points
RUN mkdir -p /home/user/hermes /home/user/.claude

WORKDIR /home/user/hermes

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
