{ }:
{
  # `lovelaceConfig` below only registers the Home view as an *extra*
  # sidebar dashboard (services.home-assistant.config.lovelace.dashboards.nixos-lovelace)
  # -- it does NOT replace HA's built-in default/primary dashboard, which
  # stays in storage mode and is what actually loads first. The built-in
  # primary dashboard's reserved url_path is "lovelace" -- defining a
  # `dashboards.lovelace` entry (as opposed to any other name) reconfigures
  # that primary dashboard itself rather than adding another sidebar
  # entry, making the Home view the initial page. (The legacy top-level
  # `lovelace.mode` does the same thing but is deprecated as of HA
  # 2026.8.) The module-generated `dashboards.nixos-lovelace` entry is
  # nulled out so it doesn't linger as a redundant second sidebar item.
  lovelace.dashboards = {
    nixos-lovelace = null;
    lovelace = {
      mode = "yaml";
      filename = "ui-lovelace.yaml";
      # `title` is required by the lovelace integration's config schema
      # even for the primary dashboard -- omitting it fails validation,
      # which cascades into `frontend` failing to load entirely and HA
      # falling into recovery mode.
      title = "Longleaf";
      icon = "mdi:view-dashboard";
    };
  };

  lovelaceConfig = {
    title = "Longleaf";
    views = [
      {
        title = "Home";
        path = "home";
        icon = "mdi:home";
        cards = [
          {
            type = "vertical-stack";
            cards = [
              {
                type = "picture-entity";
                title = "Driveway";
                entity = "camera.driveway";
                camera_view = "live";
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
            type = "iframe";
            aspect_ratio = "75%";
            # https://embed.windy.com -- Windy's public embeddable widget,
            # centered on the house's coordinates with the radar overlay.
            # `marker=true` drops a pin at detailLat/detailLon (the house).
            url = "https://embed.windy.com/embed2.html?lat=34.7608002429598&lon=-86.69216641164486&detailLat=34.7608002429598&detailLon=-86.69216641164486&width=650&height=450&zoom=8&level=surface&overlay=radar&product=radar&menu=&message=true&marker=true&calendar=now&pressure=&type=map&location=coordinates&detail=&metricWind=default&metricTemp=default&metricRain=in&radarRange=-1";
            # Windy's embed2 iframe has no URL param to disable dragging, so
            # this blocks all pointer interaction with the card instead --
            # the map still animates/updates, it just can't be panned/zoomed.
            card_mod.style = ''
              ha-card {
                pointer-events: none;
              }
            '';
          }
        ];
      }
      {
        title = "Cameras";
        path = "cameras";
        icon = "mdi:cctv";
        cards = [
          {
            type = "picture-entity";
            title = "Driveway";
            entity = "camera.driveway";
            camera_view = "live";
          }
          {
            type = "picture-entity";
            title = "Front Door";
            entity = "camera.front_door";
            camera_view = "live";
          }
          {
            type = "picture-entity";
            title = "Back Gate";
            entity = "camera.back_gate";
            camera_view = "live";
          }
        ];
      }
    ];
  };
}
