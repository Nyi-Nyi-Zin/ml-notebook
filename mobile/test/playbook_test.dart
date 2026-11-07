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
  final cases =
      jsonDecode(
            File('../data/fixtures/playbook_cases.json').readAsStringSync(),
          )
          as List;
  for (final c in cases) {
    test('lineup plan: ${c['id']}, both languages and all focus slots', () {
      final draft = Draft.fromJson(
        Map<String, dynamic>.from(c['draft'] as Map),
      );
      for (final language in ['en', 'mm']) {
        String? previous;
        for (var role = 0; role < 5; role++) {
          final result = localAnalysis(
            draft,
            catalog,
            c['side'] as String,
            role,
            'balanced',
            language,
          );
          expect(result['strategy_id'], c['strategy_id']);
          final text = jsonEncode(result['plan']);
          for (final name in c['required'] as List) {
            expect(text, contains(name));
          }
          for (final card in result['plan'] as List) {
            expect(card['title'], isNot(contains('{')));
            expect(card['body'], isNot(contains('{')));
          }
          if (previous != null) expect(text, previous);
          previous = text;
        }
      }
    });
  }
}
