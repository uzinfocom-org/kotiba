{
  description = "Kotiba application";

  inputs = {
    dream2nix.url = "github:lambdajon/dream2nix";
    nixpkgs.follows = "dream2nix/nixpkgs";

    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    git-hooks.url = "github:cachix/git-hooks.nix";

    systems.url = "github:nix-systems/default";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rna.url = "path:/home/xfeusw/workspace/congeries/release-notes-assistant";
  };

  outputs = { self, dream2nix, systems, nixpkgs, nixpkgs-unstable, git-hooks
    , treefmt-nix, rna }:
    let
      eachSystem = f:
        nixpkgs.lib.genAttrs (import systems)
        (system: f nixpkgs.legacyPackages.${system});
      pkgsUnstable =
        eachSystem (pkgs: nixpkgs-unstable.legacyPackages.${pkgs.system});
      treefmt = {
        projectRootFile = "flake.nix";
        programs.fourmolu.enable = true;
        programs.cabal-fmt.enable = true;
        programs.nixfmt.enable = true;
      };
      treefmtEval = eachSystem (pkgs:
        treefmt-nix.lib.evalModule pkgs (treefmt // {
          programs.fourmolu.package =
            pkgsUnstable.${pkgs.system}.haskell.packages."ghc912".fourmolu;
        }));
    in {
      packages = eachSystem (pkgs: {
        default = dream2nix.lib.evalModules {
          packageSets.nixpkgs = pkgs;
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

      checks = eachSystem (pkgs: {
        pre-commit = git-hooks.lib.${pkgs.system}.run {
          src = ./.;

          hooks = {
            treefmt = {
              enable = true;
              package = treefmtEval.${pkgs.system}.config.build.wrapper;
            };
          };
        };
        test = pkgs.testers.runNixOSTest {

          name = "config test";

          nodes.machine = { ... }: {
            imports = with self; [
              nixosModules.default
              ({ ... }: {
                services.kotiba = {
                  enable = true;
                  createDatabaseLocally = true;
                  forgejoToken =
                    "write your access token (dont forget delete it before pushing)";
                  forgejoUrl = "git.oss.uzinfocom.uz";
                  identityName = "John Doe";
                  identityEmail = "johndoe@mail.com";
                };
                system.stateVersion = "26.05";
              })
            ];
          };

          node = {
            # since we are using an overlay, we must make pkgs writable
            pkgsReadOnly = false;
          };

          # disable only when working on testScript
          skipTypeCheck = true;

          testScript = builtins.readFile ./test.py;
        };

      });

      devShells = eachSystem (pkgs:
        let
          hlib = pkgs.haskell.lib;
          hp = pkgs.haskell.packages."ghc912".override {
            overrides = self: super: {
              brick = hlib.dontCheck (hlib.doJailbreak super.brick);
            };
          };
        in {
          default = pkgs.mkShell {
            nativeBuildInputs = [
              pkgs.cabal-install
              hp.ghc
              hp.haskell-language-server
              hp.fourmolu
              hp.hlint
              hp.ghcid
              hp.implicit-hie
              pkgs.haskellPackages.cabal-fmt
              pkgs.pkg-config
              pkgs.zlib
              pkgs.zlib.dev
              pkgs.bzip2
              pkgs.bzip2.dev
              pkgs.libzip
              pkgs.libpq
              pkgs.libpq.dev

              pkgs.nixd
              pkgs.statix
              pkgs.deadnix
              pkgs.treefmt
              pkgs.nixfmt

              pkgs.jq
              pkgs.just
              rna.packages.${pkgs.system}.default
            ] ++ self.checks.${pkgs.system}.pre-commit.enabledPackages;

            shellHook = ''
              echo "Welcome to kotiba dev shell"

              ${self.checks.${pkgs.system}.pre-commit.shellHook}

              export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.postgresql}/lib
              export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.libzip}/lib
              export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${pkgs.bzip2}/lib
              export LIBRARY_PATH=$LIBRARY_PATH:${pkgs.bzip2}/lib
              export NIX_LDFLAGS="$NIX_LDFLAGS -L${pkgs.bzip2}/lib"
            '';

            NIX_CONFIG = "extra-experimental-features = nix-command flakes";
          };
        });
      apps = eachSystem (pkgs:
        let refresh = self.packages.${pkgs.system}.default.config.lock.refresh;
        in {
          default = {
            type = "app";
            program = "${self.packages.${pkgs.system}.default}/bin/kotiba";
          };
          update-lock = {
            type = "app";
            program = "${pkgs.writeShellScript "update-lock" ''
              export PATH="${pkgs.git}/bin:${pkgs.cabal-install}/bin:$PATH"
              exec ${nixpkgs.lib.getExe refresh}
            ''}";
          };
        });

      nixosModules = { default = import ./module.nix self; };

      formatter =
        eachSystem (pkgs: treefmtEval.${pkgs.system}.config.build.wrapper);
    };
}
