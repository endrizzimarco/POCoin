IEx.Helpers.c "best_effort_broadcast.ex", "."
IEx.Helpers.c "paxos.ex", "."
IEx.Helpers.c "../confidential_utxo/wallet.ex", "."
IEx.Helpers.c "../confidential_utxo/node.ex", "."

defmodule Master do
  def start(n \\ 5) do
    paxos_names = get_names(n, "p") # [:p1, :p2, :p3, :p4, :p5]
    node_names = get_names(n, "n") # [:n1, :n2, :n3, :n4, :n5]

    # generate genesis keypair
    {pub_key, priv_key} = :crypto.generate_key(:ecdh, :secp256k1)

    # spawn nodes
    nodes_pids = for name <- node_names, do: spawn(BlockchainNode, :start, [name, node_names, paxos_names, pub_key])

    # master wallet
    master_pid = spawn(Wallet, :start, [Enum.at(nodes_pids, 0)])
    Wallet.add_keypair(master_pid, {pub_key, priv_key})  # provide master with full genesis amount

    # generate alice and bob wallets
    wallet_pids = for x <- (1..2), do: spawn(Wallet, :start, [Enum.at(nodes_pids, x)])
    alice = Wallet.generate_address(Enum.at(wallet_pids, 0))
    bob = Wallet.generate_address(Enum.at(wallet_pids, 1))

    # send 20 coins each to alice and bob
    Wallet.send(master_pid, alice, 20)
    Wallet.send(master_pid, bob, 20)

    # TODO: what if a node fails? Alice and Bobs wallets are completely fucked hehe
    # efd_pids =
    #   for {p_pid, n_pid} <- {paxos_pids, nodes_pids},
    #       do: spawn_link(EventualFailureDetector, :init, [p_pid, n_pid])

    {nodes_pids, master_pid, wallet_pids}
  end

  defp get_names(n, id) do
    Enum.map(1..n, fn x -> String.to_atom("#{id}#{x}") end)
  end
end

{nodes_pids, master_pid, wallet_pids} = Master.start()
IO.puts(inspect nodes_pids)
# master_pid |> Wallet.balance()
