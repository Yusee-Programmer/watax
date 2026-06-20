# WebSockets

watax implements RFC 6455 WebSockets. A handler upgrades the HTTP connection to
a `WsConn`, then reads and writes text frames over the live channel.

## Upgrading

```tauraro
from watax import WsConn

def chat(c: HttpConn):
    mut ws = c.upgrade_websocket()       # performs the handshake
    while ws.is_open():
        mut msg = ws.recv_text()         # blocks for the next text frame
        if Str.len(msg) == 0:
            break                        # peer closed
        ws.send_text("echo: " + msg)
    ws.send_close()

def main():
    mut app = App.new()
    app = app.get("/ws", chat)
    app.listen_reactor_pool("127.0.0.1", 8080, 4)
```

## `WsConn` API

| Method | Purpose |
|--------|---------|
| `c.upgrade_websocket()` | handshake an `HttpConn` into a `WsConn` |
| `ws.is_open()` | whether the channel is still open |
| `ws.recv_text()` | read the next text message (`""` on close) |
| `ws.send_text(msg)` | send a text frame |
| `ws.send_close()` | send a close frame and end the connection |

## A broadcast/echo loop

```tauraro
def echo(c: HttpConn):
    mut ws = c.upgrade_websocket()
    while ws.is_open():
        mut m = ws.recv_text()
        if Str.len(m) == 0: break
        ws.send_text(m)
    ws.send_close()
```

## Best practices

- **Always loop on `is_open()`** and break when `recv_text()` returns `""`
  (the peer closed) to avoid spinning.
- **Send a close frame** (`send_close()`) when you're done so the client sees a
  clean shutdown.
- **Keep per-connection state local** to the handler; a WebSocket handler owns
  its connection for its whole lifetime.
- **Validate/limit messages.** Don't echo or store unbounded client input.
- **Use a connection-friendly server.** Long-lived WebSocket connections pair
  well with the reactor servers; see [Servers](10-servers.md).

## When WebSockets are perfect

Reach for WebSockets when you need **bidirectional, low-latency** messaging:
chat, multiplayer, collaborative editing, live trading, interactive dashboards.

If the server only needs to **push** to the browser (and the client never sends
back over the same channel), prefer
[Server-Sent Events](04-responses.md#server-sent-events-sse) — they're simpler,
ride normal HTTP, and reconnect automatically.
