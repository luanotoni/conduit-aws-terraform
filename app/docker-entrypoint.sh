#!/bin/sh
set -e

if [ -n "$POSTGRES_HOST" ]; then
  echo "Waiting for Postgres at ${POSTGRES_HOST}:${POSTGRES_PORT:-5432}..."
  until python -c "
import os, socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(2)
try:
    s.connect((os.environ['POSTGRES_HOST'], int(os.environ.get('POSTGRES_PORT', 5432))))
except OSError:
    sys.exit(1)
"
  do
    sleep 1
  done
  echo "Postgres is up."
fi

# In production (ECS) migrations are run as a one-off task from the CD
# pipeline, deliberately NOT here — if this ran on every container start,
# an autoscaling event that launches 3 tasks at once would race 3 concurrent
# `migrate` runs against the same database. RUN_MIGRATIONS_ON_START is only
# set to "true" in docker-compose, where there's just one instance.
if [ "$RUN_MIGRATIONS_ON_START" = "true" ]; then
  echo "Running migrations..."
  python manage.py migrate --noinput
fi

exec "$@"
