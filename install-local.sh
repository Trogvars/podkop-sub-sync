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
SUB_URL_SET=0
INTERVAL=""
INTERVAL_SET=0
MAX_NODES=""
MAX_NODES_SET=0
INCLUDES=""
EXCLUDES=""
EXCLUDES_SET=0
NO_START=0
XHTTP_VALUE=""
XHTTP_SET=0
INTERACTIVE=1

usage(){
    cat <<'EOF'
Usage: install-local.sh [options]

  --url URL          VPN subscription URL
  --interval SEC     Refresh interval in seconds
  --max-nodes N      Keep only N fastest working nodes after precheck (0 = unlimited)
  --include CC       Keep only this country; repeatable: --include RU --include KZ
  --exclude CC       Exclude country; repeatable: --exclude RU --exclude UZ
  --enable-xhttp     Enable XHTTP and automatically install/check its dependencies
  --disable-xhttp    Disable XHTTP (does not replace an already installed SBE)
  --with-xhttp       Legacy alias for --enable-xhttp
  --non-interactive  Do not prompt; use supplied/current/default values
  --no-start         Install and enable, but do not start now
  -h, --help         Show this help
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
            SUB_URL_SET=1
            shift 2
            ;;
        --interval)
            need_value "$@"
            INTERVAL="$2"
            INTERVAL_SET=1
            shift 2
            ;;
        --max-nodes)
            need_value "$@"
            MAX_NODES="$2"
            MAX_NODES_SET=1
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
            EXCLUDES_SET=1
            shift 2
            ;;
        --enable-xhttp|--with-xhttp)
            XHTTP_VALUE=1
            XHTTP_SET=1
            shift
            ;;
        --disable-xhttp)
            XHTTP_VALUE=0
            XHTTP_SET=1
            shift
            ;;
        --non-interactive)
            INTERACTIVE=0
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

is_uint(){
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

validate_country(){
    cc="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
    case "$cc" in
        [A-Z][A-Z]) printf '%s\n' "$cc" ;;
        *) return 1 ;;
    esac
}

[ -z "$INTERVAL" ] || is_uint "$INTERVAL" || {
    echo "ERROR: interval must be an integer number of seconds"
    exit 2
}

[ -z "$MAX_NODES" ] || is_uint "$MAX_NODES" || {
    echo "ERROR: max-nodes must be an integer >= 0"
    exit 2
}

for raw_cc in $INCLUDES; do
    validate_country "$raw_cc" >/dev/null || {
        echo "ERROR: invalid include country: $raw_cc"
        exit 2
    }
done

for raw_cc in $EXCLUDES; do
    validate_country "$raw_cc" >/dev/null || {
        echo "ERROR: invalid exclude country: $raw_cc"
        exit 2
    }
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

command -v uci >/dev/null 2>&1 || {
    echo "ERROR: uci command not found"
    exit 1
}

if [ "$INTERACTIVE" = 1 ] && { [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; }; then
    echo "[podkop-sub-sync] No interactive TTY; using current/default values"
    INTERACTIVE=0
fi

prompt_line(){
    prompt_text="$1"
    printf '%s' "$prompt_text" >/dev/tty
    IFS= read -r prompt_answer </dev/tty || prompt_answer=""
    printf '%s\n' "$prompt_answer"
}

prompt_yes_no(){
    prompt_text="$1"
    prompt_default="$2"

    if [ "$prompt_default" = 1 ]; then
        prompt_suffix="[Y/n]"
    else
        prompt_suffix="[y/N]"
    fi

    while :; do
        answer="$(prompt_line "$prompt_text $prompt_suffix: ")"
        [ -n "$answer" ] || {
            printf '%s\n' "$prompt_default"
            return 0
        }

        case "$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')" in
            y|yes|д|да)
                printf '1\n'
                return 0
                ;;
            n|no|н|нет)
                printf '0\n'
                return 0
                ;;
            *)
                printf 'Please answer y or n.\n' >/dev/tty
                ;;
        esac
    done
}

normalize_country_list(){
    printf '%s\n' "$1" | tr ',;' '  ' | tr '[:lower:]' '[:upper:]'
}

EXISTING_SYNC=0
if uci -q get podkop-sub-sync.main >/dev/null 2>&1; then
    EXISTING_SYNC=1
fi

CURRENT_URL="$(uci -q get podkop-sub-sync.main.url 2>/dev/null || true)"
CURRENT_INTERVAL="$(uci -q get podkop-sub-sync.main.interval 2>/dev/null || true)"
CURRENT_MAX_NODES="$(uci -q get podkop-sub-sync.main.precheck_max_nodes 2>/dev/null || true)"
CURRENT_EXCLUDES="$(uci -q get podkop-sub-sync.main.exclude_country 2>/dev/null || true)"
CURRENT_XHTTP="$(uci -q get podkop-sub-sync.main.enable_xhttp 2>/dev/null || true)"
[ -n "$CURRENT_XHTTP" ] || CURRENT_XHTTP="$(uci -q get podkop-sub-sync.main.allow_xhttp 2>/dev/null || true)"

[ -n "$CURRENT_INTERVAL" ] || CURRENT_INTERVAL='86400'
[ -n "$CURRENT_MAX_NODES" ] || CURRENT_MAX_NODES='20'
[ -n "$CURRENT_XHTTP" ] || CURRENT_XHTTP='0'

if [ "$EXISTING_SYNC" = 0 ]; then
    [ "$EXCLUDES_SET" = 1 ] || {
        EXCLUDES='RU'
        EXCLUDES_SET=1
    }
fi

if [ "$INTERACTIVE" = 1 ]; then
    echo
    echo "========================================"
    echo "  Podkop Subscription Sync setup"
    echo "========================================"

    if [ "$XHTTP_SET" = 0 ]; then
        XHTTP_VALUE="$(prompt_yes_no "Enable XHTTP and install sing-box-extended?" "$CURRENT_XHTTP")"
        XHTTP_SET=1
    fi

    if [ "$SUB_URL_SET" = 0 ]; then
        if [ -n "$CURRENT_URL" ]; then
            answer="$(prompt_line "Subscription URL [Enter = keep current, - = clear]: ")"
            case "$answer" in
                '')
                    ;;
                -)
                    SUB_URL=""
                    SUB_URL_SET=1
                    ;;
                *)
                    SUB_URL="$answer"
                    SUB_URL_SET=1
                    ;;
            esac
        else
            answer="$(prompt_line "Subscription URL [Enter = skip]: ")"
            if [ -n "$answer" ]; then
                SUB_URL="$answer"
                SUB_URL_SET=1
            fi
        fi
    fi

    if [ "$EXCLUDES_SET" = 0 ]; then
        if [ "$EXISTING_SYNC" = 1 ]; then
            if [ -n "$CURRENT_EXCLUDES" ]; then
                exclude_default="$CURRENT_EXCLUDES"
            else
                exclude_default="-"
            fi
        else
            exclude_default="RU"
        fi

        answer="$(prompt_line "Exclude country/countries [$exclude_default] (- = none): ")"
        [ -n "$answer" ] || answer="$exclude_default"

        if [ "$answer" = "-" ]; then
            EXCLUDES=""
        else
            EXCLUDES="$(normalize_country_list "$answer")"
        fi
        EXCLUDES_SET=1
    fi

    if [ "$INTERVAL_SET" = 0 ]; then
        answer="$(prompt_line "Sync interval in seconds [$CURRENT_INTERVAL]: ")"
        [ -n "$answer" ] || answer="$CURRENT_INTERVAL"
        INTERVAL="$answer"
        INTERVAL_SET=1
    fi

    if [ "$MAX_NODES_SET" = 0 ]; then
        answer="$(prompt_line "Maximum fastest nodes [$CURRENT_MAX_NODES]: ")"
        [ -n "$answer" ] || answer="$CURRENT_MAX_NODES"
        MAX_NODES="$answer"
        MAX_NODES_SET=1
    fi

    echo
fi

if [ "$XHTTP_SET" = 0 ]; then
    XHTTP_VALUE="$CURRENT_XHTTP"
fi

if [ "$INTERVAL_SET" = 0 ] && [ "$EXISTING_SYNC" = 0 ]; then
    INTERVAL='86400'
    INTERVAL_SET=1
fi

if [ "$MAX_NODES_SET" = 0 ] && [ "$EXISTING_SYNC" = 0 ]; then
    MAX_NODES='20'
    MAX_NODES_SET=1
fi

[ "$XHTTP_VALUE" = 0 ] || [ "$XHTTP_VALUE" = 1 ] || {
    echo "ERROR: XHTTP selection must be 0 or 1"
    exit 2
}

[ "$INTERVAL_SET" = 0 ] || is_uint "$INTERVAL" || {
    echo "ERROR: interval must be an integer number of seconds"
    exit 2
}

[ "$MAX_NODES_SET" = 0 ] || is_uint "$MAX_NODES" || {
    echo "ERROR: max-nodes must be an integer >= 0"
    exit 2
}

for raw_cc in $EXCLUDES; do
    validate_country "$raw_cc" >/dev/null || {
        echo "ERROR: invalid exclude country: $raw_cc"
        exit 2
    }
done

if [ "$SUB_URL_SET" = 1 ]; then
    [ -n "$SUB_URL" ] && URL_SUMMARY="provided" || URL_SUMMARY="empty"
elif [ -n "$CURRENT_URL" ]; then
    URL_SUMMARY="keep current"
else
    URL_SUMMARY="not set"
fi

if [ "$EXCLUDES_SET" = 1 ]; then
    [ -n "$EXCLUDES" ] && EXCLUDE_SUMMARY="$EXCLUDES" || EXCLUDE_SUMMARY="none"
elif [ -n "$CURRENT_EXCLUDES" ]; then
    EXCLUDE_SUMMARY="$CURRENT_EXCLUDES"
else
    EXCLUDE_SUMMARY="none"
fi

[ "$XHTTP_VALUE" = 1 ] && XHTTP_SUMMARY="yes" || XHTTP_SUMMARY="no"

echo "[podkop-sub-sync] Settings:"
echo "  XHTTP       : $XHTTP_SUMMARY"
echo "  Subscription: $URL_SUMMARY"
echo "  Exclude     : $EXCLUDE_SUMMARY"
echo "  Interval    : ${INTERVAL:-$CURRENT_INTERVAL}"
echo "  Max nodes   : ${MAX_NODES:-$CURRENT_MAX_NODES}"
echo

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

for f in \
    "$SRC/usr/bin/podkop-sub-sync" \
    "$SRC/usr/bin/podkop-sub-precheck" \
    "$SRC/usr/bin/podkop-sub-sync-daemon" \
    "$SRC/usr/lib/podkop-sub-sync/common.sh" \
    "$SRC/etc/init.d/podkop-sub-sync"
do
    /bin/ash -n "$f" || {
        echo "ERROR: source syntax error in $f"
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

OLD_SYNC_ENABLED="$(uci -q get podkop-sub-sync.main.enabled 2>/dev/null || echo 0)"
OLD_SYNC_URL="$(uci -q get podkop-sub-sync.main.url 2>/dev/null || true)"

restart_old_service(){
    if [ "$OLD_SYNC_ENABLED" = 1 ] && [ -n "$OLD_SYNC_URL" ] && [ -x /etc/init.d/podkop-sub-sync ]; then
        /etc/init.d/podkop-sub-sync start >/dev/null 2>&1 || true
    fi
}

if [ -x /etc/init.d/podkop-sub-sync ]; then
    /etc/init.d/podkop-sub-sync stop >/dev/null 2>&1 || true
fi

LOCK="/var/lock/podkop-sub-sync.lock"
if [ -r "$LOCK/pid" ]; then
    RUNNING_PID="$(cat "$LOCK/pid" 2>/dev/null || true)"
    case "$RUNNING_PID" in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$RUNNING_PID" 2>/dev/null; then
                if [ ! -r "/proc/${RUNNING_PID}/cmdline" ] ||
                   tr '\000' ' ' <"/proc/${RUNNING_PID}/cmdline" 2>/dev/null | grep -q 'podkop-sub-sync'; then
                    echo "ERROR: updater is still running (pid $RUNNING_PID); installation aborted before replacing files"
                    restart_old_service
                    exit 1
                fi
            fi
            ;;
    esac
fi

NEED_XHTTP="$XHTTP_VALUE"

if [ "$NEED_XHTTP" = 1 ]; then
    # Use the reviewed source helper before replacing the installed runtime.
    # shellcheck disable=SC1090
    . "$SRC/usr/lib/podkop-sub-sync/common.sh"
    pss_ensure_xhttp_stack || {
        echo "ERROR: XHTTP dependency setup failed; existing podkop-sub-sync files were not replaced"
        restart_old_service
        exit 1
    }
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
    uci set podkop-sub-sync.main.enable_vless='1'
    uci set podkop-sub-sync.main.enable_trojan='1'
    uci set podkop-sub-sync.main.enable_ss='1'
    uci set podkop-sub-sync.main.enable_xhttp='0'
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

LEGACY_XHTTP="$(uci -q get podkop-sub-sync.main.allow_xhttp 2>/dev/null || true)"
CURRENT_XHTTP="$(uci -q get podkop-sub-sync.main.enable_xhttp 2>/dev/null || true)"

if [ -z "$CURRENT_XHTTP" ] && [ -n "$LEGACY_XHTTP" ]; then
    echo "Migrating allow_xhttp to enable_xhttp"
    uci set "podkop-sub-sync.main.enable_xhttp=${LEGACY_XHTTP}"
fi

if [ -n "$LEGACY_XHTTP" ]; then
    uci -q delete podkop-sub-sync.main.allow_xhttp || true
fi

LEGACY_USER_AGENT="$(uci -q get podkop-sub-sync.main.user_agent 2>/dev/null || true)"
case "$LEGACY_USER_AGENT" in
    podkop-sub-sync-openwrt24/*|podkop-sub-sync/1.*)
        echo "Migrating generated legacy user_agent to dynamic versioned default"
        uci -q delete podkop-sub-sync.main.user_agent || true
        ;;
esac

uci -q get podkop-sub-sync.main.retry_interval >/dev/null 2>&1 ||
    uci set podkop-sub-sync.main.retry_interval='900'

[ "$INTERVAL_SET" = 1 ] && uci set "podkop-sub-sync.main.interval=${INTERVAL}"
[ "$MAX_NODES_SET" = 1 ] && uci set "podkop-sub-sync.main.precheck_max_nodes=${MAX_NODES}"

if [ "$SUB_URL_SET" = 1 ]; then
    uci set "podkop-sub-sync.main.url=${SUB_URL}"
    [ -n "$SUB_URL" ] && uci set podkop-sub-sync.main.enabled='1'
fi

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

if [ "$EXCLUDES_SET" = 1 ]; then
    uci -q delete podkop-sub-sync.main.exclude_country || true

    for raw_cc in $EXCLUDES; do
        cc="$(validate_country "$raw_cc")" || {
            echo "ERROR: invalid exclude country: $raw_cc"
            exit 2
        }
        uci add_list "podkop-sub-sync.main.exclude_country=${cc}"
    done
fi

uci set "podkop-sub-sync.main.enable_xhttp=${XHTTP_VALUE}"

uci commit podkop-sub-sync

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
