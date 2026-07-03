# Cheatsheet

A one-page reference. Deep dives are linked from the [docs index](../README.md#documentation).

## App & routing

```tauraro
mut app = App.new()
    .use(mw)                            # before middleware  (def(HttpConn)->bool)
    .use_after(hook)                    # after hook         (def(HttpConn)->void)
    .static_dir("/static", "./public")
    .body_limit(1048576)                # 413 over 1 MiB
    .get("/", home)
    .post("/users", create)
    .put("/users/:id", replace)
    .patch("/users/:id", update)
    .delete("/users/:id", remove)
    .route("OPTIONS", "/users", preflight)
    .mount(router)                      # mount a Router (prefix + group mw)
    .on_error(not_found)                # def(HttpConn, int)->void
app.listen_reactor_pool("127.0.0.1", 8080, 4)
```

## Request (`c.request`)

```tauraro
c.request.method                        # "GET"
c.request.path                          # "/users/42"
c.request.get_param("id")               # path param  :id  / *id
c.request.query_param("q")              # ?q=...
c.request.form_param("title")           # form field
c.request.json()                        # JsonDoc  (auto-dropped)
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
c.send_json_writer(200, w)               # owns + frees the JsonWriter
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
# --- read: JsonDoc + JsonRef (zero-copy, auto-dropped) ---
mut v    = c.request.json()              # JsonDoc
mut root = v.root()                      # JsonRef
root.obj_get("k").get_str() / get_int() / get_float() / get_bool()
root.obj_get("k").str_view() / str_eq("x")   # zero-copy, no alloc
root.obj_has("k") / is_object() / is_array() / is_str() / exists()
root.array_len() / array_get(i)
# --- write: JsonWriter (streaming) ---
mut w = JsonWriter.init(64)
w.begin_object(); w.field_str("k", "v"); w.field_int("n", 1); w.end_object()
w.begin_array(); w.str_val("a"); w.end_array()
c.send_json_writer(200, w)               # owns + frees the JsonWriter
# request.json() -> JsonDoc is auto-dropped; nothing to dispose
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
