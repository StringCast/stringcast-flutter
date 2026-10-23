import 'package:flutter_test/flutter_test.dart';
import 'package:stringcast/stringcast.dart';

void main() {
  const avail = ['en', 'es', 'es-MX', 'pt-BR', 'zh-Hans', 'zh-Hant'];

  String? r(List<String> prefs, {String? override, List<String> available = avail}) =>
      resolveLanguage(preferred: prefs, available: available, baseLanguage: 'en', override: override);

  test('exact match, case-insensitive, underscore normalised', () {
    expect(r(['es-mx']), 'es-MX');
    expect(r(['es_MX']), 'es-MX');
  });

  test('language only, then any variant with the same language', () {
    expect(r(['es-AR']), 'es');
    expect(r(['pt-PT']), 'pt-BR');
  });

  test('script: explicit and inferred for Chinese', () {
    expect(r(['zh-Hant-TW']), 'zh-Hant');
    expect(r(['zh-TW']), 'zh-Hant');
    expect(r(['zh-HK']), 'zh-Hant');
    expect(r(['zh-CN']), 'zh-Hans');
  });

  test('first preferred hit wins; base is the fallback', () {
    expect(r(['de', 'fr', 'es']), 'es');
    expect(r(['de']), 'en');
    expect(r([]), 'en');
  });

  test('override beats everything and is matched with the same rules', () {
    expect(r(['es'], override: 'pt'), 'pt-BR');
    expect(r(['es'], override: 'de_AT'), 'de-AT');
  });
}
