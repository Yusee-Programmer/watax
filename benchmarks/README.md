# watax benchmarks

HTTP throughput, latency, and **memory** comparison of **watax** against two
mature web stacks:

| App | Stack | Language |
|-----|-------|----------|
| `watax_app/`   | watax (reactor pool) | Tauraro |
| `axum_app/`    | axum-style routing over hyper 1.x | Rust |
| `fastapi_app/` | FastAPI on uvicorn | Python |

All three expose the **same** endpoints so the comparison is apples-to-apples:

| Route | Response |
|-------|----------|
| `GET /`            | `text/plain` — `Hello, World!` |
| `GET /json`        | JSON object `{"message","id","ok"}` |
| `GET /greet/:name` | JSON built from a path parameter — `{"hello": <name>}` |

## Running

```sh
# Linux / macOS (used by CI):
bash benchmarks/run_all.sh

# Windows:
pwsh benchmarks/run_all.ps1
```

Knobs (environment variables): `BENCH_CONC` (concurrent keep-alive connections,
default 50) and `BENCH_DUR` (seconds per endpoint, default 8). A framework whose
toolchain is missing (`cargo`, `fastapi`/`uvicorn`) is **skipped**, not failed,
so the suite always runs watax-only on a minimal machine.

The runner builds each server, drives it with [`wrk`](https://github.com/wg/wrk)
(a fast, accurate HTTP benchmarking tool — installed by CI), and records
**req/sec, average latency, error count, and peak resident memory**. When `wrk`
isn't available (e.g. on Windows) it falls back to the bundled, dependency-free
`loadtest.py`. Results are written to [`results.md`](results.md).

Extra knob: `BENCH_THREADS` (wrk worker threads, default 4).

## Why memory is the headline

watax handlers **never free memory manually**. The framework and the Tauraro
standard library own every per-request allocation:

- response bodies are released by `HttpResponse.dispose()` (std);
- `send_json_value(v)` serializes, sends, and disposes the whole `JsonValue`
  tree + the serialized string internally;
- string/collection locals are auto-dropped at scope exit by the compiler.

The net effect is that watax's peak RSS stays **flat** under sustained load —
no per-request leak — which is the property these benchmarks verify.
