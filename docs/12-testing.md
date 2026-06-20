# Testing

`TestClient` starts your app on a loopback port and lets you drive it with real
HTTP requests in-process — no external tools, no mocking the socket.

## Basic test

```tauraro
from watax import App, TestClient
from std.net.http_server import HttpConn

def home(c: HttpConn):
    c.send_text(200, "Hello, World!")

def build_app() -> App:
    mut app = App.new()
    app = app.get("/", home)
    return app

def main():
    mut client = TestClient.start(build_app(), 8199)   # boots the app on :8199

    mut resp = client.get("/")
    assert resp.status == 200
    assert resp.body == "Hello, World!"

    print("ok")
```

## The client API

| Method | Sends |
|--------|-------|
| `client.get(path)` | `GET` |
| `client.post(path, body)` | `POST` with a raw body |
| `client.post_json(path, body)` | `POST` with `Content-Type: application/json` |
| `client.put(path, body)` | `PUT` |
| `client.patch(path, body)` | `PATCH` |
| `client.delete(path)` | `DELETE` |

Each returns an `HttpClientResponse` with `status`, `body`, and headers.

## Testing a JSON endpoint

```tauraro
mut client = TestClient.start(build_app(), 8199)

mut r = client.post_json("/users", "{\"name\": \"Ada\"}")
assert r.status == 201
assert Str.contains(r.body, "\"name\":\"Ada\"")
```

## Testing middleware / auth

```tauraro
# Unauthenticated:
mut r1 = client.get("/admin")
assert r1.status == 401

# (Send headers/cookies by extending the client call as your app expects.)
```

## Best practices

- **One app builder, reused.** Put route wiring in a `build_app()` function so
  both `main()` and tests construct the same app.
- **Use a dedicated test port** (e.g. `8199`) distinct from your dev port.
- **Assert on `status` and `body`.** Check the contract, not internals.
- **Test the unhappy paths** too — `404`, `400`, `401`, `413` — not just `200`.
- **Pair with the leak benchmark.** For long-running endpoints, the
  [benchmarks](../benchmarks/) confirm memory stays flat under load; `TestClient`
  confirms correctness.

## When to use TestClient

Use `TestClient` for **integration tests** of routing, middleware, and handler
behavior end-to-end — it exercises the real parser, router, and response path.
For pure logic (parsers, formatters), unit-test the functions directly without
spinning up a server.
