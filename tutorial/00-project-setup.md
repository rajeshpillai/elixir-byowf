# Step 0: Project Setup

## What We're Building

Before writing any framework code, we need to create the Elixir project
that will hold everything. By the end of this step, you'll have a working
Mix project called **Ignite** that compiles and runs.

## Prerequisites

- **Elixir >= 1.14** installed. Check with:
  ```bash
  elixir --version
  ```
  If not installed, follow the [official guide](https://elixir-lang.org/install.html).

- **A text editor** — VS Code with the ElixirLS extension works well.

- **A terminal** — all commands in this tutorial use bash.

## Concepts You'll Learn

### Mix

**Mix** is Elixir's build tool. It's like `npm` for Node.js, `cargo` for
Rust, or `maven` for Java. Mix handles:

- Creating new projects (`mix new`)
- Compiling code (`mix compile`)
- Running tests (`mix test`)
- Managing dependencies (`mix deps.get`)
- Starting an interactive shell (`iex -S mix`)

### Project Structure

When Mix creates a project, it generates a standard directory layout:

```
ignite/
├── lib/                  # Your source code goes here
│   ├── ignite.ex         # Top-level module
│   └── ignite/
│       └── application.ex  # OTP Application entry point
├── test/                 # Tests
│   ├── ignite_test.exs
│   └── test_helper.exs
├── mix.exs               # Project configuration (like package.json)
└── .formatter.exs        # Code formatting rules
```

The key convention: a module named `Ignite.Server` lives in the file
`lib/ignite/server.ex`. The directory structure mirrors the module name.

### mix.exs

This is the project's configuration file. It defines:

```elixir
defmodule Ignite.MixProject do
  use Mix.Project

  def project do
    [
      app: :ignite,                          # Application name (atom)
      version: "0.1.0",                      # Version string
      elixir: "~> 1.18",                     # Required Elixir version
      start_permanent: Mix.env() == :prod,   # Crash VM if app crashes in prod
      deps: deps()                           # Dependencies (none yet!)
    ]
  end

  def application do
    [
      extra_applications: [:logger],          # Include Elixir's logger
      mod: {Ignite.Application, []}           # Entry point module
    ]
  end

  defp deps do
    []   # No dependencies for Steps 1-9!
  end
end
```

Key parts:
- **`project/0`** — general project metadata
- **`application/0`** — OTP application config. The `mod:` tells the
  BEAM VM which module to call when the app starts.
- **`deps/0`** — external libraries. We won't add any until Step 10!

### IEx (Interactive Elixir)

`iex` is Elixir's interactive shell (REPL). Running `iex -S mix` starts
it with your project loaded, so you can call your functions directly:

```bash
$ iex -S mix
iex(1)> 1 + 1
2
iex(2)> String.upcase("hello")
"HELLO"
```

The `-S mix` flag tells IEx to compile and load your project first.

### The `lib/ignite.ex` Module

Every Mix project gets a top-level module. Ours just has a module doc
for now — we'll add functions later:

```elixir
defmodule Ignite do
  @moduledoc """
  Ignite - A tiny Phoenix-like web framework built from scratch.
  """
end
```

`@moduledoc` is a **module attribute** that documents the module. It
shows up in generated documentation and in IEx when you type `h Ignite`.

### The `lib/ignite/application.ex` Module

This is the OTP Application entry point. The BEAM calls `start/2` when
your app boots:

```elixir
defmodule Ignite.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = []

    opts = [strategy: :one_for_one, name: Ignite.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Don't worry about understanding this yet — we'll cover OTP, Supervisors,
and `use Application` in detail in Step 6. For now, just know it starts
an empty supervisor that we'll add children to later.

## Step-by-Step Setup

### 1. Create the project

Open your terminal and run:

```bash
mix new ignite --sup
```

The `--sup` flag generates the `application.ex` supervisor file. Mix
will create the full project structure:

```
* creating README.md
* creating .formatter.exs
* creating .gitignore
* creating mix.exs
* creating lib
* creating lib/ignite.ex
* creating lib/ignite/application.ex
* creating test
* creating test/test_helper.exs
* creating test/ignite_test.exs
```

### 2. Enter the project directory

```bash
cd ignite
```

### 3. Initialize git

```bash
git init
git add .
git commit -m "Step 0: Initialize Mix project"
```

### 4. Verify it compiles

```bash
mix compile
```

You should see output like:

```
Compiling 2 files (.ex)
Generated ignite app
```

### 5. Start the interactive shell

```bash
iex -S mix
```

Try some Elixir:

```elixir
iex(1)> IO.puts("Ignite is ready!")
Ignite is ready!
:ok
```

Exit with `Ctrl+C` twice.

### 6. Run the tests

```bash
mix test
```

You should see:

```
..
Finished in 0.0 seconds
1 test, 0 failures
```

### 7. Create the tutorial and templates directories

We'll need these in later steps:

```bash
mkdir -p templates
mkdir -p assets
```

## File Checklist

After this step, your project should have these files:

| File | Status | Purpose |
|------|--------|---------|
| `mix.exs` | Generated by Mix | Project configuration |
| `lib/ignite.ex` | Generated by Mix | Top-level module |
| `lib/ignite/application.ex` | Generated by Mix | OTP Application entry point |
| `test/test_helper.exs` | Generated by Mix | Test setup |
| `test/ignite_test.exs` | Generated by Mix | Default test file |
| `.formatter.exs` | Generated by Mix | Code formatting rules |
| `.gitignore` | Generated by Mix | Git ignore patterns |

## What's Next

We have an empty Elixir project. In **Step 1**, we'll build the first
real piece: a **TCP server** that listens on port 4000 and responds
"Hello, Ignite!" to every browser request. You'll learn about Erlang's
`:gen_tcp`, pattern matching, recursion, and BEAM processes.
