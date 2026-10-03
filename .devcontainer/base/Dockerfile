# Generic base image for the Claude Code sandbox: no project-specific content.
# Built on the host by initialize.sh as "ai-envelope-base:latest";
# the project layer's Dockerfile starts FROM it.
FROM node:lts-bookworm-slim

ENV SHELL=/usr/bin/zsh

# System packages: shell, editor and the CLI tools Claude Code relies on
RUN apt-get update && apt-get install -y --no-install-recommends \
        git zsh vim curl jq ripgrep fd-find ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd

# uv (Python package/project manager); projects pin Python and deps themselves
COPY --from=ghcr.io/astral-sh/uv:0.8.6 /uv /uvx /usr/local/bin/

# Install Claude Code globally
RUN npm install -g @anthropic-ai/claude-code@latest

# Replace the default 'node' user with 'claude' at UID/GID 1000
RUN userdel -f node 2>/dev/null || true \
    && groupdel node 2>/dev/null || true \
    && groupadd --gid 1000 claude \
    && useradd --uid 1000 --gid 1000 --shell /usr/bin/zsh \
               --create-home --home-dir /home/claude claude

# Set up Claude wrapper scripts (exclusion check runs before every 'claude' start)
COPY --chown=root:root check-exclusions.sh /usr/local/bin/check-exclusions
RUN chmod +x /usr/local/bin/check-exclusions \
    && mv $(which claude) /usr/local/bin/claude.real
COPY --chown=root:root claude-wrapper.sh /usr/local/bin/claude
RUN chmod +x /usr/local/bin/claude

# User-specific dotfiles
COPY --chown=claude:claude .zshrc /home/claude/.zshrc

# Switch to claude user and set up workspace
RUN mkdir -p /workspace && chown claude:claude /workspace
USER claude
ENV PATH="/home/claude/.local/bin:${PATH}"
WORKDIR /workspace

CMD ["zsh"]
