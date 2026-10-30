#!/bin/bash
# Runs the image the way Cloudron does (read-only rootfs, writable /app/data, /tmp, /run,
# Redis addon env) and checks health, WebSocket handshake, REST publish and restart.
#
# Usage: test/smoke.sh <image>

set -euo pipefail

# Files written by the container belong to its user; CI needs sudo to read them, Docker Desktop does not
as_root() {
    if [[ $(id -u) -ne 0 ]] && sudo -n true 2> /dev/null; then sudo "$@"; else "$@"; fi
}

IMAGE="$1"
NET=sockudo-smoke
DATA=$(mktemp -d)
REDIS_PASSWORD=smoke-test-password

cleanup() {
    docker logs sockudo-smoke-app > /tmp/sockudo-smoke.log 2>&1 || true
    docker rm -f sockudo-smoke-app sockudo-smoke-redis sockudo-smoke-redis-ext > /dev/null 2>&1 || true
    docker network rm "${NET}" > /dev/null 2>&1 || true
    as_root rm -rf "${DATA}"
}
trap cleanup EXIT

docker network create "${NET}" > /dev/null
docker run -d --name sockudo-smoke-redis --network "${NET}" redis:7-alpine \
    redis-server --requirepass "${REDIS_PASSWORD}" > /dev/null

start_app() {
    docker run -d --name sockudo-smoke-app --network "${NET}" -p 6001:6001 \
        --read-only --tmpfs /tmp --tmpfs /run \
        -v "${DATA}:/app/data" \
        -e CLOUDRON_REDIS_HOST=sockudo-smoke-redis \
        -e CLOUDRON_REDIS_PORT=6379 \
        -e CLOUDRON_REDIS_PASSWORD="${REDIS_PASSWORD}" \
        -e CLOUDRON_REDIS_URL="redis://default:${REDIS_PASSWORD}@sockudo-smoke-redis:6379" \
        "$@" "${IMAGE}" > /dev/null
}

wait_healthy() {
    for _ in $(seq 1 60); do
        if curl -fsS http://localhost:6001/up > /dev/null 2>&1; then
            echo "    /up is healthy"
            return 0
        fi
        sleep 1
    done
    echo "!!  /up did not become healthy"
    docker logs sockudo-smoke-app
    return 1
}

app_field() {
    as_root jq -r ".app_manager.array.apps[0].$1" "${DATA}/config.json"
}

echo "==> First start"
start_app
wait_healthy

APP_ID=$(app_field id)
APP_KEY=$(app_field key)
APP_SECRET=$(app_field secret)
[[ "${APP_KEY}" != "__APP_KEY__" && -n "${APP_SECRET}" ]] || { echo "!!  default app was not generated"; exit 1; }
echo "    default app ${APP_ID} generated"

echo "==> WebSocket handshake"
handshake=$(curl -s -i -N --max-time 3 \
    -H "Connection: Upgrade" -H "Upgrade: websocket" \
    -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: c29ja3Vkby1zbW9rZS10ZXN0" \
    "http://localhost:6001/app/${APP_KEY}?protocol=7&client=smoke&version=1.0" || true)
echo "${handshake}" | head -1 | grep -q " 101 " || { echo "!!  no 101 Switching Protocols"; echo "${handshake}"; exit 1; }
echo "${handshake}" | grep -q "pusher:connection_established" || { echo "!!  no pusher:connection_established"; echo "${handshake}"; exit 1; }
echo "    101 + pusher:connection_established"

echo "==> Signed REST publish"
body='{"name":"smoke","channels":["smoke-channel"],"data":"{\"ok\":true}"}'
body_md5=$(printf '%s' "${body}" | md5sum | cut -d' ' -f1)
query="auth_key=${APP_KEY}&auth_timestamp=$(date +%s)&auth_version=1.0&body_md5=${body_md5}"
path="/apps/${APP_ID}/events"
signature=$(printf 'POST\n%s\n%s' "${path}" "${query}" | openssl dgst -sha256 -hmac "${APP_SECRET}" | sed 's/^.*= //')
status=$(curl -s -o /tmp/publish.out -w '%{http_code}' -X POST -H "Content-Type: application/json" \
    --data "${body}" "http://localhost:6001${path}?${query}&auth_signature=${signature}")
[[ "${status}" == "200" ]] || { echo "!!  publish returned ${status}: $(cat /tmp/publish.out)"; exit 1; }
echo "    publish returned 200"

echo "==> Restart keeps config"
docker rm -f sockudo-smoke-app > /dev/null
start_app
wait_healthy
[[ "$(app_field key)" == "${APP_KEY}" ]] || { echo "!!  app key changed after restart"; exit 1; }
echo "    app key unchanged"

echo "==> External Redis via SOCKUDO_REDIS_URL"
# The addon variables point to a host that does not exist: /up (which checks the Redis cache)
# only becomes healthy if the external server is used.
docker rm -f sockudo-smoke-app > /dev/null
docker run -d --name sockudo-smoke-redis-ext --network "${NET}" redis:7-alpine \
    redis-server --requirepass external-password > /dev/null
start_app -e CLOUDRON_REDIS_HOST=addon-does-not-exist \
    -e CLOUDRON_REDIS_URL="redis://default:x@addon-does-not-exist:6379" \
    -e SOCKUDO_REDIS_URL="redis://default:external-password@sockudo-smoke-redis-ext:6379/3"
wait_healthy
# Read the log first: grep -q closing the pipe early would fail the pipeline under pipefail
log=$(docker logs sockudo-smoke-app 2>&1)
grep -q "Using external Redis at sockudo-smoke-redis-ext:6379 (db 3, tls false)" <<< "${log}" \
    || { echo "!!  external Redis not selected"; echo "${log}"; exit 1; }
echo "    external Redis selected and healthy"

echo "==> Memory usage"
docker stats --no-stream --format '    {{.MemUsage}}' sockudo-smoke-app

echo "==> All smoke tests passed"
