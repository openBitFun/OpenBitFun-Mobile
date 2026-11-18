import { util } from '@kit.ArkTS';
import { OhosError } from '../OhosError';
import { LocalGenUIManifest } from './LocalGenUIModels';
import { LocalCanvasSpec } from './LocalGenUIRuntimeProtocol';

/** Generated Local GenUI contract read from HAP rawfile. Never hand-written. */
export interface LocalGenUIContract {
  manifest: LocalGenUIManifest;
  prompt: string;
  /** Raw JSON of `{ name, description, input_schema }`. */
  toolSchemaJson: string;
  /** Acceptance checks required by the pinned design specification. */
  requiredChecks: string[];
  canvas: LocalCanvasSpec;
}

interface LocalCatalogInsets {
  left?: number;
  right?: number;
}

interface LocalCatalogShell {
  contentInsets?: LocalCatalogInsets;
}

interface LocalCatalogViewport {
  width?: number;
}

interface LocalCatalogDesignSpec {
  acceptance?: LocalCatalogAcceptance;
  viewport?: LocalCatalogViewport;
  shell?: LocalCatalogShell;
}

interface LocalCatalogAcceptance {
  checks?: string[];
}

interface LocalCatalog {
  designSpec?: LocalCatalogDesignSpec;
}

export class LocalGenUIContractLoader {
  static async load(context: Context): Promise<LocalGenUIContract> {
    try {
      const manifest = JSON.parse(await LocalGenUIContractLoader.read(context, 'genui/runtime-manifest.json')) as LocalGenUIManifest;
      const catalog = JSON.parse(await LocalGenUIContractLoader.read(context, 'genui/catalog.json')) as LocalCatalog;
      const prompt = await LocalGenUIContractLoader.read(context, 'genui/harmony-prompt.txt');
      const toolSchemaJson = await LocalGenUIContractLoader.read(context, 'genui/local-tool-schema.json');
      const checks = catalog.designSpec && catalog.designSpec.acceptance && catalog.designSpec.acceptance.checks
        ? catalog.designSpec.acceptance.checks : [];
      const spec = catalog.designSpec;
      const width = spec && spec.viewport && spec.viewport.width ? spec.viewport.width : 0;
      const insets = spec && spec.shell && spec.shell.contentInsets ? spec.shell.contentInsets : undefined;
      if (!manifest.libraryId || !manifest.catalogHash || prompt.length === 0 || checks.length === 0 || width <= 0 || !insets) {
        throw new Error('generated Local GenUI contract is incomplete');
      }
      const canvas: LocalCanvasSpec = { width, insetLeft: insets.left || 0, insetRight: insets.right || 0 };
      return { manifest, prompt, toolSchemaJson, requiredChecks: checks, canvas };
    } catch (err) {
      throw OhosError.wrap('local genui contract load', err);
    }
  }

  private static async read(context: Context, path: string): Promise<string> {
    const bytes = await context.resourceManager.getRawFileContent(path);
    const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    return decoder.decodeToString(bytes);
  }
}
