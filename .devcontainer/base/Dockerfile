# Generic base image for the AI sandbox: no agent CLI, no project-specific content.
# Built on the host by initialize.sh as "ai-envelope-base:latest"; the enabled
# modules (modules/<name>/Dockerfile) are stacked on top of it, and the project
# layer's Dockerfile starts FROM the last module image.
FROM node:lts-bookworm-slim

ENV SHELL=/usr/bin/zsh

# System packages: shell, editor and the CLI tools the agents rely on
RUN apt-get update && apt-get install -y --no-install-recommends \
        git zsh vim curl jq ripgrep fd-find ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd

# uv (Python package/project manager); projects pin Python and deps themselves
COPY --from=ghcr.io/astral-sh/uv:0.8.6 /uv /uvx /usr/local/bin/

# Replace the default 'node' user with 'dev' at UID/GID 1000
RUN userdel -f node 2>/dev/null || true \
    && groupdel node 2>/dev/null || true \
    && groupadd --gid 1000 dev \
    && useradd --uid 1000 --gid 1000 --shell /usr/bin/zsh \
               --create-home --home-dir /home/dev dev

# Exclusion check + launcher used by every module's CLI wrapper
COPY --chown=root:root check-exclusions.sh /usr/local/bin/check-exclusions
COPY --chown=root:root run-guarded.sh /usr/local/bin/run-guarded
RUN chmod +x /usr/local/bin/check-exclusions /usr/local/bin/run-guarded

# User-specific dotfiles; history dir is a named volume (created with dev ownership)
COPY --chown=dev:dev .zshrc /home/dev/.zshrc
RUN install -d -o dev -g dev /home/dev/.local /home/dev/.local/state /home/dev/.local/state/zsh

# Switch to dev user and set up workspace
RUN mkdir -p /workspace && chown dev:dev /workspace
USER dev
ENV PATH="/home/dev/.local/bin:${PATH}"
WORKDIR /workspace

CMD ["zsh"]
