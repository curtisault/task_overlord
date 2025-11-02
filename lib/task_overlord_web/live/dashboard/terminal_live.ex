defmodule TaskOverlordWeb.Dashboard.TerminalLive do
  use TaskOverlordWeb, :live_view
  alias TaskOverlord.Server

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Server.subscribe()
      Process.send_after(self(), :update_time, 1000)
    end

    state = Server.list_all()

    {:ok,
     socket
     |> assign(:tasks, state.tasks |> Map.values())
     |> assign(:overlord_streams, state.streams |> Map.values())
     |> assign(:current_time, DateTime.utc_now())
     |> assign(:session_id, generate_session_id())
     |> assign(:feed_events, [])
     |> assign_stats()}
  end

  @impl true
  def handle_info({:updated, state}, socket) do
    tasks = state.tasks |> Map.values()
    overlord_streams = state.streams |> Map.values()

    # Add events to feed for new or updated items
    new_events = generate_feed_events(tasks, overlord_streams, socket.assigns.tasks, socket.assigns.overlord_streams)

    {:noreply,
     socket
     |> assign(:tasks, tasks)
     |> assign(:overlord_streams, overlord_streams)
     |> assign(:feed_events, Enum.take(new_events ++ socket.assigns.feed_events, 20))
     |> assign_stats()}
  end

  @impl true
  def handle_info(:update_time, socket) do
    Process.send_after(self(), :update_time, 1000)
    {:noreply, assign(socket, :current_time, DateTime.utc_now())}
  end

  defp generate_feed_events(new_tasks, new_streams, old_tasks, old_streams) do
    task_events =
      Enum.flat_map(new_tasks, fn task ->
        old_task = Enum.find(old_tasks, &(&1.ref == task.ref))

        cond do
          is_nil(old_task) ->
            [{:task_started, task, DateTime.utc_now()}]

          old_task.status != task.status and task.status == :done ->
            [{:task_completed, task, DateTime.utc_now()}]

          old_task.status != task.status and task.status == :error ->
            [{:task_failed, task, DateTime.utc_now()}]

          true ->
            []
        end
      end)

    stream_events =
      Enum.flat_map(new_streams, fn stream ->
        old_stream = Enum.find(old_streams, &(&1.ref == stream.ref))

        cond do
          is_nil(old_stream) ->
            [{:stream_started, stream, DateTime.utc_now()}]

          old_stream.status != stream.status and stream.status == :done ->
            [{:stream_completed, stream, DateTime.utc_now()}]

          old_stream.stream_completed != stream.stream_completed ->
            [{:stream_progress, stream, DateTime.utc_now()}]

          true ->
            []
        end
      end)

    task_events ++ stream_events
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(4)
    |> Base.encode16(case: :lower)
  end

  defp assign_stats(socket) do
    tasks = socket.assigns.tasks
    overlord_streams = socket.assigns.overlord_streams

    total = length(tasks) + length(overlord_streams)
    running = Enum.count(tasks, &(&1.status == :running)) + Enum.count(overlord_streams, &(&1.status == :streaming))
    done = Enum.count(tasks, &(&1.status == :done)) + Enum.count(overlord_streams, &(&1.status == :done))
    error = Enum.count(tasks, &(&1.status == :error)) + Enum.count(overlord_streams, &(&1.status == :error))

    cpu_usage = if total > 0, do: Float.round(running / total * 100, 1), else: 0.0
    mem_usage = if total > 0, do: Float.round((running + done) / total * 100, 1), else: 0.0

    socket
    |> assign(:stats, %{
      total: total,
      running: running,
      done: done,
      error: error,
      cpu_usage: cpu_usage,
      mem_usage: mem_usage
    })
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

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp status_indicator(:running), do: "RUNNING"
  defp status_indicator(:streaming), do: "RUNNING"
  defp status_indicator(:done), do: "DONE   "
  defp status_indicator(:error), do: "ERROR  "

  defp status_color(:running), do: "text-warning"
  defp status_color(:streaming), do: "text-warning"
  defp status_color(:done), do: "text-success"
  defp status_color(:error), do: "text-error"

  defp render_progress_bar(completed, total, width) do
    if total > 0 do
      filled = trunc(completed / total * width)
      empty = width - filled
      "█" |> String.duplicate(filled) |> Kernel.<>(String.duplicate("░", empty))
    else
      String.duplicate("░", width)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-black text-green-400 font-mono p-4" style="font-family: 'Courier New', monospace;">
      <!-- Terminal Header -->
      <div class="border border-green-500 p-3 mb-4 shadow-lg shadow-green-500/20">
        <div class="flex justify-between items-center">
          <div class="flex items-center gap-4">
            <span class="text-green-300">▶ FINCHART TERMINAL v1.0</span>
            <span class="text-cyan-400">
              [SESSION: <%= @session_id %>]
            </span>
            <span class="text-cyan-400">
              UTC: <%= Calendar.strftime(@current_time, "%Y-%m-%d %H:%M:%S") %>
            </span>
          </div>
          <div class="flex gap-2">
            <.link navigate="/dashboard/cards" class="text-gray-500 hover:text-green-400">
              [CARDS]
            </.link>
            <.link navigate="/dashboard/timeline" class="text-gray-500 hover:text-green-400">
              [TIMELINE]
            </.link>
          </div>
        </div>
      </div>

      <div class="grid grid-cols-12 gap-4">
        <!-- Left Column: Task Monitor + Quick Actions -->
        <div class="col-span-5 space-y-4">
          <!-- Task Monitor -->
          <div class="border border-green-500 p-3 shadow-lg shadow-green-500/20">
            <div class="text-cyan-400 mb-2">─── TASK MONITOR ───</div>

            <%= if length(@tasks) > 0 do %>
              <div class="space-y-2 max-h-96 overflow-y-auto">
                <%= for task <- Enum.take(@tasks, 10) do %>
                  <div class="border-l-2 border-green-700 pl-2">
                    <div class="flex justify-between items-start">
                      <span class="text-green-300">▸ <%= String.slice(to_string(task.heading), 0, 30) %></span>
                      <span class={"#{status_color(task.status)} font-bold"}>
                        <%= status_indicator(task.status) %>
                      </span>
                    </div>
                    <div class="text-xs text-gray-500 mt-1">
                      PID: <%= inspect(task.pid) |> String.slice(0, 20) %> |
                      UPTIME: <%= format_duration_ms(DateTime.diff(DateTime.utc_now(), task.started_at, :millisecond)) %>
                    </div>
                    <%= if task.status == :running do %>
                      <div class="text-cyan-400 text-xs mt-1 animate-pulse">
                        <%= render_progress_bar(rem(System.system_time(:second), 10), 10, 30) %>
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="text-gray-600 text-center py-8">
                [NO ACTIVE TASKS]
              </div>
            <% end %>
          </div>

          <!-- Stream Monitor -->
          <%= if length(@overlord_streams) > 0 do %>
            <div class="border border-cyan-500 p-3 shadow-lg shadow-cyan-500/20">
              <div class="text-cyan-400 mb-2">─── STREAM MONITOR ───</div>
              <div class="space-y-2">
                <%= for stream <- Enum.take(@overlord_streams, 5) do %>
                  <div class="border-l-2 border-cyan-700 pl-2">
                    <div class="flex justify-between items-start">
                      <span class="text-cyan-300">▸ <%= String.slice(to_string(stream.heading), 0, 30) %></span>
                      <span class={"#{status_color(stream.status)} font-bold"}>
                        <%= status_indicator(stream.status) %>
                      </span>
                    </div>
                    <div class="text-xs text-gray-500 mt-1">
                      PROGRESS: <%= stream.stream_completed %>/<%= stream.stream_total %>
                    </div>
                    <div class="text-cyan-400 text-xs mt-1">
                      <%= render_progress_bar(stream.stream_completed, stream.stream_total, 30) %>
                      <%= if stream.stream_total > 0 do %>
                        <%= Float.round(stream.stream_completed / stream.stream_total * 100, 1) %>%
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>

          <!-- Quick Actions -->
          <div class="border border-yellow-500 p-3 shadow-lg shadow-yellow-500/20">
            <div class="text-yellow-400 mb-2">─── QUICK ACTIONS ───</div>
            <div class="space-y-1">
              <button phx-click="action_new_task" class="w-full text-left hover:bg-green-900/30 px-2 py-1">
                [F1] NEW_TASK
              </button>
              <button phx-click="action_stop_all" class="w-full text-left hover:bg-green-900/30 px-2 py-1">
                [F2] STOP_ALL
              </button>
              <button phx-click="action_clear_done" class="w-full text-left hover:bg-green-900/30 px-2 py-1">
                [F3] CLEAR_DONE
              </button>
              <button phx-click="action_export" class="w-full text-left hover:bg-green-900/30 px-2 py-1">
                [F4] EXPORT
              </button>
            </div>
          </div>

          <!-- System Metrics -->
          <div class="border border-green-500 p-3 shadow-lg shadow-green-500/20">
            <div class="text-cyan-400 mb-2">─── SYSTEM METRICS ───</div>
            <div class="space-y-2 text-sm">
              <div>
                <div class="flex justify-between mb-1">
                  <span class="text-gray-400">CPU:</span>
                  <span class="text-green-400"><%= @stats.cpu_usage %>%</span>
                </div>
                <div class="bg-gray-800 h-2 rounded">
                  <div
                    class="bg-green-500 h-2 rounded transition-all duration-300"
                    style={"width: #{@stats.cpu_usage}%"}
                  >
                  </div>
                </div>
              </div>

              <div>
                <div class="flex justify-between mb-1">
                  <span class="text-gray-400">MEM:</span>
                  <span class="text-cyan-400"><%= @stats.mem_usage %>%</span>
                </div>
                <div class="bg-gray-800 h-2 rounded">
                  <div
                    class="bg-cyan-500 h-2 rounded transition-all duration-300"
                    style={"width: #{@stats.mem_usage}%"}
                  >
                  </div>
                </div>
              </div>

              <div class="pt-2 border-t border-gray-700">
                <div class="flex justify-between">
                  <span class="text-gray-400">TOTAL:</span>
                  <span class="text-green-400"><%= @stats.total %></span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-400">RUNNING:</span>
                  <span class="text-yellow-400"><%= @stats.running %></span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-400">DONE:</span>
                  <span class="text-green-400"><%= @stats.done %></span>
                </div>
                <div class="flex justify-between">
                  <span class="text-gray-400">ERROR:</span>
                  <span class="text-red-400"><%= @stats.error %></span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Right Column: Live Feed + Analytics -->
        <div class="col-span-7 space-y-4">
          <!-- Live Feed -->
          <div class="border border-green-500 p-3 shadow-lg shadow-green-500/20 h-[600px] flex flex-col">
            <div class="text-cyan-400 mb-2">─── LIVE FEED ───</div>
            <div class="flex-1 overflow-y-auto space-y-1 text-sm">
              <%= if length(@feed_events) == 0 do %>
                <div class="text-gray-600">
                  [<%= format_timestamp(@current_time) %>] INFO: Waiting for events...
                </div>
              <% end %>

              <%= for {event_type, item, timestamp} <- @feed_events do %>
                <div class="flex gap-2">
                  <span class="text-gray-500">[<%= format_timestamp(timestamp) %>]</span>
                  <%= case event_type do %>
                    <% :task_started -> %>
                      <span class="text-cyan-400">TASK_START:</span>
                      <span class="text-green-300"><%= item.heading %> started</span>
                    <% :task_completed -> %>
                      <span class="text-green-400">TASK_DONE:</span>
                      <span class="text-green-300">
                        <%= item.heading %> completed in <%= format_duration_ms(
                          DateTime.diff(item.finished_at, item.started_at, :millisecond)
                        ) %>
                      </span>
                    <% :task_failed -> %>
                      <span class="text-red-400">TASK_ERROR:</span>
                      <span class="text-red-300"><%= item.heading %> failed</span>
                    <% :stream_started -> %>
                      <span class="text-cyan-400">STREAM_START:</span>
                      <span class="text-cyan-300">
                        <%= item.heading %> started (<%= item.stream_total %> items)
                      </span>
                    <% :stream_completed -> %>
                      <span class="text-green-400">STREAM_DONE:</span>
                      <span class="text-green-300">
                        <%= item.heading %> completed <%= item.stream_completed %> items
                      </span>
                    <% :stream_progress -> %>
                      <span class="text-yellow-400">STREAM_PROGRESS:</span>
                      <span class="text-yellow-300">
                        <%= item.heading %> - <%= item.stream_completed %>/<%= item.stream_total %>
                      </span>
                  <% end %>
                </div>
              <% end %>

              <div class="flex gap-2 animate-pulse">
                <span class="text-gray-500">[<%= format_timestamp(@current_time) %>]</span>
                <span class="text-gray-600">_</span>
              </div>
            </div>
          </div>

          <!-- Analytics -->
          <div class="border border-green-500 p-3 shadow-lg shadow-green-500/20">
            <div class="text-cyan-400 mb-2">─── ANALYTICS ───</div>
            <div class="grid grid-cols-2 gap-4">
              <div class="border border-gray-700 p-3">
                <div class="text-green-300 font-bold text-2xl"><%= @stats.total %></div>
                <div class="text-xs text-gray-500">Total Tasks</div>
              </div>
              <div class="border border-gray-700 p-3">
                <div class="text-yellow-300 font-bold text-2xl"><%= @stats.running %></div>
                <div class="text-xs text-gray-500">Active</div>
              </div>
              <div class="border border-gray-700 p-3">
                <div class="text-green-300 font-bold text-2xl"><%= @stats.done %></div>
                <div class="text-xs text-gray-500">Completed</div>
              </div>
              <div class="border border-gray-700 p-3">
                <div class="text-red-300 font-bold text-2xl"><%= @stats.error %></div>
                <div class="text-xs text-gray-500">Errors</div>
              </div>
            </div>

            <!-- Success Rate Chart -->
            <div class="mt-4 border border-gray-700 p-3">
              <div class="text-xs text-gray-400 mb-2">Success Rate</div>
              <div class="flex items-end gap-1 h-20">
                <%= for i <- 1..20 do %>
                  <%
                  height =
                    cond do
                      @stats.total == 0 -> 0
                      rem(i, 3) == 0 -> Enum.random(40..100)
                      true -> Enum.random(60..95)
                    end
                  %>
                  <div class="flex-1 bg-green-600 transition-all" style={"height: #{height}%"}></div>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Command Line -->
          <div class="border border-green-500 p-3 shadow-lg shadow-green-500/20">
            <div class="text-cyan-400 mb-2">─── COMMAND ───</div>
            <div class="flex items-center gap-2">
              <span class="text-green-400">></span>
              <input
                type="text"
                class="flex-1 bg-black border-0 outline-none text-green-400"
                placeholder="Enter command..."
                phx-keydown="execute_command"
                phx-key="Enter"
              />
              <span class="animate-pulse">_</span>
            </div>
            <div class="text-xs text-gray-600 mt-2">
              HOTKEYS: F1-F4 (Actions) | CTRL+L (Clear) | ESC (Menu)
            </div>
          </div>
        </div>
      </div>

      <!-- Status Bar -->
      <div class="border border-green-500 p-2 mt-4 flex justify-between text-xs shadow-lg shadow-green-500/20">
        <div class="flex gap-4">
          <span class="text-green-400">STATUS: ONLINE</span>
          <span class="text-cyan-400">CONNECTED TO: TASK_OVERLORD</span>
        </div>
        <div class="flex gap-4">
          <span class="text-yellow-400">LATENCY: 12ms</span>
          <span class="text-green-400">UPTIME: <%= format_duration_ms(System.system_time(:millisecond)) %></span>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("action_new_task", _params, socket) do
    # Placeholder for new task action
    {:noreply, socket}
  end

  @impl true
  def handle_event("action_stop_all", _params, socket) do
    # Stop all running tasks
    Enum.each(socket.assigns.tasks, fn task ->
      if task.status == :running do
        Server.discard_task(task.base_encoded_ref)
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("action_clear_done", _params, socket) do
    # Clear all completed tasks
    Enum.each(socket.assigns.tasks, fn task ->
      if task.status == :done do
        Server.discard_task(task.base_encoded_ref)
      end
    end)

    Enum.each(socket.assigns.overlord_streams, fn stream ->
      if stream.status == :done do
        Server.discard_stream(stream.base_encoded_ref)
      end
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_event("action_export", _params, socket) do
    # Placeholder for export action
    {:noreply, socket}
  end

  @impl true
  def handle_event("execute_command", _params, socket) do
    # Placeholder for command execution
    {:noreply, socket}
  end
end
