# Templates

watax renders server-side HTML with [templa](https://github.com/Yusee-Programmer/templa),
a Jinja-style engine: `{{ variables }}`, `{% blocks %}`, `{% for %}` / `{% if %}`,
template inheritance, and filters.

## Inline templates

```tauraro
from templa import Context

def hello(c: HttpConn):
    mut ctx = Context.init()
    ctx.set("name", "Ada")
    c.send_template_string(200, "<h1>Hello, {{ name }}!</h1>", ctx)
```

**Perfect for**: tiny fragments, emails, one-off snippets.

## File templates

```tauraro
def profile(c: HttpConn):
    mut ctx = Context.init()
    ctx.set("name", "Ada")
    ctx.set("bio", "Builds compilers.")
    c.send_template(200, "templates/profile.html", ctx)
```

```html
<!-- templates/profile.html -->
<h1>{{ name }}</h1>
<p>{{ bio }}</p>
```

**Perfect for**: real pages — anything beyond a couple of lines of HTML.

## The Context

`Context` is the variable bag passed to a template:

```tauraro
mut ctx = Context.init()
ctx.set("title", "Dashboard")
ctx.set("count", "3")          # values are strings; format before setting
```

Build it from request data, then render:

```tauraro
def search(c: HttpConn):
    mut ctx = Context.init()
    ctx.set("q", c.request.query_param("q"))
    c.send_template(200, "templates/results.html", ctx)
```

## Layouts & inheritance

templa supports `{% extends %}` / `{% block %}` so pages share a layout:

```html
<!-- templates/base.html -->
<!doctype html>
<html><head><title>{% block title %}watax{% endblock %}</title></head>
<body>
  <header>My Site</header>
  {% block content %}{% endblock %}
</body></html>
```

```html
<!-- templates/page.html -->
{% extends "base.html" %}
{% block title %}Home{% endblock %}
{% block content %}<h1>Welcome</h1>{% endblock %}
```

```tauraro
c.send_template(200, "templates/page.html", ctx)
```

**Perfect for**: multi-page apps with a shared shell (nav, footer, head).

## Loops, conditionals, filters

```html
<ul>
{% for item in items %}
  <li>{{ item | upper }}</li>
{% endfor %}
</ul>
{% if logged_in %}<a href="/logout">Log out</a>{% endif %}
```

(Filters and tags follow templa's syntax — see the templa docs for the full set.)

## Escaping & safety

Always HTML-escape untrusted values before they reach the page. watax exposes
`html_escape` for when you build HTML by hand:

```tauraro
from watax import html_escape
mut safe = html_escape(c.request.query_param("name"))
```

Inside templates, prefer letting the template engine handle escaping over
concatenating raw strings in your handler.

## Best practices

- **Keep logic out of templates.** Compute in the handler, pass finished values
  via `Context`; templates should only present.
- **Use a base layout** with `{% extends %}` to avoid repeating `<head>`/nav.
- **Escape untrusted input** (`html_escape`) to prevent XSS.
- **One `Context` per request**, built from that request's data.

## When templates are perfect

Use templates for **server-rendered HTML**: marketing pages, dashboards, admin
panels, forms, anything where the server produces the markup. For pure JSON
APIs consumed by a separate frontend, skip templates and use
[`send_json_value`](04-responses.md#json--two-ways).
