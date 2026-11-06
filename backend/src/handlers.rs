use crate::{auth, engine, models::*, AppError, AppState, Result};
use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{postgres::PgRow, Row};
use uuid::Uuid;

pub async fn health(State(s): State<AppState>) -> Result<Json<Value>> {
    sqlx::query("SELECT 1").execute(&s.pool).await?;
    Ok(Json(
        json!({"status":"ok","service":"draftroom-rust","version":env!("CARGO_PKG_VERSION")}),
    ))
}
#[derive(Deserialize, Default)]
pub struct CatalogQuery {
    pub patch_id: Option<String>,
}
pub async fn load_catalog(s: &AppState, id: Option<&str>) -> Result<Catalog> {
    let value: Value = if let Some(id) = id {
        sqlx::query_scalar("SELECT payload FROM catalogs WHERE patch_id=$1")
            .bind(id)
            .fetch_optional(&s.pool)
            .await?
    } else {
        sqlx::query_scalar(
            "SELECT payload FROM catalogs ORDER BY created_at DESC,patch_id DESC LIMIT 1",
        )
        .fetch_optional(&s.pool)
        .await?
    }
    .ok_or_else(|| AppError::bad("Catalog patch not found. Refresh the hero catalog."))?;
    serde_json::from_value(value).map_err(|_| {
        AppError(
            StatusCode::INTERNAL_SERVER_ERROR,
            "Catalog data needs review.".into(),
        )
    })
}
pub async fn catalog(
    State(s): State<AppState>,
    Query(q): Query<CatalogQuery>,
) -> Result<Json<Catalog>> {
    Ok(Json(load_catalog(&s, q.patch_id.as_deref()).await?))
}
pub async fn analyze(
    State(s): State<AppState>,
    Json(r): Json<AnalyzeRequest>,
) -> Result<Json<engine::Analysis>> {
    let c = load_catalog(&s, Some(&r.draft.patch_id)).await?;
    Ok(Json(engine::analyze(&r, &c).map_err(AppError::bad)?))
}
pub async fn teams(State(s): State<AppState>, headers: HeaderMap) -> Result<Json<Vec<Team>>> {
    let u = auth::user(&s, &headers).await?;
    Ok(Json(sqlx::query_as("SELECT t.id,t.name,m.role FROM teams t JOIN team_members m ON m.team_id=t.id WHERE m.user_id=$1 ORDER BY t.name").bind(u.id).fetch_all(&s.pool).await?))
}
#[derive(Deserialize)]
pub struct CreateTeam {
    name: String,
}
pub async fn create_team(
    State(s): State<AppState>,
    headers: HeaderMap,
    Json(r): Json<CreateTeam>,
) -> Result<Json<Team>> {
    let u = auth::user(&s, &headers).await?;
    let name = r.name.trim();
    if name.is_empty() || name.chars().count() > 60 {
        return Err(AppError::bad("Team name must be 1–60 characters."));
    }
    let id = Uuid::new_v4();
    let mut tx = s.pool.begin().await?;
    sqlx::query("INSERT INTO teams(id,name,owner_id) VALUES($1,$2,$3)")
        .bind(id)
        .bind(name)
        .bind(u.id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("INSERT INTO team_members(team_id,user_id,role) VALUES($1,$2,'owner')")
        .bind(id)
        .bind(u.id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(Json(Team {
        id,
        name: name.into(),
        role: "owner".into(),
    }))
}
pub async fn team_role(s: &AppState, id: Uuid, uid: Uuid) -> Result<Option<String>> {
    Ok(
        sqlx::query_scalar("SELECT role FROM team_members WHERE team_id=$1 AND user_id=$2")
            .bind(id)
            .bind(uid)
            .fetch_optional(&s.pool)
            .await?,
    )
}
#[derive(Deserialize)]
pub struct Invite {
    role: String,
}
pub async fn invite(
    State(s): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<Uuid>,
    Json(r): Json<Invite>,
) -> Result<Json<Value>> {
    let u = auth::user(&s, &headers).await?;
    if team_role(&s, id, u.id).await?.as_deref() != Some("owner") {
        return Err(AppError::forbidden());
    }
    if !["coach", "viewer"].contains(&r.role.as_str()) {
        return Err(AppError::bad("Invite role must be coach or viewer."));
    }
    let token = auth::token();
    sqlx::query("INSERT INTO team_invites(token_hash,team_id,role,expires_at) VALUES($1,$2,$3,now()+interval '24 hours')").bind(auth::hash_token(&token)).bind(id).bind(r.role).execute(&s.pool).await?;
    Ok(Json(
        json!({"code":token,"expires_in_hours":24,"single_use":true}),
    ))
}
#[derive(Deserialize)]
pub struct Join {
    code: String,
}
pub async fn join(
    State(s): State<AppState>,
    headers: HeaderMap,
    Json(r): Json<Join>,
) -> Result<Json<Value>> {
    let u = auth::user(&s, &headers).await?;
    if r.code.len() != 64 {
        return Err(AppError::bad("Invite code is invalid or expired."));
    }
    let mut tx = s.pool.begin().await?;
    let hash = auth::hash_token(r.code.trim());
    let invite=sqlx::query("SELECT team_id,role FROM team_invites WHERE token_hash=$1 AND used_at IS NULL AND expires_at>now() FOR UPDATE").bind(&hash).fetch_optional(&mut *tx).await?.ok_or_else(||AppError::bad("Invite code is invalid or expired."))?;
    let team_id: Uuid = invite.get("team_id");
    let role: String = invite.get("role");
    sqlx::query(
        "INSERT INTO team_members(team_id,user_id,role) VALUES($1,$2,$3) ON CONFLICT DO NOTHING",
    )
    .bind(team_id)
    .bind(u.id)
    .bind(role)
    .execute(&mut *tx)
    .await?;
    sqlx::query("UPDATE team_invites SET used_at=now() WHERE token_hash=$1")
        .bind(hash)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(Json(json!({"team_id":team_id})))
}
fn record(row: PgRow, uid: Uuid) -> Result<DraftRecord> {
    let value: Value = row.get("payload");
    let owner_id: Uuid = row.get("owner_id");
    let role: Option<String> = row.try_get("member_role").unwrap_or(None);
    Ok(DraftRecord {
        id: row.get("id"),
        owner_id,
        team_id: row.get("team_id"),
        draft: serde_json::from_value(value)
            .map_err(|_| AppError::bad("Saved draft has invalid data."))?,
        revision: row.get("revision"),
        updated_at: row.get("updated_at"),
        archived: row
            .get::<Option<chrono::DateTime<chrono::Utc>>, _>("archived_at")
            .is_some(),
        can_edit: owner_id == uid || matches!(role.as_deref(), Some("coach" | "owner")),
    })
}
const RECORD_SELECT:&str="SELECT d.*,m.role AS member_role FROM drafts d LEFT JOIN team_members m ON m.team_id=d.team_id AND m.user_id=$1";
async fn find_draft(s: &AppState, uid: Uuid, id: Uuid) -> Result<DraftRecord> {
    let q = format!("{RECORD_SELECT} WHERE d.id=$2 AND (d.owner_id=$1 OR m.user_id IS NOT NULL)");
    let row = sqlx::query(&q)
        .bind(uid)
        .bind(id)
        .fetch_optional(&s.pool)
        .await?
        .ok_or_else(AppError::missing)?;
    record(row, uid)
}
#[derive(Deserialize, Default)]
pub struct DraftQuery {
    #[serde(default)]
    archived: bool,
    team_id: Option<Uuid>,
}
pub async fn drafts(
    State(s): State<AppState>,
    headers: HeaderMap,
    Query(q): Query<DraftQuery>,
) -> Result<Json<Vec<DraftRecord>>> {
    let u = auth::user(&s, &headers).await?;
    let query=format!("{RECORD_SELECT} WHERE (d.owner_id=$1 OR m.user_id IS NOT NULL) AND (d.archived_at IS NOT NULL)=$2 AND ($3::uuid IS NULL OR d.team_id=$3) ORDER BY d.updated_at DESC LIMIT 100");
    let rows = sqlx::query(&query)
        .bind(u.id)
        .bind(q.archived)
        .bind(q.team_id)
        .fetch_all(&s.pool)
        .await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| record(r, u.id))
            .collect::<Result<Vec<_>>>()?,
    ))
}
pub async fn get_draft(
    State(s): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<Uuid>,
) -> Result<Json<DraftRecord>> {
    let u = auth::user(&s, &headers).await?;
    Ok(Json(find_draft(&s, u.id, id).await?))
}
pub async fn create_draft(
    State(s): State<AppState>,
    headers: HeaderMap,
    Json(r): Json<SaveDraft>,
) -> Result<Json<DraftRecord>> {
    let u = auth::user(&s, &headers).await?;
    let c = load_catalog(&s, Some(&r.draft.patch_id)).await?;
    engine::validate(&r.draft, &c).map_err(AppError::bad)?;
    if let Some(id) = r.team_id {
        if !matches!(
            team_role(&s, id, u.id).await?.as_deref(),
            Some("owner" | "coach")
        ) {
            return Err(AppError::forbidden());
        }
    }
    let id = Uuid::new_v4();
    sqlx::query("INSERT INTO drafts(id,owner_id,team_id,patch_id,payload) VALUES($1,$2,$3,$4,$5)")
        .bind(id)
        .bind(u.id)
        .bind(r.team_id)
        .bind(&r.draft.patch_id)
        .bind(serde_json::to_value(&r.draft).unwrap())
        .execute(&s.pool)
        .await?;
    Ok(Json(find_draft(&s, u.id, id).await?))
}
pub async fn update_draft(
    State(s): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<Uuid>,
    Json(r): Json<SaveDraft>,
) -> Result<Json<DraftRecord>> {
    let u = auth::user(&s, &headers).await?;
    let prior = find_draft(&s, u.id, id).await?;
    if !prior.can_edit {
        return Err(AppError::forbidden());
    }
    if r.team_id != prior.team_id {
        return Err(AppError::bad(
            "Use Save a copy to move a draft to another workspace.",
        ));
    }
    if prior.archived {
        return Err(AppError::bad("Restore this draft before editing."));
    }
    let expected = r
        .expected_revision
        .ok_or_else(|| AppError::bad("Expected revision is required for updates."))?;
    let c = load_catalog(&s, Some(&r.draft.patch_id)).await?;
    engine::validate(&r.draft, &c).map_err(AppError::bad)?;
    let result=sqlx::query("UPDATE drafts SET payload=$1,patch_id=$2,revision=revision+1,updated_at=now() WHERE id=$3 AND revision=$4 AND archived_at IS NULL AND (owner_id=$5 OR EXISTS(SELECT 1 FROM team_members WHERE team_id=drafts.team_id AND user_id=$5 AND role IN ('owner','coach')))").bind(serde_json::to_value(&r.draft).unwrap()).bind(&r.draft.patch_id).bind(id).bind(expected).bind(u.id).execute(&s.pool).await?;
    if result.rows_affected() == 0 {
        return Err(AppError(
            StatusCode::CONFLICT,
            "This draft changed on another device. Refresh it, or save your work as a copy.".into(),
        ));
    }
    Ok(Json(find_draft(&s, u.id, id).await?))
}
#[derive(Deserialize)]
pub struct Archive {
    pub archived: bool,
    pub expected_revision: i64,
}
pub async fn archive_draft(
    State(s): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<Uuid>,
    Json(r): Json<Archive>,
) -> Result<Json<DraftRecord>> {
    let u = auth::user(&s, &headers).await?;
    let prior = find_draft(&s, u.id, id).await?;
    if !prior.can_edit {
        return Err(AppError::forbidden());
    }
    let result=sqlx::query("UPDATE drafts SET archived_at=CASE WHEN $1 THEN now() ELSE NULL END,revision=revision+1,updated_at=now() WHERE id=$2 AND revision=$3 AND (owner_id=$4 OR EXISTS(SELECT 1 FROM team_members WHERE team_id=drafts.team_id AND user_id=$4 AND role IN ('owner','coach')))").bind(r.archived).bind(id).bind(r.expected_revision).bind(u.id).execute(&s.pool).await?;
    if result.rows_affected() == 0 {
        return Err(AppError(
            StatusCode::CONFLICT,
            "Draft changed. Refresh before archiving or restoring.".into(),
        ));
    }
    Ok(Json(find_draft(&s, u.id, id).await?))
}
