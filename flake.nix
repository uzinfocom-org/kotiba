{
  description = "Kotiba application";

  inputs = {
    dream2nix.url = "github:nix-community/dream2nix";
    nixpkgs.follows = "dream2nix/nixpkgs";
  };

  outputs = {
    self,
    dream2nix,
    nixpkgs,
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
    eachSystem = nixpkgs.lib.genAttrs systems;
  in {
    packages = eachSystem (system: {
      default = dream2nix.lib.evalModules {
        packageSets.nixpkgs = nixpkgs.legacyPackages.${system};
        modules = [
          ./default.nix
          {
            paths.projectRoot = ./.;
            paths.projectRootFile = "flake.nix";
            paths.package = ./.;
          }
        ];
      };
    });

devShells = eachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      hp = pkgs.haskell.packages.ghc912;
    in {
      default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          cabal-install
          hp.ghc
          hp.haskell-language-server
          hp.fourmolu
          hp.hlint
          hp.ghcid
          hp.implicit-hie
          haskellPackages.cabal-fmt
          pkg-config
          zlib
          zlib.dev
          bzip2
          bzip2.dev
          libzip
          libpq
          libpq.dev

          nixd
          statix
          deadnix
          treefmt
          
          jq
          just
        ];

        shellHook = ''
          echo "Welcome to kotiba dev shell"
          export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.postgresql}/lib
          export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.libzip}/lib
          export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.bzip2}/lib
          export LIBRARY_PATH=$LIBRARY_PATH:${pkgs.bzip2}/lib
          export NIX_LDFLAGS="$NIX_LDFLAGS -L${pkgs.bzip2}/lib"
        '';

        NIX_CONFIG = "extra-experimental-features = nix-command flakes";
      };
      
    });
  };
}
