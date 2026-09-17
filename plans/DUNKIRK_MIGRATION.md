# Plan: move Home Assistant from dubai to dunkirk

Status: cutover done on 2026-09-16. Home Assistant and zwave-js-ui run on
dunkirk. Remaining: re-point the Frigate integration and drop dunkirk's
`migration.nix`, then decommission dubai (see "Cleanup when dubai is retired").

Moving Home Assistant to dunkirk looks doable, and most of the config moves as
is:

- dunkirk has the same Home Assistant version (2026.5.4).
- None of the ports it needs (8123, 8091, 3000, 40000) are in use there.

Three things need a decision first. The live data, not the Nix config, is the
riskiest part.

## Decide first

1. **GPIO switches.** dubai sets up 8 Pi GPIO pins as switches (`Port5` …
   `Port26`), but nothing in the dashboards or automations uses them. dunkirk
   has no GPIO.
   - If something is physically wired to them, it needs a replacement (for
     example an ESPHome board or Z-Wave relays).
   - Otherwise, drop that config.
2. **Bluetooth.** dubai has a Bluetooth adapter (`hci0`), and Home Assistant's
   default config turns Bluetooth on. dunkirk has no adapter.
   - If any Bluetooth devices are in use, dunkirk needs a USB adapter or an
     ESPHome Bluetooth proxy.
   - This is unverified: the `deploy` user can't read `/var/lib/hass`.
3. **One box for both.** A dunkirk outage would take out cameras and home
   automation together. dunkirk does auto-reboot on a hang (watchdog).
   - Memory is fine. dunkirk has 31 GiB of RAM, and 20 GiB of the "used" memory
     is ZFS cache, which gives memory back when needed.
   - Home Assistant uses about 0.5 GiB.
   - Consider capping the ZFS cache (`zfs_arc_max`) anyway.

## Config changes

### dunkirk repo

- **Move the module.** Copy `modules/home-assistant/` from dubai into
  `modules/services/` and import it. The directory includes:
  - `zwave.nix`
  - the petlibro component and feeders
  - Lock Code Manager
  - the dashboards
  - the zwave-js-ui 11.24.0 override (dunkirk's nixpkgs ships 11.18.0)

  The module only needs `homelab` and `pkgs`, which dunkirk already provides.
- **Drop the Pi-only parts:**
  - the `gpio` component and switch config
  - the udev rules
  - the `gpio` group, `SupplementaryGroups`, `DeviceAllow` and
    `PrivateDevices = mkForce false`
- **Merge the duplicate secret.** `age.secrets.mqtt-password` is already defined
  on dunkirk for Frigate.
- **Keep** the living-room TV SSDP drop rule (`tcp dport 40000`).
- **Keep** `trusted_proxies` pointing at newyork.
- **Replace the Frigate proxy.** The dubai-only `frigate-homeassistant-proxy`
  (socat) and its firewall rule for dubai's IP (in
  `modules/services/frigate/default.nix`) are no longer needed. Home Assistant
  can reach Frigate locally (`127.0.0.1` or the container address
  `10.88.0.10:5000`).
- **dubai-only settings.** Decide whether dunkirk needs an equivalent of dubai's
  `waitOnline` and metrics settings. dunkirk is wired, so the wifi module isn't
  needed.

### homelab repo

- `hosts.nix`:
  - Move `services.homeassistant` from `dubai` to `dunkirk`. This drives the DNS
    names for `homeassistant.*`.
  - Remove `frigate.ports.homeAssistant`, which is only open to dubai's IP.
  - Update the comment on `zwave-dongle`.
- Later, remove the `dubai` host and its key from `secrets/secrets.nix`.

### newyork repo

- `modules/services/caddy.nix`: change the public
  (`homeassistant.grimaldifamily.org`) and local upstreams from `dubai:8123` to
  `dunkirk:8123`.
- `modules/services/glance/default.nix`: change the health-check URL.
- `modules/services/home-assistant-notify.nix`: change the VictoriaLogs query
  from `host:=dubai` to `host:=dunkirk`, and update the alert text and comments.
  If this is missed, failed-sign-in alerts stop without any error.

### Cleanup when dubai is retired

- washington `modules/services/victoriametrics.nix`: remove dubai from
  `nodeHosts`.
- In the hosts repo:
  - `flake.nix`: the dubai input and node
  - `.gitmodules`
  - the `mod? dubai` line in `JUSTFILE`
- Docs:
  - `nix/README.md`
  - `AGENTS.md`
  - `homelab/plans/DMZ_PLAN.md`
  - the dunkirk README
  - the paris wireguard comments

## Moving the data

This is manual work and needs root on both hosts. The `deploy` user can't do it.

1. **Back up first.** No automated backup of either directory was found in the
   repos.
   - Take a Home Assistant backup.
   - Tar `/var/lib/hass` and `/var/lib/private/zwave-js-ui`. The zwave-js-ui
     directory holds the S2 security keys and the node database; losing it means
     re-pairing every Z-Wave device.
2. **Stop both services on dubai** (`home-assistant` and `zwave-js-ui`) before
   starting them on dunkirk. The Z-Wave controller at
   `tcp://10.40.0.10:6638` must only have one zwave-js-ui connected at a time.
3. **Copy both directories to dunkirk.**
   - `/var/lib/hass` holds:
     - the `.storage` data: UI-configured integrations (MQTT, Z-Wave JS,
       Frigate, Lock Code Manager, mobile_app), users, registries and
       storage-mode dashboards
     - `home-assistant_v2.db` (history)
   - The `hass` user ID is fixed at 286 by NixOS, so ownership carries over.
   - zwave-js-ui runs as a dynamic user, so fix ownership of
     `/var/lib/private/zwave-js-ui` after copying.
4. **Deploy dunkirk, then fix things up in the UI:**
   - Frigate integration URL: use the local address.
   - Z-Wave JS: keep `ws://127.0.0.1:3000`.
   - Settings → System → Network:
     - Change the network adapter; it was dubai's wifi interface `wld0`.
     - Change any internal URL that says `dubai`.
   - Update the companion app's internal URL on each phone.
5. **Update the other repos.** Deploy homelab and newyork (DNS, Caddy, alerts).
   Check that the public and local URLs work, then retire dubai.

## Order of operations

1. Deploy dunkirk with Home Assistant staged: services disabled, or started only
   after the data is copied.
2. Back up and stop the services on dubai, then copy the data.
3. Start Home Assistant and zwave-js-ui on dunkirk and do the UI fix-ups.
4. Switch the homelab DNS and the newyork proxies and alerts.
5. Decommission dubai and clean up the references.

## To verify

- **Network access.** No firewall rule between VLANs mentioning dubai or the IoT
  network was found. Confirm dunkirk (10.20.0.4) can reach:
  - the Z-Wave dongle (10.40.0.10:6638)
  - the feeders over MQTT on newyork
  - the TV and other LAN devices, the same way dubai does
- **`stateVersion`.** dunkirk is on 25.11 and dubai on 25.05. Neither the Home
  Assistant module nor the zwave-js-ui module depends on it, so nothing changes.
