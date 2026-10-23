import 'plural_rules.dart';

/// A key's value in one language (contract §2): `String`, plural map (`Map<String, String>` with
/// `other`) or `List<String>`. Anything else is rejected by [parseValue].
typedef Value = Object;

/// Validates and converts decoded JSON into a [Value]; `null` when it isn't one.
Value? parseValue(Object? v) {
  if (v is String) return v;
  if (v is List) return v.every((e) => e is String) ? List<String>.unmodifiable(v.cast<String>()) : null;
  if (v is Map) {
    if (v.isEmpty || v['other'] is! String) return null;
    for (final e in v.entries) {
      if (!pluralCategories.contains(e.key) || e.value is! String) return null;
    }
    return Map<String, String>.unmodifiable(v.cast<String, String>());
  }
  return null;
}

/// True for an empty / absent value (treated as missing, contract §3).
bool isEmptyValue(Object? v) =>
    v == null || (v is String && v.isEmpty) || (v is List && v.isEmpty) || (v is Map && v.isEmpty);

// {{name}} or {name}
final _named = RegExp(r'\{\{\s*([A-Za-z0-9_.$-]+)\s*\}\}|\{([A-Za-z0-9_.$-]+)\}');
// %% | %1$s %1$@ %1$d | %s %@ %d %i %u %f %.2f %ld %lld
final _positional = RegExp(r'%%|%(?:(\d+)\$)?(?:\.(\d+))?(?:ll|l|h)?([sdif@u])');

String _formatArg(Object? arg, String conv, String? precision) {
  if (arg is num) {
    if (conv == 'd' || conv == 'i' || conv == 'u') return arg.truncate().toString();
    if (conv == 'f') return precision != null ? arg.toStringAsFixed(int.parse(precision)) : arg.toString();
  }
  return '$arg';
}

/// Interpolates [template] (contract §2 placeholders, same rules as the web SDK).
///
/// - a `Map` fills `{name}` / `{{name}}` (unknown names are left as-is);
/// - a `List` fills `%s` `%d` `%@` `%.2f` `%1$s` … positionally, and `%%` becomes `%`.
///
/// [positional], when given, is used for printf tokens even if [args] is a map (plurals pass the count).
String interpolate(String template, Object? args, [List<Object?>? positional]) {
  if (args == null && positional == null) return template;
  var out = template;
  final named = args is Map ? args : null;
  final list = args is List ? args : positional;
  if (named != null && named.isNotEmpty) {
    out = out.replaceAllMapped(_named, (m) {
      final name = m[1] ?? m[2]!;
      return named.containsKey(name) ? '${named[name]}' : m[0]!;
    });
  }
  if (list != null) {
    var next = 0;
    out = out.replaceAllMapped(_positional, (m) {
      if (m[0] == '%%') return '%';
      final i = m[1] != null ? int.parse(m[1]!) - 1 : next++;
      if (i < 0 || i >= list.length) return m[0]!;
      return _formatArg(list[i], m[3]!, m[2]);
    });
  }
  return out;
}
