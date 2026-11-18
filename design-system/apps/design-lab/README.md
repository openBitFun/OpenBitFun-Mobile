# Mobile Design Lab

From the repository root, run `pnpm install --frozen-lockfile` and
`pnpm run mobile:design-lab`, then open <http://127.0.0.1:4178>.
Use `pnpm run mobile:design-lab:check` to build the lab and run its mobile
component tests.

- **Typical mobile scenes** shows the conversation, sidebar, recent home, and
  device pairing in phone frames.
- **Components** shows the mobile kit, its token roles, and interactive controls
  such as sheets that open inside the frame.
- **Updated HTML prototype** opens the supplied [standalone demo](public/openbitfun-mobile-standalone.html).
  The file also opens directly in a browser. Inter loads from Google Fonts when
  available.

The mobile scenes, React kit, and [icon guidelines](../../docs/ICON_SYSTEM.md)
come from Cindy's [OpenBitFun PR #3937](https://github.com/openBitFun/OpenBitFun/pull/3937),
snapshot [bd83b39](https://github.com/openBitFun/OpenBitFun/commit/bd83b396f3af7010d0e937e749aeb6a0243d68f5).
The browser reference uses demo data. For native tokens and Android, iOS, and
HarmonyOS comparison, use the [native design system](../../../src/apps/mobile/design-system/README.md).
