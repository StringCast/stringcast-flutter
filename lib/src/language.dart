/// Language resolution (contract §6.4). Pure and side-effect free.
library;

/// Normalise a language tag for comparison: `pt_BR` → `pt-br`.
String normalizeTag(String code) => code.trim().replaceAll('_', '-').toLowerCase();

/// Language subtag of a tag (`pt-BR` → `pt`).
String languageSubtag(String code) => normalizeTag(code).split('-').first;

// Regions whose Chinese script is Traditional; every other `zh-<region>` is Simplified.
const _hantRegions = {'tw', 'hk', 'mo'};

/// The script of a tag: explicit (`zh-Hant-TW` → `hant`), or the likely script for Chinese
/// (`zh-TW` → `hant`, `zh-CN` → `hans`). `null` when unknown.
String? _scriptOf(String normalized) {
  final parts = normalized.split('-');
  for (final p in parts.skip(1)) {
    if (p.length == 4 && RegExp(r'^[a-z]{4}$').hasMatch(p)) return p;
  }
  if (parts.first == 'zh') {
    final region = parts.length > 1 ? parts[1] : '';
    return _hantRegions.contains(region) ? 'hant' : 'hans';
  }
  return null;
}

/// Match one preferred tag against the project's languages: exact → language + script →
/// language only → any project language with the same language subtag. Returns the project's own
/// spelling, or `null`.
String? matchLanguage(String tag, List<String> available) {
  final wanted = normalizeTag(tag);
  if (wanted.isEmpty) return null;
  final avail = [for (final code in available) (code: code, norm: normalizeTag(code))];
  String? find(String n) {
    for (final a in avail) {
      if (a.norm == n) return a.code;
    }
    return null;
  }

  final exact = find(wanted);
  if (exact != null) return exact;

  final lang = wanted.split('-').first;
  final script = _scriptOf(wanted);
  if (script != null) {
    final withScript = find('$lang-$script');
    if (withScript != null) return withScript;
  }

  final langOnly = find(lang);
  if (langOnly != null) return langOnly;

  for (final a in avail) {
    if (a.norm.startsWith('$lang-')) return a.code;
  }
  return null;
}

/// Resolve the language to use (contract §6.4).
///
/// [override] beats everything; when it matches no project language it is returned as given (`_` → `-`)
/// and lookups fall through to the base bundle. Otherwise [preferred] is walked in order and the first
/// hit wins. Fallback: [baseLanguage] (as spelled in [available] when present).
String? resolveLanguage({
  required List<String> preferred,
  required List<String> available,
  required String? baseLanguage,
  String? override,
}) {
  final o = override?.trim();
  if (o != null && o.isNotEmpty) {
    return matchLanguage(o, available) ?? o.replaceAll('_', '-');
  }
  for (final tag in preferred) {
    final hit = matchLanguage(tag, available);
    if (hit != null) return hit;
  }
  if (baseLanguage == null) return null;
  return matchLanguage(baseLanguage, available) ?? baseLanguage;
}
