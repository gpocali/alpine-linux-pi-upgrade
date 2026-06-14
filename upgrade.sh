#!/bin/ash
# Alpine Linux Raspberry Pi Upgrade Script

# Fail immediately if any command exits with a non-zero status
set -e

echo "Detecting boot partition..."
BOOT_PART=""

# Scan typical Alpine mount points for standard Raspberry Pi boot files
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

TMP_DIR=$(mktemp -d)
TAR_FILE="${TMP_DIR}/image.tar.gz"

echo "Downloading ${FILENAME}..."
wget -qO "$TAR_FILE" "$DOWNLOAD_LINK"

echo "Extracting image..."
tar -C "$TMP_DIR" -xf "$TAR_FILE"
rm "$TAR_FILE"

echo "Remounting boot partition as read-write..."
mount -o remount,rw "$BOOT_PART"

echo "Replacing boot directories..."
for dir in "$TMP_DIR"/*/; do
    [ -d "$dir" ] || continue
    dirname=$(basename "$dir")
    rm -rf "${BOOT_PART:?}/${dirname}"
    mv "$dir" "$BOOT_PART/"
done

echo "Replacing root boot files..."
rm -f "$BOOT_PART"/*.dtb "$BOOT_PART"/*.elf "$BOOT_PART"/*.dat
for file in "$TMP_DIR"/*; do
    [ -f "$file" ] && mv "$file" "$BOOT_PART/"
done

rm -rf "$TMP_DIR"

echo "Remounting boot partition as read-only..."
mount -o remount,ro "$BOOT_PART" || true

echo "Updating repositories..."
cat <<EOF > /etc/apk/repositories
https://dl-cdn.alpinelinux.org/alpine/latest-stable/main
https://dl-cdn.alpinelinux.org/alpine/latest-stable/community
EOF

echo "Creating post-upgrade finish script..."
rc-update add local default

cat <<'EOF' > /etc/local.d/99-finish-upgrade.start
#!/bin/ash
sleep 5

echo "Completing Alpine package upgrades..."
apk update
apk upgrade
apk cache sync
apk cache clean

echo "Cleaning up run-once script..."
rm -f "$0"

lbu commit -d
EOF

chmod +x /etc/local.d/99-finish-upgrade.start

echo "Committing initial changes and rebooting..."
lbu commit -d && reboot