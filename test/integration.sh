#!/bin/bash
# Sockudo app -> Redis app over TLS, configured the way a user would: SOCKUDO_REDIS_URL in
# Sockudo's /app/data/env.sh, password from the Redis app's credentials.env.
#
# Usage: test/integration.sh <sockudo-image> <redis-image>

set -euo pipefail

# Files written by the container belong to its user; CI needs sudo to read them, Docker Desktop does not
as_root() {
    if [[ $(id -u) -ne 0 ]] && sudo -n true 2> /dev/null; then sudo "$@"; else "$@"; fi
}

SOCKUDO_IMAGE="$1"
REDIS_IMAGE="$2"
NET=integration
DOMAIN=redis.test
WORK=$(mktemp -d)
mkdir -p "${WORK}/certs" "${WORK}/redis-data" "${WORK}/sockudo-data"

cleanup() {
    for name in it-sockudo it-redis; do
        docker logs "${name}" > "/tmp/${name}.log" 2>&1 || true
    done
    docker rm -f it-sockudo it-redis > /dev/null 2>&1 || true
    docker network rm "${NET}" > /dev/null 2>&1 || true
    as_root rm -rf "${WORK}"
}
trap cleanup EXIT

CERTS="${WORK}/certs"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=integration-ca" \
    -keyout "${CERTS}/ca_key.pem" -out "${CERTS}/ca.pem" 2> /dev/null
openssl req -newkey rsa:2048 -nodes -subj "/CN=${DOMAIN}" \
    -keyout "${CERTS}/tls_key.pem" -out "${CERTS}/server.csr" 2> /dev/null
openssl x509 -req -in "${CERTS}/server.csr" -CA "${CERTS}/ca.pem" -CAkey "${CERTS}/ca_key.pem" \
    -CAcreateserial -days 1 -extfile <(printf "subjectAltName=DNS:%s" "${DOMAIN}") \
    -out "${CERTS}/tls_cert.pem" 2> /dev/null

docker network create "${NET}" > /dev/null

wait_for() {
    for _ in $(seq 1 60); do
        curl -fsS "$1" > /dev/null 2>&1 && return 0
        sleep 1
    done
    echo "!!  $1 did not become healthy"
    return 1
}

echo "==> Redis app"
docker run -d --name it-redis --network "${NET}" --network-alias "${DOMAIN}" -p 8000:8000 \
    --read-only --tmpfs /tmp --tmpfs /run \
    -v "${WORK}/redis-data:/app/data" -v "${CERTS}:/etc/certs:ro" \
    -e CLOUDRON_APP_DOMAIN="${DOMAIN}" -e REDIS_TLS_PORT=6380 \
    "${REDIS_IMAGE}" > /dev/null
wait_for http://localhost:8000/healthz
PASSWORD=$(as_root sed -n 's/^REDIS_PASSWORD=//p' "${WORK}/redis-data/credentials.env")
echo "    healthy"

echo "==> Sockudo app with SOCKUDO_REDIS_URL in env.sh"
cp "${CERTS}/ca.pem" "${WORK}/sockudo-data/redis-ca.pem"
cat > "${WORK}/sockudo-data/env.sh" <<EOF
export SOCKUDO_REDIS_URL="rediss://default:${PASSWORD}@${DOMAIN}:6380/0"
export DATABASE_REDIS_MASTER_TLS_CA_PATH=/app/data/redis-ca.pem
EOF
# The addon variables point nowhere: Sockudo can only become healthy through the Redis app
docker run -d --name it-sockudo --network "${NET}" -p 6001:6001 \
    --read-only --tmpfs /tmp --tmpfs /run \
    -v "${WORK}/sockudo-data:/app/data" \
    -e CLOUDRON_REDIS_HOST=addon-does-not-exist -e CLOUDRON_REDIS_PORT=6379 \
    -e CLOUDRON_REDIS_PASSWORD=x -e CLOUDRON_REDIS_URL="redis://default:x@addon-does-not-exist:6379" \
    "${SOCKUDO_IMAGE}" > /dev/null
wait_for http://localhost:6001/up || { docker logs it-sockudo; exit 1; }
log=$(docker logs it-sockudo 2>&1)
grep -q "Using external Redis at ${DOMAIN}:6380 (db 0, tls true)" <<< "${log}" \
    || { echo "!!  external Redis not selected"; echo "${log}"; exit 1; }
echo "    healthy over rediss://"

echo "==> Sockudo writes into the Redis app"
keys=$(docker run --rm --network "${NET}" -v "${CERTS}:/certs:ro" --entrypoint redis-cli "${REDIS_IMAGE}" \
    -h "${DOMAIN}" -p 6380 --tls --cacert /certs/ca.pem --no-auth-warning -a "${PASSWORD}" DBSIZE)
echo "    keys in db 0: ${keys}"

echo "==> Integration test passed"
