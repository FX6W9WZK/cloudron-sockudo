#!/bin/bash
# Runs the Redis image the way Cloudron does (read-only rootfs, tls addon certs in /etc/certs,
# REDIS_TLS_PORT from tcpPorts) and checks TLS, auth, persistence and the disabled-port mode.
#
# Usage: redis/test/smoke.sh <image>

set -euo pipefail

# Files written by the container belong to its user; CI needs sudo to read them, Docker Desktop does not
as_root() {
    if [[ $(id -u) -ne 0 ]] && sudo -n true 2> /dev/null; then sudo "$@"; else "$@"; fi
}

IMAGE="$1"
NET=redis-smoke
DOMAIN=redis.test
WORK=$(mktemp -d)
DATA="${WORK}/data"
CERTS="${WORK}/certs"
mkdir -p "${DATA}" "${CERTS}"

cleanup() {
    docker logs redis-smoke-app > /tmp/redis-smoke.log 2>&1 || true
    docker rm -f redis-smoke-app > /dev/null 2>&1 || true
    docker network rm "${NET}" > /dev/null 2>&1 || true
    as_root rm -rf "${WORK}"
}
trap cleanup EXIT

# Self-signed CA + server certificate for the test domain (Cloudron provides a real one)
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=smoke-ca" \
    -keyout "${CERTS}/ca_key.pem" -out "${CERTS}/ca.pem" 2> /dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=${DOMAIN}" \
    -keyout "${CERTS}/tls_key.pem" -out "${CERTS}/server.csr" 2> /dev/null
openssl x509 -req -in "${CERTS}/server.csr" -CA "${CERTS}/ca.pem" -CAkey "${CERTS}/ca_key.pem" \
    -CAcreateserial -days 1 -extfile <(printf "subjectAltName=DNS:%s" "${DOMAIN}") \
    -out "${CERTS}/tls_cert.pem" 2> /dev/null

docker network create "${NET}" > /dev/null

start_app() {
    docker run -d --name redis-smoke-app --network "${NET}" --network-alias "${DOMAIN}" -p 8000:8000 \
        --read-only --tmpfs /tmp --tmpfs /run \
        -v "${DATA}:/app/data" -v "${CERTS}:/etc/certs:ro" \
        -e CLOUDRON_APP_DOMAIN="${DOMAIN}" "$@" \
        "${IMAGE}" > /dev/null
}

wait_healthy() {
    for _ in $(seq 1 60); do
        if curl -fsS http://localhost:8000/healthz > /dev/null 2>&1; then
            echo "    /healthz is healthy"
            return 0
        fi
        sleep 1
    done
    echo "!!  /healthz did not become healthy"
    docker logs redis-smoke-app
    return 1
}

# redis-cli from the image under test, as a separate client container on the same network
cli() {
    docker run --rm --network "${NET}" -v "${CERTS}:/certs:ro" --entrypoint redis-cli "${IMAGE}" \
        -h "${DOMAIN}" -p 6380 "$@" 2>&1
}

echo "==> First start with TLS port"
start_app -e REDIS_TLS_PORT=6380
wait_healthy
PASSWORD=$(as_root sed -n 's/^REDIS_PASSWORD=//p' "${DATA}/credentials.env")
[[ ${#PASSWORD} -eq 64 ]] || { echo "!!  password was not generated"; exit 1; }
echo "    password generated"

echo "==> TLS + auth"
[[ "$(cli --tls --cacert /certs/ca.pem --no-auth-warning -a "${PASSWORD}" PING)" == "PONG" ]] || { echo "!!  TLS PING failed"; exit 1; }
echo "    PING over TLS with password: PONG"
cli --tls --cacert /certs/ca.pem PING | grep -q NOAUTH || { echo "!!  unauthenticated command was not rejected"; exit 1; }
echo "    without password: NOAUTH"
if cli PING | grep -q PONG; then echo "!!  plaintext connection accepted"; exit 1; fi
echo "    plaintext connection refused"
cli --tls --cacert /certs/ca.pem --no-auth-warning -a "${PASSWORD}" SET smoke:key persisted > /dev/null

echo "==> Status page"
page=$(curl -fsS http://localhost:8000/)
echo "${page}" | grep -q "Redis is running" || { echo "!!  status page broken"; echo "${page}"; exit 1; }
if echo "${page}" | grep -q "${PASSWORD}"; then echo "!!  status page leaks the password"; exit 1; fi
echo "    running, no password on page"

echo "==> Restart keeps data and password"
docker rm -f redis-smoke-app > /dev/null
start_app -e REDIS_TLS_PORT=6380
wait_healthy
[[ "$(cli --tls --cacert /certs/ca.pem --no-auth-warning -a "${PASSWORD}" GET smoke:key)" == "persisted" ]] || { echo "!!  data lost after restart"; exit 1; }
echo "    key survived restart"

echo "==> TCP port disabled"
docker rm -f redis-smoke-app > /dev/null
start_app
wait_healthy
if cli --tls --cacert /certs/ca.pem --no-auth-warning -a "${PASSWORD}" PING | grep -q PONG; then echo "!!  TLS port open although disabled"; exit 1; fi
echo "    no network listener, health check still works"

echo "==> Memory usage"
docker stats --no-stream --format '    {{.MemUsage}}' redis-smoke-app

echo "==> All smoke tests passed"
