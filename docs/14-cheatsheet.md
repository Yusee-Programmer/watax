# Cheatsheet

A one-page reference. Deep dives are linked from the [docs index](../README.md#documentation).

## App & routing

```tauraro
mut app = App.new()
app = app.use(mw)                       # before middleware  (def(HttpConn)->bool)
app = app.use_after(hook)               # after hook         (def(HttpConn)->void)
app = app.static_dir("/static", "./public")
app = app.body_limit(1048576)           # 413 over 1 MiB
app = app.get("/", home)
app = app.post("/users", create)
app = app.put("/users/:id", replace)
app = app.patch("/users/:id", update)
app = app.delete("/users/:id", remove)
app = app.route("OPTIONS", "/users", preflight)
app = app.mount(router)                 # mount a Router (prefix + group mw)
app = app.on_error(not_found)           # def(HttpConn, int)->void
app.listen_reactor_pool("127.0.0.1", 8080, 4)
```

## Request (`c.request`)

```tauraro
c.request.method                        # "GET"
c.request.path                          # "/users/42"
c.request.get_param("id")               # path param  :id  / *id
c.request.query_param("q")              # ?q=...
c.request.form_param("title")           # form field
c.request.json()                        # Pointer[JsonValue]  (you dispose)
c.request.multipart()                   # MultipartForm       (you dispose)
c.request.header("Authorization")       # header (case-insensitive)
c.request.cookie("session")             # cookie value
c.request.is_json() / is_form() / is_multipart()
c.request.keep_alive()
```

## Response (`c`)

```tauraro
c.send_text(200, "hi")
c.send_html(200, "<h1>hi</h1>")
c.send_json(200, "{\"ok\":true}")
c.send_json_value(200, jsonValue)       # owns + frees the tree
c.send_template(200, "page.html", ctx)
c.send_template_string(200, "{{ x }}", ctx)
c.send_status(204)
c.abort(403, "forbidden")
c.redirect("/login", false)             # true = 301
c.set_cookie("session", v, "/", true)
c.set_resp_header("Cache-Control", "no-store")
# streaming:
c.begin_chunked(200, "text/plain"); c.write_chunk("..."); c.end_chunked()
# SSE:
c.begin_sse(); c.send_event("tick")
# websocket:
mut ws = c.upgrade_websocket()
```

## JSON (`std.encoding.json`)

```tauraro
JsonValue.init_object() / init_array()
JsonValue.init_str(s) / init_int(n) / init_float(f) / init_bool(b) / init_null()
o.read().obj_set("k", v) / obj_get("k") / obj_has("k")
a.read().push(v) / array_get(i) / array_len()
v.read().get_str() / get_int() / get_float() / get_bool()
v.read().is_object() / is_array() / is_str() / ...
v.read().to_str() / to_pretty(2)
c.send_json_value(200, v)               # don't dispose v yourself
body.read().dispose()                   # DO dispose a parsed request tree
```

## Middleware (built-in)

```tauraro
from watax import request_logger_after, set_cors_origin, cors_mw,
                   set_rate_limit, rate_limit_mw, SessionCodec, html_escape
app = app.use_after(request_logger_after)
set_cors_origin("https://app.example.com"); app = app.use(cors_mw)
set_rate_limit(100, 60000);                 app = app.use(rate_limit_mw)
mut codec = SessionCodec.init("secret"); codec.encode(v); codec.decode(signed)
```

## Servers

```tauraro
app.listen("127.0.0.1", 8080)                       # simplest
app.listen_threaded("127.0.0.1", 8080)              # thread per conn
app.listen_pooled("127.0.0.1", 8080, 4)             # thread pool
app.listen_reactor("127.0.0.1", 8080)               # single event loop
app.listen_reactor_pool("127.0.0.1", 8080, 4)       # reactor pool (default)
app.listen_tls("0.0.0.0", 8443, "cert.pem", "key.pem")   # needs -DTAURARO_TLS_OPENSSL
```

## Config (env)

```tauraro
mut cfg = Config.from_env()
# WATAX_HOST / WATAX_PORT / WATAX_STATIC_DIR / WATAX_CORS_ORIGIN
# WATAX_RATE_LIMIT / WATAX_RATE_WINDOW_MS
```

## Testing

```tauraro
mut client = TestClient.start(build_app(), 8199)
mut r = client.get("/")                 # .post/.post_json/.put/.patch/.delete
assert r.status == 200 and r.body == "Hello, World!"
```

## Memory rule of thumb

> Build it and hand it to a `send_*` → **watax frees it.**
> Parse it from the request (`json()`/`multipart()`) → **you `dispose()` it once.**
> Everything else (str/collection locals) → **auto-freed.**
