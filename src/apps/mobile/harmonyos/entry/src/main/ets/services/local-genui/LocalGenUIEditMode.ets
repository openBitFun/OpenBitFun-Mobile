/**
 * OpenUI edit mode for Local GenUI follow-ups and repairs.
 *
 * The model returns only the statements that change; the runtime merges them
 * into the base program with lang-core `mergeStatements` (same name replaces,
 * a new name appends, `name = null` deletes, unreachable statements drop).
 * `OPENUI_EDIT_MODE_RULES` is lang-core's own edit-mode prompt section,
 * copied verbatim; tools/tests/local-genui-edit-mode.test.cjs keeps it in step
 * with the bundled lang-core.
 */
export const OPENUI_EDIT_MODE_RULES: string = [
  '## Edit Mode',
  '',
  'The runtime merges by statement name: same name = replace, new name = append.',
  'Output ONLY statements that changed or are new. Everything else is kept automatically.',
  '',
  '### Delete',
  'To remove a component, re-declare its parent without that component in the parent\'s children array. The removed component and any statements only it referenced are automatically garbage-collected.',
  '',
  '### Patch size guide',
  '- Changing a title or label: 1 statement',
  '- Adding a component: 2-3 statements (the new component + parent update)',
  '- Removing a component: 1 statement (re-declare parent without the removed child)',
  '- Adding a filter + wiring to query: 3-5 statements',
  '- Restructuring into tabs: 5-10 statements',
  '',
  '### Rules',
  '- Reuse existing statement names exactly — do not rename',
  '- Do NOT re-emit unchanged statements — the runtime keeps them',
  '- A typical edit patch is 1-10 statements, not 20+',
  '- If the existing code already satisfies the request, output only the root statement',
  '- NEVER output the entire program as a patch. Only output what actually changes',
  '- If you are about to output more than 10 statements, reconsider — most edits need fewer'
].join('\n');

export class LocalGenUIEditMode {
  /** A follow-up request on an existing app: patch it, or rewrite it when asked. */
  static followUp(request: string, title: string, source: string, stateJson: string): string {
    return [
      request,
      '',
      `This conversation already has the mini app "${title}". If the request changes it, call the tool in edit mode: put only the changed or new statements in source.content, keeping existing statement names. Write the complete program only when the person asks for a new version or a full redesign. If the request does not change the app, answer in text.`,
      OPENUI_EDIT_MODE_RULES,
      'Its current OpenUI Lang source is:',
      source,
      `Current user state: ${stateJson}`
    ].join('\n');
  }
}
