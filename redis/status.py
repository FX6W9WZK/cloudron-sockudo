#!/usr/bin/env python3
"""Status page and health check for the Cloudron HTTP port.

GET /healthz  200 when Redis answers PING on the local socket, 503 otherwise
GET /         minimal status page (no credentials)
"""

import html
import os
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SOCKET = "/run/redis/redis.sock"
PASSWORD = os.environ["REDIS_PASSWORD"]
DOMAIN = os.environ.get("CLOUDRON_APP_DOMAIN", "")
TLS_PORT = os.environ.get("REDIS_TLS_PORT", "")


def command(*args):
    """Send AUTH + one command over RESP and return the raw reply of the command."""
    def encode(parts):
        out = f"*{len(parts)}\r\n"
        for part in parts:
            out += f"${len(part.encode())}\r\n{part}\r\n"
        return out.encode()

    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
        conn.settimeout(2)
        conn.connect(SOCKET)
        conn.sendall(encode(["AUTH", PASSWORD]) + encode(list(args)))
        reply = b""
        while True:
            chunk = conn.recv(65536)
            if not chunk:
                break
            reply += chunk
            auth, _, rest = reply.partition(b"\r\n")
            if not auth.startswith(b"+OK"):
                raise RuntimeError("authentication failed")
            if rest.startswith((b"+", b"-")) and rest.endswith(b"\r\n"):
                return rest[1:-2].decode()
            if rest.startswith(b"$"):
                length, _, body = rest[1:].partition(b"\r\n")
                if len(body) >= int(length) + 2:
                    return body[: int(length)].decode()
    raise RuntimeError("connection closed")


def info():
    fields = {}
    for line in command("INFO").splitlines():
        key, sep, value = line.partition(":")
        if sep:
            fields[key] = value
    return fields


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            try:
                healthy = command("PING") == "PONG"
            except Exception:
                healthy = False
            self.respond(200 if healthy else 503, "text/plain", "ok\n" if healthy else "unavailable\n")
            return

        try:
            fields = info()
            # This page is public: no version, no key names or counts
            rows = [
                ("Uptime", f"{int(fields.get('uptime_in_seconds', 0)) // 3600} h"),
                ("Memory used", fields.get("used_memory_human", "?")),
                ("Memory limit", fields.get("maxmemory_human", "?")),
            ]
            status = "running"
        except Exception as error:
            rows, status = [("Error", str(error))], "not responding"

        if TLS_PORT:
            endpoint = f"rediss://default:&lt;password&gt;@{html.escape(DOMAIN)}:{html.escape(TLS_PORT)}"
        else:
            endpoint = "TCP port disabled in the app settings"
        table = "".join(f"<tr><th>{html.escape(k)}</th><td>{html.escape(v)}</td></tr>" for k, v in rows)
        page = f"""<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Redis</title>
<style>
body{{font:15px/1.5 system-ui,sans-serif;max-width:640px;margin:40px auto;padding:0 16px;color:#1f2328;background:#fff}}
@media (prefers-color-scheme:dark){{body{{color:#e6edf3;background:#0d1117}}th{{color:#9198a1}}}}
h1{{font-size:22px}} table{{border-collapse:collapse;width:100%}} th,td{{text-align:left;padding:6px 8px;border-bottom:1px solid #8884}}
th{{color:#59636e;font-weight:500;width:40%}} code{{word-break:break-all}}
</style></head><body>
<h1>Redis is {status}</h1>
<p>Connect with <code>{endpoint}</code>. The password is in <code>/app/data/credentials.env</code>.</p>
<table>{table}</table>
</body></html>
"""
        self.respond(200, "text/html; charset=utf-8", page)

    def respond(self, code, content_type, body):
        data = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
