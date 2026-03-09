# Step 22: PUT/PATCH/DELETE HTTP Methods

## What We're Building

Support for `put`, `patch`, and `delete` route macros in the Router DSL, giving Ignite full REST/CRUD capability.

## The Problem

Our router only supports `get` and `post` macros. REST APIs need all four mutation verbs:

| Verb | Purpose | Example |
|------|---------|---------|
| POST | Create a resource | `POST /users` |
| PUT | Replace a resource entirely | `PUT /users/42` |
| PATCH | Partially update a resource | `PATCH /users/42` |
| DELETE | Remove a resource | `DELETE /users/42` |

Without these, Ignite can't serve as a proper API backend.

## The Solution

Since we already have a `build_route/4` helper that generates pattern-matching dispatch clauses, adding new HTTP methods is trivial — we just call it with a different method string.

### New Macros in `Ignite.Router`

```elixir
defmacro put(path, to: controller, action: action) do
  build_route("PUT", path, controller, action)
end

defmacro patch(path, to: controller, action: action) do
  build_route("PATCH", path, controller, action)
end

defmacro delete(path, to: controller, action: action) do
  build_route("DELETE", path, controller, action)
end
```

That's it. Each macro generates a `dispatch/2` function clause that pattern-matches on the HTTP method string (`"PUT"`, `"PATCH"`, `"DELETE"`) and the path segments.

### Why This Is So Simple

This is the payoff of good abstraction. Back in Step 3 (Router DSL), we built `build_route/4` to handle the complex work of:
1. Splitting the path into segments
2. Converting `:param` segments into pattern-match variables
3. Building the params map from captured variables
4. Generating the dispatch function clause

All the new macros need to do is pass the correct HTTP method string. The macro system does the rest at compile time.

### Body Parsing

PUT and PATCH requests typically carry a request body. Our Cowboy adapter already handles this — the `read_cowboy_body/1` function uses `:cowboy_req.has_body/1`, which returns `true` for any request with a body regardless of method. Combined with Step 21's JSON parsing, both form-encoded and JSON bodies work automatically.

DELETE requests typically don't carry a body, but if one is present, it will be parsed too.

## Using It

### Router

```elixir
get "/users/:id", to: UserController, action: :show
post "/users", to: UserController, action: :create
put "/users/:id", to: UserController, action: :update
patch "/users/:id", to: UserController, action: :update
delete "/users/:id", to: UserController, action: :delete
```

### Controller

```elixir
def update(conn) do
  user_id = conn.params[:id]
  username = conn.params["username"] || "unknown"
  json(conn, %{updated: true, id: user_id, username: username})
end

def delete(conn) do
  user_id = conn.params[:id]
  json(conn, %{deleted: true, id: user_id})
end
```

## Testing

```bash
# PUT — replace user
curl -X PUT -H "Content-Type: application/json" \
     -d '{"username":"Jose"}' \
     http://localhost:4000/users/42
# → {"id":"42","updated":true,"username":"Jose"}

# PATCH — partial update
curl -X PATCH -d "username=Updated" http://localhost:4000/users/42
# → {"id":"42","updated":true,"username":"Updated"}

# DELETE — remove user
curl -X DELETE http://localhost:4000/users/42
# → {"deleted":true,"id":"42"}
```

## Key Elixir Concepts

- **DRY with shared helpers**: `build_route/4` is a private function inside the `Ignite.Router` module. Since macros are expanded at compile time, this function runs during compilation to generate the right function clauses. Writing it once and reusing it for all five HTTP verbs keeps the code clean.

- **Same path, different methods**: Elixir's pattern matching naturally handles `PUT /users/42` vs `GET /users/42` vs `DELETE /users/42` as separate function clauses. The BEAM's pattern matching engine picks the right one in constant time.

- **PUT vs PATCH convention**: PUT means "replace the entire resource" while PATCH means "update specific fields." In practice, many apps route both to the same controller action (as we do here), but the distinction matters for API design.
