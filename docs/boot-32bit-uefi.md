# Booting a 64-bit Linux on 32-bit UEFI firmware

## The problem

The Linx 1010B pairs a 64-bit Atom CPU with a **32-bit (IA32) UEFI**
implementation. This was common on cheap Bay Trail tablets around 2014–2015,
largely to fit a 32-bit Windows image and its driver set.

UEFI cannot execute a PE binary of a different bitness than the firmware. So:

- The firmware looks for `\EFI\BOOT\BOOTIA32.EFI` on removable media.
- A stock amd64 Debian/Ubuntu/Fedora ISO ships only `BOOTX64.EFI`.
- The firmware finds nothing it can load and reports "no bootable device", with
  no hint about why. The USB stick is fine; the tablet simply cannot start it.

There is also no CSM, so there is no legacy-BIOS escape hatch.

## What is and is not bitness-constrained

Only the **firmware → bootloader** handoff. Specifically:

| Component | Must be 32-bit? |
|---|---|
| UEFI firmware | (is) 32-bit |
| Bootloader (`BOOTIA32.EFI`) | **Yes** |
| Linux kernel | No — 64-bit is correct |
| Userland / all packages | No — 64-bit is correct |

A 32-bit GRUB can boot a 64-bit kernel. GRUB does not use the kernel's EFI
handover protocol for this; it loads the kernel via the Linux boot protocol and
performs the mode switch to long mode itself. This is a well-trodden path — it
is exactly what Debian's `grub-efi-ia32` package exists for.

The kernel's `CONFIG_EFI_MIXED` covers the related case of the EFI stub being
entered from 32-bit firmware, and is enabled in the optional custom kernel
fragment. It is not required for the GRUB path.

## Why 64-bit userland rather than i386

Tempting, given 2 GB of RAM — 32-bit pointers would save some memory. But:

- Debian's i386 port no longer ships a usable GNOME desktop and is on a path to
  removal. Building on it means fighting the distribution.
- x86-64 has twice the general-purpose registers and a better calling
  convention. On an in-order Silvermont core, register pressure hurts more than
  usual, and the code-density loss is comparatively small.
- Firmware, driver and browser support are all better tested on amd64 now.

The memory cost is real but modest, and zram recovers more than it costs.

## How this repository builds it

`build/stages/70-efi.sh` builds both bootloaders with `grub-mkimage`:

```bash
grub-mkimage --format=i386-efi   --prefix=/boot/grub -o BOOTIA32.EFI  <modules>
grub-mkimage --format=x86_64-efi --prefix=/boot/grub -o BOOTX64.EFI   <modules>
```

`BOOTX64.EFI` is not needed by the tablet. It is included so the same ISO boots
an ordinary 64-bit UEFI PC, which makes it possible to test the image without
committing it to the tablet each time.

This requires `grub-efi-ia32-bin` on the **build host** — it provides
`/usr/lib/grub/i386-efi`. Stage 00 checks for it and fails loudly if it is
missing, because without it the build silently produces an ISO that this tablet
cannot boot.

## Installation to the eMMC

`installer/linx-install.sh` runs `grub-install --target=i386-efi` **twice**:

```bash
grub-install --target=i386-efi --efi-directory=/boot/efi --bootloader-id=linx --removable
grub-install --target=i386-efi --efi-directory=/boot/efi --bootloader-id=linx
```

The first writes `\EFI\BOOT\BOOTIA32.EFI`, the removable-media fallback path
that every UEFI implementation must check. The second creates a proper NVRAM
boot entry.

Both are done deliberately: these tablets frequently lose or ignore NVRAM boot
variables after a firmware reset or a fully flat battery. If you only create the
NVRAM entry, the machine eventually becomes unbootable for no visible reason.
The fallback path always works.

## If it still will not boot

See [troubleshooting.md](troubleshooting.md#the-tablet-will-not-boot-the-usb-stick).
