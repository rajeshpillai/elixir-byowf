# Step 7: EEx Template Engine

## What We're Building

Instead of returning plain text, we want controllers to render full HTML
pages with dynamic content:

```elixir
def show(conn) do
  render(conn, "profile", name: "Rajesh", id: conn.params[:id])
end
```

This renders `templates/profile.html.eex` — an HTML file with embedded
Elixir code. The result is a complete HTML page sent to the browser.

## Concepts You'll Learn

### EEx (Embedded Elixir)

EEx is part of Elixir's **standard library** — no dependencies needed!
It lets you embed Elixir expressions inside any text file using special tags:

```html
<h1>Hello, <%= @name %>!</h1>
<p>2 + 2 = <%= 2 + 2 %></p>
```

The tags:
- `<%= expr %>` — evaluate `expr` and insert the result into the output
- `<% expr %>` — evaluate `expr` but don't insert (for control flow)

### EEx.eval_file/2

This function reads a `.eex` file, evaluates the Elixir expressions inside
it, and returns the resulting string:

```elixir
EEx.eval_file("templates/profile.html.eex", assigns: %{name: "Rajesh"})
#=> "<!DOCTYPE html>\n<html>...<h1>Rajesh</h1>..."
```

The second argument is a **binding** — a keyword list of variables available
inside the template. We pass `assigns: %{...}` so the template can use
`@name`, `@id`, etc. The `@` is an EEx shortcut that expands `@name` to
`assigns[:name]`.

### Keyword Lists

A keyword list is a list of `{key, value}` tuples where keys are atoms:

```elixir
[name: "Rajesh", id: 42]
# Same as:
[{:name, "Rajesh"}, {:id, 42}]
```

We convert keyword lists to maps with `Enum.into/2`:

```elixir
[name: "Rajesh", id: 42] |> Enum.into(%{})
#=> %{name: "Rajesh", id: 42}
```

### Default Arguments (`\\\\`)

Elixir uses `\\\\` to set default parameter values:

```elixir
def render(conn, template_name, assigns \\ []) do
```

This means you can call `render` two ways:
- `render(conn, "profile", name: "Rajesh")` — passes assigns
- `render(conn, "profile")` — assigns defaults to `[]`

Under the hood, Elixir generates two function clauses: a 2-arity one
that calls the 3-arity one with the default value.

### Path.join/2

Builds file paths safely across operating systems:

```elixir
Path.join("templates", "profile.html.eex")
#=> "templates/profile.html.eex"
```

## The Code

### Updated `lib/ignite/controller.ex`

New `render/3` function:

```elixir
def render(conn, template_name, assigns \\ []) do
  template_path = Path.join("templates", "#{template_name}.html.eex")
  content = EEx.eval_file(template_path, assigns: Enum.into(assigns, %{}))
  html(conn, content)
end
```

The flow:
1. Build the file path from the template name
2. Evaluate the EEx file with the assigns
3. Pass the resulting HTML to `html/2` (which sets content-type and status)

### `templates/profile.html.eex`

A simple HTML page that uses assigns:

```html
<h1>User Profile</h1>
<p><strong>Name:</strong> <%= @name %></p>
<p><strong>ID:</strong> <%= @id %></p>
<p><strong>Email:</strong> <%= @email %></p>
<p><strong>Server Time:</strong> <%= DateTime.utc_now() %></p>
```

The `@name` syntax is EEx's built-in shortcut — it expands to `assigns[:name]`.
This is the same syntax Phoenix uses in its templates.

### Updated UserController

```elixir
def show(conn) do
  user_id = conn.params[:id]
  render(conn, "profile", name: "Elixir Enthusiast", id: user_id, email: "N/A")
end
```

Clean and readable — the controller doesn't know anything about HTML.

## How It Works

```
Controller                          EEx Engine
    |                                   |
    | render(conn, "profile",           |
    |   name: "Rajesh", id: 42)        |
    |---------------------------------->|
    |                                   | Read templates/profile.html.eex
    |                                   | Replace <%= @name %> → "Rajesh"
    |                                   | Replace <%= @id %> → "42"
    |   "<html>...<h1>Rajesh</h1>..."   |
    |<----------------------------------|
    |                                   |
    | html(conn, content)               |
    | → %Conn{resp_body: "<html>..."}   |
```

## Try It Out

1. Start the server (it starts automatically with `iex -S mix`)

2. Visit http://localhost:4000/users/42

You should see a styled HTML page with:
- Name: Elixir Enthusiast
- ID: 42
- The current server time

3. Right-click → "View Page Source" to see the full HTML that was generated.

4. Visit http://localhost:4000/users/99 — same page, but ID shows 99.

## What's Next

We can now route requests and render HTML, but there's no way to run
code **before** every request — like logging or authentication.

In **Step 8**, we'll build a **Middleware Pipeline** (Plugs). You'll
write `plug :log_request` in your router, and every request will be
logged automatically. If an auth plug fails, it can halt the pipeline
before the controller even runs.
