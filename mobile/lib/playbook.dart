import 'models.dart';
import 'playbook_rules.g.dart';

// This interpreter mirrors Rust; rule thresholds and text have one JSON source.
Map<String, dynamic> lineupPlan(
  Draft draft,
  Catalog catalog,
  String side,
  String language,
) {
  final mm = language == 'mm';
  final own = draft
      .side(side)
      .picks
      .map(catalog.hero)
      .whereType<HeroProfile>()
      .toList();
  final enemy = draft
      .enemy(side)
      .picks
      .map(catalog.hero)
      .whereType<HeroProfile>()
      .toList();
  final metrics = <String, int>{
    'own_picks': own.length,
    'enemy_picks': enemy.length,
    'missing_picks': 10 - own.length - enemy.length,
  };
  final tokens = metrics.map((key, value) => MapEntry(key, '$value'));
  final fallback = mm ? 'မသတ်မှတ်ရသေး' : 'none identified yet';
  for (final entry in {'own': own, 'enemy': enemy}.entries) {
    for (final kind in [
      'all',
      'frontline',
      'control',
      'peel',
      'dps',
      'poke',
      'pick',
      'burst',
      'dive',
      'sustain',
      'antidash',
      'suppress',
    ]) {
      final group = entry.value
          .where(
            (h) => switch (kind) {
              'all' => true,
              'frontline' => h.frontline,
              'control' => h.has('cc') || h.has('suppress'),
              'peel' => h.has('peel') || h.has('antidash') || h.has('cc'),
              'sustain' => h.has('sustain') || h.has('heal'),
              _ => h.has(kind),
            },
          )
          .toList();
      final key = '${entry.key}_$kind';
      metrics[key] = group.length;
      tokens[key] = group.isEmpty
          ? fallback
          : group.map((h) => h.name).join(', ');
    }
  }
  for (var i = 0; i < roles.length; i++) {
    tokens[roles[i].toLowerCase()] =
        catalog.hero(draft.side(side).picks[i])?.name ?? fallback;
  }
  bool matches(dynamic rule) => (rule['when'] as List).every((condition) {
    final n = metrics[condition['metric']];
    return n != null &&
        n >= (condition['min'] as int) &&
        (condition['max'] == null || n <= (condition['max'] as int));
  });
  String render(dynamic localized) {
    var result = localized[mm ? 'mm' : 'en'] as String;
    for (final entry in tokens.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }

  Map<String, String> card(dynamic c) => {
    'title': render(c['title']),
    'body': render(c['body']),
  };
  final style = (playbookRules['styles'] as List).firstWhere(matches);
  final cards = (style['cards'] as List).map(card).toList();
  if (own.isNotEmpty) {
    cards.addAll((playbookRules['common'] as List).map(card));
    for (final rule in playbookRules['context'] as List) {
      if (matches(rule)) cards.addAll((rule['cards'] as List).map(card));
    }
  }
  return {
    'strategy_id': '${playbookRules['version']}:${style['id']}',
    'plan': cards,
  };
}
