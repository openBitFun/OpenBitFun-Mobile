# OpenBitFun Mobile

Native Android, iOS and HarmonyOS controllers for [OpenBitFun](https://github.com/openBitFun/OpenBitFun).

The three apps and their shared Kotlin core now live in this repository.
Desktop, CLI, Relay and the browser mobile-web surface remain in OpenBitFun.
The original directory layout is retained to preserve native build paths.

## Build

Use Node.js 22.12+ and pnpm 10.15.0.

```sh
pnpm install --frozen-lockfile
pnpm run prepare:assets
pnpm run check
```

- [Android](src/apps/mobile/android/AGENTS.md): Android Studio JDK and Android SDK; run `./gradlew :app:assembleDebug` from `src/apps/mobile/android`.
- [iOS](src/apps/mobile/ios/README.md): Xcode and the Kotlin framework build described in the platform guide.
- [HarmonyOS](src/apps/mobile/harmonyos/README.md): DevEco Studio; local signing and SDK configuration stay outside Git.
- [Shared core](src/apps/mobile/AGENTS.md): run `./gradlew jvmTest` from `src/apps/mobile/shared`.
- [Design preview](src/apps/mobile/design-system/README.md): `pnpm run mobile:ui:preview`.
- [Mobile Design Lab and standalone prototype](design-system/apps/design-lab/README.md): `pnpm run mobile:design-lab`.

See [migration and compatibility ownership](MIGRATION.md), [app features](src/apps/mobile/README.md), and [contributing instructions](AGENTS.md).

## Releases

Native releases use `mobile-v*` tags in this repository. The migrated Android
release workflow retains its existing debug-signing prerelease behavior.
Production signing credentials are not included. iOS and HarmonyOS still require
their platform signing and distribution processes. Existing installed app IDs,
protocol versions and persisted data formats have not been renamed or reset.

## License

MIT; original OpenBitFun and bundled third-party notices are retained.
