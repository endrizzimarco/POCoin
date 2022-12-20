defmodule TestResults do
  def start() do
    spawn(TestResults, :run, [%{pass: [], fail: []}])
  end

  def run(state) do
    state =
      receive do
        {:test, result, name, desc} ->
          case result do
            "PASS" ->
              %{state | pass: [name | state.pass]}

            "FAIL" ->
              %{state | fail: [{name, desc} | state.fail]}

            _ ->
              state
          end

        {:state, client} ->
          send(client, {:response, state})
          # Process.exit(self(), :normal)
          state

        _ ->
          state
      end

    run(state)
  end

  def final_status(pid) do
    send(pid, {:state, self()})

    receive do
      {:response, state} ->
        Process.sleep(100)
        IO.puts("\n============================")
        IO.puts("--------- RESULTS ----------")
        IO.puts("============================")
        IO.puts("Passed: #{length(state.pass)}/#{length(state.pass) + length(state.fail)}\n")

        if length(state.fail) != 0 do
          IO.puts("==== Failed tests: =====")

          for x <- state.fail do
            IO.puts("Name: #{inspect(elem(x, 0))}")
            IO.puts("Result: #{inspect(elem(x, 1))}\n")
          end
        end
    after
      1000 ->
        IO.puts("Timeout")
    end
  end

  def add(pid, name, result, desc) do
    send(pid, {:test, result, name, desc})
  end
end
