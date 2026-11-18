# HOS7 design tokens and component specs

Source: https://github.com/litwalle/HOS7 (private), commit `b4b4b551ba2c9b59a6e785b3d8138c2b820c5c5e`.
Used with the author's permission (granted to the repository owner, 2026-10-28). The upstream repository has no LICENSE file.

Unmodified copies:

- `harmony.css` ← `src/registry/hos7/styles/harmony.css`: HarmonyOS truth colors and type scale, system/wearable × light/dark.
- `materials.css` ← `src/registry/hos7/styles/materials.css`: the `hm-material-*` floating materials (backdrop blur, fills and inset light).
- `truth/*.json` ← `truth/*.json`: component geometry (heights, radii, paddings) for the controls the sandbox styles natively.

How they are used:

- `scripts/build-hos7.mjs` reads the system light and dark blocks of `harmony.css` and writes `src/hm-hos7.generated.ts`. `hm-theme.ts` takes the default theme's colors from it, so the sandbox, exports and MCP pages carry concrete values (Chart.js and canvas code read them through `getComputedStyle`). `pnpm --filter @repo/design-system hos7:check` verifies the generated file byte for byte; the build runs it.
- The web app imports `harmony.css` and `materials.css` directly (`@repo/design-system/hos7/*`). Its dark mode sets `data-theme="dark"`, which is the selector both files key on.
- Component sizes in `index.ts` follow `truth/*.json`; the entry each value comes from is noted beside it.

To update: copy the files again from a newer commit, update the commit above and the hashes in `manifest.json`, then run `pnpm --filter @repo/design-system hos7:generate`.
