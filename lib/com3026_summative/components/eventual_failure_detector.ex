defmodule IncreasingTimeout do
  def start(name, processes) do
    pid = spawn(IncreasingTimeout, :init, [name, processes])

    case :global.re_register_name(name, pid) do
      :yes -> pid
      :no -> :error
    end

    IO.puts("registered #{name}")
    pid
  end

  # Init event must be the first
  # one after the component is created
  def init(name, processes) do
    state = %{
      name: name,
      processes: Enum.filter(processes, fn p -> name != p end),
      # timeout in millis
      delta: 500,
      delay: 1000,
      alive: MapSet.new(processes),
      suspected: %MapSet{}
    }

    Process.send_after(self(), {:timeout}, state.delta)
    run(state)
  end

  def run(state) do
    state =
      receive do
        {:timeout} ->
          # if alive ∩ suspected ̸= ∅ then
          if MapSet.intersection(state.alive, state.suspected) != %MapSet{} do
            %{state | delta: state.delay + state.delta}
          end

          IO.puts("#{state.name}: #{inspect({:timeout})}")
          state = check_and_probe(state, state.processes)
          state = %{state | alive: %MapSet{}}
          Process.send_after(self(), {:timeout}, state.delay)
          state

        {:heartbeat_request, pid} ->
          IO.puts("#{state.name}: #{inspect({:heartbeat_request, pid})}")
          send(pid, {:heartbeat_reply, state.name})
          state

        {:heartbeat_reply, name} ->
          # Uncomment this line to simulate a delayed response by process :p1
          # This results in all processes detecting :p1 as crashed.
          if state.name == :p1, do: Process.sleep(10000)

          IO.puts("#{state.name}: #{inspect({:heartbeat_reply, name})}")
          %{state | alive: MapSet.put(state.alive, name)}

        {:restore, p} ->
          IO.puts("#{state.name}: #{p} decided to come back from the dead and has been RESTORED")
          state

        {:crash, p} ->
          IO.puts("#{state.name}: CRASH suspected #{p}")
          state
      end

    run(state)
  end

  defp check_and_probe(state, []), do: state

  defp check_and_probe(state, [p | p_tail]) do
    state =
      cond do
        # if (p ̸∈ alive) ∧ (p ̸∈ detected) then
        p not in state.alive and p not in state.suspected ->
          state = %{state | suspected: MapSet.put(state.suspected, p)}
          send(self(), {:crash, p})
          state

        # else if (p ∈ alive) ∧ (p ∈ suspected) then
        p in state.alive and p in state.suspected ->
          state = %{state | suspected: MapSet.delete(state.suspected, p)}
          send(self(), {:restore, p})
          state

        true ->
          state
      end

    case :global.whereis_name(p) do
      pid when is_pid(pid) -> send(pid, {:heartbeat_request, self()})
      # IO.puts("self: #{inspect(self())}\npid: #{inspect(pid)}\nare different: #{inspect(pid != self())}")
      # IO.puts("pid: #{inspect(pid)}")
      :undefined -> :ok
    end

    check_and_probe(state, p_tail)
  end
end
