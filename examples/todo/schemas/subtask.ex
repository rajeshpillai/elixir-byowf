defmodule TodoApp.Subtask do
  use Ecto.Schema
  import Ecto.Changeset

  schema "todo_subtasks" do
    field :title, :string
    field :status, :string, default: "pending"
    belongs_to :todo, TodoApp.TodoItem
    timestamps()
  end

  def changeset(subtask, attrs) do
    subtask
    |> cast(attrs, [:title, :status, :todo_id])
    |> validate_required([:title, :todo_id])
    |> validate_inclusion(:status, ["pending", "completed"])
  end
end
