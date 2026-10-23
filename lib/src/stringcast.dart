import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'config.dart';
import 'format.dart';
import 'language.dart';
import 'local_strings.dart';
import 'models.dart';
import 'plural_rules.dart';
import 'storage.dart';
import 'storage_memory.dart';

/// Why listeners were notified.
enum StringCastUpdateReason {
  /// A new release was downloaded and is now in use.
  release,

  /// The resolved language changed (override, app locale or device languages).
  language,

  /// A bundle for another language finished loading (lazy language switch).
  bundle,
}

/// Payload of [StringCast.updates].
@immutable
class StringCastUpdate {
  const StringCastUpdate({required this.version, required this.language, required this.reason});

  /// Release version now in use (0 = none).
  final int version;

  /// Resolved language.
  final String? language;
  final StringCastUpdateReason reason;

  @override
  String toString() => 'StringCastUpdate(version: $version, language: $language, reason: ${reason.name})';
}

/// Result of [StringCast.uploadLocalStrings], summed over every request.
@immutable
class UploadResult {
  const UploadResult({this.created = 0, this.filled = 0, this.ignored = 0});

  final int created;
  final int filled;
  final int ignored;

  UploadResult operator +(UploadResult o) =>
      UploadResult(created: created + o.created, filled: filled + o.filled, ignored: ignored + o.ignored);

  @override
  String toString() => 'UploadResult(created: $created, filled: $filled, ignored: $ignored)';
}

/// Who is checking in (contract §4.2). Detected by [StringCast.init]; injectable for tests.
@immutable
class ClientInfo {
  const ClientInfo({this.platform, this.appId, this.appVersion});

  /// `android`, `ios` or `web`; `null` = header omitted.
  final String? platform;
  final String? appId;
  final String? appVersion;
}

typedef _Hit = ({Value value, String lang});

class _Record {
  _Record(this.manifest, this.etag, this.fetchedAt, this.bundles);

  final Manifest manifest;
  final String? etag;
  final int fetchedAt;

  /// Languages whose bundles are cached for `manifest.version`.
  final List<String> bundles;

  _Record copyWith({Manifest? manifest, String? etag, int? fetchedAt, List<String>? bundles}) =>
      _Record(manifest ?? this.manifest, etag ?? this.etag, fetchedAt ?? this.fetchedAt, bundles ?? this.bundles);

  Map<String, Object?> toJson() =>
      {'manifest': manifest.toJson(), 'etag': etag, 'fetchedAt': fetchedAt, 'bundles': bundles};

  static _Record? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      return _Record(
        Manifest.fromJson(json['manifest']),
        json['etag'] as String?,
        json['fetchedAt'] is int ? json['fetchedAt'] as int : 0,
        [for (final b in (json['bundles'] as List? ?? const [])) '$b'],
      );
    } catch (_) {
      return null;
    }
  }
}

const _maxMissingPerRequest = 500;
const _manifestFile = 'manifest.json';
const _uploadMarkerFile = 'upload-marker';
String _bundleFile(int version, String lang) => 'bundle-$version-$lang.json';

/// StringCast over-the-air localization.
///
/// ```dart
/// await StringCast.init(const StringCastConfig(projectId: 'p_…', sdkKey: 'pk_…'));
/// StringCast.instance.t('welcome_title');
/// ```
///
/// It is a [ChangeNotifier]: listeners are notified when a release arrives or the language changes.
/// In widgets, use [StringCast.of] (inside a `StringCastScope`), `StringCastBuilder` or
/// `StringCastText` so the UI rebuilds. Lookups never throw; network, cache and parse errors are
/// logged and swallowed.
class StringCast extends ChangeNotifier with WidgetsBindingObserver {
  StringCast._(
    this.config, {
    required http.Client httpClient,
    required StringCastStorage storage,
    required List<String> Function() preferredLanguages,
    required ClientInfo clientInfo,
    required DateTime Function() clock,
    required bool observeBinding,
  })  : _http = httpClient,
        _storage = storage,
        _preferred = preferredLanguages,
        _client = clientInfo,
        _clock = clock,
        _override = config.languageOverride {
    if (observeBinding) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  static StringCast? _instance;

  /// The instance created by [init]. Before [init] it is an inert instance that returns defaults /
  /// keys (and logs a warning).
  static StringCast get instance => _instance ??= _inert();

  static StringCast _inert() => StringCast._(
        const StringCastConfig(projectId: '', sdkKey: ''),
        httpClient: http.Client(),
        storage: MemoryStorage(),
        preferredLanguages: () => const [],
        clientInfo: const ClientInfo(),
        clock: DateTime.now,
        observeBinding: false,
      ).._inertInstance = true;

  /// Starts the SDK and makes it [instance]. Call once, before `runApp`:
  ///
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await StringCast.init(const StringCastConfig(projectId: 'p_…', sdkKey: 'pk_…'));
  ///   runApp(const MyApp());
  /// }
  /// ```
  ///
  /// It reads the cached release and the bundled fallbacks (fast, local only) and returns; the
  /// manifest check runs in the background (await [ready] to wait for it). Never throws.
  static Future<StringCast> init(StringCastConfig config, {http.Client? httpClient, StringCastStorage? storage}) async {
    WidgetsFlutterBinding.ensureInitialized();
    final previous = _instance;
    final sc = await create(config, httpClient: httpClient, storage: storage);
    _instance = sc;
    if (previous != null && !previous._inertInstance) previous.dispose();
    return sc;
  }

  /// Creates an independent instance without touching [instance] (several projects in one app, or
  /// tests). Every dependency can be injected.
  static Future<StringCast> create(
    StringCastConfig config, {
    http.Client? httpClient,
    StringCastStorage? storage,
    AssetBundle? assetBundle,
    List<String> Function()? preferredLanguages,
    ClientInfo? clientInfo,
    DateTime Function()? clock,
    bool observeBinding = true,
    bool autoRefresh = true,
  }) async {
    final results = await Future.wait<Object?>([
      storage != null ? Future.value(storage) : defaultStorage(config.projectId),
      clientInfo != null ? Future.value(clientInfo) : _detectClient(config),
    ]);
    final sc = StringCast._(
      config,
      httpClient: httpClient ?? http.Client(),
      storage: results[0]! as StringCastStorage,
      preferredLanguages: preferredLanguages ?? _deviceLanguages,
      clientInfo: results[1]! as ClientInfo,
      clock: clock ?? DateTime.now,
      observeBinding: observeBinding,
    );
    await Future.wait([sc._loadCache(), sc._loadFallbacks(assetBundle)]);
    sc._resolved = sc._computeLanguage();
    if (autoRefresh) {
      sc.ready = sc.refresh().then((_) => sc._maybeAutoUpload());
    }
    return sc;
  }

  /// The [StringCast] of the nearest `StringCastScope`, registering [context] to rebuild on every
  /// update. Falls back to [instance] (without rebuilds) when there is no scope.
  static StringCast of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StringCastInherited>();
    return scope?.notifier ?? instance;
  }

  final StringCastConfig config;
  final http.Client _http;
  final StringCastStorage _storage;
  final List<String> Function() _preferred;
  final ClientInfo _client;
  final DateTime Function() _clock;
  bool _inertInstance = false;
  bool _observing = false;
  bool _disposed = false;
  bool _warnedInert = false;

  _Record? _record;
  Map<String, StringBundle> _bundles = {};

  /// Bundled offline strings by language (as spelled in the files).
  final Map<String, Map<String, Value>> _fallbacks = {};
  String? _override;
  String? _appLocale;
  String? _resolved;

  Future<void>? _inflight;
  final Map<String, Future<void>> _bundleLoads = {};
  final StreamController<StringCastUpdate> _updates = StreamController.broadcast();

  final Map<String, Value> _pendingMissing = {};
  final Set<String> _reportedMissing = {};
  Timer? _missingTimer;

  /// Completes once the first background refresh attempt (and draft-mode auto upload) finished,
  /// successfully or not. Never completes with an error.
  Future<void> ready = Future.value();

  // ------------------------------------------------------------------------------ public state

  /// Resolved language (as spelled in the project), or `null` before anything is known.
  String? get language => _resolved;

  /// [language] as a [Locale] (e.g. for `MaterialApp.locale`).
  Locale? get locale => _resolved == null ? null : localeFromTag(_resolved!);

  /// Language codes in the current release (fallback languages before the first release).
  List<String> get languages => _record != null && _record!.manifest.languages.isNotEmpty
      ? _record!.manifest.codes
      : _fallbacks.keys.toList();

  /// [languages] as [Locale]s, e.g. for `MaterialApp.supportedLocales`.
  List<Locale> get supportedLocales => [for (final l in languages) localeFromTag(l)];

  /// The project's base language (`null` before any manifest is known).
  String? get baseLanguage => _record?.manifest.baseLanguage;

  /// Current release version (0 = none).
  int get version => _record?.manifest.version ?? 0;

  /// Whether draft mode is on (see [StringCastConfig.draftMode]).
  bool get draftMode => config.effectiveDraftMode;

  /// Every update (also delivered to [addListener] listeners).
  Stream<StringCastUpdate> get updates => _updates.stream;

  // ------------------------------------------------------------------------------ lookups

  /// The string for [key]. Lookup order: resolved-language release → base-language release →
  /// bundled fallback (resolved, then base language) → [defaultValue] → [key].
  ///
  /// [args] is a `Map` for `{name}` / `{{name}}` placeholders or a `List` for `%s` `%d` `%@` `%1$s`
  /// `%.2f`. If the value is a plural map, `args['count']` picks the form.
  String t(String key, {Object? args, String? defaultValue}) {
    try {
      final hit = _lookup(key);
      _trackMissing(key, defaultValue);
      if (hit != null) {
        final v = hit.value;
        if (v is String) return interpolate(v, args);
        if (v is Map<String, String>) {
          final count = args is Map ? args['count'] : null;
          return count is num ? _formatPlural(v, hit.lang, count.toInt(), args) : interpolate(v['other']!, args);
        }
      }
      return defaultValue != null ? interpolate(defaultValue, args) : key;
    } catch (e) {
      _warn('t($key) failed', e);
      return defaultValue ?? key;
    }
  }

  /// Plural string for [key] and [count], with CLDR rules of the language the value came from. An
  /// explicit `zero` form wins for 0. [count] fills `{count}` and the first `%d`.
  ///
  /// [defaultValue] is a `String` or a plural map (`{'one': '%d item', 'other': '%d items'}`).
  String plural(String key, int count, {Object? args, Object? defaultValue}) {
    try {
      final hit = _lookup(key);
      _trackMissing(key, defaultValue);
      if (hit != null) {
        final v = hit.value;
        if (v is Map<String, String>) return _formatPlural(v, hit.lang, count, args);
        if (v is String) return _formatPlural({'other': v}, hit.lang, count, args);
      }
      final def = defaultValue is String ? {'other': defaultValue} : parseValue(defaultValue);
      if (def is Map<String, String>) return _formatPlural(def, _resolved ?? baseLanguage, count, args);
      return key;
    } catch (e) {
      _warn('plural($key) failed', e);
      return key;
    }
  }

  /// String array for [key]; also reassembles iOS-style `key.0`, `key.1`, …
  List<String> array(String key, {List<String>? defaultValue}) {
    try {
      final hit = _lookup(key);
      _trackMissing(key, defaultValue);
      if (hit != null && hit.value is List<String>) return List.of(hit.value as List<String>);
      final flat = _lookupFlattenedArray(key);
      if (flat != null) return flat;
      return List.of(defaultValue ?? const []);
    } catch (e) {
      _warn('array($key) failed', e);
      return List.of(defaultValue ?? const []);
    }
  }

  /// Whether a release or fallback has a value for [key].
  bool has(String key) => _lookup(key) != null;

  String _formatPlural(Map<String, String> forms, String? lang, int count, Object? args) {
    final template = selectPlural(forms, count, lang) ?? '';
    if (args is List) return interpolate(template, args);
    final named = <String, Object?>{'count': count, if (args is Map) ...args.cast<String, Object?>()};
    return interpolate(template, named, [count]);
  }

  /// OTA (resolved, base) then bundled fallbacks (resolved, base).
  Iterable<({Map<String, Value> strings, String lang})> _sources() sync* {
    for (final lang in _lookupOrder()) {
      final b = _bundles[lang];
      if (b != null) yield (strings: b.strings, lang: lang);
    }
    final seen = <String>{};
    for (final lang in [_resolved, baseLanguage ?? _fallbackBase()]) {
      final match = LocalStrings.matchIn(lang, _fallbacks);
      if (match != null && seen.add(match)) yield (strings: _fallbacks[match]!, lang: match);
    }
  }

  _Hit? _lookup(String key) {
    if (_inertInstance) _warnInert();
    for (final s in _sources()) {
      final v = s.strings[key];
      if (!isEmptyValue(v)) return (value: v!, lang: s.lang);
    }
    return null;
  }

  List<String>? _lookupFlattenedArray(String key) {
    for (final s in _sources()) {
      if (s.strings['$key.0'] is! String) continue;
      final out = <String>[];
      for (var i = 0; s.strings['$key.$i'] is String; i++) {
        out.add(s.strings['$key.$i']! as String);
      }
      return out;
    }
    return null;
  }

  List<String> _lookupOrder() {
    final order = <String>[];
    if (_resolved != null) order.add(_resolved!);
    final base = baseLanguage;
    if (base != null && base != _resolved) order.add(base);
    return order;
  }

  String? _fallbackBase() {
    if (_fallbacks.isEmpty) return null;
    return config.fallbackLanguage ?? LocalStrings.matchIn('en', _fallbacks) ?? _fallbacks.keys.first;
  }

  // ------------------------------------------------------------------------------ language

  /// Force a language (beats the app and device locales); `null` follows them again. Kept in memory
  /// only: persist the user's choice yourself and pass it as [StringCastConfig.languageOverride].
  void setLanguage(String? code) {
    _override = (code == null || code.trim().isEmpty) ? null : code;
    _languageInputsChanged();
  }

  /// The locale the app's `Localizations` resolved (set by `StringCastLocalizationsDelegate`). It is
  /// tried before the device languages; an explicit [setLanguage] still wins.
  void setAppLocale(Locale? locale) {
    final tag = locale?.toLanguageTag();
    if (tag == _appLocale) return;
    _appLocale = tag;
    _languageInputsChanged();
  }

  void _languageInputsChanged() {
    final before = _resolved;
    _resolved = _computeLanguage();
    if (before != _resolved) _emit(StringCastUpdateReason.language);
    if (_resolved != null) unawaited(_ensureBundles([_resolved!]));
  }

  String? _computeLanguage() {
    final m = _record?.manifest;
    final prefs = [if (_appLocale != null) _appLocale!, ..._preferred()];
    if (m == null || m.languages.isEmpty) {
      if (_override != null) return _override;
      if (_fallbacks.isNotEmpty) {
        return resolveLanguage(preferred: prefs, available: _fallbacks.keys.toList(), baseLanguage: _fallbackBase());
      }
      return m?.baseLanguage;
    }
    return resolveLanguage(preferred: prefs, available: m.codes, baseLanguage: m.baseLanguage, override: _override);
  }

  /// Waits until the bundle of the current [language] is loaded (or failed), at most [timeout].
  Future<void> ensureLanguageLoaded({Duration timeout = const Duration(seconds: 3)}) async {
    final lang = _resolved;
    if (lang == null) return;
    try {
      await _ensureBundles([lang]).timeout(timeout);
    } catch (_) {
      // timeout: keep showing the fallback; listeners are notified when it arrives
    }
  }

  // ------------------------------------------------------------------------------ updates

  void _emit(StringCastUpdateReason reason) {
    if (_disposed) return;
    final event = StringCastUpdate(version: version, language: _resolved, reason: reason);
    _log('update: $event');
    if (!_updates.isClosed) _updates.add(event);
    notifyListeners();
  }

  @override
  void didChangeLocales(List<Locale>? locales) => _languageInputsChanged();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && config.refreshOnResume) unawaited(refresh());
  }

  // ------------------------------------------------------------------------------ cache

  Future<void> _loadCache() async {
    try {
      final rec = _Record.fromJson(_decode(await _storage.read(_manifestFile)));
      if (rec == null) return;
      if (rec.manifest.projectId.isNotEmpty && rec.manifest.projectId != config.projectId) return;
      final bundles = <String, StringBundle>{};
      for (final lang in rec.bundles) {
        try {
          final raw = await _storage.read(_bundleFile(rec.manifest.version, lang));
          if (raw != null) {
            bundles[lang] = StringBundle.fromJson(jsonDecode(raw), version: rec.manifest.version, language: lang);
          }
        } catch (e) {
          _warn('cached bundle $lang unreadable', e);
        }
      }
      _record = rec.copyWith(bundles: bundles.keys.toList());
      _bundles = bundles;
      _log('loaded cached release v${rec.manifest.version} (${bundles.keys.join(', ')})');
    } catch (e) {
      _warn('cache read failed', e);
    }
  }

  Future<void> _loadFallbacks(AssetBundle? assetBundle) async {
    final dir = config.fallbackAssetsPath;
    if (dir != null && dir.isNotEmpty) {
      try {
        final bundle = assetBundle ?? rootBundle;
        final prefix = dir.endsWith('/') ? dir : '$dir/';
        final manifest = await AssetManifest.loadFromAssetBundle(bundle);
        final files = manifest.listAssets().where((a) => a.startsWith(prefix) && (a.endsWith('.json') || a.endsWith('.arb')));
        for (final path in files) {
          final decoded = LocalStrings.decode(await bundle.loadString(path, cache: false));
          final lang = LocalStrings.languageOf(path, decoded);
          if (decoded == null || lang == null) {
            _warn('skipping fallback file $path (not a JSON object or no language in its name)');
            continue;
          }
          _fallbacks.update(lang, (m) => {...m, ...LocalStrings.parse(decoded)}, ifAbsent: () => LocalStrings.parse(decoded));
        }
        if (files.isEmpty) _warn('no .json/.arb files under $prefix — declare the folder under flutter: assets:');
      } catch (e) {
        _warn('loading fallback assets from $dir failed', e);
      }
    }
    config.fallbackStrings?.forEach((lang, strings) {
      final parsed = LocalStrings.parse(strings);
      _fallbacks.update(lang, (m) => {...m, ...parsed}, ifAbsent: () => parsed);
    });
  }

  Future<void> _writeRelease(_Record record, List<StringBundle> bundles, _Record? previous) async {
    try {
      final stored = <String>[];
      for (final b in bundles) {
        await _storage.write(_bundleFile(record.manifest.version, b.language), jsonEncode(b.toJson()));
        stored.add(b.language);
      }
      await _storage.write(_manifestFile, jsonEncode(record.copyWith(bundles: stored).toJson()));
      if (previous != null && previous.manifest.version != record.manifest.version) {
        for (final lang in previous.bundles) {
          await _storage.delete(_bundleFile(previous.manifest.version, lang));
        }
      }
    } catch (e) {
      _warn('cache write failed', e);
    }
  }

  Future<void> _touch(_Record record) async {
    try {
      await _storage.write(_manifestFile, jsonEncode(record.toJson()));
    } catch (e) {
      _warn('cache write failed', e);
    }
  }

  // ------------------------------------------------------------------------------ network

  /// Checks for a new release. Skipped when the last check was less than
  /// [StringCastConfig.refreshInterval] ago, unless [force]. Concurrent calls share one request.
  /// Never throws.
  Future<void> refresh({bool force = false}) {
    if (_inflight != null) return _inflight!;
    final f = _doRefresh(force).catchError((Object e) => _warn('refresh failed', e)).whenComplete(() => _inflight = null);
    _inflight = f;
    return f;
  }

  Future<void> _doRefresh(bool force) async {
    if (_disposed || _inertInstance || config.projectId.isEmpty) return;
    final rec = _record;
    final now = _clock().millisecondsSinceEpoch;
    if (rec != null && !force && now - rec.fetchedAt < config.refreshInterval.inMilliseconds) {
      await _ensureBundles(_wantedLanguages(rec.manifest));
      return;
    }

    final headers = {'X-Api-Key': config.sdkKey, 'Accept': 'application/json', ..._checkInHeaders()};
    final etag = rec == null ? null : rec.etag ?? '"v${rec.manifest.version}"';
    if (etag != null) headers['If-None-Match'] = etag;
    final url = Uri.parse('${config.apiOrigin}/v1/sdk/${Uri.encodeComponent(config.projectId)}/manifest');
    final res = await _http.get(url, headers: headers).timeout(const Duration(seconds: 30));

    if (res.statusCode == 304 && rec != null) {
      _record = rec.copyWith(fetchedAt: now);
      await _touch(_record!);
      _log('manifest unchanged (v${rec.manifest.version})');
      await _ensureBundles(_wantedLanguages(rec.manifest));
      return;
    }
    if (res.statusCode != 200) throw http.ClientException('manifest HTTP ${res.statusCode}: ${_short(res.body)}', url);

    final manifest = Manifest.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    final newEtag = res.headers['etag'] ?? '"v${manifest.version}"';

    if (rec != null && rec.manifest.version == manifest.version) {
      _record = rec.copyWith(manifest: manifest, etag: newEtag, fetchedAt: now);
      await _touch(_record!);
      await _ensureBundles(_wantedLanguages(manifest));
      return;
    }

    // New release: download resolved + base, then swap everything at once. Any failure keeps the old one.
    final wanted = _wantedLanguages(manifest);
    final downloaded = await Future.wait([for (final code in wanted) _downloadBundle(manifest, code)]);
    if (_disposed) return;
    final next = _Record(manifest, newEtag, now, wanted);
    await _writeRelease(next, downloaded, rec);
    _record = next;
    _bundles = {for (final b in downloaded) b.language: b};
    _resolved = _computeLanguage();
    _log('release v${manifest.version} in use (${wanted.join(', ')})');
    _emit(StringCastUpdateReason.release);
  }

  List<String> _wantedLanguages(Manifest manifest) {
    // Resolve against the new manifest without committing it yet.
    final resolved = resolveLanguage(
      preferred: [if (_appLocale != null) _appLocale!, ..._preferred()],
      available: manifest.codes,
      baseLanguage: manifest.baseLanguage,
      override: _override,
    );
    final codes = manifest.codes;
    return {resolved, manifest.baseLanguage}.whereType<String>().where(codes.contains).toList();
  }

  /// Loads bundles of the current release that are not in memory yet (lazy languages, cache misses).
  Future<void> _ensureBundles(List<String> codes) async {
    final rec = _record;
    if (rec == null || _inertInstance) return;
    await Future.wait([
      for (final code in codes)
        if (!_bundles.containsKey(code) && rec.manifest.entry(code) != null)
          _bundleLoads.putIfAbsent('${rec.manifest.version}:$code', () {
            return _downloadBundle(rec.manifest, code).then((b) async {
              if (_record?.manifest.version != rec.manifest.version || _disposed) return; // superseded
              _bundles[code] = b;
              final next = _record!.copyWith(bundles: {..._record!.bundles, code}.toList());
              _record = next;
              try {
                await _storage.write(_bundleFile(rec.manifest.version, code), jsonEncode(b.toJson()));
                await _touch(next);
              } catch (e) {
                _warn('cache write failed', e);
              }
              _emit(StringCastUpdateReason.bundle);
            }).catchError((Object e) => _warn('bundle $code failed', e)).whenComplete(
                () => _bundleLoads.remove('${rec.manifest.version}:$code'));
          }),
    ]);
  }

  Future<StringBundle> _downloadBundle(Manifest manifest, String code) async {
    final entry = manifest.entry(code);
    if (entry == null) throw StateError('language $code not in manifest');
    final url = Uri.parse(entry.url);
    // Bundle URLs are public (CDN): no key or check-in headers, except on the API host itself (local dev).
    final headers = {'Accept': 'application/json'};
    if (url.origin == Uri.parse(config.apiOrigin).origin) headers['X-Api-Key'] = config.sdkKey;
    final res = await _http.get(url, headers: headers).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw http.ClientException('bundle $code HTTP ${res.statusCode}', url);
    final bytes = res.bodyBytes;
    if (entry.hash != null && !verifyHash(bytes, entry.hash!)) throw StateError('bundle $code hash mismatch');
    final data = jsonDecode(utf8.decode(bytes));
    if (data is Map) {
      if (data['version'] is int && data['version'] != manifest.version) {
        throw StateError('bundle $code version ${data['version']} != manifest ${manifest.version}');
      }
      if (data['language'] is String && normalizeTag(data['language'] as String) != normalizeTag(code)) {
        throw StateError('bundle language ${data['language']} != $code');
      }
    }
    return StringBundle.fromJson(data, version: manifest.version, language: code);
  }

  /// Check-in headers (contract §4.2), for `/manifest` and `/missing` only. Printable ASCII; empty
  /// values omitted. No device or user identifiers.
  Map<String, String> _checkInHeaders() {
    final out = <String, String>{};
    void put(String name, String? value) {
      final v = asciiHeaderValue(value);
      if (v.isNotEmpty) out[name] = v;
    }

    put('X-StringCast-Platform', _client.platform);
    if (_client.platform != 'web') put('X-StringCast-App-Id', config.appId ?? _client.appId);
    put('X-StringCast-App-Version', config.appVersion ?? _client.appVersion);
    put('X-StringCast-SDK-Version', 'flutter-$sdkVersion');
    put('X-StringCast-Language', _resolved);
    return out;
  }

  // ------------------------------------------------------------------------------ draft mode

  void _trackMissing(String key, Object? defaultValue) {
    if (!draftMode || _disposed || _inertInstance) return;
    if (_reportedMissing.contains(key) || _pendingMissing.containsKey(key) || config.excludedKeys.contains(key)) return;
    final base = baseLanguage;
    if (base != null && _bundles[base]?.strings[key] != null) return;
    // Contract §4.2: keys without a local value are not reported.
    final fb = LocalStrings.matchIn(base ?? _fallbackBase(), _fallbacks);
    final local = (fb != null ? _fallbacks[fb]![key] : null) ?? parseValue(defaultValue);
    if (local == null) return;
    _pendingMissing[key] = local;
    _missingTimer ??= Timer(config.missingKeyDebounce, () {
      _missingTimer = null;
      unawaited(flushMissing());
    });
  }

  /// Sends pending missing-key reports now (draft mode).
  Future<void> flushMissing() async {
    _missingTimer?.cancel();
    _missingTimer = null;
    if (_pendingMissing.isEmpty || _disposed) return;
    await ready;
    final rec = _record;
    if (rec == null) return; // can't tell what's missing yet; keep pending for the next flush
    final base = rec.manifest.baseLanguage;
    final baseBundle = _bundles[base];
    if (rec.manifest.version > 0 && baseBundle == null) return; // base not loaded yet; retry later

    final items = <String, Value>{};
    for (final e in _pendingMissing.entries.toList()) {
      _pendingMissing.remove(e.key);
      if (baseBundle?.strings[e.key] != null) continue;
      _reportedMissing.add(e.key);
      items[e.key] = e.value;
    }
    if (items.isEmpty) return;
    try {
      final r = await _postStrings(base, items);
      _log('reported ${items.length} missing key(s): $r');
    } catch (e) {
      _warn('reporting ${items.length} missing keys failed', e);
      for (final it in items.entries) {
        _reportedMissing.remove(it.key);
        _pendingMissing[it.key] = it.value;
      }
    }
  }

  /// Uploads the bundled fallback strings ([StringCastConfig.fallbackAssetsPath] /
  /// [StringCastConfig.fallbackStrings]) to `/missing`: base language first (creates keys), then the
  /// other languages (fills empty values). The server never overwrites a value. Works in any build;
  /// throws on network errors. Excluded keys are skipped.
  Future<UploadResult> uploadLocalStrings() async {
    if (_fallbacks.isEmpty) return const UploadResult();
    final base = baseLanguage ?? _fallbackBase();
    final baseMatch = LocalStrings.matchIn(base, _fallbacks);
    final langs = [if (baseMatch != null) baseMatch, ..._fallbacks.keys.where((l) => l != baseMatch)];
    var total = const UploadResult();
    for (final lang in langs) {
      final strings = {
        for (final e in _fallbacks[lang]!.entries)
          if (!config.excludedKeys.contains(e.key)) e.key: e.value,
      };
      // Send the project's spelling of the base language so new keys are created.
      total += await _postStrings(lang == baseMatch && base != null ? base : lang, strings);
    }
    return total;
  }

  Future<UploadResult> _postStrings(String language, Map<String, Value> strings) async {
    var total = const UploadResult();
    final entries = strings.entries.toList();
    final url = Uri.parse('${config.apiOrigin}/v1/sdk/${Uri.encodeComponent(config.projectId)}/missing');
    for (var i = 0; i < entries.length; i += _maxMissingPerRequest) {
      final batch = entries.sublist(i, i + _maxMissingPerRequest > entries.length ? entries.length : i + _maxMissingPerRequest);
      final res = await _http
          .post(
            url,
            headers: {'X-Api-Key': config.sdkKey, 'Content-Type': 'application/json', ..._checkInHeaders()},
            body: jsonEncode({
              if (_client.platform != null) 'platform': _client.platform,
              'language': language,
              'keys': [for (final e in batch) {'key': e.key, 'value': e.value}],
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw http.ClientException('missing HTTP ${res.statusCode}: ${_short(res.body)}', url);
      final body = jsonDecode(res.body);
      if (body is Map) {
        total += UploadResult(
          created: body['created'] is int ? body['created'] as int : 0,
          filled: body['filled'] is int ? body['filled'] as int : 0,
          ignored: body['ignored'] is int ? body['ignored'] as int : 0,
        );
      }
    }
    return total;
  }

  /// Draft mode: upload the fallbacks once per app version + SDK version (+ content), after the
  /// first manifest. The marker is stored only when every request succeeded.
  Future<void> _maybeAutoUpload() async {
    if (!draftMode || !config.autoUploadLocalStrings || _fallbacks.isEmpty || _disposed || _inertInstance) return;
    if (_record == null) {
      _warn('no manifest yet (offline or wrong key); local strings will be uploaded on a later launch');
      return;
    }
    final keyCount = _fallbacks.values.fold<int>(0, (n, m) => n + m.length);
    final marker = '${config.appVersion ?? _client.appVersion ?? ''}|$sdkVersion|${_fallbacks.length}|$keyCount';
    try {
      if (await _storage.read(_uploadMarkerFile) == marker) return;
      final r = await uploadLocalStrings();
      await _storage.write(_uploadMarkerFile, marker);
      debugPrint('[StringCast] uploaded local strings (${_fallbacks.keys.join(', ')}; $keyCount values): $r');
    } catch (e) {
      _warn('uploading local strings failed; will retry on next launch', e);
    }
  }

  // ------------------------------------------------------------------------------ lifecycle

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _missingTimer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    unawaited(_updates.close());
    if (identical(_instance, this)) _instance = null;
    super.dispose();
  }

  // ------------------------------------------------------------------------------ logging

  bool get _verbose => config.logging ?? draftMode;

  void _log(String message) {
    if (_verbose) debugPrint('[StringCast] $message');
  }

  void _warn(String message, [Object? error]) => debugPrint('[StringCast] $message${error != null ? ': $error' : ''}');

  void _warnInert() {
    if (_warnedInert) return;
    _warnedInert = true;
    debugPrint('[StringCast] StringCast.instance used before StringCast.init(); returning defaults.');
  }
}

/// Verifies an SRI-style `sha256-<base64>` (or hex) hash of [bytes]. Unknown formats are accepted.
bool verifyHash(List<int> bytes, String hash) {
  if (!hash.startsWith('sha256-')) return true;
  final digest = sha256.convert(bytes);
  final expected = hash.substring('sha256-'.length);
  return expected == base64.encode(digest.bytes) || expected.toLowerCase() == digest.toString();
}

/// Printable ASCII only, trimmed (header values must be ASCII-safe).
String asciiHeaderValue(String? value) => (value ?? '').replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();

/// `zh-Hant-TW` → `Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW')`.
Locale localeFromTag(String tag) {
  final parts = tag.replaceAll('_', '-').split('-');
  String? script;
  String? country;
  for (final p in parts.skip(1)) {
    if (p.length == 4 && script == null && country == null) {
      script = p[0].toUpperCase() + p.substring(1).toLowerCase();
    } else if ((p.length == 2 || (p.length == 3 && int.tryParse(p) != null)) && country == null) {
      country = p.toUpperCase();
    }
  }
  return Locale.fromSubtags(languageCode: parts.first.toLowerCase(), scriptCode: script, countryCode: country);
}

Object? _decode(String? raw) {
  if (raw == null) return null;
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

String _short(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

List<String> _deviceLanguages() {
  try {
    return [for (final l in WidgetsBinding.instance.platformDispatcher.locales) l.toLanguageTag()];
  } catch (_) {
    return const [];
  }
}

Future<ClientInfo> _detectClient(StringCastConfig config) async {
  final platform = kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.android => 'android',
          TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
          _ => null,
        };
  if (config.appId != null && config.appVersion != null) {
    return ClientInfo(platform: platform, appId: config.appId, appVersion: config.appVersion);
  }
  try {
    final info = await PackageInfo.fromPlatform().timeout(const Duration(seconds: 2));
    return ClientInfo(
      platform: platform,
      appId: info.packageName.isEmpty ? null : info.packageName,
      appVersion: info.version.isEmpty ? null : info.version,
    );
  } catch (_) {
    return ClientInfo(platform: platform);
  }
}

/// Exposes a [StringCast] to descendants; see `StringCastScope`.
class StringCastInherited extends InheritedNotifier<StringCast> {
  const StringCastInherited({super.key, required StringCast super.notifier, required super.child});
}
