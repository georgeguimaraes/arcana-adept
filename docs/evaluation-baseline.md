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

## Arcana.Loop on doctor-who (2026-04-08)

First end-to-end runs of the new `Arcana.Loop` agentic RAG module against
the doctor-who corpus. Loop drives an LLM tool loop with five default tools
(search, rewrite, decompose, answer, give_up) and falls back to chunk
synthesis when `max_iterations` is hit without an `answer` call.

Setup: `Adept.Repo`, `doctor-who` collection, default search (vector +
graph + cross-encoder reranker, the same baseline as above), `chunk_cap:
20`, `max_iterations: 6`. Numbers are wall-clock from a single machine,
not benchmarks.

| Question | Model | Iterations | Outcome | Wall-clock |
|---|---|---|---|---|
| "What is a TARDIS?" | glm-4.5-flash | 3 (2 search + answer) | answered cleanly | 81.5s |
| "What is a TARDIS?" | glm-4.6 | 6 searches | max_iterations + synthesis | 27.3s |
| "Which Time Lords have betrayed the Doctor across the show's history?" | glm-4.6 | 6 searches | max_iterations + synthesis | 34.2s |
| "Which Time Lords have betrayed the Doctor across the show's history?" (10 iter cap) | glm-4.6 | 10 searches | max_iterations + synthesis | 51.2s |

Observations:

- `glm-4.5-flash` was actually slower per iteration (~27s) than `glm-4.6`
  (~5s) on this corpus, the opposite of what the names suggest. Likely
  Z.ai routing or queue position, not anything inherent to either model.
- Both models reliably refuse to call `answer` on enumeration questions
  ("which X have done Y") even with 10 iterations of room. They keep
  hunting for completeness one entity at a time. The fallback synthesis
  step is what saves these runs: at the end of the loop, Arcana makes one
  more tool-less LLM call with the accumulated chunks and the original
  question, and the model produces a structured answer covering Rassilon,
  the Valeyard, the Master, Omega, and friends.
- For factoid questions ("what is a TARDIS"), glm-4.5-flash hits the
  happy path: 2 searches, then `answer`, ~81s end to end (which is too
  slow for a chat UX but fine for a research agent).
- Iteration time is dominated by the controller LLM round-trip. Pgvector
  search against 174K chunks is sub-second per call.
- OpenAI was attempted but the API key in this environment has an
  `invalid_organization` binding that 401s before reaching any model, so
  no OpenAI numbers here.

Two real issues found and fixed in `Arcana.Loop` while running this:

1. Z.ai's encoder rejected our assistant tool calls because they were
   plain `%{id, name, arguments}` maps. They need to be `ReqLLM.ToolCall`
   structs so the encoder wraps them as
   `{id, type: "function", function: %{name, arguments}}`.
2. Tuple LLM specs like `{"zai:glm-4.6", api_key: "..."}` (the
   `Arcana.Config` convention) weren't being unwrapped before reaching
   `ReqLLM.generate_text`. Loop now handles both string and tuple model
   specs the same way the rest of Arcana does.

The third "fix" was actually a redesign: graceful degradation via
`fallback_synthesis`. Without it, enumeration questions return `nil`
answers, which is technically correct given `max_iterations` semantics
but useless in practice. With it, the loop almost always returns
something usable.

### Re-run with full chunk text in tool results (2026-04-08)

The runs above were done with the search tool returning 400-character
truncated chunk previews to the controller. I borrowed that pattern
from Anthropic's general agent-design guidance (keep tool results
terse), but the agentic RAG papers (Self-RAG, CRAG) all pass full
passages to the model, and that's the right model here too: the
controller IS the answerer in this loop and it needs the actual
evidence to decide whether what it has is enough to commit.

After dropping the truncation (one `Tools.format_search_summary`
change), same questions, same models, same `max_iterations: 6`:

| Question | Model | Iterations | Outcome | Wall-clock |
|---|---|---|---|---|
| "What is a TARDIS?" | glm-4.6 | 4 (3 search + answer) | **answered cleanly** | 24.6s |
| "Which Time Lords have betrayed the Doctor across the show's history?" | glm-4.6 | 6 searches | max_iterations + synthesis | 60.4s |

The factoid question is the dramatic improvement: glm-4.6 went from
6 searches with no `answer` call (fallback synthesis required) to
3 searches and a clean `answer` call in 24.6s. The over-search
failure mode on factoid questions was downstream of the truncation:
the model never saw enough of any chunk to commit, so it kept
refining queries indefinitely. With full chunks it commits.

The enumeration question still hits `:max_iterations`, but the
synthesized answer covers six distinct Time Lords (Master/Missy,
War Chief, Rani, Monk, Omega, Rassilon) with substantive
characterization, vs four (Rassilon, Valeyard, Master, Omega) in
the truncated run. The accumulated chunks now contain real evidence
for the synthesizer to work with, not 400-char previews. Wall-clock
went up from 34s to 60s because each iteration sends more tokens to
the controller, which is the expected tradeoff.

Cost note: full chunks roughly double the tokens per controller
turn (from ~2KB to ~4-5KB). For a 6-iteration loop that's ~12KB of
tool result text the controller processes, well within any modern
context window. The latency cost is real and dominated by LLM
round-trip time, not the search itself.
