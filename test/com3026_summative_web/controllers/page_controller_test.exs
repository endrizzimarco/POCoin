defmodule Com3026SummativeWeb.PageControllerTest do
  use Com3026SummativeWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "Welcome to Phoenix!"
  end
end
