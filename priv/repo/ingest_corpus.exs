# Script for ingesting corpus files into Arcana
#
#     mix run priv/repo/ingest_corpus.exs
#
# Or specify a specific corpus file:
#
#     mix run priv/repo/ingest_corpus.exs priv/corpus/doctor_who.json

alias Adept.Repo

corpus_file = System.argv() |> List.first() || "priv/corpus/doctor_who.json"

unless File.exists?(corpus_file) do
  IO.puts("Corpus file not found: #{corpus_file}")
  IO.puts("\nRun the scraper first:")
  IO.puts("  mix scrape.tardis_wiki")
  System.halt(1)
end

IO.puts("Loading corpus from #{corpus_file}...")

articles =
  corpus_file
  |> File.read!()
  |> Jason.decode!()

IO.puts("Found #{length(articles)} articles")
IO.puts("\nIngesting into Arcana (collection: doctor-who)...\n")

for {article, index} <- Enum.with_index(articles, 1) do
  title = article["title"]
  content = article["content"]
  url = article["url"]

  # Build metadata
  metadata = %{
    title: title,
    url: url,
    source: article["source"],
    scraped_at: article["scraped_at"]
  }

  case Arcana.ingest(content,
         repo: Repo,
         collection: "doctor-who",
         metadata: metadata,
         format: :text
       ) do
    {:ok, _doc} ->
      IO.puts("  [#{index}/#{length(articles)}] #{title}")

    {:error, reason} ->
      IO.puts("  [#{index}/#{length(articles)}] FAILED: #{title} - #{inspect(reason)}")
  end
end

IO.puts("\nDone! Visit http://localhost:4000/arcana to search Doctor Who content.")
