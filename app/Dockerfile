# syntax=docker/dockerfile:1

# ---- Stage 1: build a venv with all Python deps -----------------------------
# Keeps build tools (gcc, libpq-dev) out of the final image entirely.
FROM python:3.12-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ---- Stage 2: slim runtime image --------------------------------------------
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    DJANGO_SETTINGS_MODULE=conduit.settings \
    OTEL_SERVICE_NAME=conduit-api \
    OTEL_PYTHON_DJANGO_EXCLUDED_URLS=healthz

# libpq5 is the runtime Postgres client lib psycopg2 links against. The
# upgrade pulls Debian security fixes released after the base image was built,
# which the image scan in CD would otherwise flag.
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends libpq5 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 appuser

COPY --from=builder /opt/venv /opt/venv

WORKDIR /app
COPY . .

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Safe to run with no env vars: settings.py has dev-safe defaults for
# SECRET_KEY/DEBUG/DB, and collectstatic doesn't touch the database.
RUN python manage.py collectstatic --noinput

RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 8000

# Used by docker/docker-compose. ECS ignores it: there the ALB target group
# health check on the same endpoint decides whether a task is healthy.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/healthz', timeout=4)"]

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["gunicorn", "conduit.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3", "--error-logfile", "-"]
