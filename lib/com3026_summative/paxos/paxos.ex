defmodule Paxos do
  def start(name, participants) do
    pid = spawn(Paxos, :init, [name, participants])

    case :global.re_register_name(name, pid) do
      :yes -> pid
    end

    pid
  end

  def init(name, participants) do
    state = %{
      name: name,
      processes: participants,
      quorum: div(length(participants), 2) + 1,
      bal: 0, # highest ballot in which this process participated
      a_bal: 0,  # highest ballot that was ever accepted by this process
      a_val: nil, # value associated with highest accepted ballot a_bal
      proposed_value: %{}, # value proposed for a round:  %{inst => value}
      prepared: %{}, # received prepared messages for a round:  %{inst => [{bal, a_bal, a_val}]}
      accepted: %{}, # received accepted messages for a round:  %{inst => count}
      decided: %{} # log of decided values:  %{inst => value}
    }

    run(state)
  end

  def run(state) do
    state = receive do
      # ====================
      # ----- Acceptor -----
      # ====================
      {:prepare, client, proposer, inst} ->
        # If the ballot is greater than the currently highest seen ballot, send back a :prepared message
        if inst > state.bal do
          state = %{state | bal: inst}
          send(proposer, {:prepared, client, inst, state.a_bal, state.a_val})
          state
        else
          send(proposer, {:nack, client, inst})
        end
        state

      {:accept, client, proposer, inst, v} ->
        # If the ballot is greater than the current ballot, accept the ballot and send an :accepted message
        if inst >= state.a_bal do
          state = %{state | bal: inst, a_bal: inst, a_val: v}
          send(proposer, {:accepted, client, inst, v})
          state
        else
          send(proposer, {:nack, client, inst})
        end
        state

      {:decided, inst, v} ->
        # delete intermidiary data and update decided value for this round
        %{state | decided: Map.put(state.decided, inst, v)}

      # ====================
      # ----- Proposer -----
      # ====================
      {:propose, client, leader_pid, inst, value} ->
        IO.puts("#{inspect state.name}: received propose request for instance #{inspect inst} with value #{inspect value}")

        # brodcast prepare message to all acceptors
        if leader_pid == self(), do: beb_broadcast({:prepare, client, self(), inst}, state.processes)
        # store proposal for this round
        %{state | proposed_value: Map.put(state.proposed_value, inst, value)}

      {:prepared, client, inst, a_bal, a_val} ->
        # collect :prepared messages for an instance of paxos
        state = %{state | prepared: Map.update(state.prepared, inst, [], fn list -> [{a_bal, a_val} | list] end)}

        # if quorum of prepared messages, enter accept phase by broadcasting :accept messages
        if length(state.prepared[inst]) >= state.quorum do
          v = decide_proposal(inst, state)
          beb_broadcast({:accept, client, self(), inst, v}, state.processes)
          %{state | prepared: Map.delete(state.prepared, inst),
                    proposed_value: Map.delete(state.proposed_value, inst)} # cleanup
        end
        state

      {:accepted, client, inst, v} ->
        # increment accepted count for this ballot
        state = %{state | accepted: Map.update(state.accepted, inst, 1, fn x -> x + 1 end)}

        # if quorum of prepared messages, commit value with paxos processes and communicate back to client
        if state.accepted[inst] >= state.quorum do
          beb_broadcast({:decided, inst, v}, state.processes)
          send(client, {:decided, v})
          %{state | accepted: Map.delete(state.accepted, inst)} # cleanup
        end
        state

      {:nack, client, inst} ->
        # ensure safety by aborting if a nack is received
        %{state | decided: Map.put(state.decided, inst, :aborted)}
        send(client, {:abort})

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
      {:ok, v} -> v
      {:error, m} ->
        IO.puts(m)
        nil
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
    {a_bal, a_val} = Enum.max_by(state.prepared[inst], fn {a_bal, _} -> a_bal end)
    case a_bal do
      0 -> state.proposed_value[inst] # no accepted proposals, free to use own proposed value
      _ -> a_val # a process has accepted another proposal, override value
    end
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
