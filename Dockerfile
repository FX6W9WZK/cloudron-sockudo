FROM cloudron/base:5.0.0@sha256:04fd70dbd8ad6149c19de39e35718e024417c3e01dc9c6637eaf4a41ec4e596c

# Managed by .github/workflows/check-upstream.yml - do not rename these ARGs.
ARG SOCKUDO_VERSION=5.2.0
ARG SOCKUDO_SHA256=9fac16a8e0fe2c77a16a9451efbd82d519de3c3a80683ae53214ea3d23782a90

RUN mkdir -p /app/code /app/pkg
WORKDIR /app/code

# Statically linked (musl) release binary published by the Sockudo project.
RUN curl -fsSL -o /tmp/sockudo.tgz \
        "https://github.com/sockudo/sockudo/releases/download/v${SOCKUDO_VERSION}/sockudo-v${SOCKUDO_VERSION}-x86_64-unknown-linux-musl.tgz" && \
    echo "${SOCKUDO_SHA256}  /tmp/sockudo.tgz" | sha256sum -c - && \
    tar -xzf /tmp/sockudo.tgz -C /app/code sockudo && \
    rm /tmp/sockudo.tgz && \
    chmod 0755 /app/code/sockudo && \
    /app/code/sockudo --version

COPY config.json.template env.sh.template redis-env.py start.sh /app/pkg/
RUN chmod +x /app/pkg/start.sh

CMD [ "/app/pkg/start.sh" ]
