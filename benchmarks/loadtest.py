#!/usr/bin/env python3
"""Tiny HTTP load tester (no external deps): N concurrent workers hammer a
URL for `duration` seconds using persistent keep-alive connections, then
report requests/sec, average latency, and error count.

Usage: python loadtest.py <url> [concurrency] [duration_seconds]
"""
import http.client
import sys
import threading
import time
from urllib.parse import urlparse


def worker(host, port, path, duration, results, idx, keepalive):
    count = 0
    errors = 0
    total_latency = 0.0
    end = time.monotonic() + duration
    conn = http.client.HTTPConnection(host, port, timeout=5) if keepalive else None
    while time.monotonic() < end:
        start = time.monotonic()
        try:
            if not keepalive:
                conn = http.client.HTTPConnection(host, port, timeout=5)
            conn.request("GET", path)
            resp = conn.getresponse()
            resp.read()
            if resp.status != 200:
                errors += 1
        except Exception:
            errors += 1
            try:
                conn.close()
            except Exception:
                pass
            conn = http.client.HTTPConnection(host, port, timeout=5)
        else:
            total_latency += (time.monotonic() - start)
            count += 1
        finally:
            if not keepalive and conn is not None:
                conn.close()
    if conn is not None:
        conn.close()
    results[idx] = (count, errors, total_latency)


def main():
    url = sys.argv[1]
    concurrency = int(sys.argv[2]) if len(sys.argv) > 2 else 20
    duration = float(sys.argv[3]) if len(sys.argv) > 3 else 5.0
    keepalive = (sys.argv[4].lower() != "no-keepalive") if len(sys.argv) > 4 else True

    parsed = urlparse(url)
    host = parsed.hostname
    port = parsed.port or 80
    path = parsed.path or "/"

    results = [None] * concurrency
    threads = []
    t0 = time.monotonic()
    for i in range(concurrency):
        t = threading.Thread(target=worker, args=(host, port, path, duration, results, i, keepalive))
        threads.append(t)
        t.start()
    for t in threads:
        t.join()
    elapsed = time.monotonic() - t0

    total_count = sum(r[0] for r in results)
    total_errors = sum(r[1] for r in results)
    total_latency = sum(r[2] for r in results)

    rps = total_count / elapsed
    avg_latency_ms = (total_latency / total_count * 1000) if total_count else 0.0

    print(f"URL:          {url}")
    print(f"Keep-alive:   {keepalive}")
    print(f"Concurrency:  {concurrency}")
    print(f"Duration:     {elapsed:.2f}s")
    print(f"Requests:     {total_count}")
    print(f"Errors:       {total_errors}")
    print(f"Req/sec:      {rps:.1f}")
    print(f"Avg latency:  {avg_latency_ms:.3f} ms")


if __name__ == "__main__":
    main()
