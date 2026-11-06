use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub const ROLES: [&str; 5] = ["Roam", "Jungle", "Mid", "EXP", "Gold"];

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Patch {
    pub id: String,
    pub label: String,
    pub reviewed: bool,
    pub notes: String,
    pub sources: Vec<String>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Hero {
    pub id: String,
    pub name: String,
    pub roles: Vec<String>,
    pub tags: Vec<String>,
    pub damage: String,
}
impl Hero {
    pub fn has(&self, tag: &str) -> bool {
        self.tags.iter().any(|t| t == tag)
    }
    pub fn front(&self) -> bool {
        self.has("tank") || self.has("frontline")
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Catalog {
    pub patch: Patch,
    pub heroes: Vec<Hero>,
}
impl Catalog {
    pub fn hero(&self, id: &str) -> Option<&Hero> {
        self.heroes.iter().find(|h| h.id == id)
    }
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Side {
    Blue,
    Red,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Lineup {
    pub name: String,
    pub picks: [Option<String>; 5],
    pub bans: [Option<String>; 5],
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Draft {
    pub title: String,
    pub patch_id: String,
    pub blue: Lineup,
    pub red: Lineup,
    pub notes: String,
}
impl Draft {
    pub fn lineup(&self, side: &Side) -> &Lineup {
        match side {
            Side::Blue => &self.blue,
            Side::Red => &self.red,
        }
    }
    pub fn enemy(&self, side: &Side) -> &Lineup {
        match side {
            Side::Blue => &self.red,
            Side::Red => &self.blue,
        }
    }
    pub fn used(&self) -> Vec<&str> {
        self.blue
            .picks
            .iter()
            .chain(&self.red.picks)
            .chain(&self.blue.bans)
            .chain(&self.red.bans)
            .filter_map(|h| h.as_deref())
            .collect()
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Priority {
    Balanced,
    Survival,
    Tempo,
}
#[derive(Debug, Deserialize)]
pub struct AnalyzeRequest {
    pub draft: Draft,
    pub side: Side,
    pub role_index: usize,
    pub priority: Priority,
    #[serde(default)]
    pub language: String,
}
#[derive(Debug, Serialize, Deserialize)]
pub struct User {
    pub id: Uuid,
    pub email: String,
    pub display_name: String,
}
#[derive(Debug, Serialize, Deserialize)]
pub struct AuthResponse {
    pub token: String,
    pub user: User,
}
#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub email: String,
    pub password: String,
}
#[derive(Debug, Deserialize)]
pub struct RegisterRequest {
    pub email: String,
    pub password: String,
    pub display_name: String,
}
#[derive(Debug, Deserialize)]
pub struct SaveDraft {
    pub draft: Draft,
    pub team_id: Option<Uuid>,
    pub expected_revision: Option<i64>,
}
#[derive(Debug, Serialize, Deserialize)]
pub struct DraftRecord {
    pub id: Uuid,
    pub owner_id: Uuid,
    pub team_id: Option<Uuid>,
    pub draft: Draft,
    pub revision: i64,
    pub updated_at: chrono::DateTime<chrono::Utc>,
    pub archived: bool,
    pub can_edit: bool,
}
#[derive(Debug, Serialize, Deserialize, sqlx::FromRow)]
pub struct Team {
    pub id: Uuid,
    pub name: String,
    pub role: String,
}
