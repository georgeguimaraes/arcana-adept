defmodule Adept.Repo.Migrations.ConvertEntityTypeToString do
  use Ecto.Migration

  def up do
    # Convert ENUM column to string
    execute """
    ALTER TABLE arcana_graph_entities
    ALTER COLUMN type TYPE varchar(255)
    USING type::varchar(255)
    """

    # Drop the enum type
    execute "DROP TYPE arcana_entity_type"
  end

  def down do
    # Recreate the enum type
    execute """
    CREATE TYPE arcana_entity_type AS ENUM (
      'person', 'organization', 'location', 'event',
      'concept', 'technology', 'other'
    )
    """

    # Convert back to enum (will fail if any values don't match)
    execute """
    ALTER TABLE arcana_graph_entities
    ALTER COLUMN type TYPE arcana_entity_type
    USING type::arcana_entity_type
    """
  end
end
