defmodule Examples.TodoE2ETest do
  @moduledoc """
  End-to-end exercise of the Step 43 capstone (examples/todo).

  There were no tests for the Todo app. These drive the real LiveView through
  its full feature set against the live (migrated) test database: auth, CRUD,
  edit/delete, categories, bulk actions, filter/search/pagination, bookmarks,
  and subtasks (including parent auto-completion). It also confirms the ~F
  migration (review item A2) escapes a todo title in the actual capstone.

  Every event is driven through `TodoApp.TodoLive.handle_event/3` exactly as the
  WebSocket handler would, and the whole view is re-rendered after each group to
  prove `render/1` never crashes for that state.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias MyApp.Repo
  alias TodoApp.{User, TodoItem, Category, Subtask}
  alias Ignite.LiveView.Engine

  @email_prefix "e2e_todo_"
  @category_prefix "e2e_cat_"

  setup do
    on_exit(&cleanup/0)
    :ok
  end

  defp cleanup do
    user_ids = Repo.all(from u in User, where: like(u.email, ^"#{@email_prefix}%"), select: u.id)
    todo_ids = Repo.all(from t in TodoItem, where: t.user_id in ^user_ids, select: t.id)

    if todo_ids != [], do: Repo.delete_all(from s in Subtask, where: s.todo_id in ^todo_ids)
    if user_ids != [], do: Repo.delete_all(from t in TodoItem, where: t.user_id in ^user_ids)
    if user_ids != [], do: Repo.delete_all(from u in User, where: u.id in ^user_ids)
    Repo.delete_all(from c in Category, where: like(c.name, ^"#{@category_prefix}%"))
  end

  # ── Helpers ────────────────────────────────────────────────────────

  defp render_html(assigns) do
    {statics, dynamics} = Engine.render(TodoApp.TodoLive, assigns)

    statics
    |> Enum.zip(dynamics ++ [""])
    |> Enum.map_join("", fn {s, d} -> s <> flatten(d) end)
  end

  defp flatten(d) when is_list(d), do: Enum.map_join(d, "", &flatten/1)
  defp flatten(d), do: to_string(d)

  defp unique_email, do: "#{@email_prefix}#{System.unique_integer([:positive])}@test.dev"

  # Dispatch an event the way the handler does, asserting the {:noreply, _} shape.
  defp ev(assigns, event, params) do
    assert {:noreply, new_assigns} = TodoApp.TodoLive.handle_event(event, params, assigns)
    new_assigns
  end

  defp logged_in do
    {:ok, assigns} = TodoApp.TodoLive.mount(%{}, %{})

    assigns =
      ev(assigns, "register", %{
        "username" => "E2E User",
        "email" => unique_email(),
        "password" => "password123"
      })

    assert assigns.current_user != nil, "registration should log the user in"
    assigns
  end

  defp add(assigns, title, category_id \\ ""),
    do: ev(assigns, "add_todo", %{"title" => title, "category_id" => category_id})

  defp find_todo(assigns, title), do: Enum.find(assigns.todos, &(&1.title == title))

  # ── Tests ──────────────────────────────────────────────────────────

  test "logged-out mount renders the auth screen without touching the DB" do
    {:ok, assigns} = TodoApp.TodoLive.mount(%{}, %{})

    assert assigns.current_user == nil
    html = render_html(assigns)
    assert html =~ "Welcome Back"
    assert html =~ "password"
  end

  test "register -> add todo -> render (escaped) -> cycle status" do
    assigns = logged_in()
    user_id = assigns.current_user.id
    assert render_html(assigns) =~ "Todo App"

    xss = "<script>alert('xss')</script>"
    assigns = add(assigns, xss)

    todo = Repo.one(from t in TodoItem, where: t.user_id == ^user_id)
    assert todo.title == xss
    assert todo.status == "pending"

    html = render_html(assigns)
    refute html =~ "<script>alert", "title must not render as a live script tag"
    assert html =~ "&lt;script&gt;", "title should be HTML-escaped by ~F"

    assigns = ev(assigns, "cycle_status", %{"value" => to_string(todo.id)})
    assert Repo.get(TodoItem, todo.id).status == "in_progress"
    assert render_html(assigns) =~ "Todo App"
  end

  test "edit and delete a todo" do
    assigns = logged_in()
    assigns = add(assigns, "Original title")
    todo = find_todo(assigns, "Original title")

    # Edit
    assigns = ev(assigns, "start_edit", %{"value" => to_string(todo.id)})
    assert assigns.editing_id == todo.id
    assigns = ev(assigns, "save_edit", %{"title" => "Edited title"})
    assert assigns.editing_id == nil
    assert Repo.get(TodoItem, todo.id).title == "Edited title"
    assert render_html(assigns) =~ "Edited title"

    # Delete (with confirm step)
    assigns = ev(assigns, "confirm_delete", %{"value" => to_string(todo.id)})
    assert assigns.confirm_delete_id == todo.id
    assigns = ev(assigns, "delete_todo", %{"value" => to_string(todo.id)})

    assert Repo.get(TodoItem, todo.id) == nil
    assert assigns.todos == []
    assert render_html(assigns) =~ "Todo App"
  end

  test "categories: create, assign, filter, rename, delete" do
    assigns = logged_in()

    # Create a category
    assigns = ev(assigns, "add_category", %{"name" => "#{@category_prefix}Work"})
    cat = Enum.find(assigns.categories, &(&1.name == "#{@category_prefix}Work"))
    assert cat, "category should be created and loaded"

    # Assign a todo to it
    assigns = add(assigns, "Categorized todo", to_string(cat.id))
    todo = find_todo(assigns, "Categorized todo")
    assert todo.category_id == cat.id
    assert render_html(assigns) =~ "#{@category_prefix}Work"

    # Filter by the category — the todo stays visible
    assigns = ev(assigns, "change", %{"field" => "category_filter", "value" => to_string(cat.id)})
    assert find_todo(assigns, "Categorized todo")

    # Filter by a non-matching category — the todo is hidden
    assigns = ev(assigns, "change", %{"field" => "category_filter", "value" => to_string(cat.id + 99_999)})
    assert assigns.todos == []

    # Clear the filter, then rename the category
    assigns = ev(assigns, "change", %{"field" => "category_filter", "value" => ""})
    assigns = ev(assigns, "start_edit_category", %{"value" => to_string(cat.id)})
    assigns = ev(assigns, "save_category", %{"name" => "#{@category_prefix}Renamed"})
    assert Repo.get(Category, cat.id).name == "#{@category_prefix}Renamed"

    # Delete the category
    assigns = ev(assigns, "delete_category", %{"value" => to_string(cat.id)})
    assert Repo.get(Category, cat.id) == nil
    refute Enum.any?(assigns.categories, &(&1.id == cat.id))
    assert render_html(assigns) =~ "Todo App"
  end

  test "bulk select then bulk-complete and bulk-delete" do
    assigns = logged_in()
    user_id = assigns.current_user.id

    assigns = add(assigns, "Bulk A")
    assigns = add(assigns, "Bulk B")
    assigns = add(assigns, "Bulk C")
    assert length(assigns.todos) == 3

    # Select all, then complete all
    assigns = ev(assigns, "toggle_select_all", %{})
    assert MapSet.size(assigns.selected_ids) == 3
    assigns = ev(assigns, "bulk_action", %{"action" => "completed"})

    completed = Repo.aggregate(from(t in TodoItem, where: t.user_id == ^user_id and t.status == "completed"), :count)
    assert completed == 3
    assert MapSet.size(assigns.selected_ids) == 0

    # Select all again, then delete all
    assigns = ev(assigns, "toggle_select_all", %{})
    assigns = ev(assigns, "bulk_action", %{"action" => "delete"})

    assert Repo.aggregate(from(t in TodoItem, where: t.user_id == ^user_id), :count) == 0
    assert render_html(assigns) =~ "Todo App"
  end

  test "filter, search, and pagination" do
    assigns = logged_in()

    assigns = add(assigns, "buy milk")
    assigns = add(assigns, "buy eggs")
    assigns = add(assigns, "call dentist")
    assert assigns.total_count == 3

    # Search narrows by title (LIKE)
    assigns = ev(assigns, "search", %{"search" => "buy"})
    assert assigns.total_count == 2
    assert Enum.all?(assigns.todos, &String.contains?(&1.title, "buy"))

    assigns = ev(assigns, "clear_search", %{})
    assert assigns.total_count == 3

    # Status filter
    target = find_todo(assigns, "call dentist")
    assigns = ev(assigns, "cycle_status", %{"value" => to_string(target.id)})
    assigns = ev(assigns, "set_filter", %{"value" => "in_progress"})
    assert assigns.total_count == 1
    assert hd(assigns.todos).title == "call dentist"

    # Pagination: 3 todos, 2 per page
    assigns = ev(assigns, "set_filter", %{"value" => "all"})
    assigns = ev(assigns, "change", %{"field" => "per_page", "value" => "2"})
    assert assigns.total_count == 3
    assert length(assigns.todos) == 2
    assert assigns.page == 1

    assigns = ev(assigns, "set_page", %{"value" => "2"})
    assert assigns.page == 2
    assert length(assigns.todos) == 1
    assert render_html(assigns) =~ "Todo App"
  end

  test "bookmark a todo and filter by bookmarked" do
    assigns = logged_in()
    assigns = add(assigns, "Important todo")
    assigns = add(assigns, "Normal todo")
    todo = find_todo(assigns, "Important todo")

    assigns = ev(assigns, "toggle_bookmark", %{"value" => to_string(todo.id)})
    assert Repo.get(TodoItem, todo.id).bookmarked == true

    assigns = ev(assigns, "toggle_bookmarked_filter", %{})
    assert assigns.show_bookmarked == true
    assert length(assigns.todos) == 1
    assert hd(assigns.todos).title == "Important todo"

    # Toggling the filter off shows everything again
    assigns = ev(assigns, "toggle_bookmarked_filter", %{})
    assert assigns.show_bookmarked == false
    assert assigns.total_count == 2
    assert render_html(assigns) =~ "Todo App"
  end

  test "subtasks: add, toggle (auto-completes parent), delete" do
    assigns = logged_in()
    assigns = add(assigns, "Parent todo")
    todo = find_todo(assigns, "Parent todo")

    # Open the subtask panel for this todo
    assigns = ev(assigns, "show_subtasks", %{"value" => to_string(todo.id)})
    assert assigns.active_todo_id == todo.id

    assigns = ev(assigns, "add_subtask", %{"title" => "Step one"})
    assigns = ev(assigns, "add_subtask", %{"title" => "Step two"})
    assert length(assigns.subtasks) == 2
    assert render_html(assigns) =~ "Step one"

    # Complete both subtasks → parent auto-completes
    [s1, s2] = assigns.subtasks
    assigns = ev(assigns, "toggle_subtask", %{"value" => to_string(s1.id)})
    assigns = ev(assigns, "toggle_subtask", %{"value" => to_string(s2.id)})
    assert Enum.all?(assigns.subtasks, &(&1.status == "completed"))
    assert Repo.get(TodoItem, todo.id).status == "completed", "parent should auto-complete"

    # Delete one subtask
    assigns = ev(assigns, "delete_subtask", %{"value" => to_string(s1.id)})
    assert length(assigns.subtasks) == 1
    assert Repo.get(Subtask, s1.id) == nil
    assert render_html(assigns) =~ "Todo App"
  end
end
