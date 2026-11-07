use crate::models::*;
use serde::Serialize;
use std::collections::HashSet;

#[derive(Debug, Serialize)]
pub struct Counts {
    pub frontline: usize,
    pub control: usize,
    pub dive: usize,
    pub burst: usize,
    pub sustain: usize,
    pub physical: usize,
    pub magic: usize,
}
fn count(hs: &[&Hero], tag: &str) -> usize {
    hs.iter().filter(|h| h.has(tag)).count()
}
pub fn counts(hs: &[&Hero]) -> Counts {
    Counts {
        frontline: hs.iter().filter(|h| h.front()).count(),
        control: hs
            .iter()
            .filter(|h| h.has("cc") || h.has("suppress"))
            .count(),
        dive: count(hs, "dive"),
        burst: count(hs, "burst"),
        sustain: hs
            .iter()
            .filter(|h| h.has("sustain") || h.has("heal"))
            .count(),
        physical: hs
            .iter()
            .filter(|h| ["physical", "mixed"].contains(&h.damage.as_str()))
            .count(),
        magic: hs
            .iter()
            .filter(|h| ["magic", "mixed"].contains(&h.damage.as_str()))
            .count(),
    }
}
#[derive(Debug, Serialize)]
pub struct Prompt {
    pub title: String,
    pub body: String,
}
#[derive(Debug, Serialize)]
pub struct Emblem {
    pub base: String,
    pub talents: [String; 3],
    pub spell: String,
    pub reason: String,
    pub tradeoff: String,
    pub alternative: String,
    pub specificity: String,
}
#[derive(Debug, Serialize)]
pub struct Candidate {
    pub hero_id: String,
    pub score: i32,
    pub reasons: Vec<String>,
}
#[derive(Debug, Serialize)]
pub struct Analysis {
    pub rules_version: String,
    pub patch: Patch,
    pub partial: bool,
    pub own: Counts,
    pub enemy: Counts,
    pub focus: Option<Hero>,
    pub emblem: Option<Emblem>,
    pub threats: Vec<Prompt>,
    pub plan: Vec<Prompt>,
    pub candidates: Vec<Candidate>,
}
pub fn validate(d: &Draft, c: &Catalog) -> Result<(), String> {
    if d.patch_id != c.patch.id {
        return Err("Choose the catalog patch used by this draft.".into());
    }
    if d.title.trim().is_empty() || d.title.chars().count() > 100 {
        return Err("Draft title must be 1–100 characters.".into());
    }
    if d.notes.chars().count() > 12000 {
        return Err("Notes must be at most 12,000 characters.".into());
    }
    if [&d.blue.name, &d.red.name]
        .iter()
        .any(|n| n.trim().is_empty() || n.chars().count() > 32)
    {
        return Err("Team names must be 1–32 characters.".into());
    }
    let mut ids = HashSet::new();
    for id in d.used() {
        if c.hero(id).is_none() {
            return Err(format!("Unknown hero: {id}"));
        }
        if !ids.insert(id) {
            return Err("A hero cannot be picked or banned more than once.".into());
        }
    }
    Ok(())
}
fn lineup<'a>(l: &Lineup, c: &'a Catalog) -> Vec<&'a Hero> {
    l.picks
        .iter()
        .filter_map(|id| id.as_deref().and_then(|id| c.hero(id)))
        .collect()
}
fn text(mm: bool, en: &str, my: &str) -> String {
    if mm {
        my.into()
    } else {
        en.into()
    }
}
fn prompt(mm: bool, title: &str, my_title: &str, body: &str, my_body: &str) -> Prompt {
    Prompt {
        title: text(mm, title, my_title),
        body: text(mm, body, my_body),
    }
}
pub fn analyze(r: &AnalyzeRequest, c: &Catalog) -> Result<Analysis, String> {
    validate(&r.draft, c)?;
    if r.role_index >= 5 {
        return Err("Role index must be 0–4.".into());
    }
    let mm = r.language == "mm";
    let hs = lineup(r.draft.lineup(&r.side), c);
    let es = lineup(r.draft.enemy(&r.side), c);
    let own = counts(&hs);
    let enemy = counts(&es);
    let focus = r.draft.lineup(&r.side).picks[r.role_index]
        .as_deref()
        .and_then(|id| c.hero(id));
    let other_front = hs
        .iter()
        .filter(|h| h.front() && Some(h.id.as_str()) != focus.map(|f| f.id.as_str()))
        .count();
    let emblem=focus.map(|h| {
        let (base,one,two,three,spell,reason,tradeoff,alt)=match r.role_index {
            0 => {
                let healer=(h.has("heal")||h.has("support"))&&!h.has("tank");
                let damage=h.has("assassin")||h.id=="selena";
                let durable=matches!(r.priority,Priority::Survival)||matches!(r.priority,Priority::Balanced)&&(other_front==0||enemy.burst>=3);
                let base=if healer {"Support"} else if damage {if h.damage=="magic" {"Mage"} else {"Assassin"}} else {"Tank"};
                let two=if healer||damage||!durable {"Pull Yourself Together"} else {"Tenacity"};
                let three=if healer {"Focusing Mark"} else if damage {"Lethal Ignition"} else if h.has("heal")||h.has("sustain") {"Brave Smite"} else {"Concussive Blast"};
                let spell=if damage&&h.id=="natalia" {"Execute"} else {"Flicker"};
                let reason=if healer {text(mm,"Utility and skill uptime fit this profile. Use teammate cover when checking fog.","Utility နဲ့ skill uptime ကို ဦးစားပေးထားတယ်။ Information ယူချိန် teammate cover လိုတယ်။")} else if damage {text(mm,"Play around information and isolated targets. Confirm who holds space for your carries.","Information နဲ့ လူခွဲနေတဲ့ target ကို ဦးစားပေးပါ။ Carry အတွက် နေရာထိန်းပေးသူကို သတ်မှတ်ပါ။")} else if durable {text(mm,"You are the main frontline, the enemy has several burst profiles, or Survival was selected. Keep Agility while investing in durability.","Main frontline ဖြစ်တာ၊ enemy burst များတာ၊ Survival ရွေးထားတာကြောင့် ခံနိုင်ရည်ကို ဦးစားပေးထားတယ်။ Rotation အတွက် Agility ဆက်ထားမယ်။")} else {text(mm,"Another ally can share the frontline, or Tempo was selected. Keep Tank durability and Agility, then invest in battle-spell availability.","Frontline တာဝန်ခွဲနိုင်တဲ့ ally ရှိတာ သို့မဟုတ် Tempo ရွေးထားလို့ Tank နဲ့ Agility ထားပြီး Battle Spell uptime ကို ဖြည့်ထားတယ်။")};
                (base,"Agility",two,three,spell,reason,
                 if base=="Tank" {text(mm,"Tank gives up Support's healing, skill cooldown and base movement benefits. Agility only partly offsets that mobility trade-off.","Tank ယူရင် Support ရဲ့ healing၊ skill cooldown နဲ့ base movement benefit တွေကို စွန့်ရတယ်။ Agility က movement trade-off ကို တစ်စိတ်တစ်ပိုင်းပဲ ဖြည့်ပေးတယ်။")} else {text(mm,"This page gives less raw durability than a Tank base. Positioning and team cover matter.","Tank base ထက် ခံနိုင်ရည်နည်းနိုင်လို့ positioning နဲ့ teammate cover ကို ဂရုစိုက်ပါ။")},
                 if two=="Tenacity" {text(mm,"Consider Pull Yourself Together when you can survive and missing Flicker windows limits your plays.","ခံနိုင်ရည်လုံလောက်ပြီး Flicker မမီလို့ play လုပ်မရရင် Pull Yourself Together ပြောင်းစဉ်းစားပါ။")} else {text(mm,"Consider Tenacity when you cannot survive the first damage wave. Another frontline ally does not guarantee your safety.","ပထမ damage wave မခံနိုင်ရင် Tenacity ပြောင်းစဉ်းစားပါ။ Frontline ally ရှိတာနဲ့ လုံလောက်ပြီလို့ မယူပါနဲ့။")})
            },
            1 => (if h.has("tank") {"Tank"} else if h.damage=="magic" {"Mage"} else if h.has("sustain") {"Fighter"} else {"Assassin"},"Agility","Seasoned Hunter",if h.has("tank") {"Concussive Blast"} else if h.damage=="magic" {"Lethal Ignition"} else if h.has("sustain") {"Brave Smite"} else {"Killing Spree"},"Retribution",
                  text(mm,"Retribution matches the Jungle role. The base follows this hero's durability or damage profile.","Jungle တာဝန်အတွက် Retribution ယူမယ်။ Hero ရဲ့ damage နဲ့ ခံနိုင်ရည်အလိုက် base ရွေးထားတယ်။"),text(mm,"Generic starting template. Verify clear speed, talent availability and the hero's current-patch interactions.","အခြေခံ template ဖြစ်လို့ jungle clear speed၊ talent ရနိုင်မှုနဲ့ current patch interaction ကို ပြန်စစ်ပါ။"),text(mm,"Select the Retribution upgrade around target access and survivability.","Target ကို ဝင်နိုင်မှုနဲ့ အသက်ရှင်ရေးအလိုက် Retribution upgrade ရွေးပါ။")),
            2 => (if h.damage=="physical" {"Assassin"} else {"Mage"},"Agility","Bargain Hunter",if h.has("poke") {"Impure Rage"} else {"Lethal Ignition"},if enemy.control>=3&&!es.iter().any(|h|h.has("suppress")) {"Purify"} else {"Flicker"},text(mm,"Wave access and safe rotation support your damage windows.","Wave ရှင်းနိုင်မှုနဲ့ လုံခြုံတဲ့ rotation ကို ဦးစားပေးထားတယ်။"),text(mm,"Role template, not a tested optimal hero build. Resource needs may override it.","Role template ဖြစ်ပြီး hero အတွက် optimal build လို့ မယူပါနဲ့။ Resource လိုအပ်ချက်အရ ပြောင်းနိုင်တယ်။"),text(mm,"Choose a defensive spell that answers the actual enemy engage. Purify does not remove suppression.","Enemy engage ကို ဖြေရှင်းနိုင်တဲ့ spell ရွေးပါ။ Purify နဲ့ suppression ကို မဖြေနိုင်ဘူး။")),
            3 => (if h.has("tank") {"Tank"} else if h.id=="esmeralda" {"Support"} else if h.damage=="magic" {"Mage"} else if h.has("assassin") {"Assassin"} else {"Fighter"},"Agility","Tenacity",if h.has("sustain") {"Brave Smite"} else if h.damage=="magic" {"Lethal Ignition"} else if h.has("basic") {"Quantum Charge"} else {"War Cry"},if enemy.control>=3&&!es.iter().any(|h|h.has("suppress")) {"Purify"} else if h.has("sustain") {"Vengeance"} else {"Flicker"},text(mm,"Hold the side wave and arrive with enough HP to create a second angle.","Side wave ကို ထိန်းပြီး ဒုတိယ angle က pressure ပေးနိုင်အောင် HP ထိန်းလာပါ။"),text(mm,"The lane matchup and build strongly affect this choice. No item timings are simulated.","Lane matchup နဲ့ item build ပေါ် မူတည်တယ်။ Item timing ကို ဒီ engine မှာ မတွက်ထားသေးဘူး။"),text(mm,"Flicker supports target access; Vengeance suits extended contact. Review the lane opponent before locking.","Flicker က ဝင်ရောက်နိုင်ဖို့၊ Vengeance က fight ရှည်အတွက် စဉ်းစားနိုင်တယ်။ Lane opponent ကိုပါ ပြန်စစ်ပါ။")),
            _ => (if h.damage=="magic" {"Mage"} else {"Marksman"},"Agility",if h.damage=="magic" {"Bargain Hunter"} else {"Weapon Master"},if h.has("basic") {"Quantum Charge"} else {"Lethal Ignition"},if enemy.control>=3&&!es.iter().any(|h|h.has("suppress")) {"Purify"} else {"Flicker"},text(mm,"Preserve safe damage uptime and answer the enemy's route to your backline.","Damage ပေးနိုင်တဲ့အချိန်ကို ထိန်းပြီး enemy ဝင်လာမယ့်လမ်းကို စဉ်းစားပါ။"),text(mm,"This is a generic lane page. Hero-specific mechanics and lane matchups can override it.","Lane အတွက် generic page ဖြစ်တယ်။ Hero mechanics နဲ့ matchup အရ ပြောင်းဖို့လိုနိုင်တယ်။"),text(mm,"Inspire is an alternative only for heroes and fights where safe basic-attack uptime is realistic.","Basic attack လုံလုံခြုံခြုံ ပေးနိုင်တဲ့ hero နဲ့ fight ဖြစ်မှ Inspire ကို စဉ်းစားပါ။"))
        };
        Emblem {base:base.into(),talents:[one.into(),two.into(),three.into()],spell:spell.into(),reason,tradeoff,alternative:alt,specificity:if h.id=="minotaur" {"scenario_rules"} else {"role_template"}.into()}
    });
    let mut threats = vec![];
    if focus.is_some_and(|h| !h.roles.iter().any(|role| role == ROLES[r.role_index])) {
        threats.push(prompt(mm,"Off-lane selection","Lane မကိုက်တဲ့ pick","This hero is outside the catalog's suggested lanes. Confirm a practiced flex; the emblem remains a starting profile, not evidence of lane suitability.","ဒီ hero က သတ်မှတ်ထားတဲ့ lane မဟုတ်လို့ လေ့ကျင့်ထားတဲ့ flex ဟုတ်မဟုတ် စစ်ပါ။ Emblem အကြံပြုတာနဲ့ lane ကိုက်တယ်လို့ မယူပါနဲ့။"));
    }
    if es.iter().any(|h| h.has("truedmg")) {
        threats.push(prompt(mm,"True-damage triggers","True damage ကို သတိထား","Track the specific true-damage trigger. Armor and magic defense alone do not answer it; use spacing, HP and deny repeated hits.","True damage ထွက်စေတဲ့ skill နဲ့ trigger ကို စောင့်ကြည့်ပါ။ Armor နဲ့ magic defense တင်မလုံလောက်လို့ spacing၊ HP နဲ့ အကြိမ်ကြိမ်ထိတာကို ရှောင်ပါ။"));
    }
    if es.iter().filter(|h| h.has("basic") && h.has("dps")).count() >= 2 {
        threats.push(prompt(mm,"Basic-attack uptime","Basic attack ပေးခွင့် မပေးပါနဲ့","Avoid extended open contact with multiple basic-attack carries. Break line of sight and coordinate control before they free-hit.","Basic attack carry များနေရင် အချိန်ကြာကြာ ပစ်ခွင့်မပေးပါနဲ့။ မြင်ကွင်းဖြတ်ပြီး CC နဲ့ teammate ကို ညှိပါ။"));
    }
    if es.iter().any(|h| h.id == "yin") {
        threats.push(prompt(mm,"Respect isolation","တစ်ယောက်တည်း မခွဲနေပါနဲ့","Keep vision before approaching Yin and track his isolation ultimate. Plan survival without assuming outside ally support can reach you.","Yin အနားဝင်ရင် vision နဲ့ ultimate ကို စစ်ပါ။ Team အကူအညီ အမြဲမီမယ်လို့ မယူဘဲ အသက်ရှင်ဖို့ ပြင်ထားပါ။"));
    }
    if es.iter().any(|h| h.id == "marcel") {
        threats.push(prompt(mm,"Marcel's control field","Marcel ရဲ့ control area","Avoid committing the whole team into Marcel's control area. Keep an exit and check the actual skill state before following an engage.","Marcel ရဲ့ control area ထဲ team အကုန်မဝင်ပါနဲ့။ ထွက်လမ်းထားပြီး skill အခြေအနေကို စစ်ပြီးမှ follow-up လုပ်ပါ။"));
    }

    if es.iter().any(|h| h.has("suppress")) {
        threats.push(prompt(mm,"Suppression access","Suppression ကို သတိထား","Track the suppression carrier's position and cooldown. Purify does not remove suppression; coordinate spacing and interruption.","Suppression hero ရဲ့ position နဲ့ cooldown ကို စောင့်ကြည့်ပါ။ Purify နဲ့ မဖြေနိုင်လို့ spacing နဲ့ teammate interruption ကို ညှိပါ။"));
    }
    if enemy.dive > 0 {
        threats.push(prompt(mm,"Protect the second angle","ဒုတိယ angle ကို ကာကွယ်ပါ","The enemy has dive profiles. Keep a peel tool when your carry can be reached; do not spend all control on the first target.","Enemy dive hero ရှိလို့ carry အတွက် peel CC တစ်ခု ချန်ထားပါ။ ပထမ target ပေါ် CC အကုန် မသုံးပါနဲ့။"));
    }
    if enemy.burst >= 2 {
        threats.push(prompt(mm,"Survive the first wave","ပထမ damage wave ကို ခံနိုင်ဖို့","Scout with an exit and teammate cover. Preserve enough HP to finish your control sequence.","ထွက်လမ်းနဲ့ teammate cover ရှိမှ information ယူပါ။ CC combo ပြီးအောင် သုံးနိုင်ဖို့ HP ထိန်းပါ။"));
    }
    if enemy.sustain >= 2 {
        threats.push(prompt(mm,"Assign anti-heal coverage","Anti-heal တာဝန်ခွဲပါ","Assign an anti-heal carrier and confirm how they apply it. The roamer need not buy every utility item.","Anti-heal ကို ဘယ်သူယူပြီး ဘယ်လို apply လုပ်မလဲ သတ်မှတ်ပါ။ Utility item အားလုံးကို roam တစ်ယောက်တည်း ယူဖို့ မလိုဘူး။"));
    }
    if es.iter().any(|h| h.has("antidash")) && focus.is_some_and(|h| h.has("dive")) {
        threats.push(prompt(mm,"Respect anti-dash zones","Anti-dash skill ကို စောင့်ပါ","Wait for the relevant anti-dash control to end before committing mobility. Track the specific skill, not just the hero name.","Anti-dash skill ထွက်သွားမှ mobility နဲ့ ဝင်ပါ။ Hero name ပဲကြည့်မနေဘဲ skill cooldown ကို စောင့်ပါ။"));
    }
    if focus.is_some_and(|h| h.id == "minotaur") && es.iter().any(|h| h.id == "valentina") {
        threats.push(prompt(mm,"Track the copied ultimate","Copy လုပ်ထားတဲ့ ultimate ကို စောင့်ကြည့်ပါ","Check Valentina's copied ultimate and avoid a grouped counter-engage after your own initiation.","Valentina copy လုပ်ထားတဲ့ ultimate ကို စစ်ပြီးမှ ဝင်ပါ။ Team အကုန်ကပ်ပြီး counter-engage ခံရတာကို ရှောင်ပါ။"));
    }
    let mut plan=vec![prompt(mm,"Opening · earn the first move","အစပိုင်း · rotation အရင်ရအောင်","Coordinate the first clear with mid and jungle. Scout only with a purpose, teammate cover and an exit route.","Mid နဲ့ Jungle clear အချိန်ကို ညှိပါ။ ရည်ရွယ်ချက်၊ teammate cover နဲ့ ထွက်လမ်းရှိမှ information ယူပါ။"),prompt(mm,"Objective · control an entrance","Objective · entrance တစ်ခုကို ထိန်းပါ","Prepare nearby waves, pick an entrance to hold, and name who zones the enemy jungler. Reassess if a side-laner cannot join.","အနီးက wave ကို ပြင်ပါ။ ဘယ် entrance ထိန်းမလဲ၊ enemy jungler ကို ဘယ်သူတားမလဲ သတ်မှတ်ပါ။ Side laner မလာနိုင်ရင် ပြန်စဉ်းစားပါ။")];
    plan.push(if focus.is_some_and(|h|h.id=="minotaur")&&hs.iter().any(|h|h.id=="esmeralda") {prompt(mm,"Teamfight · divide the jobs","Teamfight · တာဝန်ခွဲထားပါ","Esmeralda can pressure a second angle. Minotaur follows with control or holds peel. An assassin commits after key enemy control is used; not everyone must enter together.","Esme က ဒုတိယ angle က pressure ပေးနိုင်တယ်။ Minotaur က follow-up CC သို့မဟုတ် peel တာဝန်ယူပါ။ Assassin က အရေးကြီး enemy CC ထွက်ပြီးမှ ဝင်ပါ။ အားလုံးတပြိုင်တည်း ဝင်ဖို့ မလိုဘူး။")} else {prompt(mm,"Teamfight · name the target","Teamfight · target ကို သတ်မှတ်ပါ","Name the first target, confirm follow-up range, and track the enemy control that stops your damage. Keep peel if the carry is exposed.","ပထမ target နဲ့ teammate လိုက်မီတဲ့ range ကို သတ်မှတ်ပါ။ ကိုယ့် damage ကို တားနိုင်တဲ့ enemy CC ကို စောင့်ပြီး carry အတွက် လိုရင် peel ချန်ထားပါ။")});
    let selected_id = r.draft.lineup(&r.side).picks[r.role_index].as_deref();
    let remaining: Vec<&Hero> = hs
        .iter()
        .copied()
        .filter(|h| Some(h.id.as_str()) != selected_id)
        .collect();
    let rem = counts(&remaining);
    let used: HashSet<&str> = r.draft.used().into_iter().collect();
    let mut candidates: Vec<Candidate> = c
        .heroes
        .iter()
        .filter(|h| !used.contains(h.id.as_str()))
        .filter(|h| h.roles.iter().any(|role| role == ROLES[r.role_index]))
        .map(|h| {
            let mut score = 0;
            let mut reasons = vec![];
            let mut add = |s: i32, en: &str, my: &str| {
                score += s;
                reasons.push(text(mm, en, my));
            };
            if h.roles.iter().any(|role| role == ROLES[r.role_index]) {
                add(5, "Fits this role", "ဒီ role နဲ့ ကိုက်တယ်");
            } else {
                add(
                    -4,
                    "Off-role: confirm a practiced flex",
                    "Off-role ဖြစ်လို့ လေ့ကျင့်ထားတဲ့ flex ဟုတ်မဟုတ် စစ်ပါ",
                );
            }
            if rem.frontline == 0 && h.front() {
                add(3, "Adds a frontline", "Frontline ဖြည့်ပေးတယ်");
            }
            if rem.control == 0 && (h.has("cc") || h.has("suppress")) {
                add(2, "Adds control", "Control ဖြည့်ပေးတယ်");
            }
            if rem.magic == 0 && ["magic", "mixed"].contains(&h.damage.as_str()) {
                add(1, "Adds magic damage", "Magic damage ဖြည့်ပေးတယ်");
            }
            if enemy.dive >= 2 && (h.has("peel") || h.has("antidash")) {
                add(2, "Helps against dive access", "Enemy dive ကို ကာကွယ်ဖို့ ကူညီတယ်");
            }
            if enemy.sustain >= 2 && h.has("antiheal") {
                add(
                    2,
                    "Adds anti-sustain pressure",
                    "Enemy sustain ကို ဖိအားပေးနိုင်တယ်",
                );
            }
            Candidate {
                hero_id: h.id.clone(),
                score,
                reasons,
            }
        })
        .collect();
    candidates.sort_by(|a, b| b.score.cmp(&a.score).then(a.hero_id.cmp(&b.hero_id)));
    candidates.truncate(8);
    Ok(Analysis {
        rules_version: "coach-rules-2".into(),
        patch: c.patch.clone(),
        partial: hs.len() < 5 || es.len() < 5,
        own,
        enemy,
        focus: focus.cloned(),
        emblem,
        threats,
        plan,
        candidates,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    fn catalog() -> Catalog {
        serde_json::from_str(include_str!("../../data/catalog.json")).unwrap()
    }
    fn draft() -> Draft {
        Draft {
            title: "Scrim".into(),
            patch_id: catalog().patch.id,
            blue: Lineup {
                name: "Blue".into(),
                picks: [
                    Some("minotaur".into()),
                    Some("ling".into()),
                    None,
                    None,
                    None,
                ],
                bans: Default::default(),
            },
            red: Lineup {
                name: "Red".into(),
                picks: Default::default(),
                bans: Default::default(),
            },
            notes: String::new(),
        }
    }
    fn request(draft: Draft) -> AnalyzeRequest {
        AnalyzeRequest {
            draft,
            side: Side::Blue,
            role_index: 0,
            priority: Priority::Balanced,
            language: "en".into(),
        }
    }
    #[test]
    fn single_frontline_keeps_survival() {
        let a = analyze(&request(draft()), &catalog()).unwrap();
        assert_eq!(a.emblem.unwrap().talents[1], "Tenacity");
        assert!(a.partial);
    }
    #[test]
    fn esme_allows_spell_tempo_but_heavy_burst_overrides() {
        let mut d = draft();
        d.blue.picks[3] = Some("esmeralda".into());
        assert_eq!(
            analyze(&request(d.clone()), &catalog())
                .unwrap()
                .emblem
                .unwrap()
                .talents[1],
            "Pull Yourself Together"
        );
        d.red.picks = [
            Some("eudora".into()),
            Some("hayabusa".into()),
            Some("brody".into()),
            None,
            None,
        ];
        assert_eq!(
            analyze(&request(d), &catalog())
                .unwrap()
                .emblem
                .unwrap()
                .talents[1],
            "Tenacity"
        );
    }
    #[test]
    fn prevents_duplicate_across_pick_and_ban() {
        let mut d = draft();
        d.red.bans[0] = Some("ling".into());
        assert!(validate(&d, &catalog()).is_err());
    }
    #[test]
    fn suppression_and_copy_are_visible() {
        let mut d = draft();
        d.red.picks[0] = Some("franco".into());
        d.red.picks[2] = Some("valentina".into());
        let a = analyze(&request(d), &catalog()).unwrap();
        assert!(a.threats.iter().any(|p| p.title.contains("Suppression")));
        assert!(a.threats.iter().any(|p| p.title.contains("copied")));
    }
    #[test]
    fn priority_is_an_explicit_tradeoff() {
        let mut r = request(draft());
        r.priority = Priority::Tempo;
        assert_eq!(
            analyze(&r, &catalog()).unwrap().emblem.unwrap().talents[1],
            "Pull Yourself Together"
        );
    }
    #[test]
    fn empty_focus_and_invalid_role_are_handled() {
        let mut r = request(draft());
        r.role_index = 2;
        let a = analyze(&r, &catalog()).unwrap();
        assert!(a.emblem.is_none());
        assert!(!a.candidates.is_empty());
        r.role_index = 6;
        assert!(analyze(&r, &catalog()).is_err());
    }
    #[test]
    fn suggestions_exclude_all_used_heroes() {
        let d = draft();
        let a = analyze(&request(d.clone()), &catalog()).unwrap();
        assert!(a
            .candidates
            .iter()
            .all(|c| !d.used().contains(&c.hero_id.as_str())));
    }
    #[test]
    fn jungle_always_has_retribution() {
        let mut r = request(draft());
        r.role_index = 1;
        assert_eq!(
            analyze(&r, &catalog()).unwrap().emblem.unwrap().spell,
            "Retribution"
        );
    }
    #[test]
    fn myanmar_generic_plan_does_not_invent_esme() {
        let mut r = request(draft());
        r.language = "mm".into();
        assert!(!analyze(&r, &catalog()).unwrap().plan[2]
            .body
            .contains("Esme"));
    }
    #[test]
    fn complete_roster_works_in_every_suggested_lane_and_language() {
        let c = catalog();
        assert_eq!(c.heroes.len(), 133);
        let ids: HashSet<_> = c.heroes.iter().map(|h| &h.id).collect();
        assert_eq!(ids.len(), 133);
        for hero in &c.heroes {
            for lane in &hero.roles {
                let role = ROLES.iter().position(|r| r == lane).unwrap();
                for language in ["en", "mm"] {
                    let mut d = draft();
                    d.blue.picks = Default::default();
                    d.blue.picks[role] = Some(hero.id.clone());
                    let mut r = request(d);
                    r.role_index = role;
                    r.language = language.into();
                    let a = analyze(&r, &c).unwrap();
                    assert!(a.emblem.is_some(), "{} in {}", hero.id, lane);
                    assert!(a.candidates.iter().all(|candidate| c
                        .hero(&candidate.hero_id)
                        .unwrap()
                        .roles
                        .contains(lane)));
                    if role == 1 {
                        assert_eq!(a.emblem.unwrap().spell, "Retribution");
                    }
                }
            }
        }
    }
    #[test]
    fn magic_junglers_and_utility_supports_use_matching_emblems() {
        let c = catalog();
        for (hero, role, base) in [
            ("harley", 1, "Mage"),
            ("marcel", 0, "Support"),
            ("gloo", 0, "Tank"),
            ("hirara", 1, "Assassin"),
            ("obsidia", 4, "Marksman"),
        ] {
            let mut d = draft();
            d.blue.picks = Default::default();
            d.blue.picks[role] = Some(hero.into());
            let mut r = request(d);
            r.role_index = role;
            assert_eq!(analyze(&r, &c).unwrap().emblem.unwrap().base, base);
        }
    }
    #[test]
    fn mixed_damage_and_new_matchup_prompts_are_visible() {
        let c = catalog();
        let mixed = counts(&[c.hero("esmeralda").unwrap()]);
        assert_eq!((mixed.physical, mixed.magic), (1, 1));
        let mut d = draft();
        d.red.picks = [Some("marcel".into()), Some("yin".into()), None, None, None];
        let a = analyze(&request(d), &c).unwrap();
        for title in [
            "True-damage triggers",
            "Respect isolation",
            "Marcel's control field",
        ] {
            assert!(a.threats.iter().any(|p| p.title == title));
        }
    }
}
