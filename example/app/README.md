# watax-notes

A small but complete **reference / showcase application** for the **watax** web
framework — and a tour of Tauraro itself (classes, modules, refcounted strings
with automatic cleanup, no manual memory management in user code). It exercises
almost the entire watax feature surface in one realistic app.

## Project layout (modular)

The app is split into focused modules; `main.tr` is just the HTTP layer + wiring:

| File         | Responsibility                                                |
|--------------|---------------------------------------------------------------|
| `src/note.tr`  | the `Note` domain model (`to_html` / `write_json`)          |
| `src/store.tr` | in-memory note store + config (module-private state behind pub accessor functions) |
| `src/main.tr`  | route handlers + wiring                                     |

> The HTTP route handlers live in `main.tr` because they call watax's
> `extend HttpConn` helpers (`send_template`, `send_json_writer`, `abort`,
> `upgrade_websocket`, …). Domain/state logic that doesn't touch the connection
> is factored into `note.tr` / `store.tr`.

## Features demonstrated

- **Templates** — server-rendered HTML (`layout.html`, `index.html`,
  `about.html`, `404.html`) using templa's `{% extends %}` / `{% block %}`
  inheritance, filters (`| safe`), and context variables / lists.
- **Static assets** — served from `./static` via `static_dir("/static", …)`.
- **Middleware** — a *before* hook (`use`) that adds an `X-Powered-By` header,
  and an *after* hook (`use_after`) for request logging.
- **Cookies / session state** — a per-session visit counter (`set_cookie` +
  `request.cookie`).
- **Query strings** — `/?q=…` search filter (`request.query_param`).
- **HTML form CRUD** — create / toggle / delete over an in-memory list, with
  path params (`/notes/:id/…`) and POST-redirect-GET.
- **JSON REST API** under `/api` (CORS + rate-limited group):
  `GET/POST/PUT/DELETE /api/notes[/:id]`, parsing JSON request bodies
  (`request.json()`) and building responses with the streaming **JsonWriter**
  (`send_json_writer`) — no intermediate node tree.
- **Health check** — `/healthz` JSON via JsonWriter.
- **Chunked streaming** — `/notes.csv` exported with chunked transfer-encoding
  (`begin_chunked` / `write_chunk` / `end_chunked`).
- **Server-Sent Events** — `/events` (`begin_sse` / `send_event`).
- **WebSocket** (RFC 6455) — `/ws` echo + live note count (`upgrade_websocket`).
- **CORS** (`cors_mw`), **rate limiting** (`rate_limit_mw`, returns `429`),
  **centralized 404/5xx** (`on_error`), **route groups** (`group` / `mount`),
  **redirects**, **`abort`**, and **config from the environment**
  (`Config.from_env`).

## Building and running

The dependencies (`watax`, `templa`) are vendored under `.taupkg/packages/`.
`taupkg build` wires up `TAURARO_PATH` automatically; to build by hand with
`tauraroc`, just put the **packages root** on `TAURARO_PATH` — the resolver
discovers each package's index module and `src/` directory from there (so both
the package root *and* explicit `…/<pkg>/src` dirs work). The path separator is
`:` on Linux/macOS and `;` on Windows.

```sh
cd watax/example/app

# package root is enough — sibling modules + extends resolve automatically:
TAURARO_PATH="$PWD/.taupkg/packages" tauraroc src/main.tr -o watax_notes.exe

./watax_notes.exe        # listens on http://127.0.0.1:8080
```

## Configuration

All settings are optional and read from the environment:

| Variable               | Default       | Purpose                          |
|-------------------------|---------------|-----------------------------------|
| `WATAX_HOST`            | `127.0.0.1`   | Bind address                      |
| `WATAX_PORT`            | `8080`        | Bind port                         |
| `WATAX_CORS_ORIGIN`     | `*`           | `Access-Control-Allow-Origin` for `/api/*` |

```sh
WATAX_PORT=9000 WATAX_CORS_ORIGIN=https://example.com ./watax_notes.exe
```

## Routes

| Method | Path                  | Description                                  |
|--------|-----------------------|----------------------------------------------|
| GET    | `/`                   | Notes list (HTML) + `?q=` search + visit cookie |
| GET    | `/about`              | About page (template context)                |
| GET    | `/healthz`            | Health JSON (JsonWriter)                      |
| GET    | `/notes.csv`          | Notes as CSV (chunked streaming)             |
| GET    | `/events`             | Server-Sent Events (live note count)         |
| GET    | `/ws`                 | WebSocket echo + live note count             |
| POST   | `/notes`              | Create a note (form: `title`, `body`)        |
| POST   | `/notes/:id/toggle`   | Toggle a note's done state                   |
| POST   | `/notes/:id/delete`   | Delete a note                                |
| GET    | `/api/notes`          | List notes as JSON (CORS, rate-limited)      |
| GET    | `/api/notes/:id`      | One note as JSON                             |
| POST   | `/api/notes`          | Create from a JSON body                      |
| PUT    | `/api/notes/:id`      | Update from a JSON body                      |
| DELETE | `/api/notes/:id`      | Delete a note                                |
| GET    | `/static/*`           | Static CSS/JS assets                         |
| *      | (anything else)       | `404.html`                                   |
