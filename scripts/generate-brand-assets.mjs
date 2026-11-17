import {mkdir,readFile,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import sharp from 'sharp';
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(SCRIPT_DIR, '..');
const SOURCE_DIR = path.join(ROOT_DIR, 'assets', 'brand', 'source');
const SOURCE_SVG = path.join(ROOT_DIR, 'design-system/packages/ui/src/brand/assets/openbitfun-mark.svg');
const SOURCE_APP_MARK = path.join(ROOT_DIR, 'design-system/packages/ui/src/brand/assets/openbitfun-app-mark.png');
const SOURCE_MARKS = {
  dark: path.join(SOURCE_DIR, 'openbitfun-mark-dark.png'),
  light: path.join(SOURCE_DIR, 'openbitfun-mark-light.png'),
};

const BRAND_SIZE = 512;
const APP_ICON_SIZE = 1024;
const APP_ICON_CORNER_RADIUS = 96;
const APP_MARK_LIFT = 28;
const ANDROID_FOREGROUND_SCALE = 0.66;

const ANDROID_DENSITIES = {
  mdpi: { icon: 48, adaptive: 108 },
  hdpi: { icon: 72, adaptive: 162 },
  xhdpi: { icon: 96, adaptive: 216 },
  xxhdpi: { icon: 144, adaptive: 324 },
  xxxhdpi: { icon: 192, adaptive: 432 },
};

const outputPath = (...segments) => path.join(ROOT_DIR, ...segments);

async function writePng(filePath, buffer) {
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, buffer);
}

function createReusableWebMark(svg) {
  const reusableMark = svg.replaceAll('stroke="black"', 'stroke="currentColor"');
  if (!reusableMark.includes('stroke="currentColor"')) {
    throw new Error('OpenBitFun mark source is missing its canonical inherited-color strokes');
  }
  return reusableMark;
}

async function normalizePng(input) {
  return sharp(input)
    .ensureAlpha()
    .resize({ width: BRAND_SIZE, height: BRAND_SIZE, fit: 'contain', kernel: 'lanczos3' })
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer();
}

async function renderMark(svg, size, tone, opticalSize = size) {
  // At favicon sizes, fifteen subpixel strokes disappear. Keep the same
  // silhouette with fewer filaments. The opaque outer rim must survive
  // antialiasing independently of the decorative interior strokes.
  const indices = opticalSize <= 24 ? [0, 7, 14]
    : opticalSize <= 48 ? [0, 3, 7, 11, 14]
      : opticalSize <= 96 ? [0, 2, 4, 7, 10, 12, 14] : null;
  let index = 0;
  const reusableMark = createReusableWebMark(svg);
  const artwork = indices ? reusableMark.replace(/<path\b[^>]*\/>/g, element => {
    const contour = index++;
    if (!indices.includes(contour)) return '';
    const outer = contour === 14;
    const inner = contour === 0;
    const width = Math.max(outer ? 3.2 : inner ? 1.2 : 0.7,
      (outer ? 1.35 : inner ? 0.85 : 0.65) * 256 / opticalSize);
    return element.replace(/ (?:stroke-width|opacity)="[^"]*"/g, '')
      .replace('/>', ` stroke-width="${width}" opacity="${outer ? 1 : inner ? 0.9 : 0.75}"/>`);
  }) : reusableMark;
  return sharp(Buffer.from(artwork.replaceAll('currentColor', tone)), { density: 144 })
    .resize(size, size)
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer();
}

async function resizePng(input, size) {
  return sharp(input)
    .resize({ width: size, height: size, fit: 'contain', kernel: 'lanczos3' })
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer();
}

async function createApplicationMark(lightMark) {
  const { data, info } = await sharp(lightMark)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  const channels = info.channels;
  const whiteMark = Buffer.alloc(data.length);

  for (let index = 0; index < data.length; index += channels) {
    const sourceTone = data[index];
    const liftedTone = Math.min(255, sourceTone + APP_MARK_LIFT);
    whiteMark[index] = liftedTone;
    whiteMark[index + 1] = liftedTone;
    whiteMark[index + 2] = liftedTone;
    whiteMark[index + 3] = data[index + 3];
  }

  return sharp(whiteMark, {
    raw: { width: info.width, height: info.height, channels: 4 },
  })
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer();
}

async function createApplicationIcon(applicationMark) {
  const { width: size } = await sharp(applicationMark).metadata();
  const cornerRadius = APP_ICON_CORNER_RADIUS * size / BRAND_SIZE;
  const background = Buffer.from(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">` +
      `<rect width="${size}" height="${size}" rx="${cornerRadius}" fill="#000000"/>` +
    '</svg>',
  );

  return sharp({
    create: {
      width: size,
      height: size,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite([
      { input: background },
      { input: applicationMark },
    ])
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer();
}

async function createAdaptiveForeground(applicationMark, size) {
  const artworkSize = Math.round(size * ANDROID_FOREGROUND_SCALE);
  const artwork = await resizePng(applicationMark, artworkSize);

  return sharp({
    create: {
      width: size,
      height: size,
      channels: 4,
      background: { r: 255, g: 255, b: 255, alpha: 0 },
    },
  })
    .composite([{
      input: artwork,
      left: Math.floor((size - artworkSize) / 2),
      top: Math.floor((size - artworkSize) / 2),
    }])
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer();
}

async function generateBrandAssets() {
  const applicationMark = await createApplicationMark(await normalizePng(SOURCE_APP_MARK));
  const svg = await readFile(SOURCE_SVG, 'utf8');
  const lightMark = await renderMark(svg, BRAND_SIZE, '#e8e8e8');
  const applicationIcon = await createApplicationIcon(applicationMark);
  const applicationIconLarge = await resizePng(applicationIcon, APP_ICON_SIZE);
  const renderIcon = size => resizePng(applicationIcon, size);
  for (const [density, sizes] of Object.entries(ANDROID_DENSITIES)) {
    const legacyIcon = await renderIcon(sizes.icon);
    const adaptiveForeground = await createAdaptiveForeground(applicationMark, sizes.adaptive);
    const androidDir = outputPath('src', 'apps', 'mobile', 'android', 'app', 'src', 'main', 'res', `mipmap-${density}`);
    await writePng(path.join(androidDir, 'ic_launcher.png'), legacyIcon);
    await writePng(path.join(androidDir, 'ic_launcher_round.png'), legacyIcon);
    await writePng(path.join(androidDir, 'ic_launcher_foreground.png'), adaptiveForeground);
    await writePng(path.join(androidDir, 'ic_launcher_monochrome.png'), adaptiveForeground);
  }

  await writePng(
    outputPath('src', 'apps', 'mobile', 'ios', 'OpenBitFun', 'Resources.xcassets', 'AppIcon.appiconset', 'openbitfun-app-icon.png'),
    // App Store icons must be opaque; iOS applies its own corner mask.
    await sharp(applicationIconLarge).flatten({ background: '#000000' }).png().toBuffer(),
  );
  await writePng(
    outputPath('src', 'apps', 'mobile', 'ios', 'OpenBitFun', 'Resources.xcassets', 'OpenBitFunMark.imageset', 'openbitfun-mark-light.png'),
    lightMark,
  );

  await writePng(
    outputPath('src', 'apps', 'mobile', 'harmonyos', 'AppScope', 'resources', 'base', 'media', 'openbitfun_app_icon.png'),
    applicationIconLarge,
  );
  await writePng(
    outputPath('src', 'apps', 'mobile', 'harmonyos', 'entry', 'src', 'main', 'resources', 'base', 'media', 'openbitfun_app_icon.png'),
    applicationIconLarge,
  );
  await writePng(
    outputPath('src', 'apps', 'mobile', 'harmonyos', 'entry', 'src', 'main', 'resources', 'base', 'media', 'openbitfun_start_window.png'),
    await resizePng(lightMark, 144),
  );

}
await generateBrandAssets();
