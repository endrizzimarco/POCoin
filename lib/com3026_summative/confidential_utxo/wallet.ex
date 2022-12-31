# ==== wallet API ====
#   send(w, address, amount) ~ send money to another wallet
#   generate_address(w) ~ generate a new address for the wallet
#   balance(w) ~ get wallet balance
#   history(w) ~ get the history of every transaction

defmodule Wallet do
  def start(node) do
    state = %{
      node: node, # pid of the node this wallet communicates with
      available_UTXOs: %{}, # %{{amount, txid} => address}
      addresses: %{}, # contains the pub/private keypairs for every address %{address => {pub, priv}}
      past_transactions: %{}, # %{txid -> tx}
      pending: %{}, # store transactions until confirmed in the blockchain %{txid => {from, to, amount}}
      balance: 0, # easier than looping through `past_transactions` every time
      scanned_height: 0 # block height of the last block scanned in the blockchain
    }
    run(state)
  end

  def run(state) do
    state = receive do
      {:spend, client, to_addr, amount} ->
        # select UTXOs to spend and generate a change address
        {from_addrs, change} = select_utxos(state, amount)

        # generate a new address for the change
        {change_addr, keypair} = cond do
          change > 0 -> generate_address()
          change < 0 -> raise("not enough funds")
          change == 0 -> nil
        end

        # create transaction payload
        transaction = create_transaction(state, from_addrs, to_addr, amount, change, change_addr)
        txid = :crypto.hash(:sha256, transaction)

        # send transaction to node for processing
        send(state.node, {:transaction, transaction, txid})
        send(client, {:ok, transaction})

        # update state for new transaction
        addresses = if change_addr, do: %{state | addresses: Map.put(state.addresses, change_addr, keypair)}, else: state.addresses
        %{state | pending: Map.put(state.pending, txid, transaction),
                  balance: state.balance - amount,
                  available_UTXOs: Map.drop(state.available_UTXOs, transaction.inputs),
                  addresses: addresses}

      {:generate_address, client} ->
        {addr, keypair} = generate_address()
        send(client, {:address, addr})
        %{state | addresses: Map.put(state.addresses, addr, keypair)}

      {:get_balance, client} ->
        send(client, {:balance, state.balance})
        state

      {:get_history, client} ->
        send(client, {:history, state.past_transactions})
        state

      _ -> state
    end

    poll_for_blocks(state)
    run(state)
  end

  # ======================
  # ----- Public API -----
  # ======================
  def send(w, address, amount) do
    if amount < 0, do: raise("good one, you can't send negative money")
    send(w, {:spend, self(), address, amount})
    receive do
      {:transaction, data} -> data
      _ -> :fail
    after
      100 -> :timeout
    end
  end

  # return an invoice address (limitation: not HD)
  def generate_address(w) do
    send(w, {:generate_address, self()})
    receive do
      {:transaction, data} -> data
      _ -> :fail
    after
      100 -> :timeout
    end
  end

  # returns the balance of an input wallet
  def balance(w) do
    send(w, {:get_balance, self()})
    receive do
      {:balance, data} -> data
      _ -> :fail
    after
      100 -> :timeout
    end
  end

  def history(w) do
    send(w, {:get_history, self()})
    receive do
      {:history, data} -> data
      _ -> :fail
    after
      100 -> :timeout
    end
  end

  # =====================
  # ------ Helpers ------
  # =====================
  defp create_transaction(state, from_addrs, to_addr, amount, change, change_addr) do
    pub_keys = for addr <- from_addrs, do: {state.addresses[addr][0]}
    outputs = if change_addr, do: [{to_addr, amount}], else: [{to_addr, amount}, {change_addr, change}]

    details = %{
      inputs: pub_keys, # will be turned into addresses by the node
      outputs: outputs
    }
    signatures = for addr <- from_addrs, do: digital_sig(details, state.addresses[addr])

    Map.put(details, :signatures, signatures)
  end

  # enumerates all UTXOs starting from smallest values until a sum greater than the amount is reached
  defp select_utxos(state, amount) do
    {total, keys} = Enum.reduce(state.available_UTXOs, {0, []}, fn {{val, _}, addr}, {tot, addrs} ->
      if tot + val < amount, do: {tot+val, addrs ++ [addr]}, else: {tot, addrs} end)
    {keys, total-amount}
  end

  # generates a key pair and its corresponding address
  defp generate_address() do
    {pub_key, priv_key} = :crypto.generate_key(:ecdh, :secp256k1)
    addr = :crypto.hash(:sha256, pub_key) |> Base.encode16()
    {addr, {pub_key, priv_key}}
  end

  defp digital_sig(details, {_, priv_key}) do
    :crypto.sign(:ecdsa, :sha256, :erlang.term_to_binary(details), [priv_key, :secp256k1])
  end

  defp owned_address(state, tx_outputs) do
    Enum.any?(tx_outputs, fn {addr, _} -> Map.has_key?(state.addresses, addr) end)
  end

  # Poll a node process for the latest blocks in the blockchain
  defp poll_for_blocks(state) do
    send(state.node, {:get_blocks, self(), state.scanned_height})
    receive do
      {:new_blocks, blocks} ->
        Enum.reduce(blocks, state, fn block, state ->
          state = %{state | scanned_height: block.index}
          cond do
            Map.has_key?(state.pending, block.index) ->  # for sent transactions...
              %{
                state |
                past_transactions: Map.put(state.past_transactions, block.index, block.transaction),
                pending: Map.delete(state.pending, block.txid)
              }

            owned_address(state, block.transaction.outputs) -> # for received transaction...
              available_utxo = for {addr, amount} <- block.transaction.outputs,
                                do: Map.put(state.available_utxo, {amount, block.txid}, addr) #TODO: might be wrong
              %{
                state |
                past_transactions: Map.put(state.past_transactions, block.index, block.transaction),
                balance: state.balance + block.transaction.amount,
                available_utxo: available_utxo,
                pending: Map.delete(state.pending, block.txid)
              }

            true ->
              state
            end
          end)

      {:up_to_date} -> state

      _ -> state
    after
      100 -> :timeout
    end
  end
end
