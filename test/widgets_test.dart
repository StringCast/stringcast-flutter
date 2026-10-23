import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:stringcast/stringcast.dart';

void main() {
  var version = 1;
  var welcome = 'Welcome v1';

  final client = MockClient((req) async {
    if (req.url.path.endsWith('/manifest')) {
      return http.Response(
        jsonEncode({
          'projectId': 'p_w',
          'version': version,
          'baseLanguage': 'en',
          'languages': [
            {'code': 'en', 'url': 'https://cdn.test/v$version/en.json'},
            {'code': 'de', 'url': 'https://cdn.test/v$version/de.json'},
          ],
        }),
        200,
      );
    }
    final lang = req.url.pathSegments.last.replaceAll('.json', '');
    return http.Response.bytes(
      utf8.encode(jsonEncode({
        'version': version,
        'language': lang,
        'strings': {'welcome': lang == 'de' ? 'Willkommen' : welcome, 'n': {'one': '{count} pin', 'other': '{count} pins'}},
      })),
      200,
    );
  });

  Future<StringCast> make(WidgetTester tester) async {
    final sc = await tester.runAsync(() => StringCast.create(
          const StringCastConfig(projectId: 'p_w', sdkKey: 'pk', baseUrl: 'https://api.test', draftMode: false),
          httpClient: client,
          storage: MemoryStorage(),
          preferredLanguages: () => const ['en'],
          clientInfo: const ClientInfo(),
          observeBinding: false,
        ));
    await tester.runAsync(() => sc!.ready);
    addTearDown(sc!.dispose);
    return sc;
  }

  testWidgets('StringCastScope, StringCastText and StringCastBuilder rebuild on a new release', (tester) async {
    version = 1;
    welcome = 'Welcome v1';
    final sc = await make(tester);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: StringCastScope(
        stringcast: sc,
        child: Column(children: [
          Builder(builder: (context) => Text('scope:${StringCast.of(context).t('welcome')}')),
          const StringCastText('n', count: 3),
          StringCastBuilder(stringcast: sc, builder: (context, s) => Text('builder:${s.t('welcome')}')),
        ]),
      ),
    ));
    expect(find.text('scope:Welcome v1'), findsOneWidget);
    expect(find.text('3 pins'), findsOneWidget);
    expect(find.text('builder:Welcome v1'), findsOneWidget);

    version = 2;
    welcome = 'Welcome v2';
    await tester.runAsync(() => sc.refresh(force: true));
    await tester.pump();
    expect(find.text('scope:Welcome v2'), findsOneWidget);
    expect(find.text('builder:Welcome v2'), findsOneWidget);
  });

  testWidgets('Localizations delegate follows the app locale', (tester) async {
    version = 1;
    final sc = await make(tester);
    final delegate = StringCastLocalizationsDelegate(stringcast: sc);
    final loaded = await tester.runAsync(() => delegate.load(const Locale('de', 'AT')));
    expect(loaded, same(sc));
    expect(sc.language, 'de');
    expect(sc.t('welcome'), 'Willkommen');
    expect(sc.supportedLocales, [const Locale('en'), const Locale('de')]);
  });
}
