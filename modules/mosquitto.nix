{ config, ... }:
{
  age.secrets.mqtt-password.file = ../secrets/mqtt-password.age;

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        port = 1883;
        users.hass = {
          passwordFile = config.age.secrets.mqtt-password.path;
          acl = [ "readwrite #" ];
        };
      }
    ];
  };

  # Reachable by the external Frigate NVR host publishing detection events.
  networking.firewall.allowedTCPPorts = [ 1883 ];
}
