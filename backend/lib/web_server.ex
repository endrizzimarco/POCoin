defmodule WebServer do
  import Plug.Conn

  defimpl Jason.Encoder, for: Tuple do
    def encode(data, opts) when is_tuple(data) do
      Jason.Encode.list(Tuple.to_list(data), opts)
    end
  end

  def init(_options) do
    Master.start()
  end

  def call(conn, _options) do
    params = Plug.Conn.fetch_query_params(conn).query_params

    case conn.path_info do
      # ======================
      # ----- Wallet API -----
      # ======================
      ["wallet_stats"] ->
        w = get_pid(params["wallet"])
        response(conn, %{
          total_balance: Wallet.balance(w) |> cast_float() |> Float.round(2),
          available_balance: Wallet.available_balance(w) |> cast_float()|> Float.round(2),
          addresses: Enum.map(Wallet.addresses(w), fn {addr, {pub, priv}} -> Map.put(%{}, addr, {Base.encode64(pub), Base.encode64(priv)}) end),
          next_pending: Wallet.get_pending_tx(w),
          available_utxos: Enum.with_index(Wallet.available_utxos(w)) |> Enum.map(fn {{addr, balance}, index} ->
            %{key: index,
              address: addr,
              balance: balance |> cast_float() |> Float.round(2)} end),
          history: Enum.map(Wallet.history(w), fn {height, type, tx} ->
            %{block: height,
              type: type,
              txid: tx.txid |> String.slice(0, 25),
              amount: Enum.at(tx.outputs, 0) |> elem(1) |> cast_float() |> Float.round(2)} end) |> Enum.reverse()
        })

      ["send"] ->
        wallet = get_pid(params["wallet"])
        to_addr = params["to_addr"]
        amount = elem(Float.parse(params["amount"]), 0)
        response(conn, Wallet.send(wallet, to_addr, amount))

      ["generate_address"] ->
        response(conn, params["wallet"] |> get_pid |> Wallet.generate_address())

      # ======================
      # ------ Node API ------
      # ======================
      ["node_stats"] ->
        n = params["node"] |> get_pid
        response(conn, %{
          mempool: BlockchainNode.get_mempool(n) |> Enum.map(fn txid -> %{txid: txid |> String.slice(0, 25)} end),
          current: BlockchainNode.get_working_on(n),
          mining_power: BlockchainNode.get_mining_power(n) |> cast_float() |> Float.round(2),
          utxos: BlockchainNode.get_utxos(n) |> Enum.map(fn {addr, balance} ->
            %{address: addr,
            balance: balance |> cast_float() |> Float.round(2)} end),
        })

      ["blockchain"] ->
        node = params["node"] |> get_pid
        height = params["height"] |> String.to_integer()
        data = BlockchainNode.get_new_blocks(node, height)
        data = if data != :up_to_date do
            Enum.map(data, fn block ->
              Map.put(block, :transaction, %{
                block.transaction
                | inputs: encode_64(block.transaction.inputs),
                  signatures: encode_64(block.transaction.signatures)
              })
            end)
        else
          data
        end
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

  defp cast_float(n), do: n * 1.0

  defp get_pid(name) do
    :global.whereis_name(String.to_atom(name))
  end

  defp encode_64(lst) do
    Enum.map(lst, fn x -> Base.encode64(x) end)
  end
end
