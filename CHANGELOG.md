# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-02-25

### Added
- `Witness.Store` behaviour — a pluggable interface for persistent event storage
  backends. Defines three callbacks: `store_event/5`, `list_events/3`, and
  `child_spec/1`.
- `Witness.Store.Mnesia` — a Mnesia-backed store implementation. Each Witness
  context gets its own isolated table (`Module.concat(context, WitnessEvents)`),
  keyed by `{timestamp_us, ref}` as an `ordered_set` for chronological ordering.
  Supports `:after`, `:before`, `:limit`, and `:event_name` query filters.
  Storage type is configurable (`ram_copies` by default, `disc_copies` optional).
- `Witness.Handler.Store` — a handler bridge that routes telemetry events into
  any configured `Witness.Store` backend. Logs warnings on store failures without
  disrupting the telemetry pipeline.
- `:store` config key on `Witness` contexts — accepts a `{module, config}` tuple
  to enable persistence, or `nil` to disable (default).

## [0.2.0] - 2026-02-17

### Added
- `SpanRegistry` now tombstones span entries instead of deleting them when a span
  closes or a process dies. Tombstones are kept for 30 seconds, allowing out-of-band
  processors (async pipelines, event handlers) to look up a parent span ref even after
  the originating process has finished.
- `SpanRegistry.sweep/2` for manual tombstone cleanup (primarily for testing).

### Changed
- `SpanRegistry.unregister_span/2` now requires the `span_ref` as a second argument
  so the tombstone can be written without an extra ETS lookup.
- `SpanRegistry` GenServer now monitors registered PIDs (ref-counted for nested spans)
  and tombstones their ETS entries on `:DOWN`, preventing unbounded memory growth from
  processes killed mid-span.

### Fixed
- ETS entries for processes killed mid-span (untrappable `:kill` signal) were never
  cleaned up. The GenServer now monitors each registered PID and tombstones the entry
  on process death, with a periodic sweep to reclaim memory.

## [0.1.0] - 2026-02-13

### Added
- Initial release of Witness observability library
- Compile-time event registry using module attributes
- Zero-duplication event tracking with automatic handler attachment
- `Witness` main module with `use`-able macro for creating observability contexts
- `Witness.Tracker` for emitting telemetry events and spans
- `Witness.Source` behaviour for event source modules
- `Witness.Handler` behaviour for custom event handlers
- `Witness.Handler.OpenTelemetry` for OpenTelemetry integration
- `Witness.Supervisor` for managing handler lifecycle
- `Witness.Span` for span metadata and status management
- `Witness.Utils` for internal utilities (map flattening, metadata enrichment)
- Comprehensive documentation and examples
- Production-grade Credo configuration
- Hippocratic License 3.0

[Unreleased]: https://github.com/systemic-engineer/witness/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/systemic-engineer/witness/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/systemic-engineer/witness/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/systemic-engineer/witness/releases/tag/v0.1.0
