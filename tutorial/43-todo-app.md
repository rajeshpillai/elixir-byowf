# Step 43: Todo App — Capstone Project

## What We're Building

A full-featured Todo application that showcases the Ignite framework features built across Steps 1–42. This is a capstone project that demonstrates real-world usage of LiveView, Streams, Ecto, FEEx templates, and more.

## Features

- **CRUD operations** — Create, read, update, delete todo items
- **Categories** — Organize todos by category with color coding
- **Subtasks** — Break down todos into smaller subtasks
- **User accounts** — Registration and login with hashed passwords
- **Real-time updates** — LiveView with `~F` (FEEx) templates
- **Stream-based lists** — Efficient rendering with LiveView Streams
- **Responsive UI** — Custom CSS with a Tailwind-inspired design system

## Framework Features Used

| Feature | Step | Usage in Todo App |
|---------|------|-------------------|
| LiveView | 12 | Real-time UI without page reloads |
| Streams | 25 | Efficient todo list rendering |
| Ecto | 30 | Database persistence with SQLite |
| FEEx `~F` | 42 | Clean template syntax with `@assigns` |
| Router | 3 | Route to the todo LiveView |
| Cowboy | 10 | HTTP server |

## Project Structure

```
examples/todo/
├── live/
│   ├── todo_live.ex       # Main LiveView (608 lines)
│   └── todo_html.ex       # HTML templates using ~F sigil
├── schemas/
│   ├── todo_item.ex       # Todo item schema + changeset
│   ├── category.ex        # Category schema
│   ├── subtask.ex         # Subtask schema
│   └── user.ex            # User schema with password hashing
assets/
└── todo.css               # Component CSS (Tailwind-inspired)
templates/
└── todo_live.html.eex     # Initial HTML template
priv/repo/migrations/
└── 20260306000001_create_todo_app_tables.exs
```

## Key Implementation Details

### Schemas

The app uses four Ecto schemas:

- `TodoItem` — title, description, priority, status, due date, belongs to user and category
- `Category` — name and color, has many todos
- `Subtask` — title and completed flag, belongs to todo item
- `User` — email and password hash with `Bcrypt`-style hashing

### LiveView

`TodoLive` handles all user interactions through LiveView events:

- `handle_event("add-todo", ...)` — Creates new todo items
- `handle_event("toggle-todo", ...)` — Toggles completion status
- `handle_event("delete-todo", ...)` — Removes todo items
- `handle_event("filter", ...)` — Filters by status/category

### FEEx Templates

`TodoHTML` uses the `~F` sigil from Step 42 for clean template syntax:

```elixir
def todo_item(assigns) do
  ~F"""
  <div class={"todo-item #{if @completed, do: "completed"}"}>
    <h3>#{@title}</h3>
    <span class="priority priority-#{@priority}">#{@priority}</span>
  </div>
  """
end
```

## File Checklist

| File | Status | Purpose |
|------|--------|---------|
| `examples/todo/live/todo_live.ex` | **New** | Main LiveView with all event handlers |
| `examples/todo/live/todo_html.ex` | **New** | FEEx template components |
| `examples/todo/schemas/*.ex` | **New** | Ecto schemas for todos, categories, subtasks, users |
| `assets/todo.css` | **New** | Complete CSS design system |
| `templates/todo_live.html.eex` | **New** | Initial HTML template |
| `priv/repo/migrations/...` | **New** | Database migration for all tables |
| `lib/my_app/router.ex` | **Modified** | Added `/todo` route |
| `lib/ignite/application.ex` | **Modified** | Added todo app supervision |

---

[← Previous: Step 42 - FEEx Templates](42-feex-templates.md) | [Next: Step 44 - LiveView Resilience →](44-liveview-resilience.md)
