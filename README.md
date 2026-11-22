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
| `scripts/mac-build.sh` | One command on macOS: installs tools, fetches sources, builds `out/pico-boot.img` |
| `scripts/docker-build.sh`, `scripts/container-build.sh`, `docker/Dockerfile` | The containerized build (kernel, BusyBox, initramfs, boot image) |
| `scripts/build-kernel.sh` | Fetches Linux, merges `kernel/pico.config`, builds `Image.gz` and the device tree |
| `scripts/mkboot.sh`, `scripts/mkbootimg.py` | Wrap kernel + device tree + initramfs into an Android boot image (pure Python, no AOSP tool needed) |
| `scripts/run-qemu.sh` | Boots the same kernel and initramfs in QEMU `aarch64 virt` |
| `renderer/` | `pico-renderer`: dependency-free software renderer prototype (rounded rects, tonal color) |
| `Makefile` | Entry points for all of the above |

## Quick start on a Mac

```
git clone https://github.com/stragjr/pico-os
cd pico-os
./scripts/mac-build.sh
```

The script installs what it needs with Homebrew (`fastboot`, and `colima` + `docker`
if you have no Docker yet), then builds everything in a Linux container: Linux v6.12,
a static BusyBox, the initramfs, and `out/pico-boot.img`. It needs Homebrew installed
first, about 10 GB of disk, and 20 to 60 minutes the first time. Add `--boot` to be
offered a `fastboot boot` at the end. Read any `WARNING: CONFIG_... is not =y` lines
it prints: they mean a symbol in `kernel/pico.config` does not exist in that kernel
version and must be fixed before the phone can boot it.

The source tree lives in a Docker volume, not a Mac folder, because the Linux
source has file names that differ only by case, which macOS's default filesystem
cannot hold. Linux with Docker can run `make docker-build` for the same result.

## What you need without the Mac script

- Docker (for `make docker-build`), or `aarch64-linux-gnu-gcc` with `flex bison bc` for `make kernel-build`
- A static aarch64 `busybox` binary if you build step by step (set `BUSYBOX=` when running make)
- `fastboot` (Android platform tools)
- Optional: `qemu-system-aarch64`, and Rust (stable) for the renderer

## First boot (M0)

1. Back up the stock partitions and unlock the bootloader (see the plan doc).
2. Build the boot image: `./scripts/mac-build.sh` on a Mac, or `make docker-build`
   on Linux. Use `KERNEL_TAG=v6.x` to pick another kernel version. Step by step:
   `make kernel-build`, then
   `make boot BUSYBOX=/path/to/busybox-aarch64 KERNEL_SRC=build/linux`.
3. (Optional) the same kernel and initramfs can be tried in QEMU with
   `make qemu BUSYBOX=... KERNEL_SRC=build/linux`; QEMU's virt machine does not
   use the enchilada device tree, so this only checks that init runs.
4. Test from RAM, without flashing anything (phone in fastboot mode, power off then
   hold Volume Up + Power): `fastboot boot out/pico-boot.img`
5. Pico shows up as a USB network device (CDC-ECM, which macOS supports; it has no RNDIS driver).
   Find the new interface with `networksetup -listallhardwareports`, give it an address
   (`sudo ifconfig enX 172.16.42.2 netmask 255.255.255.0`, with enX from that list), then run
   `telnet 172.16.42.1`. This M0 shell has no password and is only reachable over the USB
   cable; it is replaced by SSH in a later milestone.

### If the phone stays on the fastboot screen

Two different cases look alike. With the phone still showing the fastboot screen, run on the Mac:

- `fastboot devices`: if the phone is still listed, the bootloader never started the kernel
  (image rejected, or bootloader still locked: check "DEVICE STATE" on the fastboot screen).
- `system_profiler SPUSBDataType | grep -B2 -A8 Pico`: if "Pico OnePlus 6" appears, the kernel
  IS running and only the screen is frozen on the old picture. Pico is then reachable over USB.

## Check before you flash

One command checks Pico's boot image settings against your phone's stock boot image.
Give it a FULL OxygenOS OTA zip for the OnePlus 6 (not an incremental one), a `payload.bin`,
a `boot.img`, or a download link to the zip:

```
./scripts/check-stock-boot.sh ~/Downloads/OnePlus6Oxygen_xxx.zip
```

It extracts the boot partition from the OTA (plain Python, nothing to install), prints its header,
and compares it with `scripts/mkboot.sh` and with `out/pico-boot.img` if you have built it.
`scripts/inspect-bootimg.py` does the comparison part on its own.

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
