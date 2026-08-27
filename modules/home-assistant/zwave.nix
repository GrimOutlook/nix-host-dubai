{ homelab, pkgs, ... }:
let
  # The SONOFF Z-Wave 800 PoE Dongle Max (Dongle-MZG23). Its DHCP reservation
  # lives in `homelab/hosts.nix` (MAC 1c:c3:ab:13:14:07), so the address comes
  # from there rather than being repeated here -- same as `wan.nix`.
  #
  # NOTE: this has to stay an *IP*, and must not become a hostname. The
  # upstream zwave-js-ui unit runs under `RootDirectory=%t/zwave-js-ui` with
  # only /nix/store bind-mounted, so the service has no /etc/resolv.conf and
  # cannot resolve names.
  dongleIp = homelab.hosts.dongle-mzg23.net.ip;

  # Settings that zwave-js-ui would otherwise only accept through its web
  # console, declared here instead. `ZWAVE_EXTERNAL_SETTINGS` points at a JSON
  # file whose keys are merged over the `zwave` section of the app's own
  # settings store on startup, and the corresponding UI fields are then locked
  # as "managed externally" -- so this file, not hand-clicking, is the source
  # of truth. See `api/lib/externalSettings.ts` upstream for the accepted keys.
  #
  # Deliberately NOT declared here: `securityKeys`/`securityKeysLongRange`.
  # This file lands world-readable in /nix/store, and the S2 keys are the
  # Z-Wave network's secrets. zwave-js-ui generates them into its own state
  # directory on first run, which is the right place for them. Declaring them
  # would mean agenix plus an added `BindReadOnlyPaths` on the unit, since
  # `RootDirectory` hides /run/agenix from the service.
  externalSettings = pkgs.writeText "zwave-js-ui-external-settings.json" (
    builtins.toJSON {
      # The Z-Wave JS Server that Home Assistant's `zwave_js` integration
      # speaks to. Bound to loopback: Home Assistant runs on this same Pi, so
      # this never needs to cross the network, and port 3000 stays closed in
      # the firewall below.
      serverEnabled = true;
      serverHost = "127.0.0.1";
      serverPort = 3000;
    }
  );
in
{
  # Z-Wave, driven by a SONOFF Z-Wave 800 PoE Dongle Max (Dongle-MZG23).
  #
  # Unlike a USB stick, this controller is a *network* device: it takes PoE on
  # its own ethernet port and republishes the Z-Wave serial protocol over TCP.
  # So nothing is plugged into this Pi, there is no /dev/tty* to grant, and no
  # udev rule to write -- zwave-js-ui just opens a socket to it.
  #
  # The data path is:
  #
  #   Z-Wave nodes
  #     <-radio->                  Dongle-MZG23
  #     <-tcp://<dongle-ip>:6638-> zwave-js-ui (this host)
  #     <-ws://127.0.0.1:3000->    Home Assistant `zwave_js` integration
  #
  # NOTE: the dongle's *MQTT* feature is not part of that path. It only
  # publishes the dongle's own settings/diagnostic entities (and any
  # eWeLink-Remote R5/S-mate sub-devices paired to it) via MQTT discovery.
  # Actual Z-Wave device control is the tcp://:6638 leg above. The MQTT
  # integration is already configured on this host for Frigate, so those
  # dongle entities will appear on their own if the dongle's MQTT client is
  # pointed at newyork's broker -- but it is not required for Z-Wave to work.
  #
  # `services.zwave-js` (bare zwave-js-server) deliberately isn't used here:
  # it passes `serialPort` to the binary as an argv and types it as
  # `types.path`, so a `tcp://` URL cannot be expressed at all. zwave-js-ui
  # takes its port from the environment instead, which a network controller
  # can actually satisfy.
  services.zwave-js-ui = {
    enable = true;

    # Required by the module, and used for nothing but `DeviceAllow=` on the
    # unit -- upstream documents it as "only used to grant permissions to the
    # device". There is no local serial device to grant, so point it at the
    # harmless one; `ZWAVE_PORT` below is what actually selects the
    # controller.
    serialPort = "/dev/null";

    settings = {
      # Web control panel: inclusion/exclusion, node config, OTA firmware.
      HOST = "0.0.0.0";
      PORT = "8091";

      # Forces the controller address, overriding whatever is in the app's
      # store, and implicitly sets `zwave.enabled = true` (see
      # `ZwaveClient.connect()` upstream). With this set, zwave-js-ui also
      # stops enumerating local serial ports and greys the field out in the
      # UI, which is what makes the choice declarative rather than advisory.
      ZWAVE_PORT = "tcp://${dongleIp}:6638";

      ZWAVE_EXTERNAL_SETTINGS = externalSettings;
    };
  };

  # The upstream unit runs the service inside `RootDirectory=%t/zwave-js-ui`
  # with only /nix/store bind-mounted, so it starts with no /etc at all and
  # therefore no resolver configuration. Everything Z-Wave still works -- the
  # controller is reached by IP and Home Assistant over loopback -- but the
  # daily firmware-update check calls out to firmware.zwave-js.io and fails
  # with "Cannot check for firmware updates: fetch failed (ZW0261)".
  #
  # Name resolution needs two files: resolv.conf supplies the nameserver, and
  # nsswitch.conf tells glibc to consult DNS for hosts. Both are read-only, and
  # neither widens the sandbox in any other direction.
  #
  # `BindReadOnlyPaths` is a list-valued unit option, so this appends to the
  # module's own `/nix/store` entry rather than replacing it.
  systemd.services.zwave-js-ui.serviceConfig.BindReadOnlyPaths = [
    "/etc/resolv.conf"
    "/etc/nsswitch.conf"
  ];

  # DNS alone isn't enough -- the check is an HTTPS fetch, and this Node is
  # built against the OpenSSL default CA store rather than a compiled-in one,
  # so inside the empty root it failed TLS with
  # UNABLE_TO_GET_ISSUER_CERT_LOCALLY even once the hostname resolved.
  #
  # Pointing at the bundle in the Nix store means no third bind mount:
  # /nix/store is already mounted in the sandbox, so the path just works. The
  # usual /etc/ssl/certs/ca-certificates.crt would NOT have -- it is a symlink
  # into /etc/static, which does not exist inside the root directory.
  systemd.services.zwave-js-ui.environment.SSL_CERT_FILE =
    "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  # The zwave-js-ui module has no `openFirewall`, so open the console port by
  # hand. Only the console needs to be reachable off-host: Home Assistant
  # reaches the WS server over loopback, so 3000 is deliberately left closed.
  networking.firewall.allowedTCPPorts = [ 8091 ];

  # zwave-js-ui persists its network key set, node database and cache under
  # StateDirectory=zwave-js-ui (/var/lib/zwave-js-ui). That is the Z-Wave
  # network's identity -- losing it means re-including every node -- so it
  # must be backed up, and must not be wiped between deploys.

  # All that is left to do by hand is add the integration in Home Assistant:
  # Settings > Devices & Services > Add Integration > Z-Wave, pointed at
  # ws://127.0.0.1:3000.
  services.home-assistant.extraComponents = [ "zwave_js" ];
}
