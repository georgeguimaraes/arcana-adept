# One-off script to backfill entity embeddings using direct Bumblebee/EMLX inference
# Run with: mix run scripts/backfill_entity_embeddings.exs

Logger.configure(level: :warning)

import Ecto.Query
alias Arcana.Graph.Entity

IO.puts("Loading model...")
{:ok, model_info} = Bumblebee.load_model({:hf, "BAAI/bge-small-en-v1.5"})
{:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "BAAI/bge-small-en-v1.5"})

IO.puts("Backend: #{inspect(Nx.default_backend())}")

# Get collection
collection_id =
  Adept.Repo.one(from(c in Arcana.Collection, where: c.name == "doctor-who", select: c.id))

# Get entities without embeddings
IO.puts("Loading entities...")

entities =
  Adept.Repo.all(
    from(e in Entity,
      where: e.collection_id == ^collection_id and is_nil(e.embedding),
      order_by: e.id,
      select: %{id: e.id, name: e.name, description: e.description}
    )
  )

total = length(entities)
IO.puts("#{total} entities to embed")

batch_size = 64

start_time = System.monotonic_time(:millisecond)

entities
|> Enum.chunk_every(batch_size)
|> Enum.with_index()
|> Enum.each(fn {batch, batch_idx} ->
  texts =
    Enum.map(batch, fn entity ->
      case entity.description do
        nil -> entity.name
        "" -> entity.name
        desc -> "#{entity.name}: #{desc}"
      end
    end)

  inputs = Bumblebee.apply_tokenizer(tokenizer, texts)
  %{pooled_state: pooled} = Axon.predict(model_info.model, model_info.params, inputs)

  # Convert to list of vectors and L2-normalize (BGE expects normalized embeddings)
  embeddings =
    pooled
    |> Nx.to_list()
    |> Enum.map(fn vec ->
      norm = vec |> Enum.map(&(&1 * &1)) |> Enum.sum() |> :math.sqrt()
      Enum.map(vec, &(&1 / norm))
    end)

  now = NaiveDateTime.utc_now()

  # Concurrent DB updates so we don't bottleneck on sequential writes
  Enum.zip(batch, embeddings)
  |> Task.async_stream(
    fn {entity, embedding} ->
      Adept.Repo.update_all(
        from(e in Entity, where: e.id == ^entity.id),
        set: [embedding: embedding, updated_at: now]
      )
    end,
    max_concurrency: 16,
    timeout: :infinity
  )
  |> Stream.run()

  count = (batch_idx + 1) * batch_size

  if rem(batch_idx, 10) == 0 do
    elapsed = (System.monotonic_time(:millisecond) - start_time) / 1000
    rate = count / elapsed
    eta = (total - count) / rate
    IO.puts("  [#{count}/#{total}] #{Float.round(rate, 1)}/sec, ETA: #{div(round(eta), 60)}m")
  end
end)

IO.puts("Done!")
