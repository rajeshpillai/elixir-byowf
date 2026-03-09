defmodule MyApp.Repo.Migrations.CreateTodoAppTables do
  use Ecto.Migration

  def change do
    create table(:todo_categories) do
      add :name, :string, null: false
      timestamps()
    end

    create table(:todo_users) do
      add :username, :string, null: false
      add :email, :string, null: false
      add :password_hash, :string, null: false
      timestamps()
    end

    create unique_index(:todo_users, [:email])

    create table(:todo_items) do
      add :title, :string, null: false
      add :status, :string, default: "pending"
      add :bookmarked, :boolean, default: false
      add :user_id, references(:todo_users, on_delete: :delete_all)
      add :category_id, references(:todo_categories, on_delete: :nilify_all)
      timestamps()
    end

    create index(:todo_items, [:user_id])
    create index(:todo_items, [:category_id])

    create table(:todo_subtasks) do
      add :title, :string, null: false
      add :status, :string, default: "pending"
      add :todo_id, references(:todo_items, on_delete: :delete_all)
      timestamps()
    end

    create index(:todo_subtasks, [:todo_id])
  end
end
