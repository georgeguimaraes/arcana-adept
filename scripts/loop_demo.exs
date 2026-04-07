# Demo: run Arcana.Loop on the doctor-who corpus.
#
# Usage:
#   ZAI_API_TOKEN=... mix run scripts/loop_demo.exs
#
# Optional:
#   ARCANA_LLM=glm-5.1 (default)
#   LOOP_QUESTION="..." (override the default questions)
#
# Prints, for each question:
#   - the original question
#   - each tool call the controller made (with the summary it saw)
#   - the final answer
#   - the termination reason and iteration count

Logger.configure(level: :warning)

questions =
  case System.get_env("LOOP_QUESTION") do
    nil ->
      [
        "Who is the Master and how is he related to the Doctor?",
        "Which Time Lords have betrayed the Doctor across the show's history?",
        "What happened in the episode 'The Five Doctors'?",
        "How does regeneration work for Time Lords?"
      ]

    q ->
      [q]
  end

llm =
  case System.get_env("LOOP_LLM") do
    nil ->
      Application.fetch_env!(:arcana, :llm)

    "openai:" <> _ = model ->
      {model, api_key: System.fetch_env!("OPENAI_API_KEY")}

    "anthropic:" <> _ = model ->
      {model, api_key: System.fetch_env!("ANTHROPIC_API_KEY")}

    "google:" <> _ = model ->
      {model, api_key: System.fetch_env!("GEMINI_API_KEY")}

    model ->
      model
  end

run_one = fn question ->
  IO.puts(IO.ANSI.format([:bright, :cyan, "\n=== ", question, " ==="]))

  start_time = System.monotonic_time(:millisecond)

  {:ok, ctx} =
    Arcana.Loop.new(question, repo: Adept.Repo, collection: "doctor-who")
    |> Arcana.Loop.run(
      controller_llm: llm,
      max_iterations: String.to_integer(System.get_env("LOOP_MAX_ITERATIONS", "6")),
      chunk_cap: 20
    )

  elapsed = System.monotonic_time(:millisecond) - start_time

  IO.puts(IO.ANSI.format([:faint, "Tool history (#{length(ctx.tool_history)}):"]))

  show_summaries = System.get_env("LOOP_DEBUG") == "1"

  Enum.each(ctx.tool_history, fn entry ->
    IO.puts(
      IO.ANSI.format([
        "  ",
        :yellow,
        "[#{entry.iteration}] ",
        :reset,
        Atom.to_string(entry.tool),
        " ",
        :faint,
        inspect(entry.args, limit: 3, printable_limit: 80)
      ])
    )

    if show_summaries do
      IO.puts(IO.ANSI.format([:faint, "    ", entry.summary]))
    end
  end)

  IO.puts(IO.ANSI.format([:bright, "\nAnswer:"]))
  IO.puts(ctx.answer || "<none>")

  IO.puts(
    IO.ANSI.format([
      :faint,
      "\nTerminated by: ",
      to_string(ctx.terminated_by),
      " | iterations: #{ctx.iterations}",
      " | chunks: #{length(ctx.chunks)}",
      " | #{elapsed}ms"
    ])
  )

  if ctx.error do
    IO.puts(IO.ANSI.format([:red, "Error: ", inspect(ctx.error, pretty: true, limit: 20)]))
  end
end

Enum.each(questions, run_one)
