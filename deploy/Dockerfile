FROM debian:bookworm-slim

# Switch apt to HTTPS — some hosts block outbound port 80
# bookworm-slim lacks ca-certificates, so bootstrap with verification disabled
RUN sed -i 's|http://|https://|g' /etc/apt/sources.list.d/debian.sources \
    && apt-get -o Acquire::https::Verify-Peer=false update \
    && apt-get -o Acquire::https::Verify-Peer=false install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash curl git tmux python3 python3-pip sudo gosu \
    && rm -rf /var/lib/apt/lists/*

# Node.js (Claude Code dependency)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code
RUN npm install -g @anthropic-ai/claude-code

# hermes session wrapper
COPY hermes.sh /etc/profile.d/hermes.sh

# Ark rules mount point (Phase 3) — user home created at runtime by entrypoint
RUN mkdir -p /opt/hermes/rules

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
