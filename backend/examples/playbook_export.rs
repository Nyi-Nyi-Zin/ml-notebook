//! Export the shared regression cases for exact comparison with Dart.
use draftroom_api::{models::*, playbook};
use serde_json::{json, Value};

fn main() {
    let catalog: Catalog = serde_json::from_str(include_str!("../../data/catalog.json")).unwrap();
    let cases: Vec<Value> =
        serde_json::from_str(include_str!("../../data/fixtures/playbook_cases.json")).unwrap();
    let mut output = vec![];
    for case in cases {
        let draft: Draft = serde_json::from_value(case["draft"].clone()).unwrap();
        let side: Side = serde_json::from_value(case["side"].clone()).unwrap();
        for language in ["en", "mm"] {
            let (strategy_id, plan) = playbook::plan(&draft, &side, &catalog, language == "mm");
            output.push(
                json!({"id":case["id"],"language":language,"strategy_id":strategy_id,"plan":plan}),
            );
        }
    }
    println!("{}", serde_json::to_string(&output).unwrap());
}
