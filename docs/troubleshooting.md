# Troubleshooting

Start with `linx-report` — it checks most of the things below automatically and
flags the two failure modes (no backlight device, no zram) explicitly.

---

## The tablet will not boot the USB stick

Almost always the 32-bit UEFI problem. In order of likelihood:

**1. `BOOTIA32.EFI` is missing from the stick.**

```bash
sudo mount /dev/sdX2 /mnt && ls /mnt/EFI/BOOT/
```

Must contain `BOOTIA32.EFI`. If it contains only `BOOTX64.EFI`, the tablet cannot
load it. Either the build host lacked `grub-efi-ia32-bin`, or Rufus was used in
ISO mode rather than DD mode and rewrote the boot layout.

**2. Secure Boot is on.** This image is not signed. Firmware menu → Security →
disable Secure Boot.

**3. The stick is not offered at all.** Some units only enumerate USB devices
present at power-on. Insert the stick, then power on holding Volume Up. Try the
other USB port, and try a USB 2.0 stick — some of these firmwares are unreliable
with USB 3.0 devices.

**4. It boots to a `grub>` prompt instead of the menu.** GRUB loaded - which means
the 32-bit EFI half already works - but could not find `grub.cfg`.

Recover the current boot:

```
grub> search --no-floppy --set=root --file /boot/grub/grub.cfg
grub> configfile /boot/grub/grub.cfg
```

or boot directly:

```
grub> search --no-floppy --set=root --file /live/filesystem.squashfs
grub> linux /live/vmlinuz boot=live components quiet loglevel=3
grub> initrd /live/initrd.img
grub> boot
```

**Why this happens**, because it is worth understanding: `grub-mkimage
--prefix=/boot/grub` sets a prefix with no device, so GRUB looks for
`($root)/boot/grub/grub.cfg` where `$root` is whatever device the firmware says
it loaded from. On this tablet that is the FAT EFI System Partition, which holds
only `/EFI/BOOT/*.EFI` - so the config is never found.

Confusingly, the same image can boot fine elsewhere: some firmware reports the
whole disk instead of the partition, and GRUB then reads the hybrid image as
iso9660, where `/boot/grub/grub.cfg` does exist. So this bug hides under
emulation and appears on real hardware.

Images built after this was fixed embed a configuration into the EFI binary that
locates the medium by a marker file (`/.disk/linx1010b.id`) and sets `root` and
`prefix` explicitly, which does not depend on firmware behaviour. A fallback
config is also written to the ESP itself. If you are on an older image, the
commands above get you booted; the installed system is unaffected, because
`grub-install` writes its own correct configuration to the eMMC.

Note for anyone editing that embedded config: it runs in GRUB's minimal parser
before `normal` is loaded, so `if`, `then`, `fi` and `[` do not exist there and
produce `Unknown command \`if'`, after which nothing else in it runs. Plain
sequential commands only.

## Installed system will not boot, live USB does

The NVRAM entry was lost — common on these tablets after a firmware reset or a
flat battery. The fallback path should still work; if it does not, reinstall the
bootloader following
[install.md § Reinstalling the bootloader](install.md#reinstalling--recovering-the-bootloader).

---

## No sound

1. `linx-report audio`
2. `dsp_driver` must read **2**. If it reads 3 or `auto`, SOF has bound instead
   of the legacy SST driver:

```bash
sudo linx-tune audio-sst
sudo reboot
```

3. If `dsp_driver` is 2 and a card is listed but there is still no sound, the UCM
   profiles are missing or wrong for your codec:

```bash
dpkg -l alsa-ucm-conf          # must be installed
lsmod | grep -E 'rt5[0-9]{3}'  # which codec bound
```

Codec variants exist across production batches (rt5640 is most common; rt5645 and
rt5651 exist). If yours is not rt5640, check that `alsa-ucm-conf` carries a
profile for it — a newer version from backports sometimes helps.

4. Check the output is not routed to HDMI: `wpctl status`.

## Brightness control does nothing

`/sys/class/backlight/` is empty. `pwm_lpss` did not load before `i915` bound.

```bash
grep pwm /etc/initramfs-tools/modules   # should list pwm_lpss and pwm_lpss_platform
sudo update-initramfs -u -k all
sudo reboot
```

This image ships that file, so if it is missing something has overwritten it.

## Touchscreen does not work

Unlike Silead-based tablets, this one needs no firmware and no DMI quirk — the
Goodix controller enumerates over ACPI as `GDIX1001`.

```bash
linx-report input
dmesg | grep -i goodix
```

If the device is absent entirely, check `CONFIG_TOUCHSCREEN_GOODIX` and
`CONFIG_I2C_DESIGNWARE_PLATFORM` are enabled — relevant only if you built a
custom kernel.

**Touch works but the axes are wrong** (after a manual rotation). Under X11:

```bash
xinput set-prop "pointer:Goodix Capacitive TouchScreen" \
    'Coordinate Transformation Matrix' 0 1 0 -1 0 1 0 0 1
```

Under Wayland this is handled by the compositor; use GNOME's rotation lock rather
than rotating by hand.

## Screen orientation is wrong

There is no DRM panel-orientation quirk upstream for this model, so GNOME relies
on the accelerometer:

```bash
systemctl status iio-sensor-proxy
monitor-sensor                      # should report orientation changes
```

To force a console/boot orientation, uncomment in `/etc/default/grub`:

```
fbcon=rotate:1 video=DSI-1:panel_orientation=right_side_up
```

then `sudo update-grub`. Check the actual connector name first with
`linx-report display` — it may be `eDP-1` rather than `DSI-1`.

---

## A kworker thread is at 100% CPU

An ACPI GPE storm.

```bash
linx-gpe-scan
sudo linx-gpe-scan --apply
sudo reboot
```

If nothing is reported but a kworker is still busy, look at `/proc/interrupts`
for a rapidly climbing line instead — a shared IRQ can produce the same symptom.

## Random hard freezes

The Bay Trail C-state erratum.

1. Confirm microcode is loaded — `dmesg | grep -i microcode`. This image installs
   `intel-microcode`, which fixes it on most units.
2. If it still freezes: `sudo linx-tune cstate-safe`, reboot.

This costs close to half the battery life, which is why it is not a default.

## Wi-Fi drops, or a new MAC address every boot

```bash
sudo linx-tune wifi-stable     # disables power saving; costs battery
```

For the MAC: some units have nothing programmed in the Wi-Fi EEPROM. This image
sets `wifi.cloned-mac-address=permanent`, but if the permanent address is itself
random, pin one explicitly:

```bash
cat | sudo tee /etc/systemd/network/10-wlan.link <<'EOF2'
[Match]
OriginalName=wlan0

[Link]
MACAddress=02:11:22:33:44:55
EOF2
sudo update-initramfs -u
```

Use a locally-administered address — second hex digit `2`, `6`, `A` or `E`.

## System runs out of memory

```bash
linx-report memory
```

`zram` must show as active and sized to about 2 GB. If it reads `INACTIVE`,
`systemd-zram-generator` is not installed or `/etc/systemd/zram-generator.conf`
is missing — this is the most impactful thing to fix on this machine.

Beyond that: fewer browser tabs, and `linx-tune greeter-lite` to free ~120 MB.

## Desktop feels sluggish

In order of impact:

1. `linx-gpe-scan` — a GPE storm dwarfs everything else on this list.
2. `gsettings get org.gnome.desktop.interface enable-animations` → must be `false`.
3. `systemctl --user status tracker-miner-fs-3` → must be masked.
4. `linx-report memory` → is zram active, and is it full?
5. `linx-report cpu` → is it thermally throttled? The Z3735F is fanless and will
   drop to ~500 MHz when hot. Nothing fixes that except less sustained load.
6. `linx-tune greeter-lite`.

## Software app cannot install anything

Expected — `packagekit` is masked. Use `apt`, or:

```bash
sudo systemctl unmask packagekit && sudo systemctl start packagekit
```

## No network printer discovery

Expected — `avahi-daemon` is masked. `sudo linx-tune printing-on`.

## `journalctl -b -1` shows nothing

Expected — the journal is volatile. `sudo linx-tune logs-persistent`, reproduce
the problem, then switch back.
