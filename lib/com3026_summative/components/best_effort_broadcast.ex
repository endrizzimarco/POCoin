# Best-Effort Broadcast library: do not change or modify!
defmodule BestEffortBroadcast do
  def init() do
    run(%{type: :normal, failed: false})
  end

  def beb_broadcast(pid, m, dest) do
    send(pid, {:bcast, m, dest})
  end

  def fail(pid) do
    send(pid, {:fail})
  end

  def change_bcast_type(pid, type) do
    send(pid, {:change_type, type})
  end

  def run(state) do
    {s_type, s_fail} = {state.type, state.failed}

    state =
      receive do
        {:bcast, m, dest} when s_type == :reorder ->
          beb_broadcast_with_reorder(m, if(s_fail, do: fail_random_dest(dest), else: dest))
          if s_fail, do: Process.exit(self(), :kill), else: state

        {:bcast, m, dest} ->
          beb_broadcast_normal(m, if(s_fail, do: fail_random_dest(dest), else: dest))
          if s_fail, do: Process.exit(self(), :kill), else: state

        {:change_type, :normal} ->
          %{state | type: :normal}

        {:change_type, :reorder} ->
          %{state | type: :reorder}

        {:fail} ->
          %{state | failed: true}

        {:crash} ->
          Process.exit(self(), :kill)
      end

    run(state)
  end

  # Send message m point-to-point to process p
  defp unicast(m, p) do
    case :global.whereis_name(p) do
      pid when is_pid(pid) -> send(pid, m)
      :undefined -> :ok
    end
  end

  def beb_broadcast_normal(m, dest), do: for(p <- dest, do: unicast(m, p))

  defp fail_random_dest(dest) do
    Enum.slice(Enum.shuffle(dest), 0, Enum.random(1..length(dest)))
  end

  def beb_broadcast_with_reorder(m, dest) do
    spawn(fn ->
      Process.sleep(Enum.random(1..2000))
      beb_broadcast_normal(m, dest)
    end)
  end
end
