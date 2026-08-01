# dubai

Raspberry Pi 5 (aarch64, NVMe root) running Home Assistant.

## Services

| Service | Description |
| --- | --- |
| [home-assistant](https://github.com/home-assistant/core) | Home Automation (MQTT broker is hosted on `newyork`) |

## Layout

Like every other host in `nix-hosts`, dubai builds on the shared `nix-config`
flake and is configured through its `host.*` options. It is the one host that
does **not** go through `nix-config.lib.mkHost`: the Pi needs
`nixos-raspberrypi.lib.nixosSystem` as its builder, so `flake.nix` reproduces
what `mkHost` does by hand. See the comments there.

`nixos-raspberrypi` is pinned to the `nixos-<release>` branch matching
`nix-config`'s nixpkgs, and follows it — moving one to a new NixOS release
means moving the other in the same commit.

Only a deliberately small slice of `nix-config`'s core capability is enabled;
`modules/configurations.nix` lists what is turned off and why. The curated CLI
toolbox (`host.default-programs`) is off, which also means **the login shell
here is bash, not fish** like on the other hosts.

## Deploying

`nix develop` gives you a `deploy` command (`nh os switch` under the hood).
Run it on the Pi, or from a workstation, where it targets `root@dubai`:

```sh
deploy                          # builds locally, activates on dubai
deploy --build-host root@dubai  # build on the Pi instead of cross/emulated
```

> **One-time note for the first switch onto this config:** the shared config
> sets `users.mutableUsers = false` and owns the user list, so the old `pi`
> account goes away and is replaced by `grim` (same authorized keys, uid 1000).
> `AllowUsers` becomes `grim` and `root`, so run that first switch from the
> `pi` account or the console — afterwards it is `ssh grim@dubai`, and `root`
> from the LAN.

## TODO:

- [ ] Add services
    - [ ] [`cryptpad`](https://github.com/cryptpad/cryptpad)
    - [ ] [`booklore`](https://github.com/booklore-app/booklore). Replaces `colibre-web`.
    - [ ] [`komga`](https://github.com/gotson/komga)
    - [ ] [`immich`](https://github.com/immich-app/immich)
    - [ ] [`karakeep`](https://github.com/karakeep-app/karakeep) or maybe [`linkwarden`](https://linkwarden.app/)
- [ ] Look into replacing `plex` with [`jellyfin`](https://github.com/jellyfin/jellyfin)
- [ ] Look into [`matomo`](https://github.com/matomo-org/matomo) for analytics on hosted websites.
- [ ] Look into [`changedetection.io`](https://github.com/dgtlmoon/changedetection.io) for product availability checks
- [ ] [`healthchecks`](https://github.com/healthchecks/healthchecks): Listen for pings and sends alerts when pings are late.
- [ ] [`Radicale`](https://github.com/Kozea/Radicale):  A simple CalDAV (calendar) and CardDAV (contact) server.
- [ ] [`Open-WebUI`](https://github.com/ollama/ollama): Get up and running with Llama 3.3, DeepSeek-R1, Phi-4, Gemma 3, and other large language models.
- [ ] [`Ollama`](https://github.com/open-webui/open-webui): User-friendly AI Interface, supports Ollama, OpenAI API.
- [ ] [`HomeBox`](https://github.com/sysadminsmedia/homebox): Inventory and organization system built for the home user.
- [ ] [`grocy`](https://github.com/grocy/grocy): ERP beyond your fridge. Groceries & household management solution for your home.
- [ ] [`mainsail`](https://github.com/mainsail-crew/mainsail): Modern and responsive user interface for the Klipper 3D printer firmware. Control and monitor your printer from everywhere, from any device.
- [ ] [`Logseq`](https://github.com/logseq/logseq): A privacy-first, open-source platform for knowledge management and collaboration

### Maybe move these to a dedicated 3D printing host?
- [ ] [`spoolman`](https://github.com/Donkie/Spoolman): Keep track of your inventory of 3D-printer filament spools.
- [ ] [`octoprint`](https://github.com/OctoPrint/OctoPrint): Snappy web interface for controlling consumer 3D printers.
- [ ] [`fluidd`](https://github.com/fluidd-core/fluidd): Lightweight & responsive user interface for Klipper, the 3D printer firmware.
