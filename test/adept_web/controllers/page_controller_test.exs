defmodule AdeptWeb.PageControllerTest do
  use AdeptWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Arcana"
    assert html =~ "Powered by Arcana"
  end
end
