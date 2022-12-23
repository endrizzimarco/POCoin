defmodule BEB_Broadcast do

 def broadcast(m, dest), do: for(p <- dest, do: unicast(m, p))

  # Send message m point-to-point to process p
  defp unicast(m, p) do
    case :global.whereis_name(p) do
      pid when is_pid(pid) -> send(pid, m)
      :undefined -> :ok
    end
  end
end