import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:stringcast/stringcast.dart';

// Defaults: the local backend's demo project (`npm run seed` in backend/).
const _projectId = String.fromEnvironment('STRINGCAST_PROJECT_ID', defaultValue: 'p_demo');
const _sdkKey = String.fromEnvironment('STRINGCAST_SDK_KEY', defaultValue: 'pk_demo_local');
const _baseUrl = String.fromEnvironment('STRINGCAST_BASE_URL');

/// The Android emulator reaches the host machine at 10.0.2.2, not localhost.
String get _localBaseUrl =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android ? 'http://10.0.2.2:8787' : 'http://localhost:8787';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StringCast.init(StringCastConfig(
    projectId: _projectId,
    sdkKey: _sdkKey,
    baseUrl: _baseUrl.isNotEmpty ? _baseUrl : _localBaseUrl,
    fallbackAssetsPath: 'assets/stringcast/',
    refreshInterval: const Duration(seconds: 30),
  ));
  runApp(const StringCastScope(child: DemoApp()));
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final sc = StringCast.of(context); // rebuilds when a release arrives or the language changes
    return MaterialApp(
      title: 'StringCast Demo',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF4F46E5)),
      // StringCast picks the language (device languages, or the picker below) and Material follows it.
      // Apps that choose the locale themselves add StringCastLocalizationsDelegate() instead.
      locale: sc.locale,
      supportedLocales: sc.supportedLocales.isEmpty ? const [Locale('en')] : sc.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _items = 1;
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await StringCast.instance.refresh(force: true);
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final sc = StringCast.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('StringCast'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('v${sc.version} · ${sc.language ?? '–'}', key: const Key('status'))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          StringCastText('welcome_title', key: const Key('welcome_title'), style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          const StringCastText('welcome_body'),
          const SizedBox(height: 20),
          Text(sc.t('greeting', args: ['Ana', 3]), style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                onPressed: _items > 0 ? () => setState(() => _items--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(onPressed: () => setState(() => _items++), icon: const Icon(Icons.add_circle_outline)),
              Expanded(child: Text(sc.plural('items_count', _items))),
            ],
          ),
          const SizedBox(height: 12),
          for (final (i, step) in sc.array('onboarding_steps').indexed) Text('${i + 1}. $step'),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('${sc.t('language_label')}: '),
              DropdownButton<String?>(
                value: sc.languages.contains(sc.language) ? sc.language : null,
                hint: const Text('Device'),
                items: [for (final l in sc.languages) DropdownMenuItem(value: l, child: Text(l))],
                onChanged: (l) => sc.setLanguage(l),
              ),
              TextButton(onPressed: () => sc.setLanguage(null), child: const Text('Device')),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('refresh'),
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            label: Text(sc.t('cta_refresh')),
          ),
        ],
      ),
    );
  }
}
