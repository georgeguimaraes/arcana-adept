# Run the doctor-who eval set through the default Pipeline retriever
# (Arcana.search/2 with vector + graph + cross-encoder reranker) and
# print the metrics. Used to verify the GraphRAG Local Search alignment
# work moved Hit@1/MRR vs the recorded baseline.
#
# Usage:
#   ZAI_API_TOKEN=... mix run scripts/eval_pipeline.exs
#
# Optional:
#   EVAL_ANSWERS=true   also evaluate answer correctness/faithfulness
#                       via LLM-as-judge (requires reference_answer on
#                       each test case)
#
# Baseline to compare against (docs/evaluation-baseline.md, 2026-04-06):
#   MRR 0.458, Hit@1 0.433, Hit@10 0.500
#
# Retrieval-only is fast: 60 cases through pgvector + reranker takes a
# few minutes, no LLM calls in the retriever path. With EVAL_ANSWERS=true
# expect ~10-30s extra per case for the judge calls.

Logger.configure(level: :warning)

evaluate_answers? = System.get_env("EVAL_ANSWERS") == "true"

counter = :counters.new(1, [:atomics])

progress_retriever = fn question, opts ->
  :counters.add(counter, 1, 1)
  n = :counters.get(counter, 1)

  start = System.monotonic_time(:millisecond)

  result =
    Arcana.search(
      question,
      Keyword.merge([repo: Adept.Repo, collection: "doctor-who", limit: 10], opts)
    )

  elapsed = System.monotonic_time(:millisecond) - start

  case result do
    {:ok, chunks} ->
      IO.puts(
        IO.ANSI.format([
          "[#{n}] ",
          :faint,
          String.slice(question, 0, 70),
          " ",
          :reset,
          "→ #{length(chunks)} chunks ",
          :faint,
          "(#{elapsed}ms)"
        ])
      )

      result

    error ->
      IO.puts(IO.ANSI.format([:red, "[#{n}] error: #{inspect(error)}"]))
      error
  end
end

IO.puts(
  IO.ANSI.format([
    :bright,
    :cyan,
    "\nRunning Arcana.Pipeline eval against doctor-who test cases\n"
  ])
)

eval_opts =
  [repo: Adept.Repo, retriever: progress_retriever]
  |> then(fn opts ->
    if evaluate_answers? do
      Keyword.merge(opts,
        evaluate_answers: true,
        llm: Application.fetch_env!(:arcana, :llm)
      )
    else
      opts
    end
  end)

{:ok, run} = Arcana.Evaluation.run(eval_opts)

IO.puts(
  IO.ANSI.format([
    :bright,
    "\n=== Pipeline eval results (#{run.test_case_count} cases) ===\n"
  ])
)

m = run.metrics

fmt = fn
  nil -> "—"
  v when is_float(v) -> Float.round(v, 3) |> to_string()
  v -> to_string(v)
end

IO.puts("MRR:           #{fmt.(m[:mrr])}")
IO.puts("Hit@1:         #{fmt.(m[:hit_rate_at_1])}")
IO.puts("Hit@3:         #{fmt.(m[:hit_rate_at_3])}")
IO.puts("Hit@5:         #{fmt.(m[:hit_rate_at_5])}")
IO.puts("Hit@10:        #{fmt.(m[:hit_rate_at_10])}")
IO.puts("Recall@5:      #{fmt.(m[:recall_at_5])}")
IO.puts("Recall@10:     #{fmt.(m[:recall_at_10])}")

if evaluate_answers? do
  IO.puts("\nFaithfulness: #{fmt.(m[:faithfulness])} / 10")
  IO.puts("Correctness:  #{fmt.(m[:correctness])} / 10")
end

IO.puts("\nRun ID: #{run.id}")

IO.puts("\nBaseline (2026-04-06, +cross-encoder reranker):")
IO.puts("  MRR 0.458, Hit@1 0.433, Hit@10 0.500")
