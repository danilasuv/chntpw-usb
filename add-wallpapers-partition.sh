#!/bin/sh
set -eu

cd "$(dirname "$0")"
iso=live-image-amd64.hybrid.iso
photo=config/includes.chroot/usr/local/share/windows-rescue/wallpaper.png

for command in xorriso mkfs.vfat mcopy truncate mktemp; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Install the command $command before building the ISO." >&2
    exit 1
  fi
done
if [ ! -s "$iso" ] || [ ! -s "$photo" ]; then
  echo 'ISO or bundled wallpaper is missing.' >&2
  exit 1
fi

temporary=$(mktemp -d)
trap 'rm -rf -- "$temporary"' EXIT HUP INT TERM
truncate -s 500M "$temporary/wallpapers.fat"
mkfs.vfat -F 32 -n WALLPAPERS "$temporary/wallpapers.fat"
mcopy -i "$temporary/wallpapers.fat" "$photo" ::/wallpaper.png
xorriso -indev "$iso" -outdev "$temporary/with-wallpapers.iso" \
  -append_partition 3 0x0c "$temporary/wallpapers.fat" \
  -boot_image any replay -commit
if [ ! -s "$temporary/with-wallpapers.iso" ]; then
  echo 'Failed to add the WALLPAPERS partition.' >&2
  exit 1
fi
mv -- "$temporary/with-wallpapers.iso" "$iso"
echo 'Added 500 MiB FAT32 WALLPAPERS partition.'
