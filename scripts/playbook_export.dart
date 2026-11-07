// Run from the repository root: dart scripts/playbook_export.dart
import 'dart:convert';
import 'dart:io';

import '../mobile/lib/models.dart';
import '../mobile/lib/playbook.dart';

void main() {
  final catalog = Catalog.fromJson(
    jsonDecode(File('data/catalog.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final cases =
      jsonDecode(File('data/fixtures/playbook_cases.json').readAsStringSync())
          as List;
  final output = <Map<String, dynamic>>[];
  for (final c in cases) {
    final draft = Draft.fromJson(Map<String, dynamic>.from(c['draft'] as Map));
    for (final language in ['en', 'mm']) {
      final result = lineupPlan(draft, catalog, c['side'] as String, language);
      if (result['strategy_id'] != c['strategy_id']) {
        throw StateError(
          'Unexpected strategy for ${c['id']}: ${result['strategy_id']}',
        );
      }
      final text = jsonEncode(result['plan']);
      for (final name in c['required'] as List) {
        if (!text.contains(name as String))
          throw StateError('${c['id']} missing $name');
      }
      for (final card in result['plan'] as List) {
        if ((card['title'] as String).contains('{') ||
            (card['body'] as String).contains('{')) {
          throw StateError('Unresolved template in ${c['id']}');
        }
      }
      output.add({'id': c['id'], 'language': language, ...result});
    }
  }
  stdout.writeln(jsonEncode(output));
}
