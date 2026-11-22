KERNEL_SRC ?=
BUSYBOX    ?=
CROSS      ?= aarch64-linux-gnu-
OUT        := out

.PHONY: help kernel-build kernel-docker kernel-config kernel initramfs boot qemu renderer-demo renderer-test clean

help:
	@echo "targets: kernel-build kernel-docker kernel-config kernel initramfs boot qemu renderer-demo renderer-test clean"
	@echo "set KERNEL_SRC=/path/to/linux and BUSYBOX=/path/to/static-aarch64-busybox"

kernel-build:
	sh scripts/build-kernel.sh

# Same build inside a Debian container; no cross toolchain needed on the host.
kernel-docker:
	docker run --rm -e HOST_UID=$$(id -u) -e HOST_GID=$$(id -g) -v "$(CURDIR)":/work -w /work debian:bookworm sh -c \
	  'apt-get update -qq && apt-get install -y -qq build-essential gcc-aarch64-linux-gnu flex bison bc libssl-dev libelf-dev git ca-certificates >/dev/null && sh scripts/build-kernel.sh'

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
