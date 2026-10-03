# Module: GitHub Copilot CLI. Stacked on the previous image of the module chain
# (BASE_IMAGE is passed by initialize.sh). Build context: this folder.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

USER root
RUN npm install -g @github/copilot@latest \
    && mv "$(command -v copilot)" /usr/local/bin/copilot.real
# Wrapper: loads the token, exclusion check before every 'copilot' start
COPY --chown=root:root copilot-wrapper.sh /usr/local/bin/copilot
RUN chmod +x /usr/local/bin/copilot
USER dev
