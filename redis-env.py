#!/usr/bin/env python3
"""Turn SOCKUDO_REDIS_URL into the shell exports Sockudo reads.

Usage: eval "$(python3 redis-env.py redis[s]://[user]:password@host[:port][/db])"
"""

import shlex
import sys
from urllib.parse import unquote, urlsplit


def main():
    url = urlsplit(sys.argv[1])
    if url.scheme not in ("redis", "rediss") or not url.hostname:
        sys.exit("SOCKUDO_REDIS_URL must look like redis://:password@host:6379/0 or rediss://...")

    db = url.path.lstrip("/") or "0"
    if not db.isdigit():
        sys.exit(f"SOCKUDO_REDIS_URL: database must be a number, got '{db}'")

    exports = {
        "DATABASE_REDIS_HOST": url.hostname,
        "DATABASE_REDIS_PORT": str(url.port or 6379),
        "DATABASE_REDIS_USERNAME": unquote(url.username or ""),
        "DATABASE_REDIS_PASSWORD": unquote(url.password or ""),
        "DATABASE_REDIS_DB": db,
        "DATABASE_REDIS_MASTER_TLS_ENABLED": "true" if url.scheme == "rediss" else "false",
        "REDIS_URL": sys.argv[1],
    }
    for name, value in exports.items():
        print(f"export {name}={shlex.quote(value)}")


if __name__ == "__main__":
    main()
