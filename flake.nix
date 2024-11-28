{
  description = "I do not have to explain myself";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    lix = {
      url = "https://git.lix.systems/lix-project/lix/archive/main.tar.gz";
      flake = false;
    };

    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/main.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.lix.follows = "lix";
    };
  };

  outputs = { self, nixpkgs, lix-module, ... }: let
    inherit (nixpkgs) lib;
  in {
    inherit lib;

    overlays.default = lib.composeExtensions
      lix-module.overlays.default
      (import ./overlay.nix);

    nixosModules.default = import ./module.nix;

    legacyPackages = lib.genAttrs [ "riscv64-linux" "aarch64-linux" "x86_64-linux" ] (system: import nixpkgs {
      localSystem = {
        inherit system;

        gcc.arch = {
          riscv64-linux = "rv64gc";
          aarch64-linux = "armv8.2-a+fp16+rcpc+dotprod";
          x86_64-linux = "x86-64-v3";
        }.${system};
      };

      overlays = [ self.overlays.default ];
      config = let
        extendEnv = import ./extendEnv.nix;
        env = {
          NIX_CFLAGS_COMPILE = [ "-pipe" ];
          NIX_LDFLAGS_BEFORE = [ "-O2" "--hash-style=gnu" ];
          NIX_RUSTFLAGS = [ "-C" "codegen-units=1" "-C" "opt-level=2" ];
        };
      in {
        allowUnfree = true;
        replaceStdenv = { pkgs }:
          extendEnv { inherit (pkgs) lib addAttrsToDerivation; } env pkgs.stdenv;
        replaceCrossStdenv = { buildPackages, baseStdenv }:
          extendEnv { inherit (buildPackages) lib addAttrsToDerivation; } env baseStdenv;
      };
    });

    hydraJobs = {
      nixos = self.legacyPackages |> lib.mapAttrs (system: pkgs: let
        nixos = lib.nixosSystem {
          modules = [
            self.nixosModules.default {
              system.stateVersion = "25.05";
              nixpkgs = { inherit (pkgs) hostPlatform overlays config; };
              boot = {
                kernel.enable = false;
                initrd.enable = false;
                loader.grub.enable = false;
              };
            }
          ];
        };
      in lib.hydraJob nixos.config.system.build.toplevel);
    } // (lib.genAttrs (import ./packages.nix) (name: lib.mapAttrs (system: pkgs: pkgs.${name}) self.legacyPackages
      |> lib.filterAttrs (system: pkg: pkg.meta.hydraPlatforms or pkg.meta.platforms or [ ]
        |> lib.any (lib.meta.platformMatch self.legacyPackages.${system}.hostPlatform))
      |> lib.mapAttrs (system: pkg: lib.hydraJob pkg)));
  };
}
