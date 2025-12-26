defmodule AdeptWeb.PageController do
  use AdeptWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
