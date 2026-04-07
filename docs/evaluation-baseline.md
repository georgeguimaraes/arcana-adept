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

### Re-run after dropping rewrite and decompose tools (2026-04-08)

Across every run above the controllers had ignored the `rewrite` and
`decompose` tools entirely — every tool history was just sequential
`search` calls. Both tools were no-ops on loop state (they returned
hint text back to the controller without triggering anything), so the
model correctly skipped the indirection and refined queries inline
instead. Per Anthropic's tool sprawl guidance ("drop tools that don't
actually change agent behavior") the right move was to remove them.

The behaviors weren't lost — the system prompt now explicitly tells
the controller to mentally rewrite vague queries before searching and
to issue sequential searches per aspect for multi-part questions.
There just isn't a dedicated tool for either anymore.

Same questions, same models, three-tool default (`search`, `answer`,
`give_up`):

| Question | Model | Iterations | Outcome | Wall-clock |
|---|---|---|---|---|
| "What is a TARDIS?" | glm-4.6 | 3 (2 search + answer) | answered cleanly | 17.5s |
| "Which Time Lords have betrayed the Doctor across the show's history?" | glm-4.6 | 6 searches | max_iterations + synthesis | 58.1s |

Behavior is essentially identical to the 5-tool runs, which confirms
the hypothesis that `rewrite` and `decompose` were dead weight: the
controllers were already getting the same outcomes via direct
`search` calls. The TARDIS path is ~30% faster (17.5s vs 24.6s),
almost certainly because the per-turn system prompt is shorter
without the descriptions for the dropped tools. The enumeration
path still hits `max_iterations` because that's a model-behavior
issue with "list all X" questions, not a tool-availability issue.

The synthesized Time Lord answer this round covered 7 entities
(Master, Valeyard, Rassilon, Omega, High Council, General Tannis,
Rani) vs 6 in the previous full-chunks run; that's normal LLM
variance, not a behavior change.

### Full 60-case eval through Arcana.Loop (2026-04-08)

With the eval framework's new `:retriever` option (a simple callback
that lets you plug in any retrieval strategy), we ran the same 60
test cases through `Arcana.Loop` with glm-4.6 as the controller and
max_iterations: 10. `ctx.chunks` (accumulated across all search
iterations, capped at 30) got scored by the same Hit/MRR/Recall
metrics the Pipeline baseline used.

| Metric | Vector+Graph+Reranker | Loop (glm-4.6) | Delta |
|---|---|---|---|
| **MRR** | 0.458 | **0.241** | -47% |
| **Hit@1** | 0.433 | **0.133** | -69% |
| **Hit@3** | 0.483 | **0.300** | -38% |
| **Hit@5** | 0.483 | **0.383** | -21% |
| **Hit@10** | 0.500 | **0.433** | -13% |
| **Recall@5** | 0.483 | **0.383** | -21% |
| **Recall@10** | 0.500 | **0.433** | -13% |

Termination distribution across 60 cases:

- `:answered`: 42 cases (70%) — controller committed via the answer tool
- `:max_iterations`: 18 cases (30%) — fallback synthesis fired
- `:gave_up`: 1 case

Cost per case (glm-4.6 against Z.ai):

- Average iterations: 5.1
- Average chunks accumulated: 15.4
- Average wall-clock: **33.8 seconds**
- Total wall-clock: 2027 seconds (~34 minutes for 60 cases)
- Estimated LLM calls: ~306

### Interpretation

**Loop is strictly worse than Pipeline on this eval, at 100x the
cost and 100x the latency.** Every retrieval metric regresses. The
gap is largest at k=1 (-69%) and narrows at higher k, but doesn't
close.

There are three things going on and they're worth separating out.

**1. The metric mismatch is real.** Pipeline's `Arcana.search/2`
produces a *ranked list*: position 1 is the backend's best guess
for the query. Loop's `ctx.chunks` is a *score-sorted union*
across multiple search calls, which is a different shape. The
chunk most relevant to the actual question might rank #3 or #5
in the union because an earlier, less-focused search returned a
chunk with a higher absolute similarity score. MRR and Hit@1
penalize this heavily; Hit@10 less so.

**2. Loop's recall is also genuinely lower, even correcting for
the ranking mismatch.** Loop at k=10 (0.433) vs Pipeline at k=5
(0.483) is roughly comparable at the top of the recall curve,
but Pipeline at k=10 still beats Loop at k=10 (0.500 vs 0.433).
That's a ~13% real gap. Possible causes: Loop's multiple queries
drift as the model refines, Loop doesn't cross-encoder rerank
the accumulated union (Pipeline does, and that's where Pipeline's
biggest gain came from in earlier runs), and the chunk_cap
eviction is by raw score rather than query-conditional rank.

**3. The eval doesn't measure what Loop is actually for.** The 60
test cases were generated by sampling a single source chunk and
asking an LLM "what question would retrieve this?" Every test
case has exactly one expected chunk. That's a **single-chunk
relevance eval**, and Pipeline is explicitly optimized for that
shape: one search call, one ranked list, the best chunk at the
top. Loop's value is on multi-hop questions where the answer has
to be synthesized across several chunks ("which Time Lords
betrayed the Doctor", "compare X and Y", "what do we know about
Z") — and those questions aren't in this eval set at all. The
eval is measuring Loop on the task it's worst at.

### What this tells us about when to use Loop

The practical conclusion for Arcana users:

- **Factoid lookup, single-chunk retrieval, simple QA** — use
  `Arcana.search/2` or `Arcana.Pipeline`. Loop is strictly worse
  and dramatically more expensive on these shapes.
- **Multi-hop synthesis, enumeration, open-ended exploration** —
  Loop is designed for this, but we don't have numbers yet. A
  separate eval set targeted at this use case would tell us
  whether Loop's cost is justified.
- **When you want the model to decide retrieval strategy at
  runtime** — Loop is the only option. Value here is correctness
  on hard questions, not raw retrieval metrics.

A fair Loop eval would need: multi-hop test cases with multiple
expected chunks, answer-quality metrics (LLM-as-judge for
faithfulness and completeness), and ideally cost/latency budgets
as first-class metrics alongside accuracy. That's a separate
piece of work.

### What this does NOT tell us

- **Answer quality.** The eval measures "did the expected chunk
  show up in the retrieved set" but says nothing about whether
  the final answer Loop produced was correct, complete, or
  faithful. Loop's synthesized answers on the Time Lord question
  (6-7 entities covered) were genuinely useful even when the
  retrieval metrics looked bad.
- **Grounding.** `Arcana.Loop.ground/2` now exists and could have
  been run on each answer, but wasn't in this eval.
- **Robustness on questions where Pipeline fails.** If there's a
  class of questions Pipeline gets wrong and Loop gets right,
  this eval won't show it because the test set was generated
  against Pipeline's strengths.

## Pipeline on the multi-hop set with answer scoring (2026-04-07)

First end-to-end Pipeline eval against the 10-case multi-hop set
with `evaluate_answers: true` (LLM-as-judge for faithfulness and
correctness, glm-4.6 as the judge). Run via `mix adept.eval`:

```
ARCANA_LLM=glm-4.6 mix adept.eval --evaluate-answers
```

Branch state at the time of this run: `fix/graph-robustness` with
GraphRAG Local Search alignment (entity embedding search, structured
ask context, community summaries, cross-encoder reranker).

| Metric | Pipeline (multi-hop) |
|---|---|
| **MRR** | 1.000 |
| **Hit@1** | 1.000 |
| **Hit@3** | 1.000 |
| **Hit@5** | 1.000 |
| **Hit@10** | 1.000 |
| **Recall@5** | 0.500 |
| **Recall@10** | 1.000 |
| **Faithfulness** | 10.0 / 10 |
| **Correctness** | 7.8 / 10 |

Per-case correctness breakdown (faithfulness was 10 across the board):

| Score | Question |
|---|---|
| 10 | What are the known weaknesses of the Cybermen across different eras? |
| 10 | What are the main abilities and unusual properties of the TARDIS? |
| 10 | Which Time Lords have betrayed the Doctor across the show's history? |
| 10 | Which companions have become Time Lords or Time Lord-like beings? |
| 10 | Which historical figures has the Doctor met, and in which stories? |
| 9 | How has the Master's character and appearance evolved across different incarnations? |
| 9 | What role did the Daleks play during the Last Great Time War? |
| 5 | What is the evolution of the sonic screwdriver's capabilities over the show's history? |
| 5 | Who are the most notable companions of the Fourth Doctor and what distinguishes each? |
| 0 | How has Gallifrey's depiction changed between the classic and modern series? |

### Interpretation

**Retrieval is essentially solved on this set.** Hit@1 1.0 means the
top-ranked chunk was always one of the relevant set, MRR 1.0 confirms
rank 1 every time. Recall@10 1.0 means the full relevant chunk set
was retrieved within k=10 for every case. The GraphRAG entity
embedding work + cross-encoder reranking is doing what it should: even
on multi-hop questions where the answer spans multiple chunks, the
retriever surfaces all the right ones.

**Faithfulness 10/10 across the board** means every answer the LLM
produced stayed grounded in the retrieved context. No hallucinations
on this set. That's the GraphRAG "structured context" work paying
off — entities, relationships, and community summaries give the LLM
enough scaffolding to commit to grounded answers instead of filling
gaps with plausible-sounding fiction.

**Correctness 7.8/10 average is the realistic ceiling and the place
to improve.** Two failure modes:

1. *Comparative / "evolution over time" questions* (sonic screwdriver,
   Fourth Doctor companions, Gallifrey old vs new). These need the
   answer to span multiple eras, and the retrieved chunks tend to
   over-represent one era. The single Gallifrey 0 is the worst case:
   retrieval found Gallifrey chunks, but they were all classic-era,
   so the answer couldn't compare classic vs modern.
2. *Enumeration questions where the relevant set is large.* Recall@5
   is only 0.5, so at the rerank cap of 5 the answer only sees half
   the relevant chunks. Increasing `limit` would help here at the
   cost of more tokens.

### Caveats

- **This is not a direct comparison to the 2026-04-06 baseline.**
  That baseline was 60 single-chunk synthetic cases (one expected
  chunk each). This run is 10 multi-hop manual cases (multiple
  expected chunks each, with ground-truth reference answers). The
  retrieval metrics aren't apples-to-apples.
- **MRR/Hit@k on multi-hop is "at least one relevant chunk in top
  k", not "exact chunk in top k".** That's why Hit@1 can be 1.0
  while Recall@5 is 0.5 — the first chunk is always relevant, but
  the top 5 only cover half the relevant set per case.
- **Faithfulness 10/10 is suspiciously perfect** and suggests the
  LLM-as-judge is permissive. A harder set with adversarial
  questions would probably surface real ungrounded claims.
- **All scoring uses glm-4.6 as both the answerer and the judge.**
  Same-model judging biases toward the answerer. A different judge
  model (claude or gpt) would be a stronger validation.

### What the answer eval framework needed to make this work

The first run produced nil for every faithfulness and correctness
score. Root cause: glm-4.6 wraps JSON output in ` ```json ... ``` `
markdown fences even when the prompt asks for "JSON only", and
`Arcana.Evaluation.AnswerMetrics.parse_response/1` was passing the
fenced text straight to `JSON.decode/1`, which choked on the
backticks and returned `:invalid_response`. Every per-case score
collapsed silently and the aggregate came back nil. Fixed in
arcana 1ba19c4 by stripping the fence before decoding.
