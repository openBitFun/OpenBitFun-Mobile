import index from './vendor/fluent-emoji-animated-index.json';

/**
 * Animated Fluent Emoji (Microsoft, MIT) for cover pictures, served by the
 * Harmony host at one pinned commit next to the static 3D pictures. Only the
 * emoji the animated set covers have an entry; every other picture stays
 * static. See scripts/vendor-fluent-emoji-animated-index.mjs.
 */
export const LOCAL_GENUI_ICON3D_ANIMATED_ROOT = 'https://genui-assets.openbitfun.invalid/fluent-emoji/animated/';
const ASSET_ROOT = `${LOCAL_GENUI_ICON3D_ANIMATED_ROOT}${index.sha}/`;
const ASSETS: Record<string, string> = index.icons;

export function fluentEmojiAnimatedUrl(emoji: string): string | undefined {
  const key = Array.from(emoji.trim())
    .filter(character => character.codePointAt(0) !== 0xfe0f)
    .map(character => (character.codePointAt(0) ?? 0).toString(16))
    .join('-');
  const path = ASSETS[key];
  return path ? ASSET_ROOT + path.split('/').map(encodeURIComponent).join('/') : undefined;
}
