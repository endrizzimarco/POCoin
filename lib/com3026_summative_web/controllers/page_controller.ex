defmodule Com3026SummativeWeb.PageController do
  use Com3026SummativeWeb, :controller

  def index(conn, _params) do
    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> Plug.Conn.send_file(200, "priv/app/index.html")
    |> halt()
  end
end
