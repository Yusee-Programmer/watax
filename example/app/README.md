# watax-notes

A small but complete reference application for the **watax** web framework.
It demonstrates a realistic project layout: server-rendered HTML via
[templa](../../../templa) templates with a shared layout, static CSS/JS
assets, form-based CRUD, a JSON API, middleware, centralized error handling,
and configuration via environment variables.

## Features demonstrated

- Server-rendered HTML pages (`templates/layout.html`, `index.html`,
  `about.html`, `404.html`) using templa's `{% extends %}` / `{% block %}`
  template inheritance.
- Static assets served from `./static` (`/static/css/style.css`,
  `/static/js/app.js`).
- Form-based CRUD over an in-memory note list (`POST /notes`,
  `POST /notes/:id/toggle`, `POST /notes/:id/delete`).
- A JSON API under `/api/notes`, guarded by CORS middleware
  (`app.group("/api")` + `cors_mw`).
- Centralized 404 handling via `app.on_error(...)`.
- Request logging via `request_logger_after`.
- Configuration from environment variables via `Config.from_env()`.

## Building and running

This example lives inside the `watax` project tree and uses watax/templa
directly from source via `TAURARO_PATH` (no `taupkg` package step needed):

```sh
cd watax/example/app

TAURARO_PATH="<path-to>/watax/src;<path-to>/tauProject" \
    tauraroc src/main.tr -o watax_notes.exe

./watax_notes.exe
```

`<path-to>/tauProject` should be the parent directory that contains both
`watax/` and `templa/` (so `from templa import ...` resolves).

## Configuration

All settings are optional and read from the environment:

| Variable               | Default       | Purpose                          |
|-------------------------|---------------|-----------------------------------|
| `WATAX_HOST`            | `127.0.0.1`   | Bind address                      |
| `WATAX_PORT`            | `8080`        | Bind port                         |
| `WATAX_STATIC_DIR`      | `./public`    | (unused here; app serves `./static` directly) |
| `WATAX_CORS_ORIGIN`     | `*`           | `Access-Control-Allow-Origin` for `/api/*` |
| `WATAX_RATE_LIMIT`      | `0` (off)     | Requests per window before `429`  |
| `WATAX_RATE_WINDOW_MS`  | `60000`       | Rate-limit window size            |

```sh
WATAX_PORT=9000 WATAX_CORS_ORIGIN=https://example.com ./watax_notes.exe
```

## Routes

| Method | Path                    | Description                         |
|--------|-------------------------|--------------------------------------|
| GET    | `/`                     | Notes list (HTML)                    |
| GET    | `/about`                | About page (HTML)                    |
| POST   | `/notes`                | Create a note (form: `title`, `body`)|
| POST   | `/notes/:id/toggle`     | Toggle a note's done state           |
| POST   | `/notes/:id/delete`     | Delete a note                        |
| GET    | `/api/notes`            | All notes as JSON (CORS-enabled)     |
| GET    | `/static/*`             | Static CSS/JS assets                 |
| *      | (anything else)         | `404.html`                           |
