# OpenBitFun Mobile Design System

This directory is the source-neutral visual contract for the native HarmonyOS,
Android, and iOS applications. It owns stable visual facts and deterministic
preview scenarios; it does not implement a cross-platform renderer.

## Ownership

- `tokens/mobile-tokens.json`: the single source for semantic colors,
  typography, shared geometry, breakpoints, and motion durations.
- `components/mobile-components.json`: component anatomy, states, and the token
  roles each native implementation must consume.
- `scenarios/mobile-preview-scenarios.json`: deterministic states rendered by
  native preview galleries and the desktop comparison tool.
- `preview/`: the local three-column inspection surface. It can show the
  contract fallback immediately and accepts native screenshots for overlay or
  side-by-side inspection.

Generated platform files are checked in so IDE previews and native builds do
not require Node.js. Change the contract, then run:

```bash
pnpm run mobile:ui:generate
pnpm run mobile:ui:check
pnpm run mobile:ui:preview
```

Do not edit generated files by hand. Native components remain responsible for
safe areas, keyboard behavior, accessibility bridges, navigation gestures, and
platform presentation primitives.

## Typography

- Product text consumes the semantic roles in `tokens/mobile-tokens.json`;
  native components must not introduce literal text sizes.
- Keep the hierarchy shallow: display and page titles use the display/headline
  roles, row titles use title roles, reading text uses body roles, and compact
  metadata uses label roles. The smallest product-text role is `label_small`
  at 12 units; icon glyph sizing is independent of text sizing.
- Native hosts follow the system font-size preference with a documented maximum
  scale. Validate the standard size and at least one enlarged accessibility size
  without changing display zoom, and prefer wrapping or ellipsis over clipping.
- The ramp's sizes were tuned on the iPhone Pro class, where one logical unit is
  1/153.3 inch (460 ppi at 3x). A screen whose logical unit is physically larger
  renders the same `16` visibly bigger, so `text_scale` normalises it: the host
  computes `xdpi / density / reference_logical_dpi`, clamps it to
  `[min_factor, max_factor]`, and applies it to text only, on top of the user's
  font-size preference. HarmonyOS folds it into the generated typography roles
  (`MobileTextScale.apply` at ability start, so every role getter returns the
  scaled value); Android folds it into the theme's `Density.fontScale` so every
  `sp` under `OpenBitFunTheme` follows. iOS is the reference and stays at 1.
  Symbol glyph and `dp`/`vp` geometry never scale. A HUAWEI Mate X7
  (415.6 dpi at density 3.125) resolves to 0.868, so its `16` reads as 14 vp —
  the same millimetres as 16 pt on the iPhone.
- Inline Markdown runs (`**strong**`, `*emphasis*`, `` `code` ``) change only
  weight, slant, or family; they inherit the paragraph role's size on all three
  hosts.

The native role names map to the product's formal content purposes as follows:

| Content purpose | Native role |
| --- | --- |
| Page title | `display_large`, or `headline_large` in a compact container |
| Section title | `headline_small` |
| Card or row title | `title_small` / `title_medium` |
| Body copy | `body_medium`, with `body_large` for reading emphasis |
| Supporting text | `body_small` |
| Control label | `label_medium` / `label_large` |
| Compact metadata | `label_small` |

Platform renderers may choose the listed size variant for available width, but
must not substitute a different content purpose merely to obtain a preferred
metric.

## Sidebar chrome

The left sidebar is chrome, not another page. The desktop client paints it with
its own surface family — one step off the scene the conversation sits on — so
the mobile clients carry a dedicated `sidebar_*` token family rather than
reusing the page roles (`page_bg`, `card`, `soft`, `line`, `ink`, `muted`,
`subtle`). Those page roles stay exactly as they were for conversations,
sheets, and action surfaces; only the rail moved.

Each token maps one-to-one onto a desktop semantic role from
`design-system/packages/theme-openbitfun`:

| Mobile token | Desktop role | Used for |
| --- | --- | --- |
| `sidebar_bg` | `color.surface.chrome` | the rail itself, and the pane behind it |
| `sidebar_bg_fade` | same hue at zero alpha | the top stop of the footer fade |
| `sidebar_raised` | `color.surface.raised` | circle buttons, the quiet footer action |
| `sidebar_line` | `color.border.subtle` | hairlines and control borders |
| `sidebar_hover` | `color.action.quiet.hover` | the search field fill |
| `sidebar_selection` | `color.selection.surface` | the selected row and device fills |
| `sidebar_ink` | `color.content.primary` | titles, row labels, icon tint |
| `sidebar_muted` | `color.content.secondary` | supporting row text |
| `sidebar_subtle` | `color.content.caption` | placeholders and offline devices |

`sidebar_line`, `sidebar_hover` (dark), and `sidebar_selection` are stored as
`#AARRGGBB` on purpose: desktop defines them as alpha over the chrome surface,
and keeping the alpha lets them composite the same way instead of baking a
flattened value that drifts the moment the surface changes.

Sidebar components shared with page surfaces take their layer from the caller
rather than assuming it — Android's `SidebarCircleButton` and
`SignedOutConnectionActions` both expose background/border/content parameters,
and the sheet presented from the sidebar (the workspace picker) stays on page
roles because a sheet is not chrome.

## Simulator captures

The native galleries can be launched without changing the normal app path:

```bash
# Android (after installing the debug APK)
adb shell am force-stop com.openbitfun.mobile.debug
adb shell am start \
  -n com.openbitfun.mobile.debug/com.openbitfun.mobile.app.MainActivity \
  --ez openbitfun.design_preview true \
  --es openbitfun.design_scenario connected-conversation

# iOS Simulator (after installing the simulator app)
xcrun simctl launch booted com.openbitfun.mobile.ios \
  --design-preview connected-conversation

# HarmonyOS emulator (after installing a locally signed debug HAP)
hdc -t <emulator-tcp-target> shell aa force-stop <harmony-bundle-id>
hdc -t <emulator-tcp-target> shell aa start \
  -a EntryAbility -b <harmony-bundle-id> \
  --ps openbitfunDesignPreview connected-conversation
```

Valid scenario ids come from `scenarios/mobile-preview-scenarios.json`. Save
captures using the convention documented in `preview/snapshots/README.md`, then
open the desktop comparison surface to inspect them beside the HarmonyOS
baseline.

## Cold-start brand motion

HarmonyOS, Android and iOS render `startup_brand_reveal` natively. The 6.8-second
sequence uses the `brand_wordmark` artwork typography and the dedicated
`brand_dot` cyan, distinct from action and status colors. Platform soft sans
fonts are used; the HTML prototype's macOS fonts are not redistributed. This
decorative wordmark scales with its 280-unit stage, rather than Dynamic Type;
normal app text continues to respect accessibility sizing.

The cyan dot hops with the letter reveals, returns to the dotless i, then the
shared contour mark expands above the word. Cold-launch presentation is
independent of account and network readiness. Backgrounding removes it without
replay, and system reduced-motion skips it. Notification onboarding waits until
the overlay finishes. Design-preview launches bypass the startup overlay.

Validate on a compact and wide native window, including a live resize where
available, and check a background/foreground cycle during the reveal.

## Signed-out welcome home

The signed-out welcome home spans the available window. Its top row contains
the brand wordmark and a sidebar restore control. The primary action opens
sign-in, and **Explore MiniApps** opens the offline gallery. A retained remote
target keeps its session context and reconnect controls.

Compact windows place the actions in a dark dock. Windows at least 600 logical
units wide center the brand and constrain the actions to 400 units. At widths of
at least 840 units and a width/height ratio of 1.2 or more, the brand and actions
sit side by side in a composition capped at 1000 units. The mark measures 156,
184, or 216 units in those respective layouts. Native safe areas, system text
scaling, and scrolling follow each platform.

The mark uses the same contour geometry and diagonal sweep as recent home.
Phrases enter with 55 ms per-glyph staggering and an 800 ms cubic ease-out,
then leave over 650 ms. Reduced motion renders a static wordmark. Native
renderers use `assets/welcome-brand-contours.json` for the shared geometry.
HarmonyOS can render the isolated welcome via `openbitfunDesignPreview=welcome-home`.

### Recent-conversation home

Signed-in home shows up to three non-archived sessions from the current remote
device, ordered by valid update timestamp (creation time is the fallback). It
labels the device and workspace without treating a loaded catalog as an active
workspace selection. All conversations opens the existing sidebar; creation
stays in the workspace-owned sidebar action. Signed-in users without a remote
target see the same home with a connection entry, while signed-out users retain
the welcome page. Loading and offline states never erase retained sessions.
The mark uses a five-second diagonal highlight sweep; reduced motion uses a
static contour. Native hosts retain their own lifecycle and adaptive layout.

The recent-home mark and animated phrase are centered above the leading-aligned
session list. The mark, type scale, phrase stage, and vertical spacing use the
`recent_home_*` tokens.

### Authenticated cold-start home transition

After the persisted first-install reveal has already been claimed, an
authenticated process launch uses `cold_start_home` (2400 ms). The home shell
mounts immediately so restoration and remote loading continue underneath the
cover. The contour mark starts at 56 logical units, then moves to the mark's
measured native bounds during 16%–68% of the timeline; the cover fades from
68%–100%. Each platform measures the actual compact or wide home layout, so
safe-area insets, split windows, and foldable posture changes do not rely on a
fixed coordinate. Signed-out restore, manual login after launch, activity or
scene recreation, foreground resume, and a second root do not claim the
transition. If the home mark is unavailable, the mark remains centered and the
cover still fades on the same clock. Reduced motion finishes immediately, and
accessibility and pointer interaction stay with the cover until it completes.
