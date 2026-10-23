import 'dart:convert';

import 'format.dart';
import 'language.dart';

/// Reads offline fallback files: flat `<lang>.json` (contract §4.3 `json` format, nested non-plural
/// objects flattened with `.`) and Flutter ARB files (`@`-metadata skipped, whole-message ICU plurals
/// converted to plural maps).
class LocalStrings {
  LocalStrings._();

  /// Language of an asset file, from its name (`es.json`, `app_es.arb`, `intl_pt_BR.arb`) or the ARB
  /// `@@locale` entry. `null` when it can't be told.
  static String? languageOf(String path, Object? decoded) {
    if (decoded is Map && decoded['@@locale'] is String) return (decoded['@@locale'] as String).replaceAll('_', '-');
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return null;
    final stem = name.substring(0, dot);
    // ARB: `app_en` → `en`, `intl_pt_BR` → `pt-BR`, `app_zh_Hant_TW` → `zh-Hant-TW` (longest suffix wins).
    if (name.endsWith('.arb')) {
      for (var i = stem.indexOf('_'); i >= 0; i = stem.indexOf('_', i + 1)) {
        final suffix = stem.substring(i + 1);
        if (_arbSuffix.hasMatch(suffix)) return suffix.replaceAll('_', '-');
      }
    }
    return _bareTag.hasMatch(stem) ? stem.replaceAll('_', '-') : null;
  }

  static final _bareTag = RegExp(r'^[a-z]{2,3}([-_][A-Za-z]{4})?([-_]([A-Za-z]{2}|\d{3}))?$');
  static final _arbSuffix = RegExp(r'^[a-z]{2,3}(_[A-Z][a-z]{3})?(_([A-Z]{2}|\d{3}))?$');

  /// `{key: value}` from a decoded JSON / ARB object.
  static Map<String, Value> parse(Object? decoded) {
    final out = <String, Value>{};
    if (decoded is! Map) return out;
    void walk(String prefix, Map<Object?, Object?> map) {
      map.forEach((k, v) {
        if (k is! String || k.startsWith('@')) return;
        final key = prefix.isEmpty ? k : '$prefix.$k';
        if (v is String) {
          out[key] = icuPlural(v) ?? v;
          return;
        }
        final value = parseValue(v);
        if (value != null) {
          out[key] = value;
        } else if (v is Map) {
          walk(key, v);
        }
      });
    }

    walk('', decoded);
    return out;
  }

  /// Decodes a file's text; `null` when it isn't a JSON object.
  static Object? decode(String text) {
    try {
      final d = jsonDecode(text);
      return d is Map ? d : null;
    } catch (_) {
      return null;
    }
  }

  /// `{count, plural, =0{none} one{# item} other{# items}}` → `{zero: none, one: {count} item, other: {count} items}`.
  /// Only messages that are a single plural are converted; `null` otherwise.
  static Map<String, String>? icuPlural(String message) {
    final head = RegExp(r'^\s*\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*plural\s*,').firstMatch(message);
    if (head == null || !message.trimRight().endsWith('}')) return null;
    final variable = head[1]!;
    final body = message.trimRight();
    var i = head.end;
    final end = body.length - 1; // the outer closing brace
    final forms = <String, String>{};
    final exact = <String>{};
    while (i < end) {
      while (i < end && body[i].trim().isEmpty) {
        i++;
      }
      if (i >= end) break;
      final selStart = i;
      while (i < end && body[i] != '{' && body[i].trim().isNotEmpty) {
        i++;
      }
      final selector = body.substring(selStart, i);
      while (i < end && body[i].trim().isEmpty) {
        i++;
      }
      if (i >= end || body[i] != '{') return null;
      var depth = 0;
      final textStart = i + 1;
      for (; i < end; i++) {
        if (body[i] == '{') depth++;
        if (body[i] == '}' && --depth == 0) break;
      }
      if (depth != 0) return null;
      final text = body.substring(textStart, i).replaceAll('#', '{$variable}');
      i++;
      final category = switch (selector) { '=0' => 'zero', '=1' => 'one', '=2' => 'two', _ => selector };
      if (selector.startsWith('offset:')) continue;
      if (!const ['zero', 'one', 'two', 'few', 'many', 'other'].contains(category)) continue;
      // Exact selectors (`=1`) win over the category (`one`) they map to, as in ICU.
      if (selector.startsWith('=')) {
        exact.add(category);
      } else if (exact.contains(category)) {
        continue;
      }
      forms[category] = text;
    }
    return forms['other'] == null ? null : forms;
  }

  /// Index of [code]'s strings in [byLanguage] using contract matching, or `null`.
  static String? matchIn(String? code, Map<String, Map<String, Value>> byLanguage) =>
      code == null ? null : matchLanguage(code, byLanguage.keys.toList());
}
