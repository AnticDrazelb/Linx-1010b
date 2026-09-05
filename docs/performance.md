# What was stripped, what was added, and what each costs

Every item here is a trade-off. This document states the cost as well as the
benefit, so you can reverse anything that does not suit you — most of it is one
`linx-tune` command away.

Rough targets on a Linx 1010B (Z3735F, 2 GB, eMMC). **These are design targets,
not measurements — nothing in this repository has been benchmarked on hardware yet.**

| | Stock Debian GNOME | This image (intended) |
|---|---|---|
| Installed size | ~5.5 GB | ~2.8 GB |
| RAM at idle desktop | ~950 MB | ~550 MB |
| Boot to login | ~55 s | ~30 s |

---

## Memory: the binding constraint

2 GB is below what GNOME wants. Three things make it work.

**zram swap, lz4, sized to 100% of RAM.**
Compressed swap in RAM turns swapping from "seek on a slow eMMC" into "a memcpy
plus a decompress". lz4 rather than zstd deliberately: zstd compresses about 30%
better but costs far more CPU to decompress, and on a 1.33 GHz Silvermont core
CPU is scarcer than RAM. Typical compression ratio for desktop anonymous memory
with lz4 is around 2.5:1, so 2 GB of zram holds roughly 5 GB of pages.

**`vm.swappiness=180`.**
Counter-intuitive if you learned that low swappiness is good. That rule is for
disk swap. With zram, reclaiming an anonymous page is *cheaper* than evicting a
page-cache page you are about to re-read from eMMC. 180 is the value the kernel's
own zram documentation recommends; the maximum is 200.

**`vm.page-cluster=0`.**
zram gains nothing from readahead — faulting in neighbouring pages just burns CPU
decompressing pages nobody asked for.

*Cost:* CPU spent on compression. On this machine it is clearly the right trade,
but a genuinely CPU-bound workload will feel it.

---

## Storage: a slow, small, wear-limited eMMC

- **`noatime`** — otherwise every read causes a metadata write.
- **`commit=60`** — batches ext4 journal commits instead of every 5 s, cutting
  small synchronous writes considerably. *Cost:* up to 60 s of work lost on an
  unclean shutdown. The journal itself is kept; disabling it for a few percent of
  throughput on a tablet that will be hard-powered-off is a bad trade.
- **Weekly `fstrim.timer`, not the `discard` mount option** — continuous TRIM
  makes every delete slow on this controller. Batch TRIM gets the same benefit.
- **`mq-deadline`, `nr_requests=64`** — keeps an interactive read from queueing
  behind a large writeback burst.
- **`vm.dirty_ratio=10` / `dirty_background_ratio=5`** — the defaults allow a
  writeback burst large enough to stall the desktop for *seconds* at ~40 MB/s.
- **Volatile journal (logs in RAM)** — a persistent journal is a continuous
  background write load. *Cost:* `journalctl -b -1` does not work. Reverse with
  `linx-tune logs-persistent` when debugging a boot problem.
- **`/tmp` on tmpfs, 512 MB** — keeps browser and build scratch off the eMMC.

---

## GNOME: what was dropped

Installed as a hand-picked list (`config/packages/30-gnome-minimal.list`), not
`gnome` or `gnome-core`. Dropped: `gnome-software` background refresh,
`gnome-photos`, `gnome-music`, `totem`, `rhythmbox`, `cheese`, `simple-scan`,
`gnome-maps`, `gnome-weather`, `gnome-contacts`, `evolution`, `libreoffice`,
`malcontent`, `fonts-recommended` (~200 MB by itself), and the documentation
packages.

**Animations off.** The single largest perceived-speed change. Every GNOME Shell
transition is a full-screen composited effect; at 1280×800 on Gen7 graphics that
is roughly 100 ms of jank each time. `linx-tune animations-on` reverses it.

**Tracker masked and configured to index nothing.** Full-text indexing of the
home directory means sustained CPU and sustained writes to a wear-limited eMMC,
to power a search feature that costs more than it is worth here. *Cost:* no
content search in the Activities overview or Nautilus. Filename search still
works.

**External search providers disabled.** The Shell queries every installed
provider on each keystroke in the overview. On this CPU that is the difference
between responsive and unusable.

**Solid-colour background.** A wallpaper is a large JPEG that must be decoded and
held resident.

**GDM is kept** for out-of-the-box correctness — it provides the on-screen
keyboard at the login prompt, which matters if you use the tablet undocked.
`linx-tune greeter-lite` swaps it for LightDM and frees roughly 120 MB.

---

## Services masked

Each is resident RAM, a timer wakeup, or both.

| Unit | Why | Cost of masking |
|---|---|---|
| `ModemManager` | No cellular modem | none |
| `packagekit` | Large resident daemon; GNOME Software's backend | Software app cannot install; use `apt` |
| `avahi-daemon` | Resident daemon + periodic multicast wakeups | no zero-config network printer/share discovery |
| `cups`, `cups-browsed` | Printing off by default | `linx-tune printing-on` |
| `apt-daily{,-upgrade}.timer` | Multi-MB download + CPU spike on a timer | update manually |
| `man-db.timer` | Indexes man pages we strip anyway | none |
| `NetworkManager-wait-online` | Adds seconds of boot delay | none for a desktop |
| `tracker-*` (user) | See above | content search |
| `colord` | Colour management for a fixed uncalibrated panel | none |
| `switcheroo-control` | Dual-GPU switching | none |
| `geoclue` | Location services | apps needing location |
| `e2scrub_all.timer` | Thrashes flash | none |
| `speech-dispatcher` | No voice shipped | screen reader |

Masked rather than disabled, so a package update cannot silently re-enable them.

---

## Kernel and boot

Default command line:

```
quiet loglevel=3 i915.fastboot=1 i915.enable_fbc=1 nmi_watchdog=0
```

- `i915.fastboot=1` — skip re-programming the display pipe if the firmware
  already configured it. Removes a visible mode-set flicker and ~0.3 s of boot.
- `i915.enable_fbc=1` — framebuffer compression. Display memory bandwidth is the
  main bottleneck on Gen7 Bay Trail graphics.
- `nmi_watchdog=0` — frees a per-CPU timer and a little power.

Blacklisted modules for hardware this machine does not have: other GPUs, wired
Ethernet, floppy/parallel/FireWire, and `atomisp` (the unusable cameras).

**Firmware pruning** in stage 50 removes blobs for hundreds of absent devices —
`amdgpu`, `nvidia`, other-generation `i915`, `ath10k`, `mediatek`, enterprise
NICs. This is the largest single size saving in the cleanup stage.

**Documentation, man pages and unused locales** are stripped. Copyright files are
deliberately kept — removing them is a licence-compliance problem and they are
small.

---

## Per-unit issues no image can fix by default

**ACPI GPE storm.** A firmware bug where a General Purpose Event fires
continuously, pinning a kworker near 100% CPU forever. The GPE number varies
between units, so it cannot be a shipped default. Run `linx-gpe-scan`; if it
reports a storm, `linx-gpe-scan --apply`. When present, this is the biggest
performance problem on the machine — larger than everything else on this page
combined.

**Bay Trail C-state freezes.** Fixed by current `intel-microcode`, which this
image installs. If a unit still freezes, `linx-tune cstate-safe` — at close to
half the battery life.

---

## Things deliberately not done

- **`f2fs` root.** Genuinely better suited to eMMC than ext4, but GRUB's f2fs
  support is read-only and less exercised, `fsck.f2fs` is less battle-tested, and
  the practical difference with `noatime` + weekly TRIM is small. Not worth the
  recovery risk on a machine with one storage device.
- **Disabling the ext4 journal.** A few percent of write throughput in exchange
  for filesystem corruption on the first hard power-off. No.
- **`intel_idle.max_cstate=1` by default.** Fixes a freeze that most units no
  longer have, at close to half the battery life. Available via `linx-tune`.
- **`powertop --auto-tune` at boot.** It re-enables USB autosuspend on input
  devices, which makes the keyboard drop its first keystroke. The durable, safe
  subset is in `overlay/etc/udev/rules.d/60-linx-power.rules` instead.
- **Preload / prelink / readahead daemons.** They trade eMMC writes and RAM for a
  benefit that zram and the page cache already provide.
