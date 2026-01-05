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

## Nx Backend

This app uses [EXLA](https://hexdocs.pm/exla) for local embeddings. On Apple Silicon, you can use [EMLX](https://github.com/elixir-nx/emlx) instead:

```elixir
# mix.exs
{:emlx, "~> 0.1"}  # instead of {:exla, "~> 0.9"}

# config/config.exs
config :nx,
  default_backend: EMLX.Backend,
  default_defn_options: [compiler: EMLX]
```

Visit [localhost:4000/arcana](http://localhost:4000/arcana) to access the dashboard.

## Embedding the Doctor Who Corpus

The Doctor Who corpus is at `priv/corpus/doctor_who.json`. Embed it with:

```elixir
# In IEx (iex -S mix)
alias Adept.Repo

"priv/corpus/doctor_who.json"
|> File.read!()
|> JSON.decode!()
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

## GraphRAG

Build a knowledge graph from the corpus for enhanced retrieval:

```bash
# Install graph tables (first time only)
mix arcana.graph.install
mix ecto.migrate

# Rebuild graph (extracts entities and relationships)
mix arcana.graph.rebuild --collection doctor-who

# Detect communities (recommended settings for Doctor Who corpus)
mix arcana.graph.detect_communities --collection doctor-who --resolution 1.0 --max-level 5

# Generate community summaries (requires LLM config)
mix arcana.graph.summarize_communities --collection doctor-who
```

The Doctor Who corpus works well with:
- **Resolution 1.0** - Balances community size (higher values fragment into smaller groups)
- **Max level 5** - Allows for hierarchy (actual levels depend on graph structure)

## Dashboard

The Arcana dashboard at `/arcana` provides:

- **Documents** - View and manage ingested documents
- **Search** - Test semantic, full-text, and hybrid search
- **Ask** - RAG-powered question answering (requires LLM config)
- **Collections** - Organize documents by topic
- **Evaluation** - Measure retrieval quality

## License

Apache-2.0 - See [LICENSE](LICENSE)
