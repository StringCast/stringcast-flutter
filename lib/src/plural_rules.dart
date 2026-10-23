import 'language.dart';

/// CLDR plural categories (contract §2).
const pluralCategories = ['zero', 'one', 'two', 'few', 'many', 'other'];

const _noPlural = {
  'ja', 'zh', 'ko', 'th', 'vi', 'id', 'ms', 'lo', 'my', 'km', 'yue', 'jv', 'su', 'bo', 'dz', 'ig', 'yo', 'sg', 'to', //
};
// `one` for 0 and 1.
const _zeroOneIsOne = {'hi', 'bn', 'fa', 'gu', 'kn', 'mr', 'zu', 'am', 'as'};
const _eastSlavic = {'ru', 'uk', 'be'};
const _southSlavic = {'hr', 'sr', 'bs', 'sh'};
const _romanceMillion = {'es', 'it', 'ca'};

bool _within(int v, int lo, int hi) => v >= lo && v <= hi;

/// CLDR cardinal plural category for an integer [count] in [language]. Same table as the iOS and
/// Android SDKs; unknown languages use the English `one`/`other` rule.
String pluralCategory(int count, String? language) {
  final tag = normalizeTag(language ?? 'en');
  final lang = tag.split('-').first;
  final n = count.abs();
  final mod10 = n % 10;
  final mod100 = n % 100;

  if (_noPlural.contains(lang)) return 'other';
  if (lang == 'fr') {
    if (n <= 1) return 'one';
    if (n % 1000000 == 0) return 'many';
    return 'other';
  }
  if (lang == 'pt') {
    if (tag == 'pt-pt' ? n == 1 : n <= 1) return 'one';
    if (n != 0 && n % 1000000 == 0) return 'many';
    return 'other';
  }
  if (_romanceMillion.contains(lang)) {
    if (n == 1) return 'one';
    if (n != 0 && n % 1000000 == 0) return 'many';
    return 'other';
  }
  if (_zeroOneIsOne.contains(lang)) return n <= 1 ? 'one' : 'other';
  if (_eastSlavic.contains(lang) || _southSlavic.contains(lang)) {
    if (mod10 == 1 && mod100 != 11) return 'one';
    if (_within(mod10, 2, 4) && !_within(mod100, 12, 14)) return 'few';
    return _eastSlavic.contains(lang) ? 'many' : 'other';
  }
  switch (lang) {
    case 'pl':
      if (n == 1) return 'one';
      if (_within(mod10, 2, 4) && !_within(mod100, 12, 14)) return 'few';
      return 'many';
    case 'cs' || 'sk':
      if (n == 1) return 'one';
      if (_within(n, 2, 4)) return 'few';
      return 'other';
    case 'ar':
      if (n == 0) return 'zero';
      if (n == 1) return 'one';
      if (n == 2) return 'two';
      if (_within(mod100, 3, 10)) return 'few';
      if (_within(mod100, 11, 99)) return 'many';
      return 'other';
    case 'he' || 'iw':
      if (n == 1) return 'one';
      if (n == 2) return 'two';
      return 'other';
    case 'ro' || 'mo':
      if (n == 1) return 'one';
      if (n == 0 || _within(mod100, 2, 19)) return 'few';
      return 'other';
    case 'lt':
      if (mod10 == 1 && !_within(mod100, 11, 19)) return 'one';
      if (_within(mod10, 2, 9) && !_within(mod100, 11, 19)) return 'few';
      return 'other';
    case 'lv':
      if (mod10 == 0 || _within(mod100, 11, 19)) return 'zero';
      if (mod10 == 1 && mod100 != 11) return 'one';
      return 'other';
    case 'sl':
      if (mod100 == 1) return 'one';
      if (mod100 == 2) return 'two';
      if (_within(mod100, 3, 4)) return 'few';
      return 'other';
    case 'ga':
      if (n == 1) return 'one';
      if (n == 2) return 'two';
      if (_within(n, 3, 6)) return 'few';
      if (_within(n, 7, 10)) return 'many';
      return 'other';
    case 'cy':
      return switch (n) { 0 => 'zero', 1 => 'one', 2 => 'two', 3 => 'few', 6 => 'many', _ => 'other' };
    case 'is' || 'mk':
      return (mod10 == 1 && mod100 != 11) ? 'one' : 'other';
    default:
      return n == 1 ? 'one' : 'other';
  }
}

/// Pick the form of a plural map for [count]. An explicit `zero` form wins for 0 (Android/iOS
/// convention); a missing category falls back to `other`, then `one`, then any form.
String? selectPlural(Map<String, String> forms, int count, String? language) {
  if (count == 0 && forms['zero'] != null) return forms['zero'];
  return forms[pluralCategory(count, language)] ?? forms['other'] ?? forms['one'] ?? forms.values.firstOrNull;
}
