#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo 'Run as root: sudo ./build.sh' >&2
  exit 1
fi
if ! command -v lb >/dev/null 2>&1; then
  echo 'Install live-build first: apt install live-build' >&2
  exit 1
fi
cd "$(dirname "$0")"
chmod +x auto/config config/includes.chroot/usr/local/sbin/rescue-menu config/includes.chroot/usr/local/sbin/promote-admin config/includes.chroot/usr/local/sbin/rescue-gui config/includes.chroot/usr/local/bin/start-rescue-gui
lb clean --all
lb config
lb build
if [ ! -s live-image-amd64.hybrid.iso ]; then
  echo 'Build did not produce an ISO; inspect live-build output.' >&2
  exit 1
fi
sh add-wallpapers-partition.sh
sha256sum live-image-amd64.hybrid.iso > live-image-amd64.hybrid.iso.sha256
echo 'ISO and SHA-256 checksum are ready.'
