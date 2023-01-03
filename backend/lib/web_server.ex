defmodule WebServer do
  import Plug.Conn

  def init(options) do
    options
  end

  def call(conn, _opts) do
    case conn.request_path do
      "/hello" -> response(conn, "test")
      "/world" -> response(conn, "lol")
      _ -> response(conn, "not found")
    end
  end

  def response(conn, data) do
    conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(data))
  end
end
