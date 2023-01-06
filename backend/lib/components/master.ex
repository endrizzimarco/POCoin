defmodule Master do
  def start(n \\ 5) do
    paxos_names = get_names(n, "p") # [:p1, :p2, :p3, :p4, :p5]
    node_names = get_names(n, "n") # [:n1, :n2, :n3, :n4, :n5]

    # generate genesis keypair
    {pub_key, priv_key} = :crypto.generate_key(:ecdh, :secp256k1)

    # spawn nodes
    nodes_pids = for name <- node_names, do: BlockchainNode.start(name, node_names, paxos_names, pub_key)

    # spawn wallets
    wallet_pids = for x <- 0..4, do: Wallet.start(String.to_atom("w#{x+1}"), Enum.at(nodes_pids, x))
    alice_pid = Enum.at(wallet_pids, 0)

    # provide alice with full genesis amount
    Wallet.add_keypair(alice_pid, {pub_key, priv_key})

    # generate addresses for everyone
    [_alice, bob, charlie, marco, georgi] = for w <- wallet_pids, do: Wallet.generate_address(w)

    # distribute coins to everyone
    Wallet.send(alice_pid, bob, 200)
    Wallet.send(alice_pid, charlie, 200)
    Wallet.send(alice_pid, marco, 200)
    Wallet.send(alice_pid, georgi, 200)

    {nodes_pids, wallet_pids}
  end

  defp get_names(n, id) do
    Enum.map(1..n, fn x -> String.to_atom("#{id}#{x}") end)
  end
end
