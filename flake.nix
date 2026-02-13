{
  description = "Witness - Compile-time observability for Elixir";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        elixir = pkgs.beam.packages.erlang_27.elixir_1_17;

        # Development dependencies
        buildInputs = with pkgs; [
          elixir
          erlang_27
          git
          gnupg
        ];
      in
      {
        devShells.default = pkgs.mkShell {
          inherit buildInputs;

          shellHook = ''
            # Set up Mix to use local hex/rebar
            mkdir -p .nix-mix
            mkdir -p .nix-hex
            export MIX_HOME=$PWD/.nix-mix
            export HEX_HOME=$PWD/.nix-hex
            export PATH=$MIX_HOME/bin:$PATH
            export PATH=$HEX_HOME/bin:$PATH
            export LANG=en_US.UTF-8
            export ERL_AFLAGS="-kernel shell_history enabled"
          '';
        };
      }
    );
}
