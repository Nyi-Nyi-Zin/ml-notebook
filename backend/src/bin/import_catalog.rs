use draftroom_api::models::{Catalog, ROLES};
use sqlx::postgres::PgPoolOptions;
use std::collections::HashSet;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    dotenvy::dotenv().ok();
    let path = std::env::args()
        .nth(1)
        .ok_or("Usage: cargo run --bin import_catalog -- path/to/catalog.json")?;
    let c: Catalog = serde_json::from_slice(&std::fs::read(path)?)?;
    if c.patch.id.trim().is_empty() || c.patch.id.len() > 80 || c.heroes.is_empty() {
        return Err("Patch ID and heroes are required".into());
    }
    let mut ids = HashSet::new();
    for h in &c.heroes {
        if h.id.is_empty()
            || h.id.len() > 80
            || !h
                .id
                .bytes()
                .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
            || !ids.insert(&h.id)
            || h.name.trim().is_empty()
            || h.roles.is_empty()
            || h.roles.iter().any(|r| !ROLES.contains(&r.as_str()))
            || !["physical", "magic", "mixed"].contains(&h.damage.as_str())
        {
            return Err(format!("Invalid or duplicate hero profile: {}", h.id).into());
        }
    }
    let pool = PgPoolOptions::new()
        .max_connections(1)
        .connect(&std::env::var("DATABASE_URL")?)
        .await?;
    sqlx::query("INSERT INTO catalogs(patch_id,payload) VALUES($1,$2)")
        .bind(&c.patch.id)
        .bind(serde_json::to_value(&c)?)
        .execute(&pool)
        .await?;
    println!(
        "Imported {} profiles as patch {}. Existing patches were not modified.",
        c.heroes.len(),
        c.patch.id
    );
    pool.close().await;
    Ok(())
}
