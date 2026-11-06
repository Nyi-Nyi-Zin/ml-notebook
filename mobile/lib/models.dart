import 'dart:convert';

const roles = ['Roam', 'Jungle', 'Mid', 'EXP', 'Gold'];

class HeroProfile {
  final String id, name, damage;
  final List<String> roles, tags;
  HeroProfile.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      name = j['name'] as String,
      damage = j['damage'] as String,
      roles = List<String>.from(j['roles'] as List),
      tags = List<String>.from(j['tags'] as List);
  bool has(String tag) => tags.contains(tag);
  bool get frontline => has('tank') || has('frontline');
}

class Catalog {
  final Map<String, dynamic> patch;
  final List<HeroProfile> heroes;
  final Map<String, dynamic> json;
  Catalog.fromJson(Map<String, dynamic> j)
    : patch = Map<String, dynamic>.from(j['patch'] as Map),
      heroes = (j['heroes'] as List)
          .map((h) => HeroProfile.fromJson(Map<String, dynamic>.from(h as Map)))
          .toList(),
      json = j;
  String get id => patch['id'] as String;
  HeroProfile? hero(String? id) {
    if (id == null) return null;
    for (final h in heroes) {
      if (h.id == id) return h;
    }
    return null;
  }
}

class Lineup {
  String name;
  List<String?> picks, bans;
  Lineup(this.name, {List<String?>? picks, List<String?>? bans})
    : picks = picks ?? List<String?>.filled(5, null),
      bans = bans ?? List<String?>.filled(5, null);
  factory Lineup.fromJson(Map<String, dynamic> j) {
    final picks = List<String?>.from(j['picks'] as List);
    final bans = List<String?>.from(j['bans'] as List);
    if (picks.length != 5 || bans.length != 5) {
      throw const FormatException('Each side needs five picks and five bans.');
    }
    return Lineup(j['name'] as String, picks: picks, bans: bans);
  }
  Map<String, dynamic> toJson() => {'name': name, 'picks': picks, 'bans': bans};
}

class Draft {
  String title, patchId, notes;
  Lineup blue, red;
  Draft({
    required this.title,
    required this.patchId,
    required this.blue,
    required this.red,
    this.notes = '',
  });
  factory Draft.empty(String patchId) => Draft(
    title: 'Untitled scrim',
    patchId: patchId,
    blue: Lineup('Our team'),
    red: Lineup('Opponent'),
  );
  factory Draft.sample(String patchId) => Draft(
    title: 'Mino + Esme · scrim preparation',
    patchId: patchId,
    blue: Lineup(
      'Our team',
      picks: ['minotaur', 'ling', 'lylia', 'esmeralda', 'claude'],
      bans: ['fanny', 'diggie', null, null, null],
    ),
    red: Lineup(
      'Opponent',
      picks: ['khufra', 'hayabusa', 'valentina', 'terizla', 'brody'],
      bans: ['joy', 'chip', null, null, null],
    ),
    notes:
        'Win condition: Esme creates a second angle; Minotaur controls the opening.\nAssassin commits after key enemy control is used.',
  );
  factory Draft.fromJson(Map<String, dynamic> j) => Draft(
    title: j['title'] as String,
    patchId: j['patch_id'] as String,
    blue: Lineup.fromJson(Map<String, dynamic>.from(j['blue'] as Map)),
    red: Lineup.fromJson(Map<String, dynamic>.from(j['red'] as Map)),
    notes: j['notes'] as String? ?? '',
  );
  Lineup side(String side) => side == 'blue' ? blue : red;
  Lineup enemy(String side) => side == 'blue' ? red : blue;
  List<String> get used => [
    ...blue.picks,
    ...red.picks,
    ...blue.bans,
    ...red.bans,
  ].whereType<String>().toList();
  Map<String, dynamic> toJson() => {
    'title': title,
    'patch_id': patchId,
    'blue': blue.toJson(),
    'red': red.toJson(),
    'notes': notes,
  };
  Draft copy() =>
      Draft.fromJson(jsonDecode(jsonEncode(toJson())) as Map<String, dynamic>);
  void validate(Catalog catalog) {
    if (patchId != catalog.id) {
      throw const FormatException('This draft uses a different catalog patch.');
    }
    if (title.trim().isEmpty || title.runes.length > 100) {
      throw const FormatException('Title must be 1–100 characters.');
    }
    if (notes.runes.length > 12000) {
      throw const FormatException('Notes are too long.');
    }
    for (final s in [blue, red]) {
      if (s.name.trim().isEmpty || s.name.runes.length > 32) {
        throw const FormatException('Team names must be 1–32 characters.');
      }
      if (s.picks.length != 5 || s.bans.length != 5) {
        throw const FormatException(
          'Each side needs five picks and five bans.',
        );
      }
    }
    if (used.toSet().length != used.length) {
      throw const FormatException('A hero is already picked or banned.');
    }
    if (used.any((id) => catalog.hero(id) == null)) {
      throw const FormatException('Unknown hero in this draft.');
    }
  }
}

class DraftRecord {
  final String id, ownerId, updatedAt;
  final String? teamId;
  final Draft draft;
  final int revision;
  final bool canEdit, archived;
  DraftRecord.fromJson(Map<String, dynamic> j)
    : id = j['id'] as String,
      ownerId = j['owner_id'] as String,
      teamId = j['team_id'] as String?,
      updatedAt = j['updated_at'] as String,
      draft = Draft.fromJson(Map<String, dynamic>.from(j['draft'] as Map)),
      revision = j['revision'] as int,
      canEdit = j['can_edit'] as bool,
      archived = j['archived'] as bool;
}
