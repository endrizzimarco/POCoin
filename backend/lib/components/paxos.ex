defmodule Paxos do
  def start(name, participants) do
    pid = spawn(Paxos, :init, [name, participants])

    case :global.re_register_name(name, pid) do
      :yes -> pid
    end

    pid
  end

  def init(name, participants) do
    start_beb(name)
    state = %{
      name: name,
      processes: participants,
      quorum: div(length(participants), 2) + 1,
      decided: %{}, # log of decided values %{inst => value}

      # ==========================
      # ----- Instance state -----
      # ==========================

      # == acceptor state ==
      # a ballot is defined in the form {inst, counter, proc_name} to ensure uniqueness and increasing order
      # the counter is incremented each time a new proposal is made by the same proposer for the same instance
      bal: %{}, # highest ballot in which this process participated %{inst => {inst, counter, p_name}}
      a_bal: %{}, # highest ballot that was ever accepted by this process %{inst => {inst, counter, p_name}}
      a_val: %{}, # value associated with highest accepted ballot a_bal %{inst => value}

      # == proposer state ==
      proposed_value: %{}, # value proposed for a round:  %{inst => value}
      prepared: %{}, # received prepared messages for a round:  %{inst => [{bal, a_bal, a_val}]}
      accepted: %{}, # received accepted messages for a round:  %{inst => count}
      nacked: %{}, # nacked ballots for a round:  %{inst => MapSet(b)}
      client: %{}, # client that initiated the round:  %{b => client}
    }

    run(state)
  end

  def run(state) do
    state = receive do
      # ====================
      # ----- Acceptor -----
      # ====================
      {:prepare, proposer, b} ->
        {i, bal} = {inst(b), Map.get(state.bal, inst(b))}

        # If the ballot is greater than the currently highest seen ballot, send back a :prepared message
        if b > bal and not already_decided(state, i) do
          # IO.puts("#{inspect state.name}: promised ballot #{inspect b} for instance #{inspect i}")
          state = %{state | bal: Map.put(state.bal, i, b)}
          {a_bal, a_val} = {Map.get(state.a_bal, i), Map.get(state.a_val, i)}
          send(proposer, {:prepared, b, a_bal, a_val})
          state
        else
          send(proposer, {:nack, b})
          state
        end

      {:accept, proposer, b, v} ->
        {i, bal} = {inst(b), Map.get(state.bal, inst(b))}

        # If the ballot is greater than the current ballot, accept the ballot and send an :accepted message
        if b >= bal and not already_decided(state, i) do
          # IO.puts("#{inspect state.name}: accepted ballot #{inspect b} for instance #{inspect i} with value #{inspect v}")
          state = %{state | bal: Map.put(state.bal, i, b),
                            a_bal: Map.put(state.a_bal, i, b),
                            a_val: Map.put(state.a_val, i, v)}
          send(proposer, {:accepted, b, v})
          state
        else
          send(proposer, {:nack, b})
          state
        end

      {:decided, inst, v} ->
        case already_decided(state, inst) do
          true -> state # ignore - already saved
          false ->
            beb_broadcast({:decided, inst, v}, state.processes) # rb: ensure everyone knows even when proposer fails
            state = cleanup_acceptor_state(state, inst)

            %{state | decided: Map.put(state.decided, inst, v)}
        end

      # ====================
      # ----- Proposer -----
      # ====================
      {:propose, client, inst, value} ->
        case already_decided(state, inst) do
          true ->
            send(client, {:decided, state.decided[inst]})
            state

          false ->
            # IO.puts("#{inspect state.name}: received propose request for instance #{inspect inst} with value #{inspect value}")
            counter = if Map.has_key?(state.nacked, inst), do: MapSet.size(state.nacked[inst]), else: 0
            b = {inst, counter, state.name}
            beb_broadcast({:prepare, self(), b}, state.processes) # braodcast prepare message to all acceptors

            %{state | proposed_value: Map.put(state.proposed_value, inst, value),
                      client: Map.put(state.client, b, client)}
        end

      {:prepared, b, a_bal, a_val} ->
        i = inst(b)

        # collect :prepared messages for an instance of paxos
        state = %{state | prepared: Map.update(state.prepared, i, [{a_bal, a_val}], fn list -> [{a_bal, a_val} | list] end)}

        # if quorum of prepared messages, enter accept phase by broadcasting :accept messages
        quorum_reached = length(state.prepared[i]) == state.quorum
        if quorum_reached and not nacked_ballot(state, b) do
          # IO.puts("#{inspect state.name}: received quorum of prepared messages for instance #{inspect i}")
          v = decide_proposal(i, state)
          beb_broadcast({:accept, self(), b, v}, state.processes)

          %{state | prepared: Map.delete(state.prepared, i),
                    proposed_value: Map.delete(state.proposed_value, i)} # cleanup
        else
          state
        end

      {:accepted, b, v} ->
        i = inst(b)

        # increment accepted count for this ballot
        state = %{state | accepted: Map.update(state.accepted, i, 1, fn x -> x + 1 end)}

        # if quorum of prepared messages, commit value with paxos processes and communicate back to client
        quorum_reached = state.accepted[i] == state.quorum
        if quorum_reached and not nacked_ballot(state, b) do
          # IO.puts("#{inspect state.name}: decided value #{inspect v} for instance #{inspect i}")
          beb_broadcast({:decided, i, v}, state.processes)
          send(state.client[b], {:decided, v})
          state = cleanup_proposer_state(state, b)

          %{state | nacked: Map.delete(state.nacked, i)} # cleanup previous nacked ballots for this round
        else
          state
        end

      {:nack, b} ->
        if Map.has_key?(state.client, b) do
          send(state.client[b], {:abort}) # ensure safety by aborting if a nack is received
          state = cleanup_proposer_state(state, b)

          %{state | nacked: Map.update(state.nacked, inst(b), MapSet.new([b]), fn mapset -> MapSet.put(mapset, b) end)}
        else
          state # in case a slow acceptor sends a nack after the proposer has already decided, ignore
        end


      # =====================
      # ----- Utilities -----
      # =====================
      {:get_decision, client, inst} ->
        if Map.has_key?(state.decided, inst) do
          send(client, {:ok, state.decided[inst]})
        else
          send(client, {:error, "no decision for paxos instance #{inst}"})
        end
        state

      _ -> state
    end
    run(state)
  end


  # =======================
  # ----- Module API  -----
  # =======================
  def propose(pid, inst, value, t) do
    # propose(pid, inst, value, t) is a function that takes the process identifier pid of an
    # Elixir process running a Paxos replica, an instance identifier inst, a timeout t in milliseconds,
    # and proposes a value value for the instance of consensus associated with inst.
    send(pid, {:propose, self(), inst, value})
    receive do
      {:decided, v} -> {:decision, v}
      {:abort} -> {:abort}
    after
      t -> {:timeout}
    end
  end

  def get_decision(pid, inst, t) do
    # get_decision(pid, inst, t) is a function that takes the process identifier pid of an Elixir process
    # running a Paxos replica, an instance identifier inst, and a timeout t in milliseconds. It returns
    # v ≠ nil if v is the value decided by the consensus instance inst; it returns nil in all other cases.
    send(pid, {:get_decision, self(), inst})
    receive do
      {:ok, v} when v != nil -> v
      {:error, _m} -> nil # could return error message here
      true -> nil
    after
      t -> {:timeout}
    end
  end


  # ============================
  # ----- Helper functions -----
  # ============================
  # returns the value to use for a proposal during a round of paxos
  defp decide_proposal(inst, state) do
    {a_bal, a_val} = Enum.max_by(state.prepared[inst], fn {a_bal, a_val} -> {a_bal, a_val} end)
    case a_bal do
      nil -> state.proposed_value[inst] # no accepted proposals, free to use own proposed value
      _ -> a_val # a process has accepted another proposal, override value
    end
  end

  defp already_decided(state, inst) do
    Map.has_key?(state.decided, inst)
  end

  defp nacked_ballot(state, b) do
    Map.has_key?(state.nacked, inst(b)) and MapSet.member?(state.nacked[inst(b)], b)
  end

  defp cleanup_proposer_state(state, b) do
    i = inst(b)
    %{state | proposed_value: Map.delete(state.proposed_value, i),
              prepared: Map.delete(state.prepared, i),
              accepted: Map.delete(state.accepted, i),
              client: Map.delete(state.client, b)}
  end

  defp cleanup_acceptor_state(state, inst) do
    %{state | bal: Map.delete(state.bal, inst),
              a_bal: Map.delete(state.a_bal, inst),
              a_val: Map.delete(state.a_val, inst)}
  end

  defp inst(instance) do
    elem(instance, 0)
  end

  # =======================
  # ----- BEB helpers -----
  # =======================
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
