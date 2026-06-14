#!/bin/ash
# Alpine Linux Raspberry Pi Upgrade Script (Low-Memory & Auto-Update Optimized)

# Fail immediately if any command exits with a non-zero status
set -e

INSTALL_CRON=0
CRON_MODE=0

# Parse command line flags
while getopts "ac" opt; do
    case ${opt} in
        a ) INSTALL_CRON=1 ;;
        c ) CRON_MODE=1 ;;
        \? ) echo "Usage: $0 [-a] (install auto-update cron)" >&2; exit 1 ;;
    esac
done

echo "Detecting boot partition..."
BOOT_PART=""

for dir in /media/* /boot; do
    if [ -d "$dir" ] && [ -f "$dir/config.txt" ] && [ -f "$dir/cmdline.txt" ]; then
        BOOT_PART="$dir"
        break
    fi
done

if [ -z "$BOOT_PART" ]; then
    echo "Error: Could not dynamically locate the Raspberry Pi boot partition."
    exit 1
fi

echo "Boot partition identified at: $BOOT_PART"

YAML_URL="https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/latest-releases.yaml"
BASE_URL="${YAML_URL%/*}"

echo "Fetching latest release info..."
FILENAME=$(wget -qO- "$YAML_URL" | awk '/file:.*rpi.*\.tar\.gz/ {print $2; exit}')
DOWNLOAD_LINK="${BASE_URL}/${FILENAME}"

# Version check for automated runs
CURRENT_VER=$(cat /etc/alpine-release 2>/dev/null || echo "0.0.0")

# If the current version string exists inside the latest filename, we are up to date
if echo "$FILENAME" | grep -q "$CURRENT_VER"; then
    if [ "$CRON_MODE" = 1 ]; then
        echo "System is already running the latest version ($CURRENT_VER). Cron job exiting cleanly."
        exit 0
    else
        echo "System is already at version $CURRENT_VER. Proceeding anyway due to manual execution..."
    fi
else
    echo "New version detected or forced run. Current: $CURRENT_VER, Latest Target: $FILENAME"
fi

echo "Remounting boot partition as read-write to prepare staging area..."
mount -o remount,rw "$BOOT_PART"

STAGING_DIR="${BOOT_PART}/upgrade_staging"
mkdir -p "$STAGING_DIR"
TAR_FILE="${STAGING_DIR}/image.tar.gz"

echo "Downloading ${FILENAME} directly to boot media..."
wget -qO "$TAR_FILE" "$DOWNLOAD_LINK"

echo "Extracting image on boot media..."
tar -C "$STAGING_DIR" -xf "$TAR_FILE"

echo "Removing tarball to free up disk space before moving files..."
rm "$TAR_FILE"

echo "Replacing boot directories..."
for dir in "$STAGING_DIR"/*/; do
    [ -d "$dir" ] || continue
    dirname=$(basename "$dir")
    [ "$dirname" = "upgrade_staging" ] && continue
    rm -rf "${BOOT_PART:?}/${dirname}"
    mv "$dir" "$BOOT_PART/"
done

echo "Replacing root boot files..."
rm -f "$BOOT_PART"/*.dtb "$BOOT_PART"/*.elf "$BOOT_PART"/*.dat
for file in "$STAGING_DIR"/*; do
    [ -f "$file" ] && mv "$file" "$BOOT_PART/"
done

echo "Cleaning up staging directory..."
rm -rf "$STAGING_DIR"

echo "Remounting boot partition as read-only..."
mount -o remount,ro "$BOOT_PART"

echo "Updating repositories to HTTPS and latest-stable..."
sed -i 's|http://|https://|g' /etc/apk/repositories
sed -i -E 's|/v[0-9]+\.[0-9]+/|/latest-stable/|g' /etc/apk/repositories

if [ "$INSTALL_CRON" = 1 ]; then
    echo "Installing monthly cron job for automatic updates..."
    mkdir -p /etc/periodic/monthly
    
    # Create the cron script that calls the raw GitHub file with the -c flag
    cat << 'CRONEOF' > /etc/periodic/monthly/alpine-upgrade
#!/bin/ash
# Automated monthly Alpine upgrade
exec > /var/log/alpine-cron-upgrade.log 2>&1
wget -qO- https://raw.githubusercontent.com/gpocali/alpine-linux-pi-upgrade/main/upgrade.sh | sh -s -- -c
CRONEOF
    
    chmod +x /etc/periodic/monthly/alpine-upgrade
    
    # Ensure the cron service is enabled and started
    rc-update add crond default
    rc-service crond start || true
fi

echo "Creating post-upgrade finish script..."
rc-update add local default

cat <<'EOF' > /etc/local.d/99-finish-upgrade.start
#!/bin/ash
exec > /var/log/alpine-upgrade.log 2>&1

echo "Starting post-upgrade sequence..."

check_network() {
    ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 2 dl-cdn.alpinelinux.org >/dev/null 2>&1
}

echo "Waiting for network connectivity..."
NETWORK_UP=false
for i in $(seq 1 6); do
    if check_network; then
        NETWORK_UP=true
        break
    fi
    sleep 5
done

if [ "$NETWORK_UP" = false ]; then
    echo "Network check failed. Attempting to restart networking service..."
    rc-service networking restart
    sleep 5
    if ! check_network; then
        echo "Still no network. Forcing DHCP renewal on hardwired interface (eth0)..."
        udhcpc -i eth0 -q
        sleep 5
        if ! check_network; then
            echo "CRITICAL: Network could not be restored. Aborting upgrade finish."
            exit 1
        fi
    fi
fi

echo "Network is up. Performing base system upgrade..."
apk update
apk upgrade --available

echo "Reinstalling all configured packages to ensure clean binary state..."
WORLD_PKGS=$(grep -v '^#' /etc/apk/world | tr '\n' ' ')
if [ -n "$WORLD_PKGS" ]; then
    apk add --force-reinstall $WORLD_PKGS
fi

echo "Syncing and cleaning package cache..."
apk cache sync
apk cache clean

echo "Cleaning up run-once script..."
rm -f "$0"

echo "Committing final state..."
lbu commit -d

echo "Rebooting into finalized system..."
reboot
EOF

chmod +x /etc/local.d/99-finish-upgrade.start

echo "Committing initial changes and rebooting into new kernel..."
lbu commit -d && reboot