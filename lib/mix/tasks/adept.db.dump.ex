defmodule Mix.Tasks.Adept.Db.Dump do
  @shortdoc "Dump the Adept dev database to dumps/ as a timestamped gzip"

  @moduledoc """
  Dumps the configured Adept database to `dumps/adept_<env>_<ts>.sql.gz`.

  Shells out to `pg_dump` with the credentials from `Adept.Repo.config/0`,
  pipes the SQL through `gzip`, and writes the compressed file.

  ## Usage

      mix adept.db.dump                 # dumps dev DB to dumps/
      MIX_ENV=test mix adept.db.dump    # dumps test DB

  ## Options

    * `--output DIR` - output directory (default: `dumps`)
    * `--no-data` - schema only, no rows

  Output filename is `adept_<env>_<YYYY-MM-DD_HHMMSS>.sql.gz`.

  The `dumps/` directory is gitignored for `.sql.gz` files so dumps
  don't end up in version control.
  """

  use Mix.Task

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args, strict: [output: :string, no_data: :boolean])

    output_dir = Keyword.get(opts, :output, "dumps")
    schema_only? = Keyword.get(opts, :no_data, false)

    config = Adept.Repo.config()

    File.mkdir_p!(output_dir)

    timestamp =
      NaiveDateTime.utc_now()
      |> NaiveDateTime.truncate(:second)
      |> NaiveDateTime.to_iso8601()
      |> String.replace(":", "")
      |> String.replace("T", "_")

    filename = "adept_#{Mix.env()}_#{timestamp}.sql.gz"
    path = Path.join(output_dir, filename)

    pg_dump_args =
      [
        "--host=#{config[:hostname] || "localhost"}",
        "--port=#{config[:port] || 5432}",
        "--username=#{config[:username]}",
        "--dbname=#{config[:database]}",
        "--no-owner",
        "--no-privileges"
      ] ++ if(schema_only?, do: ["--schema-only"], else: [])

    env = [{"PGPASSWORD", config[:password] || ""}]

    Mix.shell().info("Dumping #{config[:database]} to #{path}...")

    {_, status} =
      System.cmd(
        "sh",
        ["-c", "pg_dump #{Enum.join(pg_dump_args, " ")} | gzip > #{path}"],
        env: env,
        stderr_to_stdout: true
      )

    case status do
      0 ->
        size = File.stat!(path).size
        Mix.shell().info("  wrote #{format_size(size)}")

      code ->
        File.rm(path)
        Mix.raise("pg_dump failed with exit code #{code}")
    end
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)}KB"

  defp format_size(bytes) when bytes < 1024 * 1024 * 1024,
    do: "#{Float.round(bytes / 1024 / 1024, 1)}MB"

  defp format_size(bytes), do: "#{Float.round(bytes / 1024 / 1024 / 1024, 2)}GB"
end
