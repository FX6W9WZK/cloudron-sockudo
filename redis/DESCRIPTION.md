Redis is an in-memory data store used as a cache, message broker and database. This package installs Redis from the official Redis APT repository (packages.redis.io). It exposes Redis on a TCP port that only accepts TLS connections with a password.

### This package

* TLS with the app domain's certificate from Cloudron. Clients connect with `rediss://default:<password>@<app domain>:<port>`.
* A random password is generated on first start (`/app/data/credentials.env`).
* Data is persisted with AOF and RDB snapshots in `/app/data/redis` and included in Cloudron backups.
* `maxmemory` is set to 75% of the app's memory limit. Change the memory limit in the app's resource settings.
* Your own settings go into `/app/data/redis.conf`.
