# Building the image

## Host requirements

A Debian or Ubuntu machine (or container) with root. **Not the tablet** — it does
not have the disk space or the patience.

- ~12 GB free disk
- The build downloads ~1.5 GB of packages
- 20–40 minutes on a modern desktop

```bash
make deps
```

installs: `debootstrap squashfs-tools xorriso mtools dosfstools rsync grub-common
grub-efi-ia32-bin grub-efi-amd64-bin`.

`grub-efi-ia32-bin` is the one people miss. It provides `/usr/lib/grub/i386-efi`,
without which the build produces an ISO the tablet cannot boot. Stage 00 fails
loudly if it is absent.

## Running a build

```bash
sudo make iso                  # everything
sudo ./build/build.sh          # same thing
sudo ./build/build.sh 30 40 50 60 70 80   # re-run selected stages only
```

Configuration is in `build/config.sh`; every value can be overridden from the
environment:

```bash
sudo SUITE=forky LOCALE=de_DE.UTF-8 KEYMAP=de ./build/build.sh
```

## Stages

| Stage | Does |
|---|---|
| `00-deps` | Verifies host tools, including the i386-efi GRUB modules |
| `10-bootstrap` | `debootstrap --variant=minbase`, writes apt sources and the no-recommends policy |
| `20-packages` | Installs each list in `config/packages/` separately, so a failure names the list |
| `30-overlay` | rsyncs `overlay/` into the rootfs; installs `linx-*` tools |
| `40-tuning` | Locale, user, service masking, dconf compile, initramfs |
| `50-cleanup` | Strips docs/locales/firmware, purges caches, blanks machine-id |
| `60-squashfs` | zstd-19 squashfs, extracts kernel + initrd for the ISO |
| `70-efi` | **Builds BOOTIA32.EFI and BOOTX64.EFI**, writes the live GRUB menu, packs the ESP |
| `80-iso` | xorriso, UEFI-only hybrid ISO, SHA256 |

Stages are **sourced**, not executed, so they share config, helpers and the mount
tracking that the cleanup trap depends on.

The build is **resumable**: `work/rootfs` persists. Iterating on the overlay is
stages 30–80, not a re-bootstrap. `rm -rf work/rootfs` forces a fresh one.

## Why Debian rather than Fedora

For a *stock* install on this tablet, Fedora is currently the least painful
option and is what most guides recommend. This project is not a stock install.

`debootstrap --variant=minbase` plus an explicit package list gives exact control
over what ends up in the image, which is the entire point here. Fedora's
equivalent (`livemedia-creator` + kickstart) is heavier to script and harder to
strip to this degree. Debian also packages `grub-efi-ia32-bin` cleanly, which is
the critical dependency.

## Design notes

**No `live-build`.** It can be made to emit a `bootia32.efi`, but the dual-ESP
layout matters too much here to leave to a tool whose EFI handling changes
between releases. Stage 70 is explicit about exactly what goes in the ESP.

**UEFI-only ISO.** The tablet has no CSM and cannot boot in legacy BIOS mode, so
a BIOS El Torito entry would add a `grub-pc-bin` build dependency for a path this
hardware can never take. *Consequence:* the ISO will not boot an old BIOS-only PC.

**zstd squashfs, not xz.** About 8% larger, decompresses roughly 4× faster. Every
page fault against the live filesystem costs a decompression, and on a 1.33 GHz
Atom that is on the critical path.

**Service starts are blocked during the build** via `policy-rc.d`, removed in
stage 50.

## Custom kernel (optional)

```bash
cd kernel && ./build-kernel.sh
sudo ./build/build.sh 20 30 40 50 60 70 80
```

If `kernel/out/` contains `linux-image-*.deb`, stage 20 installs those and drops
`linux-image-amd64` from the package list. Opt-in purely by the files existing.

See [../kernel/README.md](../kernel/README.md).

## Troubleshooting the build

**Stage 00 fails on `/usr/lib/grub/i386-efi`** — `apt install grub-efi-ia32-bin`.

**Stage 80 xorriso failure** — the `-e --interval:appended_partition_2:all::`
form is version-sensitive. Check `xorriso -version`; older versions want
`-e EFI/BOOT/BOOTIA32.EFI -no-emul-boot` against a file in the ISO tree instead.

**`rm -rf work` refuses / hangs** — the chroot's pseudo-filesystems are still
mounted. `make distclean` checks for this. Manually:
`sudo umount -R work/rootfs/{proc,sys,dev,run}`.

**Package not found** — a package name changed between Debian releases. Build
output names the list file that failed; fix it in `config/packages/`.
