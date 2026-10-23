import 'package:flutter/widgets.dart';

import 'stringcast.dart';

/// Makes a [StringCast] available to [StringCast.of] and rebuilds the widgets that call it whenever
/// a release arrives or the language changes. Put it above your `MaterialApp`:
///
/// ```dart
/// runApp(StringCastScope(child: MyApp()));
/// ...
/// Text(StringCast.of(context).t('welcome_title'))
/// ```
class StringCastScope extends StatelessWidget {
  const StringCastScope({super.key, this.stringcast, required this.child});

  /// Defaults to [StringCast.instance].
  final StringCast? stringcast;
  final Widget child;

  @override
  Widget build(BuildContext context) => StringCastInherited(notifier: stringcast ?? StringCast.instance, child: child);
}

/// Rebuilds [builder] on every StringCast update. Works without a [StringCastScope].
class StringCastBuilder extends StatelessWidget {
  const StringCastBuilder({super.key, this.stringcast, required this.builder});

  /// Defaults to [StringCast.instance].
  final StringCast? stringcast;
  final Widget Function(BuildContext context, StringCast stringcast) builder;

  @override
  Widget build(BuildContext context) {
    final sc = stringcast ?? StringCast.instance;
    return ListenableBuilder(listenable: sc, builder: (context, _) => builder(context, sc));
  }
}

/// A [Text] showing [StringCast.t] (or [StringCast.plural] when [count] is set) that updates over the air.
class StringCastText extends StatelessWidget {
  const StringCastText(
    this.stringKey, {
    super.key,
    this.args,
    this.count,
    this.defaultValue,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.semanticsLabel,
  });

  final String stringKey;

  /// `Map` for `{name}` placeholders or `List` for `%s` / `%d` / `%1$s`.
  final Object? args;

  /// When set, the key is looked up as a plural.
  final int? count;

  /// `String`, or a plural map when [count] is set.
  final Object? defaultValue;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final scoped = context.dependOnInheritedWidgetOfExactType<StringCastInherited>()?.notifier;
    Widget text(StringCast sc) => Text(
          count != null
              ? sc.plural(stringKey, count!, args: args, defaultValue: defaultValue)
              : sc.t(stringKey, args: args, defaultValue: defaultValue is String ? defaultValue as String : null),
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap,
          semanticsLabel: semanticsLabel,
        );
    if (scoped != null) return text(scoped);
    return StringCastBuilder(builder: (context, sc) => text(sc));
  }
}

/// Lets StringCast follow the locale your `MaterialApp` resolved, and exposes the instance through
/// `Localizations.of<StringCast>(context, StringCast)`:
///
/// ```dart
/// MaterialApp(
///   localizationsDelegates: const [StringCastLocalizationsDelegate(), ...GlobalMaterialLocalizations.delegates],
///   supportedLocales: StringCast.instance.supportedLocales,
/// )
/// ```
///
/// On a locale change it calls [StringCast.setAppLocale] and waits (up to [timeout]) for that
/// language's bundle, so the first frame in the new locale is already translated.
class StringCastLocalizationsDelegate extends LocalizationsDelegate<StringCast> {
  const StringCastLocalizationsDelegate({this.stringcast, this.timeout = const Duration(seconds: 3)});

  /// Defaults to [StringCast.instance].
  final StringCast? stringcast;
  final Duration timeout;

  @override
  bool isSupported(Locale locale) => true; // unknown languages fall back to the base language

  @override
  Future<StringCast> load(Locale locale) async {
    final sc = stringcast ?? StringCast.instance;
    sc.setAppLocale(locale);
    await sc.ensureLanguageLoaded(timeout: timeout);
    return sc;
  }

  @override
  bool shouldReload(StringCastLocalizationsDelegate old) => old.stringcast != stringcast;
}
