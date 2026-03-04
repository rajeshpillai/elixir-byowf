defmodule Ignite.LiveView do
  @moduledoc """
  Defines the LiveView behaviour for real-time server-rendered views.

  A LiveView is a stateful process that:
  1. Mounts with initial state
  2. Renders HTML based on that state
  3. Handles events from the browser (clicks, form submissions)
  4. Re-renders and pushes updates over WebSocket

  ## Example

      defmodule MyApp.CounterLive do
        use Ignite.LiveView

        def mount(_params, _session) do
          {:ok, %{count: 0}}
        end

        def handle_event("increment", _params, assigns) do
          {:noreply, %{assigns | count: assigns.count + 1}}
        end

        def render(assigns) do
          \"""
          <div>
            <h1>Count: \#{assigns.count}</h1>
            <button ignite-click="increment">+1</button>
          </div>
          \"""
        end
      end
  """

  @doc "Called when the LiveView process starts. Returns initial assigns."
  @callback mount(params :: map(), session :: map()) :: {:ok, map()}

  @doc "Called when the browser sends an event (click, form submit, etc.)."
  @callback handle_event(event :: String.t(), params :: map(), assigns :: map()) ::
              {:noreply, map()}

  @doc "Returns the HTML string or %Rendered{} struct for the current assigns."
  @callback render(assigns :: map()) :: String.t() | Ignite.LiveView.Rendered.t()

  @doc "Called when the process receives a message (e.g. PubSub broadcast, timer tick)."
  @callback handle_info(msg :: term(), assigns :: map()) :: {:noreply, map()}

  @optional_callbacks [handle_info: 2]

  @doc """
  Renders a LiveComponent inline within a LiveView's render function.

  Components are identified by a unique `id`. On first render, the component's
  `mount/1` is called with the given props. On subsequent renders, props are
  merged into the existing component state.

  The parent LiveView stores component state in its assigns under `__components__`.

  ## Example

      def render(assigns) do
        \\"\\"\\"
        <div>
          \\\#{live_component(assigns, MyApp.Components.ToggleButton, id: "dark-mode", label: "Dark Mode")}
        </div>
        \\"\\"\\"
      end
  """
  def live_component(parent_assigns, module, opts) do
    id = Keyword.fetch!(opts, :id)
    props = opts |> Keyword.delete(:id) |> Map.new()

    # Get existing component state from parent assigns
    components = Map.get(parent_assigns, :__components__, %{})

    comp_assigns =
      case Map.get(components, id) do
        {^module, existing_assigns} ->
          # Existing component — merge new props from parent
          Map.merge(existing_assigns, props)

        _ ->
          # New component — call mount if defined, otherwise just use props
          # ensure_loaded is needed because BEAM lazy-loads modules;
          # function_exported?/3 returns false for unloaded modules
          Code.ensure_loaded(module)

          if function_exported?(module, :mount, 1) do
            {:ok, initial} = module.mount(props)
            initial
          else
            props
          end
      end

    # Store component state in the process dictionary so the handler
    # can persist it after render completes (render is a pure function
    # that returns a string, so it can't update parent assigns directly)
    rendered_components = Process.get(:__ignite_components__, %{})
    Process.put(:__ignite_components__, Map.put(rendered_components, id, {module, comp_assigns}))

    # Render the component with a wrapper div carrying component ID
    html = module.render(comp_assigns)

    ~s(<div ignite-component="#{id}">#{html}</div>)
  end

  @doc """
  Collects component state accumulated during render.

  Called by the handler after render to persist component state
  back into the parent's assigns.
  """
  def collect_components(assigns) do
    case Process.delete(:__ignite_components__) do
      nil -> assigns
      components when map_size(components) == 0 -> assigns
      components -> Map.put(assigns, :__components__, components)
    end
  end

  @doc """
  Triggers a client-side navigation to a different LiveView.

  The client will close the current WebSocket, update the URL via
  `history.pushState`, and open a new WebSocket to the target LiveView.

  ## Example

      def handle_event("go_dashboard", _params, assigns) do
        {:noreply, push_redirect(assigns, "/dashboard")}
      end
  """
  def push_redirect(assigns, url, live_path \\ nil) do
    redirect_info = %{url: url}

    redirect_info =
      if live_path do
        Map.put(redirect_info, :live_path, live_path)
      else
        redirect_info
      end

    Map.put(assigns, :__redirect__, redirect_info)
  end

  @doc """
  Compiles a LiveView template into a `%Rendered{}` struct for fine-grained diffing.

  Uses EEx syntax (`<%= expr %>`) to mark dynamic expressions. Static HTML
  is separated at compile time — only dynamic values are evaluated at runtime.

  ## Example

      def render(assigns) do
        ~L\"\"\"
        <h1>Count: <%= assigns.count %></h1>
        <button ignite-click="inc">+1</button>
        \"\"\"
      end

  This produces a `%Rendered{}` with:
  - statics: `["<h1>Count: ", "</h1>\\n<button ignite-click=\\"inc\\">+1</button>\\n"]`
  - dynamics: `[to_string(assigns.count)]`
  """
  defmacro sigil_L({:<<>>, _meta, [template]}, _modifiers) do
    EEx.compile_string(template, engine: Ignite.LiveView.EExEngine)
  end

  defmacro __using__(_opts) do
    quote do
      @behaviour Ignite.LiveView
      import Ignite.LiveView, only: [
        push_redirect: 2,
        push_redirect: 3,
        live_component: 3,
        collect_components: 1,
        sigil_L: 2
      ]
      import Ignite.LiveView.Stream, only: [
        stream: 3,
        stream: 4,
        stream_insert: 3,
        stream_insert: 4,
        stream_delete: 3
      ]
      import Ignite.LiveView.UploadHelpers, only: [
        allow_upload: 2,
        allow_upload: 3,
        uploaded_entries: 2,
        consume_uploaded_entries: 3,
        cancel_upload: 3,
        live_file_input: 2
      ]
    end
  end
end
