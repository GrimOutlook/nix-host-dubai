{
  config,
  lib,
  nixos-raspberrypi,
  pkgs,
  ...
}:
{
  imports = with nixos-raspberrypi.nixosModules; [
    raspberry-pi-5.base
    raspberry-pi-5.bluetooth # remove if you don't need BT
  ];

  # ------------------------------------------------------------------ #
  # Boot                                                                 #
  # ------------------------------------------------------------------ #
  # kernelboot is the default for Pi 5 and supports generation rollbacks
  boot.loader.raspberry-pi.bootloader = "kernel";

  # ------------------------------------------------------------------ #
  # Hardware                                                             #
  # ------------------------------------------------------------------ #
  hardware.raspberry-pi.config = {
    all.options = {
      hdmi_force_hotplug = {
        # HDMI force hotplug so the display works even without a monitor at boot
        enable = true;
        value = true;
      };
      # GPU memory split (MB) — tune as needed
      gpu_mem = {
        enable = true;
        value = 128;
      };
      # existing options...
      # Boot order: 0x6 = NVMe, 0x1 = SD, 0x4 = USB, 0xF = Reboot
      # Full order: try NVMe first, fall back to SD
      boot_order = {
        enable = true;
        value = "0xf461";
      };
      dtparam_pciex1 = {
        enable = true;
        value = true;
      };
    };
  };

  # ------------------------------------------------------------------ #
  # Networking                                                           #
  # ------------------------------------------------------------------ #
  networking = {
    hostName = "dubai";
    useDHCP = lib.mkDefault true;
    networkmanager.enable = true;
  };

  # ------------------------------------------------------------------ #
  # Users                                                                #
  # ------------------------------------------------------------------ #
  users.users.pi = {
    isNormalUser = true;
    initialHashedPassword = "$y$j9T$B1twhXiwjRRijxI5.sKdD.$ezIbul2rpq59cT/zHUDgeVygGVXcq01LDiyb4GFc79/";
    extraGroups = [
      "wheel"
      "gpio"
      "i2c"
      "spi"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHw6y8P3yv2xkLTl93JhF4DiCHjWrk0RzlY1Iwdz7tJL grim@paris"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # ------------------------------------------------------------------ #
  # SSH                                                                  #
  # ------------------------------------------------------------------ #
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # ------------------------------------------------------------------ #
  # Nix settings                                                         #
  # ------------------------------------------------------------------ #
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "@wheel"
    ];
    # Pull aarch64 builds from the community cache
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Bg="
    ];
  };

  # ------------------------------------------------------------------ #
  # Base packages                                                        #
  # ------------------------------------------------------------------ #
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    curl
    wget
  ];

  system.stateVersion = "25.05";
}
