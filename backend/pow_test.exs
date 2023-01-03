# iex pow_tests.exs
defmodule Test do
  def proof_of_work(pid, block) do
    n = :rand.uniform(trunc(:math.pow(2, 32)))

    cond do
      String.starts_with?(calculate_pow_hash(block, n), "0000") ->
        send(pid, {:pow_found, block, n})

      true ->
        proof_of_work(pid, block)
    end
  end

  defp calculate_pow_hash(block, n) do
    bin_sum = :erlang.term_to_binary(block) <> :erlang.term_to_binary(n)
    b = :crypto.hash(:sha256, bin_sum) |> Base.encode16()
    IO.inspect(b)
    b
  end
end

time = Time.utc_now()
Test.proof_of_work(self(), %{:a => "b"})
IO.inspect(Time.diff(Time.utc_now(), time, :millisecond))
