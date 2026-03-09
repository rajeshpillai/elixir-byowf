defmodule TodoApp.TodoHTML do
  @moduledoc """
  HTML rendering functions for the Todo app LiveView.
  Uses ~F (Flame EEx) templates for clean, auto-escaped rendering.
  """

  import Ignite.LiveView, only: [sigil_F: 2, raw: 1]
  alias TodoApp.Category

  # ═══════════════════════════════════════════════════════════════════
  # Entry Points
  # ═══════════════════════════════════════════════════════════════════

  def render_auth(assigns) do
    to_html(~F"""
    <div id="todo-auth" class="auth-container">
      <div class="auth-card">
        <%= if @auth_mode == :register do %>
          <h1 class="auth-title">Create Account</h1>
          <p class="auth-subtitle">Start organizing your tasks</p>
          <form ignite-submit="register">
            <div class="form-group">
              <label class="form-label">Username</label>
              <input class="form-input<%= error_class(@auth_errors, "username") %>" type="text" name="username" placeholder="Your name" />
              <%= raw(error_tag(@auth_errors, "username")) %>
            </div>
            <div class="form-group">
              <label class="form-label">Email</label>
              <input class="form-input<%= error_class(@auth_errors, "email") %>" type="email" name="email" placeholder="you@example.com" />
              <%= raw(error_tag(@auth_errors, "email")) %>
            </div>
            <div class="form-group">
              <label class="form-label">Password</label>
              <input class="form-input<%= error_class(@auth_errors, "password") %>" type="password" name="password" placeholder="Min 6 characters" />
              <%= raw(error_tag(@auth_errors, "password")) %>
            </div>
            <button class="btn btn-primary btn-full" type="submit">Create Account</button>
          </form>
          <p class="auth-switch">
            Already have an account?
            <button class="auth-switch-link" ignite-click="switch_auth">Sign in</button>
          </p>
        <% else %>
          <h1 class="auth-title">Welcome Back</h1>
          <p class="auth-subtitle">Sign in to your account</p>
          <form ignite-submit="login">
            <div class="form-group">
              <label class="form-label">Email</label>
              <input class="form-input<%= error_class(@auth_errors, "email") %>" type="email" name="email" placeholder="you@example.com" />
              <%= raw(error_tag(@auth_errors, "email")) %>
            </div>
            <div class="form-group">
              <label class="form-label">Password</label>
              <input class="form-input<%= error_class(@auth_errors, "password") %>" type="password" name="password" placeholder="Your password" />
              <%= raw(error_tag(@auth_errors, "password")) %>
            </div>
            <button class="btn btn-primary btn-full" type="submit">Sign In</button>
          </form>
          <p class="auth-switch">
            Don't have an account?
            <button class="auth-switch-link" ignite-click="switch_auth">Create one</button>
          </p>
        <% end %>
      </div>
    </div>
    """)
  end

  def render_app(assigns, counts) do
    """
    <div id="todo-app" class="todo-app">
      #{render_header(assigns)}
      #{render_toolbar(assigns)}
      #{render_filter_bar(assigns, counts)}
      #{render_add_form(assigns)}
      #{render_bulk_bar(assigns)}
      #{render_todo_list(assigns)}
      #{render_pagination(assigns)}
      #{render_subtask_panel(assigns)}
      #{render_category_manager(assigns)}
    </div>
    """
  end

  # ═══════════════════════════════════════════════════════════════════
  # Section Renderers
  # ═══════════════════════════════════════════════════════════════════

  defp render_header(assigns) do
    to_html(~F"""
    <header class="app-header">
      <h1 class="app-title">Todo App</h1>
      <div class="user-info">
        <span class="user-name"><%= @current_user.username %></span>
        <button class="btn btn-ghost btn-sm" ignite-click="logout">Logout</button>
      </div>
    </header>
    """)
  end

  defp render_toolbar(assigns) do
    to_html(~F"""
    <div class="toolbar">
      <form class="search-form" ignite-submit="search">
        <input class="search-input" type="text" name="search" value="<%= @search %>" placeholder="Search todos... (Enter to search)" />
        <button class="btn btn-secondary btn-sm" type="submit">Search</button>
        <%= if @search != "" do %>
          <button class="btn btn-ghost btn-sm" ignite-click="clear_search">Clear</button>
        <% end %>
      </form>
      <div class="toolbar-actions">
        <select class="form-select" name="category_filter" ignite-change="change">
          <option value=""<%= if @category_filter == "" do %> selected<% end %>>All Categories</option>
          <%= for cat <- @categories do %>
            <option value="<%= cat.id %>"<%= if to_string(cat.id) == @category_filter do %> selected<% end %>><%= cat.name %></option>
          <% end %>
        </select>
        <button class="btn btn-ghost btn-sm" ignite-click="toggle_category_mgmt">Manage</button>
      </div>
    </div>
    """)
  end

  defp render_filter_bar(assigns, counts) do
    filters = [
      {"all", "All", counts.all},
      {"pending", "Pending", counts.pending},
      {"in_progress", "In Progress", counts.in_progress},
      {"completed", "Completed", counts.completed}
    ]

    to_html(~F"""
    <div class="filter-bar">
      <div class="filter-group">
        <%= for {val, label, count} <- filters do %>
          <button class="filter-btn<%= if @filter == val do %> filter-btn--active<% end %>" ignite-click="set_filter" ignite-value="<%= val %>"><%= label %> <span class="text-count">(<%= count %>)</span></button>
        <% end %>
      </div>
      <button class="<%= if @show_bookmarked do %>bookmark-filter-btn bookmark-filter-btn--active<% else %>bookmark-filter-btn<% end %>" ignite-click="toggle_bookmarked_filter">&#9829; Favorites</button>
    </div>
    """)
  end

  defp render_add_form(assigns) do
    to_html(~F"""
    <form class="add-form" ignite-submit="add_todo">
      <input class="add-form__input" type="text" name="title" placeholder="What needs to be done?" value="" />
      <select class="add-form__select" name="category_id">
        <option value="">No category</option>
        <%= for cat <- @categories do %>
          <option value="<%= cat.id %>"><%= cat.name %></option>
        <% end %>
      </select>
      <button class="btn btn-primary" type="submit">Add</button>
    </form>
    """)
  end

  defp render_bulk_bar(assigns) do
    count = MapSet.size(assigns.selected_ids)

    if count > 0 do
      to_html(~F"""
      <div class="bulk-bar">
        <span class="bulk-bar__count"><%= count %> selected</span>
        <form ignite-submit="bulk_action" style="display:flex;gap:0.5rem;align-items:center;">
          <select class="bulk-bar__select" name="action">
            <option value="">-- Bulk Action --</option>
            <option value="pending">Mark Pending</option>
            <option value="in_progress">Mark In Progress</option>
            <option value="completed">Mark Completed</option>
            <option value="delete">Delete Selected</option>
          </select>
          <button class="btn btn-sm btn-secondary" type="submit">Apply</button>
        </form>
      </div>
      """)
    else
      ""
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Todo List & Items
  # ═══════════════════════════════════════════════════════════════════

  defp render_todo_list(assigns) do
    if assigns.todos == [] do
      """
      <div class="empty-state">
        <div class="empty-state__icon">&#128203;</div>
        <h3 class="empty-state__title">No todos found</h3>
        <p class="empty-state__text">Add a new todo above or adjust your filters.</p>
      </div>
      """
    else
      all_selected =
        length(assigns.todos) > 0 &&
          MapSet.size(assigns.selected_ids) == length(assigns.todos)

      items = Enum.map_join(assigns.todos, "\n", &render_todo_item(&1, assigns))

      to_html(~F"""
      <div class="todo-list">
        <div class="todo-list-header">
          <input type="checkbox" class="todo-list-header__checkbox" ignite-click="toggle_select_all"<%= if all_selected do %> checked<% end %> />
          <span>Todo</span>
        </div>
        <%= raw(items) %>
      </div>
      """)
    end
  end

  defp render_todo_item(todo, assigns) do
    cond do
      todo.id == assigns.editing_id -> render_todo_item_editing(todo, assigns)
      todo.id == assigns.confirm_delete_id -> render_todo_item_confirm(todo, assigns)
      true -> render_todo_item_normal(todo, assigns)
    end
  end

  defp render_todo_item_editing(todo, assigns) do
    to_html(~F"""
    <div class="todo-item todo-item--editing todo-item--<%= todo.status %>">
      <form class="edit-form" ignite-submit="save_edit">
        <input class="edit-form__input" type="text" name="title" value="<%= @editing_title %>" />
        <button class="btn btn-primary btn-sm" type="submit">Save</button>
        <button class="btn btn-ghost btn-sm" type="button" ignite-click="cancel_edit">Cancel</button>
      </form>
    </div>
    """)
  end

  defp render_todo_item_normal(todo, assigns) do
    selected = MapSet.member?(assigns.selected_ids, todo.id)
    title_class =
      if todo.status == "completed",
        do: "todo-item__title todo-item__title--done",
        else: "todo-item__title"

    to_html(~F"""
    <div class="todo-item todo-item--<%= todo.status %><%= if selected do %> todo-item--selected<% end %>">
      <input type="checkbox" class="todo-item__checkbox" ignite-click="toggle_select" ignite-value="<%= todo.id %>"<%= if selected do %> checked<% end %> />
      <button class="badge badge--<%= todo.status %>" ignite-click="cycle_status" ignite-value="<%= todo.id %>"><%= status_display(todo.status) %></button>
      <div class="todo-item__content">
        <span class="<%= title_class %>"><%= todo.title %></span>
        <div class="todo-item__meta">
          <%= if match?(%Category{}, todo.category) do %>
            <span class="badge badge--category"><%= todo.category.name %></span>
          <% end %>
          <%= raw(render_subtask_btn(todo, assigns)) %>
        </div>
      </div>
      <div class="todo-item__actions">
        <button class="heart-btn<%= if todo.bookmarked do %> heart-btn--active<% end %>" ignite-click="toggle_bookmark" ignite-value="<%= todo.id %>"><%= if todo.bookmarked do %>&#9829;<% else %>&#9825;<% end %></button>
        <button class="btn-icon btn-icon--edit" ignite-click="start_edit" ignite-value="<%= todo.id %>">&#9998;</button>
        <button class="btn-icon btn-icon--danger" ignite-click="confirm_delete" ignite-value="<%= todo.id %>">&#10005;</button>
      </div>
    </div>
    """)
  end

  defp render_subtask_btn(todo, assigns) do
    count = length(todo.subtasks)

    if count > 0 do
      done = Enum.count(todo.subtasks, &(&1.status == "completed"))

      to_html(~F"""
      <button class="subtask-count<%= if todo.id == @active_todo_id do %> subtask-count--active<% end %>" ignite-click="show_subtasks" ignite-value="<%= todo.id %>"><%= done %>/<%= count %> subtasks</button>
      """)
    else
      to_html(~F"""
      <button class="subtask-count" ignite-click="show_subtasks" ignite-value="<%= todo.id %>">+ subtask</button>
      """)
    end
  end

  defp render_todo_item_confirm(todo, assigns) do
    selected = MapSet.member?(assigns.selected_ids, todo.id)

    to_html(~F"""
    <div class="todo-item todo-item--<%= todo.status %><%= if selected do %> todo-item--selected<% end %>">
      <div class="todo-item__content">
        <span class="todo-item__title"><%= todo.title %></span>
      </div>
      <div class="confirm-dialog">
        <span>Delete this todo?</span>
        <button class="btn btn-danger btn-sm" ignite-click="delete_todo" ignite-value="<%= todo.id %>">Yes, delete</button>
        <button class="btn btn-ghost btn-sm" ignite-click="cancel_delete">Cancel</button>
      </div>
    </div>
    """)
  end

  # ═══════════════════════════════════════════════════════════════════
  # Pagination
  # ═══════════════════════════════════════════════════════════════════

  defp render_pagination(assigns) do
    total_pages = max(1, ceil(assigns.total_count / assigns.per_page))
    page = assigns.page

    if total_pages <= 1 do
      to_html(~F"""
      <div class="pagination">
        <div></div>
        <%= raw(render_pagination_info(assigns)) %>
      </div>
      """)
    else
      to_html(~F"""
      <div class="pagination">
        <div class="pagination__buttons">
          <button class="pagination__btn"<%= if page > 1 do %> ignite-click="set_page" ignite-value="<%= page - 1 %>"<% else %> disabled<% end %>>&larr; Prev</button>
          <%= for p <- page_range(page, total_pages) do %>
            <%= if p == :ellipsis do %>
              <span class="pagination__btn" style="cursor:default;">...</span>
            <% else %>
              <button class="pagination__btn<%= if p == page do %> pagination__btn--active<% end %>" ignite-click="set_page" ignite-value="<%= p %>"><%= p %></button>
            <% end %>
          <% end %>
          <button class="pagination__btn"<%= if page < total_pages do %> ignite-click="set_page" ignite-value="<%= page + 1 %>"<% else %> disabled<% end %>>Next &rarr;</button>
        </div>
        <%= raw(render_pagination_info(assigns)) %>
      </div>
      """)
    end
  end

  defp render_pagination_info(assigns) do
    from = (assigns.page - 1) * assigns.per_page + 1
    to_val = min(assigns.page * assigns.per_page, assigns.total_count)

    to_html(~F"""
    <div class="pagination__info">
      <span><%= from %>-<%= to_val %> of <%= @total_count %></span>
      <select class="pagination__select" name="per_page" ignite-change="change">
        <%= for n <- [5, 10, 25, 50] do %>
          <option value="<%= n %>"<%= if n == @per_page do %> selected<% end %>><%= n %></option>
        <% end %>
      </select>
      <span>per page</span>
    </div>
    """)
  end

  # ═══════════════════════════════════════════════════════════════════
  # Subtask Panel
  # ═══════════════════════════════════════════════════════════════════

  defp render_subtask_panel(assigns) do
    if assigns.active_todo_id == nil do
      ""
    else
      active_todo = Enum.find(assigns.todos, &(&1.id == assigns.active_todo_id))
      todo_title = if active_todo, do: active_todo.title, else: "Todo ##{assigns.active_todo_id}"

      to_html(~F"""
      <div class="subtask-panel">
        <div class="subtask-panel__header">
          <h3 class="subtask-panel__title">Subtasks: <%= todo_title %></h3>
          <button class="btn btn-ghost btn-sm" ignite-click="show_subtasks" ignite-value="<%= @active_todo_id %>">Close</button>
        </div>
        <form class="subtask-form" ignite-submit="add_subtask">
          <input class="subtask-form__input" type="text" name="title" placeholder="Add a subtask..." value="" />
          <button class="btn btn-primary btn-sm" type="submit">Add</button>
        </form>
        <div class="subtask-list">
          <%= if @subtasks == [] do %>
            <p class="empty-state__text" style="padding: 1rem 0;">No subtasks yet. Add one above.</p>
          <% else %>
            <%= for st <- @subtasks do %>
              <%= raw(render_subtask_item(st)) %>
            <% end %>
          <% end %>
        </div>
        <%= raw(render_subtask_progress(@subtasks)) %>
      </div>
      """)
    end
  end

  defp render_subtask_item(st) do
    done = st.status == "completed"
    title_class = if done, do: "subtask-item__title subtask-item__title--done", else: "subtask-item__title"

    to_html(~F"""
    <div class="subtask-item">
      <input type="checkbox" class="subtask-item__checkbox" ignite-click="toggle_subtask" ignite-value="<%= st.id %>"<%= if done do %> checked<% end %> />
      <span class="<%= title_class %>"><%= st.title %></span>
      <button class="btn-icon btn-icon--danger" ignite-click="delete_subtask" ignite-value="<%= st.id %>">&#10005;</button>
    </div>
    """)
  end

  defp render_subtask_progress([]), do: ""

  defp render_subtask_progress(subtasks) do
    total = length(subtasks)
    done = Enum.count(subtasks, &(&1.status == "completed"))
    pct = if total > 0, do: round(done / total * 100), else: 0

    to_html(~F"""
    <div class="subtask-progress">
      <span><%= done %>/<%= total %> completed (<%= pct %>%)</span>
      <div class="subtask-progress__bar">
        <div class="subtask-progress__fill" style="width: <%= pct %>%;"></div>
      </div>
    </div>
    """)
  end

  # ═══════════════════════════════════════════════════════════════════
  # Category Manager
  # ═══════════════════════════════════════════════════════════════════

  defp render_category_manager(assigns) do
    if !assigns.show_category_mgmt do
      ""
    else
      to_html(~F"""
      <div class="overlay" ignite-click="toggle_category_mgmt"></div>
      <div class="category-panel">
        <div class="category-panel__header">
          <h2 class="category-panel__title">Manage Categories</h2>
          <button class="btn-icon" ignite-click="toggle_category_mgmt">&#10005;</button>
        </div>
        <div class="category-panel__body">
          <form class="category-form" ignite-submit="add_category">
            <input class="category-form__input" type="text" name="name" placeholder="New category name..." value="" />
            <button class="btn btn-primary btn-sm" type="submit">Add</button>
          </form>
          <div class="category-list">
            <%= if @categories == [] do %>
              <p class="empty-state__text">No categories yet.</p>
            <% else %>
              <%= for cat <- @categories do %>
                <%= if cat.id == @editing_category_id do %>
                  <div class="category-item">
                    <form class="category-edit-form" ignite-submit="save_category">
                      <input class="category-form__input" type="text" name="name" value="<%= @editing_category_name %>" />
                      <button class="btn btn-primary btn-sm" type="submit">Save</button>
                      <button class="btn btn-ghost btn-sm" type="button" ignite-click="cancel_edit_category">Cancel</button>
                    </form>
                  </div>
                <% else %>
                  <div class="category-item">
                    <span class="category-item__name"><%= cat.name %></span>
                    <div class="category-item__actions">
                      <button class="btn-icon btn-icon--edit" ignite-click="start_edit_category" ignite-value="<%= cat.id %>">&#9998;</button>
                      <button class="btn-icon btn-icon--danger" ignite-click="delete_category" ignite-value="<%= cat.id %>">&#10005;</button>
                    </div>
                  </div>
                <% end %>
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
      """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════════════════

  defp to_html(%Ignite.LiveView.Rendered{statics: statics, dynamics: dynamics}) do
    statics
    |> Enum.zip(dynamics ++ [""])
    |> Enum.map_join(fn {s, d} -> s <> d end)
  end

  defp error_tag(errors, field) do
    case Map.get(errors, field) do
      nil -> ""
      msg -> ~s(<p class="form-error">#{Ignite.LiveView.FEExEngine.escape(msg)}</p>)
    end
  end

  defp error_class(errors, field) do
    if Map.has_key?(errors, field), do: " form-input--error", else: ""
  end

  defp status_display("pending"), do: "Pending"
  defp status_display("in_progress"), do: "In Progress"
  defp status_display("completed"), do: "Completed"
  defp status_display(s), do: s

  defp page_range(_current, total) when total <= 7 do
    Enum.to_list(1..total)
  end

  defp page_range(current, total) do
    cond do
      current <= 3 ->
        Enum.to_list(1..4) ++ [:ellipsis, total]

      current >= total - 2 ->
        [1, :ellipsis] ++ Enum.to_list((total - 3)..total)

      true ->
        [1, :ellipsis, current - 1, current, current + 1, :ellipsis, total]
    end
  end
end
