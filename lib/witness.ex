config_defaults = [
  active: true,
  extra_events: [],
  handler: [
    Witness.Handler.OpenTelemetry
  ]
]

config_schema =
  [
    active: [
      type: :boolean,
      required: false,
      doc:
        "When set to `false` no handlers will be started or attached to events. Calling Witness functions effectively acts as a noop."
    ],
    app: [
      type: :atom,
      required: true,
      doc: "The OTP application of this Witness context."
    ],
    prefix: [
      type: {:list, :atom},
      required: true,
      doc: "A list of atoms that gets prefixed to every emitted event name."
    ],
    extra_events: [
      type: {:list, {:list, :atom}},
      required: false,
      doc: "A list of further events that belong to this context."
    ],
    handler: [
      type: {:list, {:or, [{:tuple, [:atom, :any]}, :atom]}},
      required: false,
      doc: "A list of `Witness.Handler`s that process emitted events."
    ],
    sources: [
      type: {:or, [nil, {:list, :atom}]},
      required: false,
      doc:
        "A list of `Witness.Source`s which belong to this context; when `nil` they are determined at runtime (through `:application.get_env(<app>, :modules)`)"
    ]
  ]
  # Merge defaults into schema for proper documentation generation
  |> Enum.map(fn {key, spec} ->
    if Keyword.has_key?(config_defaults, key) do
      {key, Keyword.put(spec, :default, config_defaults[key])}
    else
      {key, spec}
    end
  end)
  |> NimbleOptions.new!()

config_types = Enum.map(config_schema.schema, &NimbleOptions.option_typespec([&1]))

defmodule Witness do
  @moduledoc """
  A `use`able module to create an observability context for parts of your app.

  Effectively an opinionated wrapper around `:telemetry` that - by default - exports
  it's events and spans to `OpenTelemetry`.

  ## Usage

      defmodule MyApp.AnotherBoundedContext.Observability do
        use Witness,
          prefix: [:another_bounded_context]
      end

  This generates a `c:config/0` function - which can be overwritten - and injects
  `Witness.Tracker` functions and macros.

      defmodule MyApp.AnotherBoundedContext.SomeModuleWeWantToObserve do
        require MyApp.AnotherBoundedContext.Observability, as: O11y

        def some_function(an_argument) do
          O11y.with_span [:doing, :the, :thing], %{optional: "metadata"} do
            # Some cool logic here
            O11y.track_event([:stuff, :happend], %{required: "attributes"}, %{optional: "metadata"})
            # Some more logic
          end
        end
      end

  For further things you can do check the `Witness.Tracker` module.

  To export your events and spans you need to include your observability context in a supervision tree.

      defmodule MyApp.AnotherBoundedContext.Supervisor do
        # ...

        def init(arg) do
          children = [
            MyApp.AnotherBoundedContext.Observability,
            # ...
          ]

          Supervisor.init(children, ...)
        end
      end

  ## Events and Handlers

  All events and spans are emitted through `:telemetry` (`:telemetry.execute/3` and `:telemetry.span/3`).

  The macros provided by `Witness.Tracker` keep track of the emitted event names and
  transform each using module into a `Witness.Source`.

  When including an observability context into a supervision tree, we load all "source modules" that
  belong to the context, aggregate their events, and attach the given `handler`s to all of them.
  Every handler gets attached to every event that can happen in a context.

  By default all events and spans get exported to `OpenTelemetry` through the
  `Witness.Handler.OpenTelemetry` handler.

  If you'd like to implement a custom handler, refer to the `Witness.Handler` behaviour.

  ## Config
  #{NimbleOptions.docs(config_schema)}
  """

  alias __MODULE__.Source

  defmacro __using__(config) do
    if not Keyword.keyword?(config) do
      raise ArgumentError, "expected config to be a keyword list but got: #{Macro.to_string(config)}"
    end

    quote location: :keep do
      @behaviour unquote(__MODULE__)

      use unquote(__MODULE__).Tracker,
        context: __MODULE__

      # Validate the config in an after_compile hook, this way we can also validate
      # a config from an overridden `config/0` call
      @after_compile unquote(__MODULE__)

      @spec child_spec(ignored :: term) :: Witness.Supervisor.child_spec()
      def child_spec(_) do
        unquote(__MODULE__).Supervisor.child_spec(__MODULE__)
      end

      @impl unquote(__MODULE__)
      def config do
        app = unquote(config[:app])

        if app do
          app
          |> unquote(__MODULE__).defaults()
          |> Keyword.merge(Application.get_env(app, __MODULE__, []))
          |> Keyword.merge(unquote(config))
        else
          unquote(__MODULE__).defaults()
          |> Keyword.merge(unquote(config))
        end
      end

      defoverridable config: 0
    end
  end

  @config_schema config_schema

  def __after_compile__(%{module: module}, _bytecode) do
    NimbleOptions.validate!(module.config(), @config_schema)
  end

  @typedoc "A module which implements this behaviour."
  @type t :: module
  @type config :: [unquote(NimbleOptions.option_typespec(config_schema))]

  @type event_name :: nonempty_list(atom)
  @type attributes :: keyword | map
  @type meta :: keyword | map

  @callback config() :: config

  @doc """
  A guard that checks if the given value is a context module.

  To be specific it only checks if the given value is an atom and not nil. As
  further checks are not possible in guards. If you'd like to be certain use
  `context?/1`.

  ## Examples

      iex> is_context(SomeModule)
      true

      iex> is_context(:an_atom)
      true

      iex> is_context(nil)
      false

      iex> is_context("a string")
      false

      iex> is_context(["a", "list"])
      false
  """
  defguard is_context(context) when is_atom(context) and not is_nil(context)

  @doc """
  (Actually) checks if the given value is a context module.

  That is if it's a module that implements the `c:config/0` callback and if the
  returned config adheres to the config schema.

  ## Examples

      iex> defmodule ContextWithValidConfig do
      ...>   def config, do: %{app: :my_app, prefix: [:some, :prefix], handler: [SomeHandler]}
      ...> end
      iex> context?(ContextWithValidConfig)
      true

      iex> defmodule ContextWithInvalidConfig do
      ...>   def config, do: %{invalid: "config"}
      ...> end
      iex> context?(MyContext)
      false

      iex> context?(Enum)
      false

      iex> context?(nil)
      false

      iex> is_context("a string")
      false

      iex> is_context(["a", "list"])
      false
  """
  def context?(maybe_context) do
    is_context(maybe_context) and
      function_exported?(maybe_context, :config, 0) and
      has_valid_config?(maybe_context)
  end

  defp has_valid_config?(context) do
    config = config(context)

    match?({:ok, _}, NimbleOptions.validate(config, @config_schema))
  end

  defaults = Keyword.delete(config_defaults, :app)

  @doc """
  The default values that are merged into the given config when `use`ing this module.

  ## Examples

      iex> defaults(:unknown_app)
      #{inspect([{:app, :unknown_app} | defaults])}

      iex> Application.put_env(:some_app, #{inspect(__MODULE__)}, prefix: [:blubb], handler: [SomeHandler])
      iex> defaults(:some_app)
      #{inspect(Keyword.merge([{:app, :some_app} | defaults], prefix: [:blubb], handler: [SomeHandler]))}
  """
  @spec defaults(app :: atom | nil) :: keyword
  def defaults(app \\ nil) do
    defaults =
      if app do
        [{:app, app} | unquote(defaults)]
      else
        unquote(defaults)
      end

    case app && Application.fetch_env(app, __MODULE__) do
      {:ok, configured} ->
        Keyword.merge(defaults, configured)

      _ ->
        defaults
    end
  end

  @doc """
  Returns the `c:config/0` of the given context module.

  ## Config
  #{NimbleOptions.docs(config_schema)}
  """
  @spec config(t) :: config
  def config(module) when is_context(module), do: module.config()

  @doc """
  Returns the specified `c:config/0` value of the given context module.

  ## Config
  #{NimbleOptions.docs(config_schema)}
  """
  for {key, type} <- config_types do
    @spec config(t, unquote(key)) :: unquote(type)
    def config(module, unquote(key)), do: config(module)[unquote(key)]
  end

  @doc "Returns all modules that are observable through the given context module."
  @spec sources_in(t) :: {:ok, [module]} | {:error, {:unknown_app, atom}}
  def sources_in(context) when is_context(context) do
    if sources = config(context, :sources) do
      {:ok, sources}
    else
      resolve_sources_for(context)
    end
  end

  defp resolve_sources_for(context) do
    app = config(context, :app)

    case :application.get_key(app, :modules) do
      {:ok, modules} ->
        sources = Enum.filter(modules, &match?(%{context: ^context}, Source.info(&1)))

        {:ok, sources}

      :undefined ->
        {:error, {:unknown_app, app}}
    end
  end

  @doc "Checks if the given module is a `#{inspect(__MODULE__)}.Source`."
  @spec source?(module) :: boolean
  defdelegate source?(module), to: Source
end
