defmodule Adept.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AdeptWeb.Telemetry,
      Adept.Repo,
      {DNSCluster, query: Application.get_env(:adept, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Adept.PubSub},
      # Arcana embeddings serving for semantic search
      Arcana.Embedding.Local,
      # Start to serve requests, typically the last entry
      AdeptWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Adept.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    AdeptWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
