IEx.Helpers.c "lib/components/best_effort_broadcast.ex", "."
IEx.Helpers.c "lib/components/paxos.ex", "."
IEx.Helpers.c "lib/components/wallet.ex", "."
IEx.Helpers.c "lib/components/node.ex", "."
IEx.Helpers.c "lib/components/master.ex", "."

{nodes_pids, wallet_pids} = Master.start()
IO.puts("wallet_pids: #{inspect wallet_pids}")
IO.puts("nodes_pids: #{inspect nodes_pids}")

# :global.whereis_name(:n1) |> BlockchainNode.get_blockchain()
# :global.whereis_name(:w1) |> Wallet.send(
# :global.whereis_name(:w1) |> Wallet.balance()
