{
  description = "The drums Rust library";
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.follows = "flake-utils";
      };
    };
  };

  outputs = { self, nixpkgs, crane, flake-utils, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };

        rustTarget = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
        unstableRustTarget = pkgs.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default.override {
          extensions = [ "rust-src" "miri" "rustfmt" ];
        });
        craneLib = (crane.mkLib pkgs).overrideToolchain rustTarget;
        unstableCraneLib = (crane.mkLib pkgs).overrideToolchain unstableRustTarget;

        tomlInfo = craneLib.crateNameFromCargoToml { cargoToml = ./Cargo.toml; };
        inherit (tomlInfo) pname version;
        src = ./.;

        rustfmt' = pkgs.writeShellScriptBin "rustfmt" ''
          exec "${unstableRustTarget}/bin/rustfmt" "$@"
        '';

        cargoArtifacts = craneLib.buildDepsOnly {
          inherit src;
          cargoExtraArgs = "--all-features --all";
        };

        drums = craneLib.buildPackage {
          inherit cargoArtifacts src version;
          cargoExtraArgs = "--all-features --all";
        };

      in
      rec {
        checks = {
          inherit drums;

          drums-clippy = craneLib.cargoClippy {
            inherit cargoArtifacts src;
            cargoExtraArgs = "--all --all-features";
            cargoClippyExtraArgs = "-- --deny warnings";
          };

          drums-fmt = unstableCraneLib.cargoFmt {
            inherit src;
          };
        };

        packages.drums = drums;
        packages.default = packages.drums;

        apps.drums = flake-utils.lib.mkApp {
          name = "drums";
          drv = drums;
        };
        apps.default = apps.drums;

        devShells.default = devShells.drums;
        devShells.drums = pkgs.mkShell {
          buildInputs = [ ];

          nativeBuildInputs = [
            rustfmt'
            rustTarget

            pkgs.probe-rs
            pkgs.cargo-msrv
            pkgs.cargo-deny
            pkgs.cargo-expand
            pkgs.cargo-bloat
            pkgs.cargo-fuzz
            pkgs.cargo-generate
            pkgs.cargo-binutils

            # pkgs.rerun

            # pkgs.gitlint

            # (pkgs.openocd.overrideAttrs (old: {
            #   src = pkgs.fetchFromGitHub {
            #     owner = "openocd-org";
            #     repo = "openocd";
            #     rev = "master";
            #     hash = "sha256-vV9U5HUlXzSacywPQGwj+1eMFyUw4tROBVfZ7GXRfHs=";
            #   };
            #   nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.autoreconfHook ];
            # }))
          ];
        };
      }
    );
}
