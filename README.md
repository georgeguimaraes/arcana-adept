# Arcana Adept

A complete example Phoenix application demonstrating [Arcana](https://github.com/georgeguimaraes/arcana) - a RAG (Retrieval-Augmented Generation) toolkit for Elixir.

## What's Included

- Pre-configured Arcana with pgvector
- Sample Elixir/Phoenix documentation ingested
- Dashboard at `/arcana` for managing documents and searching
- Evaluation system with test cases

## Quick Start

### Prerequisites

- Elixir 1.15+
- PostgreSQL with pgvector extension
- (Optional) Ollama or OpenAI API key for LLM features

### Setup

```bash
# Clone the repo
git clone https://github.com/georgeguimaraes/arcana-adept.git
cd arcana-adept

# Install dependencies and set up database
mix setup

# Start the server
mix phx.server
```

Visit [http://localhost:4000/arcana](http://localhost:4000/arcana) to see the dashboard.

## Features Demonstrated

### Document Ingestion

The seeds file ingests sample Elixir documentation organized into collections:

```elixir
# Ingest into a collection
Arcana.ingest(content, repo: Repo, collection: "elixir-guides")

# Ingest with metadata
Arcana.ingest(content, repo: Repo, metadata: %{author: "José Valim"})
```

### Semantic Search

Search your documents using natural language:

```elixir
# Basic search
results = Arcana.search("How do I handle state in Elixir?", repo: Repo)

# Search within a collection
results = Arcana.search("pattern matching", repo: Repo, collection: "elixir-guides")

# Hybrid search (semantic + full-text)
results = Arcana.search("GenServer callbacks", repo: Repo, mode: :hybrid)
```

### RAG Question Answering

Get AI-powered answers grounded in your documents:

```elixir
{:ok, answer} = Arcana.ask(
  "What are the key features of Phoenix LiveView?",
  repo: Repo,
  llm: Application.get_env(:arcana, :llm)
)
```

### Evaluation

Measure and improve retrieval quality:

```elixir
# Generate test cases from your documents
{:ok, test_cases} = Arcana.Evaluation.generate_test_cases(
  repo: Repo,
  llm: Application.get_env(:arcana, :llm),
  sample_size: 20,
  collection: "elixir-guides"
)

# Run evaluation
{:ok, run} = Arcana.Evaluation.run(repo: Repo, mode: :semantic)

# Check metrics
run.metrics
# => %{mrr: 0.76, recall_at_5: 0.84, precision_at_5: 0.68, hit_rate_at_5: 0.91}

# Evaluate answer quality too
{:ok, run} = Arcana.Evaluation.run(
  repo: Repo,
  mode: :semantic,
  evaluate_answers: true,
  llm: Application.get_env(:arcana, :llm)
)

run.metrics.faithfulness  # => 7.8 (0-10 scale)
```

## Configuration

### Basic Setup (config/dev.exs)

```elixir
config :arcana,
  repo: MyApp.Repo,
  embedding: [
    model: "BAAI/bge-small-en-v1.5",
    dimensions: 384
  ]
```

### With LLM for RAG and Evaluation

```elixir
# Using Ollama (local)
config :arcana,
  repo: MyApp.Repo,
  llm: fn prompt, _context ->
    # Your Ollama integration
    {:ok, response}
  end

# Using OpenAI
config :arcana,
  repo: MyApp.Repo,
  llm: fn prompt, _context ->
    # Your OpenAI integration
    {:ok, response}
  end
```

## Dashboard

The Arcana dashboard at `/arcana` provides:

- **Documents** - View, upload, and manage ingested documents
- **Search** - Test semantic, full-text, and hybrid search
- **Collections** - Organize documents into collections
- **Evaluation** - Generate test cases and run evaluations

## Project Structure

```
lib/
├── adept/
│   ├── repo.ex          # Ecto repo with pgvector types
│   └── postgrex_types.ex # pgvector type configuration
├── adept_web/
│   └── router.ex        # Mounts arcana_dashboard("/arcana")
config/
└── dev.exs              # Arcana configuration
priv/
└── repo/
    ├── migrations/      # Arcana tables + pgvector
    └── seeds.exs        # Sample document ingestion
```

## Learn More

- [Arcana Documentation](https://github.com/georgeguimaraes/arcana)
- [Arcana Evaluation Guide](https://github.com/georgeguimaraes/arcana/blob/main/guides/evaluation.md)
- [Phoenix Framework](https://www.phoenixframework.org/)
