defmodule TaskOverlord.Server do
  @moduledoc """
  **Centralized GenServer for real-time task and stream monitoring**

  - Tracks asynchronous tasks and data streams in unified state
  - Broadcasts live updates via Phoenix PubSub to subscribed processes
  - Automatically spawns tasks via Task.Supervisor with error handling
  - Handles task completion, failure, and crash scenarios gracefully
  - Periodically expires and cleans up finished work
  - Provides subscription API for building reactive UIs

  """

  use GenServer

  alias TaskOverlord.OverlordStream
  alias TaskOverlord.OverlordTask

  require Logger

  @topic "task_overlord_server"
  @discard_interval :timer.seconds(1)
  @demo_interval :timer.seconds(10)

  # Client API

  @doc """
  Subscribes the calling process to task/stream updates.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(TaskOverlord.PubSub, @topic)
  end

  @spec subscribe(pid()) :: :ok | {:error, term()}
  def subscribe(pid) do
    Phoenix.PubSub.subscribe(TaskOverlord.PubSub, @topic, pid: pid)
  end

  @doc """
  Starts the server.
  """
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Task operations

  @doc """
  Starts and tracks a task (linked to Server).
  """
  @spec start_task(
          {:function, function()} | {:mfa, module(), atom(), list()},
          String.t(),
          String.t()
        ) :: :ok
  def start_task(func_spec, heading, message) do
    GenServer.call(__MODULE__, {:start_task, func_spec, heading, message})
  end

  @doc """
  Starts and tracks a task (not linked to Server).
  """
  @spec start_task_nolink(
          {:function, function()} | {:mfa, module(), atom(), list()},
          String.t(),
          String.t()
        ) :: :ok
  def start_task_nolink(func_spec, heading, message) do
    GenServer.call(__MODULE__, {:start_task_nolink, func_spec, heading, message})
  end

  @doc """
  Registers a new task in the tracking system (deprecated - use start_task instead).
  """
  @spec register_task(OverlordTask.t()) :: :ok
  def register_task(%OverlordTask{} = task) do
    GenServer.cast(__MODULE__, {:register_task, task})
  end

  @doc """
  Updates an existing task's state.
  """
  @spec update_task(reference(), map()) :: :ok
  def update_task(ref, updates) when is_reference(ref) and is_map(updates) do
    GenServer.cast(__MODULE__, {:update_task, ref, updates})
  end

  @doc """
  Marks a task as complete with a result.
  """
  @spec complete_task(reference(), any()) :: :ok
  def complete_task(ref, result) when is_reference(ref) do
    GenServer.cast(__MODULE__, {:complete_task, ref, result})
  end

  @doc """
  Marks a task as failed with a reason.
  """
  @spec fail_task(reference(), any()) :: :ok
  def fail_task(ref, reason) when is_reference(ref) do
    GenServer.cast(__MODULE__, {:fail_task, ref, reason})
  end

  @doc """
  Removes a task from tracking.
  """
  @spec discard_task(String.t()) :: :ok
  def discard_task(encoded_ref) when is_binary(encoded_ref) do
    GenServer.call(__MODULE__, {:discard_task, encoded_ref})
  end

  @doc """
  Lists all tracked tasks.
  """
  @spec list_tasks() :: %{reference() => OverlordTask.t()}
  def list_tasks do
    GenServer.call(__MODULE__, :list_tasks)
  end

  # Stream operations

  @doc """
  Registers a new stream in the tracking system.
  """
  @spec register_stream(OverlordStream.t()) :: :ok
  def register_stream(%OverlordStream{} = stream) do
    GenServer.cast(__MODULE__, {:register_stream, stream})
  end

  @doc """
  Updates stream progress with a new result.
  """
  @spec stream_item(reference(), {:ok, any()} | {:error, any()}) :: :ok
  def stream_item(ref, result) when is_reference(ref) do
    GenServer.cast(__MODULE__, {:stream_item, ref, result})
  end

  @doc """
  Marks a stream as complete.
  """
  @spec complete_stream(reference()) :: :ok
  def complete_stream(ref) when is_reference(ref) do
    GenServer.cast(__MODULE__, {:stream_complete, ref})
  end

  @doc """
  Removes a stream from tracking.
  """
  @spec discard_stream(String.t()) :: :ok
  def discard_stream(encoded_ref) when is_binary(encoded_ref) do
    GenServer.call(__MODULE__, {:discard_stream, encoded_ref})
  end

  @doc """
  Lists all tracked streams.
  """
  @spec list_streams() :: %{reference() => OverlordStream.t()}
  def list_streams do
    GenServer.call(__MODULE__, :list_streams)
  end

  @doc """
  Lists all tracked tasks and streams.
  """
  @spec list_all() :: %{tasks: map(), streams: map()}
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  # GenServer callbacks

  @impl true
  def init(_) do
    Process.send_after(self(), :discard_outdated, @discard_interval)
    Process.send_after(self(), :create_demo_tasks, @demo_interval)
    {:ok, %{tasks: %{}, streams: %{}}}
  end

  # Task handlers

  @impl true
  def handle_cast({:register_task, task}, %{tasks: tasks} = state) do
    # Don't monitor - Task.Supervisor.async already sets up monitoring
    # The task ref IS the monitor ref, and we'll receive {ref, result} messages
    new_tasks = Map.put(tasks, task.ref, task)
    new_state = %{state | tasks: new_tasks}
    {:noreply, broadcast(new_state)}
  end

  def handle_cast({:update_task, ref, updates}, %{tasks: tasks} = state) do
    case Map.get(tasks, ref) do
      nil ->
        {:noreply, state}

      task ->
        updated_task = Map.merge(task, updates)
        new_tasks = Map.put(tasks, ref, updated_task)
        new_state = %{state | tasks: new_tasks}
        {:noreply, broadcast(new_state)}
    end
  end

  def handle_cast({:complete_task, ref, result}, %{tasks: tasks} = state) do
    case Map.get(tasks, ref) do
      nil ->
        {:noreply, state}

      task ->
        updated_task = %{task | status: :done, result: result, finished_at: DateTime.utc_now()}
        new_tasks = Map.put(tasks, ref, updated_task)
        new_state = %{state | tasks: new_tasks}
        {:noreply, broadcast(new_state)}
    end
  end

  def handle_cast({:fail_task, ref, reason}, %{tasks: tasks} = state) do
    case Map.get(tasks, ref) do
      nil ->
        {:noreply, state}

      task ->
        updated_task = %{task | status: :error, result: reason, finished_at: DateTime.utc_now()}
        new_tasks = Map.put(tasks, ref, updated_task)
        new_state = %{state | tasks: new_tasks}
        {:noreply, broadcast(new_state)}
    end
  end

  # Stream handlers

  def handle_cast({:register_stream, stream}, %{streams: streams} = state) do
    new_streams = Map.put(streams, stream.ref, stream)
    new_state = %{state | streams: new_streams}
    {:noreply, broadcast(new_state)}
  end

  def handle_cast({:stream_item, _ref, {:error, reason}}, state) do
    Logger.error("#{__MODULE__} - Stream error: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_cast({:stream_item, ref, result}, %{streams: streams} = state) do
    case Map.get(streams, ref) do
      nil ->
        {:noreply, state}

      stream ->
        updated_stream =
          stream
          |> Map.update!(:stream_results, &(&1 ++ [result]))
          |> Map.update!(:stream_completed, &(&1 + 1))

        new_streams = Map.put(streams, ref, updated_stream)
        new_state = %{state | streams: new_streams}
        {:noreply, broadcast(new_state)}
    end
  end

  def handle_cast({:stream_complete, ref}, %{streams: streams} = state) do
    case Map.get(streams, ref) do
      nil ->
        {:noreply, state}

      stream ->
        updated_stream = %{stream | status: :done, finished_at: DateTime.utc_now()}
        new_streams = Map.put(streams, ref, updated_stream)
        new_state = %{state | streams: new_streams}
        {:noreply, broadcast(new_state)}
    end
  end

  # Call handlers

  @impl true
  def handle_call({:start_task, func_spec, heading, message}, _from, %{tasks: tasks} = state) do
    # Wrap the function to catch errors and report them
    wrapped_func = fn ->
      try do
        result =
          case func_spec do
            {:function, func} -> func.()
            {:mfa, module, func, args} -> apply(module, func, args)
          end

        {:ok, result}
      rescue
        e ->
          {:error, {e, __STACKTRACE__}}
      catch
        kind, reason ->
          {:error, {kind, reason, __STACKTRACE__}}
      end
    end

    task = Task.Supervisor.async(TaskOverlord.TaskSupervisor, wrapped_func)
    task_struct = OverlordTask.new(task, heading, message)
    new_tasks = Map.put(tasks, task.ref, task_struct)
    new_state = %{state | tasks: new_tasks}
    {:reply, :ok, broadcast(new_state)}
  end

  def handle_call(
        {:start_task_nolink, func_spec, heading, message},
        _from,
        %{tasks: tasks} = state
      ) do
    # Wrap the function to catch errors and report them
    wrapped_func = fn ->
      try do
        result =
          case func_spec do
            {:function, func} -> func.()
            {:mfa, module, func, args} -> apply(module, func, args)
          end

        {:ok, result}
      rescue
        e ->
          {:error, {e, __STACKTRACE__}}
      catch
        kind, reason ->
          {:error, {kind, reason, __STACKTRACE__}}
      end
    end

    task = Task.Supervisor.async_nolink(TaskOverlord.TaskSupervisor, wrapped_func)
    task_struct = OverlordTask.new(task, heading, message)
    new_tasks = Map.put(tasks, task.ref, task_struct)
    new_state = %{state | tasks: new_tasks}
    {:reply, :ok, broadcast(new_state)}
  end

  def handle_call(:list_tasks, _from, %{tasks: tasks} = state) do
    {:reply, tasks, state}
  end

  def handle_call(:list_streams, _from, %{streams: streams} = state) do
    {:reply, streams, state}
  end

  def handle_call(:list_all, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:discard_task, encoded_ref}, _from, %{tasks: tasks} = state) do
    ref = decode_ref(encoded_ref)
    updated_tasks = Map.delete(tasks, ref)
    updated_state = %{state | tasks: updated_tasks}
    {:reply, :ok, broadcast(updated_state)}
  end

  def handle_call({:discard_stream, encoded_ref}, _from, %{streams: streams} = state) do
    ref = decode_ref(encoded_ref)
    updated_streams = Map.delete(streams, ref)
    updated_state = %{state | streams: updated_streams}
    {:reply, :ok, broadcast(updated_state)}
  end

  # Info handlers

  @impl true
  def handle_info(:discard_outdated, %{tasks: tasks, streams: streams} = state) do
    updated_tasks =
      tasks
      |> Enum.reject(fn {_id, task} -> OverlordTask.expired?(task) end)
      |> Map.new()

    updated_streams =
      streams
      |> Enum.reject(fn {_id, stream} -> OverlordStream.expired?(stream) end)
      |> Map.new()

    updated_state = %{state | tasks: updated_tasks, streams: updated_streams}
    Process.send_after(self(), :discard_outdated, @discard_interval)

    {:noreply, broadcast(updated_state)}
  end

  # Handle task completion from Task.Supervisor
  def handle_info({ref, result}, %{tasks: tasks} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])

    case Map.get(tasks, ref) do
      nil ->
        Logger.warning(
          "#{__MODULE__} - Received completion for unknown task ref: #{inspect(ref)}"
        )

        {:noreply, state}

      task ->
        # Check if the result indicates an error (from our wrapper)
        case result do
          {:ok, actual_result} ->
            updated_task = %{
              task
              | status: :done,
                result: actual_result,
                finished_at: DateTime.utc_now()
            }

            new_tasks = Map.put(tasks, ref, updated_task)
            new_state = %{state | tasks: new_tasks}
            {:noreply, broadcast(new_state)}

          {:error, error_info} ->
            Logger.error(
              "#{__MODULE__} - Task failed: #{inspect(task.heading)}, error: #{inspect(error_info)}"
            )

            updated_task = %{
              task
              | status: :error,
                result: error_info,
                finished_at: DateTime.utc_now()
            }

            new_tasks = Map.put(tasks, ref, updated_task)
            new_state = %{state | tasks: new_tasks}
            {:noreply, broadcast(new_state)}
        end
    end
  end

  # Handle task failure from Task.Supervisor
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{tasks: tasks} = state)
      when is_reference(ref) do
    case Map.get(tasks, ref) do
      nil ->
        Logger.warning("#{__MODULE__} - Received DOWN for unknown task ref: #{inspect(ref)}")
        {:noreply, state}

      task ->
        Logger.error(
          "#{__MODULE__} - Task crashed: #{inspect(task.heading)}, reason: #{inspect(reason)}"
        )

        updated_task = %{task | status: :error, result: reason, finished_at: DateTime.utc_now()}
        new_tasks = Map.put(tasks, ref, updated_task)
        new_state = %{state | tasks: new_tasks}
        {:noreply, broadcast(new_state)}
    end
  end

  # Demo task generator
  def handle_info(:create_demo_tasks, state) do
    # Create a demo task
    task_types = [
      "Data Processing",
      "API Call",
      "File Upload",
      "Report Generation",
      "Email Sending"
    ]

    task_type = Enum.random(task_types)

    # Create task function with error handling wrapper
    wrapped_func = fn ->
      try do
        # Random sleep between 2-8 seconds
        sleep_time = Enum.random(2000..8000)
        Process.sleep(sleep_time)

        # 80% success rate
        result =
          if :rand.uniform() < 0.8 do
            "Task completed successfully in #{sleep_time}ms"
          else
            raise "Random error occurred"
          end

        {:ok, result}
      rescue
        e ->
          {:error, {e, __STACKTRACE__}}
      catch
        kind, reason ->
          {:error, {kind, reason, __STACKTRACE__}}
      end
    end

    # Start the task directly
    task = Task.Supervisor.async_nolink(TaskOverlord.TaskSupervisor, wrapped_func)
    task_struct = OverlordTask.new(task, task_type, "Processing #{Enum.random(100..999)} items")
    new_tasks = Map.put(state.tasks, task.ref, task_struct)

    # Create a demo stream
    stream_ref = make_ref()
    stream_total = 5

    stream = %OverlordStream{
      ref: stream_ref,
      base_encoded_ref: OverlordStream.base_encode_ref(stream_ref),
      mfa: {__MODULE__, :demo_stream, []},
      status: :streaming,
      heading: "Data Stream",
      message: "Streaming #{stream_total} records",
      stream_completed: 0,
      stream_total: stream_total,
      stream_results: [],
      logs: [],
      started_at: DateTime.utc_now(),
      finished_at: nil,
      expires_at_unix:
        DateTime.utc_now() |> DateTime.add(:timer.minutes(5), :millisecond) |> DateTime.to_unix()
    }

    # Add stream to state
    new_streams = Map.put(state.streams, stream_ref, stream)

    updated_state = %{state | tasks: new_tasks, streams: new_streams}

    # Start a supervised task to simulate stream items
    Task.Supervisor.start_child(TaskOverlord.TaskSupervisor, fn ->
      Enum.each(1..stream_total, fn i ->
        Process.sleep(Enum.random(500..1500))
        stream_item(stream_ref, {:ok, "Item #{i}"})
      end)

      complete_stream(stream_ref)
    end)

    # Schedule next demo
    Process.send_after(self(), :create_demo_tasks, @demo_interval)

    {:noreply, broadcast(updated_state)}
  end

  # Catch-all for debugging unhandled messages
  def handle_info(msg, state) do
    Logger.warning("#{__MODULE__} - Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private helpers

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(TaskOverlord.PubSub, @topic, {:updated, state})
    state
  end

  defp decode_ref(encoded_ref) do
    encoded_ref |> Base.url_decode64!(padding: false) |> :erlang.binary_to_term()
  end
end
