# JSON

watax uses Tauraro's `std.encoding.json`. You build a `JsonValue` tree, and for
responses you hand it to `send_json_value`, which serializes, sends, **and frees
the whole tree** — your handler frees nothing.

## Building values

```tauraro
from std.encoding.json import JsonValue

mut s = JsonValue.init_str("hello")
mut n = JsonValue.init_int(42)
mut f = JsonValue.init_float(3.14)
mut b = JsonValue.init_bool(true)
mut z = JsonValue.init_null()
```

## Objects

```tauraro
mut user = JsonValue.init_object()
user.read().obj_set("id", JsonValue.init_int(42))
user.read().obj_set("name", JsonValue.init_str("Ada"))
user.read().obj_set("admin", JsonValue.init_bool(false))
```

> `init_object()` returns a `Pointer[JsonValue]`, so call methods through
> `.read()` (e.g. `user.read().obj_set(...)`).

## Arrays

```tauraro
mut tags = JsonValue.init_array()
tags.read().push(JsonValue.init_str("web"))
tags.read().push(JsonValue.init_str("fast"))

mut doc = JsonValue.init_object()
doc.read().obj_set("tags", tags)        # nest arrays/objects freely
```

## Sending JSON (recommended)

```tauraro
def get_user(c: HttpConn):
    mut o = JsonValue.init_object()
    o.read().obj_set("id", JsonValue.init_int(42))
    o.read().obj_set("name", JsonValue.init_str("Ada"))
    c.send_json_value(200, o)        # serialize + send + free the whole tree
```

**No `dispose`/`free` in your handler.** `send_json_value` owns the value tree
and the serialized string, and releases both. This is the leak-proof path.

## Reading request JSON

```tauraro
def update(c: HttpConn):
    mut body = c.request.json()                       # Pointer[JsonValue]
    mut name = body.read().obj_get("name").read().get_str()
    mut age  = body.read().obj_get("age").read().get_int()
    # ... use name/age ...
    body.read().dispose()                             # free the parsed tree
    c.send_status(204)
```

Useful readers:

| Method | Returns |
|--------|---------|
| `v.read().obj_get(key)` | child value (a `null` value if absent) |
| `v.read().obj_has(key)` | whether a key exists |
| `v.read().get_str()` / `get_int()` / `get_float()` / `get_bool()` | the scalar |
| `v.read().is_object()` / `is_array()` / `is_str()` / … | type checks |
| `v.read().array_len()` / `array_get(i)` | array access |
| `v.read().to_str()` / `to_pretty(2)` | serialize to a string |

## Ownership rules (important)

- **Responses are framework-owned.** Anything you pass to `send_json_value` is
  serialized and freed by watax — don't `dispose` it yourself.
- **Parsed requests are yours.** `request.json()` allocates a tree you own;
  call `.dispose()` when finished.
- **Children belong to their parent.** Once you `obj_set`/`push` a child into a
  parent, disposing the parent frees the child too — never dispose a child you
  already added.

These rules mean a typical handler has exactly **one** `dispose` (for a parsed
request) and **zero** `free` calls. See [Memory model](13-memory.md).

## Best practices

- **Prefer `send_json_value`** over `send_json` with a hand-built string — no
  manual escaping, no leaks.
- **Build the tree, then hand it off.** Don't keep references to a tree after
  passing it to `send_json_value`.
- **Dispose parsed request trees** exactly once.
- For very hot endpoints returning a constant shape, a precomputed string with
  `send_json` is fine — just remember watax frees a fresh response string.

## When JSON is perfect

`send_json_value` is the default for any API returning structured data. Use
templates instead when you're producing HTML, and chunked/SSE responses when the
payload is huge or streamed.
