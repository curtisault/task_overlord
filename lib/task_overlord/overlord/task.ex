defmodule TaskOverlord.OverlordTask do
  @moduledoc """
  Represents a tracked task in the TaskOverlord system.

  This struct contains all the information needed to track a single task's
  execution, including its status, result, timing, and metadata.
  """

  defstruct [
    :pid,
    :ref,
    :base_encoded_ref,
    :mfa,
    :status,
    :heading,
    :message,
    :result,
    :logs,
    :started_at,
    :finished_at,
    :expires_at_unix
  ]

  @type status() :: :running | :done | :error
  @type t() :: %__MODULE__{
          pid: pid() | nil,
          ref: reference(),
          base_encoded_ref: String.t(),
          mfa: mfa(),
          status: status(),
          heading: module() | String.t(),
          message: String.t(),
          result: any() | nil,
          logs: [{Logger.level(), String.t()}],
          started_at: DateTime.t(),
          finished_at: DateTime.t() | nil,
          expires_at_unix: integer()
        }

  @doc """
  Creates a new OverlordTask from a Task struct.
  """
  @spec new(Task.t(), module() | String.t(), String.t()) :: t()
  def new(%Task{} = beam_task, heading, message) do
    %__MODULE__{
      pid: beam_task.pid,
      ref: beam_task.ref,
      base_encoded_ref: base_encode_ref(beam_task.ref),
      mfa: beam_task.mfa,
      status: :running,
      heading: heading,
      message: message,
      result: nil,
      logs: [],
      started_at: DateTime.utc_now(),
      finished_at: nil,
      expires_at_unix: default_expiration()
    }
  end

  @doc """
  Checks if a task has expired based on its expiration timestamp.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{} = task) do
    DateTime.to_unix(DateTime.utc_now()) > task.expires_at_unix
  end

  defp base_encode_ref(ref) do
    ref |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)
  end

  defp default_expiration do
    DateTime.utc_now() |> DateTime.add(:timer.minutes(5), :millisecond) |> DateTime.to_unix()
  end
end
