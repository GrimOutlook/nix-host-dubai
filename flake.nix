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

      # A bootable rescue/installer card for this Pi.
      #
      # There is deliberately no image of `dubai` itself: its root lives on the
      # NVMe (see `modules/disko.nix`), so an SD image of that config would have
      # to define its own conflicting `fileSystems."/"`. The supported route is
      # to boot this installer and install onto the NVMe from it.
      #
      #   nix build .#installerImage
      #
      # This is upstream's rpi5 installer plus the workstation SSH keys, so it
      # can be driven over the network instead of needing a keyboard on the Pi.
      # See README.md for the install procedure.
      nixosConfigurations.dubai-installer = nixos-raspberrypi.lib.nixosInstaller {
        specialArgs = { inherit inputs; };
        modules = [
          (
            {
              pkgs,
              nixos-raspberrypi,
              ...
            }:
            {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
              ];

              networking.hostName = "dubai-installer";

              # Same keys the retired `pi` account carried, so the machines that
              # deploy dubai can reach the installer too. The installation-device
              # profile already enables sshd and a passwordless `nixos` user.
              users.users =
                let
                  keys = [
                    # paris
                    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA+VOouatDdN2oqpwfDtzJqDvrx9YJwbvs3of1aZ8Q24"
                    # berlin
                    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIApGjkXLSbpQIvpIFbVeywyS8Y9rk0kQqPT5wjE/QEnX"
                  ];
                in
                {
                  nixos.openssh.authorizedKeys.keys = keys;
                  root.openssh.authorizedKeys.keys = keys;
                };

              # Enough to partition the NVMe and fetch this flake on the Pi.
              environment.systemPackages = with pkgs; [
                disko
                git
              ];

              # Throwaway media -- nothing persists across boots of it, so this
              # just tracks whatever release the image is built from.
              system.stateVersion = "26.05";
            }
          )
        ];
      };

      installerImage = self.nixosConfigurations.dubai-installer.config.system.build.sdImage;
    };
}
