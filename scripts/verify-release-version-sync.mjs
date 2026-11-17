import {readFileSync} from 'node:fs';
const args=parseArgs(process.argv.slice(2));
const mobileVersions = new Map([
  ['src/apps/mobile/android/app/build.gradle.kts', readTextVersion('src/apps/mobile/android/app/build.gradle.kts', /versionName\s*=\s*"([^"]+)"/)],
  ['src/apps/mobile/ios/OpenBitFun/Info.plist', readTextVersion('src/apps/mobile/ios/OpenBitFun/Info.plist', /<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)],
  ['src/apps/mobile/harmonyos/AppScope/app.json5', readTextVersion('src/apps/mobile/harmonyos/AppScope/app.json5', /"versionName"\s*:\s*"([^"]+)"/)],
]);

const expected=args['mobile-version'] || mobileVersions.values().next().value;
for(const [file,version] of mobileVersions) { if(version!==expected) throw new Error(`${file}: expected ${expected}, found ${version}`); }
console.log(`Mobile version: ${expected}`);
function readTextVersion(file, pattern) {
  const match = pattern.exec(readFileSync(file, 'utf8'));
  if (!match) throw new Error(`Version was not found in ${file}`);
  return match[1];
}

function parseArgs(rawArgs) {
  const parsed = {};
  for (let i = 0; i < rawArgs.length; i += 1) {
    const arg = rawArgs[i];
    if (!arg.startsWith('--')) continue;
    parsed[arg.slice(2)] = rawArgs[i + 1];
    i += 1;
  }
  return parsed;
}
