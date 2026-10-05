#!/bin/sh
set -e

[ "$#" -eq 1 ] || {
    echo "Usage: $0 /path/to/openwrt-sdk"
    exit 2
}

SDK="$(CDPATH= cd -- "$1" && pwd)"
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

[ -f "$SDK/rules.mk" ] || {
    echo "ERROR: not an OpenWrt SDK: $SDK"
    exit 1
}

DEST="$SDK/package/podkop-sub-sync"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$HERE/package/." "$DEST/"

cd "$SDK"

./scripts/feeds update -a
./scripts/feeds install -a

if ! grep -q '^CONFIG_PACKAGE_podkop-sub-sync=' .config 2>/dev/null; then
    echo 'CONFIG_PACKAGE_podkop-sub-sync=m' >> .config
fi

make defconfig
make package/podkop-sub-sync/clean V=s
make package/podkop-sub-sync/compile V=s

echo
echo "Built package(s):"
find bin -type f \( -name 'podkop-sub-sync_*.ipk' -o -name 'podkop-sub-sync-*.apk' \) -print
