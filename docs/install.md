# Installing on the tablet

## 1. Write the ISO

```bash
sudo dd if=out/linx1010b-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

On Windows, Rufus in **DD image** mode. Do *not* let Rufus use ISO mode — it
rewrites the boot layout and can lose `BOOTIA32.EFI`, which is the one file this
tablet needs.

Verify the stick afterwards if boot fails:

```bash
sudo mount /dev/sdX2 /mnt && ls /mnt/EFI/BOOT/
# must contain BOOTIA32.EFI
```

## 2. Boot it

1. Power the tablet **fully off** (not sleep).
2. Hold **Volume Up**, press **Power**, keep holding until the screen reacts.
3. You get "Esc is pressed" and then the firmware menu.
4. **Boot Manager** → select the USB device.

If the USB stick is not listed, see
[troubleshooting.md](troubleshooting.md#the-tablet-will-not-boot-the-usb-stick).

## 3. Try it live first

The live session runs entirely from the USB stick. It is slow — that is the
stick, not the installed system — but it tells you whether the hardware works
before you erase anything:

```bash
linx-report
```

Check specifically:

- `display` — a backlight device exists (if not, `pwm_lpss` did not load)
- `audio` — `dsp_driver` is 2 and a card is listed
- `input` — a Goodix touchscreen and an accelerometer
- `network` — a Realtek module loaded

## 4. Install

```bash
sudo linx-install
```

This **erases the whole eMMC**, including Windows. It asks you to type the device
name to confirm. Layout:

| Partition | Size | Filesystem | Mount |
|---|---|---|---|
| `p1` | 512 MB | FAT32 | `/boot/efi` |
| `p2` | rest | ext4 | `/` |

Expect 10–20 minutes for the copy — eMMC write speed, nothing to be done about
it. It then asks for a username and hostname and sets a password.

## 5. First boot

Remove the USB stick and reboot. If the tablet drops into the firmware menu,
choose Boot Manager and pick the internal eMMC entry once — some units need
telling the first time.

Then, in this order:

```bash
linx-gpe-scan       # do this first - see below
linx-report
linx-tune status
```

**Run `linx-gpe-scan` first.** If your unit has an ACPI GPE storm, a kworker
thread is pinned near 100% CPU and nothing else you tune will matter as much.
`linx-gpe-scan --apply` writes the fix and reboots into it.

---

## Dual-booting with Windows

`linx-install` does **not** do this — it is a whole-disk installer. On a 32 GB
eMMC, a Windows 10 install plus a GNOME install leaves very little room for
either, so this is not recommended. If you want it anyway:

1. In Windows, shrink the C: partition with Disk Management (leave ≥ 12 GB free).
2. Boot the live image and partition manually with `gdisk` — create **one** new
   ext4 partition in the free space. **Keep the existing ESP**; do not create a
   second one.
3. Mount and copy by hand, following the `rsync` invocation in
   `installer/linx-install.sh`.
4. Mount the *existing* ESP at `/boot/efi` and run the two `grub-install
   --target=i386-efi` commands from the same script.
5. Set `GRUB_DISABLE_OS_PROBER=false` in `/etc/default/grub`, install `os-prober`,
   and run `update-grub` to pick up the Windows entry.

Back up the ESP before you start:

```bash
sudo dd if=/dev/mmcblk1p1 of=~/esp-backup.img
```

## Reinstalling / recovering the bootloader

If Windows or a firmware reset removes the boot entry, boot the live image and:

```bash
sudo mount /dev/mmcblk1p2 /mnt
sudo mount /dev/mmcblk1p1 /mnt/boot/efi
for m in dev dev/pts proc sys run; do sudo mount --rbind /$m /mnt/$m; done
sudo chroot /mnt grub-install --target=i386-efi --efi-directory=/boot/efi \
     --bootloader-id=linx --recheck --removable
sudo chroot /mnt update-grub
```

Check the device names with `lsblk` first — the internal eMMC is `mmcblk0` or
`mmcblk1` depending on whether a microSD card is inserted.
