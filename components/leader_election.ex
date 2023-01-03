defmodule EventualLeaderElection do
  def start(name, processes) do
    pid = spawn(EventualLeaderElection, :init, [name, processes])

    case :global.re_register_name(name, pid) do
      :yes -> pid
    end

    IO.puts("registered #{name}")
    pid
  end

  def init(name, processes) do
    state = %{
      name: name,
      processes: processes,
      delta: 500,
      delay: 1000,
      alive: MapSet.new(processes),
      suspected: %MapSet{},
      leader: maxrank(processes)
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

          IO.puts("current leader: #{state.leader}")
          # IO.puts("#{state.name}: #{inspect({:timeout})}")
          state =
            check_and_probe(state, Enum.filter(state.processes, fn p -> state.name != p end))

          state = %{state | alive: %MapSet{}}
          Process.send_after(self(), {:timeout}, state.delay)
          state

        {:heartbeat_request, pid} ->
          IO.puts("#{state.name}: #{inspect({:heartbeat_request, pid})}")
          send(pid, {:heartbeat_reply, state.name})
          state

        {:heartbeat_reply, name} ->
          # Uncomment this line to simulate a delayed response by process :p1
          # if state.name == :p1, do: Process.sleep(10000)

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
          checkrank(state)

        # else if (p ∈ alive) ∧ (p ∈ suspected) then
        p in state.alive and p in state.suspected ->
          state = %{state | suspected: MapSet.delete(state.suspected, p)}
          send(self(), {:restore, p})
          checkrank(state)

        true ->
          state
      end

    case :global.whereis_name(p) do
      pid when is_pid(pid) -> send(pid, {:heartbeat_request, self()})
      :undefined -> :ok
    end

    check_and_probe(state, p_tail)
  end

  defp checkrank(state) do
    if state.leader != maxrank(state.alive) do
      %{state | leader: maxrank(MapSet.put(state.alive, state.name))}
    else
      state
    end
  end

  # first process in ordered alive set = highest rank
  defp maxrank(alive) do
    alive |> Enum.sort() |> Enum.at(0)
  end
end
