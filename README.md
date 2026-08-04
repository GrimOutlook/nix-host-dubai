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

## Installing from removable media

For when dubai won't boot and there is nothing to `deploy` onto.

### 1. Build and flash the installer

```sh
nix build .#installerImage
zstdcat result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

Built on x86_64 this goes through aarch64 binfmt emulation, so expect it to
take a while; most of the closure substitutes from the caches.

**Prefer an SD card.** `BOOT_ORDER` is `0xf461`, read right-to-left:
SD → NVMe → USB → restart. The firmware only moves to the next device when the
current one has *no bootable image*; a broken-but-present NVMe install still
has a valid `config.txt` and `kernel.img`, so the firmware commits to it and
hands off to the kernel before USB ever gets a turn. There is no fallback after
handoff. SD is checked first, so it always wins.

USB media is fine on a Pi 5 — it just needs the NVMe to lose its turn:

- pull the NVMe (simplest, and the drive is already accessible), or
- rename `config.txt`/`kernel.img` on its firmware partition from another
  machine — though if you can mount it, fixing `os_prefix=` is faster than
  installing at all, or
- put `4` first in the EEPROM's `BOOT_ORDER`, which needs a booted system.

> Note the `boot_order` entry in `modules/configurations.nix` is inert — it is
> written into `config.txt`, but boot order lives in the bootloader EEPROM, so
> the real value may differ from the one quoted above. Check with
> `rpi-eeprom-config` (it ships in this image). `0xf461` is also the Pi 5
> factory default.

### 2. Boot it

Ethernet, then find the lease on newyork; the installer comes up as
`dubai-installer` with the paris/berlin keys on both `nixos` and `root`. There
is also console autologin if you have a monitor on it.

### 3a. Repair in place — keeps Home Assistant's state

This reinstalls the system and rewrites `/boot/firmware` without touching the
NVMe's contents. Mount what disko already made, then push a closure built on a
workstation so the Pi never has to evaluate the flake (which would need
credentials for the private `homelab` input):

```sh
# on the installer
mount -o subvol=/rootfs,compress=zstd /dev/disk/by-partlabel/NIXROOT /mnt
mkdir -p /mnt/nix /mnt/home /mnt/boot/firmware
mount -o subvol=/nix,compress=zstd,noatime /dev/disk/by-partlabel/NIXROOT /mnt/nix
mount -o subvol=/home,compress=zstd    /dev/disk/by-partlabel/NIXROOT /mnt/home
mount /dev/disk/by-partlabel/disk-disk1-firmware /mnt/boot/firmware

# on a workstation
system=$(nix build --print-out-paths .#nixosConfigurations.dubai.config.system.build.toplevel)
nix copy --to ssh://root@dubai-installer "$system"

# back on the installer
nixos-install --root /mnt --system "$system" --no-root-password
```

### 3b. Clean install — **wipes the NVMe**

Only when you actually want to start over. `modules/disko.nix` formats with
`-f`, so everything on that disk goes, including `/var/lib/hass` — back it up
first if it still reads.

```sh
# from a workstation, against the booted installer
nix run github:nix-community/nixos-anywhere -- \
  --flake .#dubai --target-host root@dubai-installer --build-on local
```

Or on the installer itself: `disko --mode destroy,format,mount
/mnt/etc/nixos/modules/disko.nix`, then `nixos-install` as in 3a.

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
