# Alpine Linux Raspberry Pi Upgrade

A robust, automated script to upgrade an Alpine Linux "diskless" installation on a Raspberry Pi to the latest stable `aarch64` release.

## Overview

This repository provides a streamlined `upgrade.sh` script designed to handle the complexities of upgrading a diskless Alpine Linux environment. It dynamically locates your boot media, fetches the latest release from the official Alpine CDN, safely swaps out the core boot files, and stages a run-once init script to handle the final package synchronizations upon reboot.

## Features

* **Dynamic Media Detection:** Automatically scans `/media/*` and `/boot` to identify the correct boot partition (whether it's an SD card, USB drive, or NVMe) by verifying the presence of essential Pi bootloader files (`config.txt`, `cmdline.txt`).
* **Safe Extraction:** Downloads and extracts the latest image to a temporary directory, replacing boot files without disrupting your current running environment.
* **Automated Package Sync:** Leverages OpenRC's `/etc/local.d/` facility to create a run-once script (`99-finish-upgrade.start`). On the first boot after the kernel upgrade, it automatically runs `apk update`, `apk upgrade`, syncs the diskless cache, cleans up old packages, and seals the changes with `lbu commit`.
* **Failsafes:** Built with `set -e` and shell variable protections to prevent catastrophic deletions if a download or mount point fails.

## Quick Start

You can execute this script directly from the repository using `wget` piped into `sh`. 

**Note:** This script must be run as `root`.

```sh
wget -qO- https://raw.githubusercontent.com/gpocali/alpine-linux-pi-upgrade/main/upgrade.sh | sh

```

## What the Script Does

1. Locates the active Raspberry Pi boot partition.
2. Scrapes the Alpine CDN to find the latest `aarch64` Raspberry Pi tarball.
3. Downloads and extracts the tarball to `/tmp`.
4. Remounts the boot partition as read-write.
5. Replaces system directories (`boot`, `apks`, etc.) and root boot files (`*.dtb`, `*.elf`, `*.dat`).
6. Updates `/etc/apk/repositories` to point to the `latest-stable` branch.
7. Generates the post-upgrade OpenRC script and enables the `local` service.
8. Commits the current state using `lbu commit -d` and reboots.
9. On next boot, completes the package updates and cleans itself up.

## Prerequisites

* A Raspberry Pi running Alpine Linux in "diskless" mode.
* An active internet connection.
* Root privileges.

## Disclaimer

Always ensure you have a backup of your `config.txt`, `cmdline.txt`, and `.apkovl` files before performing major version upgrades. Use at your own risk.
