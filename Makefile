KERNEL_SRC ?=
BUSYBOX    ?=
CROSS      ?= aarch64-linux-gnu-
OUT        := out

.PHONY: help build kernel-build docker-build kernel-config kernel initramfs boot qemu renderer-demo renderer-test clean

help:
	@echo "targets: build docker-build kernel-build kernel-config kernel initramfs boot qemu renderer-demo renderer-test clean"
	@echo "set KERNEL_SRC=/path/to/linux and BUSYBOX=/path/to/static-aarch64-busybox"

kernel-build:
	sh scripts/build-kernel.sh

# Everything natively (needs an aarch64 cross-compiler; on Arch, ./scripts/arch-build.sh installs it).
build:
	sh scripts/build-all.sh

# Everything (kernel, BusyBox, initramfs, boot image) in a Linux container. Works on macOS too;
# on a Mac, ./scripts/mac-build.sh also installs the tools for you.
docker-build:
	sh scripts/docker-build.sh

kernel-config:
	@test -n "$(KERNEL_SRC)" || (echo "set KERNEL_SRC" && exit 1)
	cd $(KERNEL_SRC) && ARCH=arm64 CROSS_COMPILE=$(CROSS) make defconfig
	cd $(KERNEL_SRC) && ARCH=arm64 CROSS_COMPILE=$(CROSS) ./scripts/kconfig/merge_config.sh -m .config $(CURDIR)/kernel/pico.config
	cd $(KERNEL_SRC) && ARCH=arm64 CROSS_COMPILE=$(CROSS) make olddefconfig

kernel:
	@test -n "$(KERNEL_SRC)" || (echo "set KERNEL_SRC" && exit 1)
	cd $(KERNEL_SRC) && ARCH=arm64 CROSS_COMPILE=$(CROSS) make -j$$(nproc) Image.gz dtbs

initramfs:
	@test -n "$(BUSYBOX)" || (echo "set BUSYBOX" && exit 1)
	python3 scripts/mkinitramfs.py --root initramfs --busybox $(BUSYBOX) --out $(OUT)/initramfs.cpio.gz

boot: initramfs
	@test -n "$(KERNEL_SRC)" || (echo "set KERNEL_SRC" && exit 1)
	sh scripts/mkboot.sh $(KERNEL_SRC) $(OUT)/initramfs.cpio.gz $(OUT)/pico-boot.img

qemu: initramfs
	@test -n "$(KERNEL_SRC)" || (echo "set KERNEL_SRC" && exit 1)
	sh scripts/run-qemu.sh $(KERNEL_SRC)/arch/arm64/boot/Image $(OUT)/initramfs.cpio.gz

renderer-demo:
	mkdir -p $(OUT)
	cd renderer && cargo run --release --example demo -- ../$(OUT)/renderer-demo.png

renderer-test:
	cd renderer && cargo test

clean:
	rm -rf $(OUT)
	cd renderer && cargo clean
