# Configuration

`Config` reads settings from environment variables, so the same binary runs in
dev, staging, and prod without code changes.

## From the environment

```tauraro
from watax import Config

def main():
    mut cfg = Config.from_env()
    mut app = App.new()
        .static_dir("/static", cfg.static_dir)
    app.listen_reactor_pool(cfg.host, cfg.port, 4)
```

## Variables & defaults

| Field | Env var | Default |
|-------|---------|---------|
| `host` | `WATAX_HOST` | `127.0.0.1` |
| `port` | `WATAX_PORT` | `8080` |
| `static_dir` | `WATAX_STATIC_DIR` | `./public` |
| `cors_origin` | `WATAX_CORS_ORIGIN` | `*` |
| `rate_limit` | `WATAX_RATE_LIMIT` | `0` (off) |
| `rate_window_ms` | `WATAX_RATE_WINDOW_MS` | `60000` |

```sh
WATAX_HOST=0.0.0.0 WATAX_PORT=9000 WATAX_CORS_ORIGIN=https://app.example.com ./myapp
```

## Wiring config into middleware

```tauraro
from watax import Config, set_cors_origin, cors_mw, set_rate_limit, rate_limit_mw

mut cfg = Config.from_env()
set_cors_origin(cfg.cors_origin)
if cfg.rate_limit > 0:
    set_rate_limit(cfg.rate_limit, cfg.rate_window_ms)

mut app = App.new()
app = app.use(cors_mw)
if cfg.rate_limit > 0:
    app = app.use(rate_limit_mw)
```

## Best practices

- **Config from the environment, not code.** Keep hosts, ports, origins, and
  limits out of the source so the same artifact ships everywhere.
- **Bind `0.0.0.0` only when you mean it.** Default to `127.0.0.1` and open up
  explicitly via `WATAX_HOST` when running directly exposed.
- **Lock down CORS in prod.** `*` is convenient in dev; set a real origin via
  `WATAX_CORS_ORIGIN` in production.
- **Turn on rate limiting** for public endpoints (`WATAX_RATE_LIMIT`).
- **Validate at startup.** Read `Config.from_env()` once in `main`, fail fast if
  a required value is missing.

## When to use Config

Use `Config.from_env()` for anything that differs between environments:
bind address, port, CORS origin, rate limits, static root. For app-specific
settings (feature flags, secrets), read additional env vars the same way via
`std.sys.env`.
