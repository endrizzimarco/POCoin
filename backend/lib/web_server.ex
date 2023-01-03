defmodule WebServer do
  import Plug.Conn

  def init(options) do
    {nodes_pids, master_pid, wallet_pids} = Master.start()
  end

  def call(conn, pids) do
    {nodes_pids, master_pid, wallet_pids} = pids

    case conn.path_info do
      ["balance", w] -> response(conn, Wallet.balance(get_pid(w)))
      ["send", w, to, amount] -> response(conn, Wallet.send(get_pid(w), to, amount))
      "/world" -> response(conn, "lol")
      _ -> response(conn, "not found")
    end
  end

  def response(conn, data) do
    conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(data))
  end

  defp get_pid(name) do
    :global.whereis_name(String.to_atom(name))
  end
end
