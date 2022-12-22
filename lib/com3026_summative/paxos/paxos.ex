defmodule Paxos do
  def start(name, participants) do
    pid = spawn(Paxos, :init, [name, participants])

    case :global.re_register_name(name, pid) do
      :yes -> pid
    end

    pid
  end

  def init(name, participants) do
    # process state
    state = %{
      name: name,
      processes: participants,
      quorum: div(length(participants), 2) + 1,
      decided: %{} # decided value for this paxos instance %{inst = > value}
    }

    # holds intermdiary state for all current paxos runs
    ps = %{}

    run(state, ps)
  end

  defp init_proposer_state(instance_store, inst, proposed_value, client) do
    Map.put(instance_store, inst, %{
      # === acceptor variables ===
      bal: nil, # highest ballot in which this process participated
      a_bal: nil, # highest ballot that was ever accepted by this process %{inst = > {a_bal, a_val}}
      a_val: nil, # value associated with highest accepted ballot a_bal
      # === proposer variables ===
      proposed_value: proposed_value, # value passed to a leader in the propose() function
      prepared: [], # received prepared messages for a ballot: [{bal, a_bal, a_val}]
      accepted: 0, # received accepted messages for a ballot
      client: client
      }
    )
  end

  defp init_acceptor_state(instance_store, inst) do
    Map.put(instance_store, inst, %{bal: nil, a_bal: nil, a_val: nil})
  end

  def run(state, ps) do
    {state, ps} = receive do
      # ====================
      # ----- Acceptor -----
      # ====================
      {:prepare, proposer, b} ->
        i = inst(b)
        # If the ballot is greater than the currently highest seen ballot, send back a :prepared message
        ps = if unknown_ballot(ps, i) , do: init_acceptor_state(ps, i), else: ps
        if b > ps[i].bal do
          IO.puts("#{inspect state.name}: promised ballot #{inspect b} to #{inspect proposer}")
          ps = update_paxos_state(ps, i, :bal, b)
          send(proposer, {:prepared, b, ps[i].a_bal, ps[i].a_val})
          {state, ps}
        else
          send(proposer, {:nack, i}) # tell proposer it has seen a higher ballot
          {state, ps}
        end

      {:accept, proposer, b, v} ->
        i = inst(b)
        # If the ballot is greater than the current ballot, accept the ballot and send an :accepted message
        ps = if unknown_ballot(ps, i), do: init_acceptor_state(ps, i), else: ps
        if b >= ps[i].bal do
          IO.puts("#{inspect state.name}: accepted ballot #{inspect b} with value #{inspect v}")
          ps = update_paxos_state(ps, i, :bal, b) # TODO: fix
          ps = update_paxos_state(ps, i, :a_bal, b)
          ps = update_paxos_state(ps, i,:a_val, v)
          send(proposer, {:accepted, i, v})
          {state, ps}
        else
          send(proposer, {:nack, i}) # tell proposer it has seen a higher ballot
          {state, ps}
        end

      {:decided, inst, v} ->
        state = %{state | decided: Map.put(state.decided, inst, v)} # update decided value for instance
        ps = Map.delete(ps, inst) # cleanup intermidiary state
        {state, ps}

      # ====================
      # ----- Proposer -----
      # ====================
      {:propose, client, leader_pid, inst, value} ->
        IO.puts("#{inspect state.name}: received propose request for instance #{inspect inst} with value #{inspect value}")

        # brodcast prepare message to all acceptors
        if leader_pid == self() do
          b = {inst, state.name} # ensure unique ballots to avoid conflicts
          beb_broadcast({:prepare, self(), b}, state.processes)
          ps = init_proposer_state(ps, inst, value, client) # init paxos state for this instance
          {state, ps}
        else
          {state, ps}
        end

      {:prepared, b, a_bal, a_val} ->
        i = inst(b)
        case already_decided(ps, i) do
          true -> {state, ps}
          false ->
            ps = update_paxos_state(ps, i, :prepared, [{a_bal, a_val} | ps[i].prepared]) # append :prepared messages
            # if quorum of prepared messages, enter accept phase by broadcasting :accept messages
            if length(ps[i].prepared) >= state.quorum do
              v = decide_proposal(i, ps)
              beb_broadcast({:accept, self(), b, v}, state.processes)
              ps = update_paxos_state(ps, i, :prepared, [])  # reset prepared messages
              {state, ps}
            else
              {state, ps}
            end
        end

      {:accepted, inst, v} ->
        case already_decided(ps, inst) do
          true -> {state, ps}
          false ->
            ps = increment_accepted_count(ps, inst)
            # if quorum of prepared messages, commit value with paxos processes and communicate back to client
            if ps[inst].accepted >= state.quorum do
              send(ps[inst].client, {:decided, v})
              beb_broadcast({:decided, inst, v}, state.processes)
              ps = Map.delete(ps, inst) # cleanup intermediary state for this instance
              {state, ps}
            else
              {state, ps}
            end
          end

      {:nack, inst} ->
        # ensure safety by aborting if a nack is received
        IO.puts("#{inspect state.name}: received nack for instance #{inspect inst}")
        send(ps[inst].client, {:abort})
        {state, ps}

      # =====================
      # ----- Utilities -----
      # =====================
      {:get_decision, client, pid, inst} ->
        if pid == self() do
          if Map.has_key?(state.decided, inst) do
            send(client, {:ok, state.decided[inst]})
          else
            send(client, {:error, "no decision for paxos instance #{inst}"})
          end
        end
        {state, ps}

      _ -> {state, ps}
    end
    run(state, ps)
  end


  # =======================
  # ----- Module API  -----
  # =======================
  def propose(pid, inst, value, t) do
    # propose(pid, inst, value, t) is a function that takes the process identifier pid of an
    # Elixir process running a Paxos replica, an instance identifier inst, a timeout t in milliseconds,
    # and proposes a value value for the instance of consensus associated with inst.
    send(pid, {:propose, self(), pid, inst, value})
    receive do
      {:decided, v} -> {:decided, v}
      {:abort} -> {:abort}
    after
      t -> {:timeout}
    end
  end

  def get_decision(pid, inst, t) do
    # get_decision(pid, inst, t) is a function that takes the process identifier pid of an Elixir process
    # running a Paxos replica, an instance identifier inst, and a timeout t in milliseconds. It returns
    # v ≠ nil if v is the value decided by the consensus instance inst; it returns nil in all other cases.
    send(pid, {:get_decision, self(), pid, inst})
    receive do
      {:ok, v} when v != nil -> v
      {:error, m} -> IO.puts(m); nil
      true -> nil
    after
      t -> {:timeout}
    end
  end


  # ============================
  # ----- Helper functions -----
  # ============================
  # returns the value to use for a proposal during a round of paxos
  defp decide_proposal(inst, instance_state) do
    {a_bal, a_val} = Enum.max_by(instance_state[inst].prepared, fn {a_bal, a_val} -> {a_bal, a_val} end)
    case a_bal do
      nil -> instance_state[inst].proposed_value # no accepted proposals, free to use own proposed value
      _ -> a_val # a process has accepted another proposal, override value
    end
  end

  defp unknown_ballot(instance_store, inst) do
    not Map.has_key?(instance_store, inst)
  end

  defp already_decided(instance_store, inst) do
    not Map.has_key?(instance_store, inst)
  end

  # perfoms a deep update of the paxos state for a given instance
  defp update_paxos_state(instance_store, inst, key, value) do
    Map.update!(instance_store, inst, fn(map) -> Map.replace(map, key, value) end)
  end

  defp increment_accepted_count(instance_store, inst) do
    Map.update!(instance_store, inst, fn(map) -> Map.update(map, :accepted, 1, fn x -> x + 1 end) end)
  end

  # given a ballot {inst, p_name}, return inst
  defp inst(b) do
    elem(b, 0)
  end

  def beb_broadcast(m, dest), do: for(p <- dest, do: unicast(m, p))

  # Send message m point-to-point to process p
  defp unicast(m, p) do
    case :global.whereis_name(p) do
      pid when is_pid(pid) -> send(pid, m)
      :undefined -> :ok
    end
  end
end
