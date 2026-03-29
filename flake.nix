{
  description = "NixOS configuration for dubai";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    homelab.url = "git+ssh://git@github.com/GrimOutlook/nix-homelab";

    nix-config = {
      url = "github:GrimOutlook/nix-config";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nix-config,
      ...
    }:
    nix-config.inputs.flake-parts.lib.mkFlake { inherit inputs; } (
      let
        homelab = inputs.homelab.nixosModules.default;
        host-info = rec {
          name = "dubai";
          flake = "github:GrimOutlook/nix-host-${name}";
        };
      in
      {
        imports = [
          nix-config.modules.flake.hosts
          nix-config.modules.flake.host-info
          (nix-config + "/flakes/systems.nix")
        ];
        inherit host-info;
        modules = [
          "pi"
        ];
        nixos = {
          imports = [
            ./hardware
            (import ./services rec {
              inherit homelab;
              inherit host-info;
              host = homelab.hosts.${host-info.name};
            })
          ];

          system = {
            stateVersion = "25.05";
          };
        };
        home = {
          home.stateVersion = "25.11";
        };
      }
    );
}
