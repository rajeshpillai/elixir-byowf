defmodule MyApp.UserController do
  @moduledoc """
  Handles user CRUD operations backed by SQLite via Ecto.
  """

  import Ignite.Controller
  alias MyApp.{Repo, User}

  def index(conn) do
    users = Repo.all(User)

    data =
      Enum.map(users, fn u ->
        %{id: u.id, username: u.username, email: u.email}
      end)

    json(conn, %{users: data})
  end

  def show(conn) do
    user_id = conn.params[:id]

    case Repo.get(User, user_id) do
      nil ->
        json(conn, %{error: "User not found"}, 404)

      user ->
        render(conn, "profile",
          name: user.username,
          id: user.id,
          email: user.email || "N/A"
        )
    end
  end

  def create(conn) do
    attrs = %{
      username: conn.params["username"] || "",
      email: conn.params["email"]
    }

    changeset = User.changeset(%User{}, attrs)

    case Repo.insert(changeset) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "User '#{user.username}' created!")
        |> redirect(to: "/")

      {:error, changeset} ->
        errors = format_errors(changeset)

        conn
        |> put_flash(:error, "Failed to create user: #{errors}")
        |> redirect(to: "/")
    end
  end

  def update(conn) do
    user_id = conn.params[:id]

    case Repo.get(User, user_id) do
      nil ->
        json(conn, %{error: "User not found"}, 404)

      user ->
        attrs = %{
          username: conn.params["username"],
          email: conn.params["email"]
        }

        changeset = User.changeset(user, attrs)

        case Repo.update(changeset) do
          {:ok, updated} ->
            json(conn, %{updated: true, id: updated.id, username: updated.username})

          {:error, changeset} ->
            errors = format_errors(changeset)
            json(conn, %{error: errors}, 422)
        end
    end
  end

  def delete(conn) do
    user_id = conn.params[:id]

    case Repo.get(User, user_id) do
      nil ->
        json(conn, %{error: "User not found"}, 404)

      user ->
        {:ok, _deleted} = Repo.delete(user)
        json(conn, %{deleted: true, id: user.id})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join(", ", fn {field, msgs} ->
      "#{field} #{Enum.join(msgs, ", ")}"
    end)
  end
end
