# Native mobile ownership and migration

## Source

Imported from `openBitFun/OpenBitFun` commit `315c4ca62` plus the local HarmonyOS
UI work reviewed on a physical phone in compact and expanded postures. The
source cleanup is based on upstream `4b43fbd00`; the native tree did not change
between those revisions. The import retains the original MIT license and all
third-party source notices. Earlier history is available in the source repository.

## Ownership

| Moved here | Still owned by OpenBitFun |
| --- | --- |
| `src/apps/mobile/{android,ios,harmonyos,shared,miniapps,design-system,docs}` | Desktop, CLI, Relay, Rust runtime, `src/mobile-web` |
| `src/shared/argon2`, native `src/shared/terminal/webview` | Host wire protocol and capability negotiation |
| Native architecture/design/image/locale generators and tests | Canonical shared locale and design package sources |
| Native WebView browser regressions and `mobile-v*` packaging | Desktop release workflow and embedded browser mobile-web |

`contracts/upstream-snapshots.json` pins the source and hashes for the small
shared inputs copied here: protocol fixtures, locale contract, theme packages,
brand masters and built-in offline MiniApps. These snapshots make builds
independent of a sibling checkout or a live network fetch of the host source.
When upstream changes one of these contracts, import the reviewed files at an
explicit commit, update the manifest, regenerate assets and run the native
checks. Do not edit a snapshot to invent a protocol capability. Host capabilities
must still be negotiated, including with older installations.

The copied theme packages serve only build-time preview/appearance generation;
ArkUI, Compose and SwiftUI keep their native renderers and mobile token owner.
The paths under `src/crates` contain only offline MiniApp assets and generated
appearance HTML, not an embedded Rust runtime or execution host.

## Upgrade behavior

App IDs, existing version codes, account identity, databases and wire formats
are retained. No app reinstall, data deletion or account repair is required.
HarmonyOS signing material previously embedded in build configuration is omitted
from Git; use the platform-local signing configuration for existing installs.
The native package versions remain independent of desktop releases.

## Verification

`pnpm run prepare:assets` followed by `pnpm run check` checks architecture, native
token generation, preview resources, all native/preview/MiniApp color surfaces,
locale projection, protocol facts and native versions. Host-language tests and
browser regressions run in CI. Android and shared Kotlin have a Linux build/test
job; iOS has Kotlin simulator compilation and pure Swift checks on macOS.
HarmonyOS needs the DevEco SDK and local signing for physical-device deployment.

Migration verification does not establish new remote scenario coverage. The
carried UI was exercised through real account/Relay remote control before the
move; shared host-stream tests simulate reconnect and old payloads. SSH remote
workspace, Peer Device Mode and Detached Dispatch were not live-tested as part
of the repository move.
