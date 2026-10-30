Sockudo is a fast, self-hosted WebSocket server written in Rust. It speaks the Pusher protocol, so existing Pusher clients and server SDKs (pusher-js, Laravel Echo / Broadcasting, Pusher PHP, Node, Python, Go, Ruby, ...) work without code changes. You only point them to your own host.

### Features

* Pusher protocol and HTTP API: public, private, presence and encrypted channels
* Client events, user authentication and watchlists
* Webhooks for channel, member and client events
* Per-app limits, allowed origins and channel namespaces
* Delta compression, tag filtering, idempotent publishing and connection recovery
* Prometheus metrics

### This package

* Redis (Cloudron addon) backs the cache and the webhook queue
* Apps and settings live in `/app/data/config.json`. A default app with random credentials is created on first start.
