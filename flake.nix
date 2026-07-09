{
  description = "Pause Cemu when a Bluetooth controller disconnects on macOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default-darwin";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nix-darwin,
    nixpkgs,
    systems,
  }: let
    forAllSystems = nixpkgs.lib.genAttrs (import systems);
  in {
    packages = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
      package = pkgs.stdenv.mkDerivation {
        pname = "auto-pause-cemu";
        version = "0.1.0";
        src = nixpkgs.lib.cleanSource ./.;

        nativeBuildInputs = [
          pkgs.swift
          pkgs.swiftpm
        ];

        buildPhase = ''
          runHook preBuild
          export HOME="$TMPDIR"
          swift build -c release --scratch-path "$TMPDIR/swift-build"
          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          install -Dm755 "$TMPDIR/swift-build/release/auto-pause-cemu" \
            "$out/bin/auto-pause-cemu"
          runHook postInstall
        '';

        meta = {
          description = "Pause Cemu while a Bluetooth controller is disconnected";
          homepage = "https://github.com/gaoyifan/auto-pause-cemu";
          license = nixpkgs.lib.licenses.mit;
          mainProgram = "auto-pause-cemu";
          platforms = nixpkgs.lib.platforms.darwin;
        };
      };
    in {
      default = package;
      auto-pause-cemu = package;
    });

    checks = forAllSystems (system: {
      inherit (self.packages.${system}) auto-pause-cemu;
    });

    devShells = forAllSystems (system: let
      pkgs = import nixpkgs {inherit system;};
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.swift
          pkgs.swiftpm
        ];
      };
    });

    formatter = forAllSystems (
      system: nixpkgs.legacyPackages.${system}.alejandra
    );

    darwinModules.default = import ./nix/module.nix {inherit self;};

    # Instantiate the module so CI catches invalid nix-darwin service options,
    # not just package build failures.
    darwinConfigurations.ci = nix-darwin.lib.darwinSystem {
      modules = [
        self.darwinModules.default
        {
          nixpkgs.hostPlatform = "aarch64-darwin";
          system = {
            primaryUser = "ci";
            stateVersion = 6;
          };
          users.users.ci.home = "/Users/ci";
          services.auto-pause-cemu.enable = true;
        }
      ];
    };
  };
}
