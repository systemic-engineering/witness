# Witness
[![CI](https://github.com/systemic-engineer/witness/actions/workflows/ci.yml/badge.svg)](https://github.com/systemic-engineer/witness/actions/workflows/ci.yml)
[![Hexdocs.pm](https://img.shields.io/badge/hexdocs-online-blue)](https://hexdocs.pm/witness/)
[![Hex.pm](https://img.shields.io/hexpm/v/witness.svg)](https://hex.pm/packages/witness)
[![Hex.pm Downloads](https://img.shields.io/hexpm/dt/witness)](https://hex.pm/packages/witness)

An opinionated observability library for Elixir built on `:telemetry` with compile-time event registry, zero-duplication event tracking, and OpenTelemetry integration.

## Features

- **Zero Duplication**: Event names are written once at the emission site, handlers auto-attach
- **Compile-Time Registry**: Events discovered automatically via module attributes
- **Bounded Context Isolation**: Each context has separate observability configuration
- **OpenTelemetry Integration**: Built-in OpenTelemetry handler for spans and events
- **Logger Integration**: Emit structured log events through telemetry
- **Type-Safe**: Comprehensive typespecs and compile-time validation

## Installation

Add `witness` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:witness, "~> 0.3"}
  ]
end
```

## Quick Start

### 1. Define an observability context

```elixir
defmodule MyApp.Users.Observability do
  use Witness,
    app: :my_app,
    prefix: [:users]
end
```

### 2. Use it in your modules

```elixir
defmodule MyApp.Users.Service do
  require MyApp.Users.Observability, as: O11y

  def create_user(params) do
    O11y.with_span [:create_user], %{user_id: params.id} do
      # Business logic here
      O11y.track_event([:validation, :passed], %{params: params})

      result = do_create_user(params)

      O11y.track_event([:user, :created], %{user_id: result.id})
      result
    end
  end
end
```

### 3. Add to supervision tree

```elixir
defmodule MyApp.Users.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def init(_init_arg) do
    children = [
      MyApp.Users.Observability,  # <-- Add your observability context
      # ... other children
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

## How It Works

### Compile-Time Event Registry

When you use `track_event/3` or `with_span/3` macros, Witness:

1. Remembers the event name at compile time using module attributes
2. Generates a `__observable__/0` callback that returns all events this module emits
3. Turns the module into a `Witness.Source`

When your observability context starts:

1. It discovers all source modules via `:application.get_key(app, :modules)`
2. Aggregates all events from all sources
3. Attaches configured handlers to all events

This means **you never duplicate event names** - write them once where they're emitted, handlers attach automatically.

### Bounded Contexts

Each part of your application can have its own observability context with its own:

- Event prefix (e.g., `[:users]`, `[:billing]`, `[:notifications]`)
- Handler configuration
- Active/inactive state

```elixir
defmodule MyApp.Billing.Observability do
  use Witness,
    app: :my_app,
    prefix: [:billing],
    handler: [
      {MyCustomHandler, config: :here},
      Witness.Handler.OpenTelemetry
    ]
end
```

## Custom Handlers

Implement the `Witness.Handler` behaviour:

```elixir
defmodule MyApp.MetricsHandler do
  @behaviour Witness.Handler

  @impl true
  def handle_event(event_name, measurements, metadata, config) do
    # Your custom logic here
    :ok
  end
end
```

## Logger Integration

Witness provides a `Witness.Logger` module that emits structured log events through telemetry:

```elixir
defmodule MyApp.Users.Service do
  require MyApp.Users.Observability, as: O11y
  require Witness.Logger

  def create_user(params) do
    Witness.Logger.info(O11y, "Creating user", user_id: params.id)

    case do_create_user(params) do
      {:ok, user} ->
        Witness.Logger.info(O11y, "User created successfully", user_id: user.id)
        {:ok, user}

      {:error, reason} ->
        Witness.Logger.error(O11y, "User creation failed", reason: reason)
        {:error, reason}
    end
  end
end
```

### Built-in Handler

Use `Witness.Handler.Logger` to log telemetry events:

```elixir
defmodule MyApp.Users.Observability do
  use Witness,
    app: :my_app,
    prefix: [:users],
    handler: [
      {Witness.Handler.Logger, level: :info},
      Witness.Handler.OpenTelemetry
    ]
end
```

The handler automatically:
- Logs events at the appropriate level (`:debug`, `:info`, `:warning`, `:error`, etc.)
- Formats spans with duration and status
- Includes structured metadata
- Respects per-event log levels

### Available Log Levels

- `Witness.Logger.debug/3` - Debug-level logs
- `Witness.Logger.info/3` - Info-level logs
- `Witness.Logger.notice/3` - Notice-level logs
- `Witness.Logger.warning/3` - Warning-level logs
- `Witness.Logger.error/3` - Error-level logs
- `Witness.Logger.critical/3` - Critical-level logs
- `Witness.Logger.alert/3` - Alert-level logs
- `Witness.Logger.emergency/3` - Emergency-level logs

## Configuration

### Context Configuration

```elixir
use Witness,
  app: :my_app,              # Required: OTP application name
  prefix: [:my_context],      # Required: Event name prefix
  active: true,               # Optional: Enable/disable (default: true)
  handler: [...],             # Optional: List of handlers (default: [Witness.Handler.OpenTelemetry])
  sources: [...],             # Optional: Explicit source modules (default: auto-discover)
  extra_events: [...],        # Optional: Additional events not tracked by sources
  store: {Witness.Store.Mnesia, []}  # Optional: Persistent event store (default: nil)
```

### Event Persistence

Witness supports pluggable persistent storage via the `:store` option. Events flowing
through the telemetry pipeline can be written to any backend that implements the
`Witness.Store` behaviour.

The built-in backend is `Witness.Store.Mnesia`:

```elixir
defmodule MyApp.Users.Observability do
  use Witness,
    app: :my_app,
    prefix: [:users],
    store: {Witness.Store.Mnesia, []}
end
```

For disc-backed persistence across restarts:

```elixir
store: {Witness.Store.Mnesia, storage_type: :disc_copies}
```

Query persisted events with `Witness.Store.Mnesia.list_events/3`:

```elixir
# All events
{:ok, events} = Witness.Store.Mnesia.list_events(MyApp.Users.Observability, [], [])

# Filtered
{:ok, events} = Witness.Store.Mnesia.list_events(MyApp.Users.Observability,
  [after: cutoff_ts, event_name: [:user, :created], limit: 50],
  []
)
```

#### Custom Store Backends

Implement `Witness.Store` to use any storage system:

```elixir
defmodule MyApp.Store.Postgres do
  @behaviour Witness.Store

  @impl true
  def store_event(event_name, attributes, meta, context, config) do
    # Write to Postgres
    :ok
  end

  @impl true
  def list_events(context, query_opts, config) do
    # Query from Postgres
    {:ok, []}
  end

  @impl true
  def child_spec(config) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [config]}}
  end
end
```

### Runtime Configuration

You can also configure contexts at runtime via application config:

```elixir
# config/runtime.exs
config :my_app, MyApp.Users.Observability,
  active: System.get_env("OBSERVABILITY_ENABLED", "true") == "true"
```

## Pattern: Zero Duplication

**Before (traditional telemetry):**

```elixir
# In your code
:telemetry.execute([:my_app, :users, :created], %{user_id: id}, %{})

# Somewhere else, you have to remember the exact event name
:telemetry.attach("my-handler", [:my_app, :users, :created], &handle/4, nil)
```

**After (Witness):**

```elixir
# In your code
O11y.track_event([:created], %{user_id: id})

# Handlers attach automatically - no duplication!
```

## Comparison with Raw Telemetry

| Feature | Raw :telemetry | Witness |
|---------|---------------|---------|
| Event duplication | Manual sync required | Zero duplication |
| Event discovery | Manual registration | Automatic at compile-time |
| Handler attachment | Manual per-event | Automatic per-context |
| Bounded contexts | Manual convention | Built-in structure |
| Type safety | Limited | Comprehensive specs |
| OpenTelemetry | Manual integration | Built-in handler |

## License

This project is licensed under the [Hippocratic License 3.0](LICENSE) - an ethical open source license.
