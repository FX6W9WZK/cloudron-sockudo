#!/bin/bash

set -eu

CONFIG_FILE=/app/data/config.json

mkdir -p /app/data

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "==> First run: generating ${CONFIG_FILE} with a default app"
    app_id=$(shuf -i 100000-999999 -n 1)
    app_key=$(openssl rand -hex 10)
    app_secret=$(openssl rand -hex 32)
    sed -e "s/__APP_ID__/${app_id}/" \
        -e "s/__APP_KEY__/${app_key}/" \
        -e "s/__APP_SECRET__/${app_secret}/" \
        /app/pkg/config.json.template > "${CONFIG_FILE}"
    chmod 0600 "${CONFIG_FILE}"
    echo "==> Default app created: id=${app_id} key=${app_key} (secret is in ${CONFIG_FILE})"
fi

[[ ! -f /app/data/env.sh ]] && cp /app/pkg/env.sh.template /app/data/env.sh

# Listener: Cloudron's reverse proxy terminates TLS and forwards HTTP + WebSocket traffic to httpPort
export HOST=0.0.0.0
export PORT=6001

# Exactly one trusted proxy (Cloudron's nginx) appends to X-Forwarded-For
export RATE_LIMITER_API_TRUST_HOPS=1
export RATE_LIMITER_WS_TRUST_HOPS=1

export LOG_COLORS_ENABLED=false

# User overrides (see https://sockudo.io/docs/reference/environment-variables)
source /app/data/env.sh

# Redis (used when a driver in config.json is set to "redis"). Either the Cloudron addon (default)
# or an external server set via SOCKUDO_REDIS_URL in env.sh. Credentials are injected on every
# start instead of being written into config.json, because the addon's can change.
if [[ -n "${SOCKUDO_REDIS_URL:-}" ]]; then
    redis_env=$(python3 /app/pkg/redis-env.py "${SOCKUDO_REDIS_URL}")
    eval "${redis_env}"
    echo "==> Using external Redis at ${DATABASE_REDIS_HOST}:${DATABASE_REDIS_PORT} (db ${DATABASE_REDIS_DB}, tls ${DATABASE_REDIS_MASTER_TLS_ENABLED})"
else
    export DATABASE_REDIS_HOST="${CLOUDRON_REDIS_HOST}"
    export DATABASE_REDIS_PORT="${CLOUDRON_REDIS_PORT}"
    export DATABASE_REDIS_PASSWORD="${CLOUDRON_REDIS_PASSWORD}"
    export REDIS_URL="${CLOUDRON_REDIS_URL}"
    echo "==> Using the Cloudron Redis addon"
fi

chown -R cloudron:cloudron /app/data

echo "==> Starting Sockudo $(/app/code/sockudo --version 2>/dev/null || true)"
cd /app/data
exec gosu cloudron:cloudron /app/code/sockudo --config "${CONFIG_FILE}"
