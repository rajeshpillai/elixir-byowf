# Step 30: Ecto Integration (Database Persistence)

## What We're Building

Real database persistence for our User resource. Currently all five CRUD actions in `UserController` return hardcoded or echo data. After this step, they read from and write to a SQLite database using Ecto — Elixir's database library.

## The Problem

Our framework has routing, controllers, templates, flash messages, and sessions — but no data layer. Every time you restart the server, nothing persists because data only exists in function return values. A real web app needs a database.

## How Phoenix Does It

Phoenix uses Ecto with PostgreSQL by default. Ecto has three key concepts:

- **Repo** — the connection to the database (`MyApp.Repo.all(User)`)
- **Schema** — maps an Elixir struct to a database table (`%User{}` ↔ `users` table)
- **Changeset** — validates and tracks changes before writing (`User.changeset(user, attrs)`)

We follow the exact same pattern. The only difference: we use SQLite instead of PostgreSQL for zero-infrastructure setup. To switch databases later, you change one line (the adapter) and update the config.

## Design Decision: SQLite

| Option | Pros | Cons |
|--------|------|------|
| **SQLite** | Zero setup, single file, no server needed | Single-writer, no multi-node |
| PostgreSQL | Full-featured, concurrent writes, production standard | Requires installing & running a server |

For a tutorial and small-to-medium apps, SQLite is perfect. The `ecto_sqlite3` adapter supports WAL mode for concurrent reads. To switch to Postgres later: change the adapter, swap `ecto_sqlite3` for `postgrex`, and update the config with connection details.

## Concepts You'll Learn

### `import Config` and the config system

```elixir
# config/config.exs
import Config

config :ignite, Ignite.Repo,
  database: "ignite.db"
```

`config/config.exs` is a special file that Mix reads at compile time. `import Config` brings in the `config/2` and `config/3` macros. `config :app_name, key, value` stores settings that you read at runtime with `Application.get_env(:app_name, key)`. This is how we tell Ecto where to find the database.

## Implementation

### 1. Dependencies

**Update `mix.exs`** — add `ecto_sql` and `ecto_sqlite3` to the `deps` function:

```elixir
defp deps do
  [
    {:plug_cowboy, "~> 2.7"},
    {:jason, "~> 1.4"},
    {:ecto_sql, "~> 3.12"},       # SQL query builder, migrations, repo
    {:ecto_sqlite3, "~> 0.17"}    # SQLite3 adapter for Ecto
  ]
end
```

`ecto_sql` provides the core infrastructure (Repo, migrations, query DSL). `ecto_sqlite3` is the adapter that talks to SQLite via `exqlite` (a NIF binding to SQLite3).

### 2. Configuration

**Create `config/config.exs`:**

```elixir
# config/config.exs
import Config

config :ignite, MyApp.Repo,
  database: "ignite_dev.db",
  pool_size: 5

config :ignite,
  ecto_repos: [MyApp.Repo]
```

SQLite only needs a file path — no hostname, port, username, or password. The `ecto_repos` key tells `mix ecto.create` and `mix ecto.migrate` which repos to manage.

### 3. The Repo

**Create `lib/my_app/repo.ex`:**

```elixir
# lib/my_app/repo.ex
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :ignite,
    adapter: Ecto.Adapters.SQLite3
end
```

`use Ecto.Repo` generates all the query functions: `all/1`, `get/2`, `insert/1`, `update/1`, `delete/1`, etc. The `otp_app: :ignite` tells Ecto to read config from `Application.get_env(:ignite, MyApp.Repo)`.

### 4. The User Schema & Changeset

**Create `lib/my_app/schemas/user.ex`:**

```elixir
# lib/my_app/schemas/user.ex
defmodule MyApp.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :email, :string
    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email])
    |> validate_required([:username])
    |> validate_length(:username, min: 2, max: 50)
    |> unique_constraint(:username)
  end
end
```

**Schema**: Maps `%MyApp.User{}` to the `users` table. `timestamps()` adds `inserted_at` and `updated_at` fields.

**Changeset**: The validation pipeline. `cast/3` picks allowed fields from input. `validate_required/2` ensures username is present. `validate_length/3` enforces bounds. `unique_constraint/2` converts a database uniqueness violation into a friendly error message (requires the matching unique index in the migration).

### 5. The Migration

**Create `priv/repo/migrations/20260304000001_create_users.exs`:**

```elixir
# priv/repo/migrations/20260304000001_create_users.exs
defmodule MyApp.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :username, :string, null: false
      add :email, :string
      timestamps()
    end

    create unique_index(:users, [:username])
  end
end
```

The `change/0` function is reversible — Ecto can derive the "down" migration automatically. The unique index backs the `unique_constraint(:username)` in the changeset.

### 6. Supervision Tree

**Update `lib/ignite/application.ex`** — add `MyApp.Repo` as the first child in the supervision tree:

```elixir
# lib/ignite/application.ex
children = [
  MyApp.Repo,        # NEW — start DB pool first
  Ignite.PubSub,
  Ignite.Presence,
  # ... Cowboy ...
]
```

The Repo must start before Cowboy so database connections are available when the first HTTP request arrives.

### 7. Controller Updates

**Update `lib/my_app/controllers/user_controller.ex`** — rewrite all 5 actions to use Ecto queries instead of hardcoded data. Here is the full module:

```elixir
# lib/my_app/controllers/user_controller.ex
defmodule MyApp.UserController do
  import Ignite.Controller
  alias MyApp.{Repo, User}

  def index(conn) do
    users = Repo.all(User)

    data =
      Enum.map(users, fn u ->
        %{id: u.id, username: u.username, email: u.email}
      end)

    json(conn, %{users: data})
  end

  def show(conn) do
    user_id = conn.params[:id]

    case Repo.get(User, user_id) do
      nil ->
        json(conn, %{error: "User not found"}, 404)

      user ->
        render(conn, "profile",
          name: user.username,
          id: user.id,
          email: user.email || "N/A"
        )
    end
  end

  def create(conn) do
    attrs = %{
      username: conn.params["username"] || "",
      email: conn.params["email"]
    }

    changeset = User.changeset(%User{}, attrs)

    case Repo.insert(changeset) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "User '#{user.username}' created!")
        |> redirect(to: "/")

      {:error, changeset} ->
        errors = format_errors(changeset)

        conn
        |> put_flash(:error, "Failed to create user: #{errors}")
        |> redirect(to: "/")
    end
  end

  def update(conn) do
    user_id = conn.params[:id]

    case Repo.get(User, user_id) do
      nil ->
        json(conn, %{error: "User not found"}, 404)

      user ->
        attrs = %{
          username: conn.params["username"],
          email: conn.params["email"]
        }

        changeset = User.changeset(user, attrs)

        case Repo.update(changeset) do
          {:ok, updated} ->
            json(conn, %{updated: true, id: updated.id, username: updated.username})

          {:error, changeset} ->
            errors = format_errors(changeset)
            json(conn, %{error: errors}, 422)
        end
    end
  end

  def delete(conn) do
    user_id = conn.params[:id]

    case Repo.get(User, user_id) do
      nil ->
        json(conn, %{error: "User not found"}, 404)

      user ->
        {:ok, _deleted} = Repo.delete(user)
        json(conn, %{deleted: true, id: user.id})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {field, msgs} ->
      "#{field} #{Enum.join(msgs, ", ")}"
    end)
  end
end
```

`traverse_errors/2` walks the changeset and interpolates message templates like `"should be at least %{count} character(s)"` into `"should be at least 2 character(s)"`.

## The Request Lifecycle (With Ecto)

```
POST /users (username=Jose&email=jose@example.com)
  → Cowboy adapter → parse body → conn.params = %{"username" => "Jose", ...}
  → Router → plug pipeline → dispatch to UserController.create
  → Controller builds changeset: User.changeset(%User{}, attrs)
  → Changeset validates: required, length, uniqueness
  → Repo.insert(changeset)
    → Ecto generates: INSERT INTO users (username, email, ...) VALUES (?, ?, ...)
    → SQLite executes → returns {:ok, %User{id: 1, ...}}
  → Controller: put_flash(:info, "User 'Jose' created!") → redirect(to: "/")
  → Browser: GET / → flash banner shows "User 'Jose' created!"
```

## Testing

```bash
# Setup
mix deps.get
mix ecto.create
mix ecto.migrate
iex -S mix

# Create a user
curl -X POST -d "username=Jose&email=jose@example.com" http://localhost:4000/users
# → redirects to / with flash "User 'Jose' created!"

# List users
curl http://localhost:4000/users
# → {"users": [{"id": 1, "username": "Jose", "email": "jose@example.com"}]}

# Show user (browser)
# Open http://localhost:4000/users/1 → profile template with real data

# Update user
curl -X PUT -d "username=José" http://localhost:4000/users/1
# → {"updated": true, "id": 1, "username": "José"}

# Delete user
curl -X DELETE http://localhost:4000/users/1
# → {"deleted": true, "id": 1}

# Not found
curl http://localhost:4000/users/999
# → {"error": "User not found"} (404)

# Validation error (username too short)
curl -X POST -d "username=J" http://localhost:4000/users
# → redirects to / with flash error about minimum length

# Restart server → data persists!
```

## Key Concepts

- **Repo pattern**: A single module (`MyApp.Repo`) wraps all database operations. You never write raw SQL — Ecto generates it from its query DSL.
- **Changesets**: Data never goes directly into the database. It passes through a changeset that validates, casts types, and tracks what changed. Invalid data never reaches the DB.
- **Migrations**: Schema changes are versioned files. `mix ecto.migrate` applies them in order. `mix ecto.rollback` undoes the last one. This gives you repeatable, version-controlled database evolution.
- **Adapter swapping**: Change `Ecto.Adapters.SQLite3` to `Ecto.Adapters.Postgres`, swap the dep from `ecto_sqlite3` to `postgrex`, and update the config. Everything else stays the same.

## Phoenix Comparison

| Feature | Ignite | Phoenix |
|---------|--------|---------|
| Repo pattern | `MyApp.Repo` | `MyApp.Repo` |
| Schema DSL | `use Ecto.Schema` | `use Ecto.Schema` |
| Changesets | `Ecto.Changeset` | `Ecto.Changeset` |
| Default DB | SQLite | PostgreSQL |
| Migration tool | `mix ecto.migrate` | `mix ecto.migrate` |
| Config location | `config/config.exs` | `config/dev.exs` |

Ecto is the same library — the integration pattern is identical to Phoenix.

## Files Changed

| File | Change |
|------|--------|
| `mix.exs` | Added `ecto_sql` and `ecto_sqlite3` dependencies |
| `config/config.exs` | **New** — database configuration |
| `lib/my_app/repo.ex` | **New** — Ecto Repo module |
| `lib/my_app/schemas/user.ex` | **New** — User schema with changeset |
| `priv/repo/migrations/..._create_users.exs` | **New** — users table migration |
| `lib/ignite/application.ex` | Added `MyApp.Repo` to supervision tree |
| `lib/my_app/controllers/user_controller.ex` | Rewrote all 5 actions to use Ecto |
| `templates/profile.html.eex` | Added email field |
| `lib/my_app/controllers/welcome_controller.ex` | Added email input to create form |
| `.gitignore` | Added `*.db` patterns |

## File Checklist

- [ ] `mix.exs` — **Modified** (add `ecto_sql` and `ecto_sqlite3` deps)
- [ ] `config/config.exs` — **New**
- [ ] `lib/my_app/repo.ex` — **New**
- [ ] `lib/my_app/schemas/user.ex` — **New**
- [ ] `priv/repo/migrations/20260304000001_create_users.exs` — **New**
- [ ] `lib/ignite/application.ex` — **Modified** (add `MyApp.Repo` to children)
- [ ] `lib/my_app/controllers/user_controller.ex` — **Modified** (rewrite actions to use Ecto)
- [ ] `lib/my_app/controllers/welcome_controller.ex` — **Modified** (add email input to create form)
- [ ] `templates/profile.html.eex` — **Modified** (add email field)

---

[← Previous: Step 29 - Presence Tracking](29-presence.md) | [Next: Step 31 - CSRF Protection →](31-csrf-protection.md)
