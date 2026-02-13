# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/alexwolf/witness/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/alexwolf/witness/releases/tag/v0.1.0
