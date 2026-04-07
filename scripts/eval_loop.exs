# Run the doctor-who eval set through Arcana.Loop and compare against
# the Pipeline baseline (recorded in docs/evaluation-baseline.md).
#
# Usage:
#   ZAI_API_TOKEN=... mix run scripts/eval_loop.exs
#
# Optional:
#   ARCANA_LLM=glm-4.6 (default)
#   LOOP_MAX_ITERATIONS=10 (default)
#   LOOP_LIMIT=5 (test cases to run; default: all 60)
#
# This is expensive: each test case is one full Loop run, which means
# multiple LLM round-trips. With 60 cases at ~5-30s per case and ~5
# iterations per loop, expect 30-60 minutes wall-clock and several
# hundred LLM calls. The Z.ai bill will be visible.

Logger.configure(level: :warning)

llm = Application.fetch_env!(:arcana, :llm)
max_iterations = String.to_integer(System.get_env("LOOP_MAX_ITERATIONS", "10"))

limit =
  case System.get_env("LOOP_LIMIT") do
    nil -> nil
    n -> String.to_integer(n)
  end

# Custom retriever that runs Loop and returns the accumulated chunks.
# The eval framework treats `ctx.chunks` as the "retrieved set" and
# computes Hit/MRR/Recall/Precision against the test case's expected
# chunks.
loop_retriever = fn question, _opts ->
  case Arcana.Loop.new(question, repo: Adept.Repo, collection: "doctor-who")
       |> Arcana.Loop.run(
         controller_llm: llm,
         max_iterations: max_iterations,
         chunk_cap: 30
       ) do
    {:ok, ctx} ->
      send(self(), {:loop_done, ctx.terminated_by, ctx.iterations, length(ctx.chunks)})
      {:ok, ctx.chunks}

    error ->
      error
  end
end

# Wrap the retriever to print live progress.
counter = :counters.new(1, [:atomics])

progress_retriever = fn question, opts ->
  :counters.add(counter, 1, 1)
  n = :counters.get(counter, 1)

  total_label = if limit, do: "/#{limit}", else: ""

  IO.write(
    IO.ANSI.format([:faint, "\r[#{n}#{total_label}] ", String.slice(question, 0, 70), "..."])
  )

  start = System.monotonic_time(:millisecond)
  result = loop_retriever.(question, opts)
  elapsed = System.monotonic_time(:millisecond) - start

  receive do
    {:loop_done, terminated_by, iters, chunks} ->
      IO.puts(
        IO.ANSI.format([
          "\r[#{n}#{total_label}] ",
          :faint,
          String.slice(question, 0, 60),
          " ",
          :reset,
          "→ ",
          to_string(terminated_by),
          " ",
          :faint,
          "(#{iters} iter, #{chunks} chunks, #{elapsed}ms)",
          "                    "
        ])
      )
  after
    0 -> IO.puts("")
  end

  result
end

# Optionally limit the number of test cases for quick smoke runs.
if limit do
  # Hack: temporarily delete extra test cases for this run? No — instead
  # run a custom subset by querying directly and using a smaller eval.
  # For now, the eval framework doesn't support a :limit option, so we
  # work around it by using a wrapper that returns empty for cases past N.
  #
  # Actually the cleanest path is to query test cases manually and run
  # the eval primitives directly. Let me do that.
  alias Arcana.Evaluation

  test_cases =
    Evaluation.list_test_cases(repo: Adept.Repo)
    |> Enum.take(limit)

  IO.puts(
    IO.ANSI.format([
      :bright,
      :cyan,
      "\nRunning Arcana.Loop eval against #{length(test_cases)} test cases ",
      "(LLM: #{inspect(llm, limit: 1)}, max_iterations: #{max_iterations})\n"
    ])
  )

  case_results =
    Enum.map(test_cases, fn tc ->
      {:ok, chunks} = progress_retriever.(tc.question, [])
      Arcana.Evaluation.Metrics.evaluate_case(tc, chunks)
    end)

  metrics = Arcana.Evaluation.Metrics.aggregate(case_results)

  IO.puts(
    IO.ANSI.format([:bright, "\n=== Loop eval results (#{length(test_cases)} cases) ===\n"])
  )

  IO.puts("MRR:           #{Float.round(metrics.mrr, 3)}")
  IO.puts("Hit@1:         #{Float.round(metrics.hit_rate_at_1, 3)}")
  IO.puts("Hit@3:         #{Float.round(metrics.hit_rate_at_3, 3)}")
  IO.puts("Hit@5:         #{Float.round(metrics.hit_rate_at_5, 3)}")
  IO.puts("Hit@10:        #{Float.round(metrics.hit_rate_at_10, 3)}")
  IO.puts("Recall@5:      #{Float.round(metrics.recall_at_5, 3)}")
  IO.puts("Recall@10:     #{Float.round(metrics.recall_at_10, 3)}")
else
  IO.puts(
    IO.ANSI.format([
      :bright,
      :cyan,
      "\nRunning Arcana.Loop eval against all test cases ",
      "(LLM: #{inspect(llm, limit: 1)}, max_iterations: #{max_iterations})\n"
    ])
  )

  {:ok, run} = Arcana.Evaluation.run(repo: Adept.Repo, retriever: progress_retriever)

  IO.puts(
    IO.ANSI.format([:bright, "\n=== Loop eval results (#{run.test_case_count} cases) ===\n"])
  )

  m = run.metrics
  IO.puts("MRR:           #{Float.round(m.mrr, 3)}")
  IO.puts("Hit@1:         #{Float.round(m.hit_rate_at_1, 3)}")
  IO.puts("Hit@3:         #{Float.round(m.hit_rate_at_3, 3)}")
  IO.puts("Hit@5:         #{Float.round(m.hit_rate_at_5, 3)}")
  IO.puts("Hit@10:        #{Float.round(m.hit_rate_at_10, 3)}")
  IO.puts("Recall@5:      #{Float.round(m.recall_at_5, 3)}")
  IO.puts("Recall@10:     #{Float.round(m.recall_at_10, 3)}")
  IO.puts("\nRun ID: #{run.id}")
end
