# Memory model

watax's headline property: **handlers never free memory.** You allocate strings,
JSON trees, and collections freely; the compiler and framework release them. The
result is a flat, predictable memory footprint under sustained load — no
per-request leak.

## Who frees what

| Allocation | Freed by | You do |
|------------|----------|--------|
| `str` / collection **locals** in a handler | the compiler (auto-drop at scope exit) | nothing |
| A response body you pass to `send_text`/`send_json`/… | watax (`HttpResponse.dispose`) | nothing |
| A `JsonValue` you pass to `send_json_value` | watax (serialize → send → dispose tree) | nothing |
| A parsed **request** tree from `request.json()` | **you** | `body.read().dispose()` |
| A parsed **multipart** form from `request.multipart()` | **you** | `form.dispose()` |

So a typical handler has **zero `free` calls** and **at most one `dispose`** (for
something it *parsed* from the request).

```tauraro
def create(c: HttpConn):
    mut body = c.request.json()                 # you own this -> dispose it
    mut name = body.read().obj_get("name").read().get_str()

    mut out = JsonValue.init_object()           # framework will own this
    out.read().obj_set("name", JsonValue.init_str(name))
    out.read().obj_set("created", JsonValue.init_bool(true))
    c.send_json_value(201, out)                 # serialize + send + free tree

    body.read().dispose()                       # free what you parsed
```

## How it works

- **Auto-drop.** Tauraro's compiler inserts releases for owned `str`/collection
  locals at the end of their scope across all tractable control-flow forms — so
  request-scoped strings and lists vanish when the handler returns.
- **Owning response APIs.** `HttpResponse.dispose()` releases the response body
  it retained, and `send_json_value` disposes the entire `JsonValue` tree plus
  the serialized string. The leak that used to exist on the JSON path (each
  fresh response body's reference was never released) is fixed at this layer, so
  **every** watax app benefits — not just ones that remembered to free.

## Why "framework owns it" matters

Earlier code asked users to `_tr_c_free(body)` after `send_json`. That's easy to
get wrong (leak if you forget, crash if you double-free), and it's exactly the
kind of bookkeeping a framework should hide. By moving every per-request free
into watax and the standard library, user handlers stay clean **and** correct by
construction.

## What still needs manual care (rare)

These are advanced/low-level and almost never appear in handler code:

- **Raw `unsafe` buffers** (e.g. hand-allocated byte buffers via `alloc[]`):
  whoever allocates frees. This is the point of `unsafe`.
- **`Pointer[T]` heap structs** you build by hand and *don't* hand to an owning
  API: dispose/free them yourself. (`JsonValue` you pass to `send_json_value` is
  handled for you; one you build and keep is yours.)

If you find yourself writing `free`/`dispose` in a handler beyond the single
request-parse case, that's a signal the framework should grow an owning API —
the goal is **no manual memory management in user code**.

## Verifying it

The [benchmarks](../benchmarks/) measure **peak RSS** under sustained load. watax
stays flat (e.g. `/json` ≈ 4.8 MB and steady), while a leak would show as
monotonic growth. Run `benchmarks/run_all.sh` and watch the `Peak RSS` column —
flat is the contract.

## Best practices

- **Build a `JsonValue`, hand it to `send_json_value`** — don't dispose it.
- **Dispose what you parse** (`request.json()`, `request.multipart()`) exactly
  once.
- **Don't reach for `_tr_c_free`/`dispose` in handlers** otherwise; if you think
  you need to, prefer an owning framework API.
- **Load-test new endpoints** and confirm peak memory is flat.
