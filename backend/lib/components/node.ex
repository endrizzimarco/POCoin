defmodule BlockchainNode do
  @total_supply 1000
  @pow_difficulty 6

  def start(name, node_names, paxos_names, gen_pub_key) do
    index = name |> to_string() |> String.last() |> String.to_integer()
    paxos_pid = Paxos.start(String.to_atom("p#{index}"), paxos_names)
    pid = spawn(BlockchainNode, :init, [name, node_names, gen_pub_key, paxos_pid])

    case :global.re_register_name(name, pid) do
      :yes -> pid
    end
  end

  def init(name, nodes, gen_pub_key, paxos_pid) do
    genesis_transaction = %{txid: "genesis", signatures: [], inputs: [], outputs: [{derive_address(gen_pub_key), @total_supply}]}

    state = %{
      # == distributed state ==
      name: name,
      nodes: nodes,
      pax_pid: paxos_pid,
      # == blockchain state ==
      blockchain: [%{height: 1, timestamp: 0, miner: nil, nonce: nil, prev_hash: nil, transaction: genesis_transaction}],
      mempool: [], # transactions that have been received but not yet added to the blockchain [{txid, tx}]
      utxos: Map.put(%{}, derive_address(gen_pub_key), @total_supply), # %{address => value}
      pow_pid: nil, # pid of the current POW process
      working_on: {nil, nil}, # transaction that is currently being worked on %{txid => tx}
      found_pow: [], # keep track of which node found the pow for a block
      mining_power: Enum.into(nodes, %{}, fn key -> {key, 0} end) # {node => n of blocks mined}
    }
    start_beb(name)
    run(state)
  end


  def run(state) do
    state = receive do
      {:new_transaction, client, txid, tx} ->
        if verify(state, tx) and not in_mempool(state, txid) do
          beb_broadcast({:add_transaction, txid, tx}, state.nodes)
          send(client, {:ok, txid})
          state
        else
          send(client, {:bad_transaction, txid})
          state
        end

      {:add_transaction, txid, tx} ->
        state = if verify(state, tx) and not in_mempool(state, txid) do
          %{state | mempool: state.mempool ++ [{txid, tx}]}
        else
          state
        end
        poll_mempool(state)

      {:pow_found, block, n} ->
        block = Map.put(block, :nonce, n) |> Map.put(:miner, state.name) # add nonce and miner to the block
        state = poll_for_blocks(state) # make sure to have latest blockchain
        possible_validators = Map.delete(state.mining_power, state.name)

        validators =
          if height(state.blockchain) < 10 do
            Map.keys(possible_validators) |> Enum.take_random(2)
          else
            # given a map of counts of blocks mined by each node, get percentage of blocks mined by each node
            v1 = weighted_random(possible_validators)
            v2 = weighted_random(Map.delete(possible_validators, v1))
            [v1] ++ [v2]
          end

        block = Map.put(block, :next_validators, validators ++ [state.name])

        # start SMR
        case Paxos.propose(state.pax_pid, height(state.blockchain), block, 1000) do
          {:abort} ->
            IO.puts("another block is being proposed or has already been decided")
            start_pow(state, block.transaction.txid, block.transaction) # need to start POW again to ensure liveness
          {:timeout} ->
            IO.puts("timeout")
            start_pow(state, block.transaction.txid, block.transaction)
          {:decision, _} ->
            IO.puts("#{inspect state.name} successfully mined block #{height(state.blockchain)}")
            beb_broadcast({:block_decided}, state.nodes)
        end
        state

      {:block_decided} -> state |> poll_for_blocks() |> poll_mempool()

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

      {:get_mempool, client} ->
        send(client, {:mempool, Enum.map(state.mempool, fn {id, _tx} -> id end)})
        state

      {:get_utxos, client} ->
        send(client, {:utxos, Map.to_list(state.utxos)})
        state

      {:get_working_on, client} ->
        {tx, _} = state.working_on
        send(client, {:working_on, [tx, height(state.blockchain)]})
        state

      {:get_mining_power, client} ->
        total = Enum.reduce(state.mining_power, 0, fn {_, v}, acc -> v + acc end)
        case total do
          0 -> send(client, {:mining_power, 0})
          _ -> send(client, {:mining_power, state.mining_power[state.name]/total * 100})
        end
        state

      _ -> state
    end
    run(state)
  end

  # ==========================
  # ---- General helpers  ----
  # ==========================
  # check for new blocks and process them
  defp poll_for_blocks(state) do
    case Paxos.get_decision(state.pax_pid, height(state.blockchain), 1000) do
      nil -> state
      {:timeout} -> state
      block ->
        state =
          if verify_work(block) and block.prev_hash == latest_block_hash(state) do
            # kill POW for this block height
            if not is_nil(state.pow_pid) do
              Task.shutdown(state.pow_pid, :brutal_kill)
            end

            state =
              # check whether block mined is different from the block this node has been mining
              case { block.transaction.txid, Map.delete(block.transaction, :txid) } == state.working_on do
                true -> state
                false -> %{state | mempool: [state.working_on] ++ state.mempool} # re-add block tx to mempool
              end

            %{state |
                blockchain: state.blockchain ++ [block],
                pow_pid: nil,
                working_on: {nil, nil},
                utxos: update_UTXO(state.utxos, block),
                mining_power: Map.update(state.mining_power, block.miner, 1, fn blocks_mined -> blocks_mined + 1 end)}
          else
            state
          end
        poll_for_blocks(state)
    end
  end

  defp height(blockchain) do
    length(blockchain) + 1
  end

  # generate a block from a given transaction
  defp generate_block(state, txid, transaction) do
    %{
      height: height(state.blockchain),
      timestamp: System.os_time(),
      transaction: Map.put(transaction, :txid, txid),
      prev_hash: latest_block_hash(state)
    }
  end

  defp latest_block_hash(state) do
    bin = state.blockchain |> List.last() |> :erlang.term_to_binary()
    :crypto.hash(:sha256, bin) |> Base.encode32()
  end

  # update UTXOs for a given block
  defp update_UTXO(utxos, block) do
    input_addresses = Enum.map(block.transaction.inputs, fn pub_key -> derive_address(pub_key) end) # convert pub_keys to addresses
    outputs = Map.new(block.transaction.outputs, fn {a, v} -> {a, v} end) # convert to map
    utxos |> Map.drop(input_addresses) |> Map.merge(outputs, fn _k, v1, v2 -> v1 + v2 end) # update utxos
  end

  # generate next validators randomly based on their mining power
  defp weighted_random(validators) do
    total = Enum.reduce(validators, 0, fn {_, v}, acc ->  v + acc end)
    weighted = Enum.into(validators, %{}, fn {k, v} -> {k, v/total} end)
    Enum.reduce_while(weighted, :rand.uniform(), fn ({k, v}, remaining) ->
      if remaining - v <= 0, do: {:halt, k}, else: {:cont, remaining - v}
    end)
  end

  # ====================
  # ----- Mempool  -----
  # ====================
  defp in_mempool(mempool, txid) do
    Enum.any?(mempool, fn {id, _tx} -> id == txid end)
  end

  defp poll_mempool(state) do
    if is_nil(state.pow_pid) and not Enum.empty?(state.mempool) do
      # poll a transaction from mempool
      [{txid, tx} | lst] = state.mempool
      state = %{state | mempool: lst}
      input_addresses = Enum.map(tx.inputs, fn pub_key -> derive_address(pub_key) end)

      case not_creating_money(state, input_addresses, tx.outputs) do
        true -> start_pow(state, txid, tx)
        false -> poll_mempool(state) # skip this transaction
      end
    else
      state
    end
  end

  # =======================
  # ---- Proof of Work ----
  # =======================
  defp start_pow(state, txid, tx) do
    block = generate_block(state, txid, tx)
    pid = self()
    pow_pid = Task.async(fn -> proof_of_work(pid, block) end)
    %{state | pow_pid: pow_pid, working_on: {txid, tx}}
  end

  defp proof_of_work(pid, block) do
    n = :rand.uniform(trunc(:math.pow(2, 32)))
    cond do
      String.starts_with?(generate_pow_hash(block, n), String.duplicate("0", @pow_difficulty)) -> send(pid, {:pow_found, block, n})
      true -> proof_of_work(pid, block)
    end
  end

  defp generate_pow_hash(block, n) do
    bin_sum = :erlang.term_to_binary(block) <> :erlang.term_to_binary(n)
    :crypto.hash(:sha256, bin_sum) |> Base.encode16()
  end

  defp verify_work(block) do
    nonce = block.nonce
    block = Map.drop(block, [:nonce, :miner, :next_validators])
    generate_pow_hash(block, nonce) |> String.starts_with?(String.duplicate("0", @pow_difficulty))
  end

  # ============================
  # ---- Verify transaction ----
  # ============================
  defp verify(state, tx) do
    input_addresses = Enum.map(tx.inputs, fn pub_key -> derive_address(pub_key) end) # turn pub keys into addresses
    not_creating_money = not_creating_money(state, input_addresses, tx.outputs)
    utxos_are_unspent = Enum.all?(input_addresses, fn address -> Map.has_key?(state.utxos, address) end)

    utxos_are_unspent and not_creating_money and sigs_valid(tx)
  end

  # check whether the used sum of outputs is equal to the sum of used UTXO
  defp not_creating_money(state, input_addrs, outputs) do
    inputs_total = Enum.reduce(input_addrs, 0, fn addr, acc -> acc + Map.get(state.utxos, addr, 0) end)
    outputs_total = Enum.reduce(outputs, 0, fn {_, amount}, acc -> acc + amount end)

    inputs_total == outputs_total
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

  # =========================
  # ------ Public API  ------
  # =========================
  # returns blocks in the blockchain above the input height
  def get_new_blocks(node, height) do
    send(node, {:get_new_blocks, self(), height})
    receive do
      {:new_blocks, [h | t]}  -> [h | t]
      {:new_blocks, []} -> :up_to_date
    after
      1000 -> :timeout
    end
  end

  # returns the whole blockchain
  def get_blockchain(node) do
    send(node, {:get_blockchain, self()})
    receive do
      {:blockchain, blockchain} -> blockchain
    after
      1000 -> :timeout
    end
  end

  # returns transactions in the mempool
  def get_mempool(node) do
    send(node, {:get_mempool, self()})
    receive do
      {:mempool, mempool} -> mempool
    after
      1000 -> :timeout
    end
  end

  # returns all UTXOs on the blockchain
  def get_utxos(node) do
    send(node, {:get_utxos, self()})
    receive do
      {:utxos, utxos} -> utxos
    after
      1000 -> :timeout
    end
  end

  # returns the block that a node is currently mining
  def get_working_on(node) do
    send(node, {:get_working_on, self()})
    receive do
      {:working_on, data} -> data
    after
      1000 -> :timeout
    end
  end

  # returns the percentage of blocks mined by a node
  def get_mining_power(node) do
    send(node, {:get_mining_power, self()})
    receive do
      {:mining_power, m_pow} -> m_pow
    after
      1000 -> :timeout
    end
  end
end
