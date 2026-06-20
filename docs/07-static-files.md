# Static files & uploads

## Serving a folder — `static_dir`

Mount a directory at a URL prefix and watax serves its files with the right
`Content-Type`:

```tauraro
app = app.static_dir("/static", "./public")
# GET /static/app.css   -> ./public/app.css
# GET /static/img/logo.png -> ./public/img/logo.png
```

Content types are detected from the extension (`content_type_for`) — CSS, JS,
PNG, SVG, JSON, HTML, fonts, etc. Paths are validated to prevent directory
traversal (`../`).

**Perfect for**: CSS/JS/images for server-rendered apps, and small static sites.

## Fine-grained mounts — `StaticMount`

For control over caching and SPA fallback, build a `StaticMount` and use
`serve_static`:

```tauraro
from watax import StaticMount, serve_static

mut mount = StaticMount.init("/app", "./dist")
mount = mount.with_max_age(3600)             # Cache-Control: max-age=3600
mount = mount.with_not_found("index.html")   # SPA fallback: serve index.html for unknown paths

def assets(c: HttpConn):
    if not serve_static(mount, c.request.path, c):
        c.send_status(404)
```

- `with_max_age(seconds)` — sets `Cache-Control` so browsers cache assets.
- `with_not_found(file)` — when a path doesn't resolve to a file, serve this
  file instead of 404. **Perfect for** single-page apps where the client router
  owns the path (`/app/anything` → `index.html`).

## Best practices (static)

- **Long-cache fingerprinted assets.** If your build emits `app.abc123.js`, set
  a large `max-age`; the hash busts the cache on change.
- **Keep the static root minimal.** Mount only the folder you intend to expose.
- **Use `with_not_found("index.html")`** for SPAs; omit it for plain file
  servers so missing files correctly 404.
- **Put a CDN/reverse proxy in front** in production for very high static load;
  watax serves assets fine, but edge caching is cheaper at scale.

## When static serving is perfect

Use `static_dir` for the assets of a server-rendered app, and `StaticMount` +
`with_not_found` to host a built SPA from the same origin as its API. For a
pure asset host at massive scale, front it with a CDN.

---

## Uploads — multipart/form-data

When a browser submits a `<form enctype="multipart/form-data">` (file uploads),
parse it with `request.multipart()`:

```tauraro
def upload(c: HttpConn):
    if not c.request.is_multipart():
        c.abort(415, "expected multipart/form-data")
        return
    mut form = c.request.multipart()

    # A text field:
    mut title = form.field("title")

    # A file part:
    mut file = form.get("avatar")
    if file.is_file():
        file.save("./uploads/" + file.filename)

    form.dispose()                 # free the parsed form when done
    c.send_text(200, "uploaded " + title)
```

### `MultipartForm`

| Method | Returns |
|--------|---------|
| `form.get(name)` | the `MultipartPart` for `name` |
| `form.field(name)` | a plain text field's value (`""` if absent) |
| `form.has(name)` | whether a part exists |
| `form.len()` | number of parts |
| `form.dispose()` | free the form (call when done) |

### `MultipartPart`

| Member | Meaning |
|--------|---------|
| `part.name` | form field name |
| `part.filename` | uploaded filename (empty for non-file fields) |
| `part.content_type` | the part's content type |
| `part.is_file()` | true when it's a file upload |
| `part.save(path)` | write the file's bytes to `path` |

### Best practices (uploads)

- **Set a `body_limit`.** Uploads are the easiest way to exhaust memory —
  `app = app.body_limit(10485760)` (10 MiB) and reply `413` on `oversized`.
- **Validate `content_type` / extension** before trusting a file.
- **Never use the client filename verbatim** as a path — sanitize it (strip
  `/`, `..`) before `save`.
- **`form.dispose()` when done.** The parsed form owns heap buffers; dispose it
  to free them (this is request-parsing state, not a framework-owned response).

### When uploads are perfect

Use multipart parsing for HTML file-upload forms and API clients that send
`multipart/form-data`. For large media at scale, consider streaming the body
or uploading directly to object storage.
