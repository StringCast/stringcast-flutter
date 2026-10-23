# Releasing the StringCast Flutter SDK

Package: [`stringcast`](https://pub.dev/packages/stringcast) on pub.dev. Source of truth is `sdk-flutter/` in
the monorepo; the public mirror is `github.com/stringcast/stringcast-flutter` (the pubspec `repository`).

1. Bump `version` in `pubspec.yaml` **and** `sdkVersion` in `lib/src/config.dart` (sent as
   `X-StringCast-SDK-Version: flutter-<version>`). Add a `CHANGELOG.md` entry.
2. Check:
   ```sh
   flutter test && flutter analyze
   dart pub publish --dry-run       # must report 0 warnings
   ```
3. Commit, then mirror and tag from the monorepo root:
   ```sh
   scripts/release-sdk.sh flutter <version>     # → github.com/stringcast/stringcast-flutter, tag v<version>
   ```
4. Publish from `sdk-flutter/` (needs a pub.dev login; the first time `dart pub publish` opens a browser):
   ```sh
   dart pub publish
   ```
   Later, a verified publisher (`stringcast.app`, pub.dev → *Create publisher*, DNS verification) can own the
   package, and the mirror repo can publish from GitHub Actions with
   [automated publishing](https://dart.dev/tools/pub/automated-publishing) on `v*` tags.

Published versions are permanent: pub.dev never deletes a version (it can only be *retracted* within 7 days).
To fix a bad release, bump the version and publish again.
