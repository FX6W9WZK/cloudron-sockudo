# Sockudo for Cloudron

<img src="logo.png" width="96" align="right" alt="">

A [Cloudron](https://www.cloudron.io/) community app package for [Sockudo](https://github.com/sockudo/sockudo). Sockudo is a fast, Pusher-compatible WebSocket server written in Rust.

The package updates itself. A daily GitHub Action watches Sockudo's releases, builds and tests a new image, and publishes it to `CloudronVersions.json`. Your Cloudron picks it up from there like any other app update.

This repository also contains a second app: **[Redis](redis/)**, a standalone Redis server reachable over TLS. Sockudo can use it instead of the built-in Cloudron Redis addon.

## Install

Requires Cloudron **9.1** or newer. Cloudron does not review community apps, so only install packages you trust.

| App | `CloudronVersions.json` URL |
| --- | --- |
| Sockudo | `https://raw.githubusercontent.com/FX6W9WZK/cloudron-sockudo/main/CloudronVersions.json` |
| Redis (optional) | `https://raw.githubusercontent.com/FX6W9WZK/cloudron-sockudo/main/redis/CloudronVersions.json` |

To add an app, open the **Add custom app** menu in the Cloudron dashboard, choose the community app option and paste the URL into the **Install Community App** dialog. Updates then arrive like any other app update. To stay on a version, turn off automatic updates in the app's settings.

### Sockudo with the built-in Redis

1. Install **Sockudo** on a subdomain, for example `ws.example.com`.
2. The app log shows `Default app created: id=… key=…`. The secret is in `/app/data/config.json` (File Manager or Web Terminal).
3. Point your clients at `ws.example.com`, see the [client example](#client-example-pusher-js--laravel-echo).

Sockudo uses the Redis addon that Cloudron provides to every app. There is nothing else to set up.

### Sockudo with the Redis app

Install Redis first, so Sockudo can be connected right away.

1. Install **Redis** on a subdomain, for example `redis.example.com`. Keep the suggested TCP port `6380`; it must not be in use on the server.
2. Open `https://redis.example.com`. The page should say *Redis is running*.
3. Copy the password from the Redis app's `/app/data/credentials.env`.
4. Install **Sockudo** on a subdomain, for example `ws.example.com`.
5. Add this line to Sockudo's `/app/data/env.sh`, using your password and domain, then restart Sockudo:

   ```bash
   export SOCKUDO_REDIS_URL="rediss://default:PASSWORD@redis.example.com:6380/0"
   ```

6. The Sockudo log should show `Using external Redis at redis.example.com:6380 (db 0, tls true)`.

Always connect to the Redis app by its domain, not its IP address: the TLS certificate is issued for the domain. More options are described under [Redis: addon or external server](#redis-addon-or-external-server).

### With the CLI

```bash
cloudron install --versions-url https://raw.githubusercontent.com/FX6W9WZK/cloudron-sockudo/main/redis/CloudronVersions.json --location redis
cloudron install --versions-url https://raw.githubusercontent.com/FX6W9WZK/cloudron-sockudo/main/CloudronVersions.json --location ws
```

### Moving from a self-installed Sockudo or redis-server

* **Keep your app credentials.** In `/app/data/config.json`, replace `id`, `key` and `secret` of the generated app under `app_manager.array.apps` with your existing ones (plus any limits or options), then restart. Copy only the app entries, not your whole old config: the package sets the listener and the Redis connection itself on every start. If your old setup loaded apps from MySQL or PostgreSQL, add them to this list instead.
* **Clients only change host and port.** On Cloudron, Sockudo is reached through the app domain on port 443 with TLS, see the [client example](#client-example-pusher-js--laravel-echo).
* **No Redis data to move for Sockudo.** It only keeps short-lived data in Redis (cache, webhook queue). If other programs store data in your old Redis, moving that data is a separate step.
* **Free the port first.** Stop an old `redis-server` on the same server before installing the Redis app if it uses port `6380`, and remove it afterwards: Cloudron does not support extra software on the host.

### Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| *Could not load app* when adding the URL | GitHub serves these files from a cache for up to 5 minutes after a change. Try again later. If the message stays, [open an issue](https://github.com/FX6W9WZK/cloudron-sockudo/issues) with the full text. |
| Sockudo does not start after setting `SOCKUDO_REDIS_URL` | The log shows the reason, for example an invalid URL or a wrong password. Fix or remove the line in `env.sh` and restart. Without the line, Sockudo falls back to the built-in Redis. |
| Sockudo cannot reach the Redis app | Check that the TCP port is enabled in the Redis app's settings and that a firewall at your hosting provider allows it. Cloudron only opens its own firewall. |
| Clients cannot connect | Use port 443 with TLS (`forceTLS: true`, `PUSHER_SCHEME=https`). The app's internal port 6001 is not reachable from outside. |

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
