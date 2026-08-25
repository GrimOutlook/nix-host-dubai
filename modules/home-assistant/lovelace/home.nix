{ }:
{
  title = "Home";
  path = "home";
  icon = "mdi:home";
  cards = [
    {
      type = "vertical-stack";
      cards = [
        {
          type = "custom:advanced-camera-card";
          title = "Driveway";
          live.controls.builtin = false;
          cameras = [
            {
              camera_entity = "camera.driveway";
              live_provider = "go2rtc";
              go2rtc.modes = [ "mse" ];
            }
          ];
        }
        {
          type = "entities";
          title = "House Internet Usage";
          entities = [
            "sensor.wan_download_speed"
            "sensor.wan_upload_speed"
          ];
        }
      ];
    }
    {
      type = "vertical-stack";
      cards = [
        {
          # weather.nws is the declarative template entity defined
          # under config.weather below, built from NWS's own hourly
          # period forecast feed. Replaced weather.forecast_home (the `met`
          # integration that self-registered during onboarding) as
          # the data source; `met` is still installed but unused.
          #
          # Uses the custom weather-forecast-card (see weatherForecastCard
          # in default.nix) instead of the stock weather-forecast card --
          # its chart mode can plot apparent_temperature (feels-like) as
          # its own forecast line via the attribute-selector gear icon,
          # which neither the stock card nor weather-chart-card support.
          # weather.nws only implements the hourly/twice_daily forecast
          # types (see weather.nix), not daily, so forecast_types is
          # pinned to hourly to avoid an empty daily toggle.
          type = "custom:weather-forecast-card";
          entity = "weather.nws";
          default_forecast = "hourly";
          forecast_types = "hourly";
          current = {
            # "apparent_temperature" is a real attribute of weather.nws
            # (see weather.nix), so it's referenced by name. Precipitation
            # chance isn't -- it only exists as the standalone
            # sensor.nws_precipitation_chance template sensor -- so it's an
            # entity-only (nameless) item instead, which the card renders
            # as an arbitrary attribute sourced from that entity's state.
            show_attributes = [
              "apparent_temperature"
              {
                entity = "sensor.nws_precipitation_chance";
                label = "Precipitation Chance";
                icon = "mdi:weather-rainy";
              }
            ];
          };
          forecast = {
            mode = "chart";
            show_attribute_selector = true;
          };
        }
        {
          type = "markdown";
          title = "Active Weather Hazards";
          content = ''
            {% set alerts = state_attr('sensor.nws_active_alerts', 'features') | default([]) %}
            {% if alerts | count == 0 %}
            ✅ No active weather hazards.
            {% else %}
            {% for a in alerts %}
            **{{ a.properties.event }}**
            {{ a.properties.headline }}

            {% endfor %}
            {% endif %}
          '';
        }
      ];
    }
    {
      # https://github.com/timmaurice/lovelace-windy-card
      # Windy interactive weather map card, centered on the house's
      # coordinates with the radar overlay and a pin at the location.
      # `static_map = true` locks panning/zooming via the card's native
      # interaction toggle.
      type = "custom:windy-card";
      latitude = 34.7608002429598;
      longitude = -86.69216641164486;
      overlay = "radar";
      zoom = 8;
      show_marker = true;
      static_map = true;
      aspect_ratio = "4:3";
      metric_rain = "in";
      default_mode = "map_only";
    }
  ];
}
