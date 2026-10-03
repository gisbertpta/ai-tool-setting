# Module: Claude Code. Stacked on the previous image of the module chain
# (BASE_IMAGE is passed by initialize.sh). Build context: this folder.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

USER root
RUN npm install -g @anthropic-ai/claude-code@latest \
    && mv "$(command -v claude)" /usr/local/bin/claude.real

# Wrapper: exclusion check, then Claude in bypass-permissions mode
COPY --chown=root:root claude-wrapper.sh /usr/local/bin/claude

# Managed settings: highest precedence, apply in every directory (also nested
# repos), and root-owned, so the agent can't change them
COPY --chown=root:root managed-settings.json /etc/claude-code/managed-settings.json
COPY --chown=root:root notify-ntfy.sh /usr/local/libexec/ai-envelope/notify-ntfy.sh
RUN chmod 755 /usr/local/bin/claude /usr/local/libexec/ai-envelope/notify-ntfy.sh \
    && chmod 644 /etc/claude-code/managed-settings.json

# Updates come with an image rebuild (NO_CACHE=1 initialize.sh), not at runtime
ENV DISABLE_AUTOUPDATER=1

USER dev
