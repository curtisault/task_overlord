defmodule TaskOverlordWeb.Dashboard.HomeLive do
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
     |> assign_stats()}
  end

  @impl true
  def handle_info({:updated, state}, socket) do
    {:noreply,
     socket
     |> assign(:tasks, state.tasks |> Map.values())
     |> assign(:overlord_streams, state.streams |> Map.values())
     |> assign_stats()}
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

    socket
    |> assign(:stats, %{
      total: total,
      running: running,
      done: done,
      error: error
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 p-8">
      <div class="max-w-7xl mx-auto">
        <!-- Header -->
        <div class="text-center mb-12">
          <h1 class="text-5xl font-bold mb-4">Task Overlord</h1>
          <p class="text-xl text-base-content/70">Monitor and manage your tasks with ease</p>
        </div>
        
    <!-- Stats Overview -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-12">
          <div class="stat bg-base-100 shadow-xl rounded-lg">
            <div class="stat-figure text-primary">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                class="inline-block w-8 h-8 stroke-current"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
                >
                </path>
              </svg>
            </div>
            <div class="stat-title">Total Tasks</div>
            <div class="stat-value text-primary">{@stats.total}</div>
          </div>

          <div class="stat bg-base-100 shadow-xl rounded-lg">
            <div class="stat-figure text-warning">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                class="inline-block w-8 h-8 stroke-current"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M13 10V3L4 14h7v7l9-11h-7z"
                >
                </path>
              </svg>
            </div>
            <div class="stat-title">Running</div>
            <div class="stat-value text-warning">{@stats.running}</div>
          </div>

          <div class="stat bg-base-100 shadow-xl rounded-lg">
            <div class="stat-figure text-success">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                class="inline-block w-8 h-8 stroke-current"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M5 13l4 4L19 7"
                >
                </path>
              </svg>
            </div>
            <div class="stat-title">Completed</div>
            <div class="stat-value text-success">{@stats.done}</div>
          </div>

          <div class="stat bg-base-100 shadow-xl rounded-lg">
            <div class="stat-figure text-error">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                class="inline-block w-8 h-8 stroke-current"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M6 18L18 6M6 6l12 12"
                >
                </path>
              </svg>
            </div>
            <div class="stat-title">Errors</div>
            <div class="stat-value text-error">{@stats.error}</div>
          </div>
        </div>
        
    <!-- Dashboard Links -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
          <!-- Cards View -->
          <.link
            navigate="/dashboard/cards"
            class="card bg-base-100 shadow-xl hover:shadow-2xl transition-all hover:-translate-y-1"
          >
            <div class="card-body items-center text-center">
              <div class="avatar placeholder mb-4">
                <div class="bg-primary text-primary-content rounded-full w-20">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    class="inline-block w-10 h-10 stroke-current"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z"
                    >
                    </path>
                  </svg>
                </div>
              </div>
              <h2 class="card-title text-2xl">Cards View</h2>
              <p class="text-base-content/70">View tasks organized in cards by status</p>
              <div class="card-actions">
                <button class="btn btn-primary">Open Cards</button>
              </div>
            </div>
          </.link>
          
    <!-- Timeline View -->
          <.link
            navigate="/dashboard/timeline"
            class="card bg-base-100 shadow-xl hover:shadow-2xl transition-all hover:-translate-y-1"
          >
            <div class="card-body items-center text-center">
              <div class="avatar placeholder mb-4">
                <div class="bg-secondary text-secondary-content rounded-full w-20">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    class="inline-block w-10 h-10 stroke-current"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                    >
                    </path>
                  </svg>
                </div>
              </div>
              <h2 class="card-title text-2xl">Timeline View</h2>
              <p class="text-base-content/70">See tasks in chronological order</p>
              <div class="card-actions">
                <button class="btn btn-secondary">Open Timeline</button>
              </div>
            </div>
          </.link>
          
    <!-- Terminal View -->
          <.link
            navigate="/dashboard/terminal"
            class="card bg-base-100 shadow-xl hover:shadow-2xl transition-all hover:-translate-y-1"
          >
            <div class="card-body items-center text-center">
              <div class="avatar placeholder mb-4">
                <div class="bg-accent text-accent-content rounded-full w-20">
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    class="inline-block w-10 h-10 stroke-current"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z"
                    >
                    </path>
                  </svg>
                </div>
              </div>
              <h2 class="card-title text-2xl">Terminal View</h2>
              <p class="text-base-content/70">Command-line style monitoring interface</p>
              <div class="card-actions">
                <button class="btn btn-accent">Open Terminal</button>
              </div>
            </div>
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
