defmodule Adept.Repo.Migrations.AddCommunitiesEntityIdsGinIndex do
  use Ecto.Migration

  def up do
    execute("""
    CREATE INDEX arcana_graph_communities_entity_ids_idx ON arcana_graph_communities
    USING gin (entity_ids)
    """)
  end

  def down do
    execute("DROP INDEX arcana_graph_communities_entity_ids_idx")
  end
end
