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
  test(
    'all 133 heroes work in each suggested lane in both engines languages',
    () {
      expect(catalog.heroes.length, 133);
      expect(catalog.heroes.map((h) => h.id).toSet().length, 133);
      for (final hero in catalog.heroes) {
        for (final lane in hero.roles) {
          final role = roles.indexOf(lane);
          for (final language in ['en', 'mm']) {
            final draft = Draft.empty(catalog.id);
            draft.blue.picks[role] = hero.id;
            final analysis = localAnalysis(
              draft,
              catalog,
              'blue',
              role,
              'balanced',
              language,
            );
            expect(
              analysis['emblem'],
              isNotNull,
              reason: '${hero.id} in $lane',
            );
            expect(
              (analysis['candidates'] as List).every(
                (candidate) =>
                    catalog.hero(candidate['hero_id'])!.roles.contains(lane),
              ),
              isTrue,
            );
            if (role == 1) expect(analysis['emblem']['spell'], 'Retribution');
          }
        }
      }
    },
  );
  test(
    'magical jungle and non-healing support emblem profiles are respected',
    () {
      for (final entry in [
        ('harley', 1, 'Mage'),
        ('marcel', 0, 'Support'),
        ('gloo', 0, 'Tank'),
        ('hirara', 1, 'Assassin'),
        ('obsidia', 4, 'Marksman'),
      ]) {
        final draft = Draft.empty(catalog.id);
        draft.blue.picks[entry.$2] = entry.$1;
        expect(
          localAnalysis(
            draft,
            catalog,
            'blue',
            entry.$2,
            'balanced',
            'en',
          )['emblem']['base'],
          entry.$3,
        );
      }
      final draft = Draft.empty(catalog.id)..blue.picks[3] = 'esmeralda';
      final counts = localAnalysis(
        draft,
        catalog,
        'blue',
        3,
        'balanced',
        'en',
      )['own'];
      expect(counts['physical'], 1);
      expect(counts['magic'], 1);
    },
  );
}
