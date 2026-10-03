# Project layer image for ki-zfw-wm: generic base + project toolchain and deps.
# Build context: workspace root (see Dockerfile.dockerignore for what is sent).
ARG BASE_IMAGE=ai-envelope-base:latest
FROM ${BASE_IMAGE}

USER root

# Build tools/libs for the Python deps (Netezza ODBC, PDF/text rendering)
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3-dev g++ unixodbc-dev \
        libglib2.0-0 libpango-1.0-0 libpangocairo-1.0-0 libpangoft2-1.0-0 libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

# Company CA (Artifactory / internal hosts)
COPY ki-zfw-wm-code/bitmarck-ca-chain.crt /usr/local/share/ca-certificates/bitmarck-ca-chain.crt
RUN update-ca-certificates

USER dev
ENV PATH="/home/dev/.venv/bin:${PATH}"
ENV VIRTUAL_ENV="/home/dev/.venv"
ENV UV_PROJECT_ENVIRONMENT="/home/dev/.venv"

# Copy dependency files and install Python dependencies (uv comes from the base image)
# Secrets are mounted and used only within this single layer, then cleaned up
COPY --chown=dev:dev ki-zfw-wm-code/pyproject.toml ki-zfw-wm-code/uv.lock ki-zfw-wm-code/README.md ki-zfw-wm-code/.pre-commit-config.yaml ./
RUN --mount=type=secret,id=git-username,uid=1000 \
    --mount=type=secret,id=git-password,uid=1000 \
    git config --global credential.helper '!f() { echo "username=$(cat /run/secrets/git-username)"; echo "password=$(cat /run/secrets/git-password)"; }; f' && \
    echo "---> Installing dependencies ..." && \
    uv python install 3.11 && \
    uv venv /home/dev/.venv --python-preference managed --python 3.11 && \
    uv sync --locked --python-preference managed --python 3.11 --group main --group dev \
      --trusted-host artifactory.dakentw007200.de \
      --trusted-host pypi.org \
      --trusted-host files.pythonhosted.org && \
    git config --global --unset credential.helper

# Cache the tiktoken encoding file
ENV TIKTOKEN_CACHE_DIR="/home/dev/.tiktoken_cache/"
RUN echo "---> Loading tiktoken encoding ..." && \
    /home/dev/.venv/bin/python -c "import tiktoken; tiktoken.get_encoding('cl100k_base')"

# Verify daktools is installed correctly
RUN /home/dev/.venv/bin/python -c "import sys; print(f'Python path: {sys.path}'); import daktools; print(f'daktools found at {daktools.__file__}')"

# Pre-install pre-commit hooks so they work offline
RUN --mount=type=secret,id=git-username,uid=1000 \
    --mount=type=secret,id=git-password,uid=1000 \
    git config --global credential.helper '!f() { echo "username=$(cat /run/secrets/git-username)"; echo "password=$(cat /run/secrets/git-password)"; }; f' && \
    git init /tmp/pre-commit-init && \
    cp .pre-commit-config.yaml /tmp/pre-commit-init/ && \
    cd /tmp/pre-commit-init && \
    pre-commit install-hooks && \
    cd / && \
    rm -rf /tmp/pre-commit-init && \
    git config --global --unset credential.helper
