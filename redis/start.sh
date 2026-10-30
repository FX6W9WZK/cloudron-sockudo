#!/bin/bash

set -eu

mkdir -p /app/data/redis /run/redis

if [[ ! -f /app/data/credentials.env ]]; then
    echo "==> First run: generating password in /app/data/credentials.env"
    echo "REDIS_PASSWORD=$(openssl rand -hex 32)" > /app/data/credentials.env
    chmod 0600 /app/data/credentials.env
fi
source /app/data/credentials.env

[[ ! -f /app/data/redis.conf ]] && cp /app/pkg/redis.conf.user /app/data/redis.conf

# REDIS_TLS_PORT is set by Cloudron when the TCP port is enabled. Without it, Redis is only
# reachable through the local socket (used by the health check).
if [[ -n "${REDIS_TLS_PORT:-}" ]]; then
    # /etc/certs is mounted read-only and not readable by the redis user
    cp /etc/certs/tls_cert.pem /etc/certs/tls_key.pem /run/redis/
    chmod 0600 /run/redis/tls_key.pem
    tls_settings="tls-port 6380
tls-cert-file /run/redis/tls_cert.pem
tls-key-file /run/redis/tls_key.pem
tls-ca-cert-dir /etc/ssl/certs
tls-auth-clients no
tls-protocols \"TLSv1.2 TLSv1.3\""
    echo "==> TLS port enabled (public port ${REDIS_TLS_PORT})"
else
    tls_settings="# TLS port disabled in the Cloudron app settings"
    echo "==> TCP port disabled, Redis is only reachable inside the container"
fi

# 75% of the container memory limit, leaving room for copy-on-write during persistence
memory_limit=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
[[ "${memory_limit}" == "max" ]] && memory_limit=$((512 * 1024 * 1024))
maxmemory=$((memory_limit * 3 / 4))

python3 - "${tls_settings}" "${REDIS_PASSWORD}" "${maxmemory}" > /run/redis/redis.conf <<'EOF'
import sys
template = open("/app/pkg/redis.conf.template").read()
print(template.replace("__TLS_SETTINGS__", sys.argv[1])
              .replace("__PASSWORD__", sys.argv[2])
              .replace("__MAXMEMORY__", sys.argv[3]), end="")
EOF
chmod 0600 /run/redis/redis.conf

chown -R cloudron:cloudron /app/data /run/redis

echo "==> Starting $(redis-server --version)"
gosu cloudron:cloudron redis-server /run/redis/redis.conf &
redis_pid=$!

REDIS_PASSWORD="${REDIS_PASSWORD}" gosu cloudron:cloudron python3 /app/pkg/status.py &
status_pid=$!

# If either process exits, stop the other and let Cloudron restart the container
trap 'kill -TERM ${redis_pid} ${status_pid} 2>/dev/null; wait; exit 0' TERM INT
wait -n
echo "==> A process exited, shutting down"
kill -TERM ${redis_pid} ${status_pid} 2>/dev/null || true
wait
exit 1
