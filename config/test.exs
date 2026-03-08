import Config

config :logger, :default_handler, false

# fragmentation_repo uses a pre-built Rust NIF (.so committed to the repo).
# Skip cargo compilation — cargo is only available in the nix devshell, not
# in the global PATH. The pre-built artifact is sufficient for tests.
config :fragmentation_repo, Fragmentation.Native, skip_compilation?: true
