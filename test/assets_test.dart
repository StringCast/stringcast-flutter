import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stringcast/stringcast.dart';

/// Serves [files] plus an `AssetManifest.bin` listing them, like a built app.
class FakeAssets extends CachingAssetBundle {
  FakeAssets(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        for (final f in files.keys)
          f: [
            {'asset': f},
          ],
      })!;
    }
    final text = files[key];
    if (text == null) throw FlutterError('missing asset $key');
    return ByteData.sublistView(utf8.encode(text));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fallback assets: JSON and ARB files, with an offline backend', () async {
    final sc = await StringCast.create(
      const StringCastConfig(
        projectId: 'p',
        sdkKey: 'pk',
        baseUrl: 'https://api.test',
        fallbackAssetsPath: 'assets/l10n',
        draftMode: false,
        logging: false,
      ),
      httpClient: MockClient((_) async => http.Response('', 503)),
      storage: MemoryStorage(),
      assetBundle: FakeAssets({
        'assets/l10n/app_en.arb': jsonEncode({
          'title': 'Pigeons',
          'count': '{count, plural, =0{No birds} one{# bird} other{# birds}}',
          '@count': {'placeholders': {}},
        }),
        'assets/l10n/es.json': jsonEncode({'title': 'Palomas'}),
        'assets/other/ignored.json': '{}',
      }),
      preferredLanguages: () => const ['es-ES'],
      clientInfo: const ClientInfo(),
      observeBinding: false,
    );
    addTearDown(sc.dispose);
    await sc.ready;

    expect(sc.languages, unorderedEquals(['en', 'es']));
    expect(sc.language, 'es');
    expect(sc.t('title'), 'Palomas');
    expect(sc.plural('count', 0), 'No birds'); // from the English fallback
    expect(sc.plural('count', 4), '4 birds');
  });
}
