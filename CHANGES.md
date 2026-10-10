# CHANGES

## 2.3.1

### Fixed

- Fixed precheck JSON corruption with modern Podkop 0.7.23 and
  `podkop-engine` XHTTP decoding.
- Podkop's modern facade may log warnings while
  `sing-box tools decode-link` parses a link. Precheck previously supplied
  its own stdout `log()`, so those warnings were captured together with the
  JSON returned by `sing_box_cf_add_proxy_outbound` and then fed into `jq`.
  This produced `jq: parse error: Invalid numeric literal`, parser failures,
  and eventually an empty/broken temporary batch config.
- Precheck now uses a dedicated `precheck_log()` for its console output and
  loads Podkop's native `logging.sh` for facade internals, keeping parser
  diagnostics out of JSON stdout.
- Each parser stage is now JSON-validated before it replaces the current batch
  configuration. A malformed link can be counted as a parser failure without
  poisoning the remaining nodes in the batch.
- CI now guards the logger separation and parser JSON validation.
- Older Podkop layouts without `/usr/lib/podkop/logging.sh` remain supported:
  precheck installs a syslog-only fallback `log()` for facade diagnostics, so
  legacy `podkop-xhttp-patch + sing-box-extended` setups keep working.

---

## 2.3.0

### podkop-engine support

- XHTTP dependency detection is now capability-based instead of requiring the
  engine name to contain `extended`.
- `podkop-engine` and `podkop-engine-full` r11+ are accepted natively when
  `sing-box version` advertises `Features: ... transport.xhttp ...`.
- An installed compatible podkop-engine is kept untouched; podkop-sub-sync no
  longer tries to replace it with sing-box-extended.
- If an old podkop-engine is installed but does not advertise
  `transport.xhttp`, the updater refuses an automatic engine replacement and
  asks for podkop-engine to be upgraded instead.
- Modern Podkop parser syntax `xhttp | splithttp)` is recognized in addition
  to the legacy patched `xhttp)` form. Podkop 0.7.23+ therefore does not
  receive the obsolete parser patch.
- The interactive installer prompt is now engine-neutral:
  `Enable XHTTP support?`.
- CI includes regression checks for podkop-engine feature detection, both Podkop
  parser forms, sing-box-extended compatibility, and stock sing-box rejection.

---

## 2.2.2

### Fixed

- Removed the redundant second `sing-box check` that ran after Podkop had
  already started the production sing-box process.
- With UPX-compressed SBE, that second validation starts another decompressed
  `sing-box-core` alongside production. On ~256 MiB routers this can exhaust
  RAM/swap and trigger the kernel OOM killer.
- The updater now relies on the successful validation already performed during
  Podkop startup, then checks that the production sing-box process remains alive
  for a 5-second stability window without spawning a second core.
- State hash is written only after that stability window passes.

---

## 2.2.1

### Fixed

- Low-memory precheck no longer restarts Podkop immediately after a successful
  proxy test only for the updater to restart it again a few seconds later.
- When called by the updater, successful precheck can leave Podkop stopped until
  the final proxy list has been written.
- If the tested proxy set is unchanged, the updater restores Podkop before
  exiting.
- Any precheck failure still restores the original Podkop service through the
  existing cleanup path.
- Final apply now performs a single Podkop start when precheck intentionally
  left it stopped, reducing service churn and avoiding transient `ubus service
  delete ... Not found` / `sort: Broken pipe` noise caused by back-to-back
  start/restart cycles.

---

## 2.2.0

### Interactive installer

- Installation is interactive by default when a TTY is available.
- Fresh-install defaults:
  - XHTTP: **No** (keeps the normal Podkop sing-box; SBE is not installed).
  - Subscription URL: **skip**.
  - Excluded country: **RU**.
  - Sync interval: **86400 seconds**.
  - Maximum fastest nodes: **20**.
- Existing installations use their current values as prompt defaults so Enter
  does not unexpectedly overwrite production configuration.
- Prompts read from `/dev/tty`, so the menu works with
  `wget -qO- .../install.sh | sh`.
- Added `--non-interactive` for automation/Ansible/CI.
- Added `--disable-xhttp`; `--with-xhttp` remains a legacy alias for
  `--enable-xhttp`.
- If a fresh installation has no subscription URL, sync remains disabled until
  a URL is configured. Explicitly clearing the URL also disables sync.

### Runtime fix

- Final post-restart health-check now accepts both `sing-box` and
  `sing-box-core`.
- This fixes false rollback on OpenWrt 24.x compressed SBE: the generated
  sing-box config could validate successfully while the updater still waited
  only for a process literally named `sing-box`, then rolled back after
  20 seconds.

---

## 2.1.0

### Changed

- XHTTP is now configured like the other selectable proxy types:
  `option enable_xhttp '0|1'`.
- Startup protocol reporting includes XHTTP, for example:
  `Enabled protocols: vless|trojan|ss|xhttp`.
- XHTTP selection is logically independent from ordinary VLESS. It is valid to
  use `enable_vless='0'` together with `enable_xhttp='1'`; only VLESS links
  using `type=xhttp` are retained.
- XHTTP dependency auto-repair is triggered by `enable_xhttp='1'`.

### Migration

- Existing `allow_xhttp` is automatically migrated to `enable_xhttp` during
  installation/update and the legacy option is removed.
- Runtime still understands `allow_xhttp` as a compatibility fallback until
  the installer migration has been run.
- New installer option: `--enable-xhttp`.
- Existing `--with-xhttp` remains as a compatibility alias.

---

## 2.0.4

### Fixed

- Low-memory precheck no longer assumes that `/etc/init.d/podkop stop` has
  synchronously terminated the compressed `sing-box-core` process.
- After stopping Podkop, precheck now waits up to 10 seconds for sing-box to
  exit naturally.
- If the core remains, it retries `/etc/init.d/sing-box stop`, waits again,
  then sends TERM to the remaining sing-box/sing-box-core PID(s).
- KILL is used only as a final fallback if the lingering core ignores TERM.
- The normal cleanup path still restarts Podkop automatically on every failure.

This handles OpenWrt 24.x compressed SBE installations where Podkop's stop
sequence returns before the real core process has fully exited.

---

## 2.0.3

### Fixed

- Compressed SBE production process detection now checks both `sing-box` and
  `sing-box-core`. The compressed wrapper executes the real core under the
  latter process name, which prevented the 2.0.2 low-memory mode from
  activating.
- Temporary precheck sing-box readiness no longer uses a fixed `sleep 1`.
- Precheck now waits up to 20 seconds for the first mixed inbound to actually
  enter TCP LISTEN state via `/proc/net/tcp{,6}` before testing proxies.
- This prevents false `curl rc=7 / HTTP=000` failures on UPX-compressed builds
  that take several seconds to decompress/start.

---

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
