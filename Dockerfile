# syntax=docker/dockerfile:1.29@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183
# postgen — Chainguard python, uv-managed venv, nonroot, no shell in the runtime.
# Renovate keeps builder (:latest-dev) and runtime (:latest) in lockstep so the
# venv's interpreter always matches the runtime Python.

# Base images come from chainringlabs/base-images: signature-verified copies of
# cgr.dev/chainguard/python, held back 3 days (`aged`). Both tags move together
# from the same daily record, so the builder's venv matches the runtime Python.
FROM ghcr.io/chainringlabs/base/python-dev:aged@sha256:768ee36ee9f4b8c882634c07d0b889425bc8e100886a3f742b83b1c647cc2d4b AS builder

USER root

COPY --from=ghcr.io/astral-sh/uv:0.13@sha256:a3ea1357342c1a4bf9a0c53a3deb1b55379aefa037338d8113d5771efa01774f /uv /uvx /usr/local/bin/

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

FROM ghcr.io/chainringlabs/base/python:aged@sha256:f522a16f34c8aa60f831e6476e396ef3951830a1b9059d19bc531a544d0f1579

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
