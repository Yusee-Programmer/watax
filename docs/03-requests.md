# Requests

Inside a handler, `c.request` is the parsed `HttpRequest`. It exposes the method,
path, headers, body, and helpers to read parameters in every common form.

## Fields

```tauraro
def inspect(c: HttpConn):
    mut m = c.request.method      # "GET", "POST", …
    mut p = c.request.path        # "/users/42"
    mut q = c.request.query       # raw query string, no '?'
    mut b = c.request.body        # raw request body
    c.send_text(200, m + " " + p)
```

## Path parameters — `get_param`

From `:name` / `*name` route segments (see [Routing](02-routing.md)):

```tauraro
mut id = c.request.get_param("id")     # "" if absent
```

**Perfect for**: resource identifiers in the URL — `/users/:id`, `/files/*path`.

## Query string — `query_param`

```tauraro
# GET /search?q=tauraro&page=2
mut q    = c.request.query_param("q")      # "tauraro"
mut page = c.request.query_param("page")   # "2"  ("" if absent)
```

**Perfect for**: filtering, pagination, optional flags — anything that doesn't
change *which* resource is addressed.

## Form bodies — `form_param`

For `application/x-www-form-urlencoded` POSTs (HTML `<form>`):

```tauraro
def create(c: HttpConn):
    if not c.request.is_form():
        c.abort(415, "expected a form body")
        return
    mut title = c.request.form_param("title")
    mut body  = c.request.form_param("body")
    ...
```

`is_form()` checks the content type. **Perfect for**: classic server-rendered
HTML forms.

## JSON bodies — `request.json()`

Parse the body into a `JsonDoc` (a zero-copy arena) and read it through `root()`:

```tauraro
from std.encoding.json import JsonWriter

def create_user(c: HttpConn):
    if not c.request.is_json():
        c.abort(415, "expected JSON")
        return
    mut v = c.request.json()                    # -> JsonDoc (auto-dropped)
    mut name = v.root().obj_get("name").get_str()
    mut w = JsonWriter.init(64)
    w.begin_object(); w.field_str("name", name); w.end_object()
    c.send_json_writer(200, w)                  # owns + frees the writer
```

> The **parsed request** `JsonDoc` is auto-dropped when the handler returns (no
> `dispose()`); `get_str()` gives you an owned copy that outlives it. The
> **`JsonWriter`** you pass to `send_json_writer` is owned and freed by watax. See
> [JSON](08-json.md) and [Memory model](13-memory.md).

**Perfect for**: JSON APIs and SPA backends.

## Headers — `header`

```tauraro
mut auth = c.request.header("Authorization")   # "" if absent (case-insensitive)
mut ua   = c.request.header("User-Agent")
```

## Cookies — `cookie`

```tauraro
mut sid = c.request.cookie("session")   # "" if absent
if c.request.has_cookie():
    ...
```

Set cookies on the response with `c.set_cookie(...)` ([Responses](04-responses.md)),
and sign them with `SessionCodec` ([Middleware](05-middleware.md)).

## Keep-alive

```tauraro
if c.request.keep_alive():               # HTTP/1.1 persistent connection?
    ...
```

watax handles keep-alive automatically; you rarely need this directly.

## File uploads — multipart

For `multipart/form-data` (file uploads), see the dedicated section in
[Static files & uploads](07-static-files.md#uploads):

```tauraro
mut form = c.request.multipart()
mut avatar = form.get("avatar")          # a MultipartPart
if avatar.is_file():
    avatar.save("./uploads/" + avatar.filename)
mut name = form.field("name")            # a plain text field
form.dispose()
```

## Body-size limits

Large bodies are rejected before reaching your handler when you set a limit:

```tauraro
app = app.body_limit(1048576)            # 1 MiB; oversized requests get 413
```

In a handler you can also check `c.request.oversized` (true when the declared
`Content-Length` exceeded the limit) and reply `413` yourself.

## Best practices

- **Check the content type** (`is_json` / `is_form`) before parsing, and reply
  `415 Unsupported Media Type` on mismatch.
- **Validate, then act.** Treat all request input as untrusted; verify presence
  and shape before using it.
- **Dispose what you parse.** `request.json()` / `request.multipart()` allocate
  trees you own — call `.dispose()` when done. (Responses are framework-owned.)
- **Set a `body_limit`** on any endpoint that accepts uploads or JSON to bound
  memory and avoid abuse.
