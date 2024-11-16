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

  nixConfig = {
    extra-experimental-features = [ "pipe-operator" "pipe-operators" ];
    extra-substituters = [ "https://cache.kyouma.net" ];
    extra-trusted-public-keys = [ "cache.kyouma.net:Frjwu4q1rnwE/MnSTmX9yx86GNA/z3p/oElGvucLiZg=" ];
  };

  outputs = { self, nixpkgs, lix-module, ... }: let
    lib = nixpkgs.lib.extend (final: prev: {
      neoidiosyn = {
        systems = {
          riscv64 = "rv64gc";
          aarch64 = "armv8.2-a";
          x86_64 = "x86-64-v3";
        } |> final.mapAttrs' (cpu: arch: {
          name = "${cpu}-linux";
          value = {
            config = "${cpu}-unknown-linux-musl";
            useLLVM = true;
            linker = "lld";
            gcc = { inherit arch; };
          };
        });
      };
    });
  in {
    inherit lib;

    overlays.default = lib.composeExtensions
      lix-module.overlays.default
      (import ./overlay.nix { inherit lib; });

    legacyPackages = lib.neoidiosyn.systems
    |> lib.mapAttrs (system: crossSystem: let
      pkgs = import nixpkgs {
        localSystem.config = {
          riscv64-linux = "riscv64-unknown-linux-gnu";
          aarch64-linux = "aarch64-unknown-linux-musl";
          x86_64-linux = "x86_64-unknown-linux-musl";
        }.${system};

        inherit crossSystem;
        overlays = [ self.overlays.default ];

        config = {
          allowBroken = true;
          allowUnfree = true;
          allowUnsupportedSystem = true;
        };
      };
    in pkgs // {
      config = let
        stdenv = import ./stdenv.nix { inherit lib pkgs; };
      in pkgs.config or { } // {
        replaceStdenv = stdenv;
        replaceCrossStdenv = stdenv;
      };
    });

    nixosModules = {
      default = import ./module.nix;
    } // lib.mapAttrs (system: pkgs: {
      nixpkgs = {
        inherit (pkgs)
          buildPlatform
          hostPlatform
          overlays
          config;
      };
    }) self.legacyPackages;


    hydraJobs = lib.genAttrs [
      "stdenv"

      "akkoma"
      "bat"
      "bottom"
      "cargo"
      "ceph"
      "clang"
      "cockroachdb"
      "conduwuit"
      "cryptsetup"
      "curl"
      "dbus-broker"
      "electron"
      "fd"
      "ffmpeg"
      "gfortran"
      "helix"
      "jaq"
      "kitty"
      "libinput"
      "lix"
      "lld"
      "mesa"
      "mimalloc"
      "mpv"
      "musl"
      "nftables"
      "nushell"
      "openssh"
      "qemu-user"
      "pipewire"
      "postgresql"
      "python3"
      "ripgrep"
      "rustc"
      "sd"
      "sioyek"
      "sqlite"
      "sudo-rs"
      "systemd"
      "wayland"
      "wireplumber"
      "xh"
      "zlib"
    ] (name: lib.mapAttrs (system: pkgs: pkgs.${name}) self.legacyPackages
      |> lib.filterAttrs (system: pkg: pkg.meta.hydraPlatforms or pkg.meta.platforms or [ ]
        |> lib.any (lib.meta.platformMatch self.legacyPackages.${system}.hostPlatform))
      |> lib.mapAttrs (system: pkg: lib.hydraJob pkg));
  };
}
