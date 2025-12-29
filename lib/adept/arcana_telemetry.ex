defmodule Adept.ArcanaTelemetry do
  @moduledoc """
  Telemetry handler for logging Arcana events to stdout.

  Attaches handlers for all Arcana telemetry events and logs timing information
  to help identify performance bottlenecks.
  """

  require Logger

  @doc """
  Attaches telemetry handlers for Arcana events.
  Call this from your Application.start/2.
  """
  def attach do
    events = [
      # Core operations
      [:arcana, :ingest, :stop],
      [:arcana, :search, :stop],
      [:arcana, :ask, :stop],
      [:arcana, :embed, :stop],
      [:arcana, :embed_batch, :stop],
      # Agent pipeline
      [:arcana, :agent, :rewrite, :stop],
      [:arcana, :agent, :select, :stop],
      [:arcana, :agent, :expand, :stop],
      [:arcana, :agent, :decompose, :stop],
      [:arcana, :agent, :search, :stop],
      [:arcana, :agent, :rerank, :stop],
      [:arcana, :agent, :answer, :stop],
      [:arcana, :agent, :self_correct, :stop]
    ]

    :telemetry.attach_many(
      "adept-arcana-logger",
      events,
      &__MODULE__.handle_event/4,
      nil
    )
  end

  @doc false
  def handle_event(event, measurements, metadata, _config) do
    duration_ms = format_duration(measurements[:duration])
    event_name = format_event_name(event)

    log_message = build_log_message(event_name, duration_ms, metadata)
    Logger.info(log_message)
  end

  defp format_duration(nil), do: "?"
  defp format_duration(duration_ns) do
    duration_ms = System.convert_time_unit(duration_ns, :native, :millisecond)

    cond do
      duration_ms >= 1000 -> "#{Float.round(duration_ms / 1000, 2)}s"
      duration_ms >= 1 -> "#{duration_ms}ms"
      true -> "<1ms"
    end
  end

  defp format_event_name([:arcana | rest]) do
    rest
    |> Enum.reject(&(&1 == :stop))
    |> Enum.map_join(".", &Atom.to_string/1)
  end

  defp build_log_message(event_name, duration, metadata) do
    base = "[Arcana] #{event_name} completed in #{duration}"

    details = extract_details(event_name, metadata)
    if details != "", do: "#{base} #{details}", else: base
  end

  defp extract_details("ingest", meta) do
    "(#{meta[:chunks_count] || "?"} chunks)"
  end

  defp extract_details("search", meta) do
    "(#{meta[:results_count] || "?"} results)"
  end

  defp extract_details("ask", meta) do
    case meta[:answer] do
      answer when is_binary(answer) ->
        preview = String.slice(answer, 0, 50)
        if String.length(answer) > 50, do: "(\"#{preview}...\")", else: "(\"#{preview}\")"
      _ -> ""
    end
  end

  defp extract_details("embed", meta) do
    "(#{meta[:dimensions] || "?"} dims)"
  end

  defp extract_details("embed_batch", meta) do
    "(#{meta[:count] || "?"} texts)"
  end

  defp extract_details("agent.rewrite", meta) do
    if meta[:query], do: "(\"#{String.slice(meta[:query], 0, 40)}...\")", else: ""
  end

  defp extract_details("agent.select", meta) do
    "(#{length(meta[:selected] || [])} collections)"
  end

  defp extract_details("agent.expand", meta) do
    "(#{length(meta[:queries] || [])} queries)"
  end

  defp extract_details("agent.decompose", meta) do
    "(#{length(meta[:subquestions] || [])} subquestions)"
  end

  defp extract_details("agent.search", meta) do
    "(#{meta[:total_chunks] || "?"} chunks)"
  end

  defp extract_details("agent.rerank", meta) do
    "(#{meta[:kept] || "?"}/#{meta[:original] || "?"} kept)"
  end

  defp extract_details("agent.answer", _meta), do: ""

  defp extract_details("agent.self_correct", meta) do
    "(attempt #{meta[:attempt] || "?"})"
  end

  defp extract_details(_event, _meta), do: ""
end
