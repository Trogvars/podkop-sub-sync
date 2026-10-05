# Code review and consolidation notes

This document records the review performed while consolidating the former
`podkop-sub-sync-openwrt24` and `podkop-sub-sync-openwrt25` repositories into
one codebase.

## Fixed in 2.0.0

### 1. Two repositories duplicated the same runtime logic

**Severity:** high

The 24.x repository stored normal runtime files, while the 25.x repository
embedded copies of those same scripts inside a monolithic installer. Every
feature therefore had to be patched twice, and drift had already occurred.

**Fix:** one canonical runtime tree now lives under `package/files/`.
OpenWrt 24.x and 25.x install exactly the same runtime files.

### 2. XHTTP repair ran before the updater lock

**Severity:** high

Two simultaneous updater invocations could both decide that
`sing-box-extended` or the Podkop XHTTP patch was missing and modify the system
at the same time.

**Fix:** the updater now acquires the lock before any XHTTP dependency repair.
The lock stores a PID and stale locks are recovered automatically.

### 3. Third-party root scripts were executed from moving `main` branches

**Severity:** high

The previous implementation downloaded and executed the current `main`
version of the SBE installer and Podkop XHTTP patch as root.

**Fix:** the helper script revisions are pinned to reviewed Git commit SHAs.
The pinned SBE installer still chooses the latest stable SBE release, but the
installer code itself is no longer silently replaced underneath this project.

### 4. OpenWrt 24.x and 25.x had unnecessary downloader divergence

**Severity:** medium

25.x used `curl --compressed`, while 24.x needed a workaround because some
libcurl builds do not support it.

**Fix:** the unified downloader always requests `Accept-Encoding: identity`
and still detects/decodes raw gzip responses. This works on both branches and
removes a runtime fork.

### 5. Installer could replace scripts while its daemon was running

**Severity:** medium

Updating files under a live daemon creates a small race window.

**Fix:** installer arguments and source scripts are validated before any
runtime replacement. The installer backs up the current installation, stops
`podkop-sub-sync`, checks the updater PID lock, and refuses to replace files if
a sync process is still alive. XHTTP dependencies are prepared before the
runtime files are swapped, then the new service is enabled/started.

### 6. Version/User-Agent drift

**Severity:** medium

The 25.x installer still contained an old `podkop-sub-sync/1.2` default while
the runtime had already moved to 1.3.x.

**Fix:** version is installed to `/usr/share/podkop-sub-sync/VERSION`.
The default User-Agent is generated from that file. A user-specified UCI
`user_agent` still overrides it.

### 7. Weak option validation

**Severity:** medium

Some installer and precheck numeric/country parameters were not validated
consistently.

**Fix:** country codes and numeric precheck values (including timeouts,
batch size, base port, thresholds and max-node limit) are validated before
use; installer CLI values are validated before it stops or replaces the
existing installation.

### 8. State file location

**Severity:** low

Hash state previously lived directly in `/etc` as
`/etc/podkop-sub-sync-TARGET.sha256`.

**Fix:** new state goes under `/etc/podkop-sub-sync-state/`. The old state file
is imported on first use to avoid an unnecessary update after migration.

### 9. Package build helper used shell brace expansion under `/bin/sh`

**Severity:** medium

The legacy helper used:

```sh
make package/podkop-sub-sync/{clean,compile}
```

despite a `/bin/sh` shebang. On systems where `/bin/sh` is `dash`, brace
expansion is not performed.

**Fix:** clean and compile are invoked as two explicit make targets.

### 10. Precheck TLS verification was implicit

**Severity:** low/security

The old precheck always used `curl -k`.

**Fix:** fresh installs set `precheck_insecure_tls=0` and verify TLS.
Existing configs without this option retain the legacy fallback (`1`) for
backward compatibility.

## Deliberately retained

### Sequential node probes inside each batch

The batch limits temporary sing-box configuration size and memory use. Probes
are still sequential. Parallel probing would make large subscriptions faster,
but would increase CPU/RAM/socket pressure on small routers. It should be
introduced only as an explicit configurable feature.

### Country recognition by URL-encoded emoji flags

The existing provider format uses percent-encoded country emoji in proxy
fragments. The filter keeps this behavior. Supporting arbitrary textual
country names or literal UTF-8 flags can be added separately without changing
the current matching semantics.

### Automatic SBE selection protocol

The pinned upstream SBE installer is driven with `1` + Enter: newest stable
release and the installer's recommended format. Because the installer script
itself is pinned, its prompt contract is stable for this project version.
When updating the pinned revision, this interaction must be reviewed again.


### 11. Legacy generated User-Agent migration

**Severity:** low

Legacy installers wrote generated version strings such as
`podkop-sub-sync-openwrt24/1.3.2` directly into UCI. Preserving that value
would defeat the new dynamic VERSION-based default.

**Fix:** installer migration removes only recognized generated legacy
User-Agent values. Arbitrary/custom `user_agent` values are preserved.

### 12. CI previously checked only the host shell

**Severity:** low

A script can parse under Ubuntu's `/bin/sh` but still behave differently on
OpenWrt BusyBox ash.

**Fix:** CI installs BusyBox and `check.sh` validates every shell file with
both the host `sh -n` and `busybox ash -n`.


### 13. Compressed SBE and dual-process precheck on small routers

**Severity:** high for OpenWrt 24.x devices with constrained RAM/flash

The compressed SBE build solves flash-space pressure, but its executable is
decompressed in memory. The precheck normally runs a temporary sing-box while
the production Podkop sing-box is still active. On a ~256 MiB router this can
cause the second process to receive SIGKILL (exit 137) before validation.

**Fix:** when the installed SBE identifies itself as UPX-compressed, total RAM
is below 384 MiB, and a production sing-box process is active, precheck
temporarily stops Podkop, rechecks direct connectivity, performs the tests with
one sing-box instance, and restores Podkop from both the normal path and cleanup
trap. Other installations retain zero-downtime precheck.
