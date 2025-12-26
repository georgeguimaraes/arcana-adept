defmodule Adept.Repo do
  use Ecto.Repo,
    otp_app: :adept,
    adapter: Ecto.Adapters.Postgres
end
