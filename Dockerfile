# syntax=docker/dockerfile:1.29@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# postgen — Chainguard python, uv-managed venv, nonroot, no shell in the runtime.
# Renovate keeps builder (:latest-dev) and runtime (:latest) in lockstep so the
# venv's interpreter always matches the runtime Python.

FROM cgr.dev/chainguard/python:latest-dev@sha256:c047e6d1e47b09144a771bfde6595a00c49dc8571caa7dd62df88634e84304ae AS builder

USER root

COPY --from=ghcr.io/astral-sh/uv:0.13@sha256:d3b601f0c7b118bc1753febf7c41cc80981df678445e0254284eecf84db79a7d /uv /uvx /usr/local/bin/

WORKDIR /app

ENV UV_PROJECT_ENVIRONMENT=/app/.venv \
    UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_DOWNLOADS=never

# Dependencies first (cached layer), then the project itself.
COPY pyproject.toml uv.lock README.md ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project --no-editable

COPY src ./src

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-editable

# /data is the named volume (profile, corpus, SQLite, voice profile). It must exist
# in the image owned by nonroot or the mount inherits root; the runtime has no mkdir.
RUN mkdir -p /data && chown -R nonroot:nonroot /app /data

FROM cgr.dev/chainguard/python:latest@sha256:f6e5c2e056393d48fa8afa1ea58a1394db4cd5de1a8f0f48105c8e88fcd4f9d3

WORKDIR /app

COPY --from=builder --chown=nonroot:nonroot /app/.venv /app/.venv
COPY --from=builder --chown=nonroot:nonroot /data /data

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    POSTGEN_DATA_DIR=/data \
    POSTGEN_HOST=0.0.0.0

VOLUME ["/data"]
EXPOSE 8790

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import os,urllib.request; p=os.environ.get('POSTGEN_PORT','8790'); urllib.request.urlopen(f'http://127.0.0.1:{p}/healthz', timeout=4)"]

# Clear the upstream ENTRYPOINT (/usr/bin/python) so PATH-resolved "python" is the venv's.
ENTRYPOINT []
CMD ["python", "-m", "postgen"]
