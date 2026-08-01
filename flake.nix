{
  description = "Raspberry Pi 5 NixOS configuration";

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  inputs = {
    homelab.url = "git+ssh://git@github.com/GrimOutlook/nix-homelab";
    nix-config.url = "github:GrimOutlook/nix-config";
    nixpkgs.follows = "nix-config/nixpkgs";

    # Raspberry Pi 5 hardware support: vendor kernel, firmware, bootloader and
    # the overlays that go with them. Track the branch matching `nix-config`'s
    # nixpkgs release and follow that nixpkgs, so the whole system -- shared
    # config and Pi hardware alike -- is built against exactly one nixpkgs.
    # WARN: moving `nix-config` to a new NixOS release means moving this to the
    # matching `nixos-<release>` branch in the same commit.
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/nixos-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      homelab,
      nix-config,
      nixos-raspberrypi,
      nixpkgs,
      ...
    }:
    {
      # NOTE: every other host in `nix-hosts` calls `nix-config.lib.mkHost`.
      # dubai cannot: `mkHost` instantiates the system with
      # `nixpkgs.lib.nixosSystem`, and the Pi needs
      # `nixos-raspberrypi.lib.nixosSystem`, which additionally pins
      # `nixpkgs.hostPlatform`, injects the vendor kernel/firmware/bootloader
      # overlays, and trusts the nixos-raspberrypi binary cache. Everything else
      # `mkHost` does -- importing `nix-config.nixosModules.default` and
      # defining a `deploy` devshell -- is reproduced below, so this host is
      # configured through the same `host.*` options as the rest.
      nixosConfigurations.dubai = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = { inherit inputs homelab; };
        modules = [
          nix-config.nixosModules.default
          homelab.nixosModules.default
          ./modules
        ];
      };

      # aarch64 so `nix develop` works on the Pi itself, x86_64 so it also works
      # from the machines deploys are driven from. `deploy` builds locally, so
      # from an x86_64 host either pass `--build-host root@dubai` or lean on
      # that machine's aarch64 binfmt emulation.
      devShells = nixpkgs.lib.genAttrs [ "aarch64-linux" "x86_64-linux" ] (system: {
        default = nix-config.lib.mkDeployShell {
          inherit system;
          hostname = "dubai";
        };
      });

      # Build the SD card image with:
      # nix build .#sdImages.dubai
      sdImages.dubai = self.nixosConfigurations.dubai.config.system.build.sdImage;
    };
}
