#!/bin/ash
set -e

REPO="Trogvars/podkop-sub-sync"
REF="${PODKOP_SYNC_REF:-main}"

TMP="$(mktemp -d /tmp/podkop-sub-sync-install.XXXXXX)" || exit 1
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

URL="https://github.com/${REPO}/archive/${REF}.tar.gz"
DST="$TMP/src.tar.gz"

echo "[podkop-sub-sync] Downloading ${REPO}@${REF}..."

if command -v wget >/dev/null 2>&1; then
    wget -qO "$DST" "$URL"
elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$URL" -o "$DST"
else
    echo "ERROR: wget or curl is required"
    exit 1
fi

[ -s "$DST" ] || {
    echo "ERROR: downloaded archive is empty"
    exit 1
}

tar -xzf "$DST" -C "$TMP" || {
    echo "ERROR: failed to unpack source archive"
    exit 1
}

INSTALLER="$(find "$TMP" -type f -name install-local.sh | head -n 1)"
[ -n "$INSTALLER" ] || {
    echo "ERROR: install-local.sh not found in downloaded project"
    exit 1
}

chmod 755 "$INSTALLER"
exec "$INSTALLER" "$@"
