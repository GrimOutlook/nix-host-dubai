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
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      agenix,
      disko,
      nixpkgs,
      nixos-raspberrypi,
      ...
    }@inputs:
    {
      nixosConfigurations.dubai = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = inputs;
        modules = [
          agenix.nixosModules.default
          disko.nixosModules.disko
          ./configurations.nix
          ./disko.nix
        ];
      };

      # Build the SD card image with:
      # nix build .#sdImages.yourHostname
      sdImages.dubai = self.nixosConfigurations.dubai.config.system.build.sdImage;
    };
}
