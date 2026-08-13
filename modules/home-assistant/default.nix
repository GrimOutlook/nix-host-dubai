{
  lib,
  pkgs,
  homelab,
  ...
}:
let
  feedersConfig = import ./feeders.nix { inherit lib; };
  weatherConfig = import ./weather.nix { };
  lovelaceModule = import ./lovelace.nix { };
  wanConfig = import ./wan.nix { inherit homelab; };
  automationsConfig = import ./automations.nix { };
in
{
  # Shared credential for the MQTT broker hosted on newyork (see nix-homelab).
  # Home Assistant no longer supports configuring the MQTT broker connection
  # declaratively (broker/username/password moved to UI-only config flow), so
  # this just makes the password available for the one-time manual setup:
  # Settings > Devices & Services > Add Integration > MQTT
  #   broker:   newyork (homelab.hosts.newyork.net.ip)
  #   port:     1883
  #   username: frigate
  #   password: `cat /run/agenix/mqtt-password` on this host
  age.secrets.mqtt-password.file = "${homelab}/secrets/mqtt-password.age";

  services.home-assistant = {
    enable = true;
    openFirewall = true;
    extraComponents = [
      # Components required to complete the onboarding
      "analytics"
      "google_translate"
      "met"
      "radio_browser"
      "shopping_list"
      # Recommended for fast zlib compression
      # https://www.home-assistant.io/integrations/isal
      "isal"

      "climate"
      "generic_thermostat"
      "switch"

      "mqtt"
    ];
    customComponents = with pkgs.home-assistant-custom-components; [
      frigate
      gpio
    ];
    # card-mod lets the Windy iframe's `ha-card` wrapper be styled directly --
    # used in lovelace.nix to disable pointer-events so the embedded map can't be
    # dragged/panned (Windy's embed2 iframe has no URL param for this).
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      card-mod
    ];

    lovelaceConfig = lovelaceModule.lovelaceConfig;

    config = lib.mkMerge [
      {
        # Includes dependencies for a basic setup
        # https://www.home-assistant.io/integrations/default_config/
        default_config = { };

        lovelace = lovelaceModule.lovelace;

        # Requests are reverse-proxied by caddy on newyork before reaching
        # this host, so Home Assistant needs to trust it to honor the
        # X-Forwarded-* headers it sets. Without this, external access
        # through the proxy fails with "400: Bad Request" complaining that
        # Home Assistant isn't set up for reverse proxies.
        # https://www.home-assistant.io/integrations/http/#reverse-proxies
        http = {
          use_x_forwarded_for = true;
          trusted_proxies = [ homelab.hosts.newyork.net.ip ];
        };
        homeassistant = {
          name = "Longleaf";
          temperature_unit = "F";
          time_zone = "America/Chicago";
          unit_system = "us_customary";

          customize = { };
        };
        "switch" = [
          {
            platform = "gpio";
            ports = {
              "5" = "Port5";
              "6" = "Port6";
              "13" = "Port13";
              "16" = "Port16";
              "19" = "Port19";
              "20" = "Port20";
              "21" = "Port21";
              "26" = "Port26";
            };
          }
        ];
      }
      feedersConfig
      weatherConfig
      wanConfig
      automationsConfig
    ];
  };

  # The Living Room TV (busan, MAC 7c:0a:3f:79:bb:8a in homelab/hosts.nix,
  # DHCP-reserved at 10.1.0.4) constantly probes Home Assistant's UPnP/SSDP
  # event-callback port (tcp/40000) -- roughly 200 SYNs an hour. HA is not
  # actually consuming that traffic (no DLNA/cast integration is configured),
  # so we do NOT want to open the port; we just want to stop it flooding the
  # kernel firewall log. Every unmatched packet falls through to the firewall's
  # "refused connection: " log rule before being dropped, so a silent drop for
  # exactly this source+port short-circuits the probes before they get logged.
  #
  # Note: this is an nftables rule because `nix-config`'s networking capability
  # turns `networking.nftables.enable` on. `extraInputRules` lands in the
  # `input-allow` chain, which the `input` chain jumps into *before* it reaches
  # the logging rules, so `drop` here is terminal and never gets logged. (The
  # equivalent iptables `extraCommands` is silently ignored under the nftables
  # backend, so it must not be used here.) The TV connects over IPv4, so
  # matching on `ip saddr` is sufficient.
  networking.firewall.extraInputRules = ''
    ip saddr 10.1.0.4 tcp dport 40000 drop
  '';

  users.groups.gpio.members = [ "hass" ];
  # Ensure the gpio group owns the device
  services.udev.extraRules = ''
    SUBSYSTEM=="gpio", GROUP="gpio", MODE="0660"
    KERNEL=="gpiochip*", GROUP="gpio", MODE="0660"
  '';

  systemd.services.home-assistant.serviceConfig = {
    SupplementaryGroups = [ "gpio" ];
    DeviceAllow = [
      "/dev/gpiochip0 rw"
      "/dev/gpiochip1 rw"
      "/dev/gpiochip2 rw"
      "/dev/gpiochip3 rw"
    ];
    PrivateDevices = lib.mkForce false;
  };
}
