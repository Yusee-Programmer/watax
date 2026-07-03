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
| A `JsonWriter` you pass to `send_json_writer` | watax (serialize → send → free writer) | nothing |
| A parsed **request** `JsonDoc` from `request.json()` | the compiler (auto-drop at scope exit) | nothing |
| A parsed **multipart** form from `request.multipart()` | **you** | `form.dispose()` |

So a typical JSON handler has **zero `free`/`dispose` calls**. The only thing you
still dispose is a parsed **multipart** form.

```tauraro
def create(c: HttpConn):
    mut v    = c.request.json()                 # JsonDoc — auto-dropped
    mut name = v.root().obj_get("name").get_str()   # get_str() is an owned copy

    mut w = JsonWriter.init(64)                 # watax will own + free this
    w.begin_object()
    w.field_str("name", name)
    w.field_bool("created", true)
    w.end_object()
    c.send_json_writer(201, w)                  # serialize + send + free writer
```

## How it works

- **Auto-drop.** Tauraro's compiler inserts releases for owned `str`/collection
  locals at the end of their scope across all tractable control-flow forms — so
  request-scoped strings and lists vanish when the handler returns.
- **Owning response APIs.** `HttpResponse.dispose()` releases the response body
  it retained, and `send_json_writer` frees the `JsonWriter` (its buffer and
  the serialized string). The leak that used to exist on the JSON path (each
  fresh response body's reference was never released) is fixed at this layer, so
  **every** watax app benefits — not just ones that remembered to free.
- **Zero-copy JSON reads.** `request.json()` returns a `JsonDoc` arena that is
  auto-dropped when the handler returns; `JsonRef`/`StrView` borrow from it with no
  allocation, and `get_str()` gives you an owned copy when you need to keep a value.

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
  API: dispose/free them yourself. (A `JsonWriter` you pass to `send_json_writer`
  is handled for you.)

If you find yourself writing `free`/`dispose` in a handler beyond the single
request-parse case, that's a signal the framework should grow an owning API —
the goal is **no manual memory management in user code**.

## Verifying it

The [benchmarks](../benchmarks/) measure **peak RSS** under sustained load. watax
stays flat (e.g. `/json` ≈ 4.8 MB and steady), while a leak would show as
monotonic growth. Run `benchmarks/run_all.sh` and watch the `Peak RSS` column —
flat is the contract.

## Best practices

- **Build a `JsonWriter`, hand it to `send_json_writer`** — don't free it.
- **Dispose a parsed multipart form** (`request.multipart()`) once. A parsed
  `request.json()` `JsonDoc` is auto-dropped — nothing to do.
- **Don't reach for `_tr_c_free`/`dispose` in handlers** otherwise; if you think
  you need to, prefer an owning framework API.
- **Load-test new endpoints** and confirm peak memory is flat.
