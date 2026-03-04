defmodule MyApp.User do
  @moduledoc """
  The User schema — maps to the `users` database table.

  Defines the fields and validations for user records.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :email, :string

    timestamps()
  end

  @doc """
  Validates user input for create and update operations.

  Requires `:username`, validates length, and ensures uniqueness
  (at the database level via the migration's unique index).
  """
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email])
    |> validate_required([:username])
    |> validate_length(:username, min: 2, max: 50)
    |> unique_constraint(:username)
  end
end
