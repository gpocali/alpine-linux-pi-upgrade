# Alpine Linux Raspberry Pi Upgrade

A robust, multi-architecture, and fully automated script to upgrade an Alpine Linux "diskless" installation on a Raspberry Pi to the latest stable release.

## Overview

This repository provides a highly optimized `upgrade.sh` script designed to handle the complexities of upgrading a diskless Alpine Linux environment. It dynamically detects your Raspberry Pi hardware to fetch the correct architecture (`aarch64`, `armv7`, or `armhf`), locates your boot media, safely extracts updates without exhausting system memory, intelligently updates repository URLs, ensures network connectivity upon reboot, reinstalls your configured packages, and can even install itself as a monthly automated cron job.

## Features

* **Multi-Architecture Support:** Dynamically parses the hardware signature (`/proc/device-tree/model`) to identify your exact Raspberry Pi model. Automatically selects and downloads the correct Alpine architecture (`aarch64` for Pi 3/4/5/Zero 2, `armv7` for Pi 2, and `armhf` for Pi 1/Zero 1) and handles cross-architecture upgrade states safely.
* **Low-Memory Optimization:** Bypasses RAM (`tmpfs`) limitations entirely by creating a staging directory directly on the physical boot media. This prevents Out-Of-Memory (OOM) crashes on older hardware or heavily loaded systems during the extraction phase.
* **Dynamic Media Detection:** Automatically scans `/media/*` and `/boot` to identify the correct boot partition (SD card, USB drive, or NVMe) by verifying the presence of essential Pi bootloader files (`config.txt`, `cmdline.txt`).
* **Smart Repository Updates:** Parses `/etc/apk/repositories` to upgrade all `http://` links to `https://`, and seamlessly updates specific version tags (like `v3.18`) to `latest-stable` while safely leaving `edge` repositories intact.
* **Network Resilience:** The post-upgrade script includes a robust network health check. If connectivity fails, it automatically attempts to restart the networking service and, as a fallback, forces a DHCP renewal specifically on the hardwired interface (`eth0`).
* **Stateful Package Reinstallation:** Rather than just updating the base system, it reads your explicitly installed package list (`/etc/apk/world`) and forces a clean reinstallation. This ensures all your custom binaries are perfectly matched to the newly installed kernel and libraries.
* **Automated Package Sync:** Leverages OpenRC's `/etc/local.d/` facility to create a run-once script (`99-finish-upgrade.start`). On the first boot, it synchronizes the cache, cleans old packages, and seals the final state with `lbu commit`.
* **Auto-Update Cron Job:** Run the installer with an optional `-a` flag to deploy a monthly cron job. The cron job will automatically pull the latest script from GitHub, check the Alpine CDN for a newer version, and seamlessly upgrade your Pi if an update is found.

## Quick Start

You can execute this script directly from the repository using `wget` piped into `sh`. 

**Note:** This script must be run as `root`.

### 1. Manual Upgrade (One-Time)
Run the script manually without installing any scheduled tasks:

```sh
wget -qO- https://raw.githubusercontent.com/gpocali/alpine-linux-pi-upgrade/main/upgrade.sh | sh

```

### 2. Upgrade + Install Monthly Auto-Update Cron Job
Pass the `-a` flag to perform an immediate upgrade (if applicable) and schedule a monthly check:
```sh
wget -qO- https://raw.githubusercontent.com/gpocali/alpine-linux-pi-upgrade/main/upgrade.sh | sh -s -- -a

```

## What the Script Does

1. Parses the hardware tree to determine if the Pi requires `aarch64`, `armv7`, or `armhf`.
2. Locates the active Raspberry Pi boot partition.
3. Checks the Alpine CDN for the latest targeted architecture tarball. (If run via cron, it compares versions and exits cleanly if up to date).
4. Remounts the boot partition as read-write and creates a staging directory directly on the disk.
5. Downloads, extracts, and organizes the new boot files without exhausting system RAM.
6. Intelligently updates `/etc/apk/repositories` to `https://` and `latest-stable`.
7. Generates the post-upgrade OpenRC script and enables the `local` service.
8. Installs the cron job if the `-a` flag was provided.
9. Commits the current state using `lbu commit -d` and reboots.
10. **On Next Boot:** Verifies network health (auto-recovering if needed), upgrades base packages, reinstalls all `world` packages, cleans the cache, commits the final state, and reboots one last time into the finalized environment.

## Prerequisites

* A Raspberry Pi running Alpine Linux in "diskless" mode.
* An active internet connection.
* Root privileges.

## Disclaimer

Always ensure you have a backup of your `config.txt`, `cmdline.txt`, and `.apkovl` files before performing major version upgrades. Use at your own risk.
