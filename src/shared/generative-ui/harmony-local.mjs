import { createHash } from 'node:crypto';
import { HARMONY_LOCAL_GAME_PROMPT } from './harmony-game-example.mjs';

/**
 * Harmony Local GenUI contract projection.
 *
 * The phone owns Local GenUI sessions, but it must not hand-write a second
 * component catalog, prompt or tool schema. Everything here is derived from the
 * compiled catalog so Desktop and Harmony consume one product definition.
 */
export const HARMONY_LOCAL_PROFILE = 'harmony';
export const HARMONY_LOCAL_TOOL_NAME = 'GenerativeUI';

const sha256 = text => createHash('sha256').update(text).digest('hex');

function stableJson(value) {
  return JSON.stringify(value, null, 2) + '\n';
}

/** Identity fields that only the owner may bind. The local tool schema hides them. */
export const HARMONY_LOCAL_OWNER_FIELDS = ['id', 'template', 'libraryId', 'libraryRevision', 'designSpec'];

export function projectHarmonyLocalContract(catalog) {
  const profile = catalog.profiles?.[HARMONY_LOCAL_PROFILE];
  if (!profile) throw new Error('Harmony local projection requires the harmony profile');
  const templateId = profile.templates[0];
  const template = catalog.templates[templateId];
  const libraryId = template.library;
  const library = catalog.libraries[libraryId];
  const adapter = catalog.libraryAdapters[libraryId];
  const designSpec = catalog.designSpecs[profile.designSpec];
  if (!library || !adapter || !designSpec) throw new Error('Harmony local projection requires a complete library and design specification');
  if (!designSpec.sourceKinds.includes('openui-lang')) throw new Error('Harmony local phase 1 requires openui-lang');

  // Phase 1 only ships openui-lang for the pinned harmony library. The local
  // catalog is the identity and validation contract consumed by ArkTS.
  const localCatalog = {
    contractVersion: catalog.contractVersion,
    profile: HARMONY_LOCAL_PROFILE,
    template: { id: templateId, ...template },
    library: { id: libraryId, revision: adapter.revision, adapterKind: adapter.adapterKind, rootComponent: adapter.rootComponent ?? library.metadata?.rootComponent ?? 'Col', components: Object.keys(library.components).sort() },
    designSpec: { id: profile.designSpec, ...designSpec },
    sourceKinds: ['openui-lang'],
  };

  // The phone calls the model directly, so its tool keeps the program one
  // level deep: `{title, source}` with source as the raw OpenUI Lang text.
  // Multi-model evals showed the nested openbitfun.genui.v1 envelope
  // (protocol/messages/createSurface/source.content) was the main failure
  // source: arrays sent as strings, a missing or extra closer after a program
  // full of braces, a misspelled protocol constant. The local parser still
  // accepts that envelope; Desktop keeps the shared protocol unchanged.
  const toolSchema = {
    name: HARMONY_LOCAL_TOOL_NAME,
    description: [
      'Create one interactive mini app for the user on this phone.',
      'Send title first, then source: the complete OpenUI Lang program as one string. values may give initial state values only.',
      'The host binds the component library, design specification and application identity; never send id, template, libraryId, libraryRevision or designSpec.',
      catalog.openuiLangReference.replace('OpenUI Lang source.content is', 'source is').replaceAll('source.content', 'source'),
    ].join(' '),
    input_schema: {
      type: 'object',
      properties: {
        title: { type: 'string', minLength: 1, description: 'Short app name in the user\'s language.' },
        source: { type: 'string', minLength: 1, description: 'The complete OpenUI Lang program, one statement per line, starting with root = Page(...).' },
        description: { type: 'string' },
        values: { type: 'object', description: 'Optional initial values for $state declared in source.' },
      },
      required: ['title', 'source'],
      additionalProperties: false,
    },
  };

  const prompt = [
    'You are the Local GenUI assistant in the OpenBitFun HarmonyOS phone app.',
    'You run without a workspace, shell, files, browsing or external tools. Never claim to use them.',
    `When an interactive mini app helps the user, call the ${HARMONY_LOCAL_TOOL_NAME} tool exactly once with an OpenUI Lang program; otherwise answer in plain text.`,
    'Keep any surrounding text short. Answer in the user\'s language.',
    'This phone provides local component state, new chat turns, the declared native calendar actions, gesture input, haptics and page orientation. Use the capability guidance below. Calendar controls are a default part of time-based planning apps; system writes run only when the user clicks them. Photo search is available: SearchImage and the photo fields of Shelf and Spotlight show real photos the phone finds for an exact subject query. Other network queries, maps and video are unsupported; prefer inline data, photo queries and the declared host-served picture components.',
    '',
    catalog.genuiSystemPrompts[HARMONY_LOCAL_PROFILE],
    '',
    HARMONY_LOCAL_GAME_PROMPT,
  ].join('\n');

  const catalogText = stableJson(localCatalog);
  const toolText = stableJson(toolSchema);
  const promptText = prompt.trim() + '\n';
  const catalogHash = sha256(catalogText);
  const manifest = {
    contractVersion: catalog.contractVersion,
    profile: HARMONY_LOCAL_PROFILE,
    template: templateId,
    libraryId,
    libraryRevision: adapter.revision,
    designSpec: { id: profile.designSpec, revision: designSpec.revision },
    sourceKinds: ['openui-lang'],
    ownerFields: HARMONY_LOCAL_OWNER_FIELDS,
    toolName: HARMONY_LOCAL_TOOL_NAME,
    catalogHash,
    promptHash: sha256(promptText),
    toolSchemaHash: sha256(toolText),
    rendererRevision: `${libraryId}@${adapter.revision}+${catalogHash.slice(0, 12)}`,
  };
  return {
    files: {
      'catalog.json': catalogText,
      'harmony-prompt.txt': promptText,
      'local-tool-schema.json': toolText,
      'runtime-manifest.json': stableJson(manifest),
    },
    manifest,
  };
}
