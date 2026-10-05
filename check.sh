#!/bin/sh
set -e

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

FILES="
$HERE/install.sh
$HERE/install-local.sh
$HERE/build-package.sh
$HERE/check.sh
$HERE/package/files/usr/bin/podkop-sub-sync
$HERE/package/files/usr/bin/podkop-sub-precheck
$HERE/package/files/usr/bin/podkop-sub-sync-daemon
$HERE/package/files/usr/lib/podkop-sub-sync/common.sh
$HERE/package/files/etc/init.d/podkop-sub-sync
"

for f in $FILES; do
    sh -n "$f"
done

ROOT_VERSION="$(cat "$HERE/VERSION")"
PKG_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$HERE/package/Makefile" | head -n 1)"

[ "$ROOT_VERSION" = "$PKG_VERSION" ] || {
    echo "ERROR: VERSION ($ROOT_VERSION) != package/Makefile ($PKG_VERSION)"
    exit 1
}

echo "Checks passed for podkop-sub-sync $ROOT_VERSION"
