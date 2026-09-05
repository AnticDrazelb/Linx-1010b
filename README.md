# Linx 1010B Linux

A build system for a stripped-down Debian + GNOME image targeting the **Linx 1010B**
tablet — an Intel Atom Z3735F (Bay Trail-T) machine with 2 GB of RAM, a 32 GB eMMC,
and a 32-bit UEFI implementation sitting in front of a 64-bit CPU.

The goal is a desktop that is actually usable on this hardware in 2026: nothing
installed that the machine cannot use, everything installed that it needs, and every
known Bay Trail performance trap addressed by default.

> **Status: this repository has not been built or run on hardware yet.**
> Every script is syntax-checked and the hardware facts are sourced (see
> [docs/hardware.md](docs/hardware.md)), but no ISO has been produced from it and
> no tablet has booted it. Treat the first build as a bring-up exercise, and see
> [Known unknowns](#known-unknowns) below for the specific things most likely to
> need adjusting.

---

## Quick start

On a Debian or Ubuntu build host (not the tablet — it does not have the disk space).
**On Windows, use WSL2** — see [docs/build-on-windows.md](docs/build-on-windows.md);
on macOS, use the Docker path in the same document:

```bash
make deps        # install debootstrap, xorriso, grub-efi-ia32-bin, ...
sudo make iso    # ~20-40 min, produces out/linx1010b-gnome-trixie-YYYYMMDD.iso
```

Write it to a USB stick and boot the tablet:

```bash
sudo dd if=out/linx1010b-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

On the tablet: power off, hold **Volume Up** and press **Power**, choose
**Boot Manager**, pick the USB device. Then from the live desktop:

```bash
sudo linx-install
```

Full detail in [docs/install.md](docs/install.md).

---

## The one thing that makes this tablet difficult

The Linx 1010B has a **64-bit CPU behind 32-bit UEFI firmware**. Its firmware looks
for `\EFI\BOOT\BOOTIA32.EFI` and physically cannot load a 64-bit PE binary, so a
stock amd64 ISO produces "no bootable device" and no explanation whatsoever.

This image builds **both** `BOOTIA32.EFI` (i386-efi GRUB — what the tablet runs) and
`BOOTX64.EFI` (so the same ISO boots a normal PC, which makes testing far easier).
The kernel and the entire userland remain 64-bit; only the bootloader is 32-bit.
GRUB performs the mode switch itself.

Details and the reasoning: [docs/boot-32bit-uefi.md](docs/boot-32bit-uefi.md).

---

## What this image does differently

| Area | Decision | Why |
|---|---|---|
| Base | Debian 13 `trixie`, `debootstrap --variant=minbase` | Exact control over every package; no metapackage pulls in 1.4 GB |
| Desktop | Hand-picked GNOME, **not** `gnome-core` | ~60 packages instead of ~450 |
| Animations | Off by default | Largest single perceived-speed win on Gen7 graphics |
| Search indexing | Tracker masked and configured to index nothing | Sustained CPU + eMMC writes for a feature that costs more than it is worth here |
| Swap | zram, lz4, sized to 100% of RAM | 2 GB is not enough without it; lz4 because CPU is scarcer than RAM |
| Audio | `snd-intel-dspcfg dsp_driver=2` (force legacy SST) | SOF enumerates a card that plays nothing on Bay Trail |
| Backlight | `pwm_lpss` forced into the initramfs | Without it there is no backlight device at all |
| Journal | Volatile (RAM) | Continuous writes to a wear-limited 32 GB eMMC |
| I/O | `mq-deadline`, weekly `fstrim`, no `discard` | Continuous TRIM makes deletes slow on this controller |
| Filesystem | ext4 `noatime,commit=60` | Fewer small synchronous writes; GRUB reads it reliably |
| Services | ~20 units masked (ModemManager, PackageKit, avahi, apt timers…) | Each is resident RAM or a timer wakeup on a machine with neither to spare |

The full list, with the cost of each decision, is in
[docs/performance.md](docs/performance.md).

---

## Hardware support

| Device | Status | Notes |
|---|---|---|
| Display 1280×800 | Works | i915, Gen7 Bay Trail |
| Touchscreen | Works | Goodix, ACPI `GDIX1001` — no firmware blob, no DMI quirk |
| Backlight | Works **with the `pwm_lpss` initramfs fix** | Included here |
| Audio | Works **with `dsp_driver=2`** | Included here |
| Wi-Fi | Works | Realtek SDIO, `firmware-realtek` |
| Bluetooth | Works | `bluez` + Realtek BT firmware |
| Battery / charging | Works | AXP288 PMIC |
| Auto-rotate | Works | `iio-sensor-proxy` + accelerometer |
| Keyboard dock | Works | Standard USB HID |
| microSD, USB, micro-HDMI | Works | |
| **Cameras** | **Do not work** | Atomisp; Windows-only drivers. Blacklisted so they stop wasting memory and spewing errors |

Sources and per-device detail: [docs/hardware.md](docs/hardware.md).

---

## Tools included in the image

| Command | Purpose |
|---|---|
| `linx-report` | Full hardware/status dump; `linx-report audio`, `…display`, etc. |
| `linx-gpe-scan` | **Finds an ACPI GPE interrupt storm** — a firmware bug that pins a kworker thread near 100% CPU forever. The GPE number varies per unit so it cannot be shipped as a default. `--apply` writes the fix. |
| `linx-tune` | Flips the documented trade-offs: C-states, Wi-Fi power saving, CPU governor, GDM vs LightDM, persistent logs, printing |
| `linx-install` | Installs the live system to the eMMC |

`linx-gpe-scan` is the one to run first on a new install. If your unit has a GPE
storm, it is the largest single performance problem on the machine and nothing else
you do will matter as much.

---

## Repository layout

```
build/            Staged, resumable image builder
  build.sh          Entry point:  sudo ./build/build.sh [stage...]
  config.sh         All tunables (suite, mirror, arch, compression)
  stages/           00-deps 10-bootstrap 20-packages 30-overlay
                    40-tuning 50-cleanup 60-squashfs 70-efi 80-iso
config/packages/  The curated package lists (what is kept)
overlay/          Files dropped verbatim into the rootfs (the tuning itself)
tools/            linx-report, linx-gpe-scan, linx-tune
installer/        linx-install.sh
kernel/           Optional stripped custom kernel (fragment + builder)
docker/           Containerised build environment (Windows / macOS)
docs/             Hardware reference, boot theory, install, performance, fixes
```

The build is **resumable** — `work/rootfs` persists between runs, so iterating on
the overlay is `sudo ./build/build.sh 30 40 50 60 70 80`, not a re-bootstrap.

---

## Expectations

This is a 2015 budget tablet with a 1.33 GHz in-order Atom and 2 GB of RAM. With
everything above applied it should give a responsive GNOME desktop for web browsing,
documents, media playback and terminal work. It will not be fast at anything that is
genuinely CPU-bound, and a modern JavaScript-heavy site with a dozen tabs will still
run it out of memory.

If GNOME still feels too heavy on 2 GB after `linx-tune greeter-lite`, the honest
answer is that a lighter desktop (Xfce, LXQt) will give you more headroom — but
GNOME with animations disabled and Tracker masked is genuinely usable, which is what
this image is for.

## Known unknowns

Things most likely to need adjustment on first contact with real hardware:

1. **Audio codec variant.** These tablets shipped with `rt5640` most commonly, but
   `rt5645`/`rt5651` exist. `dsp_driver=2` is codec-independent, but if there is no
   sound run `linx-report audio` and check which machine driver bound.
2. **Panel orientation.** Some Bay Trail panels are mounted portrait and need
   `fbcon=rotate:` and a `video=` panel-orientation argument. There is no DRM quirk
   upstream for this model, so GNOME + `iio-sensor-proxy` is relied on instead. The
   GRUB config carries the commented-out override.
3. **Wi-Fi MAC address.** Many of these units have no MAC in the Wi-Fi EEPROM and
   present a new random one each boot. NetworkManager is configured to use the
   permanent address; if yours has none, see [docs/troubleshooting.md](docs/troubleshooting.md).
4. **The `-e --interval:appended_partition_2:all::` xorriso incantation** in stage 80
   is the standard modern form, but xorriso is version-sensitive. If mastering fails,
   that line is the first suspect.

## Licence

Build scripts and configuration in this repository: MIT (see `LICENSE`).
The image they produce contains Debian packages under their own licences, including
non-free firmware, which is required for Wi-Fi, Bluetooth and audio on this device.
