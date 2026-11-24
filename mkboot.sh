#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 4 ]; then
    echo "Usage: $0 Image ramdisk.img resource.img boot.img" >&2
    exit 2
fi

for image in "$1" "$2" "$3"; do
    if [ ! -f "$image" ] || [ ! -s "$image" ]; then
        echo "Missing or empty input image: $image" >&2
        exit 1
    fi
done

device_dir=$(cd "$(dirname "$0")" && pwd)
aosp=$(cd "$device_dir/../../.." && pwd)
boot_limit=$(awk '$1 == "BOARD_BOOTIMAGE_PARTITION_SIZE" { print $3 }' "$device_dir/BoardConfig.mk")
tmp=$(mktemp "${4}.tmp.XXXXXX")
trap 'unlink "$tmp"' EXIT

python3 "$aosp/system/core/mkbootimg/mkbootimg" \
    --kernel "$1" --ramdisk "$2" --second "$3" \
    --cmdline 'androidboot.hardware=rk3308 console=ttyFIQ0 androidboot.console=ttyFIQ0' \
    --board rk3308 --os_version 8.1.0 --output "$tmp"

if [ "$(wc -c < "$tmp")" -gt "$boot_limit" ]; then
    echo "Boot image exceeds the $boot_limit-byte E1 boot partition" >&2
    exit 1
fi

chmod 0644 "$tmp"
mv -f "$tmp" "$4"
trap - EXIT
