defmodule Adept.Repo.Migrations.AddArcanaCollections do
  use Ecto.Migration

  def up do
    create table(:arcana_collections, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:description, :text)

      timestamps()
    end

    create(unique_index(:arcana_collections, [:name]))

    alter table(:arcana_documents) do
      add(
        :collection_id,
        references(:arcana_collections, type: :binary_id, on_delete: :nilify_all)
      )
    end

    create(index(:arcana_documents, [:collection_id]))
  end

  def down do
    drop(index(:arcana_documents, [:collection_id]))

    alter table(:arcana_documents) do
      remove(:collection_id)
    end

    drop(table(:arcana_collections))
  end
end
