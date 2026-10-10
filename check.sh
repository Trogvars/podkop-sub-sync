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
    if command -v busybox >/dev/null 2>&1; then
        busybox ash -n "$f"
    fi
done

ROOT_VERSION="$(cat "$HERE/VERSION")"
PKG_VERSION="$(sed -n 's/^PKG_VERSION:=//p' "$HERE/package/Makefile" | head -n 1)"

[ "$ROOT_VERSION" = "$PKG_VERSION" ] || {
    echo "ERROR: VERSION ($ROOT_VERSION) != package/Makefile ($PKG_VERSION)"
    exit 1
}

# Capability regression tests for XHTTP dependency detection.
COMMON="$HERE/package/files/usr/lib/podkop-sub-sync/common.sh"
# shellcheck disable=SC1090
. "$COMMON"

TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT INT TERM
PSS_PODKOP_FACADE="$TEST_TMP/sing_box_config_facade.sh"

printf '%s\n' '        xhttp)' >"$PSS_PODKOP_FACADE"
pss_has_xhttp_parser || {
    echo "ERROR: legacy xhttp parser form was not detected"
    exit 1
}

printf '%s\n' '        xhttp | splithttp)' >"$PSS_PODKOP_FACADE"
pss_has_xhttp_parser || {
    echo "ERROR: modern xhttp | splithttp parser form was not detected"
    exit 1
}

printf '%s\n' '        websocket)' >"$PSS_PODKOP_FACADE"
if pss_has_xhttp_parser; then
    echo "ERROR: non-XHTTP parser was detected as XHTTP-capable"
    exit 1
fi

pss_singbox_version(){
    printf '%s\n' 'sing-box version 1.13.21-pdk-r14'         'Features: urltest.fallbacks,urltest.download_url,transport.xhttp,tools.decode-link'
}
pss_has_xhttp_engine || {
    echo "ERROR: podkop-engine transport.xhttp capability was not detected"
    exit 1
}

pss_singbox_version(){
    printf '%s\n' 'sing-box version 1.14.1-extended-2.7.2'
}
pss_has_xhttp_engine || {
    echo "ERROR: sing-box-extended compatibility was not detected"
    exit 1
}

pss_singbox_version(){
    printf '%s\n' 'sing-box version 1.13.21'
}
if pss_has_xhttp_engine; then
    echo "ERROR: stock sing-box was detected as XHTTP-capable"
    exit 1
fi

echo "Checks passed for podkop-sub-sync $ROOT_VERSION"
