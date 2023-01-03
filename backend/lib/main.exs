IEx.Helpers.c "components/best_effort_broadcast.ex", "."
IEx.Helpers.c "components/paxos.ex", "."
IEx.Helpers.c "components/wallet.ex", "."
IEx.Helpers.c "components/node.ex", "."
IEx.Helpers.c "components/master.ex", "."

{nodes_pids, master_pid, wallet_pids} = Master.start()
IO.puts("master_pid: #{inspect master_pid}")
IO.puts("wallet_pids: #{inspect wallet_pids}")
IO.puts("nodes_pids: #{inspect nodes_pids}")

# :global.whereis_name(:n1) |> BlockchainNode.get_blockchain()
# :global.whereis_name(:w1) |> Wallet.send(
# :global.whereis_name(:w1) |> Wallet.balance()
