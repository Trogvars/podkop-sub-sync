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

PRECHECK="$HERE/package/files/usr/bin/podkop-sub-precheck"
grep -q '^precheck_log()' "$PRECHECK" || {
    echo "ERROR: precheck must use its own stdout logger"
    exit 1
}
grep -Fq '    . /usr/lib/podkop/logging.sh' "$PRECHECK" || {
    echo "ERROR: precheck must load Podkop logging for facade calls"
    exit 1
}
if grep -q '^log(){ printf ' "$PRECHECK"; then
    echo "ERROR: precheck stdout log() would contaminate facade JSON"
    exit 1
fi
grep -Fq 'json_valid "$NEW_CONFIG"' "$PRECHECK" || {
    echo "ERROR: parser JSON validation guard is missing"
    exit 1
}


SYNC="$HERE/package/files/usr/bin/podkop-sub-sync"
grep -Fq 'OLD_SB_PIDS="$(singbox_pids)"' "$SYNC" || {
    echo "ERROR: updater must snapshot old sing-box PIDs before Podkop apply"
    exit 1
}
grep -Fq 'New sing-box process detected: PID $TRACKED_PID' "$SYNC" || {
    echo "ERROR: updater must wait for a fresh sing-box process"
    exit 1
}
if grep -Fq 'sing-box check -c "$SINGCONF"' "$SYNC"; then
    echo "ERROR: updater must not run a redundant post-start sing-box check"
    exit 1
fi

grep -Fq 'SEC="${1:-main}"' "$SYNC" || {
    echo "ERROR: updater must accept a named sync section"
    exit 1
}
grep -Fq 'TARGET="$SEC"' "$SYNC" || {
    echo "ERROR: sync section must map directly to the same Podkop section"
    exit 1
}
if grep -Fq 'cfg_get target' "$SYNC"; then
    echo "ERROR: legacy target mapping must not be used by runtime"
    exit 1
fi
grep -Fq '/usr/bin/podkop-sub-precheck "$LIST" "$PRECHECKED" "$SEC"' "$SYNC" || {
    echo "ERROR: updater must pass the sync section to precheck"
    exit 1
}

DAEMON="$HERE/package/files/usr/bin/podkop-sub-sync-daemon"
grep -Fq '/usr/bin/podkop-sub-sync "$SEC"' "$DAEMON" || {
    echo "ERROR: daemon must schedule each named sync section"
    exit 1
}
if grep -Fq 'podkop-sub-sync.main.interval' "$DAEMON"; then
    echo "ERROR: daemon is still hard-coded to main"
    exit 1
fi

grep -Fq 'SEC="${3:-main}"' "$PRECHECK" || {
    echo "ERROR: precheck must accept the sync section as argument 3"
    exit 1
}

for json in \
    "$HERE/package/files/usr/share/luci/menu.d/luci-app-podkop-sub-sync.json" \
    "$HERE/package/files/usr/share/rpcd/acl.d/luci-app-podkop-sub-sync.json"
do
    python3 -m json.tool "$json" >/dev/null
done

LUCI_VIEW="$HERE/package/files/www/luci-static/resources/view/podkop-sub-sync/overview.js"
grep -Fq "uci.load('podkop')" "$LUCI_VIEW" || {
    echo "ERROR: LuCI must load Podkop sections dynamically"
    exit 1
}
grep -Fq "connection_type=proxy" "$LUCI_VIEW" || {
    echo "ERROR: LuCI must enforce Podkop proxy section targets"
    exit 1
}
grep -Fq "A sync section named" "$LUCI_VIEW" || {
    echo "ERROR: LuCI must reject duplicate sync section names"
    exit 1
}

if command -v node >/dev/null 2>&1; then
    node --check "$LUCI_VIEW"
fi

echo "Checks passed for podkop-sub-sync $ROOT_VERSION"
