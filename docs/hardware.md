# Linx 1010B hardware reference

## Specification

| | |
|---|---|
| SoC | Intel Atom Z3735F, Bay Trail-T, 4 cores, 1.33 GHz base / 1.83 GHz burst |
| Architecture | x86-64 (64-bit CPU) |
| RAM | 2 GB DDR3L, not upgradeable |
| Storage | 32 GB eMMC, plus microSD slot |
| Display | 10.1" IPS, 1280×800, 10-point capacitive touch |
| Graphics | Intel HD Graphics (Gen7, Valleyview) |
| Firmware | **32-bit UEFI (IA32)**, no CSM / no legacy BIOS boot |
| Wi-Fi | Realtek SDIO 802.11 b/g/n (RTL8723BS family) |
| Bluetooth | Realtek, on UART, shares the Wi-Fi package |
| Audio | Realtek codec on the Intel SST DSP (usually rt5640) |
| PMIC / battery | X-Powers AXP288, 7000 mAh |
| Cameras | 2 MP rear, 2 MP front — **not usable on Linux** |
| Ports | micro-HDMI, micro-USB (charge + data), 2× USB-A, microSD, 3.5 mm |
| Accessory | Detachable keyboard dock (standard USB HID) |

## Per-device notes

### Firmware — the defining constraint

32-bit UEFI on a 64-bit CPU. This is not a quirk you can work around in software
on the OS side; the bootloader binary itself must be a 32-bit PE. See
[boot-32bit-uefi.md](boot-32bit-uefi.md).

To reach the firmware: power off fully, then hold **Volume Up** while pressing
**Power**. You get an "Esc is pressed" message and then the setup menu.

### Touchscreen — Goodix

Enumerates over ACPI as `GDIX1001` and is driven by the in-tree `goodix` I2C
driver. **No firmware blob and no DMI quirk are required**, which is a meaningful
difference from the Silead (`gsl1680`) parts in many other Bay Trail tablets —
those need a per-model firmware file and an entry in
`drivers/platform/x86/touchscreen_dmi.c`. Verified: there is no Linx entry in
that file upstream, and none is needed.

Long-press to right-click is a GNOME accessibility setting, enabled by default in
this image (`org.gnome.desktop.a11y.mouse secondary-click-enabled`).

### Backlight — needs `pwm_lpss` early

Bay Trail drives the panel backlight through the LPSS PWM block. If `pwm_lpss`
and `pwm_lpss_platform` are not loaded **before** `i915` binds, no backlight
device is created at all and brightness control is dead for the whole session —
`/sys/class/backlight/` is simply empty.

The fix is to put both modules in the initramfs, which this image does via
`overlay/etc/initramfs-tools/modules`. `linx-report display` reports it if the
backlight device is missing.

### Audio — force the legacy SST driver

Current kernels default to SOF (Sound Open Firmware) for Intel DSPs. On Bay
Trail-T that path is unreliable: the card enumerates but nothing plays. Force the
legacy Atom SST driver:

```
options snd-intel-dspcfg dsp_driver=2
```

Values, from the kernel's own `MODULE_PARM_DESC` in
`sound/hda/core/intel-dsp-config.c`: `0=auto 1=legacy 2=SST 3=SOF 4=AVS`.

`alsa-ucm-conf` is equally required — without the UCM profiles the card
enumerates and routes audio nowhere.

### Wi-Fi / Bluetooth — Realtek SDIO

Driver is in-tree (`r8723bs`), firmware comes from `firmware-realtek`. Two
recurring annoyances:

- **No MAC in EEPROM on many units**, so a new random MAC every boot. This breaks
  DHCP reservations and captive portals. NetworkManager is configured with
  `wifi.cloned-mac-address=permanent` and scan randomisation off.
- **Power-save related drops** under load on some units. `linx-tune wifi-stable`
  disables Wi-Fi power management and sets `rtw_power_mgnt=0 rtw_ips_mode=0`, at
  a real cost in battery life.

### Cameras — do not work

The MIPI sensors go through Intel's Atomisp ISP. There is no usable Linux driver
path for these on Bay Trail. This image blacklists `atomisp` and
`atomisp_gmin_platform` so they stop consuming memory and filling the log.

### CPU idle — the Bay Trail freeze erratum

Some Bay Trail units freeze hard at random when entering deep C-states. Current
`intel-microcode` fixes this on most machines, which is why this image installs
it unconditionally. If a unit still freezes, `linx-tune cstate-safe` adds
`intel_idle.max_cstate=1` — this works, and it costs close to half the battery
life, so it is a fallback and not a default.

### ACPI GPE storms

A firmware bug class where an ACPI General Purpose Event fires continuously
because its handler cannot clear it, pinning a kworker thread near 100% CPU
forever. The GPE number differs between units, so it cannot be shipped as a
default kernel parameter. `linx-gpe-scan` measures the per-GPE interrupt rates
and produces the exact `acpi_mask_gpe=0x..` argument.

On a fanless 2 GB tablet this is the single largest performance problem when it
is present, and it is easy to misdiagnose as "Linux is just slow on this thing".

## Sources

- [Ian Renton — HOWTO: Install Linux on a Linx 1010B Tablet](https://ianrenton.com/projects/linux-on-linx-1010b-tablet/) — device-specific: Goodix touchscreen, the `dsp_driver=2` audio fix, the `pwm_lpss_platform` brightness fix, `grub-efi-ia32`, cameras not working
- [Concretedog — Linux on Linx1010b](https://concretedog.blogspot.com/2018/04/linux-on-linx1010b.html)
- [Linx 1010 specification (Farnell)](https://www.farnell.com/datasheets/1960178.pdf) — CPU, RAM, storage, ports
- Kernel source, checked directly: `drivers/input/touchscreen/goodix.c` (ACPI IDs `GDIX1001`–`GDIX1003`), `drivers/platform/x86/touchscreen_dmi.c` (no Linx entry — none needed), `drivers/gpu/drm/drm_panel_orientation_quirks.c` (no Linx entry), `sound/hda/core/intel-dsp-config.c` (`dsp_driver` values)
- [Arch/Ubuntu/Red Hat bug reports on ACPI GPE storms](https://bugzilla.redhat.com/show_bug.cgi?id=1192856)
