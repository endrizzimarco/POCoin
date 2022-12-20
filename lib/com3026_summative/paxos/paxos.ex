defmodule Paxos do
  def start(name, participants) do
    pid = spawn(Paxos, :init, [name, participants])

    case :global.re_register_name(name, pid) do
      :yes -> pid
    end

    IO.puts("registered #{name}")
    pid
  end

  def init(name, participants) do
    state = %{
      name: name,
      processes: participants,
      quorum: div(length(participants), 2) + 1,
      bal: 0, # highest ballot in which this process participated
      a_bal: 0,  # highest ballot that was ever accepted by this process
      a_val: nil, # value associated with a_bal
      prepared: [],
      accepted: 0,
      value: nil,
      decided: %{}
    }

    run(state)
  end


  def run(state) do
    state = receive do
      # ====================
      # ----- Acceptor -----
      # ====================
      {:prepare, client, proposer, b} ->
        # If the ballot is greater than the currently highest seen ballot send a prepared message
        if b > state.bal do
          state = %{state | bal: b}
          send(proposer, {:prepared, client, b, state.a_bal, state.a_val})
          state
        else
          send(proposer, {:nack, client, b})
        end
        state

      {:accept, client, proposer, b, val} ->
        # If the ballot is greater than the current ballot, accept the ballot and send an accepted message
        if b >= state.a_bal do
          state = %{state | bal: b, a_bal: b, a_val: val}
          send(proposer, {:accepted, client, b})
          state
        else
          send(proposer, {:nack, client, b})
        end
        state

      {:decided, b, v} ->
        %{state | decided: Map.put(state.decided, b, v)}

      # ====================
      # ----- Proposer -----
      # ====================
      {:propose, client, leader_pid, inst, value} ->
        if leader_pid == self(), do: beb_broadcast({:prepare, client, self(), inst}, state.processes)
        %{state | value: value}

      {:prepared, client, b, a_bal, a_val} ->
        state = %{state | prepared: [{b, a_bal, a_val} | state.prepared]}
        if length(state.prepared) >= state.quorum do
          v = decide_proposal(state)
          beb_broadcast({:accept, client, self(), b, v}, state.processes)
          %{state | prepared: []}
        end
        state

      {:accepted, client, b} ->
        state = %{state | accepted: state.accepted + 1}

        if state.accepted >= state.quorum do
          beb_broadcast({:decided, b, state.value}, state.processes)
          send(client, {:decided, state.value})
          %{state | accepted: []}
        end

        state

      {:nack, client, b} ->
        %{state | decided: Map.put(state.decided, b, :aborted)}
        send(client, {:abort})

      _ -> state
    end
    run(state)
  end


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

  # search for a value with higher ballot TODO: better commenting
  defp decide_proposal(state) do
    {_, a_bal, a_val} = Enum.max_by(state.prepared, fn {_, a_bal, _} -> a_bal end)
    case a_bal do
      0 -> state.value # no other process has accepted anything else # TODO:
      _ -> a_val
    end
  end


  def get_decision(pid, inst, t) do
    # TODO:
    # get_decision(pid, inst, t) is a function that takes the process identifier pid of an
    # Elixir process running a Paxos replica, an instance identifier inst, and a timeout t in milliseconds.
    # It returns v ≠ nil if v is the value decided by the consensus instance inst; it returns nil in
    # all other cases.
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
