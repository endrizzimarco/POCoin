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
      nacked: %{}, # store nacked ballots for an instance %{inst => {prevBal}}
      decided: %{}, # log of decided values %{inst => value}

      # == acceptor state ==
      bal: %{}, # highest ballot in which this process participated %{inst => {inst, pid}}
      a_bal: %{}, # highest ballot that was ever accepted by this process %{inst => {inst, pid}}
      a_val: %{}, # value associated with highest accepted ballot a_bal %{inst => value}

      # == proposer state ==
      proposed_value: %{}, # value proposed for a round:  %{inst => value}
      prepared: %{}, # received prepared messages for a round:  %{inst => [{bal, a_bal, a_val}]}
      accepted: %{}, # received accepted messages for a round:  %{inst => count}
      client: %{}, # client that initiated the round:  %{{inst, pid} => client}
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
        # update decided value for this round and delete intermidiary data
        if not already_decided(state, inst) do
          beb_broadcast({:decided, inst, v}, state.processes) # rb: ensure everyone knows even when proposer fails
          %{state | decided: Map.put(state.decided, inst, v),
                    bal: Map.delete(state.bal, inst),
                    a_bal: Map.delete(state.a_bal, inst),
                    a_val: Map.delete(state.a_val, inst)}
        else
          state # ignore - already saved
        end

      # ====================
      # ----- Proposer -----
      # ====================
      {:propose, client, inst, value} ->
        # IO.puts("#{inspect state.name}: received propose request for instance #{inspect inst} with value #{inspect value}")

        cond do
          # if already proposing for same ballot return abort message to client
          already_decided(state, inst) ->
            send(client, {:abort, inst})
            state

          # no concurrent proposals for this instance
          true ->
          # b = {inst, counter, proc_name}
          {b, state} = if Map.has_key?(state.nacked, inst) do
              {{inst, state.nacked[inst]+1, state.name}, %{state | nacked: state.nacked[inst]+1}} # increasing ballot
            else
              {{inst, 0, state.name}, state} # first ballot for this instance
            end
            # brodcast prepare message to all acceptors
            beb_broadcast({:prepare, self(), b}, state.processes)
            %{state | proposed_value: Map.put(state.proposed_value, inst, value),
                      client: Map.put(state.client, b, client)}
        end

      {:prepared, b, a_bal, a_val} ->
        i = inst(b)
        # collect :prepared messages for an instance of paxos
        state = %{state | prepared: Map.update(state.prepared, i, [{a_bal, a_val}], fn list -> [{a_bal, a_val} | list] end)}

        # if quorum of prepared messages, enter accept phase by broadcasting :accept messages
        if length(state.prepared[i]) == state.quorum do
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
        if state.accepted[i] == state.quorum do
          # IO.puts("#{inspect state.name}: decided value #{inspect v} for instance #{inspect i}")
          beb_broadcast({:decided, i, v}, state.processes)
          send(state.client[b], {:decided, v})
          %{state | accepted: Map.delete(state.accepted, i),
                    client: Map.delete(state.client, b),
                    nacked: Map.delete(state.nacked, i)} # cleanup
        else
          state
        end

      {:nack, b} ->
        if Map.has_key?(state.client, b) do
          send(state.client[b], {:abort}) # ensure safety by aborting if a nack is received
          %{state | client: Map.delete(state.client, b),
                    nacked: Map.put(state.nacked, inst(b), elem(b, 1))}
        else
          state
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
    send(pid, {:get_decision, self(), inst})
    receive do
      {:ok, v} when v != nil -> v
      {:error, _m} -> nil
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

  defp inst(instance) do
    elem(instance, 0)
  end

  # BEB Helper functions
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
