# Sockudo for Cloudron

<img src="logo.png" width="96" align="right" alt="">

A [Cloudron](https://www.cloudron.io/) community app package for [Sockudo](https://github.com/sockudo/sockudo). Sockudo is a fast, Pusher-compatible WebSocket server written in Rust.

The package updates itself. A daily GitHub Action watches Sockudo's releases, builds and tests a new image, and publishes it to `CloudronVersions.json`. Your Cloudron picks it up from there like any other app update.

This repository also contains a second app: **[Redis](redis/)**, a standalone Redis server reachable over TLS. Sockudo can use it instead of the built-in Cloudron Redis addon.

## Install

Requires Cloudron **9.1** or newer, which added community app support.

1. In the Cloudron dashboard, add this URL under **Community apps**:

   ```
   https://raw.githubusercontent.com/FX6W9WZK/cloudron-sockudo/main/CloudronVersions.json
   ```

2. Install **Sockudo** on a subdomain, for example `ws.example.com`.

You can also use the CLI:

```bash
cloudron install --versions-url https://raw.githubusercontent.com/FX6W9WZK/cloudron-sockudo/main/CloudronVersions.json --location ws
```

## Configuration

On first start, the package creates `/app/data/config.json` with one app and random `id`, `key` and `secret`. Use the File Manager or the Web Terminal to read the credentials and change settings. Restart the app afterwards.

| What | Where |
| --- | --- |
| Apps, limits, webhooks, allowed origins | `/app/data/config.json` → `app_manager.array.apps` ([docs](https://sockudo.io/docs)) |
| Extra environment variables | `/app/data/env.sh` ([reference](https://sockudo.io/docs/reference/environment-variables)) |
| Redis server | Cloudron Redis addon (default) or an external server, see [below](#redis-addon-or-external-server) |

Redis backs the cache and the webhook queue. The adapter is `local` because a Cloudron app runs as a single instance. Prometheus metrics listen on `127.0.0.1:9601` inside the container only.

Sockudo's native mobile push (FCM, APNs, Web Push) is off by default. Its store runs in memory, so the config sets `push.allow_memory_drivers: true`. Sockudo refuses to start in production mode without that flag. If you need durable native push, see the [push docs](https://sockudo.io/docs/server/push-notifications).

### Redis: addon or external server

By default Sockudo uses the Redis addon that Cloudron provides to every app. Nothing to configure.

To use another Redis server instead, for example the [Redis app](redis/) from this repository or a `redis-server` you run yourself, add one line to `/app/data/env.sh` and restart:

```bash
export SOCKUDO_REDIS_URL="rediss://default:PASSWORD@redis.example.com:6380/0"
```

* `rediss://` turns on TLS, `redis://` connects without it. Use plain `redis://` only inside a private network.
* `/0` is the database number. If several Sockudo installations share one Redis, give each one its own number.
* For a server with a self-signed certificate, also set `DATABASE_REDIS_MASTER_TLS_CA_PATH=/app/data/redis-ca.pem` and put the CA there.
* The app log shows which one is in use: `Using external Redis at …` or `Using the Cloudron Redis addon`.

A Redis running directly on the Cloudron host is not reachable on `127.0.0.1` from inside the app. It has to listen on an address the app container can reach, and it needs a password.

The addon stays provisioned when you switch to an external server, so you can switch back by removing the line.

### Client example (pusher-js / Laravel Echo)

```js
new Pusher(APP_KEY, {
  wsHost: 'ws.example.com',
  wsPort: 443,
  wssPort: 443,
  forceTLS: true,
  enabledTransports: ['ws', 'wss'],
  cluster: 'mt1', // required by pusher-js, ignored by Sockudo
});
```

Laravel `.env`:

```
BROADCAST_CONNECTION=pusher
PUSHER_APP_ID=<id>
PUSHER_APP_KEY=<key>
PUSHER_APP_SECRET=<secret>
PUSHER_HOST=ws.example.com
PUSHER_PORT=443
PUSHER_SCHEME=https
```

## How updates work

Both apps use the same mechanism.

```
sockudo/sockudo GitHub release        packages.redis.io APT repository
              │  check-upstream.yml (daily, 05:17 UTC)  │
              ▼                                          ▼
     bump Dockerfile + manifest + CHANGELOG ──► commit to main
              │  package.yml (once per app)
              ▼
docker build ─► smoke test ─► push to ghcr.io/fx6w9wzk/cloudron-{sockudo,redis}
              │
              ▼
append to the app's CloudronVersions.json ─► tag + GitHub release
              │
              ▼
Cloudron picks up the new version as an app update
```

* Sockudo: the binary is the official statically linked `x86_64-unknown-linux-musl` release asset. Its SHA256 is pinned in the `Dockerfile`, taken from GitHub's asset digest and cross-checked against the `.sha256` file in the release.
* Redis: installed with `apt` from the official Redis repository at an exact, pinned version. The repository's signing key is checked against a pinned fingerprint.
* The package version moves at the same level as the upstream release: an upstream major release bumps the package major version.
* The smoke test runs the image as Cloudron does: read-only root filesystem, Redis addon environment. It checks `/up`, the WebSocket handshake, a signed REST publish, and that the config survives a restart.
* A published version is never overwritten. To ship a packaging change, bump `version` in the app's `CloudronManifest.json`, set the same tag in `dockerImage`, and add a `CHANGELOG.md` entry.
* Pull requests build and test both apps without publishing. `integration.yml` also connects Sockudo to the Redis app over TLS.
* Release tags: `v<version>` for Sockudo, `redis-v<version>` for Redis.

## Development

```bash
docker build -t cloudron-sockudo:dev .
bash test/smoke.sh cloudron-sockudo:dev
docker build -t cloudron-redis:dev redis
bash redis/test/smoke.sh cloudron-redis:dev
bash test/integration.sh cloudron-sockudo:dev cloudron-redis:dev
```

CI also checks every `CloudronVersions.json` with `@cloudron/manifest-format`, the library a Cloudron server uses to accept or reject a community app, before it builds anything.

## License

The packaging is MIT-licensed, like Sockudo itself.
