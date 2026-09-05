# Building the ISO on Windows

You cannot build this natively on Windows. `debootstrap` and `chroot` need a real
Linux kernel, and there is no Windows equivalent. You need one of:

| Method | Effort | Recommendation |
|---|---|---|
| **WSL2** | Low | **Use this.** Fastest, and the ISO lands somewhere Windows can see |
| Docker Desktop | Low | Fine if you already have it. Uses WSL2 underneath anyway |
| A Linux VM | Medium | Most isolated; slowest to set up and slowest to run |
| Native Windows | — | Not possible |

---

## The one thing that will ruin your build

**Do not put the checkout or the build directory under `/mnt/c` (or any other
Windows drive).**

Windows drives appear in WSL as DrvFs, and a Linux root filesystem cannot live
there:

- `debootstrap` cannot create device nodes (`/dev/null`, `/dev/console`)
- File ownership silently collapses — everything ends up owned by one user
- It is **case-insensitive** by default, and a Debian rootfs contains files whose
  names differ only in case, which get silently merged
- Extended attributes are lost, so file capabilities (on `ping`, for example) go

The build appears to work and then produces an image that will not boot, with no
obvious cause. `build/stages/00-deps.sh` tests for all of this up front and
refuses to continue, but the fix is simply: **keep everything inside the Linux
filesystem** (`~/Linx-1010b`), and copy only the finished ISO out to Windows.

The Linux filesystem is also several times faster than DrvFs, which matters when
the build is unpacking tens of thousands of files.

---

## Method 1: WSL2 (recommended)

### Install

In PowerShell **as Administrator**:

```powershell
wsl --install -d Debian
```

Reboot if prompted, then launch Debian from the Start menu and create your user.
Confirm you are on version 2 (version 1 has no real kernel and will not work):

```powershell
wsl -l -v
```

If it says `VERSION 1`:

```powershell
wsl --set-version Debian 2
```

### Check you have the disk space

The build needs about **12 GB free**, on the Windows drive backing WSL. From
PowerShell:

```powershell
Get-PSDrive C
```

### Build

Inside the Debian shell:

```bash
sudo apt update && sudo apt install -y git
git clone <your-repo-url> ~/Linx-1010b     # note: ~, NOT /mnt/c
cd ~/Linx-1010b

make deps            # installs debootstrap, xorriso, grub-efi-ia32-bin, ...
sudo make iso
```

Expect 20–40 minutes and roughly 1.5 GB of downloads.

### Get the ISO onto Windows

```bash
cp out/linx1010b-*.iso /mnt/c/Users/<YourName>/Downloads/
```

Or open `\\wsl$\Debian\home\<you>\Linx-1010b\out\` in File Explorer — WSL
distributions appear there as network locations.

### Reclaim the disk space afterwards

WSL2's virtual disk grows but does not shrink on its own. After the build:

```bash
sudo make distclean
```

then, from PowerShell, compact the VHDX:

```powershell
wsl --shutdown
Optimize-VHD -Path "$env:LOCALAPPDATA\Packages\<DebianPackage>\LocalState\ext4.vhdx" -Mode Full
```

`Optimize-VHD` needs the Hyper-V module. If you do not have it, `wsl --manage
Debian --set-sparse true` on recent WSL builds does the same job.

---

## Method 2: Docker Desktop

Docker Desktop on Windows runs containers on a WSL2 backend, so this is the same
kernel with different packaging. Useful if you would rather not maintain a WSL
distribution.

Make sure Docker Desktop is set to use the **WSL2 backend**, not Hyper-V
(Settings → General → "Use the WSL 2 based engine").

From PowerShell, in the repository:

```powershell
docker build -t linx1010b-builder -f docker/Dockerfile .
docker volume create linx1010b-work
mkdir out -ErrorAction SilentlyContinue

docker run --rm -it `
  --privileged `
  -v "${PWD}:/src:ro" `
  -v "linx1010b-work:/work" `
  -v "${PWD}/out:/out" `
  linx1010b-builder
```

The ISO appears in `.\out\`.

Three details matter:

- **`--privileged`** — the build bind-mounts `/dev`, `/proc` and `/sys` into the
  chroot. It does *not* need loop devices; the EFI system partition is assembled
  with `mtools` rather than by mounting an image, which is why this works in a
  container at all.
- **`linx1010b-work` is a named volume, not a bind mount.** This is the same
  DrvFs problem as above — the rootfs must be on a real Linux filesystem. `/out`
  can be a Windows bind mount because an ISO is just a file.
- Reclaim the ~10 GB afterwards with `docker volume rm linx1010b-work`.

To run selected stages, append them: `... linx1010b-builder 60 70 80`.

On WSL, Linux or macOS, `./docker/build-in-docker.sh` does all of the above.

---

## Method 3: A Linux VM

VirtualBox, VMware or Hyper-V with Debian 13 or Ubuntu 24.04. Give it 4+ GB RAM
and a 30 GB disk, then follow [build.md](build.md) normally. Slower than WSL2 and
you have to move the ISO out over a shared folder or the network, but it is the
most isolated option.

---

## Writing the ISO to USB from Windows

Use [Rufus](https://rufus.ie/).

1. Select the ISO.
2. When Rufus asks, choose **"Write in DD Image mode"**, not ISO Image mode.
3. Partition scheme **GPT**, target system **UEFI**.

**DD mode is not optional.** In ISO mode Rufus rewrites the boot layout, and on
this image that can lose `BOOTIA32.EFI` — the single file the Linx 1010B needs in
order to boot at all. See [boot-32bit-uefi.md](boot-32bit-uefi.md).

Verify afterwards. In WSL, or on any Linux machine:

```bash
sudo mount /dev/sdX2 /mnt && ls /mnt/EFI/BOOT/
# must list BOOTIA32.EFI
```

From Windows you can check with Rufus's own log, or simply re-run the write in DD
mode if the tablet does not offer the stick as a boot option.

Balena Etcher also works and is always image-mode, so there is no setting to get
wrong. Do not use the Windows built-in "Burn disc image" — it does not do
USB sticks.

---

## Troubleshooting

**`make deps` fails with "Unable to locate package grub-efi-ia32-bin"**
You are on an old WSL distribution image. `sudo apt update` first. If it persists,
check `/etc/apt/sources.list` includes the `main` component.

**Stage 00 fails: "Cannot create device nodes"**
You are building under `/mnt/c`. Move the checkout to `~/` as described above.

**Stage 00 fails: "The filesystem is case-insensitive"**
Same cause, same fix.

**The build is extremely slow**
Almost always the same cause. DrvFs is roughly an order of magnitude slower than
WSL's ext4 for many small files, and this build writes tens of thousands.

**"No space left on device" partway through**
WSL2's disk has a maximum size. Check with `df -h ~`, and expand it with
`wsl --manage Debian --resize <size>` from PowerShell if needed.

**Docker: "operation not permitted" during debootstrap**
You omitted `--privileged`.
