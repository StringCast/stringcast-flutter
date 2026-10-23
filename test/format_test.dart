import 'package:flutter_test/flutter_test.dart';
import 'package:stringcast/stringcast.dart';

void main() {
  test('named placeholders', () {
    expect(interpolate('Hi {name}, {{name}}!', {'name': 'Ana'}), 'Hi Ana, Ana!');
    expect(interpolate('Hi {name} {other}', {'name': 'Ana'}), 'Hi Ana {other}');
  });

  test('positional printf tokens', () {
    expect(interpolate('%s has %d items', ['Ana', 3]), 'Ana has 3 items');
    expect(interpolate('%2\$@ before %1\$s', ['a', 'b']), 'b before a');
    expect(interpolate('%.2f%%', [12.345]), '12.35%');
    expect(interpolate('%d', [2.9]), '2');
    expect(interpolate('%s %s', ['only']), 'only %s');
  });

  test('no args leaves the template untouched', () {
    expect(interpolate('100%% {x} %s', null), '100%% {x} %s');
  });

  test('plural categories', () {
    expect(pluralCategory(1, 'en'), 'one');
    expect(pluralCategory(0, 'en'), 'other');
    expect(pluralCategory(0, 'fr'), 'one');
    expect(pluralCategory(22, 'ru'), 'few');
    expect(pluralCategory(25, 'ru'), 'many');
    expect(pluralCategory(21, 'ru'), 'one');
    expect(pluralCategory(12, 'pl'), 'many');
    expect(pluralCategory(3, 'ar'), 'few');
    expect(pluralCategory(1000000, 'es'), 'many');
    expect(pluralCategory(1, 'ja'), 'other');
    expect(pluralCategory(0, 'pt-PT'), 'other');
    expect(pluralCategory(0, 'pt-BR'), 'one');
  });

  test('selectPlural: explicit zero wins for 0, missing category falls back to other', () {
    final forms = {'zero': 'none', 'one': 'one item', 'other': 'many items'};
    expect(selectPlural(forms, 0, 'en'), 'none');
    expect(selectPlural(forms, 1, 'en'), 'one item');
    expect(selectPlural({'one': 'x', 'other': 'y'}, 3, 'ru'), 'y');
  });
}
