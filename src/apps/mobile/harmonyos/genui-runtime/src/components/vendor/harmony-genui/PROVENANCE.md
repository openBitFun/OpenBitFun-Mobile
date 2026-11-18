# Harmony GenUI page look

Source: `task_genui/harmony-genui` (Open Intelligent UI fork), branch `codex/genui-badminton-capabilities` (managed scoreboard, wide icon covers, tool header rules), revision recorded in
`harmonyGenuiStyles.generated.ts` (`HARMONY_GENUI_REVISION`). MIT, see `../HARMONY-LICENSE.txt`.

Unmodified copies:

- `scoreboard.css`, `scoreboard.js` ← `apps/agent/src/`: the managed scoreboard block; `../../harmonyScoreboard.tsx` ports its markup and logic.
- `page_kit.css` ← `apps/agent/src/page_kit.css`: the composePage block kit (cover, sections,
  stats, lists, timeline, checklist, note, pros/cons, table, FAQ, segmented, form, progress, chart).
- `hos7/` ← `packages/design-system/src/vendor/hos7/`: HOS7 colour, type and component geometry the
  reference design system is built on. Not under the MIT licence: used with the HOS7 author's
  permission (see `hos7/PROVENANCE.md`); the OpenBitFun maintainers confirmed that permission covers
  this repository on 2026-11-12.

Generated:

- `harmonyGenuiStyles.generated.ts`, written by `scripts/vendor-harmony-genui-styles.mjs`: the
  reference design system's theme, element, SVG and form styles, typography presets and the page kit,
  every rule confined to the Harmony application root. Two adaptations differ from the source: the page
  kit's wide layout starts at 600 CSS px instead of 720 (the Harmony host's wide posture), and the page never splits into page columns or a centred measure on a wide screen (its `columns` rules and page max-width are dropped). `@font-face` rules are dropped: the
  phone uses the system HarmonyOS Sans and the bundled HM Symbol font. The reference display faces
  (handwritten, brush, serif web fonts) are not shipped; their sources are large and several are
  licensed for demonstration only, so a heading with those presets falls back to the system face.

The OpenUI renderers in `../../harmonyPageKit.tsx` emit the page kit markup (`.pk-*`) that
`page_kit.css` styles. Do not edit the copies or the generated module; re-run the script.
