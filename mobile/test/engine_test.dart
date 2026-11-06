import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:draftroom/models.dart';
import 'package:draftroom/local_engine.dart';

void main() {
  final catalog = Catalog.fromJson(
    jsonDecode(File('assets/catalog.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  test('frontline and burst change the emblem trade-off', () {
    final d = Draft.sample(catalog.id);
    expect(
      localAnalysis(
        d,
        catalog,
        'blue',
        0,
        'balanced',
        'en',
      )['emblem']['talents'][1],
      'Pull Yourself Together',
    );
    d.blue.picks[3] = null;
    expect(
      localAnalysis(
        d,
        catalog,
        'blue',
        0,
        'balanced',
        'en',
      )['emblem']['talents'][1],
      'Tenacity',
    );
    expect(
      localAnalysis(
        d,
        catalog,
        'blue',
        0,
        'tempo',
        'en',
      )['emblem']['talents'][1],
      'Pull Yourself Together',
    );
    d.blue.picks[3] = 'esmeralda';
    d.red.picks[2] = 'eudora';
    expect(
      localAnalysis(
        d,
        catalog,
        'blue',
        0,
        'balanced',
        'en',
      )['emblem']['talents'][1],
      'Tenacity',
    );
  });
  test('duplicate picks and bans are rejected', () {
    final d = Draft.sample(catalog.id);
    d.red.bans[2] = 'minotaur';
    expect(() => d.validate(catalog), throwsFormatException);
  });
  test('JSON roundtrip preserves notes and null slots', () {
    final d = Draft.empty(catalog.id)..notes = 'မြန်မာ coach notes';
    final restored = Draft.fromJson(
      jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>,
    );
    expect(restored.notes, d.notes);
    expect(restored.blue.picks, List.filled(5, null));
  });
  test('empty focus and suppression prompts are explicit', () {
    final d = Draft.empty(catalog.id);
    d.red.picks[0] = 'franco';
    final a = localAnalysis(d, catalog, 'blue', 0, 'balanced', 'en');
    expect(a['emblem'], isNull);
    expect(a['partial'], isTrue);
    expect(
      (a['threats'] as List).any((p) => p['body'].contains('Purify')),
      isTrue,
    );
  });
  test('jungle spell and candidate exclusions', () {
    final d = Draft.sample(catalog.id);
    final a = localAnalysis(d, catalog, 'blue', 1, 'balanced', 'en');
    expect(a['emblem']['spell'], 'Retribution');
    expect(
      (a['candidates'] as List).every((c) => !d.used.contains(c['hero_id'])),
      isTrue,
    );
  });
  test('bad imports do not truncate slots or accept unknown heroes', () {
    final j = Draft.sample(catalog.id).toJson();
    (j['blue'] as Map)['picks'] = ['minotaur'];
    expect(() => Draft.fromJson(j), throwsFormatException);
    final d = Draft.empty(catalog.id);
    d.blue.picks[0] = 'unlisted-hero';
    expect(() => d.validate(catalog), throwsFormatException);
  });
}
