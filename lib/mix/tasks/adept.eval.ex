defmodule Mix.Tasks.Adept.Eval do
  @shortdoc "Run the Arcana evaluation suite against the Adept corpus"

  @moduledoc """
  Runs the Arcana evaluation suite against the Adept corpus using one
  of two retrieval strategies.

  ## Usage

      mix adept.eval                              # Pipeline, retrieval only
      mix adept.eval --retriever loop             # Arcana.Loop
      mix adept.eval --evaluate-answers           # plus LLM-as-judge
      mix adept.eval --limit 5                    # first N cases (smoke)

  ## Options

    * `--retriever pipeline|loop` - retrieval strategy (default: pipeline)
    * `--evaluate-answers` - also score faithfulness + correctness via
      LLM-as-judge. Requires test cases with a `reference_answer` set
    * `--limit N` - only run against the first N test cases. Bypasses
      `Arcana.Evaluation.run/1` so no `Run` row is created and
      `--evaluate-answers` is ignored in this mode
    * `--max-iterations N` - Loop iteration cap (default: 10, loop only)
    * `--chunk-cap N` - Loop chunk cap (default: 30, loop only)
    * `--collection NAME` - collection to search (default: doctor-who)

  Requires whatever env var the configured LLM provider needs (e.g.
  `ZAI_API_TOKEN` for Z.ai, `OPENAI_API_KEY` for OpenAI).

  Pipeline runs are fast (pgvector + reranker, no LLM calls in the
  retriever path). Loop and `--evaluate-answers` runs are dominated by
  LLM round-trip time — expect 30-60 seconds per case.
  """

  use Mix.Task

  alias Arcana.Evaluation

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          retriever: :string,
          evaluate_answers: :boolean,
          limit: :integer,
          max_iterations: :integer,
          chunk_cap: :integer,
          collection: :string
        ]
      )

    retriever_name = Keyword.get(opts, :retriever, "pipeline")
    collection = Keyword.get(opts, :collection, "doctor-who")
    limit = Keyword.get(opts, :limit)
    evaluate_answers? = Keyword.get(opts, :evaluate_answers, false)

    llm =
      if evaluate_answers? or retriever_name == "loop" do
        Application.fetch_env!(:arcana, :llm)
      end

    retriever = build_retriever(retriever_name, collection, llm, opts)

    IO.puts(
      IO.ANSI.format([
        :bright,
        :cyan,
        "\nRunning #{retriever_name} eval against doctor-who test cases\n"
      ])
    )

    case limit do
      nil -> run_full(retriever, evaluate_answers?, llm, retriever_name)
      n -> run_limited(retriever, n, retriever_name)
    end
  end

  defp build_retriever("pipeline", collection, _llm, _opts) do
    wrap_progress(fn question, opts ->
      Arcana.search(
        question,
        Keyword.merge([repo: Adept.Repo, collection: collection, limit: 10], opts)
      )
    end)
  end

  defp build_retriever("loop", collection, llm, opts) do
    max_iterations = Keyword.get(opts, :max_iterations, 10)
    chunk_cap = Keyword.get(opts, :chunk_cap, 30)

    wrap_progress(fn question, _opts ->
      ctx = Arcana.Loop.new(question, repo: Adept.Repo, collection: collection)

      case Arcana.Loop.run(ctx,
             controller_llm: llm,
             max_iterations: max_iterations,
             chunk_cap: chunk_cap
           ) do
        {:ok, %Arcana.Loop.Context{} = result_ctx} ->
          {:ok, result_ctx.chunks, result_ctx.answer}

        {:error, _} = err ->
          err
      end
    end)
  end

  defp build_retriever(other, _collection, _llm, _opts) do
    Mix.raise("unknown --retriever #{inspect(other)}, expected pipeline or loop")
  end

  # Decorates a retriever with a progress counter and a one-line log per
  # call. Accepts either a 2-tuple or 3-tuple result shape so the loop
  # and pipeline retrievers both flow through the same wrapper.
  defp wrap_progress(retriever) do
    counter = :counters.new(1, [:atomics])

    fn question, opts ->
      :counters.add(counter, 1, 1)
      n = :counters.get(counter, 1)

      start = System.monotonic_time(:millisecond)
      result = retriever.(question, opts)
      elapsed = System.monotonic_time(:millisecond) - start

      status =
        case result do
          {:ok, chunks} -> "#{length(chunks)} chunks"
          {:ok, chunks, _answer} -> "#{length(chunks)} chunks"
          {:error, reason} -> "error: #{inspect(reason)}"
        end

      color = if match?({:error, _}, result), do: :red, else: :reset

      IO.puts(
        IO.ANSI.format([
          "[#{n}] ",
          :faint,
          String.slice(question, 0, 70),
          " ",
          color,
          "→ #{status} ",
          :faint,
          "(#{elapsed}ms)"
        ])
      )

      result
    end
  end

  defp run_full(retriever, evaluate_answers?, llm, label) do
    eval_opts = [repo: Adept.Repo, retriever: retriever]

    eval_opts =
      if evaluate_answers?,
        do: Keyword.merge(eval_opts, evaluate_answers: true, llm: llm),
        else: eval_opts

    {:ok, run} = Evaluation.run(eval_opts)

    print_header(label, run.test_case_count)
    print_metrics(run.metrics, evaluate_answers?)
    IO.puts("\nRun ID: #{run.id}")
  end

  defp run_limited(retriever, limit, label) do
    test_cases =
      Evaluation.list_test_cases(repo: Adept.Repo)
      |> Enum.take(limit)

    case_results =
      Enum.map(test_cases, fn tc ->
        # A failing retriever turns into an empty-chunk miss so one bad
        # call can't crash the whole smoke run with a MatchError.
        chunks =
          case retriever.(tc.question, []) do
            {:ok, chunks} -> chunks
            {:ok, chunks, _answer} -> chunks
            _ -> []
          end

        Evaluation.Metrics.evaluate_case(tc, chunks)
      end)

    metrics = Evaluation.Metrics.aggregate(case_results)

    print_header(label, length(test_cases))
    print_metrics(metrics, false)
    IO.puts("\n(--limit bypasses Run persistence; no ID)")
  end

  defp print_header(label, n) do
    IO.puts(IO.ANSI.format([:bright, "\n=== #{label} eval results (#{n} cases) ===\n"]))
  end

  defp print_metrics(metrics, evaluate_answers?) do
    IO.puts("MRR:           #{fmt(metrics[:mrr])}")
    IO.puts("Hit@1:         #{fmt(metrics[:hit_rate_at_1])}")
    IO.puts("Hit@3:         #{fmt(metrics[:hit_rate_at_3])}")
    IO.puts("Hit@5:         #{fmt(metrics[:hit_rate_at_5])}")
    IO.puts("Hit@10:        #{fmt(metrics[:hit_rate_at_10])}")
    IO.puts("Recall@5:      #{fmt(metrics[:recall_at_5])}")
    IO.puts("Recall@10:     #{fmt(metrics[:recall_at_10])}")

    if evaluate_answers? do
      IO.puts("\nFaithfulness: #{fmt(metrics[:faithfulness])} / 10")
      IO.puts("Correctness:  #{fmt(metrics[:correctness])} / 10")
    end
  end

  defp fmt(nil), do: "—"
  defp fmt(v) when is_float(v), do: v |> Float.round(3) |> to_string()
  defp fmt(v), do: to_string(v)
end
