{
  description = "Witness - Compile-time observability for Elixir";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flakes.url = "path:/Users/reed/.flakes";
  };

  outputs = { self, nixpkgs, flake-utils, flakes }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        beam = flakes.lib.${system}.beam;
        nif  = flakes.lib.${system}.nif;
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.git
            pkgs.gnupg
          ] ++ beam.elixirTools ++ nif.nifTools;

          shellHook =
            beam.elixirHook +
            nif.nifHook + ''
            export ERL_AFLAGS="-kernel shell_history enabled"
          '';
        };
      }
    );
}
