defmodule TodoApp.TodoItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "todo_items" do
    field :title, :string
    field :status, :string, default: "pending"
    field :bookmarked, :boolean, default: false
    belongs_to :user, TodoApp.User
    belongs_to :category, TodoApp.Category
    has_many :subtasks, TodoApp.Subtask, foreign_key: :todo_id
    timestamps()
  end

  def changeset(todo, attrs) do
    todo
    |> cast(attrs, [:title, :status, :bookmarked, :user_id, :category_id])
    |> validate_required([:title, :user_id])
    |> validate_inclusion(:status, ["pending", "in_progress", "completed"])
  end
end
