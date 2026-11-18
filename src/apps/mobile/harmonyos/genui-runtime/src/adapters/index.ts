import { harmonyCrossDeviceComponents } from '../components/harmonyCrossDeviceImage';
import { harmonyComponents } from '../components/harmonyComponents';
import { harmonyPageKitComponents } from '../components/harmonyPageKit';
import { harmonyScoreboardComponents } from '../components/harmonyScoreboard';
import { oiComponents } from '../components/oiComponents';
import { openUILibrary } from '../components/openuiLibrary';
import { HARMONY_GENUI_REVISION } from '../components/vendor/harmony-genui/harmonyGenuiStyles.generated';
import { functions } from '../genUIPrimitives';
import type { GenUIImplementations, GenUIRendererSource } from '../genUILibrary';

const sourcesFor = (
  components: Record<string, unknown>,
  source: GenUIRendererSource,
): Record<string, GenUIRendererSource> => Object.fromEntries(
  Object.keys(components).map(name => [name, source]),
);

const harmonyRendererSources: Record<string, GenUIRendererSource> = {
  ...sourcesFor(oiComponents, {
    kind: 'openui-react',
    source: 'open-intelligent-ui component contract adapter',
  }),
  ...sourcesFor(harmonyCrossDeviceComponents, { kind: 'harmony-adapter', source: 'harmonyCrossDeviceImage.tsx' }),
  ...sourcesFor(harmonyComponents, { kind: 'harmony-adapter', source: 'harmonyComponents.tsx' }),
  ...sourcesFor(harmonyScoreboardComponents, {
    kind: 'harmony-adapter',
    source: 'task_genui/harmony-genui apps/agent/src/scoreboard_block.py + scoreboard.js (managed scoreboard)',
    revision: HARMONY_GENUI_REVISION,
  }),
  ...sourcesFor(harmonyPageKitComponents, {
    kind: 'harmony-adapter',
    source: 'task_genui/harmony-genui/apps/agent/src/page_blocks.py (composePage block markup)',
    revision: HARMONY_GENUI_REVISION,
  }),
  // Keep the public contract provenance for the positional Button signature;
  // the selected implementation above still supplies the Harmony renderer.
  Button: {
    kind: 'openui-react',
    source: 'open-intelligent-ui component contract adapter',
  },
  Steps: {
    kind: 'openui-react',
    source: 'task_genui/openui/packages/react-ui/src/components/Steps',
    revision: 'f08a660535e55b5b2a24a0eb68568edaf9e4fe4b',
  },
};

/**
 * Concrete adapter boundaries. OpenUI supplies the language runtime; these
 * objects own the component renderer, inspector, event and capability bridge
 * for one registered library family.
 */
/** The default profile uses the upstream Open Intelligent UI library directly. */
export const openUIAdapter: GenUIImplementations = {
  components: {},
  rendererSources: {},
  functions: {},
  nativeLibrary: openUILibrary,
};

export const harmonyGenUIAdapter: GenUIImplementations = {
  components: { ...oiComponents, ...harmonyComponents, ...harmonyPageKitComponents, ...harmonyScoreboardComponents, ...harmonyCrossDeviceComponents },
  rendererSources: harmonyRendererSources,
  functions,
};

export const genUIAdapterImplementations: Record<string, GenUIImplementations> = {
  openui: openUIAdapter,
  'harmony-genui': harmonyGenUIAdapter,
};
