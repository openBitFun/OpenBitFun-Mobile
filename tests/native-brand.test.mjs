import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,readdirSync} from 'node:fs';
import sharp from 'sharp';
const HARMONY_MEDIA_DIRS=['src/apps/mobile/harmonyos/AppScope/resources/base/media','src/apps/mobile/harmonyos/entry/src/main/resources/base/media'];
test('iOS App Store icon is a 1024 pixel RGB image without alpha', async () => {
  const metadata = await sharp('src/apps/mobile/ios/OpenBitFun/Resources.xcassets/AppIcon.appiconset/openbitfun-app-icon.png').metadata();
  assert.equal(metadata.width, 1024);
  assert.equal(metadata.height, 1024);
  assert.equal(metadata.hasAlpha, false);
  assert.equal(metadata.channels, 3);
});


test('HarmonyOS generated media use valid resource identifiers', () => {
  for (const directory of HARMONY_MEDIA_DIRS) {
    for (const fileName of readdirSync(directory)) {
      const resourceName = fileName.replace(/\.[^.]+$/, '');
      assert.match(
        resourceName,
        /^[a-zA-Z0-9_]+$/,
        `${directory}/${fileName} is not a valid HarmonyOS resource name`,
      );
    }
  }

  const appConfig = readFileSync('src/apps/mobile/harmonyos/AppScope/app.json5', 'utf8');
  const moduleConfig = readFileSync('src/apps/mobile/harmonyos/entry/src/main/module.json5', 'utf8');
  assert.match(appConfig, /\$media:openbitfun_app_icon/);
  assert.match(moduleConfig, /\$media:openbitfun_app_icon/);
  assert.match(moduleConfig, /\$media:openbitfun_start_window/);
});
