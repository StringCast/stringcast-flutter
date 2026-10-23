# StringCast for Flutter

Over-the-air localization for Flutter apps. Ship your app with its strings, then update copy and add languages
from the [StringCast](https://stringcast.app) portal. No app release needed.

- Pure Dart: Android, iOS, web, macOS, Windows and Linux. No platform code of its own.
- The last-known release loads from the device cache during `init`, so the first frame is already localized.
  New releases download in the background and widgets rebuild when they arrive.
- Offline fallback from files you ship as assets: `<lang>.json` (what `stringcast pull` writes) or your existing
  Flutter **ARB** files.
- Strings, plurals (CLDR rules), string arrays, `{name}` and `%s` / `%1$s` / `%d` placeholders.
- Network, cache and parse errors are logged and swallowed. Nothing in the SDK should crash the host app.

Full guide: https://console.stringcast.app/docs/flutter

## Install

```sh
flutter pub add stringcast
```

## Initialise

Call `StringCast.init` once, before `runApp`, and wrap your app in `StringCastScope`:

```dart
import 'package:flutter/material.dart';
import 'package:stringcast/stringcast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StringCast.init(const StringCastConfig(
    projectId: 'p_8f3k2j',
    sdkKey: 'pk_…',                          // public SDK key
    fallbackAssetsPath: 'assets/stringcast/', // optional offline fallback
  ));
  runApp(const StringCastScope(child: MyApp()));
}
```

`init` reads the cached release and the fallback assets (local only, a few milliseconds), then checks for a
new release in the background. It never throws. `await StringCast.instance.ready` waits for that first check.

Every option:

```dart
StringCastConfig(
  projectId: 'p_demo',
  sdkKey: 'pk_demo_local',
  baseUrl: 'http://localhost:8787',        // default https://console.stringcast.app; Android emulator: http://10.0.2.2:8787
  languageOverride: null,                   // e.g. 'es-MX'; beats the device and app locales
  draftMode: null,                          // null = kDebugMode (see Draft mode)
  refreshInterval: Duration(minutes: 15),   // min time between manifest checks
  refreshOnResume: true,                    // re-check when the app returns to the foreground
  fallbackAssetsPath: 'assets/stringcast/', // <lang>.json or ARB files, declared under flutter: assets:
  fallbackStrings: {'en': {'welcome_title': 'Welcome'}},  // inline fallbacks, merged over the assets
  fallbackLanguage: 'en',                   // base language before the first release is known
  appId: null,                              // default: package name / bundle ID (package_info_plus)
  appVersion: null,                         // default: version name (package_info_plus)
  missingKeyDebounce: Duration(seconds: 5),
  logging: null,                            // verbose debugPrint logs; null = same as draft mode
  excludedKeys: {},                         // never uploaded or reported as missing
  autoUploadLocalStrings: true,             // draft mode: upload the fallbacks once per app version
)
```

Plain `http://` to a local backend needs `android:usesCleartextTraffic="true"` in the debug manifest on
Android, `NSAllowsLocalNetworking` in `Info.plist` on iOS, and the `com.apple.security.network.client`
entitlement on macOS.

## Looking up strings

```dart
final sc = StringCast.of(context);   // inside StringCastScope: this widget rebuilds on every update

Text(sc.t('welcome_title'));
Text(sc.t('greeting', args: {'name': user.name}));            // "Hello {name}"
Text(sc.t('greeting_printf', args: [user.name, unread]));     // "Hello %1$s, %2$d new"
Text(sc.plural('items_count', cart.length));                   // "%d items" / "{count} items"
Text(sc.t('promo', defaultValue: 'Get 20% off'));              // default when the key is missing
for (final step in sc.array('onboarding_steps')) Text(step);  // also reads key.0, key.1, …

const StringCastText('welcome_body');                           // a Text widget that updates itself
const StringCastText('items_count', count: 3);
StringCastBuilder(builder: (context, sc) => Text(sc.t('title'))); // works without a scope

StringCast.instance.t('welcome_title');                         // outside widgets (no rebuild)
```

**Lookup order:** resolved-language release → base-language release → bundled fallback (resolved language,
then base language) → `defaultValue` → the key itself.

**Placeholders:** values are stored as uploaded. A `Map` in `args` fills `{name}` and `{{name}}`; a `List`
fills `%s`, `%@`, `%d`, `%.2f`, `%1$s`, `%2$@` positionally (`%%` becomes `%`). Unknown placeholders are left as
they are.

**Plurals:** the category comes from CLDR cardinal rules for the language the value came from (same table as
the iOS and Android SDKs). An explicit `zero` form wins for 0. `count` fills `{count}` and the first `%d`. If the
value of a `t()` call is a plural map, `args['count']` picks the form.

## Language

```dart
sc.language          // "es" — as spelled in the project
sc.languages         // languages in the current release
sc.locale            // Locale for MaterialApp.locale
sc.supportedLocales  // for MaterialApp.supportedLocales
sc.setLanguage('fr') // in memory only: persist the user's choice and pass it as languageOverride
sc.setLanguage(null) // follow the device again
```

Resolution (contract §6.4): `languageOverride` / `setLanguage` beats everything. Otherwise the device
languages (`PlatformDispatcher.locales`) are tried in order: exact match (`es-MX`), language plus script
(`zh-Hant-TW` → `zh-Hant`, and `zh-TW` → `zh-Hant`), language only (`es`), then any project language with the
same language subtag (`pt-PT` → `pt-BR`). If nothing matches, the project's base language is used. Codes
compare case-insensitively, with `_` treated as `-`. Device language changes are picked up while the app runs.

Two ways to tie it to `MaterialApp`:

- **StringCast decides** (the example app): `locale: sc.locale, supportedLocales: sc.supportedLocales`.
  Material widgets follow StringCast's language.
- **Your app decides** (its own locale setting or Flutter's resolution): add
  `StringCastLocalizationsDelegate()` to `localizationsDelegates`. On every locale change it calls
  `setAppLocale` (tried before the device languages) and waits up to 3 s for that language's bundle, so the
  first frame in the new locale is translated. Don't combine it with `locale: sc.locale`.

## Updates

```dart
StringCast.instance.addListener(() => …);                       // it is a ChangeNotifier
StringCast.instance.updates.listen((u) => print(u.reason));     // release, language or bundle
await StringCast.instance.refresh(force: true);                  // check now, ignoring refreshInterval
```

1. **Init:** reads `manifest.json` and `bundle-<version>-<lang>.json` from
   `Application Support/StringCast/<projectId>/` (`localStorage` on the web).
2. **Background:** `GET /v1/sdk/<projectId>/manifest` with `If-None-Match`. If the release changed, only the
   **resolved** and **base** language bundles are downloaded, each checked against the manifest hash
   (SHA-256), version and language. Bundles are written first, then the manifest, then the old release is
   deleted. If any download fails, the previous release stays in use.
3. Other languages download when you switch to them. A check is skipped if one ran less than
   `refreshInterval` ago, and runs again when the app resumes.

## Offline fallback (assets)

Ship the strings the app had at build time so a fresh install without network is localized:

```yaml
flutter:
  assets:
    - assets/stringcast/
```

```sh
npx stringcast pull --platform web --path assets/stringcast --source published   # writes <lang>.json
```

ARB files work too, so an app that already uses `flutter gen-l10n` can point `fallbackAssetsPath` at a copy
of its `lib/l10n/` folder declared as assets. `@` metadata is skipped, the language comes from the file name
(`app_es.arb`, `intl_pt_BR.arb`) or `@@locale`, and a message that is a single ICU plural
(`{count, plural, =0{No items} one{# item} other{# items}}`) becomes a plural map with `{count}`.

## Draft mode

On by default in debug builds (`kDebugMode`), never in release builds unless you set `draftMode: true`.

- **Missing keys:** a key you look up that isn't in the base release, and that has a local value (fallback
  asset or `defaultValue`), is reported to `POST /v1/sdk/<id>/missing`. Reports are debounced (5 s), batched
  (≤ 500) and sent once per key per launch. The server creates new keys from base-language reports only and
  never overwrites a value.
- **Automatic upload:** once per app version, after the first manifest, the bundled fallback strings are
  uploaded: base language first (creates keys), then the other languages (fills empty values). The marker is
  stored only when every request succeeded. `await StringCast.instance.uploadLocalStrings()` does the same on
  demand and returns `created` / `filled` / `ignored`.
- `excludedKeys` are never uploaded or reported.

## What the SDK sends

Manifest checks and draft-mode reports go to `baseUrl` with your public SDK key (`X-Api-Key`) and these
check-in headers (contract §4.2):

| Header | Value |
|---|---|
| `X-StringCast-Platform` | `android`, `ios` (also macOS) or `web` |
| `X-StringCast-App-Id` | package name / bundle ID (omitted on the web: the server uses `Origin`) |
| `X-StringCast-App-Version` | the app's version name |
| `X-StringCast-SDK-Version` | `flutter-0.1.0` |
| `X-StringCast-Language` | the language the SDK resolved, e.g. `es` |

No device IDs, user identifiers or other personal data are sent. Bundle downloads (CDN URLs) carry no
check-in headers. On the web, register the app's origin on the portal's Apps page.

## Several projects, tests

`StringCast.create(config, httpClient: …, storage: MemoryStorage(), …)` builds an independent instance
without touching `StringCast.instance`; pass it to `StringCastScope(stringcast: …)`. Every dependency (HTTP
client, storage, preferred languages, clock) can be injected.

## Example app

[`example/`](example) shows strings, plurals, arrays, a language picker and a refresh button. It defaults to
the local backend's demo project (`p_demo` / `pk_demo_local`):

```sh
cd example
flutter run -d chrome
flutter run --dart-define=STRINGCAST_PROJECT_ID=p_… --dart-define=STRINGCAST_SDK_KEY=pk_… \
  --dart-define=STRINGCAST_BASE_URL=https://console.stringcast.app
```

## Development

```sh
flutter test        # language resolution, placeholders, plurals, ARB/JSON fallbacks, refresh, cache, draft mode, widgets
flutter analyze
dart pub publish --dry-run
```

License: Apache-2.0.
