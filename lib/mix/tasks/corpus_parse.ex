defmodule Mix.Tasks.Corpus.Parse do
  @moduledoc """
  Parses a MediaWiki XML dump file into a JSON corpus.

  Accepts `.xml`, `.xml.gz`, or `.xml.7z` files. Compressed files are
  extracted to a temp file automatically and cleaned up after parsing.

  ## Usage

      mix corpus.parse /path/to/tardis_pages_current.xml.7z
      mix corpus.parse /path/to/tardis_pages_current.xml.gz
      mix corpus.parse /path/to/tardis_pages_current.xml

  Output is saved to priv/corpus/doctor_who.json
  """

  use Mix.Task

  @output_path "priv/corpus/doctor_who.json"
  @base_url "https://tardis.fandom.com"

  @impl Mix.Task
  def run([path]) do
    path = Path.expand(path)

    unless File.exists?(path) do
      Mix.raise("File not found: #{path}")
    end

    Mix.shell().info("Parsing MediaWiki dump: #{path}")
    Mix.shell().info("Output: #{@output_path}")

    {xml_path, tmp} = prepare_xml(path)

    try do
      parse_xml(xml_path)
    after
      if tmp, do: File.rm(tmp)
    end
  end

  def run(_) do
    Mix.raise("Usage: mix corpus.parse <path_to_xml>")
  end

  defp prepare_xml(path) do
    cond do
      String.ends_with?(path, ".7z") ->
        Mix.shell().info("Extracting 7z archive...")
        tmp = Path.join(System.tmp_dir!(), "wiki_dump_#{System.unique_integer([:positive])}.xml")
        {output, status} = System.cmd("7z", ["x", "-so", path], into: File.stream!(tmp))
        if status != 0, do: Mix.raise("7z extraction failed: #{output}")
        {tmp, tmp}

      String.ends_with?(path, ".gz") ->
        Mix.shell().info("Decompressing gzip...")
        tmp = Path.join(System.tmp_dir!(), "wiki_dump_#{System.unique_integer([:positive])}.xml")
        compressed = File.read!(path)
        File.write!(tmp, :zlib.gunzip(compressed))
        {tmp, tmp}

      true ->
        {path, nil}
    end
  end

  defp parse_xml(xml_path) do
    file = File.open!(@output_path, [:write, :utf8])
    IO.write(file, "[\n")

    initial_state = %{
      current_element: nil,
      page: %{},
      chars: [],
      count: 0,
      skipped: 0,
      redirect: false,
      file: file
    }

    result =
      :xmerl_sax_parser.file(
        String.to_charlist(xml_path),
        event_fun: &handle_event/3,
        event_state: initial_state
      )

    case result do
      {:ok, final_state, _rest} ->
        IO.write(file, "\n]")
        File.close(file)

        Mix.shell().info("\nDone!")
        Mix.shell().info("Articles saved: #{final_state.count}")
        Mix.shell().info("Skipped (redirects, short, non-content): #{final_state.skipped}")

        file_size = File.stat!(@output_path).size
        Mix.shell().info("File size: #{div(file_size, 1024 * 1024)} MB")

      {:fatal_error, _location, reason, _end_tags, _state} ->
        File.close(file)
        Mix.raise("XML parsing error: #{inspect(reason)}")
    end
  end

  defp handle_event({:startElement, _, ~c"page", _, _}, _loc, state) do
    %{state | page: %{}, redirect: false, chars: []}
  end

  defp handle_event({:startElement, _, ~c"redirect", _, _}, _loc, state) do
    %{state | redirect: true}
  end

  defp handle_event({:startElement, _, elem, _, _}, _loc, state)
       when elem in [~c"title", ~c"ns", ~c"text"] do
    %{state | current_element: elem, chars: []}
  end

  defp handle_event({:characters, chars}, _loc, %{current_element: elem} = state)
       when not is_nil(elem) do
    %{state | chars: [state.chars, chars]}
  end

  defp handle_event({:endElement, _, elem, _}, _loc, %{current_element: elem} = state)
       when elem in [~c"title", ~c"ns", ~c"text"] do
    value = IO.chardata_to_string(state.chars)

    key =
      case elem do
        ~c"title" -> :title
        ~c"ns" -> :ns
        ~c"text" -> :text
      end

    %{state | current_element: nil, page: Map.put(state.page, key, value), chars: []}
  end

  defp handle_event({:endElement, _, ~c"page", _}, _loc, state) do
    process_page(state)
  end

  defp handle_event(_event, _loc, state), do: state

  defp process_page(%{redirect: true} = state) do
    %{state | skipped: state.skipped + 1}
  end

  defp process_page(%{page: %{ns: ns}} = state) when ns != "0" do
    %{state | skipped: state.skipped + 1}
  end

  defp process_page(%{page: page} = state) do
    text = clean_wikitext(page[:text] || "")

    if String.length(text) > 100 do
      count = state.count + 1

      if rem(count, 1000) == 0 do
        Mix.shell().info("  Processed #{count} articles...")
      end

      article = %{
        title: page[:title],
        url: "#{@base_url}/wiki/#{URI.encode(page[:title])}",
        content: text,
        source: "tardis.fandom.com",
        scraped_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      prefix = if count == 1, do: "", else: ",\n"
      IO.write(state.file, prefix <> Jason.encode!(article))

      %{state | count: count}
    else
      %{state | skipped: state.skipped + 1}
    end
  end

  defp clean_wikitext(text) do
    text
    |> remove_templates()
    |> String.replace(~r/\[\[File:[^\]]+\]\]/i, "")
    |> String.replace(~r/\[\[Image:[^\]]+\]\]/i, "")
    |> String.replace(~r/\[\[[^\]|]+\|([^\]]+)\]\]/, "\\1")
    |> String.replace(~r/\[\[([^\]]+)\]\]/, "\\1")
    |> String.replace(~r/\[https?:[^\]]+\s+([^\]]+)\]/, "\\1")
    |> String.replace(~r/\[https?:[^\]]+\]/, "")
    |> String.replace(~r/<ref[^>]*>.*?<\/ref>/s, "")
    |> String.replace(~r/<ref[^>]*\/>/s, "")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/'{2,5}/, "")
    |> String.replace(~r/^=+\s*(.+?)\s*=+$/m, "\n\\1\n")
    |> String.replace(~r/\[\[Category:[^\]]+\]\]/i, "")
    |> String.replace(~r/__[A-Z]+__/, "")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  defp remove_templates(text) do
    cleaned = String.replace(text, ~r/\{\{[^{}]*\}\}/, "")

    if cleaned != text do
      remove_templates(cleaned)
    else
      cleaned
    end
  end
end
