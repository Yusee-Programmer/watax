# Responses

A handler replies by calling one of `c`'s `send_*` helpers. You never build the
socket write or free the response body yourself — watax owns the response
lifecycle.

## Plain text

```tauraro
c.send_text(200, "Hello, World!")
```

Sets `Content-Type: text/plain; charset=utf-8`. **Perfect for**: health checks,
simple APIs, error messages.

## HTML

```tauraro
c.send_html(200, "<h1>Welcome</h1>")
```

Sets `Content-Type: text/html; charset=utf-8`. For non-trivial pages, prefer
[templates](06-templates.md).

## JSON — two ways

### From a string

```tauraro
c.send_json(200, "{\"ok\": true}")
```

Use when you already have a JSON string. **The string you pass is freed by the
framework** if it's a fresh allocation owned only by this call.

### From a `JsonValue` (recommended)

Build a tree and hand it over — watax serializes, sends, and **frees the whole
tree plus the serialized string** for you:

```tauraro
from std.encoding.json import JsonValue

def user(c: HttpConn):
    mut o = JsonValue.init_object()
    o.read().obj_set("id", JsonValue.init_int(42))
    o.read().obj_set("name", JsonValue.init_str("Ada"))
    c.send_json_value(200, o)        # no dispose/free needed in your handler
```

**Perfect for**: any structured JSON. It's the leak-proof, zero-ceremony path —
your handler never calls `dispose`/`free`. See [JSON](08-json.md).

## Templates

```tauraro
from templa import Context

mut ctx = Context.init()
ctx.set("name", "Ada")
c.send_template(200, "templates/profile.html", ctx)        # from a file
c.send_template_string(200, "<h1>{{ name }}</h1>", ctx)    # inline
```

See [Templates](06-templates.md).

## Status-only

```tauraro
c.send_status(204)        # empty body with the given status
c.abort(403, "forbidden") # status + a short text body (alias of send_text)
```

## Redirects

```tauraro
c.redirect("/login", false)   # 302 Found (temporary)
c.redirect("/new-url", true)  # 301 Moved Permanently
```

**Perfect for**: post/redirect/get after form submits, auth flows, URL changes.

## Cookies

```tauraro
# name, value, path, http_only
c.set_cookie("session", token, "/", true)
```

Sign cookie values to make them tamper-evident with `SessionCodec`
([Middleware](05-middleware.md#sessions)).

## Custom response headers

Set headers that apply to the next response on this connection:

```tauraro
c.set_resp_header("Cache-Control", "no-store")
c.set_resp_header("X-Request-Id", req_id)
c.send_json_value(200, payload)
```

## Streaming (chunked transfer-encoding)

For responses whose length isn't known up front, or that are produced
incrementally — without buffering the whole body in memory:

```tauraro
def report(c: HttpConn):
    c.begin_chunked(200, "text/plain")
    mut i = 0
    while i < 1000:
        c.write_chunk("row " + i.to_str() + "\n")
        i = i + 1
    c.end_chunked()
```

**Perfect for**: large exports, log tails, generated files — anything where you
don't want a multi-megabyte string in RAM. The connection stays usable for
keep-alive afterwards.

## Server-Sent Events (SSE)

A long-lived stream of `text/event-stream` events to the browser:

```tauraro
def events(c: HttpConn):
    c.begin_sse()
    mut n = 0
    while n < 10:
        c.send_event("tick " + n.to_str())
        n = n + 1
    # connection closes when the handler returns
```

**Perfect for**: live dashboards, progress updates, notifications — a simpler,
one-way alternative to WebSockets when the server only *pushes*.

## Choosing a response

| You're sending… | Use |
|-----------------|-----|
| A short string | `send_text` |
| An HTML page | `send_html` or `send_template` |
| Structured data | `send_json_value` (build a `JsonValue`) |
| Just a status | `send_status` / `abort` |
| A location change | `redirect` |
| A large/unknown-length body | `begin_chunked` / `write_chunk` / `end_chunked` |
| A push-only live stream | `begin_sse` / `send_event` |
| A bidirectional live channel | [WebSockets](09-websockets.md) |

## Best practices

- **Send exactly once per handler.** A handler should call one terminal
  `send_*` (or run a streaming sequence). Returning without sending yields an
  empty `200`; guard branches so every path responds.
- **Prefer `send_json_value`** over hand-built JSON strings — it's both safer
  (no manual escaping) and leak-proof.
- **Stream big bodies.** Don't materialize multi-MB strings; use chunked
  responses.
- **Set caching headers** for static-ish JSON/HTML to cut load.
