defmodule TaskOverlordWeb.Dashboard.CardsLive do
  use TaskOverlordWeb, :live_view
  alias TaskOverlord.Server

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Server.subscribe()
    end

    state = Server.list_all()

    {:ok,
     socket
     |> assign(:tasks, state.tasks |> Map.values())
     |> assign(:overlord_streams, state.streams |> Map.values())
     |> assign_stats()
     |> group_by_status()}
  end

  @impl true
  def handle_info({:updated, state}, socket) do
    {:noreply,
     socket
     |> assign(:tasks, state.tasks |> Map.values())
     |> assign(:overlord_streams, state.streams |> Map.values())
     |> assign_stats()
     |> group_by_status()}
  end

  defp group_by_status(socket) do
    tasks = socket.assigns.tasks
    streams = socket.assigns.overlord_streams

    # Group tasks by status (normalize :running to :in_progress)
    running_tasks = Enum.filter(tasks, &(&1.status == :running))
    done_tasks = Enum.filter(tasks, &(&1.status == :done))
    error_tasks = Enum.filter(tasks, &(&1.status == :error))

    # Group streams by status (normalize :streaming to :in_progress)
    running_streams = Enum.filter(streams, &(&1.status == :streaming))
    done_streams = Enum.filter(streams, &(&1.status == :done))
    error_streams = Enum.filter(streams, &(&1.status == :error))

    socket
    |> assign(:in_progress, running_tasks ++ running_streams)
    |> assign(:completed, done_tasks ++ done_streams)
    |> assign(:failed, error_tasks ++ error_streams)
  end

  defp assign_stats(socket) do
    tasks = socket.assigns.tasks
    overlord_streams = socket.assigns.overlord_streams

    total_tasks = length(tasks)
    total_streams = length(overlord_streams)

    running_tasks = Enum.count(tasks, &(&1.status == :running))
    running_streams = Enum.count(overlord_streams, &(&1.status == :streaming))

    done_tasks = Enum.count(tasks, &(&1.status == :done))
    done_streams = Enum.count(overlord_streams, &(&1.status == :done))

    error_tasks = Enum.count(tasks, &(&1.status == :error))
    error_streams = Enum.count(overlord_streams, &(&1.status == :error))

    success_rate =
      if total_tasks > 0 do
        Float.round(done_tasks / total_tasks * 100, 1)
      else
        0.0
      end

    socket
    |> assign(:stats, %{
      total: total_tasks + total_streams,
      running: running_tasks + running_streams,
      done: done_tasks + done_streams,
      error: error_tasks + error_streams,
      success_rate: success_rate
    })
  end

  defp format_duration(started_at, finished_at) when not is_nil(finished_at) do
    diff = DateTime.diff(finished_at, started_at, :millisecond)
    format_duration_ms(diff)
  end

  defp format_duration(started_at, _finished_at) do
    diff = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
    format_duration_ms(diff)
  end

  defp format_duration_ms(ms) when ms < 1000, do: "#{ms}ms"

  defp format_duration_ms(ms) when ms < 60_000 do
    seconds = Float.round(ms / 1000, 1)
    "#{seconds}s"
  end

  defp format_duration_ms(ms) do
    minutes = div(ms, 60_000)
    seconds = div(rem(ms, 60_000), 1000)
    "#{minutes}m #{seconds}s"
  end

  defp format_relative_time(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 ->
        "#{diff}s ago"

      diff < 3600 ->
        minutes = div(diff, 60)
        "#{minutes}m ago"

      diff < 86400 ->
        hours = div(diff, 3600)
        "#{hours}h ago"

      true ->
        days = div(diff, 86400)
        "#{days}d ago"
    end
  end

  defp status_class(:running), do: "badge-warning"
  defp status_class(:streaming), do: "badge-warning"
  defp status_class(:done), do: "badge-success"
  defp status_class(:error), do: "badge-error"

  defp status_display(:running), do: "Running"
  defp status_display(:streaming), do: "Streaming"
  defp status_display(:done), do: "Done"
  defp status_display(:error), do: "Error"

  defp is_task?(item), do: Map.has_key?(item, :pid)

  defp task_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
      <div class="card-body">
        <div class="flex justify-between items-start">
          <h3 class="card-title text-lg">{@task.heading}</h3>
          <span class={"badge #{status_class(@task.status)}"}>
            {status_display(@task.status)}
          </span>
        </div>

        <p class="text-sm text-base-content/70">{@task.message}</p>

        <div class="divider my-2"></div>

        <div class="space-y-2 text-sm">
          <div class="flex justify-between">
            <span class="text-base-content/60">Started:</span>
            <span class="font-mono">{format_relative_time(@task.started_at)}</span>
          </div>

          <%= if @task.finished_at do %>
            <div class="flex justify-between">
              <span class="text-base-content/60">Finished:</span>
              <span class="font-mono">{format_relative_time(@task.finished_at)}</span>
            </div>
          <% end %>

          <div class="flex justify-between">
            <span class="text-base-content/60">Duration:</span>
            <span class="font-mono font-bold">
              {format_duration(@task.started_at, @task.finished_at)}
            </span>
          </div>

          <%= if @task.status == :error && @task.result do %>
            <div class="alert alert-error mt-2">
              <div class="text-xs">
                <div class="font-bold">Error:</div>
                <div class="font-mono">{inspect(@task.result)}</div>
              </div>
            </div>
          <% end %>

          <%= if @task.status == :done && @task.result do %>
            <div class="collapse collapse-arrow bg-base-200">
              <input type="checkbox" />
              <div class="collapse-title text-sm font-medium">
                View Result
              </div>
              <div class="collapse-content">
                <pre class="text-xs overflow-auto"><%= inspect(@task.result, pretty: true) %></pre>
              </div>
            </div>
          <% end %>
        </div>

        <%= if length(@task.logs) > 0 do %>
          <div class="divider my-2"></div>
          <div class="collapse collapse-arrow bg-base-200">
            <input type="checkbox" />
            <div class="collapse-title text-sm font-medium">
              Logs ({length(@task.logs)})
            </div>
            <div class="collapse-content">
              <div class="space-y-1">
                <%= for {level, log} <- @task.logs do %>
                  <div class="text-xs">
                    <span class="badge badge-xs">{level}</span>
                    <span class="ml-2">{log}</span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <div class="card-actions justify-end mt-2">
          <button
            phx-click="discard_task"
            phx-value-ref={@task.base_encoded_ref}
            class="btn btn-sm btn-ghost"
          >
            Discard
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp stream_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
      <div class="card-body">
        <div class="flex justify-between items-start">
          <h3 class="card-title text-lg">{@stream.heading}</h3>
          <span class={"badge #{status_class(@stream.status)}"}>
            {status_display(@stream.status)}
          </span>
        </div>

        <p class="text-sm text-base-content/70">{@stream.message}</p>

        <div class="divider my-2"></div>

        <!-- Progress Bar -->
        <div class="space-y-2">
          <div class="flex justify-between text-sm">
            <span>Progress</span>
            <span class="font-mono">
              {@stream.stream_completed}/{@stream.stream_total}
            </span>
          </div>
          <progress
            class="progress progress-primary w-full"
            value={@stream.stream_completed}
            max={@stream.stream_total}
          >
          </progress>
          <%= if @stream.stream_total > 0 do %>
            <div class="text-xs text-center">
              {Float.round(@stream.stream_completed / @stream.stream_total * 100, 1)}%
            </div>
          <% end %>
        </div>

        <div class="divider my-2"></div>

        <div class="space-y-2 text-sm">
          <div class="flex justify-between">
            <span class="text-base-content/60">Started:</span>
            <span class="font-mono">{format_relative_time(@stream.started_at)}</span>
          </div>

          <%= if @stream.finished_at do %>
            <div class="flex justify-between">
              <span class="text-base-content/60">Finished:</span>
              <span class="font-mono">{format_relative_time(@stream.finished_at)}</span>
            </div>
          <% end %>

          <div class="flex justify-between">
            <span class="text-base-content/60">Duration:</span>
            <span class="font-mono font-bold">
              {format_duration(@stream.started_at, @stream.finished_at)}
            </span>
          </div>
        </div>

        <%= if length(@stream.logs) > 0 do %>
          <div class="divider my-2"></div>
          <div class="collapse collapse-arrow bg-base-200">
            <input type="checkbox" />
            <div class="collapse-title text-sm font-medium">
              Logs ({length(@stream.logs)})
            </div>
            <div class="collapse-content">
              <div class="space-y-1">
                <%= for {level, log} <- @stream.logs do %>
                  <div class="text-xs">
                    <span class="badge badge-xs">{level}</span>
                    <span class="ml-2">{log}</span>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <div class="card-actions justify-end mt-2">
          <button
            phx-click="discard_stream"
            phx-value-ref={@stream.base_encoded_ref}
            class="btn btn-sm btn-ghost"
          >
            Discard
          </button>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 p-6">
      <div class="max-w-7xl mx-auto space-y-6">
        <!-- Header -->
        <div class="flex justify-between items-center">
          <h1 class="text-4xl font-bold">Task Monitor - Card View</h1>
          <div class="flex gap-2">
            <.link navigate="/dashboard/timeline" class="btn btn-ghost">Timeline</.link>
            <.link navigate="/dashboard/terminal" class="btn btn-ghost">Terminal</.link>
          </div>
        </div>

        <!-- Stats Overview -->
        <div class="stats shadow w-full">
          <div class="stat">
            <div class="stat-title">Total Tasks</div>
            <div class="stat-value">{@stats.total}</div>
          </div>

          <div class="stat">
            <div class="stat-title">Running</div>
            <div class="stat-value text-warning">{@stats.running}</div>
          </div>

          <div class="stat">
            <div class="stat-title">Completed</div>
            <div class="stat-value text-success">{@stats.done}</div>
          </div>

          <div class="stat">
            <div class="stat-title">Errors</div>
            <div class="stat-value text-error">{@stats.error}</div>
          </div>

          <div class="stat">
            <div class="stat-title">Success Rate</div>
            <div class="stat-value">{@stats.success_rate}%</div>
            <div class="stat-desc">Task completion</div>
          </div>
        </div>

        <!-- Kanban Board -->
        <%= if length(@in_progress) > 0 or length(@completed) > 0 or length(@failed) > 0 do %>
          <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
            <!-- In Progress Column -->
            <div class="space-y-4">
              <div class="sticky top-0 bg-warning/20 backdrop-blur-sm rounded-lg p-4 shadow-lg border-2 border-warning">
                <h2 class="text-xl font-bold flex items-center gap-2">
                  <span class="text-2xl">⚡</span>
                  In Progress
                  <span class="badge badge-warning">{length(@in_progress)}</span>
                </h2>
              </div>
              <div class="space-y-4">
                <%= for item <- @in_progress do %>
                  <%= if is_task?(item) do %>
                    <.task_card task={item} />
                  <% else %>
                    <.stream_card stream={item} />
                  <% end %>
                <% end %>
              </div>
            </div>

            <!-- Completed Column -->
            <div class="space-y-4">
              <div class="sticky top-0 bg-success/20 backdrop-blur-sm rounded-lg p-4 shadow-lg border-2 border-success">
                <h2 class="text-xl font-bold flex items-center gap-2">
                  <span class="text-2xl">✅</span>
                  Completed
                  <span class="badge badge-success">{length(@completed)}</span>
                </h2>
              </div>
              <div class="space-y-4">
                <%= for item <- @completed do %>
                  <%= if is_task?(item) do %>
                    <.task_card task={item} />
                  <% else %>
                    <.stream_card stream={item} />
                  <% end %>
                <% end %>
              </div>
            </div>

            <!-- Failed Column -->
            <div class="space-y-4">
              <div class="sticky top-0 bg-error/20 backdrop-blur-sm rounded-lg p-4 shadow-lg border-2 border-error">
                <h2 class="text-xl font-bold flex items-center gap-2">
                  <span class="text-2xl">❌</span>
                  Failed
                  <span class="badge badge-error">{length(@failed)}</span>
                </h2>
              </div>
              <div class="space-y-4">
                <%= for item <- @failed do %>
                  <%= if is_task?(item) do %>
                    <.task_card task={item} />
                  <% else %>
                    <.stream_card stream={item} />
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <%= if length(@in_progress) == 0 and length(@completed) == 0 and length(@failed) == 0 do %>
          <div class="hero bg-base-100 rounded-lg shadow-xl py-20">
            <div class="hero-content text-center">
              <div class="max-w-md">
                <h2 class="text-3xl font-bold">No tasks yet</h2>
                <p class="py-6">Start a task to see it appear here in real-time.</p>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("discard_task", %{"ref" => ref}, socket) do
    Server.discard_task(ref)
    {:noreply, socket}
  end

  @impl true
  def handle_event("discard_stream", %{"ref" => ref}, socket) do
    Server.discard_stream(ref)
    {:noreply, socket}
  end
end
