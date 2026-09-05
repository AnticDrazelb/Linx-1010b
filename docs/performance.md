# What was stripped, what was added, and what each costs

Every item here is a trade-off. This document states the cost as well as the
benefit, so you can reverse anything that does not suit you — most of it is one
`linx-tune` command away.

**Measured** from the first successful build, and from booting the resulting ISO
in QEMU with 2 GB of RAM to match the tablet. Boot time is deliberately absent:
under emulation it is meaningless, and on the real device it is dominated by eMMC
speed.

| | Measured |
|---|---|
| Packages installed | 859 (including dependencies) |
| Rootfs before stripping | 2826 MB |
| Rootfs after stripping | **1756 MB** |
| squashfs (zstd-19) | 606 MB |
| ISO | **693 MB** |
| initramfs | 55 MB (Debian's `MODULES=most`; see `linx-tune initramfs-slim`) |
| RAM used at idle GNOME desktop | **640 MiB** |
| Build time | ~4.5 min compute on 4 cores, plus ~1.5 GB of downloads |

The 640 MiB reading came from a live-USB session, which carries squashfs cache
overhead, so an installed system should sit a little below it. A stock Debian
GNOME install is roughly 5.5 GB on disk and heavier at idle, but that comparison
has not been measured on identical terms and is offered only as a rough sense of
scale.

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

## Can the microSD card make it faster?

Short answer: no, and two of the obvious ideas make it slower. It is still worth
using, but for space rather than speed.

**Why not speed.** Desktop responsiveness is dominated by small random reads. The
internal eMMC is generally better at those than a microSD card - often several
times better unless the card carries an A1 or A2 rating, and those ratings
guarantee only 1500 and 4000 random read IOPS respectively, which is not a lot.
Anything you move onto the card that is read at random gets slower, not faster.

**Do not use the card as a cache for the eMMC.** `bcache` and `lvmcache` speed up
a slow device by putting a fast one in front of it. Here the relationship is the
wrong way round: the card is the slower device. It adds a layer of indirection,
a write-back failure mode and a second thing that must be present at boot, in
exchange for making reads worse.

**Do not put the browser cache or `~/.cache` on it.** That is small-random-write
traffic, the worst case for a card, and it wears it out quickly.

**Do not make it the primary swap.** zram already provides swap that is roughly
two orders of magnitude faster, because it is RAM. Swapping to a card is what
zram exists to avoid.

### What the card is genuinely good for

**Bulk data that is read sequentially and written rarely** - music, video,
photos, documents, downloads, disk images. Sequential throughput is the one thing
cards are reasonable at, and moving this material off the eMMC has a real
indirect benefit: **flash slows down markedly as it fills**, because the
controller has fewer free blocks to work with for wear levelling and garbage
collection. Keeping the 29 GB eMMC comfortably empty is worth more than any
tuning parameter on this page.

```bash
# One ext4 partition on the card, mounted under your home directory.
sudo mkfs.ext4 -L linxdata /dev/mmcblkNp1        # check N with linx-report storage
sudo mkdir -p /mnt/sd

# nofail matters: without it the machine will not boot with the card removed.
echo 'LABEL=linxdata  /mnt/sd  ext4  defaults,noatime,nofail,x-systemd.device-timeout=5s  0 2' \
    | sudo tee -a /etc/fstab
sudo systemctl daemon-reload && sudo mount -a
sudo chown "$USER:$USER" /mnt/sd

# Point the bulky home directories at it.
for d in Videos Music Pictures Downloads; do
    mkdir -p "/mnt/sd/$d"
    [ -d "$HOME/$d" ] && mv "$HOME/$d"/* "/mnt/sd/$d/" 2>/dev/null
    rm -rf "$HOME/$d" && ln -s "/mnt/sd/$d" "$HOME/$d"
done
```

**An emergency second swap tier**, if and only if you are actually running out of
memory and being OOM-killed. Give it a *lower* priority than zram, so it is used
only once zram is full. This does not make anything faster - it trades a crash
for a period of severe slowness, which is sometimes the better trade.

```bash
sudo fallocate -l 2G /mnt/sd/swapfile
sudo chmod 600 /mnt/sd/swapfile && sudo mkswap /mnt/sd/swapfile
echo '/mnt/sd/swapfile  none  swap  sw,pri=10,nofail  0 0' | sudo tee -a /etc/fstab
sudo swapon -a     # zram is priority 100, so this is only reached when zram is full
```

Check whether you need it first: `linx-report memory`. If zram's *stored* figure
is nowhere near its disksize, you are not short of memory and this will do
nothing but wear the card.

## Hardware video decode

Bay Trail's GPU decodes H.264 in fixed-function hardware. Without a VA-API
driver, every video is decoded on the CPU instead - four in-order cores at
1.33 GHz - which is the difference between smooth 720p and a slideshow, and it
pins the CPU at 100% on a fanless chassis while it fails.

The image installs `i965-va-driver`. That is the intel-vaapi-driver, which covers
Gen7 and earlier. `intel-media-va-driver` is for Gen8 (Broadwell) onwards and
does nothing here.

Check it is working:

```bash
vainfo 2>&1 | head -20     # should list VAProfileH264* entries
```

Applications need to be told to use it. GStreamer-based players generally pick it
up; Chromium-based browsers need flags, and Firefox needs
`media.ffmpeg.vaapi.enabled` set in `about:config`.

### Chromium and Brave on 2 GB

Chromium's process-per-site model is more memory-hungry than Firefox's, which
matters here. Brave's built-in content blocking pulls in the other direction and
is a real win on a slow CPU - most of the cost of a modern page is JavaScript
execution and layout, not bandwidth.

Put flags in a desktop file override rather than editing the packaged one, so an
update does not revert them:

```bash
mkdir -p ~/.local/share/applications
sed -e 's|^Exec=/usr/bin/brave-browser-stable |Exec=/usr/bin/brave-browser-stable --renderer-process-limit=3 --process-per-site --enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoDecoder --ignore-gpu-blocklist --ozone-platform-hint=auto |' \
    /usr/share/applications/brave-browser.desktop > ~/.local/share/applications/brave-browser.desktop
update-desktop-database ~/.local/share/applications
```

- `--renderer-process-limit=3` is the biggest single saving. The default scales
  with RAM and still overshoots on 2 GB.
- `--process-per-site` consolidates tabs of the same site into one process.
- The VA-API flags vary by Chromium version and are worth verifying rather than
  trusting: open `brave://gpu` and look for *Video Decode: Hardware accelerated*.
  If it says software, try dropping `VaapiVideoDecodeLinuxGL` and keeping only
  `VaapiVideoDecoder`, or vice versa.

Also turn off the Brave features that run background services - Rewards, Wallet,
News and Sync - unless you use them. Each is a process on a machine with room for
few.

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
