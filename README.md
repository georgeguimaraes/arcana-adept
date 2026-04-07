# Arcana Adept

Example Phoenix app demonstrating [Arcana](https://github.com/georgeguimaraes/arcana) - an embeddable RAG library for Elixir.

Includes a Doctor Who corpus (108K+ articles from TARDIS Wiki) ready to embed and query.

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

## Corpus Management

### Parsing the dump

A MediaWiki XML dump is included at `priv/corpus/tardis_pages_current.xml.7z` (94MB).
Parse it into the JSON corpus (accepts `.7z`, `.gz`, or `.xml` directly):

```bash
mix corpus.parse priv/corpus/tardis_pages_current.xml.7z
```

To download a fresh dump from Fandom's S3:

```bash
curl -L -o priv/corpus/tardis_pages_current.xml.7z \
  "https://s3.amazonaws.com/wikia_xml_dumps/t/ta/tardis_pages_current.xml.7z"
```

### Ingesting the corpus

Ingest the JSON corpus into Arcana with parallel embedding:

```bash
# Ingest the default corpus (priv/corpus/doctor_who.json)
mix corpus.ingest

# Ingest a specific file
mix corpus.ingest priv/corpus/other.json

# Options
mix corpus.ingest --collection my-collection  # custom collection name
mix corpus.ingest --concurrency 32            # override concurrency (default 16)
mix corpus.ingest --reset                     # wipe existing collection first
```

### Searching

```elixir
Arcana.search("Who is the Doctor?", repo: Adept.Repo, collection: "doctor-who")
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

## TODO

Known gaps based on current RAG research (see [evaluation baseline](docs/evaluation-baseline.md) for measurements):

- [x] **Community summaries in ask pipeline**: injected as "background knowledge" in the LLM prompt alongside retrieved chunks
- [x] **Cross-encoder reranking**: `Arcana.Reranker.CrossEncoder` using ms-marco-MiniLM-L-6-v2 via Bumblebee. MRR +39%, Hit@1 +62%
- [x] **Evaluation baselines**: 60 synthetic test cases, comparing vector-only, vector+graph, and vector+graph+reranker
- [ ] **Upgrade embedding model**: BGE-small-en-v1.5 (~51 MTEB) is dated. `nomic-embed-text-v1.5` (~55 MTEB) works with Bumblebee from git (NomicBert support not yet in a hex release). Requires re-embedding
- [ ] **HyDE for broad queries**: generate hypothetical answer, embed that, search with it. Bridges vocabulary gap between questions and wiki content
- [ ] **Graph config docs**: `docs/graph.md` with full config reference for all tunable parameters

## References

Papers and resources that informed the GraphRAG pipeline and retrieval strategy:

- [From Local to Global: A Graph RAG Approach to Query-Focused Summarization](https://arxiv.org/abs/2404.16130) (Microsoft, 2024) — community summaries for global search over knowledge graphs
- [Lost in the Middle: How Language Models Use Long Contexts](https://arxiv.org/abs/2307.03172) (Liu et al., 2023) — context ordering matters for LLM retrieval
- [HopRAG: Multi-Hop Reasoning for Knowledge-Aware RAG](https://arxiv.org/abs/2502.12442) (ACL 2025) — graph traversal with LLM-guided pruning
- [RAGAS: Automated Evaluation of Retrieval Augmented Generation](https://arxiv.org/abs/2309.15217) (Shahul et al., 2023) — faithfulness, relevance, and context metrics
- [Graph Retrieval-Augmented Generation: A Survey](https://arxiv.org/abs/2408.08921) (2024) — comprehensive survey of Graph RAG approaches
- [RAG vs. GraphRAG: A Systematic Evaluation](https://arxiv.org/abs/2502.11371) (2025) — when graph-enhanced retrieval helps vs plain RAG
- [Precise Zero-Shot Dense Retrieval without Relevance Labels (HyDE)](https://arxiv.org/abs/2212.10496) (Gao et al., 2022) — hypothetical document embeddings for query expansion
- [LettuceDetect: A Hallucination Detector for RAG](https://arxiv.org/abs/2502.17125) (2025) — token-level grounding for faithfulness checking
- [Agentic RAG with Knowledge Graphs](https://arxiv.org/abs/2507.16507) (2025) — iterative retrieval and reasoning over graph structures

## License

Apache-2.0 - See [LICENSE](LICENSE)
