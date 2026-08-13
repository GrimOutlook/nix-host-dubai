{
  lib,
  pkgs,
  homelab,
  ...
}:
let
  # PETLIBRO PLAF301 feeders, redirected from Petlibro's own cloud to
  # newyork's local mosquitto broker instead -- see ~/projects/
  # feeder-jailbreak (topic layout and command/event JSON schemas, both
  # reverse-engineered via firmware disassembly, not documented by Petlibro
  # anywhere) and hosts/newyork/modules/services/mosquitto/default.nix (the
  # broker-side ACL these devices actually authenticate against). HA
  # connects to that same broker as `frigate` (readwrite on everything, see
  # the age.secrets comment below), so no separate credential is needed
  # here -- these entities just add topics on top of that existing
  # connection. `feed-extra` (homelab/hosts.nix has its MAC) is excluded:
  # no device ID/credentials have been captured for it yet, unlike the
  # three below.
  feeders = [
    {
      name = "feed-jem";
      deviceId = "AF0601030298F0C1320D";
    }
    {
      name = "feed-willow";
      deviceId = "AF0600310007DF0B19802Q";
    }
    {
      name = "feed-fern";
      deviceId = "AF06013A96214C47U";
    }
  ];
  feederDevice =
    { name, deviceId }:
    {
      identifiers = [ "plaf301_${deviceId}" ];
      inherit name;
      manufacturer = "PETLIBRO";
      model = "PLAF301";
    };
  # "feed-jem" -> "feed_jem", matching HA's own slugification of entity
  # names -- used to reference the paired input_number helper (below) from
  # inside the Feed Now button's payload_press template by a name we
  # control directly, rather than guessing how HA would slug it.
  feederKey = name: builtins.replaceStrings [ "-" ] [ "_" ] name;
  # dl/PLAF301/{deviceId}/device/{ntp,ota,config,event,service,system}/{sub,post}
  # -- `sub` topics are commands published TO the device, `post` topics are
  # the device reporting TO us. `heart`/`event` aren't in that six-name set
  # (heartbeats and structured events get their own leaves), confirmed by
  # direct observation in feeder-jailbreak/FINDINGS.md's live session
  # capture rather than by the naming pattern above.
  feederTopic = deviceId: leaf: "dl/PLAF301/${deviceId}/device/${leaf}";
  # Every feeder multiplexes many event kinds onto one `event/post` topic
  # (GRAIN_OUTPUT_EVENT, WAREHOUSE_DOOR_EVENT, PET_IDENTIFY_EVENT, ...) --
  # an entity that only cares about one kind renders `None` for every other
  # kind, which is MQTT-integration shorthand for "discard this update,
  # keep my last known state" rather than overwriting it with garbage.
  feederBinarySensors =
    { name, deviceId }:
    [
      {
        name = "Online";
        unique_id = "${deviceId}_online";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "heart/post";
        value_template = "{{ 'ON' if value_json.cmd == 'HEARTBEAT' else 'OFF' }}";
        payload_on = "ON";
        payload_off = "OFF";
        # Heartbeats land every 60-70s (feeder-jailbreak/FINDINGS.md) --
        # 150s covers one dropped beat before flagging offline, without
        # being so long a real outage takes minutes to notice.
        expire_after = 150;
        device_class = "connectivity";
      }
      {
        # execStep's GRAIN_BLOCKING/GRAIN_BLOCKED/GRAIN_STUCK values
        # (mqtt_command_reference.md's "Common Error/Status Strings") are
        # jam states reported on the same GRAIN_OUTPUT_EVENT stream "Last
        # Fed" below already reads -- unlike the ERROR_EVENT-sourced
        # sensors further down, this one gets a real binary on/off because
        # its clear condition is just as well-documented as its set
        # condition (a normal GRAIN_END/finished completion).
        name = "Feed Jam";
        unique_id = "${deviceId}_feed_jam";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "event/post";
        value_template = ''
          {%- if value_json.cmd == 'GRAIN_OUTPUT_EVENT' -%}
            {%- if value_json.execStep in ['GRAIN_BLOCKING', 'GRAIN_BLOCKED', 'GRAIN_STUCK'] -%}
              {{- 'ON' -}}
            {%- elif value_json.execStep == 'GRAIN_END' or value_json.finished -%}
              {{- 'OFF' -}}
            {%- else -%}
              {{- None -}}
            {%- endif -%}
          {%- else -%}
            {{- None -}}
          {%- endif -%}
        '';
        payload_on = "ON";
        payload_off = "OFF";
        device_class = "problem";
      }
    ];
  feederSensors =
    { name, deviceId }:
    [
      {
        name = "Signal Strength";
        unique_id = "${deviceId}_rssi";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "heart/post";
        value_template = "{{ value_json.rssi }}";
        device_class = "signal_strength";
        unit_of_measurement = "dBm";
        state_class = "measurement";
        entity_category = "diagnostic";
      }
      {
        name = "Last Fed";
        unique_id = "${deviceId}_last_fed";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "event/post";
        # The device doesn't put its own wall-clock time on this event, so
        # this is "when HA saw the finish" rather than "when the device
        # says it finished" -- close enough given events arrive within a
        # second or two of the real thing. Same caveat applies to every
        # other now().isoformat()-based sensor below.
        value_template = ''
          {%- if value_json.cmd == 'GRAIN_OUTPUT_EVENT' and value_json.finished -%}
            {{- now().isoformat() -}}
          {%- else -%}
            {{- None -}}
          {%- endif -%}
        '';
        device_class = "timestamp";
      }
      {
        # PET_IDENTIFY_EVENT fires when an RFID collar comes into range.
        # State is the raw tag, not a pet name -- there's no memberId ->
        # pet-name mapping anywhere in this config (ADD_OR_UPDATE_RFID_SERVICE,
        # which would set one, has never been sent), so calibrationTag is
        # the only thing guaranteed to mean something.
        name = "Pet Last Scanned";
        unique_id = "${deviceId}_last_scanned";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "event/post";
        value_template = ''
          {%- if value_json.cmd == 'PET_IDENTIFY_EVENT' -%}
            {{- value_json.calibrationTag -}}
          {%- else -%}
            {{- None -}}
          {%- endif -%}
        '';
        json_attributes_topic = feederTopic deviceId "event/post";
        json_attributes_template = ''
          {%- if value_json.cmd == 'PET_IDENTIFY_EVENT' -%}
            {{- {'member_id': value_json.memberId} -}}
          {%- else -%}
            {{- None -}}
          {%- endif -%}
        '';
        icon = "mdi:paw";
      }
      {
        # MACHINE_INFRARED_EVENT: the bowl's break-beam/presence sensor.
        # FINDINGS.md only confirms *that* this fires, not any field names
        # inside it (unlike the events above, which were seen with full
        # payloads) -- so this reports "when it last fired" rather than
        # guessing at a boolean field that isn't documented anywhere.
        name = "Bowl Activity";
        unique_id = "${deviceId}_bowl_activity";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "event/post";
        value_template = ''
          {%- if value_json.cmd == 'MACHINE_INFRARED_EVENT' -%}
            {{- now().isoformat() -}}
          {%- else -%}
            {{- None -}}
          {%- endif -%}
        '';
        device_class = "timestamp";
        entity_category = "diagnostic";
      }
      {
        # ERROR_EVENT covers everything in mqtt_command_reference.md's
        # "Common Error/Status Strings" that isn't the feed jam above --
        # LOW_FOOD, LOW_BATTERY, BARN_OPEN_DOOR_ERROR/BARN_CLOSE_DOOR_ERROR,
        # OFFLINE/NETWORK_*. One generic "last error" sensor instead of a
        # binary_sensor per condition: none of these have a documented
        # clear/resolved counterpart event the way the feed jam does, so a
        # binary_sensor here could only ever latch on and never honestly
        # turn back off. This just reports the most recent one instead of
        # claiming to know current state.
        name = "Last Error";
        unique_id = "${deviceId}_last_error";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "event/post";
        value_template = ''
          {%- if value_json.cmd == 'ERROR_EVENT' -%}
            {{- value_json.errorMsg -}}
          {%- else -%}
            {{- None -}}
          {%- endif -%}
        '';
        json_attributes_topic = feederTopic deviceId "event/post";
        json_attributes_template = ''
          {%- if value_json.cmd == 'ERROR_EVENT' -%}
            {{- {'error_code': value_json.errorCode, 'at': now().isoformat()} -}}
          {%- else -%}
            {{- None -}}
          {%- endif -%}
        '';
        icon = "mdi:alert";
        entity_category = "diagnostic";
      }
      {
        # DEVICE_START_EVENT fires once per boot -- useful mainly to
        # confirm an unexpected reboot happened at all (restartReason,
        # powerCycle) rather than anything ongoing.
        name = "Last Boot";
        unique_id = "${deviceId}_last_boot";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "event/post";
        value_template = ''
          {%- if value_json.cmd == 'DEVICE_START_EVENT' -%}
            {{- now().isoformat() -}}
          {%- else -%}
            {{- None -}}
          {%- endif -%}
        '';
        json_attributes_topic = feederTopic deviceId "event/post";
        json_attributes_template = ''
          {%- if value_json.cmd == 'DEVICE_START_EVENT' -%}
            {{- {
              'hardware_version': value_json.hardwareVersion,
              'software_version': value_json.softwareVersion,
              'power_cycle': value_json.powerCycle,
              'restart_reason': value_json.restartReason,
            } -}}
          {%- else -%}
            {{- None -}}
          {%- endif -%}
        '';
        device_class = "timestamp";
        entity_category = "diagnostic";
      }
    ];
  feederCovers =
    { name, deviceId }:
    [
      {
        # `cover`/device_class `door` fits the lid better than a plain
        # switch: SWITCH_DOOR_SERVICE's own closeDoorTimeSec auto-close
        # timer means the device flips itself back to closed on its own a
        # few seconds after opening (confirmed live, feeder-jailbreak/
        # FINDINGS.md "2026-08-12 (latest)"), and WAREHOUSE_DOOR_EVENT
        # reports that self-close the same as a commanded one -- so this
        # entity's state tracks reality either way, not just what HA asked
        # for.
        name = "Lid";
        unique_id = "${deviceId}_lid";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_open = builtins.toJSON {
          cmd = "SWITCH_DOOR_SERVICE";
          barnDoorState = 1;
        };
        payload_close = builtins.toJSON {
          cmd = "SWITCH_DOOR_SERVICE";
          barnDoorState = 0;
        };
        state_topic = feederTopic deviceId "event/post";
        value_template = ''
          {%- if value_json.cmd == 'WAREHOUSE_DOOR_EVENT' -%}
            {{- 'open' if value_json.triggerType == 'COVER_OPEN' else 'closed' -}}
          {%- else -%}
            {{- None -}}
          {%- endif -%}
        '';
        device_class = "door";
      }
    ];
  feederButtons =
    { name, deviceId }:
    [
      {
        name = "Feed Now";
        unique_id = "${deviceId}_feed_now";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        # Unlike the fixed payloads elsewhere in this file, this one has to
        # be a live template (not builtins.toJSON at build time) -- it
        # reads the paired input_number helper's *current* value each time
        # the button is pressed, defaulting to 1 portion if that helper is
        # ever unknown/non-numeric (e.g. right after a HA restart, before
        # its state has been restored).
        payload_press = ''
          {{ {'cmd': 'MANUAL_FEEDING_SERVICE', 'grainNum': states('input_number.${feederKey name}_feed_amount') | int(1)} | tojson }}
        '';
      }
    ];
  # House coordinates, shared by every NWS API call below (the alerts feed
  # and the forecast feed) so they can't drift out of sync with each other.
  nwsLat = "34.7608002429598";
  nwsLon = "-86.69216641164486";
  # NWS's forecast API is keyed by a grid office + x/y cell, not lat/lon
  # directly -- these came from a one-time lookup against
  # https://api.weather.gov/points/${nwsLat},${nwsLon} and won't change for
  # a fixed point, so it's cheaper to hardcode them than to chain two REST
  # calls (Home Assistant's rest sensor can't template its resource URL
  # from another entity's state).
  nwsGridOffice = "HUN";
  nwsGridX = "59";
  nwsGridY = "44";
  # NWS asks for an identifying User-Agent on every request (no API key
  # needed) -- an empty/generic one gets rate limited or blocked, so this is
  # the address recommended in their docs (any contact string works, it's
  # just for their abuse reports).
  nwsUserAgent = "Home Assistant (dominic.j.grimaldi@gmail.com)";
  # Shared by the weather entity's current-condition template and each
  # forecast period below -- maps NWS's own icon vocabulary
  # (https://api.weather.gov/icons) to Home Assistant's weather condition
  # enum. `skc`/`few` (clear/few clouds) are the only codes HA distinguishes
  # by day vs night (sunny/clear-night); everything else maps the same
  # regardless of daylight, so they're handled separately from this map.
  nwsConditionMap = ''
    {% set code_map = {
      'sct': 'partlycloudy', 'bkn': 'cloudy', 'ovc': 'cloudy',
      'wind_skc': 'windy', 'wind_few': 'windy', 'wind_sct': 'windy-variant',
      'wind_bkn': 'windy-variant', 'wind_ovc': 'windy-variant',
      'snow': 'snowy', 'rain_snow': 'snowy-rainy', 'rain_sleet': 'snowy-rainy',
      'snow_sleet': 'snowy-rainy', 'fzra': 'snowy-rainy', 'rain_fzra': 'snowy-rainy',
      'snow_fzra': 'snowy-rainy', 'sleet': 'snowy-rainy',
      'rain': 'rainy', 'rain_showers': 'rainy', 'rain_showers_hi': 'rainy',
      'tsra': 'lightning-rainy', 'tsra_sct': 'lightning-rainy', 'tsra_hi': 'lightning-rainy',
      'tornado': 'exceptional', 'hurricane': 'exceptional', 'tropical_storm': 'exceptional',
      'dust': 'exceptional', 'smoke': 'exceptional', 'haze': 'exceptional',
      'hot': 'sunny', 'cold': 'snowy', 'blizzard': 'snowy', 'fog': 'fog'
    } %}
    {% macro nws_condition(period) %}
      {%- set code = period.icon.split('/')[-1].split('?')[0].split(',')[0] -%}
      {%- if code in ['skc', 'few'] -%}
        {{ 'sunny' if period.isDaytime else 'clear-night' }}
      {%- else -%}
        {{ code_map.get(code, 'partlycloudy') }}
      {%- endif -%}
    {% endmacro %}
  '';
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
    # used below to disable pointer-events so the embedded map can't be
    # dragged/panned (Windy's embed2 iframe has no URL param for this).
    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      card-mod
    ];
    # There was no UI-managed (storage-mode) dashboard on dubai to preserve
    # when this was switched to YAML mode, so nothing was migrated. Setting
    # lovelaceConfig implicitly puts the main panel in `yaml` mode, which
    # means it's no longer editable from the HA UI; change it here instead.
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
                  # under config.weather below, built from NWS's own 12-hour
                  # period forecast (day/night pairs) -- hence twice_daily,
                  # not daily. Replaced weather.forecast_home (the `met`
                  # integration that self-registered during onboarding) as
                  # the data source; `met` is still installed but unused.
                  type = "weather-forecast";
                  entity = "weather.nws";
                  forecast_type = "twice_daily";
                }
                {
                  type = "horizontal-stack";
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
    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = { };
      # `lovelaceConfig` above only registers the Home view as an *extra*
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
      # The NWS forecast sensors below carry the full raw `periods` array
      # (156 entries for the hourly feed) as a state attribute purely so the
      # weather entity's templates can read it via state_attr() -- there's
      # no need for the recorder to persist that on every poll, and at that
      # size it doesn't fit the recorder's 16KiB per-attribute limit anyway
      # (silently dropped either way, but logged as a warning every time).
      recorder.exclude.entities = [
        "sensor.nws_forecast"
        "sensor.nws_hourly_forecast"
      ];
      # Paired with each feeder's "Feed Now" button (config.mqtt.button
      # below) -- a plain local helper, not an MQTT entity itself, since
      # there's nothing to report to or read from the device until the
      # button is actually pressed.
      input_number = lib.listToAttrs (
        map (
          f:
          lib.nameValuePair "${feederKey f.name}_feed_amount" {
            name = "${f.name} Feed Amount";
            min = 1;
            max = 10;
            step = 1;
            initial = 1;
            icon = "mdi:bowl-mix";
            unit_of_measurement = "portions";
          }
        ) feeders
      );
      # One Device per feeder (Settings > Devices & Services > MQTT), built
      # from the `feeders` list up top. Uses the existing `frigate` MQTT
      # connection (see age.secrets.mqtt-password above) -- no separate
      # broker credential needed for HA itself.
      mqtt = {
        binary_sensor = lib.concatMap feederBinarySensors feeders;
        sensor = lib.concatMap feederSensors feeders;
        cover = lib.concatMap feederCovers feeders;
        button = lib.concatMap feederButtons feeders;
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
          resource = "https://api.weather.gov/alerts/active?point=${nwsLat},${nwsLon}";
          method = "GET";
          headers = {
            User-Agent = nwsUserAgent;
            Accept = "application/geo+json";
          };
          # Value is just a count; the binary_sensor below re-parses the
          # attribute for the actual event names.
          value_template = "{{ value_json.features | length }}";
          json_attributes = [ "features" ];
          scan_interval = 60;
        }
        {
          # Feeds the "NWS" template weather entity below (config.weather) --
          # NWS's own 12-hour period forecast (day/night pairs) for the house's
          # coordinates. This is the same data https://forecast.weather.gov
          # itself is built from.
          platform = "rest";
          name = "NWS Forecast";
          resource = "https://api.weather.gov/gridpoints/${nwsGridOffice}/${nwsGridX},${nwsGridY}/forecast";
          method = "GET";
          headers = {
            User-Agent = nwsUserAgent;
            Accept = "application/geo+json";
          };
          # The periods array is what actually matters; the sensor's own
          # state is just "when was this last generated by NWS" so it's
          # something other than the whole JSON blob.
          value_template = "{{ value_json.properties.updateTime }}";
          device_class = "timestamp";
          json_attributes_path = "$.properties";
          json_attributes = [ "periods" ];
          # NWS regenerates this forecast a handful of times a day, not
          # continuously -- polling every 30m is plenty and stays well clear
          # of any abuse-rate concerns.
          scan_interval = 1800;
        }
        {
          # Same forecast, but NWS's hourly periods (unlike the 12-hour ones
          # above) carry relativeHumidity/dewpoint -- this exists purely to
          # feed the weather entity's humidity_template, which the `template`
          # integration's schema requires even though nothing on this
          # dashboard displays it directly.
          platform = "rest";
          name = "NWS Hourly Forecast";
          resource = "https://api.weather.gov/gridpoints/${nwsGridOffice}/${nwsGridX},${nwsGridY}/forecast/hourly";
          method = "GET";
          headers = {
            User-Agent = nwsUserAgent;
            Accept = "application/geo+json";
          };
          value_template = "{{ value_json.properties.updateTime }}";
          device_class = "timestamp";
          json_attributes_path = "$.properties";
          json_attributes = [ "periods" ];
          scan_interval = 1800;
        }
      ]
      # WAN upload/download throughput, read straight from newyork's own
      # Prometheus (hosts/newyork/modules/services/prometheus.nix) rather than
      # adding a second exporter path -- node_exporter there already scrapes
      # eth1 (the WAN NIC, see hosts/newyork/modules/default.nix's `iface`).
      # `rate(...)[5m]` (not 1m) because Prometheus's scrape_interval here is
      # the module default of 1m; a 1m rate window can span too few samples
      # and intermittently return no data.
      ++
        map
          (
            {
              name,
              device,
            }:
            {
              platform = "rest";
              inherit name;
              resource = "http://newyork.${homelab.domains.local}:${toString homelab.hosts.newyork.services.prometheus.ports.web.number}/api/v1/query";
              method = "GET";
              params.query = "rate(node_network_${device}_bytes_total{host=\"newyork\",device=\"eth1\"}[5m]) * 8 / 1000000";
              value_template = "{{ (value_json.data.result[0].value[1] | float(0)) | round(2) }}";
              unit_of_measurement = "Mbit/s";
              device_class = "data_rate";
              state_class = "measurement";
              scan_interval = 15;
            }
          )
          [
            {
              name = "WAN Download Speed";
              device = "receive";
            }
            {
              name = "WAN Upload Speed";
              device = "transmit";
            }
          ];
      # Modern `template:` integration syntax -- the legacy
      # `platform: template` form (for both binary_sensor and weather below)
      # is deprecated and stops working in HA 2026.6.
      template = [
        {
          binary_sensor =
            map
              (
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
              )
              [
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
        {
          # Declarative weather entity sourced entirely from the "NWS
          # Forecast"/"NWS Hourly Forecast" rest sensors above, instead of
          # the UI-config-flow-only `met`/`nws` integrations (neither has
          # any Nix-expressible configuration).
          weather = [
            {
              name = "NWS";
              attribution = "Forecast data from the National Weather Service (api.weather.gov).";
              # Only NWS's 12-hour period forecast is available from this feed
              # (no separate current-observation call), so "current" conditions
              # here are really "the nearest upcoming period" -- the same
              # simplification the daily card was already making with `met`.
              # Every `{% %}` control tag below is `-`-trimmed on both sides, and
              # every final `{{ }}` output is too (`{{- ... -}}`) -- Jinja only
              # auto-strips whitespace *adjacent to `{% %}` tags* (HA's template
              # environment sets trim_blocks/lstrip_blocks), not around `{{ }}`
              # expressions or Nix's own indentation of the string below, so
              # without explicit trims here every value would come back with
              # stray leading/trailing whitespace -- harmless for the numeric
              # fields (Python's int()/float() ignore it) but breaks an exact
              # enum match like `condition`.
              condition = ''
                ${nwsConditionMap}
                {%- set periods = state_attr('sensor.nws_forecast', 'periods') or [] -%}
                {{- nws_condition(periods[0]) if periods else None -}}
              '';
              temperature = ''
                {%- set periods = state_attr('sensor.nws_forecast', 'periods') or [] -%}
                {{- periods[0].temperature if periods else None -}}
              '';
              wind_speed = ''
                {%- set periods = state_attr('sensor.nws_forecast', 'periods') or [] -%}
                {%- set nums = (periods[0].windSpeed | regex_findall('[0-9]+') | map('int') | list) if periods else [] -%}
                {{- ((nums | sum) / (nums | length)) if nums | length > 0 else None -}}
              '';
              wind_bearing = ''
                {%- set periods = state_attr('sensor.nws_forecast', 'periods') or [] -%}
                {{- (periods[0].windDirection or None) if periods else None -}}
              '';
              humidity = ''
                {%- set periods = state_attr('sensor.nws_forecast_hourly', 'periods') or [] -%}
                {{- periods[0].relativeHumidity.value if periods else None -}}
              '';
              # Pressure/visibility aren't in any of NWS's forecast feeds (only
              # its per-station observations, a different endpoint this doesn't
              # call), so the entity just omits those attributes.
              forecast_twice_daily = ''
                ${nwsConditionMap}
                {%- set ns = namespace(forecast=[]) -%}
                {%- for period in state_attr('sensor.nws_forecast', 'periods') or [] -%}
                  {%- set nums = period.windSpeed | regex_findall('[0-9]+') | map('int') | list -%}
                  {%- set ns.forecast = ns.forecast + [{
                    'datetime': period.startTime,
                    'is_daytime': period.isDaytime,
                    'condition': nws_condition(period),
                    'temperature': period.temperature,
                    'precipitation_probability': period.probabilityOfPrecipitation.value | default(0),
                    'wind_speed': ((nums | sum) / (nums | length)) if nums | length > 0 else 0,
                    'wind_bearing': period.windDirection or None,
                  }] -%}
                {%- endfor -%}
                {{- ns.forecast -}}
              '';
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
