defmodule Master do
  def start(n \\ 5) do
    paxos_names = get_names(n, "p") # [:p1, :p2, :p3, :p4, :p5]
    node_names = get_names(n, "n") # [:n1, :n2, :n3, :n4, :n5]

    # generate genesis keypair
    {pub_key, priv_key} = :crypto.generate_key(:ecdh, :secp256k1)

    # spawn nodes
    nodes_pids = for name <- node_names, do: BlockchainNode.start(name, node_names, paxos_names, pub_key)

    # master wallet
    master_pid = Wallet.start(String.to_atom("m"), Enum.at(nodes_pids, 0))
    Wallet.add_keypair(master_pid, {pub_key, priv_key})  # provide master with full genesis amount

    # generate alice, bob and charlie's wallets
    wallet_pids = for x <- 1..3, do: Wallet.start(String.to_atom("w#{x}"), Enum.at(nodes_pids, x))
    [alice, bob, _charlie] = for w <- wallet_pids, do: Wallet.generate_address(w)

    Process.sleep(100) # let the master wallet realise he has control of the genesis amount

    # send 20 coins each to alice and bob
    Wallet.send(master_pid, alice, 20)
    Wallet.send(master_pid, bob, 20)
    Wallet.send(master_pid, bob, 20)
    Wallet.send(:global.whereis_name(:w2), alice, 1)
    Wallet.send(:global.whereis_name(:w1), bob, 1)
    Wallet.send(master_pid, bob, 1)


    {nodes_pids, master_pid, wallet_pids}
  end

  defp get_names(n, id) do
    Enum.map(1..n, fn x -> String.to_atom("#{id}#{x}") end)
  end
end
