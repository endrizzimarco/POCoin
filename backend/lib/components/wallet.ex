# ==== wallet API ====
#   send(w, address, amount) ~ send money to another wallet
#   generate_address(w) ~ generate a new address for the wallet
#   add_keypair(w, {pub, priv}) ~ add a keypair to the wallet
#   balance(w) ~ get wallet balance
#   history(w) ~ get the history of every transaction

defmodule Wallet do
  def start(name, node) do
    pid = spawn(Wallet, :init, [node])
    pid = case :global.re_register_name(name, pid) do
      :yes -> pid
    end
    pid
  end

  def init(node) do
    state = %{
      node: node, # pid of the node this wallet communicates with
      available_UTXOs: %{}, # %{address => amount}
      addresses: %{}, # contains the pub/private keypairs for every address %{address => {{pub, priv}}
      past_transactions: [], # [{height, type, tx}]
      transaction_pool: [], # list of transactions that need to wait for UTXOs to become available
      pending: %{}, # store transactions until confirmed in the blockchain %{txid => {from, to, amount}}
      scanned_height: 0 # block height of the last block scanned in the blockchain
    }
    run(state)
  end

  def run(state) do
    state = receive do
      {:spend, client, to_addr, amount} ->
        # select UTXOs to spend and generate a change address
        {from_addrs, change} = select_utxos(state, amount)

        if change < 0 do
          cond do
            waiting_for_pending_utxos(state, amount) ->
              send(client, {:ok, "added to pending wallet transactions (waiting for other UTXOs to confirm)"})
              %{state | transaction_pool: state.transaction_pool ++ [{client, to_addr, amount}]}
            true ->
              send(client, {:error, "not enough funds"})
              state
          end
        else
          # generate a new address for the change
          {change_addr, keypair} = cond do
            change > 0 -> generate_address()
            change == 0 -> {nil, nil}
          end

          # create transaction payload
          transaction = create_transaction(state, from_addrs, to_addr, amount, change, change_addr)
          txid = :crypto.hash(:sha256, :erlang.term_to_binary(transaction)) |> Base.encode32()

          # send transaction to node for processing
          send(state.node, {:new_transaction, self(), txid, transaction})
          receive do
            {:ok, txid} -> send(client, {:ok, "transaction #{inspect txid} accepted by node #{inspect state.node}"})
            {:bad_transaction, _} -> send(client, {:error, "transaction #{inspect txid} rejected: invalid payload"})
            after 1000 -> send(client, {:error, "node timeout"})
          end

          # update state for new transaction
          addresses = if change_addr != nil, do: Map.put(state.addresses, change_addr, keypair), else: state.addresses
          # Enum.map(from_addrs, fn addr -> String.to_atom(addr) end)
          %{state | pending: Map.put(state.pending, txid, transaction),
                    available_UTXOs: Map.drop(state.available_UTXOs, from_addrs),
                    addresses: addresses}
        end

      {:generate_address, client} ->
        {addr, keypair} = generate_address()
        send(client, {:generated_address, addr})
        %{state | addresses: Map.put(state.addresses, addr, keypair)}

      {:add_keypair, client, keypair} ->
        {pub_key, _} = keypair
        addr = :crypto.hash(:sha256, pub_key) |> Base.encode64()
        send(client, {:added_keypair, addr})
        IO.puts("added address #{addr} to wallet #{inspect(self())}")
        %{state | addresses: Map.put(state.addresses, addr, keypair)}

      {:get_balance, client} ->
        send(client, {:balance, get_balance(state)})
        state

      {:get_available, client} ->
        send(client, {:available, get_available_balance(state)})
        state

      {:get_addresses, client} ->
        send(client, {:addresses, Map.to_list(state.addresses)})
        state

      {:get_utxos, client} ->
        send(client, {:utxos, Map.to_list(state.available_UTXOs)})
        state

      {:get_history, client} ->
        send(client, {:history, state.past_transactions})
        state

      _ -> state

      after 500 -> state
    end

    state = poll_for_blocks(state)
    run(state)
  end

  # ======================
  # ----- Public API -----
  # ======================
  def send(w, address, amount) do
    if amount < 0, do: raise("good one, you can't send negative money")
    IO.puts("request to send #{amount} to #{address}")
    send(w, {:spend, self(), address, amount})
    receive do
      {:ok, msg} -> IO.puts("ok: " <> msg)
      {:error, msg} -> IO.puts("error: " <> msg)
    after
      2000 -> :timeout
    end
  end

  # return an invoice address (limitation: not HD)
  def generate_address(w) do
    send(w, {:generate_address, self()})
    receive do
      {:generated_address, addr} -> addr
    after
      1000 -> :timeout
    end
  end

  # add keypair to the wallet
  def add_keypair(w, keypair) do
    send(w, {:add_keypair, self(), keypair})
    receive do
      {:added_keypair, addr} -> addr
    after
      1000 -> :timeout
    end
  end

  # returns the balance of an input wallet (including pending balance)
  def balance(w) do
    send(w, {:get_balance, self()})
    receive do
      {:balance, bal} -> bal
    after
      1000 -> :timeout
    end
  end

  # only returns the ready-to-spend balance of this wallet
  def available_balance(w) do
    send(w, {:get_available, self()})
    receive do
      {:available, bal} -> bal
    after
      1000 -> :timeout
    end
  end

  def addresses(w) do
    send(w, {:get_addresses, self()})
    receive do
      {:addresses, addrs} -> addrs
    after
      1000 -> :timeout
    end
  end

  def available_utxos(w) do
    send(w, {:get_utxos, self()})
    receive do
      {:utxos, utxos} -> utxos
    after
      1000 -> :timeout
    end
  end

  def history(w) do
    send(w, {:get_history, self()})
    receive do
      {:history, data} -> data
    after
      1000 -> :timeout
    end
  end

  # =====================
  # ------ Helpers ------
  # =====================
  defp create_transaction(state, from_addrs, to_addr, amount, change, change_addr) do
    pub_keys = for addr <- from_addrs, do: elem(state.addresses[addr], 0)
    outputs = if change_addr != nil, do: [{to_addr, amount}, {change_addr, change}], else: [{to_addr, amount}]

    details = %{
      inputs: pub_keys, # will be turned into addresses by the node
      outputs: outputs
    }
    # sign the transaction
    signatures = for addr <- from_addrs, do: digital_sig(details, state.addresses[addr])
    Map.put(details, :signatures, signatures)
  end

  # enumerates all UTXOs starting from smallest values until a sum greater than the amount is reached
  defp select_utxos(state, amount) do
    sorted_by_values = state.available_UTXOs |> Map.to_list |> Enum.sort(fn ({_, v1}, {_, v2}) -> v1 <= v2 end)
    {utxo_keys, total} = Enum.reduce_while(sorted_by_values, {[], 0}, fn {key, val}, {addrs, tot} ->
      if tot + val < 2, do: {:cont, {addrs ++ [key], tot+val}}, else: {:halt, {addrs ++ [key], tot+val}} end)
    {utxo_keys, total-amount}
  end

  # generates a key pair and its corresponding address
  defp generate_address() do
    {pub_key, priv_key} = :crypto.generate_key(:ecdh, :secp256k1)
    addr = :crypto.hash(:sha256, pub_key) |> Base.encode64()
    {addr, {pub_key, priv_key}}
  end

  defp digital_sig(details, {_, priv_key}) do
    :crypto.sign(:ecdsa, :sha256, :erlang.term_to_binary(details), [priv_key, :secp256k1])
  end

  defp owned_outputs(state, tx_outputs) do
    Enum.filter(tx_outputs, fn {addr, _} -> Map.has_key?(state.addresses, addr) end)
  end

  # return whether there are enough pending future UTXOs to cover a given amount
  defp waiting_for_pending_utxos(state, amount) do
    pending_balance(state) >= amount
  end

  defp deliver_txpool(state) do
    {{client, addr, needed_amount}, lst} = List.pop_at(state.transaction_pool, 0)
    if get_available_balance(state) >= needed_amount do
      send(self(), {:spend, client, addr, needed_amount})
      %{state | transaction_pool: lst}
    else
      %{state | transaction_pool: lst ++ [{client, addr, needed_amount}]}
    end
  end

  defp pending_balance(state) do
    pending_outs = Enum.reduce(state.pending, [], fn {_, tx}, lst -> lst ++ tx.outputs end)
    owned_outs = owned_outputs(state, pending_outs)
    Enum.reduce(owned_outs, 0, fn {_, amount}, sum -> sum + amount end)
  end

  defp get_balance(state) do
    get_available_balance(state) + pending_balance(state)
  end

  defp get_available_balance(state) do
    Enum.reduce(state.available_UTXOs, 0, fn {_addr, val}, sum -> sum + val end)
  end

  # Poll a node process for the latest blocks in the blockchain
  defp poll_for_blocks(state) do
    new_blocks = BlockchainNode.get_new_blocks(state.node, state.scanned_height)
    case new_blocks do
      [h | t] ->
        Enum.reduce([h | t], state, fn block, state ->
          state = %{state | scanned_height: block.height}
          cond do
            Map.has_key?(state.pending, block.height) ->  # for sent transactions...
              %{state |
                past_transactions: state.past_transactions ++ [{block.height, "send", block.transaction}],
                pending: Map.delete(state.pending, block.transaction.txid)
              }

            owned_outputs(state, block.transaction.outputs) -> # for received transaction...
              outs = owned_outputs(state, block.transaction.outputs)

              # handle outputs
              state = Enum.reduce(outs, state, fn {addr, amount}, state ->
                if Map.has_key?(state.available_UTXOs, addr) do
                  %{state | available_UTXOs: Map.update!(state.available_UTXOs, addr, fn val -> val+amount end)}
                else
                  %{state | available_UTXOs: Map.put(state.available_UTXOs, addr, amount)}
                end
              end)

              # handle transaction
              state = %{state | past_transactions: state.past_transactions ++ [{block.height, "receive", block.transaction}],
                                pending: Map.delete(state.pending, block.transaction.txid)}

              # deliver the transactions in txpool (if possible, else put them at the back of the queue)
              if state.transaction_pool != [] do
                deliver_txpool(state)
              else
                state
              end

            true -> state # not related to this wallet
          end
        end)

      :up_to_date -> state

      _ -> state
    end
  end
end
