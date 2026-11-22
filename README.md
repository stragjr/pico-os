# Pico

A custom Linux distro for the OnePlus 6 (enchilada, SDM845) with its own
Material You-style renderer, a web + native app runtime, and Android app
support through a container.

The full plan lives in the "Pico OS - Plan" doc. This repo is milestone M0
(first boot) and the start of M1 (renderer demo).

## Layout

| Path | What it is |
| --- | --- |
| `kernel/pico.config` | Kernel config fragment: everything Pico needs on top of the sdm845 mainline defconfig |
| `initramfs/init` | The first userspace program; mounts the basics, starts USB networking and a shell |
| `scripts/mkinitramfs.py` | Packs `initramfs/` and a busybox binary into a gzipped newc cpio archive (no `cpio` needed) |
| `scripts/mkboot.sh` | Wraps kernel + device tree + initramfs into an Android boot image with `mkbootimg` |
| `scripts/run-qemu.sh` | Boots the same kernel and initramfs in QEMU `aarch64 virt` |
| `renderer/` | `pico-renderer`: dependency-free software renderer prototype (rounded rects, tonal color) |
| `Makefile` | Entry points for all of the above |

## What you need on your PC

- `aarch64-linux-gnu-gcc` (cross toolchain) to build the kernel
- A static aarch64 `busybox` binary (set `BUSYBOX=` when running make)
- `mkbootimg` (from the `android-tools` or AOSP `mkbootimg` package)
- `fastboot` and `qemu-system-aarch64`
- Rust (stable) for the renderer

## First boot (M0)

1. Back up the stock partitions and unlock the bootloader (see the plan doc).
2. Get a mainline kernel with the sdm845 enchilada device tree and merge the config:
   `make kernel-config KERNEL_SRC=/path/to/linux`
3. Build the kernel:
   `make kernel KERNEL_SRC=/path/to/linux`
4. Build the initramfs and boot image:
   `make boot BUSYBOX=/path/to/busybox-aarch64 KERNEL_SRC=/path/to/linux`
5. Test from RAM, without flashing anything:
   `fastboot boot out/pico-boot.img`
6. Once the phone shows up as a USB network device, give your PC an address on
   the same network (for example `172.16.42.2/24`) and run `telnet 172.16.42.1`.
   This M0 shell has no password and is only reachable over the USB cable; it is
   replaced by SSH in a later milestone.

## Check before you flash

The boot image offsets and kernel command line in `scripts/mkboot.sh` are
starting values. Confirm them against your own unit (`fastboot getvar all`,
and the unpacked stock `boot.img`) before writing anything with
`fastboot flash`. Always test with `fastboot boot` first.

## Renderer prototype

```
make renderer-demo
```

Writes `out/renderer-demo.png`: a themed card, buttons and a switch drawn with
signed-distance-field rounded rectangles and a tonal palette generated from a
seed color. There is no text yet; text (HarfBuzz + FreeType) is the next step.
