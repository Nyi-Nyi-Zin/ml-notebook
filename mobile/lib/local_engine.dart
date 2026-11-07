import 'models.dart';

// Deliberately small offline companion. Rust is authoritative when connected.
// Exact draft scoring is a coaching heuristic, never a win probability.
Map<String, dynamic> localAnalysis(
  Draft draft,
  Catalog catalog,
  String side,
  int roleIndex,
  String priority,
  String language,
) {
  draft.validate(catalog);
  if (roleIndex < 0 || roleIndex >= 5) {
    throw const FormatException('Invalid role.');
  }
  final mm = language == 'mm';
  String t(String en, String my) => mm ? my : en;
  final own = draft
      .side(side)
      .picks
      .map(catalog.hero)
      .whereType<HeroProfile>()
      .toList();
  final enemies = draft
      .enemy(side)
      .picks
      .map(catalog.hero)
      .whereType<HeroProfile>()
      .toList();
  final focus = catalog.hero(draft.side(side).picks[roleIndex]);
  int count(List<HeroProfile> hs, String tag) =>
      hs.where((h) => h.has(tag)).length;
  Map<String, int> counts(List<HeroProfile> hs) => {
    'frontline': hs.where((h) => h.frontline).length,
    'control': hs.where((h) => h.has('cc') || h.has('suppress')).length,
    'dive': count(hs, 'dive'),
    'burst': count(hs, 'burst'),
    'sustain': hs.where((h) => h.has('heal') || h.has('sustain')).length,
    'physical': hs
        .where((h) => ['physical', 'mixed'].contains(h.damage))
        .length,
    'magic': hs.where((h) => ['magic', 'mixed'].contains(h.damage)).length,
  };
  final ec = counts(enemies);
  final otherFront = own.where((h) => h.id != focus?.id && h.frontline).length;
  final suppress = enemies.any((h) => h.has('suppress'));
  Map<String, dynamic>? emblem;
  if (focus != null) {
    var base = 'Tank',
        one = 'Agility',
        two = 'Tenacity',
        three = 'Brave Smite',
        spell = 'Flicker';
    var reason = t(
      'Keep frontline durability and mobility.',
      'Frontline ခံနိုင်ရည်နဲ့ movement ကို ဦးစားပေးထားတယ်။',
    );
    if (roleIndex == 0) {
      final healer =
          (focus.has('heal') || focus.has('support')) && !focus.has('tank');
      final damage = focus.has('assassin') || focus.id == 'selena';
      final durable =
          priority == 'survival' ||
          priority == 'balanced' && (otherFront == 0 || ec['burst']! >= 3);
      base = healer
          ? 'Support'
          : damage
          ? (focus.damage == 'magic' ? 'Mage' : 'Assassin')
          : 'Tank';
      two = healer || damage || !durable
          ? 'Pull Yourself Together'
          : 'Tenacity';
      three = healer
          ? 'Focusing Mark'
          : damage
          ? 'Lethal Ignition'
          : focus.has('heal') || focus.has('sustain')
          ? 'Brave Smite'
          : 'Concussive Blast';
      if (damage && focus.id == 'natalia') spell = 'Execute';
      reason = healer
          ? t(
              'Utility and skill uptime fit this profile. Scout with cover.',
              'Utility နဲ့ skill uptime ကို ဦးစားပေးပါ။ Information ယူချိန် teammate cover လိုတယ်။',
            )
          : damage
          ? t(
              'Find isolated targets; confirm who holds space.',
              'လူခွဲနေတဲ့ target ကိုရှာပြီး နေရာထိန်းပေးမယ့်သူကို သတ်မှတ်ပါ။',
            )
          : durable
          ? t(
              'You hold the main frontline, face several burst profiles, or chose Survival. Keep Agility while investing in durability.',
              'Main frontline ဖြစ်တာ၊ enemy burst များတာ သို့မဟုတ် Survival ရွေးထားလို့ Agility နဲ့ ခံနိုင်ရည်ကို တွဲယူထားတယ်။',
            )
          : t(
              'Another ally can share space, or Tempo was selected. Keep Tank and Agility, then invest in battle-spell availability.',
              'Frontline တာဝန်ခွဲနိုင်တဲ့ ally ရှိတာ သို့မဟုတ် Tempo ရွေးထားလို့ Tank နဲ့ Agility ထားပြီး Battle Spell uptime ကို ဖြည့်ထားတယ်။',
            );
    } else if (roleIndex == 1) {
      base = focus.has('tank')
          ? 'Tank'
          : focus.damage == 'magic'
          ? 'Mage'
          : focus.has('sustain')
          ? 'Fighter'
          : 'Assassin';
      two = 'Seasoned Hunter';
      three = focus.has('tank')
          ? 'Concussive Blast'
          : focus.damage == 'magic'
          ? 'Lethal Ignition'
          : focus.has('sustain')
          ? 'Brave Smite'
          : 'Killing Spree';
      spell = 'Retribution';
      reason = t(
        'Retribution matches the Jungle role. Verify clear speed and current talent interactions.',
        'Jungle တာဝန်အတွက် Retribution ယူမယ်။ Clear speed နဲ့ talent interaction ကို ပြန်စစ်ပါ။',
      );
    } else if (roleIndex == 2) {
      base = focus.damage == 'physical' ? 'Assassin' : 'Mage';
      two = 'Bargain Hunter';
      three = focus.has('poke') ? 'Impure Rage' : 'Lethal Ignition';
      spell = ec['control']! >= 3 && !suppress ? 'Purify' : 'Flicker';
      reason = t(
        'Prioritize wave access and safe rotation.',
        'Wave ရှင်းနိုင်မှုနဲ့ လုံခြုံတဲ့ rotation ကို ဦးစားပေးပါ။',
      );
    } else if (roleIndex == 3) {
      base = focus.has('tank')
          ? 'Tank'
          : focus.id == 'esmeralda'
          ? 'Support'
          : focus.damage == 'magic'
          ? 'Mage'
          : focus.has('assassin')
          ? 'Assassin'
          : 'Fighter';
      three = focus.has('sustain')
          ? 'Brave Smite'
          : focus.damage == 'magic'
          ? 'Lethal Ignition'
          : focus.has('basic')
          ? 'Quantum Charge'
          : 'War Cry';
      spell = ec['control']! >= 3 && !suppress
          ? 'Purify'
          : focus.has('sustain')
          ? 'Vengeance'
          : 'Flicker';
      reason = t(
        'Hold the side wave and arrive with enough HP for a second angle.',
        'Side wave ကိုထိန်းပြီး ဒုတိယ angle က pressure ပေးနိုင်အောင် HP ထိန်းလာပါ။',
      );
    } else {
      base = focus.damage == 'magic' ? 'Mage' : 'Marksman';
      two = focus.damage == 'magic' ? 'Bargain Hunter' : 'Weapon Master';
      three = focus.has('basic') ? 'Quantum Charge' : 'Lethal Ignition';
      spell = ec['control']! >= 3 && !suppress ? 'Purify' : 'Flicker';
      reason = t(
        'Preserve safe damage uptime and plan around enemy access.',
        'Damage ပေးနိုင်တဲ့အချိန်ကို ထိန်းပြီး enemy ဝင်လာမယ့်လမ်းကို စဉ်းစားပါ။',
      );
    }
    emblem = {
      'base': base,
      'talents': [one, two, three],
      'spell': spell,
      'reason': reason,
      'tradeoff': base == 'Tank'
          ? t(
              'Tank gives up Support healing, skill cooldown and base movement benefits. Agility only partly offsets the mobility trade-off.',
              'Tank ယူရင် Support ရဲ့ healing၊ skill cooldown နဲ့ base movement benefit တွေကို စွန့်ရတယ်။ Agility က movement trade-off ကို တစ်စိတ်တစ်ပိုင်းပဲ ဖြည့်ပေးတယ်။',
            )
          : t(
              'A starting role template, not an optimal build. Check hero mechanics and current patch effects.',
              'အခြေခံ role template ဖြစ်လို့ hero mechanics နဲ့ current patch effects ကို ပြန်စစ်ပါ။',
            ),
      'alternative': two == 'Tenacity'
          ? t(
              'If durability is sufficient, consider Pull Yourself Together for Flicker uptime.',
              'ခံနိုင်ရည်လုံလောက်ရင် Flicker uptime အတွက် Pull Yourself Together ပြောင်းစဉ်းစားပါ။',
            )
          : t(
              'If you cannot survive the first damage wave, consider more durability.',
              'ပထမ damage wave မခံနိုင်ရင် ခံနိုင်ရည် ထပ်ဖြည့်ဖို့ စဉ်းစားပါ။',
            ),
      'specificity': focus.id == 'minotaur'
          ? 'scenario_rules'
          : 'role_template',
    };
  }
  Map<String, String> p(
    String title,
    String myTitle,
    String body,
    String myBody,
  ) => {'title': t(title, myTitle), 'body': t(body, myBody)};
  final threats = <Map<String, String>>[];
  if (focus != null && !focus.roles.contains(roles[roleIndex])) {
    threats.add(
      p(
        'Off-lane selection',
        'Lane မကိုက်တဲ့ pick',
        "This hero is outside the catalog's suggested lanes. Confirm a practiced flex; the emblem is only a starting profile.",
        'ဒီ hero က သတ်မှတ်ထားတဲ့ lane မဟုတ်လို့ လေ့ကျင့်ထားတဲ့ flex ဟုတ်မဟုတ် စစ်ပါ။ Emblem က အခြေခံအကြံပြုချက်ပါ။',
      ),
    );
  }
  if (enemies.any((h) => h.has('truedmg'))) {
    threats.add(
      p(
        'True-damage triggers',
        'True damage ကို သတိထား',
        'Track the specific true-damage trigger. Armor and magic defense alone do not answer it; use spacing, HP and deny repeated hits.',
        'True damage ထွက်စေတဲ့ trigger ကို စောင့်ကြည့်ပါ။ Armor နဲ့ magic defense တင်မလုံလောက်လို့ spacing၊ HP နဲ့ အကြိမ်ကြိမ်ထိတာကို ရှောင်ပါ။',
      ),
    );
  }
  if (enemies.where((h) => h.has('basic') && h.has('dps')).length >= 2) {
    threats.add(
      p(
        'Basic-attack uptime',
        'Basic attack ပေးခွင့် မပေးပါနဲ့',
        'Avoid extended open contact with multiple basic-attack carries. Break line of sight and coordinate control before they free-hit.',
        'Basic attack carry များနေရင် အချိန်ကြာကြာ ပစ်ခွင့်မပေးပါနဲ့။ မြင်ကွင်းဖြတ်ပြီး CC နဲ့ teammate ကို ညှိပါ။',
      ),
    );
  }
  if (enemies.any((h) => h.id == 'yin')) {
    threats.add(
      p(
        'Respect isolation',
        'တစ်ယောက်တည်း မခွဲနေပါနဲ့',
        'Keep vision before approaching Yin and track his isolation ultimate. Plan survival without assuming outside ally support can reach you.',
        'Yin အနားဝင်ရင် vision နဲ့ ultimate ကို စစ်ပါ။ Team အကူအညီ အမြဲမီမယ်လို့ မယူဘဲ အသက်ရှင်ဖို့ ပြင်ထားပါ။',
      ),
    );
  }
  if (enemies.any((h) => h.id == 'marcel')) {
    threats.add(
      p(
        "Marcel's control field",
        'Marcel ရဲ့ control area',
        "Avoid committing the whole team into Marcel's control area. Keep an exit and check the actual skill state before following an engage.",
        'Marcel ရဲ့ control area ထဲ team အကုန်မဝင်ပါနဲ့။ ထွက်လမ်းထားပြီး skill အခြေအနေကို စစ်ပြီးမှ follow-up လုပ်ပါ။',
      ),
    );
  }

  if (suppress) {
    threats.add(
      p(
        'Suppression access',
        'Suppression ကို သတိထား',
        'Purify cannot remove suppression. Track the carrier’s position and cooldown.',
        'Purify နဲ့ suppression ကို မဖြေနိုင်ဘူး။ Enemy position နဲ့ cooldown ကို စောင့်ကြည့်ပါ။',
      ),
    );
  }
  if (ec['dive']! > 0) {
    threats.add(
      p(
        'Protect the second angle',
        'ဒုတိယ angle ကို ကာကွယ်ပါ',
        'Keep one control tool for enemy dive when your carry can be reached.',
        'Enemy dive ဝင်နိုင်ရင် carry အတွက် CC တစ်ခု ချန်ထားပါ။',
      ),
    );
  }
  if (ec['burst']! >= 2) {
    threats.add(
      p(
        'First damage wave',
        'ပထမ damage wave',
        'Scout with cover and an exit. Keep enough HP to finish your CC sequence.',
        'Teammate cover နဲ့ ထွက်လမ်းရှိမှ information ယူပါ။ CC ပြီးအောင် သုံးနိုင်ဖို့ HP ထိန်းပါ။',
      ),
    );
  }
  if (ec['sustain']! >= 2) {
    threats.add(
      p(
        'Assign anti-heal coverage',
        'Anti-heal တာဝန်ခွဲပါ',
        'Name the anti-heal carrier and confirm application uptime.',
        'Anti-heal ကို ဘယ်သူယူပြီး ဘယ်လို apply လုပ်မလဲ သတ်မှတ်ပါ။',
      ),
    );
  }
  if (enemies.any((h) => h.has('antidash')) && focus?.has('dive') == true) {
    threats.add(
      p(
        'Anti-dash control',
        'Anti-dash skill ကို စောင့်ပါ',
        'Wait for the relevant control before committing mobility.',
        'Anti-dash skill ထွက်သွားမှ mobility နဲ့ ဝင်ပါ။',
      ),
    );
  }
  if (focus?.id == 'minotaur' && enemies.any((h) => h.id == 'valentina')) {
    threats.add(
      p(
        'Track copied ultimate',
        'Copy လုပ်ထားတဲ့ ultimate ကို စောင့်ကြည့်ပါ',
        'Avoid giving Valentina a grouped counter-engage after your own initiation.',
        'Valentina ကို team အကုန်ကပ်ပြီး counter-engage လုပ်ခွင့်မပေးပါနဲ့။',
      ),
    );
  }
  final plan = [
    p(
      'Opening · earn the first move',
      'အစပိုင်း · rotation အရင်ရအောင်',
      'Coordinate mid and jungle clear. Scout with a purpose, cover and an exit.',
      'Mid နဲ့ Jungle clear အချိန်ကို ညှိပါ။ ရည်ရွယ်ချက်၊ teammate cover နဲ့ ထွက်လမ်းရှိမှ information ယူပါ။',
    ),
    p(
      'Objective · control an entrance',
      'Objective · entrance တစ်ခုကို ထိန်းပါ',
      'Prepare nearby waves, control an entrance and assign who zones the jungler. Reassess if a side-laner cannot join.',
      'အနီးက wave ကိုပြင်ပါ။ Entrance ထိန်းသူနဲ့ enemy jungler ကို တားမယ့်သူ သတ်မှတ်ပါ။ Side laner မလာနိုင်ရင် ပြန်စဉ်းစားပါ။',
    ),
    focus?.id == 'minotaur' && own.any((h) => h.id == 'esmeralda')
        ? p(
            'Teamfight · divide the jobs',
            'Teamfight · တာဝန်ခွဲထားပါ',
            'Esme pressures another angle. Minotaur follows with control or peels. The assassin commits after key enemy control is used.',
            'Esme က ဒုတိယ angle က pressure ပေးပါ။ Minotaur က follow-up CC သို့မဟုတ် peel လုပ်ပါ။ Assassin က အရေးကြီး enemy CC ထွက်ပြီးမှ ဝင်ပါ။',
          )
        : p(
            'Teamfight · name the target',
            'Teamfight · target ကို သတ်မှတ်ပါ',
            'Name the first target and confirm follow-up range. Keep peel if the carry is exposed.',
            'ပထမ target နဲ့ teammate လိုက်မီတဲ့ range ကို သတ်မှတ်ပါ။ Carry အတွက် လိုရင် peel ချန်ထားပါ။',
          ),
  ];
  final remaining = own.where((h) => h.id != focus?.id).toList();
  final rc = counts(remaining);
  final candidates =
      catalog.heroes
          .where(
            (h) =>
                !draft.used.contains(h.id) &&
                h.roles.contains(roles[roleIndex]),
          )
          .map((h) {
            var score = 0;
            final reasons = <String>[];
            void add(int n, String en, String my) {
              score += n;
              reasons.add(t(en, my));
            }

            h.roles.contains(roles[roleIndex])
                ? add(5, 'Fits this role', 'ဒီ role နဲ့ ကိုက်တယ်')
                : add(
                    -4,
                    'Off-role: confirm a practiced flex',
                    'လေ့ကျင့်ထားတဲ့ flex ဟုတ်မဟုတ် စစ်ပါ',
                  );
            if (rc['frontline'] == 0 && h.frontline) {
              add(3, 'Adds a frontline', 'Frontline ဖြည့်ပေးတယ်');
            }
            if (rc['control'] == 0 && (h.has('cc') || h.has('suppress'))) {
              add(2, 'Adds control', 'Control ဖြည့်ပေးတယ်');
            }
            if (rc['magic'] == 0 && ['magic', 'mixed'].contains(h.damage)) {
              add(1, 'Adds magic damage', 'Magic damage ဖြည့်ပေးတယ်');
            }
            if (ec['dive']! >= 2 && (h.has('peel') || h.has('antidash'))) {
              add(2, 'Helps against dive', 'Enemy dive ကို ကာကွယ်ဖို့ ကူညီတယ်');
            }
            if (ec['sustain']! >= 2 && h.has('antiheal')) {
              add(2, 'Pressures sustain', 'Enemy sustain ကို ဖိအားပေးနိုင်တယ်');
            }
            return {'hero_id': h.id, 'score': score, 'reasons': reasons};
          })
          .toList()
        ..sort((a, b) {
          final n = (b['score'] as int).compareTo(a['score'] as int);
          return n != 0
              ? n
              : (a['hero_id'] as String).compareTo(b['hero_id'] as String);
        });
  return {
    'rules_version': 'offline-rules-2',
    'patch': catalog.patch,
    'partial': own.length < 5 || enemies.length < 5,
    'own': counts(own),
    'enemy': ec,
    'focus': focus == null ? null : {'id': focus.id, 'name': focus.name},
    'emblem': emblem,
    'threats': threats,
    'plan': plan,
    'candidates': candidates.take(8).toList(),
  };
}
