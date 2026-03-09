defmodule TodoApp.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "todo_users" do
    field :username, :string
    field :email, :string
    field :password_hash, :string
    field :password, :string, virtual: true
    timestamps()
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :email, :password])
    |> validate_required([:username, :email, :password])
    |> validate_length(:username, min: 2, max: 50)
    |> validate_format(:email, ~r/@/)
    |> validate_length(:password, min: 6)
    |> unique_constraint(:email)
    |> hash_password()
  end

  def verify_password(user, password) do
    hash =
      :crypto.hash(:sha256, "ignite_todo_salt:" <> password)
      |> Base.encode16(case: :lower)

    Plug.Crypto.secure_compare(hash, user.password_hash)
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        hash =
          :crypto.hash(:sha256, "ignite_todo_salt:" <> password)
          |> Base.encode16(case: :lower)

        put_change(changeset, :password_hash, hash)
    end
  end
end
