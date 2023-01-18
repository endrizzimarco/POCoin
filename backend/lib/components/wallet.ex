# ==== wallet API ====
#   send(w, address, amount) ~ send money to another wallet
#   generate_address(w) ~ generate a new address for the wallet
#   add_keypair(w, {pub, priv}) ~ add a keypair to the wallet
#   balance(w) ~ get wallet balance
#   history(w) ~ get the history of every transaction

defmodule Wallet do
  def start(name, node) do
    pid = spawn(Wallet, :init, [node])
    case :global.re_register_name(name, pid) do
      :yes -> pid
    end
  end

  def init(node) do
    state = %{
      node: node, # pid of the node this wallet communicates with
      available_UTXOs: %{}, # %{address => amount}
      addresses: %{}, # contains the pub/private keypairs for every address %{address => {{pub, priv}}
      past_transactions: [], # [{height, type, tx}]
      transaction_pool: [], # list of transactions that need to wait for UTXOs to become available [{client, to_addr, amount}]
      pending: %{}, # store transactions until confirmed in the blockchain %{txid => {utxo_used, to_addr, amount}}
      scanned_height: 0, # block height of the last block scanned in the blockchain
      counter: 0 # counter for ignored transactions
    }
    run(state)
  end

  def run(state) do
    state = receive do
      {:spend, client, to_addr, amount} ->
        # select UTXOs to spend and generate a change address
        {from_addrs, change} = select_utxos(state, amount)

        if change < 0 do
          handle_lack_of_funds(state, amount, to_addr, client)
        else
          # generate a new change address if needed
          {change_addr, keypair} = if change > 0, do: generate_address(), else: {nil, nil}

          # create transaction payload
          transaction = create_transaction(state, from_addrs, to_addr, amount, change, change_addr)
          txid = :crypto.hash(:sha256, :erlang.term_to_binary(transaction)) |> Base.encode32()

          # send transaction to node for processing
          send(state.node, {:new_transaction, self(), txid, transaction})
          handle_node_response(state, client, from_addrs, to_addr, amount, change_addr, keypair)
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

      {:get_pending_tx, client} ->
        cond do
          List.first(state.transaction_pool) != nil ->
            {_client, to_addr, amount} = List.first(state.transaction_pool)
            send(client, {:pending_tx, {to_addr, amount}})
          true -> send(client, {:pending_tx, nil})
        end
        state

      _ -> state

      after 200 -> state
    end
    run(state |> poll_for_blocks() |> poll_ignored_txs())
  end

  # ======================
  # ------ Handlers ------
  # ======================
  # receives the transaction response from the node and updates the wallet state accordingly
  defp handle_node_response(state, client, from_addrs, to_addr, amount, change_addr, keypair) do
    receive do
      {:ok, txid} ->
        if client != nil, do: send(client, {:ok, "Transaction #{inspect txid} accepted by node #{inspect state.node}"})
        # update state for new transaction
        addresses = if change_addr != nil, do: Map.put(state.addresses, change_addr, keypair), else: state.addresses
        %{state | pending: Map.put(state.pending, txid, {Map.take(state.available_UTXOs, from_addrs), to_addr, amount}),
                  available_UTXOs: Map.drop(state.available_UTXOs, from_addrs),
                  addresses: addresses}

      {:bad_transaction, txid} ->
        if client != nil, do: send(client, {:error, "transaction #{inspect txid} rejected: malformed transaction"})
        state

      after 1000 ->
        if client != nil, do: send(client, {:error, "node timeout"})
        state
    end
  end

  # handles the wallet not having enough funds (UTXOs avaialble) to send the transaction
  defp handle_lack_of_funds(state, amount, to_addr, client) do
    cond do
      waiting_for_pending_utxos(state, amount) ->
        if client != nil, do: send(client, {:ok, "Added to pending wallet transactions (waiting for other UTXOs to confirm)"})
        %{state | transaction_pool: state.transaction_pool ++ [{client, to_addr, amount}]}
      true ->
        if client != nil, do: send(client, {:error, "not enough funds"})
        state
    end
  end

  # =====================
  # ------ Helpers ------
  # =====================
  # return a transaction of shape: %{inputs: [pub_keys], outputs: [{to_addr, amount}], signatures: [sigs]}
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
      if tot + val < amount, do: {:cont, {addrs ++ [key], tot+val}}, else: {:halt, {addrs ++ [key], tot+val}} end)
    {utxo_keys, total-amount}
  end

  # updates the available UTXOs of this wallet based on the outputs of a transaction
  defp process_tx_outputs(state, outputs) do
    outs = owned_outputs(state, outputs)
    Enum.reduce(outs, state, fn {addr, amount}, state ->
      %{state | available_UTXOs: Map.update(state.available_UTXOs, addr, amount, fn val -> val+amount end)}
    end)
  end

  # returns outputs that belong to this wallet
  defp owned_outputs(state, tx_outputs) do
    Enum.filter(tx_outputs, fn {addr, _} -> Map.has_key?(state.addresses, addr) end)
  end

  # return whether there are enough pending future UTXOs to cover a given amount
  defp waiting_for_pending_utxos(state, amount) do
    pending_balance(state) >= amount
  end

  # =====================
  # ------ Crypto ------
  # =====================
  # generates a key pair and its corresponding address
  defp generate_address() do
    {pub_key, priv_key} = :crypto.generate_key(:ecdh, :secp256k1)
    addr = :crypto.hash(:sha256, pub_key) |> Base.encode64()
    {addr, {pub_key, priv_key}}
  end

  # signs a transaction with the private key of the sender
  defp digital_sig(details, {_, priv_key}) do
    :crypto.sign(:ecdsa, :sha256, :erlang.term_to_binary(details), [priv_key, :secp256k1])
  end

  # =====================
  # ------ Balance ------
  # =====================
  # get sum of change UTXOs to be confirmed
  defp pending_balance(state) do
    Enum.reduce(state.pending, 0, fn {_, {utxos, _, amount}}, acc ->
      acc - amount + Enum.reduce(utxos, acc, fn {_addr, val}, acc2 -> acc2 + val end) end)
  end

  # get total balance (available + pending)
  defp get_balance(state) do
    get_available_balance(state) + pending_balance(state)
  end

  # get balance available to spend (sum of available UTXOs)
  defp get_available_balance(state) do
    Enum.reduce(state.available_UTXOs, 0, fn {_addr, val}, sum -> sum + val end)
  end

  # =====================
  # ------ Tx Pool ------
  # =====================
  # check if there are transactions in the pool that can be delivered
  defp check_deliver_txpool(state) do
    if state.transaction_pool != [], do: deliver_txpool(state), else: state
  end

  # deliver a transaction from the pool if there are enough funds
  defp deliver_txpool(state) do
    # get the first transaction in the pool
    {{client, addr, needed_amount}, lst} = List.pop_at(state.transaction_pool, 0)

    if get_available_balance(state) >= needed_amount do
      send(self(), {:spend, client, addr, needed_amount})
      %{state | transaction_pool: lst}
    else
      %{state | transaction_pool: lst ++ [{client, addr, needed_amount}]}
    end
  end

  # =====================
  # ------ Pollers ------
  # =====================
  """
  polls a node to check whether a submitted transaction has been ignored

  Needed for the following case:
    Say that Alice sends coins to Bob on address X and before the tx settles Bob sends coins to Charlie using address X as input.
    The node will ignore the transaction, so the wallet should have a way of knowing it needs to retry with the updated UTXO
  """
  defp poll_ignored_txs(state) do
    mempool = BlockchainNode.get_mempool(state.node)
    curr_tx = BlockchainNode.get_working_on(state.node) |> List.first()

    # make sure it's been seriously ignored - not that it's just being worked on
    txs_not_in_mempool = Enum.filter(state.pending, fn {txid, _} -> !Enum.member?(mempool, txid) && txid != curr_tx end)

    if txs_not_in_mempool != [] do
      state = %{state | counter: state.counter + 1}
      if state.counter > 3 do
        # remove from pending
        state = %{state | pending: Map.drop(state.pending, Enum.map(txs_not_in_mempool, fn {txid, _} -> txid end))}
        IO.puts("wallet decided that #{inspect(txs_not_in_mempool |> List.first() |> elem(0))} has been ignored")

        # add UTXOs back to available
        failed_utxos = Enum.reduce(txs_not_in_mempool, %{}, fn {_, {from_addrs, _, _}}, acc -> Map.merge(acc, from_addrs) end)
        state = %{state | available_UTXOs: Map.merge(state.available_UTXOs, failed_utxos, fn _k, v1, v2 -> v1+v2 end)}

        # retry failed transactions
        Enum.each(txs_not_in_mempool, fn {txid, {_, to_addr, amount}} ->
          IO.puts("retrying #{txid}")
          send(self(), {:spend, nil, to_addr, amount}) end)

        %{state | counter: 0}
      else state end
    else state end
  end

  # polls a node for the latest blocks in the blockchain
  defp poll_for_blocks(state) do
    case BlockchainNode.get_new_blocks(state.node, state.scanned_height) do
      [h | t] ->
        Enum.reduce([h | t], state, fn block, state ->
          state = %{state | scanned_height: block.height}
          cond do
            # === SENT: block contains a sent transaction from this wallet ===
            Map.has_key?(state.pending, block.transaction.txid) ->
              # handle outputs
              state = process_tx_outputs(state, block.transaction.outputs)
              # handle transaction
              state = %{state |
                past_transactions: state.past_transactions ++ [{block.height, "send", block.transaction}],
                pending: Map.delete(state.pending, block.transaction.txid)
              }
              # check if there are pending transactions that can now be delivered
              check_deliver_txpool(state)

            # === RECEIVED: block contains a receive transaction for this wallet ===
            owned_outputs(state, block.transaction.outputs) != [] ->
              # handle outputs
              state = process_tx_outputs(state, block.transaction.outputs)
              # handle transaction
              state = %{state |
                past_transactions: state.past_transactions ++ [{block.height, "receive", block.transaction}],
                pending: Map.delete(state.pending, block.transaction.txid)}
              # check if there are pending transactions that can now be delivered
              check_deliver_txpool(state)

            # === UNRELATED: ignore as block tx is not related to this wallet ===
            true -> state
          end
        end)

      :up_to_date -> state
      _ -> state
    end
  end

  # ======================
  # ----- Public API -----
  # ======================
    # send amount from a wallet to an address
    def send(w, address, amount) do
      if amount < 0, do: raise("can't send negative money")
      IO.puts("#{inspect w} request to send #{amount} to #{address}")
      send(w, {:spend, self(), address, amount})
      receive do
        {:ok, msg} -> IO.puts("ok: " <> msg); msg
        {:error, msg} -> IO.puts("error: " <> msg); msg
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

    # returns the ready-to-spend balance of this wallet
    def available_balance(w) do
      send(w, {:get_available, self()})
      receive do
        {:available, bal} -> bal
      after
        1000 -> :timeout
      end
    end

    # returns all addresses for this wallet
    def addresses(w) do
      send(w, {:get_addresses, self()})
      receive do
        {:addresses, addrs} -> addrs
      after
        1000 -> :timeout
      end
    end

    # returns all UTXOs for this wallet
    def available_utxos(w) do
      send(w, {:get_utxos, self()})
      receive do
        {:utxos, utxos} -> utxos
      after
        1000 -> :timeout
      end
    end

    # returns the past transactions for this wallet
    def history(w) do
      send(w, {:get_history, self()})
      receive do
        {:history, data} -> data
      after
        1000 -> :timeout
      end
    end

    # returns the pending transaction for this wallet
    def get_pending_tx(w) do
      send(w, {:get_pending_tx, self()})
      receive do
        {:pending_tx, data} -> data
      after
        1000 -> :timeout
      end
    end
end
