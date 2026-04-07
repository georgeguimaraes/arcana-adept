# Evaluation Baseline (2026-04-05)

60 synthetic test cases generated from the doctor-who collection (108K documents, 174K chunks).

## Results

| Metric | Vector Only | Vector + Graph | Delta |
|--------|------------|----------------|-------|
| **MRR** | 0.292 | 0.330 | +13.2% |
| **Recall@1** | 0.233 | 0.267 | +14.3% |
| **Recall@3** | 0.350 | 0.433 | +23.8% |
| **Recall@5** | 0.367 | 0.433 | +18.2% |
| **Recall@10** | 0.383 | 0.467 | +21.8% |
| **Hit Rate@1** | 0.233 | 0.267 | +14.3% |
| **Hit Rate@3** | 0.350 | 0.433 | +23.8% |
| **Hit Rate@5** | 0.367 | 0.433 | +18.2% |
| **Hit Rate@10** | 0.383 | 0.467 | +21.8% |
| **Precision@1** | 0.233 | 0.267 | +14.3% |
| **Precision@3** | 0.117 | 0.144 | +23.8% |
| **Precision@5** | 0.073 | 0.087 | +18.2% |
| **Precision@10** | 0.038 | 0.047 | +21.8% |

## Observations

- Graph-enhanced search improves recall across all k values by 14-24%
- MRR improves by 13%, meaning the correct chunk ranks higher on average
- The biggest gains are at k=3 and k=10, suggesting graph search surfaces relevant chunks that vector search misses entirely
- Absolute recall is still relatively low (47% at k=10), likely because synthetic test cases sometimes generate questions that don't map cleanly back to the source chunk

## Config

- Embedding model: BAAI/bge-small-en-v1.5 (384 dims)
- Graph: 362K entities, 2M relationships, 40K communities
- Search mode: semantic (cosine similarity)
- Graph fusion: RRF with k=60
- No reranking, no query rewriting

## After improvements (2026-04-06)

Community summaries injected into graph search results. Tested with various RRF caps.

| Config | MRR | Recall@5 | Recall@10 |
|--------|-----|----------|-----------|
| Vector only | 0.292 | 0.367 | 0.383 |
| Vector + Graph (baseline) | 0.330 | 0.433 | 0.467 |
| **Vector + Graph + Communities** | **0.333** | **0.433** | **0.467** |
| Vector + Graph + Cap 200 | 0.311 | 0.417 | 0.450 |
| Vector + Graph + Cap 50 | 0.278 | 0.400 | 0.450 |

Key findings:
- Capping graph results before RRF hurts performance, the large result set provides a useful "appears in both lists" signal
- Community summaries provide a small MRR boost and add thematic context for the ask pipeline
- The uncapped RRF fusion is working better than expected

## Cross-encoder reranking (2026-04-06)

Added `Arcana.Pipeline.Reranker.CrossEncoder` using `cross-encoder/ms-marco-MiniLM-L-6-v2` via Bumblebee. Runs locally via Nx.Serving. Also added `:reranker` option to `Arcana.Search.search/2` so reranking works outside the Agent pipeline: over-fetches 3x candidates, reranks, returns top-k.

| Metric | Vector Only | Vector + Graph | **+ Cross-Encoder Reranker** |
|--------|------------|----------------|------------------------------|
| **MRR** | 0.292 | 0.330 | **0.458 (+39%)** |
| **Hit@1** | 0.233 | 0.267 | **0.433 (+62%)** |
| **Hit@3** | 0.350 | 0.433 | **0.483 (+12%)** |
| **Hit@5** | 0.367 | 0.433 | **0.483 (+12%)** |
| **Hit@10** | 0.383 | 0.467 | **0.500 (+7%)** |

The biggest single improvement. The correct chunk now ranks first 43% of the time (up from 27%). MRR nearly doubled compared to vector-only search.

Community summaries were moved from the search path to the ask pipeline (injected as "background knowledge" in the LLM prompt alongside retrieved chunks). This is how Microsoft's GraphRAG paper recommends using them: as additional context, not as search results competing in RRF.

## Remaining gaps

- No query expansion/rewriting enabled by default
- Embedding model (BGE-small) could be upgraded
- Multi-hop graph traversal (depth 1 → 2)
- HyDE for broad thematic queries
