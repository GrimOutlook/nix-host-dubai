{
  homelab,
  host,
  ...
}:
let
  port = host.services.homeassistant.ports.web;
in
{
  services.home-assistant = {
    enable = true;
    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = { };
    };
  };
  networking.firewall.extraInputRules = homelab.lib.firewallAllowLocal port.number;
}
