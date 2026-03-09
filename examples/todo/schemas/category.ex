defmodule TodoApp.Category do
  use Ecto.Schema
  import Ecto.Changeset

  schema "todo_categories" do
    field :name, :string
    timestamps()
  end

  def changeset(category, attrs) do
    category
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end
end
