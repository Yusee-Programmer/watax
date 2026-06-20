import html
import random

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, PlainTextResponse

app = FastAPI()

# In-memory "World"/"Fortune" data (TechEmpower-style; no real database).
random.seed(20260620)
WORLDS = [random.randint(1, 10000) for _ in range(10000)]
FORTUNES = [
    "fortune: No such file or directory",
    "A computer scientist is someone who fixes things that aren't broken.",
    "After enough decimal places, nobody gives a damn.",
    '<script>alert("This should not be displayed in a browser alert box.");</script>',
    "フレームワークのベンチマーク",
]


@app.get("/", response_class=PlainTextResponse)
def root():
    return "Hello, World!"


@app.get("/json")
def json_endpoint():
    return {"message": "Hello, World!", "id": 1, "ok": True}


@app.get("/greet/{name}")
def greet(name: str):
    # Path-parameter route: GET /greet/:name -> {"hello": <name>}
    return {"hello": name}


@app.get("/users")
def users():
    # Larger JSON payload: a 20-element array of small objects.
    return [{"id": i, "name": "user", "active": True} for i in range(20)]


def _world(i):
    return {"id": i, "randomNumber": WORLDS[i - 1]}


@app.get("/db")
def db():
    # TechEmpower: single query.
    return _world(random.randint(1, 10000))


@app.get("/queries")
def queries(queries: int = 1):
    # TechEmpower: multiple queries (?queries=N, clamped 1..500).
    n = max(1, min(500, queries))
    return [_world(random.randint(1, 10000)) for _ in range(n)]


@app.get("/updates")
def updates(queries: int = 1):
    # TechEmpower: updates — read N rows, assign new values, return them.
    n = max(1, min(500, queries))
    out = []
    for _ in range(n):
        i = random.randint(1, 10000)
        WORLDS[i - 1] = random.randint(1, 10000)
        out.append(_world(i))
    return out


@app.get("/fortunes", response_class=HTMLResponse)
def fortunes():
    # TechEmpower: fortunes — HTML table, one row added at request time, escaped.
    rows = list(enumerate(FORTUNES, start=1)) + [(0, "Additional fortune added at request time.")]
    rows.sort(key=lambda r: r[1])
    body = '<!DOCTYPE html><html><head><title>Fortunes</title></head><body><table><tr><th>id</th><th>message</th></tr>'
    for rid, msg in rows:
        body += f"<tr><td>{rid}</td><td>{html.escape(msg)}</td></tr>"
    body += "</table></body></html>"
    return body


@app.get("/plaintext-big", response_class=PlainTextResponse)
def plaintext_big():
    return "The quick brown fox jumps over the lazy dog. " * 256
