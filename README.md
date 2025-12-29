# Arcana Adept

Example Phoenix app demonstrating [Arcana](https://github.com/georgeguimaraes/arcana) - an embeddable RAG library for Elixir.

Includes a Doctor Who corpus (452 articles from TARDIS Wiki) ready to embed and query.

## Quick Start

```bash
# Clone and setup
git clone https://github.com/georgeguimaraes/arcana-adept.git
cd arcana-adept
mix setup

# Start the server
mix phx.server
```

Visit [localhost:4000/arcana](http://localhost:4000/arcana) to access the dashboard.

## Embedding the Doctor Who Corpus

The Doctor Who corpus is at `priv/corpus/doctor_who.json`. Embed it with:

```elixir
# In IEx (iex -S mix)
alias Adept.Repo

"priv/corpus/doctor_who.json"
|> File.read!()
|> Jason.decode!()
|> Enum.each(fn %{"title" => title, "content" => content} ->
  {:ok, _} = Arcana.ingest(content,
    repo: Repo,
    collection: "doctor-who",
    metadata: %{"title" => title}
  )
  IO.puts("Ingested: #{title}")
end)
```

Then search:

```elixir
Arcana.search("Who is the Doctor?", repo: Repo, collection: "doctor-who")
```

## Dashboard

The Arcana dashboard at `/arcana` provides:

- **Documents** - View and manage ingested documents
- **Search** - Test semantic, full-text, and hybrid search
- **Ask** - RAG-powered question answering (requires LLM config)
- **Collections** - Organize documents by topic
- **Evaluation** - Measure retrieval quality

## License

Apache-2.0 - See [LICENSE](LICENSE)
