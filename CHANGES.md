# CHANGES

## 2.0.2

### Fixed

- Detects the UPX-compressed sing-box-extended build on routers with less than
  384 MiB RAM.
- When the production `sing-box` process is already running, proxy precheck
  temporarily stops Podkop so the temporary test sing-box can start without
  competing with a second decompressed compressed-core instance.
- Podkop is restored automatically after precheck and also from the cleanup
  trap on any failure.
- Direct control-URL connectivity is rechecked immediately after Podkop is
  stopped before any proxy batches are tested.
- Exit code 137 from `sing-box check` is now reported explicitly as likely
  OOM together with current `MemAvailable`.

This low-memory mode only affects compressed SBE installations below the RAM
threshold. Normal/APK SBE installations keep the previous zero-downtime
precheck behavior.

---

## 2.0.1

### Fixed

- OpenWrt 24.x/opkg no longer blindly accepts the upstream SBE installer's
  default normal archive.
- The normal arm64 SBE archive is about 34 MiB compressed and is unpacked in
  tmpfs while the archive is still present. The upstream 65 MiB temporary-space
  threshold can therefore be insufficient even when `df -h` shows free overlay
  space.
- Automatic XHTTP dependency setup now explicitly chooses the **compressed SBE
  build** on OpenWrt 24.x/opkg.
- OpenWrt 25.x/apk keeps the upstream recommended APK/default selection.

---

## 2.0.0

### Unified project

- Merged the former OpenWrt 24.x and 25.x projects into one
  `Trogvars/podkop-sub-sync` repository.
- One runtime codebase is now used on both OpenWrt generations.
- `install.sh` is now a single bootstrap URL for both OpenWrt 24.x and 25.x.
- `install-local.sh` detects the OpenWrt version and package manager.
- One OpenWrt `package/Makefile` is used for both package formats:
  OpenWrt 24.x builds IPK, OpenWrt 25.x builds APK.
- Removed the need for committed generated tar.gz bundles; GitHub's repository
  source archive is used directly by the bootstrap installer.

### Reliability and review fixes

- XHTTP auto-repair now runs only after the updater lock is acquired.
- Updater lock now stores a PID and recovers stale lock directories.
- SBE installer and Podkop XHTTP patch helper scripts are pinned to reviewed
  Git commit revisions instead of executing moving `main` scripts as root.
- Installer validates its inputs/source scripts before changes, stops the old sync service, and refuses to replace files while an updater PID lock is still active.
- Unified subscription download path no longer depends on `curl --compressed`.
- Added stronger validation for country and precheck numeric options, including timeout values.
- Fixed the legacy `/bin/sh` build helper brace-expansion bug.
- Moved SHA state to `/etc/podkop-sub-sync-state/` with migration from the old
  state filename.
- Added a central installed VERSION file and removed stale hard-coded
  User-Agent defaults.
- Fresh installs verify TLS during precheck; existing configs retain the old
  insecure fallback unless explicitly changed.
- Added `check.sh` and GitHub CI syntax/version consistency checks, including BusyBox ash parsing.
- Installer migration removes recognized generated legacy User-Agent values so the new VERSION-based default is used; custom User-Agent values are preserved.

### Preserved behavior

- Existing `/etc/config/podkop-sub-sync` is preserved by installer upgrades.
- VLESS, Trojan and Shadowsocks filtering.
- XHTTP automatic SBE + Podkop patch recovery.
- `include_country` / `exclude_country`.
- Full real-proxy precheck through temporary sing-box.
- `precheck_max_nodes` fastest-node selection.
- SHA-based no-op updates.
- Podkop rollback after invalid generated sing-box configuration.

---

## 1.3.2

- Automatic unattended installation/recovery of sing-box-extended and the
  Podkop XHTTP patch when XHTTP is enabled.

## 1.3.1

- Universal version-detecting bootstrap added to the two legacy repositories.

## 1.3.0

- Added `precheck_max_nodes` and fastest-node selection after availability
  testing.

## 1.2.0

- Added country whitelist support with `include_country` and installer
  `--include`.

## 1.1.0

- Added XHTTP support through sing-box-extended and the Podkop XHTTP patch.

## 1.0.0

- Initial subscription synchronization, protocol/country filtering, real proxy
  precheck, SHA comparison and rollback.
