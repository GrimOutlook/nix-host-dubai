{
  lib,
  pkgs,
  homelab,
  ...
}:
let
  feedersConfig = import ./feeders.nix { inherit lib; };
  weatherConfig = import ./weather.nix { };
  lovelaceModule = import ./lovelace.nix { inherit lib pkgs; };
  wanConfig = import ./wan.nix { inherit homelab; };
  automationsConfig = import ./automations.nix { };
  # Pinned to 3.3.0: the newest release whose minimum Home Assistant
  # (2026.5.0) is satisfied by this host's nixpkgs. 4.x+ require newer HA,
  # and 6.0 has a breaking migration -- read its upgrade guide before bumping.
  lockCodeManagerVersion = "3.3.0";
  lockCodeManagerComponent = pkgs.buildHomeAssistantComponent {
    owner = "raman325";
    domain = "lock_code_manager";
    version = lockCodeManagerVersion;
    format = "unzip";
    sourceRoot = ".";
    src = pkgs.fetchurl {
      url = "https://github.com/raman325/lock_code_manager/releases/download/${lockCodeManagerVersion}/lock_code_manager.zip";
      hash = "sha256-rzjnrHjKnIC+XOX00BWCd5z5N22j1doM0ByndJb05KY=";
    };
  };
  # The integration serves this dashboard strategy itself, but resources are in
  # YAML mode here, so it must also be registered via customLovelaceModules.
  lockCodeManagerLovelaceModule = pkgs.stdenvNoCC.mkDerivation {
    pname = "lock-code-manager";
    version = lockCodeManagerVersion;
    dontUnpack = true;
    installPhase = ''
      install -Dm444 \
        ${lockCodeManagerComponent}/custom_components/lock_code_manager/www/generated/lock-code-manager.js \
        $out/lock-code-manager.js
    '';
  };
  # Not packaged in nixpkgs (unlike the cards under
  # pkgs.home-assistant-custom-lovelace-modules below), so they are fetched
  # directly here -- upstream publishes a single prebuilt JS bundle per
  # GitHub release, which is simpler and just as reproducible as a
  # source build for a one-file lovelace card.
  weatherForecastCard = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "weather-forecast-card";
    version = "1.1.0";
    src = pkgs.fetchurl {
      url = "https://github.com/troinine/ha-weather-forecast-card/releases/download/v${version}/weather-forecast-card.js";
      hash = "sha256-a++9rfQFeH2rWdix6JBhQpraseSS89Rgn5LyboeGjJQ=";
    };
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out
      cp $src $out/${pname}.js
    '';
    meta = {
      description = "Weather forecast card for Home Assistant with hourly/daily toggle and trend charts";
      homepage = "https://github.com/troinine/ha-weather-forecast-card";
      license = lib.licenses.mit;
    };
  };
  windyCard = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "windy-card";
    version = "1.14.0";
    src = pkgs.fetchurl {
      url = "https://github.com/timmaurice/lovelace-windy-card/releases/download/${version}/windy-card.js";
      hash = "sha256-3esF1BHySMPTcjMw4Iiij7aKuqYzaI3g5B/2OxRsZ14=";
    };
    dontUnpack = true;
    installPhase = ''
      mkdir -p $out
      cp $src $out/${pname}.js
    '';
    meta = {
      description = "Windy.com weather map and spot forecast card for Home Assistant";
      homepage = "https://github.com/timmaurice/lovelace-windy-card";
      license = lib.licenses.mit;
    };
  };
  # The NixOS Home Assistant module uses a card's version as its resource
  # cache-buster. Include the exact package output identity so rebuilt bundles
  # cannot reuse a stale parent file with different hashed child chunks.
  advancedCameraCard =
    let
      package = pkgs.home-assistant-custom-lovelace-modules.advanced-camera-card;
      cacheVersion = "${package.version}-${builtins.substring 0 12 (builtins.hashString "sha256" package.outPath)}";
    in
    pkgs.stdenvNoCC.mkDerivation {
      pname = package.pname;
      version = cacheVersion;
      dontUnpack = true;
      installPhase = ''
        mkdir -p "$out"
        cp -R ${package}/. "$out/"
      '';
    };
  petlibroComponent = pkgs.buildHomeAssistantComponent {
    owner = "grim";
    domain = "petlibro";
    version = "1.0.0";
    src = ./custom_components/petlibro;
  };
in
{
  # zwave.nix is a NixOS module rather than a Home Assistant `config` fragment
  # like the `import`s above -- it configures the zwave-js-ui *service* that
  # sits between Home Assistant and the Z-Wave controller, so it has to go
  # through `imports`.
  imports = [ ./zwave.nix ];

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
    # Lock Code Manager imports all of its lock providers (ZHA, Matter, ...)
    # up front, even though this host only uses Z-Wave JS. Keep those
    # integrations disabled; provide only the Python dependencies needed for
    # the imports, including those of Home Assistant Hardware.
    extraPackages = ps: [
      ps.zha
      ps.python-matter-server
      ps.universal-silabs-flasher
      ps.ha-silabs-firmware-client
    ];
    customComponents =
      with pkgs.home-assistant-custom-components;
      [
        frigate
        gpio
      ]
      ++ [
        petlibroComponent
        lockCodeManagerComponent
      ];
    # weather-forecast-card (see weatherForecastCard above) renders weather.nws
    # -- its chart mode can plot apparent_temperature (feels-like) as its own
    # forecast line, which the previously-used stock weather-forecast card and
    # weather-chart-card can't do at all.
    # windy-card embeds Windy interactive map & forecast directly.
    customLovelaceModules =
      with pkgs.home-assistant-custom-lovelace-modules;
      [
        advancedCameraCard
      ]
      ++ [
        weatherForecastCard
        windyCard
        lockCodeManagerLovelaceModule
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

  # The Living Room TV (`living-room-tv`, MAC 7c:0a:3f:79:bb:8a in
  # homelab/hosts.nix) constantly probes Home Assistant's UPnP/SSDP
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
  #
  # The address is taken from `homelab` rather than written out: it is assigned
  # by `assignIps`, which hands out addresses in sorted-hostname order, so
  # every host after an inserted name shifts by one. A literal here silently
  # stops matching the TV and starts matching whichever host inherited the
  # address -- which is exactly what had happened to the previous hardcoded
  # `10.1.0.4` (by then `brussels`, while the TV had moved to `10.1.0.18`).
  networking.firewall.extraInputRules = ''
    ip saddr ${homelab.hosts.living-room-tv.net.ip} tcp dport 40000 drop
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
