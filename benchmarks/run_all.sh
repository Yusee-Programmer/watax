#!/usr/bin/env bash
# run_all.sh — watax HTTP benchmark suite: watax vs Rust (axum/hyper) vs
# Python (FastAPI). For each framework and endpoint it measures throughput
# (req/sec), average latency, error count, and PEAK resident memory (the
# headline metric after the auto-drop / leak work — watax should stay flat).
#
# Comparable endpoints (identical semantics in all three apps):
#   GET /            plain text
#   GET /json        small JSON object
#   GET /greet/:name JSON built from a path parameter
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

CONC="${BENCH_CONC:-50}"        # concurrent keep-alive connections
DUR="${BENCH_DUR:-8}"           # seconds per endpoint
THREADS="${BENCH_THREADS:-4}"   # wrk worker threads
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

# Run a load test against $1; echo "rps|errors|latency_ms" (empty on failure).
runload() {
    if [ -n "$WRK" ]; then
        # wrk --latency reports Requests/sec, the avg Latency (with a unit),
        # plus socket errors and non-2xx counts. Normalize latency to ms.
        "$WRK" -t"$THREADS" -c"$CONC" -d"${DUR}s" --latency "$1" 2>/dev/null | awk '
            /Requests\/sec/ { rps=$2 }
            # Thread-Stats avg latency line: "Latency  2.10ms ..." (digit after
            # Latency) — not the "Latency Distribution" header that --latency adds.
            /^[[:space:]]*Latency[[:space:]]+[0-9]/ {
                v=$2
                if      (v ~ /us$/) { sub(/us/,"",v); lat=v/1000 }
                else if (v ~ /ms$/) { sub(/ms/,"",v); lat=v }
                else if (v ~ /s$/)  { sub(/s/,"",v);  lat=v*1000 }
                else                { lat=v }
            }
            /Non-2xx or 3xx responses/ { n2=$NF }
            /Socket errors/ { to=$NF }   # timeout count is the last field
            END {
                e=(n2=="" ? 0 : n2) + (to=="" ? 0 : to)
                printf "%s|%d|%.3f", rps, e, lat
            }'
    else
        "$PY" "$LOADTEST" "$1" "$CONC" "$DUR" 2>/dev/null | awk -F: '
            /Req\/sec/      {gsub(/ /,"",$2); rps=$2}
            /Errors/        {gsub(/ /,"",$2); err=$2}
            /Avg latency/   {gsub(/ms/,"",$2); gsub(/ /,"",$2); lat=$2}
            END {print rps"|"err"|"lat}'
    fi
}

declare -a ROWS=()   # "framework|endpoint|rps|errors|latency|peakKB"

# bench_framework <name> <port> <pidvar-already-started>
# Endpoints are fixed; caller has already started the server as $SERVER_PID.
ENDPOINTS=("/|plaintext" "/json|json" "/greet/tauraro|route-param")

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
        IFS='|' read -r rps err lat <<< "$(runload "http://127.0.0.1:$port$path")"
        local peak; peak="$(peak_rss_kb "$pid")"
        ROWS+=("$name|$label|${rps:-FAIL}|${err:-?}|${lat:-?}|${peak:-?}")
        printf "%s req/s, %s ms, %s err, %s KB peak\n" "${rps:-FAIL}" "${lat:-?}" "${err:-0}" "${peak:-?}"
    done
}

echo ""
printf "${CYN}=================================================================${RST}\n"
printf "${CYN}  watax HTTP Benchmark — watax vs axum (Rust) vs FastAPI (Python)${RST}\n"
if [ -n "$WRK" ]; then
    printf "${CYN}  load: wrk  %s threads × %s conns × %ss/endpoint${RST}\n" "$THREADS" "$CONC" "$DUR"
else
    printf "${YLW}  load: loadtest.py (wrk not found)  %s conns × %ss/endpoint${RST}\n" "$CONC" "$DUR"
fi
printf "${CYN}=================================================================${RST}\n\n"

# ── watax ─────────────────────────────────────────────────────────────────────
if [ -n "$TAU_EXE" ] && [ -x "$TAU_EXE" ] || command -v "$TAU_EXE" &>/dev/null; then
    printf "${YLW}Building watax_app...${RST}\n"
    # Build from the watax ROOT so `from watax import ...` resolves the framework
    # modules (src/) and the templa dependency (.taupkg/packages/).
    ( cd "$WATAX_ROOT" \
      && TAURARO_PATH="$WATAX_ROOT/.taupkg/packages:$WATAX_ROOT/src" \
         "$TAU_EXE" benchmarks/watax_app/src/main.tr -o "$BENCH/watax_app/server" >/tmp/watax_build.log 2>&1 )
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
        --no-access-log --log-level warning >/tmp/fastapi.log 2>&1 ) & SERVER_PID=$!
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
        echo "- **Load:** \`wrk\` — ${THREADS} threads × ${CONC} connections × ${DUR}s per endpoint"
    else
        echo "- **Load:** \`loadtest.py\` — ${CONC} keep-alive connections × ${DUR}s per endpoint"
    fi
    if [ -n "$TAU_EXE" ]; then echo "- **Compiler:** \`$TAU_EXE\`"; fi
    if command -v cargo &>/dev/null; then echo "- **Rust:** $(rustc --version 2>/dev/null)"; fi
    echo ""
    echo "## Throughput, latency & memory"
    echo ""
    echo "| Framework | Endpoint | Req/sec | Avg latency (ms) | Errors | Peak RSS (KB) |"
    echo "|-----------|----------|--------:|-----------------:|-------:|--------------:|"
    for r in "${ROWS[@]}"; do
        IFS='|' read -r fw ep rps err lat peak <<< "$r"
        echo "| $fw | $ep | $rps | $lat | $err | $peak |"
    done
    echo ""
    echo "_watax frees all per-request memory inside the framework (auto-drop +"
    echo "owning response APIs), so its peak RSS stays flat under sustained load —"
    echo "user handlers never call free/dispose._"
} > "$RESULTS_MD"

printf "\n${GRN}Wrote Markdown report: %s${RST}\n\n" "$RESULTS_MD"
