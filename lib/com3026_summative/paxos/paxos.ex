# TODO: magic happens here
defmodule Paxos do
  def start(name, processes, client \\ :none) do
    pid = spawn(ReliableFIFOBroadcast, :init, [name, processes, client])

    case :global.re_register_name(name, pid) do
      :yes -> pid
      :no -> :error
    end

    IO.puts("registered #{name}")
    pid
  end

  # Init event must be the first
  # one after the component is created
  def init(name, processes, client) do
    start_beb(name)

    state = %{
      name: name,
      client: if(is_pid(client), do: client, else: self()),
      processes: processes,
      # Add state components below as necessary
      delivered: %MapSet{},
      pending: %MapSet{},
      next:
        for p <- processes, into: %{} do
          {p, 1}
        end,
      seq_no: 0
    }

    run(state)
  end

  # Helper functions: DO NOT REMOVE OR MODIFY
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

  # End of helper functions

  def run(state) do
    state =
      receive do
        {:broadcast, m} ->
          IO.puts("#{inspect(state.name)}: FIFO-broadcast: #{inspect(m)}")

          # Increase local counter
          state = %{state | seq_no: state.seq_no + 1}

          # Create a unique message identifier from state.name and state.seqno.
          unique_id = {state.name, state.seq_no}

          # Form data payload
          data_msg = {:data, self(), unique_id, m}

          # Broadcast message
          beb_broadcast(data_msg, state.processes)

          state

        # Add further message handlers as necessary.
        {:data, proc, unique_id, m} ->
          # If <proc, seqno> was already delivered, do nothing.
          if MapSet.member?(state.delivered, unique_id) do
            state
            # Otherwise, update delivered, generate a deliver event for the
            # upper layer, and re-broadcast (echo) the received message.
          else
            state = %{state | pending: MapSet.put(state.pending, {proc, unique_id, m})}

            # If there is a message the can be delivered, deliver it.
            if pending_msg(state) do
              deliver(proc, unique_id, m, state)
              # Otherwise, do nothing.
            else
              state
            end
          end

        # Message handle for delivery event if started without the client argument
        # (i.e., this process is the default client); optional, but useful for debugging.
        {:deliver, pid, proc, m} ->
          IO.puts(
            "#{inspect(state.name)}, #{inspect(pid)}: RFIFO-deliver: #{inspect(m)} from #{inspect(proc)}"
          )

          state
      end

    run(state)
  end

  # Search pending and deliver any messages that can be delivered.
  defp deliver(state) do
    if pending_msg(state) do
      {proc, unique_id, msg} = pending_msg(state)
      deliver(proc, unique_id, msg, state)
    else
      state
    end
  end

  # Deliver and rebroadcast a message, then search the pending set with deliver(state).
  defp deliver(proc, unique_id, m, state) do
    # increase expected message id of a process
    state = %{
      state
      | next: Map.put(state.next, get_name(unique_id), state.next[get_name(unique_id)] + 1)
    }

    # remove pending
    state = %{state | pending: MapSet.delete(state.pending, {proc, unique_id, m})}

    # deliver
    state = %{state | delivered: MapSet.put(state.delivered, unique_id)}
    send(state.client, {:deliver, self(), get_name(unique_id), m})

    # rebroadcast
    beb_broadcast({:data, proc, unique_id, m}, state.processes)
    # IO.puts("#{inspect(state)}")
    deliver(state)
  end

  # Check if there is a pending message that can be delivered.
  defp pending_msg(state) do
    Enum.find(state.pending, fn x ->
      get_seq(elem(x, 1)) == state.next[get_name(elem(x, 1))]
    end)
  end

  # Get process name from unique_id.
  defp get_name(unique_id) do
    elem(unique_id, 0)
  end

  # Get process sequence number from unique_id.
  defp get_seq(unique_id) do
    elem(unique_id, 1)
  end
end
