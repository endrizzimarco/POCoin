defmodule WebServer do
  import Plug.Conn

  def init(options) do
    {nodes_pids, master_pid, wallet_pids} = Master.start()
  end

  def call(conn, pids) do
    {nodes_pids, master_pid, wallet_pids} = pids
    params = Plug.Conn.fetch_query_params(conn).query_params

    case conn.path_info do
      # ======================
      # ----- Wallet API -----
      # ======================
      ["balance"] ->
        response(conn, params["wallet"] |> get_pid |> Wallet.balance())

      ["available_balance"] ->
        response(conn, params["wallet"] |> get_pid |> Wallet.available_balance())

      ["send"] ->
        wallet = get_pid(params["wallet"])
        to_addr = params["to"]
        amount = elem(Float.parse(params["amount"]), 0)
        response(conn, Wallet.send(wallet, to_addr, amount))

      ["generate_address"] ->
        response(conn, params["wallet"] |> get_pid |> Wallet.generate_address())

      ["addresses"] ->
        response(conn, params["wallet"] |> get_pid |> Wallet.addresses())

      ["available_utxos"] ->
        response(conn, params["wallet"] |> get_pid |> Wallet.available_utxos() |> detuple())

      ["history"] ->
        response(conn, params["wallet"] |> get_pid |> Wallet.available_utxos() |> detuple())

      # ======================
      # ------ Node API ------
      # ======================
      ["blockchain"] ->
        response(conn, params["node"] |> get_pid |> BlockchainNode.get_blockchain() |> detuple())

      _ ->
        response(conn, "endpoint not found -> #{conn.path_info}")
    end
  end

  def detuple(data) do
    data = if is_tuple(data), do: Tuple.to_list(data), else: data
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
