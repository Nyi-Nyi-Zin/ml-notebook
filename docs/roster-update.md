# 133-hero roster update — 7 November 2026

## Coverage and source scope

The current catalog contains 133 unique Original Server heroes. The versioned
manifest in `data/roster-133-manifest.json` records all names and the 29 additions.
The backend seed and bundled offline catalog are identical. Suggested lanes
(Roam/Jungle/Mid/EXP/Gold) are coaching eligibility, distinct from the game's
six hero classes. They are not live pick-rate or tier-list rankings.

Sources checked:

- Official hero directory: https://www.mobilelegends.com/hero/list
- Official hero profiles: https://www.mobilelegends.com/hero/detail?heroid=133
  and https://www.mobilelegends.com/hero/detail?heroid=132
- Cross-check of all names: https://mlbbhub.com/heroes
- Talent reference: https://liquipedia.net/mobilelegends/Portal:Emblems

The official directory is JavaScript-rendered and its directly retrieved page
only returned a loading shell. Indexed official skill descriptions supported
the new-hero mechanism checks; the complete name list was cross-checked with
the community directory and the supplied 133-hero count. Skill-derived tags,
suggested lanes and emblem choices are conservative coaching interpretations.
No current damage coefficients, cooldown numbers, win rates or exhaustive
pairwise counters are claimed. `patch.reviewed` remains false for that reason.

## Behavior changes

- Add Aldous, Alice, Alucard, Argus, Aulus, Badang, Balmond, Bane, Freya,
  Gloo, Gord, Hanzo, Harley, Hilda, Hirara, Johnson, Kalea, Khaleed,
  Leomord, Lukas, Marcel, Masha, Obsidia, Saber, Sora, Vale, Yin, Zetian and Zilong.
- Use Mage bases for magical junglers and Support bases for utility roamers
  such as Marcel; retain Retribution for every jungle profile.
- Refine EXP and magical Gold emblem templates using hero damage/utility.
- Treat mixed damage as present in both physical and magic composition counts.
  The counts indicate available damage profiles, not damage proportions.
- Limit automatic pick suggestions to eligible lanes and exclude all picks
  and bans. Manual flex picks remain possible with an off-lane warning.
- Add true-damage and basic-attack pressure prompts plus Yin isolation and
  Marcel control-area prompts. These are situational checks, not guaranteed counters.
- Keep the historical baseline immutable. New installs seed both versions.
  Existing baseline local caches upgrade without losing picks, bans or notes.
  Previously saved server drafts keep their original catalog.
- Upgrade a working copy to the latest server catalog without clearing it.
- Allow 75 seconds for catalog connection during a cold start; regular API
  calls retain their shorter timeout.

## Verification

The catalog validator checks 133 unique names/IDs, valid lanes and damage labels,
the exact roster manifest, the 29-name addition set, and byte-identical online
and offline catalogs. Rust and Dart tests exercise every hero in every suggested
lane, in English and Myanmar, including lane-specific candidate filtering and
jungle Retribution. Workspace tests cover cache migration and preserving a
working lineup during a catalog upgrade. API integration checks retain access
to the historical 104-hero baseline as well as the new roster.
