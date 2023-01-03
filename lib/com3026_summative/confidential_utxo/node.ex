# == Receive ==
# Once a transaction is received broadcast it to the network.

# == Verify ==
# When a transaction is created, check that the sum of the inputs is equal to or greater than the sum of the outputs.
# Also check that the UTXO are present in the UTXO set and the digitial signature. If any of these fail, the transaction is invalid otherwise add to pending.

# == Proof of Work ==
# If a transaction is valid and the node has a POW available, add the block to the blockchain.

# == Paxos ==
# Get everyone to agree with your new piece of shit block.

# == New block added ==
# Iterate through the transaction inputs and mark the corresponding UTXOs as spent.
# When a new transaction is added to the blockchain, add the new transaction outputs to the UTXO set.

defmodule BlockchainNode do
  def start(name, node_names, paxos_names, gen_pub_key) do
    index = name |> to_string() |> String.last() |> String.to_integer()
    paxos_pid = Paxos.start(String.to_atom("p#{index}"), paxos_names)
    pid = spawn(BlockchainNode, :init, [name, node_names, gen_pub_key, paxos_pid])

    pid = case :global.re_register_name(name, pid) do
            :yes -> pid
          end
    pid
  end

  def init(name, nodes, gen_pub_key, paxos_pid) do
    total_supply = 200

    state = %{
      # == distributed state ==
      name: name,
      nodes: nodes,
      pax_pid: paxos_pid,
      # == blockchain state ==
      height: 1, # height of the blockchain and paxos instance
      blockchain: [%{height: 1, timestamp: 0, transaction: %{txid: "genesis", outputs: [{derive_address(gen_pub_key),  total_supply}]}}],
      pending_transactions: %{}, # %{txid => tx}
      unspent_UTXO: Map.put(%{}, derive_address(gen_pub_key), total_supply), # %{address => value}
      pow_pids: %{}, # %{block => pid}
    }
    start_beb(name)
    run(state)
  end


  def run(state) do
    state = receive do
      {:new_transaction, client, txid, tx} ->
        if verify(state, tx) and not Map.has_key?(state.pending_transactions, txid) do
          beb_broadcast({:verify_transaction, txid, tx}, state.nodes)
          send(client, {:ok, txid})
          state
        else
          send(client, {:bad_transaction, txid})
          state
        end

      {:verify_transaction, txid, tx} ->
        if verify(state, tx) and not Map.has_key?(state.pending_transactions, txid) do
          state = %{state | pending_transactions: Map.put(state.pending_transactions, txid, tx)}

          block = generate_block(state, txid, tx)
          pid = self()
          pow_pid = Task.async(fn -> proof_of_work(pid, block) end)  # start POW for this block

          %{state | pow_pids: Map.put(state.pow_pids, state.height, pow_pid)}
        else
          state
        end

      {:pow_found, block, n} ->
        block = Map.put(block, :nonce, n) # add nonce to the block
        state = poll_for_blocks(state) # make sure to have latest blockchain

        # start SMR
        case Paxos.propose(state.pax_pid, state.height+1, block, 1000) do
          {:abort} -> IO.puts("another block is being proposed or has already been decdied")
          {:timeout} -> IO.puts("timeout")
          {:decided, _} ->
            IO.puts("#{inspect state.name} successfully mined block #{inspect state.height+1}")
            beb_broadcast({:block_decided}, state.nodes)
        end
        state

      {:block_decided} -> poll_for_blocks(state)

      # return blocks in the blockchain with height > input
      {:get_new_blocks, client, height} ->
        state = poll_for_blocks(state)
        send(client, {:new_blocks, Enum.drop(state.blockchain, height)})
        state

      # return the whole blockchain
      {:get_blockchain, client} ->
        state = poll_for_blocks(state)
        send(client, {:blockchain, state.blockchain})
        state

      _ -> state
    end
    run(state)
  end

  # =========================
  # ------ Public API  ------
  # =========================
  def get_new_blocks(node, height) do
    send(node, {:get_new_blocks, self(), height})
    receive do
      {:new_blocks, [h | t]}  -> [h | t]
      {:new_blocks, []} -> {:up_to_date}
    after
      1000 -> :timeout
    end
  end

  def get_blockchain(node) do
    send(node, {:get_blockchain, self()})
    receive do
      {:blockchain, blockchain} -> {:ok, blockchain}
    after
      1000 -> :timeout
    end
  end

  # ==========================
  # ---- General helpers  ----
  # ==========================
  defp generate_block(state, txid, transaction) do
    %{
      height: state.height + 1,
      timestamp: DateTime.utc_now(),
      transaction: Map.put(transaction, :txid, txid),
      prev_hash: latest_block_hash(state)
    }
  end

  defp latest_block_hash(state) do
    bin = state.blockchain |> List.last() |> :erlang.term_to_binary()
    :crypto.hash(:sha256, bin) |> Base.encode16()
  end

  defp poll_for_blocks(state) do
    case Paxos.get_decision(state.pax_pid, i = state.height + 1, 1000) do
      nil -> state
      {:timeout} -> state
      block ->
        state =
          if check_work(block) and block.prev_hash == latest_block_hash(state) do
            Task.shutdown(state.pow_pids[state.height], :brutal_kill) # kill POW process for that block
            # add to blockchain, delete pow_pid for that block, increment height and update UTXO
            state = %{state | blockchain: state.blockchain ++ [block],
                      pow_pids: Map.delete(state.pow_pids, block.height),
                      height: state.height + 1,
                      unspent_UTXO: update_UTXO(state.unspent_UTXO, block)}
            state
          else
            state
          end
        poll_for_blocks(%{state | height: i})
    end
  end

  defp update_UTXO(unspent_UTXO, block) do
    input_addresses = Enum.map(block.transaction.inputs, fn pub_key -> derive_address(pub_key) end)
    outputs = Map.new(block.transaction.outputs, fn {a, v} -> {a, v} end)
    # update UTXO set by removing inputs and adding outputs
    unspent_UTXO |> Map.drop(input_addresses) |> Map.merge(outputs)
  end

  # =======================
  # ---- Proof of Work ----
  # =======================
  defp proof_of_work(pid, block) do
    n = :rand.uniform(trunc(:math.pow(2, 32)))
    cond do
      String.starts_with?(calculate_pow_hash(block, n), "000000") -> send(pid, {:pow_found, block, n})
      true -> proof_of_work(pid, block)
    end
  end

  defp calculate_pow_hash(block, n) do
    bin_sum = :erlang.term_to_binary(block) <> :erlang.term_to_binary(n)
    :crypto.hash(:sha256, bin_sum) |> Base.encode16()
  end

  defp check_work(block) do
    nonce = block.nonce
    block = Map.delete(block, :nonce)
    calculate_pow_hash(block, nonce) |> String.starts_with?("000000")
  end

  # ============================
  # ---- Verify transaction ----
  # ============================
  defp verify(state, tx) do
    # turn pub keys into addresses
    input_addresses = Enum.map(tx.inputs, fn pub_key -> derive_address(pub_key) end)
    utxos_unspent = Enum.all?(input_addresses, fn address -> Map.has_key?(state.unspent_UTXO, address) end)

    if utxos_unspent do
      sum_of_inputs = Enum.reduce(input_addresses, 0, fn address, acc -> acc + state.unspent_UTXO[address] end)
      sum_of_outputs = Enum.reduce(tx.outputs, 0, fn {_, amount}, acc -> acc + amount end)

      sum_of_inputs >= sum_of_outputs and sigs_valid(tx)
    else
      false
    end
  end

  # check if all signatures of a transaction are valid
  defp sigs_valid(tx) do
    checked_sigs = Enum.map(tx.signatures, fn sig -> check_sig_against_inputs(tx, sig) end)
    Enum.all?(checked_sigs, fn x -> x end)
  end

  # check a single signature against all inputs of a transaction
  defp check_sig_against_inputs(tx, sig) do
    Enum.any?(tx.inputs, fn pub_key -> verify_sig(Map.delete(tx, :signatures), pub_key, sig) end)
  end

  # verify a single signature against a single public key
  defp verify_sig(tx, pub_key, sig) do
    :crypto.verify(:ecdsa, :sha256, :erlang.term_to_binary(tx), sig, [pub_key, :secp256k1])
  end

  # derive address from a public key
  defp derive_address(pub_key) do
    :crypto.hash(:sha256, pub_key) |> Base.encode64()
  end

  # ============================
  # --- BEB Helper functions ---
  # ============================
  defp get_beb_name() do
    {:registered_name, parent} = Process.info(self(), :registered_name)
    String.to_atom(Atom.to_string(parent) <> "_beb")
  end

  defp start_beb(name) do
    Process.register(self(), name)
    pid = spawn(BestEffortBroadcast, :init, [])
    Process.register(pid, get_beb_name())
    Process.link(pid)
  end

  defp beb_broadcast(m, dest) do
    BestEffortBroadcast.beb_broadcast(Process.whereis(get_beb_name()), m, dest)
  end
end
