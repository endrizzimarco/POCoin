defmodule AccountServer do
    
    def start(name, paxos_proc) do
        pid = spawn(AccountServer, :init, [name, paxos_proc])
        pid = case :global.re_register_name(name, pid) do
            :yes -> pid  
            :no  -> nil
        end
        IO.puts(if pid, do: "registered #{name}", else: "failed to register #{name}")
        pid
    end

    def init(name, paxos_proc) do
        state = %{
            name: name,
            pax_pid: get_paxos_pid(paxos_proc),
            last_instance: 0,
            pending: {0, nil},
            balance: 0,

        }
        # Ensures shared destiny (if one of the processes dies, the other one does too)
        # Process.link(state.pax_pid)
        run(state)
    end

    # Get pid of a Paxos instance to connect to
    defp get_paxos_pid(paxos_proc) do
        case :global.whereis_name(paxos_proc) do
                pid when is_pid(pid) -> pid
                :undefined -> raise(Atom.to_string(paxos_proc))
        end
    end

    defp wait_for_reply(_, 0), do: nil
    defp wait_for_reply(r, attempt) do
        msg = receive do
            msg -> msg
            after 1000 -> 
                send(r, {:poll_for_decisions})
                nil
        end
        if msg, do: msg, else: wait_for_reply(r, attempt-1)
    end

    def deposit(r, amount) do
        if amount < 0, do: raise("deposit failed: amount must be positive")
        send(r, {:deposit, self(), amount})
        case wait_for_reply(r, 5) do
            {:deposit_ok} -> :ok
            {:deposit_failed} -> :fail
            {:abort} -> :fail
            _ -> :timeout
        end        
    end

    def withdraw(r, amount) do
        if amount < 0, do: raise("withdraw failed: amount must be positive")
        send(r, {:withdraw, self(), amount})
        case wait_for_reply(r, 5) do
            {:insufficient_funds} -> :insufficient_funds
            {:withdraw_ok} -> :ok
            {:withdraw_failed} -> :fail
            {:abort} -> :fail
            _ -> :timeout
        end
    end

    def balance(r) do
        send(r, {:get_balance, self()})
        receive do
            {:balance, bal} -> bal
            after 10000 -> :timeout
        end
    end


    def run(state) do
        state = receive do
            {trans, client, _}=t when trans == :deposit or trans == :withdraw ->                
                state = poll_for_decisions(state)
                if Paxos.propose(state.pax_pid, state.last_instance+1, t, 1000) == {:abort} do
                    send(client, {:abort})
                else
                    %{state | pending: {state.last_instance+1, client}}
                end

            {:get_balance, client} ->
                state = poll_for_decisions(state)
                send(client, {:balance, state.balance})
                state
            
            # {:abort, inst} ->
            #     {pinst, client} = state.pending
            #     if inst == pinst do
            #         send(client, {:abort})
            #         %{state | pending: {0, nil}}
            #     else
            #         state
            #     end

            {:poll_for_decisions} ->
                poll_for_decisions(state)

            _ -> state
        end
        # IO.puts("REPLICA STATE: #{inspect state}")
        run(state)
    end


    defp poll_for_decisions(state) do
        case  Paxos.get_decision(state.pax_pid, i=state.last_instance+1, 1000) do
            {:deposit, client, amount} ->
                state = case state.pending do
                    {^i, ^client} -> 
                        send(elem(state.pending, 1), {:deposit_ok})
                        %{state | pending: {0, nil}, balance: state.balance+amount}
                    {^i, _} -> 
                        send(elem(state.pending, 1), {:deposit_failed})
                        %{state | pending: {0, nil}, balance: state.balance+amount}
                    _ -> 
                        %{state | balance: state.balance + amount}
                end
                poll_for_decisions(%{state | last_instance: i})

            {:withdraw, client, amount} ->
                state = case state.pending do
                    {^i, ^client} -> 
                        if state.balance - amount < 0 do 
                            send(elem(state.pending, 1), {:insufficient_funds})
                            %{state | pending: {0, nil}}
                        else 
                            send(elem(state.pending, 1), {:withdraw_ok})
                            %{state | pending: {0, nil}}
                        end
                    {^i, _} -> 
                        send(elem(state.pending, 1), {:withdraw_failed})
                        %{state | pending: {0, nil}}
                    _ -> state
                end
                state = %{state | balance: (if (bal = state.balance - amount) < 0, do: state.balance, else: bal)}
                # IO.puts("\tNEW BALANCE: #{bal}")
                poll_for_decisions(%{state | last_instance: i})

            nil -> state  
        end
    end

end