# Step 19: LiveComponents — Reusable Stateful Widgets

In Phoenix LiveView, **LiveComponents** are reusable pieces of UI that manage their own state. Instead of duplicating logic across multiple LiveViews, you extract it into a component module with its own `mount`, `handle_event`, and `render` callbacks.

In this step, we'll add LiveComponent support to Ignite.

## The Problem

Imagine you have a notification badge that appears in both your dashboard and your counter page. Without components, you'd have to:
1. Duplicate the badge HTML in both `render/1` functions
2. Duplicate the dismiss/restore event handling in both `handle_event/3` functions
3. Track the badge state in both LiveViews' assigns

LiveComponents solve this — write it once, use it everywhere.

## The Architecture

Our LiveComponent system has four parts:

1. **`Ignite.LiveComponent`** — a behaviour that components implement
2. **`live_component/3`** — a helper called during render to embed a component
3. **Handler routing** — the WebSocket handler routes `"component_id:event"` to the right module
4. **JS namespacing** — the client prefixes events from elements inside `[ignite-component]`

### Component State Lifecycle

```
Parent LiveView
├── assigns: %{clicks: 0, __components__: %{...}}
│
├── Component "alerts" → {NotificationBadge, %{count: 3, dismissed: false}}
├── Component "toggle" → {ToggleButton, %{on: true, label: "Dark Mode"}}
```

Components store their state as `{module, assigns}` tuples inside the parent's `__components__` key.

## Step 1: The LiveComponent Behaviour

Create `lib/ignite/live_component.ex`:

```elixir
defmodule Ignite.LiveComponent do
  @callback mount(props :: map()) :: {:ok, map()}
  @callback handle_event(event :: String.t(), params :: map(), assigns :: map()) ::
              {:noreply, map()}
  @callback render(assigns :: map()) :: String.t()

  @optional_callbacks [mount: 1]

  defmacro __using__(_opts) do
    quote do
      @behaviour Ignite.LiveComponent
    end
  end
end
```

Key differences from `Ignite.LiveView`:
- **`mount/1`** takes only props (no params/session — components receive data from their parent)
- **`mount/1` is optional** — if not defined, props are used directly as assigns
- No `handle_info/2` — components don't receive process messages directly

## Step 2: The `live_component/3` Helper

In `lib/ignite/live_view.ex`, we add a function that LiveViews call during render:

```elixir
def live_component(parent_assigns, module, opts) do
  id = Keyword.fetch!(opts, :id)
  props = opts |> Keyword.delete(:id) |> Map.new()

  # Look up existing component state
  components = Map.get(parent_assigns, :__components__, %{})

  comp_assigns =
    case Map.get(components, id) do
      {^module, existing_assigns} ->
        # Existing — merge new props from parent
        Map.merge(existing_assigns, props)
      _ ->
        # New — call mount if defined
        if function_exported?(module, :mount, 1) do
          {:ok, initial} = module.mount(props)
          initial
        else
          props
        end
    end

  # Store in process dictionary (side-channel during render)
  rendered = Process.get(:__ignite_components__, %{})
  Process.put(:__ignite_components__, Map.put(rendered, id, {module, comp_assigns}))

  # Render with wrapper div
  html = module.render(comp_assigns)
  ~s(<div ignite-component="#{id}">#{html}</div>)
end
```

### Why the Process Dictionary?

This is the trickiest part. `render/1` is a **pure function** — it takes assigns and returns a string. It can't modify the parent's assigns. But we need to persist component state (especially newly mounted components) back to the handler.

The solution: during render, `live_component/3` writes component state to the **process dictionary** (a per-process mutable store). After render completes, the handler calls `collect_components/1` to read it back:

```elixir
def collect_components(assigns) do
  case Process.delete(:__ignite_components__) do
    nil -> assigns
    components when map_size(components) == 0 -> assigns
    components -> Map.put(assigns, :__components__, components)
  end
end
```

This pattern is similar to what Phoenix LiveView does internally — it uses process-level state to track component trees during rendering.

## Step 3: Handler Event Routing

The WebSocket handler needs to detect component events and route them to the right module. Component events use the format `"component_id:event_name"`:

```elixir
defp handle_possible_component_event(event, params, state) do
  case String.split(event, ":", parts: 2) do
    [component_id, component_event] ->
      components = Map.get(state.assigns, :__components__, %{})

      case Map.get(components, component_id) do
        {module, comp_assigns} ->
          {:noreply, new_assigns} =
            apply(module, :handle_event, [component_event, params, comp_assigns])

          new_components = Map.put(components, component_id, {module, new_assigns})
          {Map.put(state.assigns, :__components__, new_components), true}

        nil ->
          {state.assigns, false}
      end

    _ ->
      {state.assigns, false}
  end
end
```

After updating component state, the handler re-renders the **entire parent LiveView** (which will re-render all its components with updated state), then sends the new dynamics to the client.

## Step 4: JavaScript Event Namespacing

On the client side, we add a `resolveEvent` function that checks if a clicked element is inside a component wrapper:

```javascript
function resolveEvent(eventName, target) {
  var el = target;
  while (el && el !== document) {
    var componentId = el.getAttribute("ignite-component");
    if (componentId) {
      return componentId + ":" + eventName;
    }
    el = el.parentElement;
  }
  return eventName;
}
```

This is called for all event types (click, change, submit). A button inside `<div ignite-component="alerts">` that has `ignite-click="dismiss"` will send `"alerts:dismiss"` over the WebSocket.

## Step 5: Building a Component

Here's a complete notification badge component:

```elixir
defmodule MyApp.Components.NotificationBadge do
  use Ignite.LiveComponent

  @impl true
  def mount(props) do
    {:ok, Map.merge(%{count: 0, label: "Notifications", dismissed: false}, props)}
  end

  @impl true
  def handle_event("dismiss", _params, assigns) do
    {:noreply, %{assigns | dismissed: true, count: 0}}
  end

  @impl true
  def handle_event("restore", _params, assigns) do
    {:noreply, %{assigns | dismissed: false}}
  end

  @impl true
  def render(assigns) do
    if assigns.dismissed do
      """
      <span>#{assigns.label} dismissed</span>
      <button ignite-click="restore">Undo</button>
      """
    else
      """
      <span>#{assigns.label}: #{assigns.count}</span>
      <button ignite-click="dismiss">Dismiss</button>
      """
    end
  end
end
```

## Step 6: Using Components in a LiveView

```elixir
defmodule MyApp.ComponentsDemoLive do
  use Ignite.LiveView

  def mount(_params, _session) do
    {:ok, %{clicks: 0}}
  end

  def handle_event("parent_click", _params, assigns) do
    {:noreply, %{assigns | clicks: assigns.clicks + 1}}
  end

  def render(assigns) do
    """
    <div>
      <h1>Parent clicks: #{assigns.clicks}</h1>
      <button ignite-click="parent_click">Click Parent</button>

      #{live_component(assigns, MyApp.Components.NotificationBadge,
          id: "alerts", label: "Alerts", count: 3)}

      #{live_component(assigns, MyApp.Components.ToggleButton,
          id: "dark-mode", label: "Dark Mode")}
    </div>
    """
  end
end
```

Each component gets a unique `id`. The same component module can be used multiple times with different IDs and props.

## How Events Flow

```
Browser: User clicks "Dismiss" inside the "alerts" component
  ↓
ignite.js: Detects ignite-click="dismiss" inside [ignite-component="alerts"]
  ↓
WebSocket: Sends {"event": "alerts:dismiss", "params": {}}
  ↓
Handler: Splits "alerts:dismiss" → component_id="alerts", event="dismiss"
  ↓
Handler: Looks up {NotificationBadge, assigns} from __components__["alerts"]
  ↓
NotificationBadge.handle_event("dismiss", ...) → updates component assigns
  ↓
Handler: Re-renders entire LiveView (including all components)
  ↓
WebSocket: Sends updated dynamics to browser
  ↓
morphdom: Patches only the changed elements
```

## Key Concepts

### Process Dictionary as Side-Channel
The process dictionary (`Process.get/put`) is normally discouraged in Elixir because it introduces mutable state. But here it's used in a controlled way — written during render, read immediately after, then cleaned up. This is the same pattern Phoenix LiveView uses internally.

### Event Namespacing
Component events are automatically namespaced by the JS layer. The component author writes `ignite-click="dismiss"`, but the server receives `"alerts:dismiss"`. This prevents event name collisions between components and the parent LiveView.

### Props vs State
- **Props** (passed via `live_component/3` opts) flow **down** from parent to component
- **State** (set by `mount/1` and `handle_event/3`) is **owned** by the component
- On re-render, new props are merged into existing component state

## Try It

```bash
mix compile
iex -S mix
# Visit http://localhost:4000/components
```

- Click "Click Parent" — only the parent counter changes
- Click "Dismiss" on a notification — only that badge updates
- Toggle switches — each toggle has independent state
- The parent and all components coexist with isolated state

## What's Next?

In Step 20, we'll add **JS Hooks** — client-side lifecycle callbacks that let you integrate third-party JavaScript libraries (charts, maps, clipboard) with LiveView's server-rendered model.
