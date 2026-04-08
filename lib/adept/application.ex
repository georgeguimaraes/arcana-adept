defmodule Adept.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # On macOS use EMLX with GPU device, on other platforms use EXLA.
    # Set BOTH the global tensor backend AND the default Nx.Defn
    # compiler so libraries that JIT-compile forward passes (Bumblebee,
    # Hallmark, Axon.predict) end up running on the same backend their
    # weights were loaded onto. Otherwise predict_batch produces
    # tensors on one backend and the weights live on another, and any
    # subsequent Nx op that mixes them crashes (see Hallmark's
    # classifier head matmul for an example).
    case :os.type() do
      {:unix, :darwin} ->
        Nx.global_default_backend({EMLX.Backend, device: :gpu})
        Nx.Defn.default_options(compiler: EMLX)

      _ ->
        Nx.global_default_backend(EXLA.Backend)
        Nx.Defn.default_options(compiler: EXLA)
    end

    # Attach Arcana telemetry handlers for logging
    Arcana.Telemetry.Logger.attach()

    children = [
      AdeptWeb.Telemetry,
      Adept.Repo,
      {DNSCluster, query: Application.get_env(:adept, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Adept.PubSub},
      # Local embedder for Arcana
      Arcana.Embedder.Local,
      Arcana.TaskSupervisor,
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
