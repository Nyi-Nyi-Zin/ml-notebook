//! Deterministic lineup coaching. Both runtimes consume the same rule data.
use crate::{engine::Prompt, models::*};
use serde::Deserialize;
use std::{collections::HashMap, sync::LazyLock};

#[derive(Deserialize)]
struct Localized {
    en: String,
    mm: String,
}
#[derive(Deserialize)]
struct Card {
    title: Localized,
    body: Localized,
}
#[derive(Deserialize)]
struct Condition {
    metric: String,
    min: usize,
    max: Option<usize>,
}
#[derive(Deserialize)]
struct Rule {
    id: String,
    when: Vec<Condition>,
    cards: Vec<Card>,
}
#[derive(Deserialize)]
struct Rules {
    version: String,
    styles: Vec<Rule>,
    common: Vec<Card>,
    context: Vec<Rule>,
}
static RULES: LazyLock<Rules> = LazyLock::new(|| {
    serde_json::from_str(include_str!("../../data/playbook_rules.json"))
        .expect("embedded playbook rules must be valid")
});

fn matches(rule: &Rule, metrics: &HashMap<String, usize>) -> bool {
    rule.when.iter().all(|c| {
        metrics
            .get(&c.metric)
            .is_some_and(|&n| n >= c.min && c.max.is_none_or(|max| n <= max))
    })
}

pub fn plan(draft: &Draft, side: &Side, catalog: &Catalog, mm: bool) -> (String, Vec<Prompt>) {
    let heroes = |lineup: &Lineup| {
        lineup
            .picks
            .iter()
            .filter_map(|id| id.as_deref().and_then(|id| catalog.hero(id)))
            .collect::<Vec<_>>()
    };
    let own = heroes(draft.lineup(side));
    let enemy = heroes(draft.enemy(side));
    let mut metrics: HashMap<String, usize> = HashMap::from([
        ("own_picks".into(), own.len()),
        ("enemy_picks".into(), enemy.len()),
        ("missing_picks".into(), 10 - own.len() - enemy.len()),
    ]);
    let mut tokens: HashMap<String, String> = metrics
        .iter()
        .map(|(key, value)| (key.clone(), value.to_string()))
        .collect();
    let fallback = if mm {
        "မသတ်မှတ်ရသေး"
    } else {
        "none identified yet"
    };
    for (prefix, list) in [("own", &own), ("enemy", &enemy)] {
        for kind in [
            "all",
            "frontline",
            "control",
            "peel",
            "dps",
            "poke",
            "pick",
            "burst",
            "dive",
            "sustain",
            "antidash",
            "suppress",
        ] {
            let group: Vec<_> = list
                .iter()
                .filter(|h| match kind {
                    "all" => true,
                    "frontline" => h.front(),
                    "control" => h.has("cc") || h.has("suppress"),
                    "peel" => h.has("peel") || h.has("antidash") || h.has("cc"),
                    "sustain" => h.has("sustain") || h.has("heal"),
                    _ => h.has(kind),
                })
                .collect();
            let key = format!("{prefix}_{kind}");
            metrics.insert(key.clone(), group.len());
            tokens.insert(
                key,
                if group.is_empty() {
                    fallback.into()
                } else {
                    group
                        .iter()
                        .map(|h| h.name.as_str())
                        .collect::<Vec<_>>()
                        .join(", ")
                },
            );
        }
    }
    for (i, role) in ["roam", "jungle", "mid", "exp", "gold"].iter().enumerate() {
        let name = draft.lineup(side).picks[i]
            .as_deref()
            .and_then(|id| catalog.hero(id))
            .map_or(fallback, |h| h.name.as_str());
        tokens.insert((*role).into(), name.into());
    }
    let render = |localized: &Localized| {
        let mut result = if mm { &localized.mm } else { &localized.en }.clone();
        for (key, value) in &tokens {
            result = result.replace(&format!("{{{key}}}"), value);
        }
        result
    };
    let card = |c: &Card| Prompt {
        title: render(&c.title),
        body: render(&c.body),
    };
    let style = RULES
        .styles
        .iter()
        .find(|r| matches(r, &metrics))
        .expect("fallback style");
    let mut cards: Vec<_> = style.cards.iter().map(&card).collect();
    if !own.is_empty() {
        cards.extend(RULES.common.iter().map(&card));
        for rule in &RULES.context {
            if matches(rule, &metrics) {
                cards.extend(rule.cards.iter().map(&card));
            }
        }
    }
    (format!("{}:{}", RULES.version, style.id), cards)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[derive(Deserialize)]
    struct Case {
        id: String,
        draft: Draft,
        side: Side,
        strategy_id: String,
        required: Vec<String>,
    }
    #[test]
    fn lineup_cases_have_expected_strategy_names_and_no_unresolved_tokens() {
        let c: Catalog = serde_json::from_str(include_str!("../../data/catalog.json")).unwrap();
        let cases: Vec<Case> =
            serde_json::from_str(include_str!("../../data/fixtures/playbook_cases.json")).unwrap();
        for case in cases {
            crate::engine::validate(&case.draft, &c).unwrap();
            for mm in [false, true] {
                let (id, cards) = plan(&case.draft, &case.side, &c, mm);
                assert_eq!(id, case.strategy_id, "{}", case.id);
                let content = cards
                    .iter()
                    .map(|p| format!("{} {}", p.title, p.body))
                    .collect::<Vec<_>>()
                    .join("\n");
                assert!(!content.contains('{'), "{}: {content}", case.id);
                for name in &case.required {
                    assert!(content.contains(name), "{} missing {name}", case.id);
                }
                if case
                    .draft
                    .lineup(&case.side)
                    .picks
                    .iter()
                    .all(Option::is_none)
                {
                    assert_eq!(cards.len(), 1);
                } else if !case.draft.used().is_empty() {
                    assert!(cards.len() >= 5);
                }
                // Bans must never be used as actors or evidence for the plan.
                for ban in case
                    .draft
                    .blue
                    .bans
                    .iter()
                    .chain(&case.draft.red.bans)
                    .flatten()
                {
                    assert!(!content.contains(&c.hero(ban).unwrap().name));
                }
            }
        }
    }

    #[test]
    fn bans_do_not_change_strategy_and_changing_opponent_changes_the_plan() {
        let c: Catalog = serde_json::from_str(include_str!("../../data/catalog.json")).unwrap();
        let mut d: Draft = serde_json::from_value(
            serde_json::from_str::<serde_json::Value>(include_str!(
                "../../data/fixtures/playbook_cases.json"
            ))
            .unwrap()[2]["draft"]
                .clone(),
        )
        .unwrap();
        let before = plan(&d, &Side::Blue, &c, false);
        d.red.bans[0] = Some("fanny".into());
        let after = plan(&d, &Side::Blue, &c, false);
        assert_eq!(
            serde_json::to_value(before).unwrap(),
            serde_json::to_value(after).unwrap()
        );
        d.red.picks = [
            Some("franco".into()),
            Some("saber".into()),
            Some("xavier".into()),
            Some("uranus".into()),
            Some("brody".into()),
        ];
        let changed = plan(&d, &Side::Blue, &c, false);
        assert_ne!(changed.0, "lineup-plan-1:protect_carry");
        assert!(changed.1.iter().any(|p| p.body.contains("Franco")));
    }
}
