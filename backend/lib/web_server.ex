defmodule WebServer do
  import Plug.Conn

  defimpl Jason.Encoder, for: Tuple do
    def encode(data, opts) when is_tuple(data) do
      Jason.Encode.list(Tuple.to_list(data), opts)
    end
  end

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
        response(conn, params["wallet"] |> get_pid |> Wallet.available_utxos())

      ["history"] ->
        response(conn, params["wallet"] |> get_pid |> Wallet.available_utxos())

      # ======================
      # ------ Node API ------
      # ======================
      ["blockchain"] ->
        data = params["node"] |> get_pid |> BlockchainNode.get_blockchain()

        data =
          Enum.map(data, fn block ->
            Map.put(block, :transaction, %{
              block.transaction
              | inputs: encode_64(block.transaction.inputs),
                signatures: encode_64(block.transaction.signatures)
            })
          end)

        response(conn, data)

      _ ->
        response(conn, "endpoint not found -> #{conn.path_info}")
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

  defp encode_64(lst) do
    Enum.map(lst, fn x -> Base.encode64(x) end)
  end
end
