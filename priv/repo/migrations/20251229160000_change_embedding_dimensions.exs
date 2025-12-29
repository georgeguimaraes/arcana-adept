defmodule Adept.Repo.Migrations.ChangeEmbeddingDimensions do
  use Ecto.Migration

  def up do
    # Drop the HNSW index first
    execute "DROP INDEX IF EXISTS arcana_chunks_embedding_idx"

    # Clear existing embeddings (they're incompatible with new dimensions)
    # CASCADE needed because arcana_evaluation_test_cases references arcana_chunks
    execute "TRUNCATE arcana_chunks CASCADE"
    execute "UPDATE arcana_documents SET status = 'pending', chunk_count = 0"

    # Change vector column from 384 to 1536 dimensions
    execute "ALTER TABLE arcana_chunks ALTER COLUMN embedding TYPE vector(1536)"

    # Recreate the HNSW index
    execute """
    CREATE INDEX arcana_chunks_embedding_idx ON arcana_chunks
    USING hnsw (embedding vector_cosine_ops)
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS arcana_chunks_embedding_idx"
    execute "TRUNCATE arcana_chunks CASCADE"
    execute "UPDATE arcana_documents SET status = 'pending', chunk_count = 0"
    execute "ALTER TABLE arcana_chunks ALTER COLUMN embedding TYPE vector(384)"

    execute """
    CREATE INDEX arcana_chunks_embedding_idx ON arcana_chunks
    USING hnsw (embedding vector_cosine_ops)
    """
  end
end
