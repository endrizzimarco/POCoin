defmodule WebServer do
  import Plug.Conn

  def init(options) do
    {nodes_pids, master_pid, wallet_pids} = Master.start()
  end

  def call(conn, pids) do
    {nodes_pids, master_pid, wallet_pids} = pids

    case conn.path_info do
      # https://elixirstream.dev/regex/31910489-405c-40fb-aa4e-a9d4f285d57a - regex that matches ~balance?wallet=w1~
      ["balance"] ->
        conn = Plug.Conn.fetch_query_params(conn)
        params = conn.query_params
        response(conn, Wallet.balance(get_pid(params["wallet"])))
      ["send", w, to, amount] -> response(conn, Wallet.send(get_pid(w), to, amount))
      ["world"] -> response(conn, "lol")
      _ -> response(conn, "not found")
    end
  end

  def response(conn, data) do
    conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(data))
  end

  # def response_with_text(conn, data) do
  #   conn
  #     |> put_resp_content_type("text/plain")
  #     |> send_resp(200, data)
  # end

  defp get_pid(name) do
    :global.whereis_name(String.to_atom(name))
  end
end
