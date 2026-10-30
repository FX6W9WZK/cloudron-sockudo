A default app with random credentials was created on first start. You can find `id`, `key` and `secret` in `/app/data/config.json`. Open it with the File Manager or the Web Terminal.

Client settings (pusher-js / Laravel Echo):

* Host: `$CLOUDRON-APP-DOMAIN`
* Port: `443`, TLS on (`forceTLS: true`)
* Key: the `key` from `config.json`

Server SDKs use the same host, with port `443` and scheme `https`, plus the app `id`, `key` and `secret`.

You can add more apps, webhooks or limits to `config.json`, then restart the app.
