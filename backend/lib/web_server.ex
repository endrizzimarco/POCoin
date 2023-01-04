defmodule WebServer do
  import Plug.Conn

  def init(options) do
    {nodes_pids, master_pid, wallet_pids} = Master.start()
  end

  def call(conn, pids) do
    {nodes_pids, master_pid, wallet_pids} = pids

    case conn.path_info do
      ["balance"] ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        response(conn, Wallet.balance(get_pid(params["wallet"])))

      ["send"] ->
        params = Plug.Conn.fetch_query_params(conn).query_params
        wallet = get_pid(params["wallet"])
        to_addr = params["to"]
        amount = elem(Float.parse(params["amount"]), 0)
        response(conn, Wallet.send(wallet, to_addr, amount))

      ["world"] ->
        response(conn, "lol")

      _ ->
        response(conn, "not found")
    end
  end

  def response(conn, data) do
    conn
    |> put_resp_header("Access-Control-Allow-Origin", "*")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(data))
  end

  defp get_pid(name) do
    :global.whereis_name(String.to_atom(name))
  end
end
