defmodule TaskOverlord.OverlordStream do
  @moduledoc """
  Represents a tracked stream operation in the TaskOverlord system.

  This struct contains all the information needed to track a stream's
  execution progress, including completion count, results, and metadata.
  """

  defstruct [
    :ref,
    :base_encoded_ref,
    :mfa,
    :status,
    :heading,
    :message,
    :stream_completed,
    :stream_total,
    :stream_results,
    :logs,
    :started_at,
    :finished_at,
    :expires_at_unix
  ]

  @type status() :: :streaming | :done | :error
  @type t() :: %__MODULE__{
          ref: reference(),
          base_encoded_ref: String.t(),
          mfa: mfa(),
          status: status(),
          heading: module() | String.t(),
          message: String.t(),
          stream_completed: non_neg_integer(),
          stream_total: non_neg_integer(),
          stream_results: [any()],
          logs: [{Logger.level(), String.t()}],
          started_at: DateTime.t(),
          finished_at: DateTime.t() | nil,
          expires_at_unix: integer()
        }

  @doc """
  Creates a new OverlordStream from an enumerable and MFA tuple.
  """
  @spec new(Enumerable.t(), mfa(), module() | String.t(), String.t()) :: t()
  def new(enumerable, mfa, heading, message) do
    stream_id = make_ref()

    %__MODULE__{
      ref: stream_id,
      base_encoded_ref: base_encode_ref(stream_id),
      mfa: mfa,
      status: :streaming,
      heading: heading,
      message: message,
      stream_completed: 0,
      stream_total: Enum.count(enumerable),
      stream_results: [],
      logs: [],
      started_at: DateTime.utc_now(),
      finished_at: nil,
      expires_at_unix: default_expiration()
    }
  end

  @doc """
  Checks if a stream has expired based on its expiration timestamp.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{} = stream) do
    DateTime.to_unix(DateTime.utc_now()) > stream.expires_at_unix
  end

  def base_encode_ref(ref) do
    ref |> :erlang.term_to_binary() |> Base.url_encode64(padding: false)
  end

  defp default_expiration do
    DateTime.utc_now() |> DateTime.add(:timer.minutes(5), :millisecond) |> DateTime.to_unix()
  end
end
