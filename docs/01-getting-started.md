# Getting started

watax is a web framework for [Tauraro](https://github.com/Yusee-Programmer/tauraro).
You build an app with a fluent builder, bind each route to a plain handler
function, and serve. Handlers are zero-cost function pointers
(`def(HttpConn) -> void`); the framework parses the request, dispatches to your
handler, and frees every per-request allocation for you.

## Install

watax is a taupkg package. In your project's `taupkg.toml`:

```toml
[package]
name = "myapp"
bin  = "src/main.tr"

[deps]
watax = "..."     # path/git/registry source, depending on how you vendor it
```

watax itself depends on [templa](https://github.com/Yusee-Programmer/templa)
for templating; `taupkg` resolves it transitively.

## Hello, World!

```tauraro
from watax import App
from std.net.http_server import HttpConn

def home(c: HttpConn):
    c.send_text(200, "Hello, watax!")

def main():
    mut app = App.new()
    app = app.get("/", home)
    app.listen_reactor_pool("127.0.0.1", 8080, 4)
```

Build and run:

```sh
taupkg build && ./myapp
# or directly:
tauraroc src/main.tr -o myapp && ./myapp
```

Open <http://127.0.0.1:8080/>.

## The shape of an app

```tauraro
def main():
    mut app = App.new()              # 1. create
    app = app.use(logger)            # 2. add middleware (optional)
    app = app.static_dir("/static", "./public")   # 3. static mounts (optional)
    app = app.get("/", home)         # 4. register routes
    app = app.post("/users", create_user)
    app = app.on_error(not_found)    # 5. error handler (optional)
    app.listen_reactor_pool("127.0.0.1", 8080, 4)   # 6. serve
```

> **Why the reassignment?** Each builder method returns the app, but the parser
> doesn't yet support multi-line method chaining, so write
> `app = app.get(...)` rather than `app.get(...).post(...)`. It's the same
> object; the reassignment is free.

### When to use what

| You want… | Reach for |
|-----------|-----------|
| The simplest possible server | `App.new()` + `listen` |
| Maximum throughput / many connections | `listen_reactor_pool` |
| A handler per URL | `app.get/post/put/patch/delete` |
| Shared logic before handlers | `app.use(mw)` (middleware) |
| Logging/metrics after handlers | `app.use_after(hook)` |
| To serve a folder of assets | `app.static_dir(prefix, dir)` |
| Grouped routes with a common prefix | `app.group("/api")` + `app.mount(router)` |
| Custom 404 / error pages | `app.on_error(handler)` |
| Config from environment | `Config.from_env()` |

## A handler

A handler takes the connection and writes a response:

```tauraro
def show_user(c: HttpConn):
    mut id = c.request.get_param("id")        # path param :id
    c.send_text(200, "user id = " + id)
```

`c.request` is the parsed request (method, path, params, query, body, headers,
cookies). `c` itself carries the response helpers (`send_text`, `send_json`,
`send_html`, `send_json_value`, `redirect`, …). Everything you allocate in a
handler — strings, JSON trees, collections — is freed automatically when the
handler returns. See [Memory model](13-memory.md).

## Next

- [Routing](02-routing.md) — paths, params, groups, mounts.
- [Requests](03-requests.md) — read params, query, forms, JSON, cookies, uploads.
- [Responses](04-responses.md) — every way to reply.
- [Servers & deployment](10-servers.md) — pick the right `listen_*`.
