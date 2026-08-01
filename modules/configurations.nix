{
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

  # Users, SSH, sudo, nix settings, agenix, journald and networking all come
  # from `nix-config` (see `capabilities/core`), same as every other host. Only
  # the Pi-specific bits live here.
  #
  # `raspberry-pi` is the host type rather than `server` because `server` turns
  # on the bootloader capability (systemd-boot/GRUB), which would fight the
  # Pi's `boot.loader.raspberry-pi` bootloader below.
  host = {
    hostname = "dubai";
    type.raspberry-pi.enable = true;

    # This is a headless Home Assistant appliance, and anything the aarch64
    # caches don't already have gets compiled on the Pi itself, so take only
    # the parts of the core capability that make the host administrable and
    # consistent with the rest of the homelab, and none of the optional
    # tooling. Its own small base package set is below.
    #
    # `default-programs` is the big one: ~100 curated CLI packages plus the
    # fish/nixvim/tmux/atuin configs (so the owner's login shell here is bash,
    # not fish). Flip it back to `true` if dubai ever becomes a machine anyone
    # works on interactively.
    default-programs.enable = false;
    # `docopts`/`pastel`/`ripgrep` plus the shell scripts in nix-config.
    custom-scripts.enable = false;
    # The prebuilt nix-index database is a large download that only pays off on
    # a machine where you go looking for packages by command name.
    nix-index-database.enable = false;
    # Desktop file/MIME associations; nothing headless uses them.
    xdg.enable = false;
  };

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
  # `networking.hostName` is set from `host.hostname` above, and
  # NetworkManager is enabled by `nix-config`'s networking capability.
  networking.useDHCP = lib.mkDefault true;

  # ------------------------------------------------------------------ #
  # Base packages                                                        #
  # ------------------------------------------------------------------ #
  # Deliberately just enough to debug the box over SSH, since none of
  # `nix-config`'s program sets are enabled above.
  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    curl
    wget
  ];

  # ------------------------------------------------------------------ #
  # State version                                                        #
  # ------------------------------------------------------------------ #
  # `nix-config` pins `system.stateVersion` to the release it currently tracks,
  # which is right for a host installed on that release and wrong for this one:
  # dubai was installed on 25.05, and stateVersion describes the state on disk,
  # not the nixpkgs being built against. It must not move for the life of the
  # install, so override it back.
  system.stateVersion = lib.mkForce "25.05";
}
