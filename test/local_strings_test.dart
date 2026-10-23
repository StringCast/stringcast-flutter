import 'package:flutter_test/flutter_test.dart';
import 'package:stringcast/src/local_strings.dart';

void main() {
  test('language from file names and @@locale', () {
    expect(LocalStrings.languageOf('assets/stringcast/es.json', {}), 'es');
    expect(LocalStrings.languageOf('assets/stringcast/pt-BR.json', {}), 'pt-BR');
    expect(LocalStrings.languageOf('lib/l10n/app_en.arb', {}), 'en');
    expect(LocalStrings.languageOf('lib/l10n/intl_pt_BR.arb', {}), 'pt-BR');
    expect(LocalStrings.languageOf('lib/l10n/my_app_zh_Hant_TW.arb', {}), 'zh-Hant-TW');
    expect(LocalStrings.languageOf('lib/l10n/strings.arb', {'@@locale': 'fr_CA'}), 'fr-CA');
    expect(LocalStrings.languageOf('lib/l10n/strings.arb', {}), isNull);
  });

  test('ARB: metadata skipped, ICU plural converted', () {
    final parsed = LocalStrings.parse({
      '@@locale': 'en',
      'title': 'Hello {name}',
      '@title': {'description': 'greeting'},
      'items': '{count, plural, =0{No items} =1{One item} one{# item} other{# items}}',
      'mixed': 'You have {count, plural, one{# item} other{# items}} left',
    });
    expect(parsed.keys, ['title', 'items', 'mixed']);
    expect(parsed['title'], 'Hello {name}');
    expect(parsed['items'], {'zero': 'No items', 'one': 'One item', 'other': '{count} items'});
    expect(parsed['mixed'], isA<String>());
  });

  test('JSON: contract value types kept, nested objects flattened', () {
    final parsed = LocalStrings.parse({
      'a': 'x',
      'p': {'one': '%d item', 'other': '%d items'},
      'arr': ['1', '2'],
      'nested': {'deep': 'y'},
      'bad': 3,
    });
    expect(parsed, {
      'a': 'x',
      'p': {'one': '%d item', 'other': '%d items'},
      'arr': ['1', '2'],
      'nested.deep': 'y',
    });
  });
}
