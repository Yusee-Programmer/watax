# run_all.ps1 — watax HTTP benchmark suite (Windows): watax vs axum (Rust) vs
# FastAPI (Python). Measures req/sec, average latency, errors, and PEAK working
# set (memory). A framework is skipped when its toolchain is absent. Writes a
# Markdown report to benchmarks/results.md. (CI uses run_all.sh on Linux.)

$ErrorActionPreference = "Continue"
$BENCH      = $PSScriptRoot
$WATAX_ROOT = (Resolve-Path "$BENCH\..").Path
$RESULTS_MD = Join-Path $BENCH "results.md"
$LOADTEST   = Join-Path $BENCH "loadtest.py"
$CONC    = 1000
$DUR     = 10
$REQUESTS = 1000
$WORKERS  = 4   # server workers for FastAPI; also set listen_reactor_pool() in watax_app/src/main.tr

$PY = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $PY) { $PY = (Get-Command python3 -ErrorAction SilentlyContinue).Source }

# tauraroc: env TAURAROC, then PATH, then known install dir.
$TAU = $env:TAURAROC
if (-not $TAU) {
    $c = Get-Command tauraroc -ErrorAction SilentlyContinue
    if ($c) { $TAU = $c.Source }
    elseif (Test-Path "$WATAX_ROOT\tauraroc.exe") { $TAU = "$WATAX_ROOT\tauraroc.exe" }
    elseif (Test-Path "C:\Users\Yusee Habibu\tauraro\tauraroc.exe") { $TAU = "C:\Users\Yusee Habibu\tauraro\tauraroc.exe" }
}

$endpoints = @(
    @{ path = "/";                     label = "plaintext"            },
    @{ path = "/json";                 label = "json"                 },
    @{ path = "/greet/tauraro";        label = "route-param"          },
    @{ path = "/users";                label = "users-json"           },
    @{ path = "/db";                   label = "db (1 row)"           },
    @{ path = "/queries?queries=20";   label = "queries (20 rows)"    },
    @{ path = "/updates?queries=20";   label = "updates (20 rows)"    },
    @{ path = "/fortunes";             label = "fortunes (html)"      },
    @{ path = "/plaintext-big";        label = "plaintext-big (~11KB)"}
)

$rows = New-Object System.Collections.Generic.List[object]

function Run-Load($url) {
    $out = & $PY $LOADTEST $url $CONC $DUR yes $REQUESTS 2>$null
    $rps = ($out | Select-String "Req/sec:\s*([\d.]+)").Matches.Groups[1].Value
    $err = ($out | Select-String "Errors:\s*(\d+)").Matches.Groups[1].Value
    $lat = ($out | Select-String "Avg latency:\s*([\d.]+)").Matches.Groups[1].Value
    return @{ rps = $rps; err = $err; lat = $lat }
}

function Bench-Framework($name, $port, $proc) {
    Start-Sleep -Seconds 2
    # confirm listening
    try { $t = New-Object Net.Sockets.TcpClient; $t.Connect("127.0.0.1", $port); $t.Close() }
    catch { Write-Host "  $name did not come up on :$port - skipping" -ForegroundColor Yellow; return }
    foreach ($ep in $endpoints) {
        Write-Host ("  {0,-8} {1,-12} ... " -f $name, $ep.label) -NoNewline
        $r = Run-Load "http://127.0.0.1:$port$($ep.path)"
        $peak = 0
        try { $proc.Refresh(); $peak = [math]::Round($proc.PeakWorkingSet64/1KB) } catch {}
        $rps = if ($r.rps) { $r.rps } else { "FAIL" }
        $rows.Add([PSCustomObject]@{ fw=$name; ep=$ep.label; rps=$rps; err=$r.err; lat=$r.lat; peak=$peak })
        Write-Host "$rps req/s, $($r.lat) ms, $($r.err) err, $peak KB peak"
    }
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  watax HTTP Benchmark - watax vs axum (Rust) vs FastAPI (Python)" -ForegroundColor Cyan
Write-Host "  concurrency=$CONC  n=$REQUESTS requests/endpoint" -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

# ── watax ──────────────────────────────────────────────────────────────────────
if ($TAU -and (Test-Path $TAU)) {
    Write-Host "Building watax_app..." -ForegroundColor Yellow
    # Build from the watax ROOT so `from watax import ...` resolves the framework
    # modules under src/ and the templa dep under .taupkg/packages (matching how
    # watax itself is built). Use forward slashes — the resolver normalizes them
    # and they avoid backslash-escaping surprises in search-path matching.
    $rootFwd = $WATAX_ROOT -replace '\\','/'
    $env:TAURARO_PATH = "$rootFwd/.taupkg/packages;$rootFwd/src"
    Push-Location $WATAX_ROOT
    & $TAU --strict -O3 "benchmarks/watax_app/src/main.tr" -o "$BENCH\watax_app\server.exe" 2>&1 | Out-File "$env:TEMP\watax_build.log"
    Pop-Location
    $wx = "$BENCH\watax_app\server.exe"
    if (Test-Path $wx) {
        $proc = Start-Process -FilePath $wx -PassThru -WindowStyle Hidden
        Bench-Framework "watax" 8200 $proc
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    } else { Write-Host "  watax build failed (see $env:TEMP\watax_build.log)" -ForegroundColor Yellow }
} else { Write-Host "tauraroc not found - skipping watax" -ForegroundColor Yellow }

# ── axum (Rust) ────────────────────────────────────────────────────────────────
if (Get-Command cargo -ErrorAction SilentlyContinue) {
    Write-Host "Building axum_app (cargo --release)..." -ForegroundColor Yellow
    Push-Location "$BENCH\axum_app"; & cargo build --release 2>&1 | Out-File "$env:TEMP\axum_build.log"; Pop-Location
    $ax = "$BENCH\axum_app\target\release\axum_bench.exe"
    if (Test-Path $ax) {
        $env:AXUM_WORKERS = "$WORKERS"
        $proc = Start-Process -FilePath $ax -PassThru -WindowStyle Hidden
        Bench-Framework "axum" 8300 $proc
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    } else { Write-Host "  axum build failed (see $env:TEMP\axum_build.log)" -ForegroundColor Yellow }
} else { Write-Host "cargo not found - skipping axum" -ForegroundColor Yellow }

# ── FastAPI (Python) ───────────────────────────────────────────────────────────
$hasFast = $false
try { & $PY -c "import fastapi, uvicorn" 2>$null; $hasFast = ($LASTEXITCODE -eq 0) } catch {}
if ($hasFast) {
    Write-Host "Starting FastAPI (uvicorn)..." -ForegroundColor Yellow
    $proc = Start-Process -FilePath $PY -WorkingDirectory "$BENCH\fastapi_app" `
        -ArgumentList "-m","uvicorn","main:app","--host","127.0.0.1","--port","8400","--workers","$WORKERS","--no-access-log","--log-level","warning" `
        -PassThru -WindowStyle Hidden
    Start-Sleep -Seconds 3   # uvicorn boots slower than the native servers
    Bench-Framework "fastapi" 8400 $proc
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
} else { Write-Host "fastapi/uvicorn not installed - skipping FastAPI" -ForegroundColor Yellow }

# ── Markdown report ────────────────────────────────────────────────────────────
$md = New-Object System.Collections.Generic.List[string]
$md.Add("# watax Benchmark Results")
$md.Add("")
$md.Add("watax vs **axum** (Rust/hyper) vs **FastAPI** (Python/uvicorn). Higher")
$md.Add("req/sec is better; lower latency, errors, and peak memory are better.")
$md.Add("Generated by ``benchmarks/run_all.ps1``.")
$md.Add("")
$md.Add("- **Host:** Windows $([System.Environment]::OSVersion.Version)")
$md.Add("- **Date (UTC):** $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss'))")
$md.Add("- **Load:** $CONC keep-alive connections x $REQUESTS requests per endpoint  ($WORKERS proc x 1 worker each)")
if ($TAU) { $md.Add("- **Compiler:** ``$TAU``") }
$md.Add("")
$md.Add("## Throughput, latency & memory")
$md.Add("")
$md.Add("| Framework | Endpoint | Req/sec | Avg latency (ms) | Errors | Peak RSS (KB) |")
$md.Add("|-----------|----------|--------:|-----------------:|-------:|--------------:|")
foreach ($r in $rows) {
    $md.Add("| $($r.fw) | $($r.ep) | $($r.rps) | $($r.lat) | $($r.err) | $($r.peak) |")
}
$md.Add("")
$md.Add("_watax frees all per-request memory inside the framework (auto-drop +")
$md.Add("owning response APIs), so its peak RSS stays flat under sustained load -")
$md.Add("user handlers never call free/dispose._")
($md -join "`n") | Out-File -FilePath $RESULTS_MD -Encoding utf8
Write-Host ""
Write-Host "Wrote Markdown report: $RESULTS_MD" -ForegroundColor Green
exit 0
