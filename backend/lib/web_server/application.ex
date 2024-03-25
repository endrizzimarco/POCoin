defmodule WebServer.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start `WebServer` and listen on port 2053
      {Plug.Cowboy, scheme: :http, plug: WebServer, options: [port: 2053]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: WebServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
