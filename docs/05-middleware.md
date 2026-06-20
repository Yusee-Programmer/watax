# Middleware

Middleware runs cross-cutting logic around your handlers — auth, CORS, logging,
rate limiting — without repeating it in every route.

## Before middleware — `app.use`

A *before* middleware is a `def(HttpConn) -> bool`. It runs before the matched
handler. **Return `true` to continue** to the handler (and any later
middleware); **return `false` to short-circuit** (you've already sent a
response, e.g. a `401`).

```tauraro
def require_auth(c: HttpConn) -> bool:
    mut token = c.request.header("Authorization")
    if Str.len(token) == 0:
        c.abort(401, "missing token")
        return false                 # stop here
    return true                      # continue to the handler

app = app.use(require_auth)
```

Middleware runs in registration order. **Perfect for**: authentication,
request validation, CORS preflight, rate limiting, feature flags.

## After middleware — `app.use_after`

An *after* hook is a `def(HttpConn) -> void`, run after the handler responds.
Use it for logging, metrics, and timing:

```tauraro
from watax import request_logger_after

app = app.use_after(request_logger_after)   # logs "METHOD path -> status (ms)"
```

**Perfect for**: access logs, latency metrics, audit trails.

## Built-in middleware

### Request logging

```tauraro
from watax import request_logger_after
app = app.use_after(request_logger_after)
```

### CORS

```tauraro
from watax import set_cors_origin, cors_mw

set_cors_origin("https://app.example.com")   # or "*" for any origin
app = app.use(cors_mw)                        # adds CORS headers + handles preflight
```

**Perfect for**: browser SPAs calling your API from another origin.

### Rate limiting

```tauraro
from watax import set_rate_limit, rate_limit_mw

set_rate_limit(100, 60000)        # 100 requests per 60s window, per client
app = app.use(rate_limit_mw)      # replies 429 when exceeded
```

**Perfect for**: protecting public endpoints from abuse and accidental loops.

## Sessions — signed cookies

`SessionCodec` signs a cookie value with a secret so the client can't tamper
with it (it's not encrypted — don't store secrets in it, just identifiers):

```tauraro
from watax import SessionCodec

mut codec = SessionCodec.init("a-long-random-secret")

# On login:
mut signed = codec.encode("user=42")
c.set_cookie("session", signed, "/", true)

# On each request:
mut raw = codec.decode(c.request.cookie("session"))   # "" if tampered/absent
```

**Perfect for**: lightweight server-side sessions without a session store —
keep the payload small (a user id) and look up the rest server-side.

## Group-scoped middleware

Attach middleware to a subtree instead of the whole app via a `Router`:

```tauraro
mut api = Router.init("/api")
    .use(cors_mw)                # only /api/* gets CORS
    .use(rate_limit_mw)
    .get("/users/:id", api_user)
app = app.mount(api)
```

See [Routing → groups](02-routing.md#route-groups--mounts).

## Order & best practices

- **Order is execution order.** Put cheap, short-circuiting checks first
  (rate-limit → auth → validation) so you reject bad traffic before doing work.
- **A `false`-returning middleware must send a response** before returning, or
  the client gets nothing.
- **Keep middleware focused.** One concern per middleware; compose them.
- **Use `use_after` for observability**, `use` for control-flow.
- **Scope with `Router`** when a concern applies to only part of the app.

## When middleware is perfect

Reach for middleware whenever the same logic would otherwise be copy-pasted into
multiple handlers: auth gates, CORS, logging, rate limits, request IDs. If logic
is specific to one route, keep it in the handler.
