# Optional custom kernel

**This is optional.** Debian's stock `linux-image-amd64` works correctly on this
tablet. A custom kernel buys:

- a smaller kernel image and far fewer modules to probe at boot
- a slightly smaller resident kernel footprint, which is worth something on 2 GB
- `CONFIG_PREEMPT` and `HZ=250`, which help interactive feel on a slow in-order core
- no debug info, cutting build time roughly in half and package size by an order
  of magnitude

It costs 30–60 minutes of build time and the ongoing burden of rebuilding for
security updates instead of letting `apt` do it. For most people the stock kernel
is the right answer.

## Use

```bash
cd kernel
./build-kernel.sh            # produces kernel/out/linux-*.deb
cd ..
sudo ./build/build.sh 20 30 40 50 60 70 80
```

Stage 20 picks up `kernel/out/linux-image-*.deb` automatically and drops
`linux-image-amd64` from the package list. The opt-in is purely the files
existing — there is no flag to set.

## How the config is produced

`linx1010b.fragment` is a **fragment**, applied on top of Debian's running kernel
config with `scripts/kconfig/merge_config.sh`. It only states what differs.

This is deliberate. A hand-written full `.config` rots the moment the kernel
version moves — new symbols appear, old ones are renamed, and you end up with a
kernel that silently lacks a driver. A fragment keeps working, and
`merge_config.sh` *reports* any option it could not satisfy, which is the signal
that the fragment needs updating.

`build-kernel.sh` then re-checks the options that actually matter for this
machine (eMMC, Goodix touch, LPSS PWM backlight, i915, SST audio, EFI mixed mode,
zram, AXP288 fuel gauge) and warns if any are missing, because losing one of
those produces a kernel that boots to a black screen or a machine with no storage.

## What the fragment strips

Whole subsystems this hardware cannot use: other GPU drivers, SATA/SCSI/RAID,
wired Ethernet, ISA/parallel/PCCard/FireWire, KVM and Xen, exotic filesystems,
and all kernel debug infrastructure (`DEBUG_INFO`, `FTRACE`, `KPROBES`, `KGDB`).

What it forces **on**, because the machine does not work without them:

| Option | Why |
|---|---|
| `MMC_SDHCI_ACPI` | The eMMC. No root filesystem without it. |
| `TOUCHSCREEN_GOODIX`, `I2C_DESIGNWARE_PLATFORM` | The touchscreen |
| `PWM_LPSS`, `PWM_LPSS_PLATFORM` | Backlight — built in, so there is no initramfs ordering problem at all |
| `SND_SST_ATOM_HIFI2_PLATFORM_ACPI` + the BYTCR machine drivers | Audio |
| `EFI_MIXED` | 64-bit kernel entered from 32-bit firmware |
| `AXP288_CHARGER`, `AXP288_FUEL_GAUGE` | Battery reporting |
| `ZRAM` + `CRYPTO_LZ4` | Compressed swap |

## Caveats

- You are now responsible for kernel security updates.
- Debian's `linux-image-amd64` metapackage will try to reinstall the stock kernel
  if something pulls it in. `apt-mark hold` it.
- If the tablet boots to a black screen after switching, pick the previous kernel
  from the GRUB menu — the stock kernel is not removed.
