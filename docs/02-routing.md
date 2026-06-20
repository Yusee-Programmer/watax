# Routing

A route maps an HTTP **method + path pattern** to a handler. watax matches
routes in registration order; the first match wins.

## Methods

```tauraro
mut app = App.new()
    .get("/posts", list_posts)
    .post("/posts", create_post)
    .put("/posts/:id", replace_post)
    .patch("/posts/:id", update_post)
    .delete("/posts/:id", delete_post)
    .route("OPTIONS", "/posts", preflight)   # any method, explicitly
```

Each method returns the app, so calls **chain** — either across lines as above,
or on one line: `App.new().get(...).post(...)`.

## Path parameters

A `:name` segment captures one path segment into `request.params`:

```tauraro
def show_user(c: HttpConn):
    mut id = c.request.get_param("id")     # "/users/42" -> "42"
    c.send_text(200, "user " + id)

mut app = App.new()
    .get("/users/:id", show_user)
    .get("/users/:id/posts/:slug", show_post)   # multiple params
```

`get_param` returns `""` for an absent parameter. Parse numbers with
`Str.parse_int`:

```tauraro
from std.string.str import Str
mut id = Str.parse_int(c.request.get_param("id"))
```

## Wildcards

A `*name` segment captures the **rest** of the path (useful for file servers
and catch-alls):

```tauraro
app = app.get("/files/*path", serve_file)   # "/files/a/b/c.txt" -> path = "a/b/c.txt"
```

> Static mounts (`app.static_dir`) already use a wildcard internally — prefer
> them for serving folders. See [Static files](07-static-files.md).

## Route groups & mounts

Group related routes under a shared prefix and middleware with a `Router`, then
`mount` it onto the app:

```tauraro
def api_routes() -> Router:
    return Router.init("/api")
        .use(cors_mw)                  # group-local middleware
        .get("/health", health)
        .get("/users/:id", api_user)

def main():
    mut app = App.new()
        .mount(api_routes())           # all routes get the /api prefix
        .get("/", home)
    app.listen_reactor_pool("127.0.0.1", 8080, 4)
```

`app.group("/api")` is a shorthand that returns a `Router` already prefixed.

### When to use groups

- **Perfect for**: versioned APIs (`/api/v1`, `/api/v2`), admin sections, or any
  set of routes that share a prefix *and* middleware (auth, CORS, rate limits).
- Keep top-level pages (`/`, `/about`) directly on the app; reserve groups for
  cohesive sub-trees.

## Custom 404 / errors

When no route matches, watax calls your error handler (status `404`), and you
can centralize error rendering:

```tauraro
def not_found(c: HttpConn, status: int):
    c.send_html(status, "<h1>" + status.to_str() + " — not here</h1>")

app = app.on_error(not_found)
```

The handler receives the would-be status code, so the same function can render
`404`, `405`, etc.

## Best practices

- **Order matters.** Register specific routes before catch-alls/wildcards.
- **One responsibility per handler.** Push cross-cutting concerns (auth,
  logging, CORS) into [middleware](05-middleware.md), not every handler.
- **Validate params early.** `get_param` never throws, but downstream parsing
  can — guard with `if Str.len(id) == 0:` and reply `400` when needed.
- **Group by concern, not by file.** Use `Router` + `mount` to keep an API
  module self-contained.

## When routing is perfect

Use watax routing whenever you have a fixed set of URL patterns — REST APIs,
server-rendered pages, file servers. For highly dynamic dispatch (e.g. routing
by header or content negotiation), do the branch inside a single handler.
