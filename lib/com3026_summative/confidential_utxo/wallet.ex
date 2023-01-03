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
        {utxo_keys, from_addrs, change} = select_utxos(state, amount)

        if change < 0 do
          # TODO: check the pending set if any change is available in the future
          # TODO: if so, add transaction to txpool
          send(client, {:error, "not enough funds or change not yet available to spend"})
          state
        else
          # generate a new address for the change
          {change_addr, keypair} = cond do
            change > 0 -> generate_address()
            change == 0 -> nil
          end

          # create transaction payload
          transaction = create_transaction(state, from_addrs, to_addr, amount, change, change_addr)
          txid = :crypto.hash(:sha256, :erlang.term_to_binary(transaction)) |> Base.encode32()

          # send transaction to node for processing
          send(state.node, {:new_transaction, self(), txid, transaction})
          receive do
            {:ok, txid} -> IO.puts("transaction #{inspect txid} accepted by node #{inspect state.node}")
            {:bad_transaction, _} -> IO.puts("transaction #{inspect txid} rejected: invalid payload")
            after 1000 -> IO.puts("rejected: timeout")
          end
          send(client, {:ok, transaction})

          # update state for new transaction
          addresses = if change_addr != nil, do: %{state | addresses: Map.put(state.addresses, change_addr, keypair)}, else: state.addresses
          %{state | pending: Map.put(state.pending, txid, transaction),
                    balance: state.balance - amount,
                    available_UTXOs: Map.drop(state.available_UTXOs, [utxo_keys]),
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
        send(client, {:balance, state.balance})
        state

      {:get_history, client} ->
        send(client, {:history, state.past_transactions})
        state

      _ -> state
      after 1000 -> state
    end
    state = poll_for_blocks(state)
    run(state)
  end

  # ======================
  # ----- Public API -----
  # ======================
  def send(w, address, amount) do
    if amount < 0, do: raise("good one, you can't send negative money")
    IO.puts("sending #{amount} to #{address}")
    send(w, {:spend, self(), address, amount})
    receive do
      {:transaction, tx, _} -> tx
      {:error, msg} -> IO.puts("error: #{msg}")
    after
      1000 -> :timeout
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

  # returns the balance of an input wallet
  def balance(w) do
    send(w, {:get_balance, self()})
    receive do
      {:balance, bal} -> bal
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
    {utxo_keys, total, addrs} = Enum.reduce_while(state.available_UTXOs, {{}, 0, []}, fn {{val, txid}, addr}, {_, tot, addrs} ->
      if tot + val < amount, do: {:cont, {{val, txid}, tot+val, addrs ++ [addr]}}, else: {:halt, {{val, txid}, tot+val, addrs ++ [addr]}} end)
    {utxo_keys, addrs, total-amount}
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

  defp owned_address(state, tx_outputs) do
    Enum.any?(tx_outputs, fn {addr, _} -> Map.has_key?(state.addresses, addr) end)
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
                past_transactions: Map.put(state.past_transactions, block.height, block.transaction),
                pending: Map.delete(state.pending, block.transaction.txid)
              }

            owned_address(state, block.transaction.outputs) -> # for received transaction...
              state = Enum.reduce(block.transaction.outputs, state, fn {addr, amount}, state ->
                          if Map.has_key?(state.addresses, addr) do
                              %{state | available_UTXOs: Map.put(state.available_UTXOs, {amount, block.transaction.txid}, addr),
                                        balance: state.balance + amount}
                          else
                            state
                          end
                        end)
              %{state | past_transactions: Map.put(state.past_transactions, block.height, block.transaction),
                        pending: Map.delete(state.pending, block.transaction.txid)}
              # TODO: deliver the transactions in txpool if possible

            true -> state # not related to this wallet
          end
        end)

      {:up_to_date} -> state

      _ -> state
    end
  end
end