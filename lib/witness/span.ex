defmodule Witness.Span do
  @moduledoc "Represents a `Witness.Tracker` span."
  alias Witness

  @type id :: reference
  @type context :: Witness.t()
  @type event_name :: Witness.event_name()
  @type status_code :: :unknown | :ok | :error
  @type status_details :: term

  @type t :: t(term)
  @type t(result) :: %__MODULE__{
          id: id,
          context: context,
          event_name: event_name,
          meta: map,
          status: :unknown | {:ok | :error, status_details},
          result: result
        }
  @enforce_keys [:id, :context, :event_name]
  defstruct id: nil,
            context: nil,
            event_name: nil,
            meta: %{},
            status: :unknown,
            result: nil

  @doc false
  @spec new(context, event_name, attributes :: map | keyword) :: t
  def new(context, event_name, attributes \\ %{}) do
    defaults = %{
      id: make_ref()
    }

    attributes =
      attributes
      |> Enum.into(defaults)
      |> Map.put(:context, context)
      |> Map.put(:event_name, event_name)

    struct!(__MODULE__, attributes)
  end

  module = inspect(__MODULE__)

  new_span = fn attributes ->
    base = "MyObservabilityContext, [:my, :event]"

    if Enum.empty?(attributes) do
      "new(#{base})"
    else
      "new(#{base}, #{inspect(attributes)})"
    end
  end

  base_span = new_span.([])

  @doc """
  Merges the given meta with the meta in the spec.

  ## Examples

      iex> span = #{base_span}
      iex> with_meta(span, my: "meta")
      %#{module}{span |
        meta: %{my: "meta"}
      }

      iex> span = #{new_span.(meta: %{my: "meta"})}
      iex> with_meta(span, more: "meta")
      %#{module}{span |
        meta: %{my: "meta", more: "meta"}
      }

      iex> span = #{new_span.(meta: %{my: "meta"})}
      iex> with_meta(span, my: "new meta", more: "meta")
      %#{module}{span |
        meta: %{my: "new meta", more: "meta"}
      }
  """
  @spec with_meta(t, meta :: Witness.meta()) :: t
  def with_meta(%__MODULE__{} = span, meta) do
    %{span | meta: Enum.into(meta, span.meta || %{})}
  end

  @doc """
  Puts the given result at `:result` and - if it's status is still `:unknown` uses
  it to set it's own `:status` through `status_of/1`.

  ## Examples

      iex> span = #{base_span}
      iex> with_result(span, "some random value")
      %#{module}{span |
        status: :unknown,
        result: "some random value"
      }

      iex> span = #{new_span.(status: {:ok, "some message"})}
      iex> with_result(span, :ok)
      %#{module}{span |
        status: {:ok, "some message"},
        result: :ok
      }

      iex> span = #{base_span}
      iex> with_result(span, :ok)
      %#{module}{span |
        status: {:ok, nil},
        result: :ok
      }

      iex> span = #{base_span}
      iex> with_result(span, {:ok, "value"})
      %#{module}{span |
        status: {:ok, nil},
        result: {:ok, "value"}
      }

      iex> span = #{base_span}
      iex> with_result(span, {:ok, "some", "value"})
      %#{module}{span |
        status: {:ok, nil},
        result: {:ok, "some", "value"}
      }

      iex> span = #{base_span}
      iex> with_result(span, :error)
      %#{module}{span |
        status: {:error, nil},
        result: :error
      }

      iex> span = #{base_span}
      iex> with_result(span, {:error, :some_reason})
      %#{module}{span |
        status: {:error, :some_reason},
        result: {:error, :some_reason}
      }

      iex> span = #{base_span}
      iex> with_result(span, {:error, :some, :detailed_reason})
      %#{module}{span |
        status: {:error, {:some, :detailed_reason}},
        result: {:error, :some, :detailed_reason}
      }

      iex> span = #{base_span}
      iex> with_result(span, {:error, :some, :detailed_reason})
      %#{module}{span |
        status: {:error, {:some, :detailed_reason}},
        result: {:error, :some, :detailed_reason}
      }
  """
  @spec with_result(t, result :: term) :: t
  def with_result(%__MODULE__{status: :unknown} = span, result) do
    %{span | result: result, status: status_of(result)}
  end

  def with_result(%__MODULE__{} = span, result) do
    %{span | result: result}
  end

  @doc """
  Sets the given status and optional message on the span.

  ## Examples

      iex> span = #{base_span}
      iex> with_status(span, :ok)
      %#{module}{span |
        status: {:ok, nil}
      }

      iex> span = #{base_span}
      iex> with_status(span, :ok, "my message")
      %#{module}{span |
        status: {:ok, "my message"}
      }

      iex> span = #{base_span}
      iex> with_status(span, :error)
      %#{module}{span |
        status: {:error, nil}
      }

      iex> span = #{base_span}
      iex> with_status(span, :error, :some_details)
      %#{module}{span |
        status: {:error, :some_details}
      }

      iex> span = #{base_span}
      iex> with_status(span, :unknown)
      %#{module}{span |
        status: :unknown
      }

      iex> span = #{base_span}
      iex> with_status(span, :unknown, "some details")
      %#{module}{span |
        status: :unknown
      }
  """
  @spec with_status(t, status_code, status_details) :: t
  def with_status(span, status, details \\ nil)

  def with_status(%__MODULE__{} = span, :unknown, _details) do
    %{span | status: :unknown}
  end

  def with_status(%__MODULE__{} = span, ok_or_error, details) when ok_or_error in [:ok, :error] do
    %{span | status: {ok_or_error, details}}
  end

  # Dialyzer ignores handle overlapping contracts, the last spec `status_of(term)`
  # also includes the previous two and that's what dialyzer means.
  # Since this should never lead to false positives but is helpful documentation we're ignoring that warning.
  @dialyzer {:no_contracts, status_of: 1}
  @spec status_of(:ok | {:ok, term} | {:ok, term, term}) :: {:ok, nil}
  @spec status_of(:error) :: {:error, nil}
  @spec status_of({:error, reason}) :: {:error, reason} when reason: term
  @spec status_of({:error, reason, details}) :: {:error, {reason, details}} when reason: term, details: term
  @spec status_of(term) :: :unknown
  def status_of(:ok), do: {:ok, nil}
  def status_of({:ok, _}), do: {:ok, nil}
  def status_of({:ok, _, _}), do: {:ok, nil}
  def status_of(:error), do: {:error, nil}
  def status_of({:error, reason}), do: {:error, reason}
  def status_of({:error, reason, details}), do: {:error, {reason, details}}
  def status_of(_), do: :unknown
end
