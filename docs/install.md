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

## Installing to the microSD card instead of the eMMC

Reasonable reasons to want this: it leaves the existing Windows install
untouched, a 64 GB card is bigger than the 29 GB eMMC, and it is completely
reversible - pull the card out and the tablet is exactly as it was.

```bash
sudo LINX_ALLOW_SD=1 linx-install /dev/mmcblkN
```

`linx-install` refuses an SD card without `LINX_ALLOW_SD=1`, because on this
hardware both the eMMC and the card report `removable = 0` and picking the wrong
one destroys somebody's photos. Confirm which is which first:

```bash
linx-report storage
cat /sys/block/mmcblk*/device/type    # MMC = internal eMMC, SD = the card
```

### Two things to check before you commit to it

**Can the firmware boot from the SD slot at all?** Not all Bay Trail tablets
expose the microSD reader as a boot device — some enumerate only USB and the
internal eMMC. There is no way to know for a given unit except to try. The good
news is that trying costs nothing but the card's existing contents: install to
the card, reboot, and see whether the firmware's Boot Manager lists it. Windows
on the eMMC is untouched either way, so a failure leaves you exactly where you
started.

**The card is almost certainly slower than the eMMC**, and this matters more
than people expect. Desktop responsiveness is dominated by small random reads,
not sequential throughput, and that is precisely where cheap cards are worst. A
card with no application-performance rating can be several times slower than the
eMMC for this workload, which will undo a good deal of what the rest of this
image is doing.

Look for an **A1** or **A2** rating on the card (a small `A1`/`A2` logo). Those
guarantee a minimum random IOPS figure and are the only ratings that predict
desktop behaviour. "Class 10" and "U1/U3" describe sequential speed only and
tell you nothing useful here.

### If the firmware will not boot from the card

On the Linx 1010B it will not. After a successful install to the SD card, the
firmware's Boot Manager still lists only "Windows Boot Manager" and "Internal
EFI Shell" - the microSD reader is not enumerated as a boot device, and no
firmware setting changes that. GRUB cannot help either: it uses the same UEFI
block devices the firmware exposes.

The kernel is a different matter. It has a real SDHCI driver and reads the card
without difficulty. So the fix is to split the chain:

```
firmware -> GRUB on the eMMC's EFI partition   (the firmware can read the eMMC)
GRUB     -> kernel + initrd, on that same ESP  (no other filesystem needed)
kernel   -> root filesystem on the SD card     (the kernel has the SD driver)
```

`linx-boot-from-emmc` sets this up:

```bash
sudo linx-boot-from-emmc
```

It backs the EFI System Partition up to the card first, only ever adds files to
it, and writes a menu that includes an entry to chainload Windows. If the ESP is
too small for a generic 57 MB initramfs - the one on this tablet is 100 MB and
already holds Windows' boot files - it rebuilds a machine-specific one with
`MODULES=dep`, which is safe because it runs on the machine itself.

One caveat worth taking seriously: if the machine uses BitLocker, adding a boot
entry can make Windows ask for its recovery key on the next Windows boot. Have
the key to hand before running it.

### If you install to the card

Everything else is identical to an eMMC install. The image's storage tuning
already applies to any `mmcblk` device — `mq-deadline`, 128 KB readahead,
`noatime`, `commit=60`, weekly batch TRIM — and zram matters even more when the
backing store is slow, so keep it.

Do not remove the card while the system is running. It is the root filesystem.

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
