# JSON

watax uses Tauraro's zero-copy `std.encoding.json`. You build responses with a
streaming **`JsonWriter`**, and you read request bodies through a **`JsonDoc`**
arena via borrowed **`JsonRef`** views. There are **no raw pointers** and nothing to
`free` in your handler — the writer is released by `send_json_writer`, and the parsed
`JsonDoc` is auto-dropped at the end of the handler.

## Sending JSON — `JsonWriter`

`JsonWriter` streams directly into a growable buffer (no intermediate tree, no
per-node allocation). Hand it to `c.send_json_writer(status, w)`, which serializes,
sends, **and frees the writer** for you.

```tauraro
from std.encoding.json import JsonWriter

def get_user(c: HttpConn):
    mut w = JsonWriter.init(64)          # starting capacity in bytes
    w.begin_object()
    w.field_int("id", 42)
    w.field_str("name", "Ada")
    w.field_bool("admin", false)
    w.end_object()
    c.send_json_writer(200, w)           # send + free the writer
```

**No `dispose`/`free` in your handler.** `send_json_writer` owns the writer and the
serialized bytes and releases both — the leak-proof path.

### Flat objects, the quick way

`field_int` / `field_str` / `field_bool` write a key and value in one call:

```tauraro
def healthz(c: HttpConn):
    mut w = JsonWriter.init(32)
    w.begin_object()
    w.field_str("status", "ok")
    w.field_int("notes", store_len())
    w.end_object()
    c.send_json_writer(200, w)
```

### Nested objects and arrays

Use the explicit `begin_*` / `end_*` + `key` / value calls:

```tauraro
mut w = JsonWriter.init(128)
w.begin_object()
    w.key("user"); w.begin_object()
        w.field_str("name", "Ada")
        w.field_int("id", 42)
    w.end_object()
    w.key("tags"); w.begin_array()
        w.str_val("web"); w.str_val("fast")
    w.end_array()
w.end_object()
c.send_json_writer(200, w)
# {"user":{"name":"Ada","id":42},"tags":["web","fast"]}
```

Writer methods: `begin_object`/`end_object`, `begin_array`/`end_array`, `key(name)`,
`int_val`/`str_val`/`bool_val`/`null_val`, and the one-shot `field_int`/`field_str`/
`field_bool`. (See the [std.encoding docs](https://github.com/Yusee-Programmer/tauraro)
for the full reference.)

## Reading request JSON — `JsonDoc` / `JsonRef`

`c.request.json()` parses the request body into a `JsonDoc` arena. Navigate it with
`root()` and the borrowed `JsonRef` accessors. The doc is **auto-dropped** when the
handler returns — no `dispose()` call.

```tauraro
def create_note(c: HttpConn):
    mut v = c.request.json()                     # -> JsonDoc
    if not v.root().is_object():
        c.abort(400, "{\"error\":\"expected a JSON object\"}")
        return
    mut title = v.root().obj_get("title").get_str()   # owned copy
    mut body  = v.root().obj_get("body").get_str()
    if v.root().obj_has("draft") and v.root().obj_get("draft").get_bool():
        ...
    store_add(title, body)
    c.send_status(204)
```

Useful `JsonRef` readers:

| Method | Returns |
|--------|---------|
| `root()` | the top-level `JsonRef` of the parsed doc |
| `obj_get(key)` | child value (a non-existent ref if absent) |
| `obj_has(key)` | whether a key exists |
| `get_str()` / `get_int()` / `get_float()` / `get_bool()` | the scalar (`get_str` is an owned copy) |
| `str_view()` / `str_eq(s)` | zero-copy string view / compare, **no allocation** |
| `is_object()` / `is_array()` / `is_str()` / `exists()` / … | type / presence checks |
| `array_len()` / `array_get(i)` | array access |
| `to_str()` | re-serialize this node to a compact string |

### Zero-copy reads on hot paths

When you only need to *test* a value (routing, validation), `str_view()` avoids
allocating a string entirely:

```tauraro
if c.request.json().root().obj_get("op").str_eq("ping"):
    c.send_status(200)
```

## Ownership rules (short version)

- **Responses are framework-owned.** The `JsonWriter` you pass to
  `send_json_writer` is freed by watax — never `free()` it yourself.
- **Parsed requests are auto-managed.** The `JsonDoc` from `request.json()` and any
  `JsonRef` borrowed from it are reclaimed automatically when the handler returns.
  `get_str()` returns an *owned* copy, so it's safe to keep after the doc drops.

The result: a typical JSON handler has **zero** `free`/`dispose` calls. See
[Memory model](13-memory.md).

## When JSON is perfect

`JsonWriter` + `send_json_writer` is the default for any API returning structured
data. Use [templates](06-templates.md) for HTML, and chunked/SSE responses when the
payload is huge or streamed.
