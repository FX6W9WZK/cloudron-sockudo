FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

LABEL org.opencontainers.image.source=https://github.com/FX6W9WZK/cloudron-sockudo

# Managed by .github/workflows/check-upstream.yml - do not rename these ARGs.
ARG REDIS_VERSION=8.10.3
ARG REDIS_APT_VERSION=6:8.10.3-1rl1~noble1

# Signing key of the official Redis APT repository (packages.redis.io)
ARG REDIS_KEY_FINGERPRINT=54318FA4052D1E61A6B6F7BB5F4349D6BF53AA0C

# cloudron/base already ships this repository (for redis-tools); its key and source entry are
# replaced so the installed version and the key fingerprint are under this package's control.
RUN curl -fsSL https://packages.redis.io/gpg -o /tmp/redis.asc && \
    gpg --show-keys --with-colons /tmp/redis.asc | grep -q "^fpr:::::::::${REDIS_KEY_FINGERPRINT}:$" && \
    gpg --batch --yes --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg /tmp/redis.asc && \
    rm /tmp/redis.asc && \
    (grep -rl packages.redis.io /etc/apt/sources.list.d/ | xargs -r rm -f) && \
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(. /etc/os-release && echo "${VERSION_CODENAME}") main" \
        > /etc/apt/sources.list.d/redis.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends --allow-downgrades \
        "redis-server=${REDIS_APT_VERSION}" "redis-tools=${REDIS_APT_VERSION}" && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* && \
    redis-server --version | grep -q "v=${REDIS_VERSION} "

RUN mkdir -p /app/pkg
COPY redis.conf.template redis.conf.user status.py start.sh /app/pkg/
RUN chmod +x /app/pkg/start.sh

CMD [ "/app/pkg/start.sh" ]
