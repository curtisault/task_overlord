defmodule TaskOverlordWeb.Dashboard.TerminalLive do
  use TaskOverlordWeb, :live_view
  alias TaskOverlord.Server
  alias TaskOverlordWeb.Dashboard.Commands
  alias TaskOverlordWeb.Dashboard.CommandSearch

  @feed_limit 50

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
     |> assign(:command_input, "")
     |> assign(:command_suggestions, [])
     |> assign(:selected_suggestion_index, 0)
     |> assign(:command_history, [])
     |> assign(:history_index, -1)
     |> assign(:show_help_modal, false)
     |> assign(:active_filter, :all)
     |> assign_stats()}
  end

  @impl true
  def handle_info({:updated, state}, socket) do
    tasks = state.tasks |> Map.values()
    overlord_streams = state.streams |> Map.values()

    # Add events to feed for new or updated items
    new_events =
      generate_feed_events(
        tasks,
        overlord_streams,
        socket.assigns.tasks,
        socket.assigns.overlord_streams
      )

    {:noreply,
     socket
     |> assign(:tasks, tasks)
     |> assign(:overlord_streams, overlord_streams)
     |> assign(:feed_events, Enum.take(new_events ++ socket.assigns.feed_events, @feed_limit))
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

    running =
      Enum.count(tasks, &(&1.status == :running)) +
        Enum.count(overlord_streams, &(&1.status == :streaming))

    done =
      Enum.count(tasks, &(&1.status == :done)) +
        Enum.count(overlord_streams, &(&1.status == :done))

    error =
      Enum.count(tasks, &(&1.status == :error)) +
        Enum.count(overlord_streams, &(&1.status == :error))

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
    <div
      class="min-h-screen bg-black text-green-400 font-mono p-4"
      style="font-family: 'Courier New', monospace;"
    >
      <!-- Terminal Header -->
      <div class="border border-green-500 p-3 mb-4 shadow-lg shadow-green-500/20">
        <div class="flex justify-between items-center">
          <div class="flex items-center gap-4">
            <span class="text-green-300">▶ OVERLORD TERMINAL v1.0</span>
            <span class="text-cyan-400">
              [SESSION: {@session_id}]
            </span>
            <span class="text-cyan-400">
              UTC: {Calendar.strftime(@current_time, "%Y-%m-%d %H:%M:%S")}
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

      <div class="grid grid-cols-12 gap-4 items-stretch min-h-[calc(100vh-12rem)]">
        <!-- Left Column: Task Monitor + Quick Actions -->
        <div class="col-span-5 space-y-4">
          <!-- Task Monitor -->
          <div class="border border-green-500 p-3 shadow-lg shadow-green-500/20">
            <div class="text-cyan-400 mb-2">─── TASK MONITOR ───</div>

            <%= if length(@tasks) > 0 do %>
              <div class="space-y-2 max-h-96 overflow-y-auto">
                <%= for task <- @tasks |> Enum.sort_by(& &1.started_at, {:desc, DateTime}) |> Enum.take(10) do %>
                  <div class="border-l-2 border-green-700 pl-2">
                    <div class="flex justify-between items-start">
                      <span class="text-green-300">
                        ▸ {String.slice(to_string(task.heading), 0, 30)}
                      </span>
                      <span class={"#{status_color(task.status)} font-bold"}>
                        {status_indicator(task.status)}
                      </span>
                    </div>
                    <div class="text-xs text-gray-500 mt-1">
                      PID: {inspect(task.pid) |> String.slice(0, 20)} |
                      UPTIME: {format_duration_ms(
                        DateTime.diff(DateTime.utc_now(), task.started_at, :millisecond)
                      )}
                    </div>
                    <%= if task.status == :running do %>
                      <div class="text-cyan-400 text-xs mt-1 animate-pulse">
                        {render_progress_bar(rem(System.system_time(:second), 10), 10, 30)}
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
          <div class="border border-cyan-500 p-3 shadow-lg shadow-cyan-500/20">
            <div class="text-cyan-400 mb-2">─── STREAM MONITOR ───</div>

            <%= if length(@overlord_streams) > 0 do %>
              <div class="space-y-2">
                <%= for stream <- @overlord_streams |> Enum.sort_by(& &1.started_at, {:desc, DateTime}) |> Enum.take(5) do %>
                  <div class="border-l-2 border-cyan-700 pl-2">
                    <div class="flex justify-between items-start">
                      <span class="text-cyan-300">
                        ▸ {String.slice(to_string(stream.heading), 0, 30)}
                      </span>
                      <span class={"#{status_color(stream.status)} font-bold"}>
                        {status_indicator(stream.status)}
                      </span>
                    </div>
                    <div class="text-xs text-gray-500 mt-1">
                      PROGRESS: {stream.stream_completed}/{stream.stream_total}
                    </div>
                    <div class="text-cyan-400 text-xs mt-1">
                      {render_progress_bar(stream.stream_completed, stream.stream_total, 30)}
                      <%= if stream.stream_total > 0 do %>
                        {Float.round(stream.stream_completed / stream.stream_total * 100, 1)}%
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="text-gray-600 text-center py-8">
                [NO ACTIVE STREAMS]
              </div>
            <% end %>
          </div>
          
    <!-- Quick Actions + System Metrics -->
          <div class="grid grid-cols-2 gap-4">
            <!-- Quick Actions -->
            <div class="border border-yellow-500 p-3 shadow-lg shadow-yellow-500/20">
              <div class="text-yellow-400 mb-2">─── QUICK ACTIONS ───</div>
              <div class="space-y-1">
                <button
                  phx-click="action_new_task"
                  class="w-full text-left hover:bg-green-900/30 px-2 py-1"
                >
                  [F1] NEW_TASK
                </button>
                <button
                  phx-click="action_stop_all"
                  class="w-full text-left hover:bg-green-900/30 px-2 py-1"
                >
                  [F2] STOP_ALL
                </button>
                <button
                  phx-click="action_clear_done"
                  class="w-full text-left hover:bg-green-900/30 px-2 py-1"
                >
                  [F3] CLEAR_DONE
                </button>
                <button
                  phx-click="action_export"
                  class="w-full text-left hover:bg-green-900/30 px-2 py-1"
                >
                  [F4] EXPORT
                </button>
              </div>
            </div>
            
    <!-- System Metrics -->
            <div class="border border-green-500 p-3 shadow-lg shadow-green-500/20">
              <div class="text-cyan-400 mb-2">─── SYSTEM METRICS ───</div>
              <div class="space-y-2 text-sm">
                <div class="grid grid-cols-2 gap-2">
                  <div>
                    <div class="flex justify-between mb-1">
                      <span class="text-gray-400 text-xs">CPU:</span>
                      <span class="text-green-400 text-xs">{@stats.cpu_usage}%</span>
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
                      <span class="text-gray-400 text-xs">MEM:</span>
                      <span class="text-cyan-400 text-xs">{@stats.mem_usage}%</span>
                    </div>
                    <div class="bg-gray-800 h-2 rounded">
                      <div
                        class="bg-cyan-500 h-2 rounded transition-all duration-300"
                        style={"width: #{@stats.mem_usage}%"}
                      >
                      </div>
                    </div>
                  </div>
                </div>

                <div class="pt-2 border-t border-gray-700 text-xs">
                  <div class="flex justify-between">
                    <span class="text-gray-400">TOTAL:</span>
                    <span class="text-green-400">{@stats.total}</span>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-gray-400">RUNNING:</span>
                    <span class="text-yellow-400">{@stats.running}</span>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-gray-400">DONE:</span>
                    <span class="text-green-400">{@stats.done}</span>
                  </div>
                  <div class="flex justify-between">
                    <span class="text-gray-400">ERROR:</span>
                    <span class="text-red-400">{@stats.error}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
          
    <!-- Analytics -->
          <div class="border border-green-500 p-3 shadow-lg shadow-green-500/20">
            <div class="text-cyan-400 mb-2">─── ANALYTICS ───</div>
            <div class="grid grid-cols-2 gap-4">
              <!-- Left Column: Stats List -->
              <div class="space-y-3">
                <div class="flex justify-between items-center">
                  <div class="text-gray-400 text-sm">Total Tasks:</div>
                  <div class="text-green-300 font-bold text-2xl">{@stats.total}</div>
                </div>
                <div class="flex justify-between items-center">
                  <div class="text-gray-400 text-sm">Completed:</div>
                  <div class="text-green-300 font-bold text-2xl">{@stats.done}</div>
                </div>
                <div class="flex justify-between items-center">
                  <div class="text-gray-400 text-sm">Active:</div>
                  <div class="text-yellow-300 font-bold text-2xl">{@stats.running}</div>
                </div>
                <div class="flex justify-between items-center">
                  <div class="text-gray-400 text-sm">Errors:</div>
                  <div class="text-red-300 font-bold text-2xl">{@stats.error}</div>
                </div>
              </div>
              
    <!-- Right Column: Success Rate Bar -->
              <div class="flex flex-col items-center justify-center">
                <div class="text-gray-400 text-sm mb-2">Success Rate</div>
                <% success_rate =
                  if @stats.total > 0,
                    do: round((@stats.total - @stats.error) / @stats.total * 100),
                    else: 0 %>
                <div class="h-32 w-16 bg-gray-800 rounded relative flex flex-col-reverse border border-gray-700">
                  <div
                    class="bg-green-500 rounded transition-all duration-300"
                    style={"height: #{success_rate}%"}
                  >
                  </div>
                </div>
                <div class="text-green-400 font-bold text-2xl mt-2">{success_rate}%</div>
              </div>
            </div>
          </div>
        </div>
        
    <!-- Right Column: Command + Live Feed + Analytics -->
        <div class="col-span-7 flex flex-col gap-4 h-full min-h-0">
          <!-- Command Line -->
          <div class="border border-green-500 p-3 shadow-lg shadow-green-500/20">
            <div class="flex items-center justify-between mb-2">
              <div class="text-cyan-400">─── COMMAND ───</div>
              <%= if length(@command_suggestions) > 0 do %>
                <div class="flex items-center gap-2 text-xs">
                  <%= for {suggestion, index} <- Enum.with_index(@command_suggestions) do %>
                    <span class={
                      if index == @selected_suggestion_index,
                        do: "text-yellow-400 font-bold",
                        else: "text-gray-500"
                    }>
                      {suggestion}
                    </span>
                    <%= if index < length(@command_suggestions) - 1 do %>
                      <span class="text-gray-700">|</span>
                    <% end %>
                  <% end %>
                  <%= if length(@command_suggestions) > 1 do %>
                    <span class="text-gray-600 text-xs ml-2">(Tab to cycle)</span>
                  <% end %>
                </div>
              <% end %>
            </div>
            <form
              phx-submit="execute_command"
              phx-change="command_input_change"
              class="flex items-center gap-2"
            >
              <span class="text-green-400">></span>
              <input
                id="command-input"
                type="text"
                value={@command_input}
                class="flex-1 bg-black border-0 outline-none text-green-400"
                placeholder="Enter command... (type 'help' or '\?' for commands)"
                phx-hook="CommandInput"
                name="value"
                autocomplete="off"
              />
              <span class="animate-pulse">_</span>
            </form>
            <div class="text-xs text-gray-600 mt-2">
              HOTKEYS: F1-F4 (Actions) | Tab (Autocomplete) | ↑/↓ (History) | ESC (Clear)
            </div>
          </div>
          
    <!-- Live Feed -->
          <div class="border border-green-500 p-3 shadow-lg shadow-green-500/20 flex flex-col flex-1 min-h-0">
            <div class="text-cyan-400 mb-2">─── LIVE FEED ───</div>
            <div class="flex-1 overflow-y-auto space-y-1 text-sm">
              <%= if length(@feed_events) == 0 do %>
                <div class="text-gray-600">
                  [{format_timestamp(@current_time)}] INFO: Waiting for events...
                </div>
              <% end %>

              <%= for event <- @feed_events do %>
                <div class="flex gap-2">
                  <%= case event do %>
                    <% {event_type, item, timestamp} when is_map(item) -> %>
                      <span class="text-gray-500">[{format_timestamp(timestamp)}]</span>
                      <%= case event_type do %>
                        <% :task_started -> %>
                          <span class="text-cyan-400">TASK_START:</span>
                          <span class="text-green-300">{item.heading} started</span>
                        <% :task_completed -> %>
                          <span class="text-green-400">TASK_DONE:</span>
                          <span class="text-green-300">
                            {item.heading} completed in {format_duration_ms(
                              DateTime.diff(item.finished_at, item.started_at, :millisecond)
                            )}
                          </span>
                        <% :task_failed -> %>
                          <span class="text-red-400">TASK_ERROR:</span>
                          <span class="text-red-300">{item.heading} failed</span>
                        <% :stream_started -> %>
                          <span class="text-cyan-400">STREAM_START:</span>
                          <span class="text-cyan-300">
                            {item.heading} started ({item.stream_total} items)
                          </span>
                        <% :stream_completed -> %>
                          <span class="text-green-400">STREAM_DONE:</span>
                          <span class="text-green-300">
                            {item.heading} completed {item.stream_completed} items
                          </span>
                        <% :stream_progress -> %>
                          <span class="text-yellow-400">STREAM_PROGRESS:</span>
                          <span class="text-yellow-300">
                            {item.heading} - {item.stream_completed}/{item.stream_total}
                          </span>
                        <% _ -> %>
                          <span class="text-gray-400">UNKNOWN</span>
                      <% end %>
                    <% {:command_executed, message, timestamp} -> %>
                      <span class="text-gray-500">[{format_timestamp(timestamp)}]</span>
                      <span class="text-yellow-400">COMMAND:</span>
                      <span class="text-yellow-300">{message}</span>
                    <% _ -> %>
                      <span class="text-gray-500">[{format_timestamp(@current_time)}]</span>
                      <span class="text-gray-400">UNKNOWN EVENT</span>
                  <% end %>
                </div>
              <% end %>

              <div class="flex gap-2 animate-pulse">
                <span class="text-gray-500">[{format_timestamp(@current_time)}]</span>
                <span class="text-gray-600">_</span>
              </div>
            </div>
          </div>
        </div>
      </div>
      
    <!-- Status Bar -->
      <div class="border border-green-500 p-2 mt-4 flex justify-between text-xs shadow-lg shadow-green-500/20">
        <div class="flex gap-4">
          <span class="text-green-400">STATUS: ONLINE</span>
          <span class="text-cyan-400">ACTIVE: {@stats.running} tasks/streams</span>
          <span class="text-yellow-400">EVENTS: {length(@feed_events)}</span>
        </div>
        <div class="flex gap-4">
          <span class="text-green-400">
            UPTIME: {format_duration_ms(System.system_time(:millisecond))}
          </span>
        </div>
      </div>
      
    <!-- Help Modal -->
      <%= if @show_help_modal do %>
        <div
          class="fixed inset-0 bg-black/80 flex items-center justify-center z-50"
          phx-click="close_help_modal"
        >
          <div
            class="bg-black border-2 border-green-500 p-6 max-w-5xl max-h-[90vh] overflow-y-auto shadow-2xl shadow-green-500/50"
            phx-click={JS.exec("phx-remove", to: ".modal-backdrop")}
            style="font-family: 'Courier New', monospace;"
          >
            <div class="flex justify-between items-center mb-4 border-b border-green-500 pb-2">
              <h2 class="text-2xl text-green-400 font-bold">
                ▸ AVAILABLE COMMANDS
              </h2>
              <button
                phx-click="close_help_modal"
                class="text-red-400 hover:text-red-300 text-xl font-bold"
              >
                [X]
              </button>
            </div>

            <%= for {category, commands} <- Commands.commands_by_category() do %>
              <div class="mb-6">
                <h3 class="text-cyan-400 font-bold mb-3 text-lg">
                  ═══ {category} ═══
                </h3>
                <div class="space-y-3">
                  <%= for command <- commands do %>
                    <div class="border-l-2 border-green-700 pl-4 py-2">
                      <div class="flex items-start gap-4">
                        <div class="w-48">
                          <div class="text-yellow-400 font-bold">
                            {command.name}
                          </div>
                          <%= if length(command.aliases) > 0 do %>
                            <div class="text-gray-500 text-xs">
                              Aliases: {Enum.join(command.aliases, ", ")}
                            </div>
                          <% end %>
                          <%= if command.keyboard_shortcut do %>
                            <div class="text-cyan-400 text-xs mt-1">
                              [{command.keyboard_shortcut}]
                            </div>
                          <% end %>
                        </div>
                        <div class="flex-1">
                          <div class="text-green-300">
                            {command.description}
                          </div>
                          <div class="text-gray-500 text-sm mt-1">
                            Usage: <span class="text-green-400">{command.usage_example}</span>
                          </div>
                        </div>
                      </div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>

            <div class="border-t border-green-500 pt-4 mt-4">
              <div class="text-gray-400 text-sm">
                <div class="font-bold text-cyan-400 mb-2">TIPS:</div>
                <ul class="list-disc list-inside space-y-1 text-xs">
                  <li>Type '\\?' or 'help' to show this dialog</li>
                  <li>Start typing any command name for autocomplete suggestions</li>
                  <li>Press Tab to cycle through suggestions</li>
                  <li>Use ↑/↓ arrows to navigate command history</li>
                  <li>Press ESC to clear the input field</li>
                  <li>Commands are case-insensitive</li>
                </ul>
              </div>
            </div>

            <div class="text-center mt-4">
              <button
                phx-click="close_help_modal"
                class="px-6 py-2 border border-green-500 text-green-400 hover:bg-green-900/30"
              >
                [CLOSE - ESC]
              </button>
            </div>
          </div>
        </div>
      <% end %>
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

  # Command input handlers

  @impl true
  def handle_event("command_input_change", %{"value" => value}, socket) do
    # Search for matching commands
    suggestions = CommandSearch.search(value)

    {:noreply,
     socket
     |> assign(:command_input, value)
     |> assign(:command_suggestions, suggestions)
     |> assign(:selected_suggestion_index, 0)
     |> assign(:history_index, -1)}
  end

  @impl true
  def handle_event("command_tab", _params, socket) do
    suggestions = socket.assigns.command_suggestions

    if length(suggestions) > 0 do
      # Cycle to next suggestion
      current_index = socket.assigns.selected_suggestion_index
      next_index = rem(current_index + 1, length(suggestions))
      selected_command = Enum.at(suggestions, next_index)

      # Push event to update input value via JS hook
      {:noreply,
       socket
       |> assign(:selected_suggestion_index, next_index)
       |> assign(:command_input, selected_command)
       |> push_event("update_input_value", %{value: selected_command})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("command_arrow_up", _params, socket) do
    history = socket.assigns.command_history

    if length(history) > 0 do
      current_index = socket.assigns.history_index
      next_index = min(current_index + 1, length(history) - 1)
      command = Enum.at(history, next_index)

      {:noreply,
       socket
       |> assign(:history_index, next_index)
       |> assign(:command_input, command)
       |> push_event("update_input_value", %{value: command})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("command_arrow_down", _params, socket) do
    current_index = socket.assigns.history_index

    if current_index > 0 do
      next_index = current_index - 1
      command = Enum.at(socket.assigns.command_history, next_index)

      {:noreply,
       socket
       |> assign(:history_index, next_index)
       |> assign(:command_input, command)
       |> push_event("update_input_value", %{value: command})}
    else
      # Back to empty input
      {:noreply,
       socket
       |> assign(:history_index, -1)
       |> assign(:command_input, "")
       |> push_event("update_input_value", %{value: ""})}
    end
  end

  @impl true
  def handle_event("execute_command", %{"value" => value}, socket) do
    command_text = String.trim(value)

    cond do
      # Empty command
      command_text == "" ->
        {:noreply, socket}

      # Help command - show modal
      CommandSearch.is_help_command?(command_text) ->
        {:noreply, assign(socket, :show_help_modal, true)}

      # Normal command - find and execute
      true ->
        execute_terminal_command(command_text, socket)
    end
  end

  @impl true
  def handle_event("close_help_modal", _params, socket) do
    {:noreply, assign(socket, :show_help_modal, false)}
  end

  defp execute_terminal_command(command_text, socket) do
    # Find the command
    command = Commands.find_command(command_text)

    if command do
      # Add to history
      history = [command_text | socket.assigns.command_history] |> Enum.take(50)

      socket =
        socket
        |> assign(:command_history, history)
        |> assign(:command_input, "")
        |> assign(:command_suggestions, [])
        |> assign(:selected_suggestion_index, 0)
        |> assign(:history_index, -1)
        |> push_event("update_input_value", %{value: ""})

      # Execute the command handler
      execute_command_handler(command.handler, socket)
    else
      # Unknown command
      socket
      |> put_flash(
        :error,
        "Unknown command: #{command_text}. Type 'help' or '\\?' to see available commands."
      )
      |> assign(:command_input, "")
      |> push_event("update_input_value", %{value: ""})
      |> then(&{:noreply, &1})
    end
  end

  defp execute_command_handler(handler, socket) do
    case handler do
      # Quick Actions
      :new_task -> handle_command_new_task(socket)
      :stop_all -> handle_command_stop_all(socket)
      :clear_done -> handle_command_clear_done(socket)
      :export -> handle_command_export(socket)
      # Task/Stream Management
      :list_tasks -> handle_command_list_tasks(socket)
      :list_streams -> handle_command_list_streams(socket)
      :list_all -> handle_command_list_all(socket)
      :stats -> handle_command_stats(socket)
      :refresh -> handle_command_refresh(socket)
      # Navigation
      :navigate_cards -> {:noreply, push_navigate(socket, to: "/dashboard/cards")}
      :navigate_timeline -> {:noreply, push_navigate(socket, to: "/dashboard/timeline")}
      :navigate_terminal -> {:noreply, put_flash(socket, :info, "Already on Terminal view")}
      # View Control
      :filter_running -> handle_command_filter(socket, :running)
      :filter_done -> handle_command_filter(socket, :done)
      :filter_errors -> handle_command_filter(socket, :errors)
      :filter_all -> handle_command_filter(socket, :all)
      # System/Help
      :show_help -> {:noreply, assign(socket, :show_help_modal, true)}
      :show_status -> handle_command_status(socket)
      :clear_feed -> handle_command_clear_feed(socket)
      :prune_feed -> handle_command_prune_feed(socket)
      _ -> {:noreply, put_flash(socket, :error, "Command not implemented yet")}
    end
  end

  # Command handler implementations

  defp handle_command_new_task(socket) do
    # Placeholder - would integrate with a task creation form
    {:noreply,
     socket
     |> put_flash(:info, "New task command executed. Task creation coming soon!")
     |> add_feed_event({:command_executed, "NEW_TASK", DateTime.utc_now()})}
  end

  defp handle_command_stop_all(socket) do
    # Stop all running tasks
    count =
      Enum.count(socket.assigns.tasks, fn task ->
        if task.status == :running do
          Server.discard_task(task.base_encoded_ref)
          true
        else
          false
        end
      end)

    {:noreply,
     socket
     |> put_flash(:info, "Stopped #{count} running task(s)")
     |> add_feed_event(
       {:command_executed, "STOP_ALL: #{count} tasks stopped", DateTime.utc_now()}
     )}
  end

  defp handle_command_clear_done(socket) do
    # Clear all completed tasks and streams
    task_count =
      Enum.count(socket.assigns.tasks, fn task ->
        if task.status == :done do
          Server.discard_task(task.base_encoded_ref)
          true
        else
          false
        end
      end)

    stream_count =
      Enum.count(socket.assigns.overlord_streams, fn stream ->
        if stream.status == :done do
          Server.discard_stream(stream.base_encoded_ref)
          true
        else
          false
        end
      end)

    total = task_count + stream_count

    {:noreply,
     socket
     |> put_flash(:info, "Cleared #{total} completed item(s)")
     |> add_feed_event(
       {:command_executed, "CLEAR_DONE: #{total} items cleared", DateTime.utc_now()}
     )}
  end

  defp handle_command_export(socket) do
    # Placeholder - would generate export file
    {:noreply,
     socket
     |> put_flash(:info, "Export command executed. Export functionality coming soon!")
     |> add_feed_event({:command_executed, "EXPORT", DateTime.utc_now()})}
  end

  defp handle_command_list_tasks(socket) do
    tasks = socket.assigns.tasks
    count = length(tasks)

    {:noreply,
     socket
     |> put_flash(:info, "#{count} task(s) listed in feed")
     |> add_feed_event({:command_executed, "LIST_TASKS: #{count} tasks", DateTime.utc_now()})}
  end

  defp handle_command_list_streams(socket) do
    streams = socket.assigns.overlord_streams
    count = length(streams)

    {:noreply,
     socket
     |> put_flash(:info, "#{count} stream(s) listed in feed")
     |> add_feed_event({:command_executed, "LIST_STREAMS: #{count} streams", DateTime.utc_now()})}
  end

  defp handle_command_list_all(socket) do
    total = length(socket.assigns.tasks) + length(socket.assigns.overlord_streams)

    {:noreply,
     socket
     |> put_flash(:info, "#{total} total item(s) listed in feed")
     |> add_feed_event({:command_executed, "LIST_ALL: #{total} items", DateTime.utc_now()})}
  end

  defp handle_command_stats(socket) do
    stats = socket.assigns.stats

    message =
      "STATS: #{stats.total} total, #{stats.running} running, #{stats.done} done, #{stats.error} errors"

    {:noreply,
     socket
     |> put_flash(:info, message)
     |> add_feed_event({:command_executed, message, DateTime.utc_now()})}
  end

  defp handle_command_refresh(socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Dashboard refreshed")
     |> add_feed_event({:command_executed, "REFRESH", DateTime.utc_now()})}
  end

  defp handle_command_filter(socket, filter) do
    filter_name =
      case filter do
        :running -> "RUNNING"
        :done -> "DONE"
        :errors -> "ERRORS"
        :all -> "ALL"
      end

    {:noreply,
     socket
     |> assign(:active_filter, filter)
     |> put_flash(:info, "Filter set to: #{filter_name}")
     |> add_feed_event({:command_executed, "FILTER: #{filter_name}", DateTime.utc_now()})}
  end

  defp handle_command_status(socket) do
    stats = socket.assigns.stats

    message =
      "STATUS: ONLINE | #{stats.total} tasks | #{stats.running} running | CPU: #{stats.cpu_usage}% | MEM: #{stats.mem_usage}%"

    {:noreply,
     socket
     |> put_flash(:info, message)
     |> add_feed_event({:command_executed, message, DateTime.utc_now()})}
  end

  defp handle_command_clear_feed(socket) do
    {:noreply,
     socket
     |> assign(:feed_events, [])
     |> put_flash(:info, "Live feed cleared")}
  end

  defp handle_command_prune_feed(socket) do
    current_count = length(socket.assigns.feed_events)
    pruned_events = Enum.take(socket.assigns.feed_events, @feed_limit)
    pruned_count = current_count - length(pruned_events)

    {:noreply,
     socket
     |> assign(:feed_events, pruned_events)
     |> put_flash(
       :info,
       "Pruned #{pruned_count} event(s) from feed (kept #{length(pruned_events)}/#{@feed_limit})"
     )
     |> add_feed_event(
       {:command_executed, "PRUNE_FEED: #{pruned_count} events removed", DateTime.utc_now()}
     )}
  end

  defp add_feed_event(socket, event) do
    assign(socket, :feed_events, [event | socket.assigns.feed_events] |> Enum.take(@feed_limit))
  end
end
