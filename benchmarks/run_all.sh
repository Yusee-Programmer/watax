#!/usr/bin/env bash
# run_all.sh — watax HTTP benchmark suite: watax vs Rust (axum/hyper) vs
# Python (FastAPI). For each framework and endpoint it measures throughput
# (req/sec), average latency, error count, and PEAK resident memory (the
# headline metric after the auto-drop / leak work — watax should stay flat).
#
# Comparable endpoints (identical semantics in all three apps):
#   GET /                   plain text
#   GET /json               small JSON object
#   GET /greet/:name        JSON built from a path parameter
#   GET /users              larger JSON payload (20-element array of objects)
#   GET /db                 TechEmpower single query   (1 in-memory "World" row)
#   GET /queries?queries=N  TechEmpower multiple queries (N rows, 1..500)
#   GET /updates?queries=N  TechEmpower updates (N rows read + written back)
#   GET /fortunes           TechEmpower fortunes (HTML table, escaped, +1 row)
#   GET /plaintext-big      ~11 KB plain text (large response)
# (watax also serves a WebSocket echo at /ws — not in the wrk table since wrk
#  speaks HTTP, not WebSocket.) The TechEmpower-style endpoints use IN-MEMORY
# data, not a real database, so they measure framework overhead (routing, query
# parsing, JSON serialization, HTML templating) — not DB latency.
#
# Reports throughput (req/s), avg + p50 + p99 latency, Transfer/sec, errors,
# peak RSS, and a memory-efficiency score (req/s per MB of peak RSS).
#
# A framework is skipped (not failed) when its toolchain is absent, so the
# suite still runs watax-only on minimal machines. Writes a Markdown report to
# benchmarks/results.md.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCH="$SCRIPT_DIR"
WATAX_ROOT="$(cd "$BENCH/.." && pwd)"
RESULTS_MD="$BENCH/results.md"
LOADTEST="$BENCH/loadtest.py"

# Remove any inherited benchmark settings from CI
# unset BENCH_CONC
# unset BENCH_DUR
# unset BENCH_THREADS
# unset BENCH_REQUESTS

# Fixed load settings
CONC=${BENCH_CONC:-100}
DUR=${BENCH_DUR:-0}
THREADS=${BENCH_THREADS:-8}
REQUESTS=${BENCH_REQUESTS:-10000}

PY="$(command -v python3 || command -v python || echo python3)"

# Load generator: prefer wrk (fast, accurate), fall back to the bundled
# dependency-free loadtest.py when wrk isn't installed (e.g. on Windows).
WRK="$(command -v wrk || true)"

# ── tauraroc resolution: env TAURAROC, then PATH, then known install ───────────
TAU_EXE="${TAURAROC:-}"
if [ -z "$TAU_EXE" ]; then
    if command -v tauraroc &>/dev/null; then TAU_EXE="$(command -v tauraroc)"
    elif [ -x "$WATAX_ROOT/tauraroc" ]; then TAU_EXE="$WATAX_ROOT/tauraroc"
    elif [ -x "$WATAX_ROOT/tauraroc.exe" ]; then TAU_EXE="$WATAX_ROOT/tauraroc.exe"
    fi
fi

GRN='\033[0;32m'; YLW='\033[0;33m'; CYN='\033[0;36m'; RST='\033[0m'

# Peak RSS (kB) of a pid, from /proc VmHWM (Linux high-water mark; persists).
peak_rss_kb() { awk '/^VmHWM/{print $2}' "/proc/$1/status" 2>/dev/null; }

# Run a load test against $1; echo "rps|errors|avg_ms|p50_ms|p99_ms|transfer_mb"
# (fields that the load generator can't supply are "-"). p50/p99 tail latency and
# Transfer/sec are the metrics devs scrutinise beyond raw throughput.
runload() {
    if [ -n "$WRK" ]; then
        # wrk --latency reports Requests/sec, avg Latency, the latency
        # distribution (50/75/90/99%), Transfer/sec, socket errors and non-2xx
        # counts. Normalize every latency to ms and transfer to MB.
        local dur_s="$DUR"; [ "$dur_s" -le 0 ] && dur_s=30
        "$WRK" -t"$THREADS" -c"$CONC" -d"${dur_s}s" --latency "$1" 2>/dev/null | awk '
            function ms(v) {
                if      (v ~ /us$/) { sub(/us/,"",v); return v/1000 }
                else if (v ~ /ms$/) { sub(/ms/,"",v); return v+0 }
                else if (v ~ /s$/)  { sub(/s/,"",v);  return v*1000 }
                else                { return v+0 }
            }
            function mb(v) {
                if      (v ~ /GB$/) { sub(/GB/,"",v); return v*1024 }
                else if (v ~ /MB$/) { sub(/MB/,"",v); return v+0 }
                else if (v ~ /KB$/) { sub(/KB/,"",v); return v/1024 }
                else if (v ~ /B$/)  { sub(/B/,"",v);  return v/1048576 }
                else                { return v+0 }
            }
            /Requests\/sec/ { rps=$2 }
            /Transfer\/sec/ { xfer=mb($2) }
            # Thread-Stats avg latency line: "Latency  2.10ms ..." (digit after
            # Latency) — not the "Latency Distribution" header that --latency adds.
            /^[[:space:]]*Latency[[:space:]]+[0-9]/ { lat=ms($2) }
            /^[[:space:]]*50%/ { p50=ms($2) }
            /^[[:space:]]*99%/ { p99=ms($2) }
            /Non-2xx or 3xx responses/ { n2=$NF }
            /Socket errors/ { to=$NF }   # timeout count is the last field
            END {
                e=(n2=="" ? 0 : n2) + (to=="" ? 0 : to)
                printf "%s|%d|%.3f|%.3f|%.3f|%.2f", rps, e, lat, p50, p99, xfer
            }'
    else
        "$PY" "$LOADTEST" "$1" "$CONC" "$DUR" yes "$REQUESTS" 2>/dev/null | awk -F: '
            /Req\/sec/      {gsub(/ /,"",$2); rps=$2}
            /Errors/        {gsub(/ /,"",$2); err=$2}
            /Avg latency/   {gsub(/ms/,"",$2); gsub(/ /,"",$2); lat=$2}
            END {print rps"|"err"|"lat"|-|-|-"}'
    fi
}

declare -a ROWS=()   # "framework|endpoint|rps|errors|latency|peakKB"

# bench_framework <name> <port> <pidvar-already-started>
# Endpoints are fixed; caller has already started the server as $SERVER_PID.
ENDPOINTS=(
    "/|plaintext"
    "/json|json"
    "/greet/tauraro|route-param"
    "/users|users-json"
    "/db|db (1 row)"
    "/queries?queries=20|queries (20 rows)"
    "/updates?queries=20|updates (20 rows)"
    "/fortunes|fortunes (html)"
    "/plaintext-big|plaintext-big (~11KB)"
)

bench_framework() {
    local name="$1" port="$2" pid="$3"
    # Warm up + confirm it's listening.
    sleep 2
    if ! "$PY" - "$port" <<'PYEOF' 2>/dev/null
import socket,sys
s=socket.socket(); s.settimeout(3)
try: s.connect(("127.0.0.1",int(sys.argv[1]))); sys.exit(0)
except Exception: sys.exit(1)
PYEOF
    then
        printf "${YLW}  %s did not come up on :%s — skipping${RST}\n" "$name" "$port"
        return 1
    fi
    for ep in "${ENDPOINTS[@]}"; do
        local path="${ep%%|*}" label="${ep##*|}"
        printf "  %-8s %-12s ... " "$name" "$label"
        IFS='|' read -r rps err lat p50 p99 xfer <<< "$(runload "http://127.0.0.1:$port$path")"
        local peak; peak="$(peak_rss_kb "$pid")"
        # Memory efficiency: requests/sec served per MB of peak RSS — watax's
        # headline strength. Computed here so it lands in the report verbatim.
        local eff="-"
        if [ -n "$rps" ] && [ -n "$peak" ] && [ "$peak" != "?" ] && [ "$peak" -gt 0 ] 2>/dev/null; then
            eff="$(awk -v r="$rps" -v p="$peak" 'BEGIN{ printf "%.0f", r/(p/1024) }')"
        fi
        ROWS+=("$name|$label|${rps:-FAIL}|${err:-?}|${lat:-?}|${p50:--}|${p99:--}|${xfer:--}|${peak:-?}|${eff:--}")
        printf "%s req/s, p99 %s ms, %s err, %s KB peak\n" "${rps:-FAIL}" "${p99:-?}" "${err:-0}" "${peak:-?}"
    done
}

echo ""
printf "${CYN}=================================================================${RST}\n"
printf "${CYN}  watax HTTP Benchmark — watax vs axum (Rust) vs FastAPI (Python)${RST}\n"
if [ -n "$WRK" ]; then
    printf "${CYN}  load: wrk  %s threads × %s conns × %s req/endpoint${RST}\n" "$THREADS" "$CONC" "$REQUESTS"
else
    printf "${YLW}  load: loadtest.py (wrk not found)  %s conns × %s req/endpoint${RST}\n" "$CONC" "$REQUESTS"
fi
printf "${CYN}=================================================================${RST}\n\n"

# ── watax ─────────────────────────────────────────────────────────────────────
if [ -n "$TAU_EXE" ] && [ -x "$TAU_EXE" ] || command -v "$TAU_EXE" &>/dev/null; then
    printf "${YLW}Building watax_app...${RST}\n"
    # Build from the watax ROOT so `from watax import ...` resolves the framework
    # modules (src/) and the templa dependency (.taupkg/packages/).
    ( cd "$WATAX_ROOT" \
      && TAURARO_PATH="$WATAX_ROOT/.taupkg/packages:$WATAX_ROOT/src" \
         "$TAU_EXE" --strict -O3 benchmarks/watax_app/src/main.tr -o "$BENCH/watax_app/server" >/tmp/watax_build.log 2>&1 )
    WX="$BENCH/watax_app/server"; [ -x "$WX" ] || WX="$BENCH/watax_app/server.exe"
    if [ -x "$WX" ]; then
        "$WX" & SERVER_PID=$!
        bench_framework watax 8200 "$SERVER_PID" || true
        kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null
    else
        printf "${YLW}  watax build FAILED — diagnostics:${RST}\n"
        # Show the actual compiler/gcc errors so failures are diagnosable in CI.
        grep -nE "error:|undeclared|undefined reference|^build/" /tmp/watax_build.log 2>/dev/null | head -30
        echo "  --- last 20 lines of build log ---"
        tail -20 /tmp/watax_build.log 2>/dev/null
    fi
else
    printf "${YLW}tauraroc not found — skipping watax${RST}\n"
fi

# ── axum (Rust / hyper) ───────────────────────────────────────────────────────
if command -v cargo &>/dev/null; then
    printf "${YLW}Building axum_app (cargo --release)...${RST}\n"
    ( cd "$BENCH/axum_app" && cargo build --release >/tmp/axum_build.log 2>&1 )
    AX="$BENCH/axum_app/target/release/axum_bench"
    if [ -x "$AX" ]; then
        "$AX" & SERVER_PID=$!
        bench_framework axum 8300 "$SERVER_PID" || true
        kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null
    else
        printf "${YLW}  axum build failed (see /tmp/axum_build.log) — skipping${RST}\n"
    fi
else
    printf "${YLW}cargo not found — skipping axum${RST}\n"
fi

# ── FastAPI (Python / uvicorn) ────────────────────────────────────────────────
if "$PY" -c "import fastapi, uvicorn" 2>/dev/null; then
    printf "${YLW}Starting FastAPI (uvicorn)...${RST}\n"
    ( cd "$BENCH/fastapi_app" && "$PY" -m uvicorn main:app --host 127.0.0.1 --port 8400 \
        --workers 8 --no-access-log --log-level warning >/tmp/fastapi.log 2>&1 ) & SERVER_PID=$!
    bench_framework fastapi 8400 "$SERVER_PID" || true
    kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null
    # uvicorn spawns a child; make sure the port is freed.
    pkill -f "uvicorn main:app" 2>/dev/null || true
else
    printf "${YLW}fastapi/uvicorn not installed — skipping FastAPI${RST}\n"
fi

# ── Markdown report ───────────────────────────────────────────────────────────
{
    echo "# watax Benchmark Results"
    echo ""
    echo "watax vs **axum** (Rust/hyper) vs **FastAPI** (Python/uvicorn). Higher"
    echo "req/sec is better; lower latency, errors, and peak memory are better."
    echo "Generated by \`benchmarks/run_all.sh\`."
    echo ""
    echo "- **Host:** $(uname -s) $(uname -m)"
    echo "- **Date (UTC):** $(date -u '+%Y-%m-%d %H:%M:%S')"
    if [ -n "$WRK" ]; then
        echo "- **Load:** \`wrk\` — ${THREADS} threads × ${CONC} connections × ${REQUESTS} requests per endpoint  (8 proc x 1 worker each)"
    else
        echo "- **Load:** \`loadtest.py\` — ${CONC} keep-alive connections × ${REQUESTS} requests per endpoint  (8 proc x 1 worker each)"
    fi
    if [ -n "$TAU_EXE" ]; then echo "- **Compiler:** \`$TAU_EXE\`"; fi
    if command -v cargo &>/dev/null; then echo "- **Rust:** $(rustc --version 2>/dev/null)"; fi
    echo ""
    echo "## Throughput, latency & memory"
    echo ""
    echo "Latency columns: **Avg** is the mean, **p50** the median, **p99** the"
    echo "99th-percentile tail (the metric that matters for real SLAs). **Transfer/sec**"
    echo "is wire throughput. **Req/s per MB** is requests/sec served per MB of peak"
    echo "RSS — a memory-efficiency score where higher is better."
    echo ""
    echo "| Framework | Endpoint | Req/sec | Avg (ms) | p50 (ms) | p99 (ms) | Transfer/sec (MB) | Errors | Peak RSS (KB) | Req/s per MB |"
    echo "|-----------|----------|--------:|---------:|---------:|---------:|------------------:|-------:|--------------:|-------------:|"
    for r in "${ROWS[@]}"; do
        IFS='|' read -r fw ep rps err lat p50 p99 xfer peak eff <<< "$r"
        echo "| $fw | $ep | $rps | $lat | $p50 | $p99 | $xfer | $err | $peak | $eff |"
    done
    echo ""
    echo "### Concurrency model"
    echo ""
    echo "watax serves with a **reactor pool** (\`listen_reactor_pool\`): a small, fixed"
    echo "set of OS worker threads, each running its OWN independent readiness reactor"
    echo "(epoll/kqueue/WSAPoll) over its own connection table — no mutable state is"
    echo "shared between workers, so it is data-race-free and passes \`--strict\`. Every"
    echo "connection is one fd in a worker's readiness set doing non-blocking I/O —"
    echo "concurrency without a thread per request, the same model as axum/tokio."
    echo "Request headers are parsed lazily (scanned on demand) and all"
    echo "per-request memory is freed inside the framework (auto-drop + owning response"
    echo "APIs), so peak RSS stays flat under sustained load — user handlers never call"
    echo "free/dispose."
    echo ""
    echo "### Test types"
    echo ""
    echo "Beyond plaintext/JSON, the suite includes TechEmpower-style endpoints:"
    echo "**db** (single row), **queries** (N rows), **updates** (N rows read +"
    echo "written), and **fortunes** (HTML table with per-row escaping). These use an"
    echo "**in-memory** \`World\`/\`Fortune\` store — there is no real database, so they"
    echo "measure framework overhead (routing, query-string parsing, JSON"
    echo "serialization, HTML templating), not DB latency. watax additionally serves a"
    echo "WebSocket echo at \`/ws\` (RFC 6455), which isn't in the table above because"
    echo "\`wrk\` benchmarks HTTP, not WebSocket. The watax app is built with \`-O3\`."
} > "$RESULTS_MD"

printf "\n${GRN}Wrote Markdown report: %s${RST}\n\n" "$RESULTS_MD"

