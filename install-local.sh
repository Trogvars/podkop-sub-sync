#!/bin/ash
set -e

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SRC="$ROOT/package/files"
[ -r "$ROOT/VERSION" ] || {
    echo "ERROR: VERSION file is missing from source tree"
    exit 1
}
VERSION="$(cat "$ROOT/VERSION")"

SUB_URL=""
INTERVAL=""
MAX_NODES=""
INCLUDES=""
EXCLUDES=""
NO_START=0
WITH_XHTTP=0

usage(){
    cat <<'EOF'
Usage: install-local.sh [options]

  --url URL        VPN subscription URL
  --interval SEC   Refresh interval in seconds
  --max-nodes N    Keep only N fastest working nodes after precheck (0 = unlimited)
  --include CC     Keep only this country; repeatable: --include RU --include KZ
  --exclude CC     Exclude country; repeatable: --exclude RU --exclude UZ
  --with-xhttp     Enable XHTTP and automatically install/check its dependencies
  --no-start       Install and enable, but do not start now
  -h, --help       Show this help
EOF
}

need_value(){
    [ "$#" -ge 2 ] && [ -n "$2" ] || {
        echo "ERROR: $1 requires a value"
        exit 2
    }
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --url)
            need_value "$@"
            SUB_URL="$2"
            shift 2
            ;;
        --interval)
            need_value "$@"
            INTERVAL="$2"
            shift 2
            ;;
        --max-nodes)
            need_value "$@"
            MAX_NODES="$2"
            shift 2
            ;;
        --include)
            need_value "$@"
            INCLUDES="${INCLUDES}${INCLUDES:+ }$2"
            shift 2
            ;;
        --exclude)
            need_value "$@"
            EXCLUDES="${EXCLUDES}${EXCLUDES:+ }$2"
            shift 2
            ;;
        --with-xhttp)
            WITH_XHTTP=1
            shift
            ;;
        --no-start)
            NO_START=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown option: $1"
            usage
            exit 2
            ;;
    esac
done

[ "$(id -u)" = 0 ] || { echo "ERROR: run as root"; exit 1; }
[ -r /etc/openwrt_release ] || { echo "ERROR: OpenWrt is required"; exit 1; }

# shellcheck disable=SC1091
. /etc/openwrt_release
OPENWRT_VERSION="${DISTRIB_RELEASE:-unknown}"

case "$OPENWRT_VERSION" in
    24.*)
        PKG_MANAGER="opkg"
        FAMILY="24.x (opkg/IPK)"
        ;;
    25.*)
        PKG_MANAGER="apk"
        FAMILY="25.x (apk/APK)"
        ;;
    *)
        echo "ERROR: unsupported OpenWrt version: $OPENWRT_VERSION"
        echo "Supported versions: OpenWrt 24.x and 25.x"
        exit 1
        ;;
esac

command -v "$PKG_MANAGER" >/dev/null 2>&1 || {
    echo "ERROR: expected package manager '$PKG_MANAGER' was not found"
    exit 1
}

[ -f /etc/config/podkop ] || { echo "ERROR: /etc/config/podkop not found"; exit 1; }
[ -r /usr/lib/podkop/sing_box_config_facade.sh ] || { echo "ERROR: Podkop libraries not found"; exit 1; }
command -v sing-box >/dev/null 2>&1 || { echo "ERROR: sing-box not found"; exit 1; }

echo "[podkop-sub-sync] Version: $VERSION"
echo "[podkop-sub-sync] Detected OpenWrt $OPENWRT_VERSION -> $FAMILY"

install_dependencies(){
    case "$PKG_MANAGER" in
        opkg)
            echo "Updating opkg lists..."
            opkg update
            for p in curl jq ca-bundle; do
                opkg status "$p" 2>/dev/null | grep -q '^Status: .* installed' ||
                    opkg install "$p"
            done
            ;;
        apk)
            echo "Updating apk indexes..."
            apk update
            for p in curl jq ca-bundle; do
                apk info -e "$p" >/dev/null 2>&1 || apk add "$p"
            done
            ;;
    esac
}

install_dependencies

for c in curl jq uci; do
    command -v "$c" >/dev/null 2>&1 || {
        echo "ERROR: required command missing after dependency install: $c"
        exit 1
    }
done

BACKUP_DIR="/root/podkop-sub-sync-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

backup_if_exists(){
    src="$1"
    [ -e "$src" ] || return 0

    dst="$BACKUP_DIR$src"
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
}

for f in \
    /usr/bin/podkop-sub-sync \
    /usr/bin/podkop-sub-precheck \
    /usr/bin/podkop-sub-sync-daemon \
    /usr/lib/podkop-sub-sync/common.sh \
    /usr/share/podkop-sub-sync/VERSION \
    /etc/init.d/podkop-sub-sync \
    /etc/config/podkop-sub-sync
do
    backup_if_exists "$f"
done

if [ -x /etc/init.d/podkop-sub-sync ]; then
    /etc/init.d/podkop-sub-sync stop >/dev/null 2>&1 || true
fi

mkdir -p \
    /usr/bin \
    /usr/lib/podkop-sub-sync \
    /usr/share/podkop-sub-sync \
    /etc/init.d \
    /etc/config

cp "$SRC/usr/bin/podkop-sub-sync" /usr/bin/podkop-sub-sync
cp "$SRC/usr/bin/podkop-sub-precheck" /usr/bin/podkop-sub-precheck
cp "$SRC/usr/bin/podkop-sub-sync-daemon" /usr/bin/podkop-sub-sync-daemon
cp "$SRC/usr/lib/podkop-sub-sync/common.sh" /usr/lib/podkop-sub-sync/common.sh
cp "$SRC/etc/init.d/podkop-sub-sync" /etc/init.d/podkop-sub-sync
printf '%s\n' "$VERSION" >/usr/share/podkop-sub-sync/VERSION

chmod 755 \
    /usr/bin/podkop-sub-sync \
    /usr/bin/podkop-sub-precheck \
    /usr/bin/podkop-sub-sync-daemon \
    /etc/init.d/podkop-sub-sync

chmod 644 /usr/lib/podkop-sub-sync/common.sh /usr/share/podkop-sub-sync/VERSION

if [ ! -f /etc/config/podkop-sub-sync ]; then
    cp "$SRC/etc/config/podkop-sub-sync" /etc/config/podkop-sub-sync
    chmod 600 /etc/config/podkop-sub-sync
else
    echo "Preserving existing /etc/config/podkop-sub-sync"
fi

if ! uci -q get podkop-sub-sync.main >/dev/null 2>&1; then
    uci set podkop-sub-sync.main='sync'
    uci set podkop-sub-sync.main.enabled='1'
    uci set podkop-sub-sync.main.url=''
    uci set podkop-sub-sync.main.target='main'
    uci set podkop-sub-sync.main.interval='86400'
    uci set podkop-sub-sync.main.retry_interval='900'
    uci set podkop-sub-sync.main.send_hwid='0'
    uci set podkop-sub-sync.main.allow_xhttp='0'
    uci set podkop-sub-sync.main.enable_vless='1'
    uci set podkop-sub-sync.main.enable_trojan='1'
    uci set podkop-sub-sync.main.enable_ss='1'
    uci set podkop-sub-sync.main.precheck_enabled='1'
    uci set podkop-sub-sync.main.precheck_url='https://www.gstatic.com/generate_204'
    uci set podkop-sub-sync.main.precheck_http_code='204'
    uci set podkop-sub-sync.main.precheck_connect_timeout='3'
    uci set podkop-sub-sync.main.precheck_timeout='7'
    uci set podkop-sub-sync.main.precheck_batch_size='6'
    uci set podkop-sub-sync.main.precheck_base_port='39000'
    uci set podkop-sub-sync.main.precheck_min_nodes='3'
    uci set podkop-sub-sync.main.precheck_min_percent='20'
    uci set podkop-sub-sync.main.precheck_max_nodes='20'
    uci set podkop-sub-sync.main.precheck_insecure_tls='0'
fi

uci -q get podkop-sub-sync.main.retry_interval >/dev/null 2>&1 ||
    uci set podkop-sub-sync.main.retry_interval='900'

case "$INTERVAL" in
    '') ;;
    *[!0-9]*) echo "ERROR: interval must be an integer number of seconds"; exit 2 ;;
    *) uci set "podkop-sub-sync.main.interval=${INTERVAL}" ;;
esac

case "$MAX_NODES" in
    '') ;;
    *[!0-9]*) echo "ERROR: max-nodes must be an integer >= 0"; exit 2 ;;
    *) uci set "podkop-sub-sync.main.precheck_max_nodes=${MAX_NODES}" ;;
esac

[ -n "$SUB_URL" ] && {
    uci set "podkop-sub-sync.main.url=${SUB_URL}"
    uci set podkop-sub-sync.main.enabled='1'
}

validate_country(){
    cc="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
    case "$cc" in
        [A-Z][A-Z]) printf '%s\n' "$cc" ;;
        *) return 1 ;;
    esac
}

if [ -n "$INCLUDES" ]; then
    uci -q delete podkop-sub-sync.main.include_country || true

    for raw_cc in $INCLUDES; do
        cc="$(validate_country "$raw_cc")" || {
            echo "ERROR: invalid include country: $raw_cc"
            exit 2
        }
        uci add_list "podkop-sub-sync.main.include_country=${cc}"
    done
fi

if [ -n "$EXCLUDES" ]; then
    uci -q delete podkop-sub-sync.main.exclude_country || true

    for raw_cc in $EXCLUDES; do
        cc="$(validate_country "$raw_cc")" || {
            echo "ERROR: invalid exclude country: $raw_cc"
            exit 2
        }
        uci add_list "podkop-sub-sync.main.exclude_country=${cc}"
    done
fi

[ "$WITH_XHTTP" = 1 ] && uci set podkop-sub-sync.main.allow_xhttp='1'

uci commit podkop-sub-sync

COMMON="/usr/lib/podkop-sub-sync/common.sh"
# shellcheck disable=SC1090
. "$COMMON"

if [ "$(uci -q get podkop-sub-sync.main.allow_xhttp 2>/dev/null || echo 0)" = 1 ]; then
    pss_ensure_xhttp_stack || {
        echo "ERROR: XHTTP dependency setup failed"
        exit 1
    }
fi

for f in \
    /usr/bin/podkop-sub-sync \
    /usr/bin/podkop-sub-precheck \
    /usr/bin/podkop-sub-sync-daemon \
    /etc/init.d/podkop-sub-sync
do
    /bin/ash -n "$f" || {
        echo "ERROR: syntax error in $f"
        exit 1
    }
done

/etc/init.d/podkop-sub-sync enable

CONFIGURED_URL="$(uci -q get podkop-sub-sync.main.url 2>/dev/null || true)"
CONFIG_ENABLED="$(uci -q get podkop-sub-sync.main.enabled 2>/dev/null || echo 0)"

if [ "$NO_START" = 1 ]; then
    echo "Installed and enabled; not started (--no-start)."
elif [ "$CONFIG_ENABLED" != 1 ]; then
    echo "Installed. Sync is disabled in UCI."
elif [ -z "$CONFIGURED_URL" ]; then
    echo "Installed, but subscription URL is empty."
else
    /etc/init.d/podkop-sub-sync start
fi

echo "Installation complete."
echo "Version: $VERSION"
echo "Backup : $BACKUP_DIR"
echo "Check  : ubus call service list '{\"name\":\"podkop-sub-sync\"}'"
echo "Logs   : logread | grep podkop-sub-sync | tail -100"
