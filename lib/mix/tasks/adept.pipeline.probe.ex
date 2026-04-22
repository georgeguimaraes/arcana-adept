defmodule Mix.Tasks.Adept.Pipeline.Probe do
  @moduledoc """
  Runs Arcana.Pipeline against the Doctor Who corpus with a variety of
  step combinations and dumps every intermediate output. Used to verify
  each pipeline step actually does what the dashboard UI exposes.

      mix adept.pipeline.probe

  One-off diagnostic task, not a test suite. Intentionally chatty so the
  outputs (rewritten query, expanded query, sub-questions, rerank deltas,
  grounding spans) are visible at a glance.
  """
  use Mix.Task

  alias Arcana.Pipeline

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    llm = Application.fetch_env!(:arcana, :llm)
    Mix.shell().info("Using LLM: #{inspect(llm)}\n")

    scenarios()
    |> Enum.each(&run_scenario(&1, llm))
  end

  defp scenarios do
    [
      %{
        label: "REWRITE (conversational cleanup)",
        question: "Hey, so like, can you tell me about the TARDIS?",
        steps: [:rewrite, :search]
      },
      %{
        label: "EXPAND (short query gets synonyms)",
        question: "Daleks",
        steps: [:expand, :search]
      },
      %{
        label: "DECOMPOSE (compound question)",
        question: "Who is the Master and what are his main appearances on the show?",
        steps: [:decompose, :search]
      },
      %{
        label: "GATE (should short-circuit)",
        question: "What is 2 plus 2?",
        steps: [:gate, :search, :answer]
      },
      %{
        label: "GATE (should retrieve)",
        question: "Who are the Cybermen in Doctor Who?",
        steps: [:gate, :search, :answer]
      },
      %{
        label: "RERANK (top order before vs after)",
        question: "What kind of enemy is the Master?",
        steps: [:search, :rerank]
      },
      %{
        label: "REASON (multi-hop)",
        question: "How do the Daleks, Cybermen, and Sontarans each approach conquest?",
        steps: [:search, :reason]
      },
      %{
        label: "FULL PIPELINE + GROUND",
        question: "What is the sonic screwdriver?",
        steps: [:rewrite, :search, :rerank, :answer, :ground]
      }
    ]
  end

  defp run_scenario(%{label: label, question: q, steps: steps}, llm) do
    banner(label)
    Mix.shell().info("Q: #{q}")
    Mix.shell().info("Steps: #{inspect(steps)}\n")

    start = System.monotonic_time(:millisecond)
    ctx = Pipeline.new(q, repo: Adept.Repo, llm: llm, collection: "doctor-who", limit: 10)

    ctx =
      Enum.reduce(steps, ctx, fn step, acc ->
        try do
          apply(Pipeline, step, [acc])
        rescue
          e ->
            Mix.shell().info("  [#{step}] RAISED: #{Exception.message(e)}")
            acc
        end
      end)

    elapsed = System.monotonic_time(:millisecond) - start
    Mix.shell().info("Total: #{elapsed}ms")

    dump_outputs(ctx, steps)
    Mix.shell().info("")
  end

  defp dump_outputs(ctx, steps) do
    if :rewrite in steps do
      Mix.shell().info("  rewritten_query: #{inspect(ctx.rewritten_query)}")
    end

    if :expand in steps do
      Mix.shell().info("  expanded_query:  #{inspect(ctx.expanded_query)}")
    end

    if :decompose in steps do
      Mix.shell().info("  sub_questions:")

      for q <- ctx.sub_questions || [] do
        Mix.shell().info("    - #{q}")
      end
    end

    if :gate in steps do
      Mix.shell().info("  skip_retrieval:  #{inspect(ctx.skip_retrieval)}")
      Mix.shell().info("  gate_reasoning:  #{inspect(ctx.gate_reasoning)}")
    end

    if :search in steps do
      chunks = flatten_chunks(ctx.results)
      Mix.shell().info("  chunks:          #{length(chunks)}")
      dump_top_chunks(chunks, 3, "before rerank")
    end

    if :reason in steps do
      Mix.shell().info("  reason_iterations: #{inspect(ctx.reason_iterations)}")

      Mix.shell().info(
        "  queries_tried:     #{inspect(ctx.queries_tried && MapSet.to_list(ctx.queries_tried))}"
      )
    end

    if :rerank in steps do
      Mix.shell().info("  rerank_scores present: #{ctx.rerank_scores != nil}")
      chunks = flatten_chunks(ctx.results)
      dump_top_chunks(chunks, 3, "after rerank")
    end

    if :answer in steps do
      Mix.shell().info("  answer (first 200 chars):")

      if is_binary(ctx.answer) do
        Mix.shell().info("    #{String.slice(ctx.answer, 0, 200)}")
      else
        Mix.shell().info("    (nil)")
      end

      Mix.shell().info("  correction_count: #{inspect(ctx.correction_count)}")
    end

    if :ground in steps do
      case ctx.grounding do
        nil ->
          Mix.shell().info("  grounding: nil")

        g ->
          Mix.shell().info("  grounding.score:              #{inspect(g.score)}")
          Mix.shell().info("  hallucinated_spans:           #{length(g.hallucinated_spans)}")
          Mix.shell().info("  faithful_spans:               #{length(g.faithful_spans)}")

          for span <- Enum.take(g.hallucinated_spans, 2) do
            Mix.shell().info("    HALLUC: #{inspect(String.slice(span.text, 0, 80))}")
          end
      end
    end

    if ctx.error do
      Mix.shell().info("  error: #{inspect(ctx.error)}")
    end
  end

  defp flatten_chunks(nil), do: []

  defp flatten_chunks(results) when is_list(results) do
    Enum.flat_map(results, fn
      %{chunks: chunks} when is_list(chunks) -> chunks
      chunk when is_map(chunk) -> [chunk]
      _ -> []
    end)
  end

  defp dump_top_chunks([], _n, _label), do: :ok

  defp dump_top_chunks(chunks, n, label) do
    Mix.shell().info("  top #{n} #{label}:")

    chunks
    |> Enum.take(n)
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, i} ->
      score = Map.get(chunk, :score) || Map.get(chunk, "score")
      text = Map.get(chunk, :text) || Map.get(chunk, "text") || ""
      id = Map.get(chunk, :id) || Map.get(chunk, "id")
      preview = text |> String.slice(0, 80) |> String.replace("\n", " ")

      score_str =
        if is_number(score), do: :erlang.float_to_binary(score * 1.0, decimals: 4), else: "—"

      Mix.shell().info(
        "    #{i}. [#{score_str}] #{String.slice(to_string(id), 0, 8)}: #{preview}"
      )
    end)
  end

  defp banner(label) do
    line = String.duplicate("=", 70)
    Mix.shell().info("\n#{line}\n#{label}\n#{line}")
  end
end
