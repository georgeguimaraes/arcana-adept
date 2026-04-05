defmodule Mix.Tasks.Corpus.Ingest do
  @moduledoc """
  Ingests a JSON corpus file into Arcana.

  ## Usage

      mix corpus.ingest                              # defaults to priv/corpus/doctor_who.json
      mix corpus.ingest priv/corpus/other.json       # specific file
      mix corpus.ingest --collection my-collection   # custom collection name
      mix corpus.ingest --concurrency 32             # override concurrency (default 16)
      mix corpus.ingest --reset                      # wipe existing collection first

  The corpus JSON should be an array of objects with `title`, `url`, `source`,
  `scraped_at`, and `content` fields.
  """

  use Mix.Task

  @default_file "priv/corpus/doctor_who.json"
  @default_collection "doctor-who"

  @impl Mix.Task
  def run(args) do
    Logger.configure(level: :warning)
    Mix.Task.run("app.start")

    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [collection: :string, concurrency: :integer, reset: :boolean]
      )

    corpus_file = List.first(positional) || @default_file
    collection = opts[:collection] || @default_collection
    concurrency = opts[:concurrency] || default_concurrency()
    reset? = opts[:reset] || false

    unless File.exists?(corpus_file) do
      Mix.raise("Corpus file not found: #{corpus_file}")
    end

    if reset? do
      reset_collection(collection)
    end

    Mix.shell().info("Loading corpus from #{corpus_file}...")

    articles =
      corpus_file
      |> File.read!()
      |> Jason.decode!()
      |> Enum.sort_by(&byte_size(&1["content"]))

    total = length(articles)
    Mix.shell().info("Found #{total} articles (sorted shortest-first)")
    {emb_module, _} = Arcana.Config.embedder()

    embedder_label =
      if emb_module == Arcana.Embedder.Local, do: "local (Nx)", else: inspect(emb_module)

    Mix.shell().info(
      "Collection: #{collection}, Embedder: #{embedder_label}, Concurrency: #{concurrency}"
    )

    [first | rest] = articles
    ingest_article(first, collection, "[1/#{total}]")

    Mix.shell().info("\nIngesting with #{concurrency} concurrent tasks...\n")

    counter = :counters.new(1, [:atomics])
    :counters.add(counter, 1, 1)
    failed = :counters.new(1, [:atomics])
    start_time = System.monotonic_time(:second)

    rest
    |> Task.async_stream(
      fn article ->
        result = ingest_article(article, collection)

        :counters.add(counter, 1, 1)
        done = :counters.get(counter, 1)
        log_progress(done, total, start_time)

        case result do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            :counters.add(failed, 1, 1)
            Mix.shell().info("  FAILED: #{article["title"]} - #{inspect(reason)}")
        end
      end,
      max_concurrency: concurrency,
      timeout: :infinity,
      ordered: false
    )
    |> Stream.run()

    elapsed = max(System.monotonic_time(:second) - start_time, 1)
    done = :counters.get(counter, 1)
    fail_count = :counters.get(failed, 1)

    Mix.shell().info("\nDone!")
    Mix.shell().info("Ingested: #{done - fail_count}, Failed: #{fail_count}")

    Mix.shell().info(
      "Time: #{format_duration(elapsed)} (#{Float.round(done / elapsed, 1)} docs/sec)"
    )
  end

  defp ingest_article(article, collection, prefix \\ nil) do
    metadata = %{
      title: article["title"],
      url: article["url"],
      source: article["source"],
      scraped_at: article["scraped_at"]
    }

    result =
      Arcana.ingest(article["content"],
        repo: Adept.Repo,
        collection: collection,
        metadata: metadata,
        format: :plaintext
      )

    if prefix do
      case result do
        {:ok, _} ->
          Mix.shell().info("  #{prefix} #{article["title"]}")

        {:error, reason} ->
          Mix.shell().info("  #{prefix} FAILED: #{article["title"]} - #{inspect(reason)}")
      end
    end

    result
  end

  defp log_progress(done, total, start_time) do
    if rem(done, 500) == 0 do
      elapsed = max(System.monotonic_time(:second) - start_time, 1)
      rate = done / elapsed
      eta_secs = trunc((total - done) / max(rate, 0.01))

      Mix.shell().info(
        "  [#{done}/#{total}] #{Float.round(rate, 1)} docs/sec, ETA: #{format_duration(eta_secs)}"
      )
    end
  end

  defp format_duration(seconds) do
    hrs = div(seconds, 3600)
    mins = div(rem(seconds, 3600), 60)

    cond do
      hrs > 0 -> "#{hrs}h #{mins}m"
      true -> "#{mins}m #{rem(seconds, 60)}s"
    end
  end

  defp default_concurrency do
    case Arcana.Config.embedder() do
      {Arcana.Embedder.Local, _} -> 16
      _ -> 2
    end
  end

  defp reset_collection(collection) do
    import Ecto.Query

    Mix.shell().info("Resetting collection: #{collection}")

    case Adept.Repo.one(
           from c in "arcana_collections", where: c.name == ^collection, select: c.id
         ) do
      nil ->
        Mix.shell().info("  Collection not found, nothing to reset")

      collection_id ->
        doc_ids =
          Adept.Repo.all(
            from d in "arcana_documents",
              where: d.collection_id == ^collection_id,
              select: d.id
          )

        {chunks, _} =
          Adept.Repo.delete_all(from ch in "arcana_chunks", where: ch.document_id in ^doc_ids)

        {docs, _} =
          Adept.Repo.delete_all(
            from d in "arcana_documents", where: d.collection_id == ^collection_id
          )

        {colls, _} =
          Adept.Repo.delete_all(from c in "arcana_collections", where: c.id == ^collection_id)

        Mix.shell().info("  Deleted #{chunks} chunks, #{docs} documents, #{colls} collection")
    end
  end
end
