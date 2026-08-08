{
  lib,
  pkgs,
  homelab,
  ...
}:
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
    # There was no UI-managed (storage-mode) dashboard on dubai to preserve
    # when this was switched to YAML mode, so nothing was migrated. Setting
    # lovelaceConfig implicitly puts the main panel in `yaml` mode, which
    # means it's no longer editable from the HA UI; change it here instead.
    lovelaceConfig = {
      title = "Longleaf";
      views = [
        {
          title = "Weather";
          path = "weather";
          icon = "mdi:weather-lightning";
          cards = [
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
          ];
        }
      ];
    };
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
      "sensor" = [
        {
          # National Weather Service active-alerts feed for the house's
          # coordinates. NWS asks for an identifying User-Agent on every
          # request (no API key needed) -- an empty/generic one gets rate
          # limited or blocked, so this is the address recommended in their
          # docs (any contact string works, it's just for their abuse
          # reports).
          platform = "rest";
          name = "NWS Active Alerts";
          resource = "https://api.weather.gov/alerts/active?point=34.7608002429598,-86.69216641164486";
          method = "GET";
          headers = {
            User-Agent = "Home Assistant (dominic.j.grimaldi@gmail.com)";
            Accept = "application/geo+json";
          };
          # Value is just a count; the binary_sensor below re-parses the
          # attribute for the actual event names.
          value_template = "{{ value_json.features | length }}";
          json_attributes = [ "features" ];
          scan_interval = 60;
        }
      ];
      # Modern `template:` integration syntax -- the legacy
      # `binary_sensor: [{ platform = "template"; ... }]` form is deprecated
      # and stops working in HA 2026.6.
      template = [
        {
          binary_sensor = map (
            {
              id,
              friendlyName,
              event,
            }:
            {
              name = friendlyName;
              default_entity_id = "binary_sensor.${id}";
              device_class = "safety";
              # One sensor per NWS alert `event` string we care about --
              # https://api.weather.gov/alerts/active?point=... entries carry
              # exactly this name in properties.event.
              state = ''
                {{ state_attr('sensor.nws_active_alerts', 'features')
                   | default([])
                   | selectattr('properties.event', 'equalto', '${event}')
                   | list | count > 0 }}
              '';
              availability = "{{ states('sensor.nws_active_alerts') not in ['unknown', 'unavailable'] }}";
            }
          ) [
            {
              id = "tornado_warning";
              friendlyName = "Tornado Warning";
              event = "Tornado Warning";
            }
            {
              id = "tornado_watch";
              friendlyName = "Tornado Watch";
              event = "Tornado Watch";
            }
            {
              id = "severe_thunderstorm_warning";
              friendlyName = "Severe Thunderstorm Warning";
              event = "Severe Thunderstorm Warning";
            }
            {
              id = "severe_thunderstorm_watch";
              friendlyName = "Severe Thunderstorm Watch";
              event = "Severe Thunderstorm Watch";
            }
          ];
        }
      ];
      automation = [
        {
          alias = "Frigate alert notification";
          description = "Push notification when Frigate creates a new alert review item.";
          trigger = [
            {
              platform = "mqtt";
              topic = "frigate/reviews";
            }
          ];
          # Frigate publishes "new", "update", and "end" messages over a review
          # item's lifetime. A review item's severity is NOT fixed when it is
          # created: Frigate frequently opens an item as "detection" and only
          # upgrades it to "alert" in a later "update" message (once the object
          # is confirmed / enters an alert zone). Filtering on
          # `type == 'new' and severity == 'alert'` therefore silently drops
          # every alert that escalates after creation -- which is most of them.
          #
          # Instead, fire once on the transition INTO alert severity: any
          # non-"end" message where severity just became "alert" (before != alert,
          # after == alert). This catches both alerts that start as alerts and
          # alerts promoted from detection, while the `tag` (review id) below
          # dedupes any repeats.
          condition = [
            {
              condition = "template";
              value_template = ''
                {{ trigger.payload_json['type'] != 'end'
                   and trigger.payload_json['after']['severity'] == 'alert'
                   and trigger.payload_json['before']['severity'] != 'alert' }}
              '';
            }
          ];
          action = [
            {
              service = "notify.mobile_app_pixel_10";
              data = {
                title = "Frigate Alert";
                message = "{{ trigger.payload_json['after']['data']['objects'] | sort | join(', ') | title }} detected on {{ trigger.payload_json['after']['camera'] }}";
                data = {
                  # Relative path, not the public https URL. The companion app
                  # downloads the notification image before it displays the
                  # notification, so a slow fetch delays the whole alert. A
                  # relative /api/... path is resolved against whichever HA URL
                  # the app is already connected to (the internal LAN URL when
                  # home), avoiding the WAN -> caddy(newyork) -> HA(dubai) ->
                  # frigate(pyongyang) round trip the hard-coded external URL
                  # forced on every notification.
                  image = "/api/frigate/notifications/{{ trigger.payload_json['after']['id'] }}/thumbnail.jpg";
                  tag = "{{ trigger.payload_json['after']['id'] }}";

                  # Delivery priority. Without these, the push is sent to FCM at
                  # normal priority, which Android is free to hold until the
                  # device next leaves Doze -- which is why alerts "arrive" all
                  # at once the moment the phone is unlocked. Exempting the
                  # companion app from battery optimization does NOT fix this:
                  # the priority is chosen by the *sender*, not the app.
                  # `priority: high` + `ttl: 0` tells FCM to wake the device and
                  # deliver now, or drop it rather than queue it. This is the
                  # same class of push messaging apps use, and it is what the
                  # companion docs prescribe for notifications that must ring
                  # before the screen is turned on.
                  ttl = 0;
                  priority = "high";

                  # Dedicated notification channel so these can be given their
                  # own importance/sound without affecting every other HA
                  # notification. NOTE: on Android 8+, a channel's importance is
                  # fixed the FIRST time the channel is seen and can afterwards
                  # only be *lowered* -- so this must be a channel name that has
                  # not been used before (the default is "General"). If the
                  # importance ever needs raising again, change this string or
                  # adjust the channel in Android's notification settings.
                  channel = "Frigate Alerts";
                  importance = "high";
                };
              };
            }
          ];
          mode = "single";
        }
      ];
    };
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
