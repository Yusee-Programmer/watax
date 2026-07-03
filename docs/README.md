<p align="center">
  <img src="../assets/watax-logo.png" alt="watax" width="240">
</p>

<h1 align="center">watax documentation</h1>

<p align="center"><em>Everything you need to build fast, leak-free web services in Tauraro.</em></p>

---

Each guide includes runnable examples, **when** to reach for the feature, **how**
it works, and **best practices** — plus a "when it's perfect" note so you pick the
right tool for the job.

## Guides

1. [Getting started](01-getting-started.md) — install, hello world, the shape of an app.
2. [Routing](02-routing.md) — methods, path params, wildcards, groups, mounts, 404s.
3. [Requests](03-requests.md) — params, query, forms, JSON, headers, cookies, uploads.
4. [Responses](04-responses.md) — text/HTML/JSON/templates/redirects, streaming, SSE.
5. [Middleware](05-middleware.md) — before/after hooks, CORS, rate limit, sessions.
6. [Templates](06-templates.md) — templa rendering, layouts, escaping.
7. [Static files & uploads](07-static-files.md) — serving assets, SPA fallback, multipart.
8. [JSON](08-json.md) — writing with `JsonWriter`, reading with `JsonDoc`/`JsonRef`, `send_json_writer`.
9. [WebSockets](09-websockets.md) — RFC 6455 upgrade, echo loop, vs SSE.
10. [Servers & deployment](10-servers.md) — the `listen_*` strategies, which to use when.
11. [Configuration](11-configuration.md) — `Config.from_env()` and env vars.
12. [Testing](12-testing.md) — `TestClient` integration tests.
13. [Memory model](13-memory.md) — who frees what, and why handlers free nothing.
14. [Cheatsheet](14-cheatsheet.md) — one-page API reference.

## The 30-second version

```tauraro
from watax import App
from std.net.http_server import HttpConn
from std.encoding.json import JsonWriter

def hello(c: HttpConn):
    c.send_text(200, "Hello, World!")

def user(c: HttpConn):
    mut w = JsonWriter.init(64)
    w.begin_object(); w.field_int("id", 42); w.end_object()
    c.send_json_writer(200, w)          # watax frees the writer

def main():
    mut app = App.new()
        .get("/", hello)
        .get("/users/:id", user)
    app.listen_reactor_pool("127.0.0.1", 8080, 4)
```

> **Golden rule (memory):** build it and hand it to a `send_*` → watax frees it;
> parse it from the request → it's auto-dropped when the handler returns;
> everything else is auto-freed. Handlers call **no** `free`/`dispose`. See
> [Memory model](13-memory.md).
