{
  # https://github.com/Mic92/buildbot-nix
  description = "A nixos module to make buildbot a proper Nix-CI.";

  inputs = {
    nixpkgs.url = "github:Nixos/nixpkgs/nixos-unstable-small";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    # used for development
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    hercules-ci-effects.url = "github:hercules-ci/hercules-ci-effects";
    hercules-ci-effects.inputs.nixpkgs.follows = "nixpkgs";
    hercules-ci-effects.inputs.flake-parts.follows = "flake-parts";
  };

  outputs =
    inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (
      {
        lib,
        config,
        withSystem,
        ...
      }:
      {
        imports =
          [
            ./nix/checks/flake-module.nix
          ]
          ++ inputs.nixpkgs.lib.optional (inputs.treefmt-nix ? flakeModule) ./nix/treefmt/flake-module.nix
          ++ inputs.nixpkgs.lib.optional (
            inputs.hercules-ci-effects ? flakeModule
          ) inputs.hercules-ci-effects.flakeModule;
        systems = [
          "x86_64-linux"
          "aarch64-linux"
          "aarch64-darwin"
        ];

        herculesCI = herculesCI: {
          onPush.default.outputs.effects.deploy = withSystem config.defaultEffectSystem (
            { pkgs, hci-effects, ... }:
            hci-effects.runIf (herculesCI.config.repo.branch == "main") (
              hci-effects.mkEffect {
                effectScript = ''
                  echo "${builtins.toJSON { inherit (herculesCI.config.repo) branch tag rev; }}"
                  ${pkgs.hello}/bin/hello
                '';
              }
            )
          );
        };

        flake = {
          nixosModules.buildbot-master.imports = [
            ./nix/master.nix
            (
              { pkgs, ... }:
              {
                services.buildbot-nix.master.buildbotNixpkgs =
                  lib.mkDefault
                    inputs.nixpkgs.legacyPackages.${pkgs.hostPlatform.system};
              }
            )
          ];

          nixosModules.buildbot-worker.imports = [
            ./nix/worker.nix
            (
              { pkgs, ... }:
              {
                services.buildbot-nix.worker.buildbotNixpkgs =
                  lib.mkDefault
                    inputs.nixpkgs.legacyPackages.${pkgs.hostPlatform.system};
              }
            )
          ];

          nixosConfigurations =
            let
              examplesFor =
                system:
                import ./examples {
                  inherit system;
                  inherit (inputs) nixpkgs;
                  buildbot-nix = self;
                };
            in
            examplesFor "x86_64-linux" // examplesFor "aarch64-linux";

          lib = {
            interpolate = value: {
              _type = "interpolate";
              inherit value;
            };
          };
        };
        perSystem =
          {
            self',
            pkgs,
            system,
            ...
          }:
          {
            packages =
              {
                default = pkgs.mkShell {
                  packages = [
                    pkgs.bashInteractive
                    pkgs.mypy
                    pkgs.ruff
                  ];
                };
                buildbot-nix = pkgs.python3.pkgs.callPackage ./default.nix { };
              }
              // lib.optionalAttrs pkgs.stdenv.isLinux {
                buildbot-effects = pkgs.python3.pkgs.callPackage ./nix/buildbot-effects.nix { };
              };
            checks =
              let
                nixosMachines = lib.mapAttrs' (
                  name: config: lib.nameValuePair "nixos-${name}" config.config.system.build.toplevel
                ) ((lib.filterAttrs (name: _: lib.hasSuffix system name)) self.nixosConfigurations);
                packages = lib.mapAttrs' (n: lib.nameValuePair "package-${n}") self'.packages;
                devShells = lib.mapAttrs' (n: lib.nameValuePair "devShell-${n}") self'.devShells;
              in
              nixosMachines // packages // devShells;
          };
      }
    );
}
