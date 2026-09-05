# Convenience wrapper. Everything here just calls build/build.sh, which is the
# real entry point and works fine on its own.

SHELL := /bin/bash

.PHONY: all iso deps clean distclean lint rootfs shell help

help:
	@echo "Linx 1010B Linux image"
	@echo
	@echo "  make deps       Install host build dependencies (Debian/Ubuntu host)"
	@echo "  make iso        Full build -> out/*.iso            (needs root)"
	@echo "  make rootfs     Build the rootfs only, stop before squashfs"
	@echo "  make shell      Open a shell inside the built rootfs (needs root)"
	@echo "  make lint       Shellcheck every script"
	@echo "  make clean      Remove generated images, keep the rootfs"
	@echo "  make distclean  Remove everything in work/ and out/"

all: iso

deps:
	sudo apt-get update
	sudo apt-get install -y --no-install-recommends \
	    debootstrap squashfs-tools xorriso mtools dosfstools rsync \
	    grub-common grub-efi-ia32-bin grub-efi-amd64-bin

iso:
	./build/build.sh

rootfs:
	./build/build.sh 00 10 20 30 40 50

shell:
	@source build/config.sh; \
	  sudo chroot "$${ROOTFS:-$$PWD/work/rootfs}" /bin/bash || true

lint:
	@command -v shellcheck >/dev/null || { echo "install shellcheck first"; exit 1; }
	shellcheck -x build/build.sh build/config.sh build/lib/*.sh \
	    tools/linx-* installer/*.sh || true
	@for f in build/stages/*.sh; do bash -n "$$f" || exit 1; done
	@echo "lint OK"

clean:
	rm -rf work/iso work/efi.img out

distclean:
	@source build/config.sh; \
	  if mountpoint -q "$$PWD/work/rootfs/proc"; then \
	    echo "work/rootfs still has mounts; refusing. Run: sudo umount -R work/rootfs/{proc,sys,dev,run}"; exit 1; \
	  fi
	rm -rf work out
