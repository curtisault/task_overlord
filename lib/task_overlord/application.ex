defmodule TaskOverlord.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TaskOverlordWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:task_overlord, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TaskOverlord.PubSub},
      {Task.Supervisor, name: TaskOverlord.TaskSupervisor},
      # Start a worker by calling: TaskOverlord.Worker.start_link(arg)
      # {TaskOverlord.Worker, arg},
      # Start to serve requests, typically the last entry
      TaskOverlordWeb.Endpoint,
      TaskOverlord.Server
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TaskOverlord.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TaskOverlordWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
