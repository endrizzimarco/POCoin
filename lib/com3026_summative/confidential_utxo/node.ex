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
    paxos_pid = spawn_link(Paxos, :start, [String.to_atom("p#{index}"), paxos_names])
    pid = spawn(BlockchainNode, :init, [name, node_names, gen_pub_key, paxos_pid])

    pid = case :global.re_register_name(name, pid) do
            :yes -> pid
          end
    {pid, paxos_pid}
  end

  def init(name, nodes, gen_pub_key, paxos_pid) do
    state = %{
      # == distributed state ==
      name: name,
      nodes: nodes,
      paxos_pid: paxos_pid,
      # == blockchain state ==
      height: 1, # height of the blockchain and paxos instance
      blockchain: [%{height: 1, timestamp: 0, txid: "genesis", transaction: nil}],
      pending_transactions: %{}, # %{txid => tx}
      unspent_UTXO: Map.put(%{}, derive_address(gen_pub_key), 200), # %{address => value}
      pow_pids: %{}, # %{block => pid}
    }
    start_beb(name)
    run(state)
  end


  def run(state) do
    state = receive do
      {:new_transaction, client, tx, txid} ->
        if verify(state, tx) and not Map.has_key?(state.pending_transactions, txid) do
          beb_broadcast(state.nodes, {:verify_transaction, tx, txid})
          send(client, {:ok, txid})
          state
        else
          send(client, {:bad_transaction, txid})
          state
        end

      {:verify_transaction, tx, txid} ->
        if verify(state, tx) and not Map.has_key?(state.pending_transactions, txid) do
          state = %{state | pending_transactions: Map.put(state.pending_transactions, txid, tx)}

          block = generate_block(state, tx, txid)
          pow_pid = Task.async(fn -> proof_of_work(self(), block) end)  # start POW for this block

          %{state | pow_pids: Map.put(state.pow_pids, state.height, pow_pid)}
        else
          state
        end

      {:pow_found, block, n} ->
        Map.put(block, :nonce, n) # add nonce to the block
        # start paxos
        state = poll_for_blocks(state)
        case Paxos.propose(state.paxos_pid, state.height+1, {:block, block}, 1000) do
          {:decided, _} -> beb_broadcast(state.nodes, {:block_decided})
          {:abort} -> IO.puts("another block is being proposed or has already been decdied")
          {:timeout} -> IO.puts("timeout")
        end
        state

      {:block_decided} -> poll_for_blocks(state)

      # return blocks in the blockchain with height > input
      {:get_new_blocks, client, height} ->
        IO.puts("HELLO??")
        state = poll_for_blocks(state)
        send(client, {:new_blocks, Enum.drop(state.blockchain, height)})
        state

      # return the whole blockchain
      {:get_blockchain, client} ->
        state = poll_for_blocks(state)
        send(client, {:blockchain, state.blockchain})
        state

      x ->
        IO.puts("WHYYYYY #{inspect x}")
        state
    end

    IO.puts("OIWQEJOIWQHJEOIHWEOIQWH")
    run(state)
  end

  # =========================
  # ------ Public API  ------
  # =========================
  def get_new_blocks(node, height) do
    IO.puts("#{inspect node}, #{inspect height}")
    IO.puts("#{inspect is_pid(node)}")
    send(node, {:get_new_blocks, self(), height})
    # IO.puts("#{inspect a}")
    receive do
      {:new_blocks, [h | t]}  ->
        IO.puts("AAAAAAAAAAAAA")
        {:new_blocks, [h | t]}
      {:new_blocks, []} ->
        IO.puts("BBBBBBBBBBBBB")
        {:up_to_date}
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
      height: state.height,
      timestamp: DateTime.utc_now(),
      txid: txid,
      transaction: transaction,
      nonce: 0, # proof of work
      previous_hash: latest_block_hash(state)
    }
  end

  defp latest_block_hash(state) do
    state.blockchain |> List.last() |> :erlang.term_to_binary() |> :crypto.hash(:sha256) |> Base.encode16()
  end

  defp poll_for_blocks(state) do
    case Paxos.get_decision(state.pax_pid, i = state.height + 1, 1000) do
      nil ->
        state

      block ->
        state =
          if check_work(block) and block.prev_hash == latest_block_hash(state) do
            Process.exit(state.pow_pids[block.height], :kill)
            # add to blockchain, delete pow_pid for that block, increment height and update UTXO
            %{state | blockchain: state.blockchain ++ [block],
                      pow_pids: Map.delete(state.pow_pids, block.height),
                      height: state.height + 1,
                      unspent_UTXO: update_UTXO(state.unspent_UTXO, block)}
          else
            state
          end

        poll_for_blocks(%{state | height: i})
    end
  end

  defp update_UTXO(state, block) do
    input_addresses = Enum.map(block.transaction.inputs, fn pub_key -> derive_address(pub_key) end)
    outputs = Map.new(block.transaction.outputs, fn {a, v} -> {a, v} end)
    # update UTXO set by removing inputs and adding outputs
    state.unspent_UTXO |> Map.drop(input_addresses) |> Map.merge(outputs)
  end

  # =======================
  # ---- Proof of Work ----
  # =======================
  defp proof_of_work(pid, block) do
    n = :rand.uniform(trunc(:math.pow(2, 32)))
    cond do
      String.starts_with?(calculate_pow_hash(block, n), "000") -> send(pid, {:pow_found, block, n})
      true -> proof_of_work(pid, block)
    end
  end

  defp calculate_pow_hash(block, n) do
    :erlang.term_to_binary(block) <> :erlang.term_to_binary(n) |> :crypto.hash(:sha256) |> Base.encode16()
  end


  defp check_work(block) do
    calculate_pow_hash(block, block.nonce) |> String.starts_with?("000")
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
    checked_sigs = Enum.map(tx.sigs, fn sig -> check_sig_against_inputs(tx, sig) end)
    Enum.all?(checked_sigs, fn x -> x end)
  end

  # check a single signature against all inputs of a transaction
  defp check_sig_against_inputs(tx, sig) do
    Enum.any?(tx.inputs, fn pub_key -> verify_sig(tx, pub_key, sig) end)
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
