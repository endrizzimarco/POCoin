defmodule Com3026SummativeWeb.PageController do
  use Com3026SummativeWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
