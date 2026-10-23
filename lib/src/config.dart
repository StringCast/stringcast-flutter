import 'package:flutter/foundation.dart';

/// SDK version, sent as `X-StringCast-SDK-Version` (prefixed `flutter-`). Keep in sync with pubspec.yaml.
const sdkVersion = '0.1.0';

/// Hosted StringCast (portal + API on one origin).
const defaultBaseUrl = 'https://console.stringcast.app';

/// Options for [StringCast.init].
@immutable
class StringCastConfig {
  const StringCastConfig({
    required this.projectId,
    required this.sdkKey,
    this.baseUrl = defaultBaseUrl,
    this.languageOverride,
    this.draftMode,
    this.refreshInterval = const Duration(minutes: 15),
    this.refreshOnResume = true,
    this.fallbackAssetsPath,
    this.fallbackStrings,
    this.fallbackLanguage,
    this.appId,
    this.appVersion,
    this.missingKeyDebounce = const Duration(seconds: 5),
    this.logging,
    this.excludedKeys = const {},
    this.autoUploadLocalStrings = true,
  });

  /// Project id, e.g. `p_8f3k2j`.
  final String projectId;

  /// Public SDK key (`pk_…`). It ships inside the app; never use the secret upload key here.
  final String sdkKey;

  /// API origin, with or without `/v1`. Local backend: `http://localhost:8787` (iOS simulator, desktop,
  /// web) or `http://10.0.2.2:8787` (Android emulator).
  final String baseUrl;

  /// Force a language; beats the device and app locales.
  final String? languageOverride;

  /// Report keys the app uses that the project lacks, and upload the bundled fallback strings once per
  /// app version. `null` (default) = on in debug builds (`kDebugMode`) only.
  final bool? draftMode;

  /// Minimum time between automatic manifest checks.
  final Duration refreshInterval;

  /// Check for a new release when the app returns to the foreground (honours [refreshInterval]).
  final bool refreshOnResume;

  /// Asset folder with offline fallback files shipped in the app, e.g. `assets/stringcast/` (declare
  /// it under `flutter: assets:`). Files: `<lang>.json` (what `stringcast pull --platform web` writes)
  /// or Flutter ARB files (`app_<lang>.arb`, `intl_<lang>.arb`, or any `.arb` with `@@locale`).
  final String? fallbackAssetsPath;

  /// Offline fallback strings by language: `{'en': {'welcome_title': 'Welcome'}}`. Merged over
  /// [fallbackAssetsPath]. Values use the contract's types (string, plural map, list).
  final Map<String, Map<String, Object>>? fallbackStrings;

  /// Base language of the fallback strings, used before the first release is known (a fresh install
  /// that is offline). Defaults to `en` when the fallbacks have it, else their first language.
  final String? fallbackLanguage;

  /// `X-StringCast-App-Id`. Default: the package name / bundle ID from `package_info_plus`.
  final String? appId;

  /// `X-StringCast-App-Version`. Default: the app's version name from `package_info_plus`.
  final String? appVersion;

  /// Debounce for missing-key reports (draft mode).
  final Duration missingKeyDebounce;

  /// Verbose logs via `debugPrint`. `null` = same as draft mode. Failures are always logged.
  final bool? logging;

  /// Keys never uploaded or reported as missing.
  final Set<String> excludedKeys;

  /// Draft mode: upload the bundled fallback strings once per app version.
  final bool autoUploadLocalStrings;

  bool get effectiveDraftMode => draftMode ?? kDebugMode;

  /// [baseUrl] without trailing `/` or `/v1`.
  String get apiOrigin {
    var u = baseUrl.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.endsWith('/v1')) u = u.substring(0, u.length - 3);
    return u;
  }
}
