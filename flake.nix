{
  description = "Kotiba application";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    haskell-flake.url = "github:srid/haskell-flake";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      imports = [
        inputs.haskell-flake.flakeModule
      ];
      perSystem = { config, self', pkgs, ... }: {
        haskellProjects.default = {
          basePackages = pkgs.haskell.packages.ghc9103;

          devShell = {
            tools = hp: {
              hlint = hp.hlint;
              fourmolu = hp.fourmolu;
            };
            mkShellArgs = {
              nativeBuildInputs = [ pkgs.pkg-config ];
            };
          };
        };

        packages.default = self'.packages.kotiba;
      };
    };
}
