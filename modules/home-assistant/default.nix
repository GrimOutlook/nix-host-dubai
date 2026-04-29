{
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
    ];
    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = { };
      homeassistant = {
        name = "Longleaf";
        temperature_unit = "F";
        time_zone = "America/Chicago";
        unit_system = "us_customary";
        # On same level as automations
        "climate" = [
          {
            platform = "generic_thermostat";
            name = "Thermostat Heater Control";
            heater = "switch.heater";
            target_sensor = "switch.thermostat_thermometer";
            target_temp = 72;
          }
        ];
      };
    };
  };
}
