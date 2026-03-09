defmodule Witness.Code do
  @moduledoc """
  Compile-time observability for Witness itself.

  Emits `:telemetry` events as each context module is compiled via
  `use Witness`. By default repos is empty — events fire but go nowhere.
  Configure to capture:

      config :witness, :code, repos: [Witness.InMemory]

  ## Events emitted

  | Event | When | Measurements |
  |-------|------|--------------|
  | `[:witness, :use, :definition]` | each `def`/`defmacro` | `%{arity: n}` |
  | `[:witness, :use, :summary]`    | before compile closes | `%{definitions: n}` |
  | `[:witness, :use, :stop]`       | after compile         | `%{duration: ns, bytecode_size: bytes}` |
  | `[:witness, :use, :verified]`   | after typecheck       | `%{}` |
  """

  @events [
    [:witness, :use, :definition],
    [:witness, :use, :summary],
    [:witness, :use, :stop],
    [:witness, :use, :verified]
  ]

  @code_repos Application.compile_env(:witness, [:code, :repos], [])

  @doc "Attach repo-writing handlers for all Witness.Code events. Called at compile time of witness.ex."
  def setup do
    for event <- @events, do: Witness.Telemetry.attach(event, @code_repos)
    :ok
  end

  @doc false
  def __on_definition__(env, kind, name, args, _guards, _body) do
    Module.put_attribute(env.module, :witness, {kind, name, length(args)})

    :telemetry.execute(
      [:witness, :use, :definition],
      %{arity: length(args)},
      %{module: env.module, kind: kind, name: name}
    )
  end

  @doc false
  defmacro __before_compile__(env) do
    events = Module.get_attribute(env.module, :witness) || []
    definitions = length(events)
    t0 = Module.get_attribute(env.module, :witness_t0)

    # Store t0 in process dict so __after_compile__ can read it after module closes
    if t0, do: :erlang.put({Witness.Code, :t0, env.module}, t0)

    :telemetry.execute(
      [:witness, :use, :summary],
      %{definitions: definitions},
      %{module: env.module}
    )

    quote do
      @doc false
      def __witness_compiled__ do
        %Witness{
          module: __MODULE__,
          prefix: config()[:prefix],
          repos: config()[:repos] || [],
          domain: config()[:domain],
          supervise: config()[:supervise] || false,
          snitch: config()[:snitch] || false,
          t0: @witness_t0,
          events: @witness
        }
      end

      @doc false
      def __witness__, do: Process.get(:__witness__)

      @doc false
      def __witness__(pid) when is_pid(pid),
        do: GenServer.call(pid, :__witness__)

      @doc false
      def __witness__(%Witness{} = witness) do
        Process.put(:__witness__, witness)
        :telemetry.execute([:witness, :state], %{}, %{witness: witness})
      end
    end
  end

  @doc false
  def __after_compile__(env, bytecode) do
    t0 = :erlang.get({Witness.Code, :t0, env.module})
    :erlang.erase({Witness.Code, :t0, env.module})

    duration =
      case t0 do
        :undefined -> 0
        t -> System.monotonic_time() - t
      end

    :telemetry.execute(
      [:witness, :use, :stop],
      %{duration: duration, bytecode_size: byte_size(bytecode)},
      %{module: env.module}
    )
  end

  @doc false
  def __after_verify__(module) do
    :telemetry.execute(
      [:witness, :use, :verified],
      %{},
      %{module: module}
    )
  end
end
