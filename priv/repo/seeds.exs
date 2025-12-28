# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Seed sample documents for Arcana, organized into collections

alias Adept.Repo

# Elixir Language Guides
elixir_docs = [
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
  # Pattern Matching in Elixir

  Pattern matching is one of Elixir's most powerful features. It allows you to match
  against data structures and bind variables in a single operation.

  ## Basic Examples

  ```elixir
  # Matching tuples
  {:ok, result} = {:ok, 42}

  # Matching lists
  [head | tail] = [1, 2, 3]
  # head = 1, tail = [2, 3]

  # Matching maps
  %{name: name} = %{name: "Alice", age: 30}
  # name = "Alice"
  ```

  ## In Function Clauses

  ```elixir
  def greet(%{name: name}), do: "Hello, #{name}!"
  def greet(_), do: "Hello, stranger!"
  ```

  Pattern matching makes code more declarative and easier to understand.
  """
]

# Phoenix Framework Guides
phoenix_docs = [
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
  """,
  """
  # Phoenix Channels for Real-time Communication

  Channels provide a way to handle real-time communication in Phoenix.
  They're built on WebSockets and provide pub/sub functionality.

  ## Use Cases

  - Chat applications
  - Live notifications
  - Collaborative editing
  - Real-time dashboards
  - Multiplayer games

  ## Example

  ```elixir
  defmodule MyAppWeb.RoomChannel do
    use Phoenix.Channel

    def join("room:" <> room_id, _params, socket) do
      {:ok, assign(socket, :room_id, room_id)}
    end

    def handle_in("new_message", %{"body" => body}, socket) do
      broadcast!(socket, "new_message", %{body: body})
      {:noreply, socket}
    end
  end
  ```
  """
]

# Ecto Database Guides
ecto_docs = [
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
  # Ecto Queries

  Ecto provides a powerful query DSL that compiles to efficient SQL.

  ## Basic Queries

  ```elixir
  # Get all users
  Repo.all(User)

  # Filter with where
  Repo.all(from u in User, where: u.age > 18)

  # Select specific fields
  Repo.all(from u in User, select: {u.name, u.email})
  ```

  ## Composable Queries

  ```elixir
  def active(query) do
    from u in query, where: u.active == true
  end

  def by_age(query, age) do
    from u in query, where: u.age >= ^age
  end

  # Compose them
  User
  |> active()
  |> by_age(21)
  |> Repo.all()
  ```
  """,
  """
  # Ecto Migrations

  Migrations allow you to evolve your database schema over time.

  ## Creating Migrations

  ```bash
  mix ecto.gen.migration create_users
  ```

  ## Migration Example

  ```elixir
  defmodule MyApp.Repo.Migrations.CreateUsers do
    use Ecto.Migration

    def change do
      create table(:users) do
        add :name, :string, null: false
        add :email, :string, null: false
        add :age, :integer

        timestamps()
      end

      create unique_index(:users, [:email])
    end
  end
  ```

  Run with `mix ecto.migrate`.
  """
]

IO.puts("Ingesting sample documents into collections...")

IO.puts("\n  Collection: elixir-guides")

for {doc, index} <- Enum.with_index(elixir_docs, 1) do
  {:ok, _} = Arcana.ingest(doc, repo: Repo, format: :markdown, collection: "elixir-guides")
  IO.puts("    Ingested document #{index}/#{length(elixir_docs)}")
end

IO.puts("\n  Collection: phoenix-guides")

for {doc, index} <- Enum.with_index(phoenix_docs, 1) do
  {:ok, _} = Arcana.ingest(doc, repo: Repo, format: :markdown, collection: "phoenix-guides")
  IO.puts("    Ingested document #{index}/#{length(phoenix_docs)}")
end

IO.puts("\n  Collection: ecto-guides")

for {doc, index} <- Enum.with_index(ecto_docs, 1) do
  {:ok, _} = Arcana.ingest(doc, repo: Repo, format: :markdown, collection: "ecto-guides")
  IO.puts("    Ingested document #{index}/#{length(ecto_docs)}")
end

total = length(elixir_docs) + length(phoenix_docs) + length(ecto_docs)
IO.puts("\nDone! Ingested #{total} documents into 3 collections.")
IO.puts("Visit http://localhost:4000/arcana to see the dashboard.")
