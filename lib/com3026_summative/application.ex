defmodule Com3026Summative.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      Com3026Summative.Repo,
      # Start the Telemetry supervisor
      Com3026SummativeWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Com3026Summative.PubSub},
      # Start the Endpoint (http/https)
      Com3026SummativeWeb.Endpoint
      # Start a worker by calling: Com3026Summative.Worker.start_link(arg)
      # {Com3026Summative.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Com3026Summative.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    Com3026SummativeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
