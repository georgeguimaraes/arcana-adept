defmodule Adept.Repo.Migrations.AddCommunitiesEntityIdsGinIndex do
  use Ecto.Migration

  # Arcana's installer (mix arcana.graph.install) now ships this index
  # directly, so a fresh setup creates it before this migration runs.
  # IF NOT EXISTS keeps the migration idempotent for those installs,
  # and CONCURRENTLY avoids an ACCESS EXCLUSIVE lock on
  # arcana_graph_communities in prod for installs that pre-date the
  # installer change.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("""
    CREATE INDEX CONCURRENTLY IF NOT EXISTS arcana_graph_communities_entity_ids_idx
    ON arcana_graph_communities
    USING gin (entity_ids)
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS arcana_graph_communities_entity_ids_idx")
  end
end
