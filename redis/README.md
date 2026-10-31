# Redis for Cloudron

<img src="logo.png" width="96" align="right" alt="">

A [Cloudron](https://www.cloudron.io/) community app package for [Redis](https://redis.io/), installed from the official Redis APT repository (`packages.redis.io`). It updates itself the same way as the [Sockudo app](../) in this repository.

## Install

Requires Cloudron **9.1** or newer. Open the **Add custom app** menu in the Cloudron dashboard, choose the community app option and paste this URL into the **Install Community App** dialog:

```
https://raw.githubusercontent.com/FX6W9WZK/cloudron-sockudo/main/redis/CloudronVersions.json
```

Or with the CLI:

```bash
cloudron install --versions-url https://raw.githubusercontent.com/FX6W9WZK/cloudron-sockudo/main/redis/CloudronVersions.json --location redis
```

During installation, Cloudron asks for the **Redis (TLS)** TCP port (default `6380`). It must not be in use on the server.

To use it with Sockudo, follow the [step-by-step guide](../#sockudo-with-the-redis-app) in the main README.

## Security

Cloudron apps talk to each other over the server's public address, not a private network. Cloudron opens the Redis port in its firewall, so **it is reachable from the internet**. The package therefore:

* accepts **TLS only**, with the Let's Encrypt certificate of the app domain from Cloudron's `tls` addon. Cloudron restarts the app when the certificate is renewed.
* requires a **random 64-character password**, generated on first start
* keeps the plain-text port disabled

The web page of the app (`https://redis.example.com`) is a public status page without credentials. Cloudron uses it as its health check.

## Connect

The password is in `/app/data/credentials.env` (File Manager or Web Terminal).

```
rediss://default:<password>@redis.example.com:6380
```

```bash
redis-cli --tls -h redis.example.com -p 6380 --user default --pass '<password>' PING
```

For [Sockudo](../#redis-addon-or-external-server), add this to Sockudo's `/app/data/env.sh` and restart Sockudo:

```bash
export SOCKUDO_REDIS_URL="rediss://default:<password>@redis.example.com:6380/0"
```

## Configuration

| What | Where |
| --- | --- |
| Your own settings (eviction policy, databases, …) | `/app/data/redis.conf`, included after the generated base config |
| Password | `/app/data/credentials.env`. Change it, then restart the app and update all clients. |
| Data (AOF + RDB) | `/app/data/redis`, part of Cloudron backups |
| Memory | `maxmemory` is 75% of the app's memory limit (default 512 MB), policy `noeviction` |

If you disable the TCP port in the app settings, Redis listens only on a local socket inside the container. That is only useful for maintenance.

## Tests

`test/smoke.sh` runs the image like Cloudron does: read-only root filesystem, certificates in `/etc/certs`, `REDIS_TLS_PORT` set. It checks:

* TLS with password works
* connections without the password and plain-text connections are rejected
* the status page shows no password
* data survives a restart
* the disabled-port mode still passes the health check

## License

The packaging is MIT-licensed. Redis itself is licensed under your choice of AGPLv3, RSALv2 or SSPLv1 (since Redis 8).
