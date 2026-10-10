#!/bin/ash

PSS_VERSION_FILE="/usr/share/podkop-sub-sync/VERSION"

# Pin the helper scripts themselves for reproducibility. The SBE helper still
# selects the latest stable sing-box-extended release at runtime.
PSS_SB_EXT_INSTALLER_REF="${PSS_SB_EXT_INSTALLER_REF:-abc0248d234fefe95e6ed787df6fb71df2b8e921}"
PSS_XHTTP_PATCH_REF="${PSS_XHTTP_PATCH_REF:-0b7be3f7504e2903c5bd8487075c8c11de459553}"

PSS_SB_EXT_URL="https://raw.githubusercontent.com/EikeiDev/OpenWRT-sing-box-extended/${PSS_SB_EXT_INSTALLER_REF}/install.sh"
PSS_XHTTP_PATCH_URL="https://raw.githubusercontent.com/moix89/podkop-xhttp-patch/${PSS_XHTTP_PATCH_REF}/install.sh"

pss_version(){
    if [ -r "$PSS_VERSION_FILE" ]; then
        cat "$PSS_VERSION_FILE"
    else
        printf '%s\n' "unknown"
    fi
}

pss_log(){
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

pss_fetch(){
    pss_url="$1"
    pss_dst="$2"

    rm -f "$pss_dst"

    if command -v wget >/dev/null 2>&1; then
        wget -O "$pss_dst" "$pss_url" || return 1
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 60 "$pss_url" -o "$pss_dst" || return 1
    else
        pss_log "ERROR: neither wget nor curl is available"
        return 1
    fi

    [ -s "$pss_dst" ]
}

pss_singbox_version(){
    sing-box version 2>/dev/null || true
}

pss_has_extended(){
    pss_singbox_version | grep -qi 'extended'
}

pss_has_podkop_engine(){
    if command -v apk >/dev/null 2>&1; then
        apk info -e podkop-engine >/dev/null 2>&1 ||
            apk info -e podkop-engine-full >/dev/null 2>&1
        return $?
    fi

    if command -v opkg >/dev/null 2>&1; then
        opkg status podkop-engine 2>/dev/null | grep -q '^Status: .* installed' ||
            opkg status podkop-engine-full 2>/dev/null | grep -q '^Status: .* installed'
        return $?
    fi

    pss_singbox_version | grep -qi -- '-pdk-r'
}

pss_has_xhttp_engine(){
    pss_version_info="$(pss_singbox_version)"

    # podkop-engine r11+ deliberately exposes machine-readable capabilities.
    # Prefer this over package/version guessing.
    printf '%s\n' "$pss_version_info" |
        grep -Eq '^Features: .*transport\.xhttp([,[:space:]]|$)' &&
        return 0

    # Compatibility with sing-box-extended, which predates the Features line.
    printf '%s\n' "$pss_version_info" | grep -qi 'extended'
}

pss_has_xhttp_parser(){
    [ -r /usr/lib/podkop/sing_box_config_facade.sh ] || return 1

    # Legacy podkop-xhttp-patch used "xhttp)".
    # Modern Podkop (0.7.23+) handles "xhttp | splithttp)" itself.
    grep -Eq '^[[:space:]]*xhttp([[:space:]]*\|[[:space:]]*[^)]*)?\)' \
        /usr/lib/podkop/sing_box_config_facade.sh
}

pss_ensure_xhttp_stack(){
    if pss_has_xhttp_engine; then
        pss_log "XHTTP: current sing-box already provides transport.xhttp"
    else
        if pss_has_podkop_engine; then
            pss_log "ERROR: installed podkop-engine does not advertise transport.xhttp"
            pss_log "ERROR: update podkop-engine to r11+ (recommended: current release) or disable XHTTP"
            return 1
        fi

        pss_log "XHTTP: compatible XHTTP engine missing; installing sing-box-extended automatically"

        pss_fetch "$PSS_SB_EXT_URL" /tmp/podkop-sub-sync-sb-ext.sh || {
            pss_log "ERROR: failed to download pinned sing-box-extended installer"
            return 1
        }

        chmod 700 /tmp/podkop-sub-sync-sb-ext.sh

        # Pinned installer currently asks:
        #   1) release number (1 = newest stable)
        #   2) format
        #
        # On OpenWrt 24.x/opkg the upstream "recommended" normal archive may
        # need far more temporary and flash space than its own 65 MiB precheck
        # accounts for (archive + unpacked binary coexist in tmpfs). Prefer the
        # compressed build there. On 25.x/apk keep the upstream recommended APK.
        if command -v opkg >/dev/null 2>&1 && ! command -v apk >/dev/null 2>&1; then
            pss_log "XHTTP: selecting latest stable release + compressed SBE build for opkg/OpenWrt 24.x"
            PSS_SBE_INPUT='1
1
'
        else
            pss_log "XHTTP: selecting latest stable release + installer-recommended format"
            PSS_SBE_INPUT='1

'
        fi

        printf '%s' "$PSS_SBE_INPUT" | sh /tmp/podkop-sub-sync-sb-ext.sh || {
            pss_log "ERROR: sing-box-extended automatic installation failed"
            return 1
        }
    fi

    pss_has_xhttp_engine || {
        pss_log "ERROR: no XHTTP-capable sing-box is active after dependency setup"
        return 1
    }

    if ! pss_has_xhttp_parser; then
        pss_log "XHTTP: Podkop parser patch missing; installing automatically"

        pss_fetch "$PSS_XHTTP_PATCH_URL" /tmp/podkop-sub-sync-xhttp-patch.sh || {
            pss_log "ERROR: failed to download pinned Podkop XHTTP patch"
            return 1
        }

        chmod 700 /tmp/podkop-sub-sync-xhttp-patch.sh
        sh /tmp/podkop-sub-sync-xhttp-patch.sh || {
            pss_log "ERROR: Podkop XHTTP patch installation failed"
            return 1
        }
    fi

    pss_has_xhttp_parser || {
        pss_log "ERROR: Podkop XHTTP parser still missing after patch"
        return 1
    }

    pss_engine_name="sing-box"
    pss_has_podkop_engine && pss_engine_name="podkop-engine"
    pss_has_extended && pss_engine_name="sing-box-extended"

    pss_log "XHTTP dependencies ready: ${pss_engine_name}; $(pss_singbox_version | head -n 1)"
    return 0
}
