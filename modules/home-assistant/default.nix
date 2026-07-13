{ lib, pkgs, homelab, ... }:
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
    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = { };
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

        customize = {
          # # On same level as automations
          # "climate" = [
          #   {
          #     platform = "generic_thermostat";
          #     name = "Thermostat Heater Control";
          #     heater = "switch.heater";
          #     target_sensor = "switch.thermostat_thermometer";
          #     target_temp = 72;
          #   }
          # ];
        };
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
    };
  };
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
