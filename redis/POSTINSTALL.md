Redis only accepts TLS connections with a password. The password was generated on first start and is in `/app/data/credentials.env`. Open it with the File Manager or the Web Terminal.

Connection URL:

```
rediss://default:<password>@$CLOUDRON-APP-DOMAIN:<port>
```

`<port>` is the TCP port you chose during installation (default `6380`). Cloudron opens it in the firewall. It is reachable from the internet, so keep the password secret.

For Sockudo from the same repository, put this into Sockudo's `/app/data/env.sh`:

```
export SOCKUDO_REDIS_URL="rediss://default:<password>@$CLOUDRON-APP-DOMAIN:<port>/0"
```
