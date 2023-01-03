require Prime

defmodule PedersonCommitment do
  @spec setup :: {pos_integer, pos_integer, pos_integer, any}
  def setup do
    p = Prime.generate(10)
    q = 2 * p + 1

    g = :rand.uniform(q - 1)
    s = :rand.uniform(q - 1)
    h = :crypto.mod_pow(g, s, q)

    {q, s, g, h}
  end

  def verify(params, c, x, r) do
    [q, g, h] = params

    sum = Enum.sum(r)
    # (pow(g,x,q) * pow(h,sum,q)) % q
    res = Kernel.rem(:crypto.mod_pow(g, x, q) * :crypto.mod_pow(h, sum, q), q)
    IO.puts("res: #{res}")

    if res == c do
      True
    end
  end

  def create(params, x) do
    [q, g, h] = params

    r = :rand.uniform(q - 1)
    c = Kernel.rem(:crypto.mod_pow(g, x, q) * :crypto.mod_pow(h, r, q), q)

    {c, r}
  end

  def add() do
  end
end
