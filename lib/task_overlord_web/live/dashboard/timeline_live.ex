defmodule TaskOverlordWeb.Dashboard.TimelineLive do
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
     |> assign(:filter, :all)
     |> assign_grouped_items()}
  end

  @impl true
  def handle_info({:updated, state}, socket) do
    {:noreply,
     socket
     |> assign(:tasks, state.tasks |> Map.values())
     |> assign(:overlord_streams, state.streams |> Map.values())
     |> assign_grouped_items()}
  end

  defp assign_grouped_items(socket) do
    all_items =
      (Enum.map(socket.assigns.tasks, &{:task, &1}) ++
         Enum.map(socket.assigns.overlord_streams, &{:stream, &1}))
      |> filter_by_status(socket.assigns.filter)
      |> Enum.sort_by(fn {_, item} -> item.started_at end, {:desc, DateTime})

    now = DateTime.utc_now()

    {active, past_hour, completed} =
      Enum.reduce(all_items, {[], [], []}, fn item, {active, past_hour, completed} ->
        {_type, data} = item
        status = data.status

        cond do
          status in [:running, :streaming] ->
            {[item | active], past_hour, completed}

          not is_nil(data.finished_at) and
              DateTime.diff(now, data.finished_at, :second) < 3600 ->
            {active, [item | past_hour], completed}

          true ->
            {active, past_hour, [item | completed]}
        end
      end)

    socket
    |> assign(:active_items, Enum.reverse(active))
    |> assign(:past_hour_items, Enum.reverse(past_hour))
    |> assign(:completed_items, Enum.reverse(completed))
  end

  defp filter_by_status(items, :all), do: items

  defp filter_by_status(items, filter) do
    Enum.filter(items, fn {_type, item} ->
      case filter do
        :running -> item.status in [:running, :streaming]
        :done -> item.status == :done
        :error -> item.status == :error
        _ -> true
      end
    end)
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

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp status_class(:running), do: "timeline-warning"
  defp status_class(:streaming), do: "timeline-warning"
  defp status_class(:done), do: "timeline-success"
  defp status_class(:error), do: "timeline-error"

  defp status_icon(:running), do: "hero-arrow-path"
  defp status_icon(:streaming), do: "hero-arrow-path"
  defp status_icon(:done), do: "hero-check-circle"
  defp status_icon(:error), do: "hero-x-circle"

  defp status_display(:running), do: "Running"
  defp status_display(:streaming), do: "Streaming"
  defp status_display(:done), do: "Done"
  defp status_display(:error), do: "Error"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 p-6">
      <div class="max-w-5xl mx-auto space-y-6">
        <!-- Header -->
        <div class="flex justify-between items-center">
          <h1 class="text-4xl font-bold">Task Monitor - Timeline</h1>
          <div class="flex gap-2">
            <.link navigate="/dashboard/cards" class="btn btn-ghost">Cards</.link>
            <.link navigate="/dashboard/terminal" class="btn btn-ghost">Terminal</.link>
          </div>
        </div>

        <!-- Filter Tabs -->
        <div class="tabs tabs-boxed bg-base-100 shadow">
          <button
            phx-click="filter"
            phx-value-status="all"
            class={"tab #{if @filter == :all, do: "tab-active"}"}
          >
            All
          </button>
          <button
            phx-click="filter"
            phx-value-status="running"
            class={"tab #{if @filter == :running, do: "tab-active"}"}
          >
            Running
          </button>
          <button
            phx-click="filter"
            phx-value-status="done"
            class={"tab #{if @filter == :done, do: "tab-active"}"}
          >
            Done
          </button>
          <button
            phx-click="filter"
            phx-value-status="error"
            class={"tab #{if @filter == :error, do: "tab-active"}"}
          >
            Errors
          </button>
        </div>

        <!-- Active Tasks Section -->
        <%= if length(@active_items) > 0 do %>
          <div class="bg-base-100 rounded-lg shadow-xl p-6">
            <h2 class="text-2xl font-bold mb-6 flex items-center gap-2">
              <span class="loading loading-spinner loading-sm text-warning"></span>
              Active Now
            </h2>
            <ul class="timeline timeline-vertical timeline-snap-icon">
              <%= for {type, item} <- @active_items do %>
                <li class={status_class(item.status)}>
                  <div class="timeline-middle">
                    <.icon name={status_icon(item.status)} class="w-5 h-5" />
                  </div>
                  <div class="timeline-start mb-10">
                    <time class="font-mono text-sm"><%= format_timestamp(item.started_at) %></time>
                  </div>
                  <div class="timeline-end mb-10">
                    <div class="card bg-base-200 shadow">
                      <div class="card-body p-4">
                        <div class="flex justify-between items-start gap-2">
                          <div class="flex-1">
                            <div class="font-bold text-lg"><%= item.heading %></div>
                            <div class="text-sm text-base-content/70"><%= item.message %></div>
                          </div>
                          <div class="flex flex-col items-end gap-1">
                            <span class="badge badge-sm badge-warning">
                              <%= status_display(item.status) %>
                            </span>
                            <span class="text-xs font-mono">
                              <%= format_duration(item.started_at, item.finished_at) %>
                            </span>
                          </div>
                        </div>

                        <%= if type == :stream do %>
                          <div class="mt-3">
                            <div class="flex justify-between text-xs mb-1">
                              <span>Progress</span>
                              <span class="font-mono">
                                <%= item.stream_completed %>/<%= item.stream_total %>
                              </span>
                            </div>
                            <progress
                              class="progress progress-primary w-full"
                              value={item.stream_completed}
                              max={item.stream_total}
                            >
                            </progress>
                          </div>
                        <% end %>

                        <%= if length(item.logs) > 0 do %>
                          <div class="collapse collapse-arrow bg-base-100 mt-2">
                            <input type="checkbox" />
                            <div class="collapse-title text-xs font-medium px-2 py-1 min-h-0">
                              Logs (<%= length(item.logs) %>)
                            </div>
                            <div class="collapse-content px-2">
                              <div class="space-y-1">
                                <%= for {level, log} <- item.logs do %>
                                  <div class="text-xs">
                                    <span class="badge badge-xs"><%= level %></span>
                                    <span class="ml-2"><%= log %></span>
                                  </div>
                                <% end %>
                              </div>
                            </div>
                          </div>
                        <% end %>

                        <div class="card-actions justify-end mt-2">
                          <button
                            phx-click={if type == :task, do: "discard_task", else: "discard_stream"}
                            phx-value-ref={item.base_encoded_ref}
                            class="btn btn-xs btn-ghost"
                          >
                            Discard
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                  <hr class="bg-base-300" />
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <!-- Past Hour Section -->
        <%= if length(@past_hour_items) > 0 do %>
          <div class="bg-base-100 rounded-lg shadow-xl p-6">
            <h2 class="text-2xl font-bold mb-6">Last Hour</h2>
            <ul class="timeline timeline-vertical timeline-snap-icon">
              <%= for {type, item} <- @past_hour_items do %>
                <li class={status_class(item.status)}>
                  <div class="timeline-middle">
                    <.icon name={status_icon(item.status)} class="w-5 h-5" />
                  </div>
                  <div class="timeline-start mb-10">
                    <time class="font-mono text-sm"><%= format_timestamp(item.started_at) %></time>
                  </div>
                  <div class="timeline-end mb-10">
                    <div class="card bg-base-200 shadow">
                      <div class="card-body p-4">
                        <div class="flex justify-between items-start gap-2">
                          <div class="flex-1">
                            <div class="font-bold"><%= item.heading %></div>
                            <div class="text-sm text-base-content/70"><%= item.message %></div>
                          </div>
                          <div class="flex flex-col items-end gap-1">
                            <span class={"badge badge-sm #{if item.status == :done, do: "badge-success", else: "badge-error"}"}>
                              <%= status_display(item.status) %>
                            </span>
                            <span class="text-xs font-mono">
                              <%= format_duration(item.started_at, item.finished_at) %>
                            </span>
                          </div>
                        </div>

                        <%= if type == :stream do %>
                          <div class="mt-2 text-xs">
                            <span class="font-mono">
                              <%= item.stream_completed %>/<%= item.stream_total %> items
                            </span>
                          </div>
                        <% end %>

                        <%= if type == :task && item.status == :error && item.result do %>
                          <div class="alert alert-error mt-2 py-2">
                            <div class="text-xs font-mono"><%= inspect(item.result) %></div>
                          </div>
                        <% end %>

                        <%= if type == :task && item.status == :done && item.result do %>
                          <div class="collapse collapse-arrow bg-base-100 mt-2">
                            <input type="checkbox" />
                            <div class="collapse-title text-xs font-medium px-2 py-1 min-h-0">
                              Result
                            </div>
                            <div class="collapse-content px-2">
                              <pre class="text-xs overflow-auto"><%= inspect(item.result, pretty: true) %></pre>
                            </div>
                          </div>
                        <% end %>

                        <%= if type == :stream && item.status == :done && length(item.stream_results) > 0 do %>
                          <div class="collapse collapse-arrow bg-base-100 mt-2">
                            <input type="checkbox" />
                            <div class="collapse-title text-xs font-medium px-2 py-1 min-h-0">
                              Results (<%= length(item.stream_results) %>)
                            </div>
                            <div class="collapse-content px-2">
                              <pre class="text-xs overflow-auto"><%= inspect(item.stream_results, pretty: true) %></pre>
                            </div>
                          </div>
                        <% end %>

                        <div class="card-actions justify-end mt-2">
                          <button
                            phx-click={if type == :task, do: "discard_task", else: "discard_stream"}
                            phx-value-ref={item.base_encoded_ref}
                            class="btn btn-xs btn-ghost"
                          >
                            Discard
                          </button>
                        </div>
                      </div>
                    </div>
                  </div>
                  <hr class="bg-base-300" />
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <!-- Completed Section -->
        <%= if length(@completed_items) > 0 do %>
          <div class="bg-base-100 rounded-lg shadow-xl p-6">
            <h2 class="text-2xl font-bold mb-6">Completed Earlier</h2>
            <ul class="timeline timeline-vertical timeline-compact">
              <%= for {type, item} <- @completed_items do %>
                <li class={status_class(item.status)}>
                  <div class="timeline-middle">
                    <.icon name={status_icon(item.status)} class="w-4 h-4" />
                  </div>
                  <div class="timeline-start mb-6">
                    <time class="font-mono text-xs"><%= format_timestamp(item.started_at) %></time>
                  </div>
                  <div class="timeline-end mb-6">
                    <div class="text-sm">
                      <span class="font-bold"><%= item.heading %></span>
                      <span class="mx-2">·</span>
                      <span class={"badge badge-xs #{if item.status == :done, do: "badge-success", else: "badge-error"}"}>
                        <%= status_display(item.status) %>
                      </span>
                      <span class="mx-2">·</span>
                      <span class="font-mono text-xs"><%= format_duration(item.started_at, item.finished_at) %></span>
                      <button
                        phx-click={if type == :task, do: "discard_task", else: "discard_stream"}
                        phx-value-ref={item.base_encoded_ref}
                        class="btn btn-xs btn-ghost ml-2"
                      >
                        ×
                      </button>
                    </div>
                  </div>
                  <hr class="bg-base-300" />
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <%= if length(@active_items) == 0 and length(@past_hour_items) == 0 and length(@completed_items) == 0 do %>
          <div class="hero bg-base-100 rounded-lg shadow-xl py-20">
            <div class="hero-content text-center">
              <div class="max-w-md">
                <h2 class="text-3xl font-bold">No tasks to display</h2>
                <p class="py-6">
                  <%= if @filter == :all do %>
                    Start a task to see it appear here in real-time.
                  <% else %>
                    No tasks match the current filter.
                  <% end %>
                </p>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    filter = String.to_existing_atom(status)

    {:noreply,
     socket
     |> assign(:filter, filter)
     |> assign_grouped_items()}
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
