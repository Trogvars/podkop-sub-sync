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

pss_has_extended(){
    sing-box version 2>/dev/null | grep -qi 'extended'
}

pss_has_xhttp_parser(){
    [ -r /usr/lib/podkop/sing_box_config_facade.sh ] &&
        grep -q '^[[:space:]]*xhttp)' /usr/lib/podkop/sing_box_config_facade.sh
}

pss_ensure_xhttp_stack(){
    if ! pss_has_extended; then
        pss_log "XHTTP: sing-box-extended missing; installing automatically"

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

    pss_has_extended || {
        pss_log "ERROR: sing-box-extended is still not active after installation"
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

    pss_log "XHTTP dependencies ready: $(sing-box version 2>/dev/null | head -n 1)"
    return 0
}
