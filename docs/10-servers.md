# Servers & deployment

watax offers several `listen_*` strategies. They differ in their concurrency
model — pick based on your workload. All take a host and port.

## The options at a glance

| Method | Model | Best for |
|--------|-------|----------|
| `listen(host, port)` | single-threaded accept loop | dev, tools, lowest concurrency |
| `listen_threaded(host, port)` | one OS thread per connection | moderate concurrency, blocking handlers |
| `listen_pooled(host, port, workers)` | fixed thread pool | bounded threads, steady load |
| `listen_async(host, port, workers)` | worker pool (async dispatch) | mixed workloads |
| `listen_reactor(host, port)` | single-thread event loop (epoll/kqueue/WSAPoll) | many idle keep-alive conns, one core |
| **`listen_reactor_pool(host, port, workers)`** | **reactor per worker** | **maximum throughput — the default** |
| `listen_tls(host, port, cert, key)` | TLS termination | HTTPS (needs `-DTAURARO_TLS_OPENSSL`) |

## Recommended: `listen_reactor_pool`

```tauraro
app.listen_reactor_pool("127.0.0.1", 8080, 4)   # 4 reactor workers
```

A pool of event-loop workers, each multiplexing many connections with the
platform's best readiness primitive (epoll on Linux, kqueue on macOS/BSD,
WSAPoll on Windows). This is the path the [benchmarks](../benchmarks/) exercise:
throughput on par with Rust (axum/hyper) and a flat memory footprint.

- **Pick `workers` ≈ CPU cores** for CPU-bound handlers; a bit higher if
  handlers do blocking I/O.
- **Perfect for**: production HTTP/JSON APIs, high connection counts, keep-alive
  heavy traffic.

## `listen_threaded`

```tauraro
app.listen_threaded("127.0.0.1", 8080)
```

Spawns a thread per accepted connection. Simple mental model; fine when handlers
block (e.g. synchronous DB calls) and concurrency is moderate.

- **Perfect for**: internal tools, admin panels, apps with blocking handlers and
  modest traffic.
- **Watch out**: thread-per-connection doesn't scale to tens of thousands of
  idle keep-alive connections — use a reactor for that.

## `listen` / `listen_reactor` (single core)

```tauraro
app.listen("127.0.0.1", 8080)            # simplest
app.listen_reactor("127.0.0.1", 8080)    # event loop, one core
```

- `listen` — the simplest possible server; great for development and CLIs.
- `listen_reactor` — a single event loop; handles many connections on one core
  with low memory. **Perfect for**: sidecars, low-traffic services, or pinning to
  one core.

## TLS / HTTPS — `listen_tls`

```tauraro
app.listen_tls("0.0.0.0", 8443, "cert.pem", "key.pem")
```

Terminates TLS in-process. Requires building with OpenSSL:
`-DTAURARO_TLS_OPENSSL`. In many deployments it's simpler to terminate TLS at a
reverse proxy (nginx/Caddy) and run watax behind it on plain HTTP.

## Graceful shutdown

watax integrates with `std.sys.signal` (re-exported as `Signal`) so you can stop
the accept loop on `SIGINT`/`SIGTERM` and let in-flight requests finish. (On
native Windows, `kill -INT` from some shells doesn't deliver; use the platform's
console signal.)

## Deployment checklist

- **Choose the server:** `listen_reactor_pool` for production APIs; pick
  `workers` from CPU count and load-test.
- **Set a `body_limit`** ([Requests](03-requests.md#body-size-limits)) to bound
  per-request memory.
- **Terminate TLS** at a proxy or via `listen_tls`.
- **Bind correctly:** `127.0.0.1` for local/behind-proxy, `0.0.0.0` to accept
  external traffic.
- **Configure from the environment** with [`Config.from_env()`](11-configuration.md).
- **Front static/edge load with a CDN** for very high static traffic.
- **Verify memory stays flat** under sustained load — that's watax's design
  guarantee; the [benchmarks](../benchmarks/) show how to measure it.

## Decision guide

```
Need HTTPS in-process?                      -> listen_tls
Tens of thousands of keep-alive conns?      -> listen_reactor_pool
Production HTTP/JSON API?                    -> listen_reactor_pool (default)
Handlers block on sync I/O, modest traffic? -> listen_threaded
One core / sidecar / low traffic?           -> listen_reactor or listen
Just developing locally?                     -> listen
```
