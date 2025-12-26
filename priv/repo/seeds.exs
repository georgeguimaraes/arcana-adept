# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Seed some sample documents for Arcana

alias Adept.Repo

# Sample documents about Elixir and Phoenix
documents = [
  """
  # Getting Started with Elixir

  Elixir is a dynamic, functional language designed for building scalable and maintainable applications.
  It runs on the Erlang VM (BEAM), known for running low-latency, distributed, and fault-tolerant systems.

  ## Key Features

  - **Functional Programming**: Elixir is a functional language with immutable data structures.
  - **Concurrency**: Built on the Actor model with lightweight processes.
  - **Fault Tolerance**: Supervisors can restart failed processes automatically.
  - **Metaprogramming**: Powerful macro system for extending the language.

  ## Installation

  You can install Elixir using your package manager or via asdf:

  ```bash
  asdf plugin add elixir
  asdf install elixir latest
  ```
  """,
  """
  # Phoenix Framework Overview

  Phoenix is a productive web framework that does not compromise speed or maintainability.
  It leverages Elixir's performance and concurrency to build highly scalable web applications.

  ## Key Components

  - **Endpoints**: Entry point for HTTP requests
  - **Routers**: Map URLs to controllers
  - **Controllers**: Handle request/response cycle
  - **Views/Templates**: Render HTML responses
  - **LiveView**: Real-time UI without JavaScript

  ## Creating a New Project

  ```bash
  mix phx.new my_app
  cd my_app
  mix ecto.setup
  mix phx.server
  ```

  Visit http://localhost:4000 to see your app.
  """,
  """
  # Understanding GenServer in Elixir

  GenServer is a behavior module for implementing the server of a client-server relation.
  It's one of the most commonly used abstractions in OTP.

  ## Basic Structure

  A GenServer has:
  - **init/1**: Initialize state when server starts
  - **handle_call/3**: Handle synchronous requests
  - **handle_cast/2**: Handle asynchronous requests
  - **handle_info/2**: Handle other messages

  ## Example

  ```elixir
  defmodule Counter do
    use GenServer

    def start_link(initial) do
      GenServer.start_link(__MODULE__, initial, name: __MODULE__)
    end

    def init(initial), do: {:ok, initial}

    def handle_call(:get, _from, state), do: {:reply, state, state}
    def handle_cast(:increment, state), do: {:noreply, state + 1}
  end
  ```
  """,
  """
  # Ecto: Database Wrapper for Elixir

  Ecto is a toolkit for data mapping and language integrated query for Elixir.
  It provides schemas, changesets, and query composition.

  ## Schemas

  Schemas map database tables to Elixir structs:

  ```elixir
  defmodule User do
    use Ecto.Schema

    schema "users" do
      field :name, :string
      field :email, :string
      has_many :posts, Post
      timestamps()
    end
  end
  ```

  ## Changesets

  Changesets track and validate changes:

  ```elixir
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email])
    |> validate_required([:name, :email])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
  end
  ```
  """,
  """
  # LiveView: Real-time UIs with Elixir

  Phoenix LiveView enables rich, real-time user experiences with server-rendered HTML.
  No JavaScript required for most interactive features.

  ## How It Works

  1. Initial page load is server-rendered HTML
  2. WebSocket connection established
  3. User events sent to server
  4. Server updates state and sends diff
  5. Client patches DOM efficiently

  ## Example

  ```elixir
  defmodule CounterLive do
    use Phoenix.LiveView

    def mount(_params, _session, socket) do
      {:ok, assign(socket, count: 0)}
    end

    def handle_event("increment", _, socket) do
      {:noreply, update(socket, :count, &(&1 + 1))}
    end

    def render(assigns) do
      ~H\"\"\"
      <button phx-click="increment">Count: <%= @count %></button>
      \"\"\"
    end
  end
  ```
  """
]

IO.puts("Ingesting #{length(documents)} sample documents...")

for {doc, index} <- Enum.with_index(documents, 1) do
  {:ok, _} = Arcana.ingest(doc, repo: Repo, format: :markdown)
  IO.puts("  Ingested document #{index}/#{length(documents)}")
end

IO.puts("\nDone! Visit http://localhost:4000/arcana to see the dashboard.")
