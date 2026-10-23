import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stringcast/stringcast.dart';

const api = 'https://api.test';
const cdn = 'https://cdn.test';

/// A tiny in-memory StringCast backend (contract §3–4).
class FakeBackend {
  int version = 1;
  String baseLanguage = 'en';
  Map<String, Map<String, Object>> strings = {
    'en': {
      'welcome': 'Welcome',
      'greeting': 'Hello {name}',
      'items': {'one': '%d item', 'other': '%d items'},
      'planets': ['Mercury', 'Venus'],
    },
    'es': {
      'welcome': 'Bienvenido',
      'items': {'one': '%d artículo', 'other': '%d artículos'},
    },
    'fr': {'welcome': 'Bienvenue'},
  };
  bool corruptHash = false;
  int manifestStatus = 200;
  final requests = <http.Request>[];
  final missingReports = <Map<String, Object?>>[];

  List<http.Request> get manifestRequests => requests.where((r) => r.url.path.endsWith('/manifest')).toList();
  List<String> get bundleDownloads =>
      [for (final r in requests) if (r.url.host == 'cdn.test') r.url.pathSegments.last];

  String bundleBody(String lang) =>
      jsonEncode({'projectId': 'p_test', 'version': version, 'language': lang, 'strings': strings[lang]});

  late final client = MockClient((req) async {
    requests.add(req);
    final path = req.url.path;
    if (path == '/v1/sdk/p_test/manifest') {
      if (req.headers['X-Api-Key'] != 'pk_test') return http.Response('{"error":{}}', 401);
      if (manifestStatus != 200) return http.Response('', manifestStatus);
      final etag = '"v$version"';
      if (req.headers['If-None-Match'] == etag) return http.Response('', 304, headers: {'etag': etag});
      return http.Response(
        jsonEncode({
          'projectId': 'p_test',
          'version': version,
          'baseLanguage': baseLanguage,
          'languages': [
            for (final l in strings.keys)
              {
                'code': l,
                'url': '$cdn/p_test/v$version/$l.json',
                'hash': corruptHash
                    ? 'sha256-AAAA'
                    : 'sha256-${base64.encode(sha256.convert(utf8.encode(bundleBody(l))).bytes)}',
              },
          ],
        }),
        200,
        headers: {'etag': etag, 'content-type': 'application/json'},
      );
    }
    if (req.url.host == 'cdn.test') {
      final lang = req.url.pathSegments.last.replaceAll('.json', '');
      return http.Response.bytes(utf8.encode(bundleBody(lang)), 200);
    }
    if (path == '/v1/sdk/p_test/missing') {
      missingReports.add(jsonDecode(req.body) as Map<String, Object?>);
      final keys = (jsonDecode(req.body) as Map)['keys'] as List;
      return http.Response(jsonEncode({'created': keys.length, 'filled': 0, 'ignored': 0}), 200);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late MemoryStorage storage;
  var now = DateTime(2026, 10, 23, 12);
  final created = <StringCast>[];

  setUp(() {
    backend = FakeBackend();
    storage = MemoryStorage();
    now = DateTime(2026, 10, 23, 12);
  });

  tearDown(() {
    for (final sc in created) {
      sc.dispose();
    }
    created.clear();
  });

  Future<StringCast> make({
    List<String> prefs = const ['es-MX', 'en-US'],
    bool? draftMode = false,
    String? override,
    Map<String, Map<String, Object>>? fallbackStrings,
    bool autoUpload = true,
  }) async {
    final sc = await StringCast.create(
      StringCastConfig(
        projectId: 'p_test',
        sdkKey: 'pk_test',
        baseUrl: '$api/v1/',
        draftMode: draftMode,
        languageOverride: override,
        fallbackStrings: fallbackStrings,
        missingKeyDebounce: const Duration(milliseconds: 10),
        autoUploadLocalStrings: autoUpload,
        logging: false,
      ),
      httpClient: backend.client,
      storage: storage,
      preferredLanguages: () => prefs,
      clientInfo: const ClientInfo(platform: 'android', appId: 'com.acme.app', appVersion: '1.2.3'),
      clock: () => now,
      observeBinding: false,
    );
    created.add(sc);
    return sc;
  }

  test('first launch: downloads resolved + base bundles, then serves OTA values', () async {
    final sc = await make();
    expect(sc.t('welcome', defaultValue: 'Hi'), 'Hi'); // nothing cached yet
    final events = <StringCastUpdate>[];
    sc.updates.listen(events.add);
    var notified = 0;
    sc.addListener(() => notified++);
    await sc.ready;
    await Future<void>.delayed(Duration.zero);

    expect(sc.version, 1);
    expect(sc.language, 'es');
    expect(sc.languages, ['en', 'es', 'fr']);
    expect(backend.bundleDownloads, unorderedEquals(['es.json', 'en.json']));
    expect(sc.t('welcome'), 'Bienvenido');
    expect(sc.t('greeting', args: {'name': 'Ana'}), 'Hello Ana'); // base-language fallback
    expect(sc.plural('items', 3), '3 artículos');
    expect(sc.plural('items', 1), '1 artículo');
    expect(sc.t('items', args: {'count': 1}), '1 artículo');
    expect(sc.array('planets'), ['Mercury', 'Venus']);
    expect(sc.t('nope'), 'nope');
    expect(sc.t('nope', defaultValue: 'Default {x}', args: {'x': 1}), 'Default 1');
    expect(events.single.reason, StringCastUpdateReason.release);
    expect(notified, 1);
  });

  test('check-in headers on the manifest, none on CDN bundles', () async {
    final sc = await make();
    await sc.ready;
    final m = backend.manifestRequests.single.headers;
    expect(m['X-StringCast-Platform'], 'android');
    expect(m['X-StringCast-App-Id'], 'com.acme.app');
    expect(m['X-StringCast-App-Version'], '1.2.3');
    expect(m['X-StringCast-SDK-Version'], 'flutter-$sdkVersion');
    final bundleReq = backend.requests.firstWhere((r) => r.url.host == 'cdn.test');
    expect(bundleReq.headers.keys.where((h) => h.startsWith('X-')), isEmpty);
  });

  test('second launch: cached release is available before any network call', () async {
    (await make()).ready.then((_) {});
    await created.first.ready;
    backend.requests.clear();
    backend.manifestStatus = 500; // offline-ish

    final sc = await make();
    expect(sc.t('welcome'), 'Bienvenido');
    expect(sc.version, 1);
    await sc.ready; // within refreshInterval: no manifest request at all
    expect(backend.manifestRequests, isEmpty);
  });

  test('refresh interval, 304 and new releases', () async {
    final sc = await make();
    await sc.ready;
    await sc.refresh();
    expect(backend.manifestRequests, hasLength(1)); // interval not elapsed

    now = now.add(const Duration(minutes: 16));
    await sc.refresh();
    expect(backend.manifestRequests, hasLength(2));
    expect(backend.manifestRequests.last.headers['If-None-Match'], '"v1"');

    backend.version = 2;
    backend.strings['es']!['welcome'] = '¡Hola!';
    await sc.refresh(force: true);
    expect(sc.version, 2);
    expect(sc.t('welcome'), '¡Hola!');
    // Old bundles were pruned from the cache.
    expect(storage.entries.keys.where((k) => k.startsWith('bundle-1-')), isEmpty);
    expect(storage.entries.keys.where((k) => k.startsWith('bundle-2-')), hasLength(2));
  });

  test('a bad bundle hash keeps the previous release', () async {
    final sc = await make();
    await sc.ready;
    backend.version = 2;
    backend.strings['es']!['welcome'] = 'Roto';
    backend.corruptHash = true;
    await sc.refresh(force: true);
    expect(sc.version, 1);
    expect(sc.t('welcome'), 'Bienvenido');
  });

  test('wrong key or server errors never throw', () async {
    backend.manifestStatus = 401;
    final sc = await make();
    await sc.ready;
    expect(sc.version, 0);
    expect(sc.t('welcome', defaultValue: 'Welcome!'), 'Welcome!');
    expect(sc.plural('items', 2, defaultValue: {'one': '%d thing', 'other': '%d things'}), '2 things');
  });

  test('setLanguage loads the other bundle lazily and notifies', () async {
    final sc = await make();
    await sc.ready;
    final reasons = <StringCastUpdateReason>[];
    sc.updates.listen((e) => reasons.add(e.reason));
    sc.setLanguage('fr-CA');
    expect(sc.language, 'fr');
    await sc.ensureLanguageLoaded();
    await Future<void>.delayed(Duration.zero);
    expect(sc.t('welcome'), 'Bienvenue');
    expect(reasons, [StringCastUpdateReason.language, StringCastUpdateReason.bundle]);
    sc.setLanguage(null);
    expect(sc.language, 'es');
  });

  test('app locale (from the Localizations delegate) beats device languages, override beats both', () async {
    final sc = await make();
    await sc.ready;
    sc.setAppLocale(const Locale('fr'));
    expect(sc.language, 'fr');
    sc.setLanguage('en');
    expect(sc.language, 'en');
  });

  test('bundled fallbacks: used offline and below the release', () async {
    backend.manifestStatus = 503;
    final fallbacks = {
      'en': <String, Object>{'welcome': 'Welcome (bundled)', 'only_local': 'Local'},
      'es': <String, Object>{'welcome': 'Bienvenido (local)'},
    };
    final sc = await make(fallbackStrings: fallbacks);
    expect(sc.language, 'es');
    expect(sc.t('welcome'), 'Bienvenido (local)');
    expect(sc.t('only_local'), 'Local');
    await sc.ready;

    backend.manifestStatus = 200;
    await sc.refresh(force: true);
    expect(sc.t('welcome'), 'Bienvenido');
    expect(sc.t('only_local'), 'Local');
  });

  test('draft mode reports missing keys with their local value, once', () async {
    final sc = await make(draftMode: true, autoUpload: false);
    await sc.ready;
    sc.t('welcome', defaultValue: 'x'); // exists in base: not reported
    sc.t('promo', defaultValue: 'Get 20% off');
    sc.t('promo', defaultValue: 'Get 20% off');
    sc.t('no_default'); // no local value: not reported
    sc.plural('cart', 2, defaultValue: {'one': '%d thing', 'other': '%d things'});
    await sc.flushMissing();
    expect(backend.missingReports, hasLength(1));
    final report = backend.missingReports.single;
    expect(report['platform'], 'android');
    expect(report['language'], 'en');
    expect(report['keys'], [
      {'key': 'promo', 'value': 'Get 20% off'},
      {
        'key': 'cart',
        'value': {'one': '%d thing', 'other': '%d things'},
      },
    ]);
    sc.t('promo', defaultValue: 'Get 20% off');
    await sc.flushMissing();
    expect(backend.missingReports, hasLength(1));
  });

  test('draft mode auto-uploads bundled strings once per app version, base language first', () async {
    final fallbacks = {
      'es': <String, Object>{'local_title': 'Título'},
      'en': <String, Object>{'local_title': 'Title'},
    };
    final sc = await make(draftMode: true, fallbackStrings: fallbacks);
    await sc.ready;
    expect([for (final r in backend.missingReports) r['language']], ['en', 'es']);

    final again = await make(draftMode: true, fallbackStrings: fallbacks);
    await again.ready;
    expect(backend.missingReports, hasLength(2)); // marker stored: not uploaded again
  });

  test('release mode never reports', () async {
    final sc = await make(draftMode: false);
    await sc.ready;
    sc.t('promo', defaultValue: 'Promo');
    await sc.flushMissing();
    expect(backend.missingReports, isEmpty);
  });

  test('concurrent refreshes share one request', () async {
    final sc = await make();
    await sc.ready;
    now = now.add(const Duration(hours: 1));
    await Future.wait([sc.refresh(), sc.refresh(), sc.refresh()]);
    expect(backend.manifestRequests, hasLength(2));
  });

  test('instance before init is inert', () {
    expect(StringCast.instance.t('k', defaultValue: 'd'), 'd');
    expect(StringCast.instance.t('k'), 'k');
    unawaited(StringCast.instance.refresh());
  });

  test('locale helpers', () {
    expect(localeFromTag('zh-Hant-TW'), const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'));
    expect(localeFromTag('pt_BR'), const Locale('pt', 'BR'));
    expect(localeFromTag('es-419'), const Locale('es', '419'));
  });
}
