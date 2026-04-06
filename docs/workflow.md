# TARDIS Wiki GraphRAG Pipeline

Full workflow for ingesting the TARDIS Wiki (Doctor Who) corpus into Arcana with GraphRAG.

## Source Data

MediaWiki XML dump: `tardis_pages_current.xml.7z` (~1.2GB uncompressed)

## 1. Corpus Parsing

```bash
mix corpus.parse
```

Parses the MediaWiki XML dump into a JSON corpus file, stripping wiki markup and filtering out redirects/disambiguation pages.

- **108,974 articles** extracted
- Output: `priv/corpus/doctor_who.json`

## 2. Document Ingestion

```bash
mix corpus.ingest
```

Chunks each article, generates embeddings locally, and stores everything in Postgres with pgvector.

- **108,974 documents** ingested
- **174,213 chunks** created and embedded (BAAI/bge-small-en-v1.5)
- ~11.5 hours, 2.6 docs/sec

## 3. Graph Extraction

```bash
ARCANA_LLM=glm-4-32b-0414-128k mix arcana.graph.rebuild --collection doctor-who --concurrency 15 --resume
```

Uses an LLM to extract entities and relationships from every chunk. The `--resume` flag skips already-processed chunks, useful since the process crashed a few times on malformed LLM output.

- **362,528 entities** (persons, locations, organizations, media, concepts)
- **2,013,123 relationships**
- Model: GLM-4-32B at $0.10/1M tokens, ~$18 total
- Concurrency 15 (Z.ai rate limit for this model)

## 4. Community Detection

```bash
mix arcana.graph.detect_communities --collection doctor-who
```

Runs the Leiden algorithm to cluster related entities into communities. Config in `runtime.exs` sets resolution=0.25, min_size=10, community_levels=5.

- **8,178 communities** at level 0 (x5 hierarchy levels = 40,890 total)
- Median community size: 15 entities
- Leiden completed in 27 seconds
- One mega-community of ~206K entities (the "everything connects to Doctor Who" hub)

## 5. Community Summarization

```bash
ARCANA_LLM=glm-4-32b-0414-128k mix arcana.graph.summarize_communities --collection doctor-who --concurrency 15
```

Generates natural language summaries for each community using the LLM. The prompt sends the top 50 entities by connection count and top 100 relationships (name + type only, no descriptions).

- **40,885 summaries** generated (99.99% coverage)
- 5 unsummarized: the mega-community repeated across 5 hierarchy levels

## 6. Entity Embeddings

```bash
mix arcana.graph.embed_entities --collection doctor-who
```

Generates vector embeddings for entity descriptions, enabling GraphRAG-style entity similarity search. Instead of relying on NER to extract entity names from queries (brittle, misses paraphrases), the search pipeline embeds the query and finds similar entities by cosine distance against their description embeddings.

This step is automatically done during `mix arcana.graph.rebuild` for new extractions. Run it separately to backfill embeddings for entities extracted before this feature was added.

- **362K entities** to embed
- Text embedded per entity: `"name: description"` or just `"name"` when no description
- Uses the same embedder as document chunks (BAAI/bge-small-en-v1.5)

## Pipeline Summary

```
1. mix corpus.parse                           # Wiki XML → JSON
2. mix corpus.ingest                          # JSON → chunks + embeddings
3. mix arcana.graph.rebuild                   # Chunks → entities + relationships (+ entity embeddings)
4. mix arcana.graph.detect_communities        # Entities → Leiden communities
5. mix arcana.graph.summarize_communities     # Communities → LLM summaries
6. mix arcana.graph.embed_entities            # (backfill only) Entity descriptions → embeddings
```

## Config

```elixir
# config/runtime.exs
config :arcana,
  repo: Adept.Repo,
  embedder: :local,
  llm: {"zai:#{System.get_env("ARCANA_LLM", "glm-5.1")}", api_key: System.get_env("ZAI_API_TOKEN")},
  graph: [
    enabled: true,
    extractor: Arcana.Graph.GraphExtractor.LLM,
    community_levels: 5,
    resolution: 0.25,
    min_size: 10
  ]
```

The `ARCANA_LLM` env var lets you swap models without changing config. GLM-5.1 is the default for chat/search, GLM-4-32B was used for bulk extraction and summarization (cheaper, higher concurrency).

## Fixes Applied to Arcana

During the extraction run, the LLM occasionally returned malformed output. These fixes were committed to the Arcana repo:

- **Nil entity names**: filtered out before DB insert
- **Blank relationship types**: filtered out before DB insert
- **String entities instead of maps**: normalized to `%{name, type, description}`
- **Integer entity names** (e.g. `1996`): coerced to string
- **Entity names exceeding 255 chars**: truncated
- **Community detection config**: `resolution`, `min_size`, `community_levels` now read from graph config instead of being hardcoded
- **Per-community data fetching**: summarization fetches entities/relationships per-community instead of loading everything into memory
- **Lean summarization prompts**: top 50 entities + 100 relationships, no descriptions
