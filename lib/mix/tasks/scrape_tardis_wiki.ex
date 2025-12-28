defmodule Mix.Tasks.Scrape.TardisWiki do
  @moduledoc """
  Scrapes Doctor Who articles from the TARDIS Wiki and saves to JSON.

  ## Usage

      # Scrape default articles (Doctors, companions, key episodes)
      mix scrape.tardis_wiki

      # Scrape large corpus (~500 articles from multiple story categories)
      mix scrape.tardis_wiki --large

      # Scrape specific category
      mix scrape.tardis_wiki --category "Tenth Doctor stories"

      # Scrape specific articles
      mix scrape.tardis_wiki --articles "Tenth Doctor,Rose Tyler,TARDIS"

      # Limit number of articles
      mix scrape.tardis_wiki --limit 50

  Output is saved to priv/corpus/doctor_who.json
  """

  use Mix.Task

  @base_url "https://tardis.fandom.com"
  @output_path "priv/corpus/doctor_who.json"

  # Key articles to scrape by default
  @default_articles [
    # The Doctors
    "First Doctor",
    "Second Doctor",
    "Third Doctor",
    "Fourth Doctor",
    "Fifth Doctor",
    "Sixth Doctor",
    "Seventh Doctor",
    "Eighth Doctor",
    "War Doctor",
    "Ninth Doctor",
    "Tenth Doctor",
    "Eleventh Doctor",
    "Twelfth Doctor",
    "Thirteenth Doctor",
    "Fourteenth Doctor",
    "Fifteenth Doctor",
    # Key companions
    "Rose Tyler",
    "Martha Jones",
    "Donna Noble",
    "Amy Pond",
    "Rory Williams",
    "Clara Oswald",
    "Bill Potts",
    "River Song",
    "Captain Jack Harkness",
    "Sarah Jane Smith",
    # Key concepts
    "TARDIS",
    "Time Lord",
    "Gallifrey",
    "Regeneration",
    "Sonic screwdriver",
    "Time Vortex",
    "Chameleon circuit",
    # Key enemies
    "Dalek",
    "Cyberman",
    "The Master",
    "Weeping Angel",
    "Sontaran",
    "Silurian",
    "The Silence",
    "Zygon",
    # Notable episodes/serials
    "An Unearthly Child (TV story)",
    "The Daleks (TV story)",
    "Genesis of the Daleks (TV story)",
    "The Caves of Androzani (TV story)",
    "Rose (TV story)",
    "Blink (TV story)",
    "The Day of the Doctor (TV story)",
    "Heaven Sent (TV story)"
  ]

  # Categories to scrape for --large option
  @story_categories [
    # Story categories per Doctor
    "First Doctor television stories",
    "Second Doctor television stories",
    "Third Doctor television stories",
    "Fourth Doctor television stories",
    "Fifth Doctor television stories",
    "Sixth Doctor television stories",
    "Seventh Doctor television stories",
    "Eighth Doctor television stories",
    "Ninth Doctor television stories",
    "Tenth Doctor television stories",
    "Eleventh Doctor television stories",
    "Twelfth Doctor television stories",
    "Thirteenth Doctor television stories",
    "Fourteenth Doctor television stories",
    "Fifteenth Doctor television stories",
    # Companions and characters
    "Companions of the First Doctor",
    "Companions of the Fourth Doctor",
    "Companions of the Tenth Doctor",
    "Companions of the Eleventh Doctor",
    "Companions of the Twelfth Doctor",
    "Recurring characters",
    # Enemies and species
    "Dalek individuals",
    "Cyberman individuals",
    "Time Lord individuals",
    "Alien species",
    "Robot individuals",
    # Concepts and technology
    "Types of TARDIS",
    "Time Lord technology",
    "Sonic devices",
    "Planets",
    "Earth locations",
    # More story types
    "Multi-Doctor television stories",
    "Regeneration stories",
    "UNIT stories",
    # Additional content
    "Sarah Jane Adventures characters",
    "The Doctor's companions",
    "Torchwood individuals",
    "Human villains",
    "UNIT members"
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          articles: :string,
          category: :string,
          limit: :integer,
          large: :boolean
        ]
      )

    Application.ensure_all_started(:req)

    articles =
      cond do
        opts[:articles] ->
          opts[:articles] |> String.split(",") |> Enum.map(&String.trim/1)

        opts[:category] ->
          fetch_category_articles(opts[:category], opts[:limit] || 100)

        opts[:large] ->
          fetch_large_corpus()

        true ->
          @default_articles
      end

    articles =
      if opts[:limit] do
        Enum.take(articles, opts[:limit])
      else
        articles
      end

    Mix.shell().info("Scraping #{length(articles)} articles from TARDIS Wiki...")

    corpus =
      articles
      |> Enum.with_index(1)
      |> Enum.map(fn {title, index} ->
        Mix.shell().info("  [#{index}/#{length(articles)}] #{title}")
        scrape_article(title)
      end)
      |> Enum.reject(&is_nil/1)

    # Save to JSON
    json = Jason.encode!(corpus, pretty: true)
    File.write!(@output_path, json)

    Mix.shell().info("\nSaved #{length(corpus)} articles to #{@output_path}")
    Mix.shell().info("Total size: #{div(byte_size(json), 1024)} KB")
  end

  defp scrape_article(title) do
    url = "#{@base_url}/wiki/#{URI.encode(title)}?action=raw"

    case Req.get(url, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        # Convert wikitext to plain text
        text = clean_wikitext(body)

        if String.length(text) > 100 do
          %{
            title: title,
            url: "#{@base_url}/wiki/#{URI.encode(title)}",
            content: text,
            source: "tardis.fandom.com",
            scraped_at: DateTime.utc_now() |> DateTime.to_iso8601()
          }
        else
          Mix.shell().info("    Skipping (too short)")
          nil
        end

      {:ok, %{status: status}} ->
        Mix.shell().info("    Failed: HTTP #{status}")
        nil

      {:error, reason} ->
        Mix.shell().info("    Error: #{inspect(reason)}")
        nil
    end
  end

  defp fetch_large_corpus do
    Mix.shell().info(
      "Fetching article list from #{length(@story_categories)} story categories..."
    )

    # Also include default articles (Doctors, companions, concepts)
    base_articles = @default_articles

    # Fetch from each story category
    story_articles =
      @story_categories
      |> Enum.flat_map(fn category ->
        Mix.shell().info("  Fetching: #{category}")
        articles = fetch_category_articles(category, 100)
        Mix.shell().info("    Found #{length(articles)} articles")
        articles
      end)

    # Combine and dedupe
    (base_articles ++ story_articles)
    |> Enum.uniq()
  end

  defp fetch_category_articles(category, limit) do
    # cmtype=page filters to only pages (excludes subcategories)
    url =
      "#{@base_url}/api.php?action=query&list=categorymembers&cmtitle=Category:#{URI.encode(category)}&cmlimit=#{limit}&cmtype=page&format=json"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        # Req auto-decodes JSON, so body is already a map
        body
        |> get_in(["query", "categorymembers"])
        |> Enum.map(& &1["title"])

      _ ->
        Mix.shell().error("Failed to fetch category: #{category}")
        []
    end
  end

  # Convert MediaWiki markup to plain text
  defp clean_wikitext(text) do
    text
    # Remove templates like {{...}}
    |> remove_templates()
    # Remove files/images [[File:...]]
    |> String.replace(~r/\[\[File:[^\]]+\]\]/i, "")
    |> String.replace(~r/\[\[Image:[^\]]+\]\]/i, "")
    # Convert links [[link|text]] to text, [[link]] to link
    |> String.replace(~r/\[\[[^\]|]+\|([^\]]+)\]\]/, "\\1")
    |> String.replace(~r/\[\[([^\]]+)\]\]/, "\\1")
    # Remove external links [http://... text]
    |> String.replace(~r/\[https?:[^\]]+\s+([^\]]+)\]/, "\\1")
    |> String.replace(~r/\[https?:[^\]]+\]/, "")
    # Remove refs <ref>...</ref>
    |> String.replace(~r/<ref[^>]*>.*?<\/ref>/s, "")
    |> String.replace(~r/<ref[^>]*\/>/s, "")
    # Remove HTML tags
    |> String.replace(~r/<[^>]+>/, "")
    # Remove bold/italic markup
    |> String.replace(~r/'{2,5}/, "")
    # Convert headers to text
    |> String.replace(~r/^=+\s*(.+?)\s*=+$/m, "\n\\1\n")
    # Remove categories
    |> String.replace(~r/\[\[Category:[^\]]+\]\]/i, "")
    # Remove magic words
    |> String.replace(~r/__[A-Z]+__/, "")
    # Clean up whitespace
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  # Remove nested templates - this is tricky with regex, so we do it iteratively
  defp remove_templates(text) do
    # Simple approach: remove non-nested templates first
    cleaned = String.replace(text, ~r/\{\{[^{}]*\}\}/, "")

    # If we removed something, try again (for nested templates)
    if cleaned != text do
      remove_templates(cleaned)
    else
      cleaned
    end
  end
end
