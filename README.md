# Podkop Subscription Sync

Automatic VPN subscription synchronization for **Podkop + sing-box** on
**OpenWrt 24.x and 25.x** from one codebase.

> Legacy repositories `podkop-sub-sync-openwrt24` and
> `podkop-sub-sync-openwrt25` are superseded by this project.

## Install / update

The same command works on OpenWrt 24.x and 25.x:

```sh
wget -qO- https://raw.githubusercontent.com/Trogvars/podkop-sub-sync/main/install.sh | sh
```

### Interactive setup

When a TTY is available, installation is interactive by default.

Fresh-install defaults:

```text
XHTTP        : No
Subscription : skip
Exclude      : RU
Interval     : 86400
Max nodes    : 20
```

Example:

```text
========================================
  Podkop Subscription Sync setup
========================================
Enable XHTTP support? [y/N]:
Subscription URL [Enter = skip]:
Exclude country/countries [RU] (- = none):
Sync interval in seconds [86400]:
Maximum fastest nodes [20]:
```

On an existing installation, the current configured values are offered as the
defaults, so pressing Enter preserves production settings.

Prompts are read from `/dev/tty`, therefore the menu also works when the
bootstrap itself is piped into `sh`.

For automation, add:

```sh
--non-interactive
```

The installer detects:

```text
OpenWrt 24.* -> opkg / IPK
OpenWrt 25.* -> apk  / APK
```

An existing `/etc/config/podkop-sub-sync` is preserved.

Useful installer arguments:

```text
--url URL
--interval SEC
--max-nodes N
--include CC
--exclude CC
--enable-xhttp
--disable-xhttp
--with-xhttp       # legacy alias
--non-interactive
--no-start
```

`--include` and `--exclude` may be repeated.

Non-interactive example:

```sh
wget -qO- https://raw.githubusercontent.com/Trogvars/podkop-sub-sync/main/install.sh \
  | sh -s -- \
      --non-interactive \
      --url 'https://example.com/sub/xxxxx' \
      --interval 86400 \
      --max-nodes 20 \
      --exclude RU \
      --enable-xhttp
```

## What it does

```text
Subscription
    |
    v
plain / Base64 / gzip decode
    |
    v
VLESS / Trojan / Shadowsocks filter
    |
    v
XHTTP filter or XHTTP dependency auto-repair
    |
    v
include_country whitelist
    |
    v
exclude_country blacklist
    |
    v
real proxy precheck through temporary sing-box
    |
    v
working nodes + measured latency
    |
    v
keep fastest X (optional)
    |
    v
stable URI list + SHA256
    |
    +-- unchanged --> no Podkop restart
    |
    v
write Podkop URLTest
    |
    v
restart Podkop
    |
    v
sing-box check
    |
    +-- failure --> rollback /etc/config/podkop
    |
    v
success
```

## Configuration

`/etc/config/podkop-sub-sync`:

```text
config sync 'main'
        option enabled '1'
        option url 'https://example.com/sub/xxxxx'
        option target 'main'

        option interval '86400'
        option retry_interval '900'

        option send_hwid '0'

        option enable_vless '1'
        option enable_trojan '1'
        option enable_ss '1'
        option enable_xhttp '0'

        # list include_country 'RU'
        # list include_country 'KZ'

        # list exclude_country 'RU'

        option precheck_enabled '1'
        option precheck_url 'https://www.gstatic.com/generate_204'
        option precheck_http_code '204'
        option precheck_connect_timeout '3'
        option precheck_timeout '7'
        option precheck_batch_size '6'
        option precheck_base_port '39000'
        option precheck_min_nodes '3'
        option precheck_min_percent '20'
        option precheck_max_nodes '20'
        option precheck_insecure_tls '0'
```

### Country filters

`include_country` is a whitelist. If at least one include is configured, only
matching countries remain.

```text
list include_country 'RU'
list include_country 'KZ'
```

means RU **or** KZ.

`exclude_country` runs afterwards and therefore has priority:

```text
include_country -> exclude_country
```

Country matching currently uses the URL-encoded emoji flag in the proxy link
fragment, matching the subscription format this project was built for.

### Fastest-node limit

```text
option precheck_max_nodes '20'
```

All candidates are tested first. Safety thresholds are evaluated against the
full set of working nodes, then only the fastest 20 are kept.

`0` disables the limit.

Typical summary:

```text
Total       : 90
Working     : 52
Failed      : 38
Parser fail : 0
Success     : 57%
Selected    : 20
Fastest     : 345ms
Cutoff      : 696ms
```

The selected URI set is sorted after ranking so latency order changes alone do
not cause unnecessary Podkop restarts.

### XHTTP

`--with-xhttp` remains supported as a legacy alias for `--enable-xhttp`.

XHTTP is a selectable protocol toggle, just like VLESS/Trojan/SS:

```text
option enable_xhttp '1'
```

or enable it during install/update with:

```sh
--enable-xhttp
```

It is independent from ordinary VLESS. For example:

```text
option enable_vless '0'
option enable_xhttp '1'
```

keeps XHTTP VLESS links while filtering ordinary VLESS links.

If XHTTP is enabled, the project first checks the capabilities of the
currently installed engine and Podkop parser.

Supported engines:

- `podkop-engine` / `podkop-engine-full` r11+ when `sing-box version`
  advertises `Features: ... transport.xhttp ...`;
- `sing-box-extended`.

A compatible installed engine is kept as-is. In particular, installing
`podkop-engine` does **not** cause podkop-sub-sync to replace it with SBE.

Modern Podkop (0.7.23+) already handles `xhttp | splithttp)` itself, so no
parser patch is installed. The legacy `podkop-xhttp-patch` is used only for an
older Podkop parser that really lacks XHTTP support.

If the current engine has no XHTTP capability and it is ordinary stock
`sing-box`, podkop-sub-sync can still install the pinned SBE helper
automatically. If `podkop-engine` itself is installed but does not advertise
`transport.xhttp` (old r<11 build), the updater refuses to replace it and asks
for a podkop-engine upgrade instead.

The helper scripts are pinned to reviewed Git commits. When SBE is actually
needed, the pinned installer selects the newest stable SBE release.

SBE format selection is intentionally platform-specific:

- OpenWrt 24.x / `opkg`: compressed SBE build is selected explicitly to avoid
  tmpfs/flash exhaustion while unpacking the much larger normal build.
- OpenWrt 25.x / `apk`: the upstream recommended APK/default is used.

On low-memory routers (<384 MiB RAM) running the compressed SBE build, a second
simultaneous sing-box process can be killed by the kernel during real precheck.
In that specific case the precheck temporarily stops Podkop, verifies direct
connectivity, tests the candidate nodes with a single sing-box instance, then
restores Podkop automatically. Normal/APK builds keep the usual zero-downtime
precheck behavior.

Current pinned helpers:

```text
EikeiDev/OpenWRT-sing-box-extended:
abc0248d234fefe95e6ed787df6fb71df2b8e921

moix89/podkop-xhttp-patch:
0b7be3f7504e2903c5bd8487075c8c11de459553
```

### Precheck TLS

Fresh 2.0.0 installations use:

```text
option precheck_insecure_tls '0'
```

so the HTTPS test certificate is verified.

For backward compatibility, an older preserved config with no such option
uses the legacy behavior (`1`, equivalent to curl `-k`). Add the option
explicitly to change it.

## Service

Manual sync:

```sh
/usr/bin/podkop-sub-sync
```

Logs:

```sh
logread | grep podkop-sub-sync
```

Service:

```sh
/etc/init.d/podkop-sub-sync restart
ubus call service list '{"name":"podkop-sub-sync"}'
```

## Build package

One OpenWrt package recipe is used for both supported generations:

```sh
./build-package.sh /path/to/openwrt-sdk
```

The OpenWrt SDK decides the package backend:

```text
OpenWrt 24.x SDK -> .ipk
OpenWrt 25.x SDK with CONFIG_USE_APK -> .apk
```

The resulting package is found under the SDK `bin/` tree.

## Repository layout

```text
.
├── VERSION
├── README.md
├── CHANGES.md
├── CODE_REVIEW.md
├── LICENSE
├── install.sh
├── install-local.sh
├── build-package.sh
├── check.sh
└── package/
    ├── Makefile
    └── files/
        ├── etc/config/podkop-sub-sync
        ├── etc/init.d/podkop-sub-sync
        ├── usr/bin/podkop-sub-sync
        ├── usr/bin/podkop-sub-precheck
        ├── usr/bin/podkop-sub-sync-daemon
        └── usr/lib/podkop-sub-sync/common.sh
```

## Migration from the legacy repositories

Running the unified installer over either legacy installation is supported:

```sh
wget -qO- https://raw.githubusercontent.com/Trogvars/podkop-sub-sync/main/install.sh | sh
```

The installer:

- backs up the current scripts and config under `/root/`;
- stops the old sync service and refuses to replace files while an active sync still owns the updater lock;
- preserves `/etc/config/podkop-sub-sync`;
- installs the unified runtime;
- re-checks XHTTP dependencies when `enable_xhttp=1`;
- validates shell syntax;
- starts the service again when enabled and configured.

## Review notes

The consolidation review and remaining design trade-offs are documented in
[CODE_REVIEW.md](CODE_REVIEW.md).

Version history: [CHANGES.md](CHANGES.md).

## License

MIT
