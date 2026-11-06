pub mod auth;
pub mod engine;
pub mod handlers;
pub mod models;

use axum::{
    http::{HeaderValue, Method, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post, put},
    Json, Router,
};
use sqlx::PgPool;
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::Instant,
};
use tower_http::{cors::CorsLayer, trace::TraceLayer};

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub login_limits: Arc<Mutex<HashMap<String, (Instant, u32)>>>,
}
impl AppState {
    pub fn new(pool: PgPool) -> Self {
        Self {
            pool,
            login_limits: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}
pub struct AppError(pub StatusCode, pub String);
impl AppError {
    pub fn bad(s: impl Into<String>) -> Self {
        Self(StatusCode::BAD_REQUEST, s.into())
    }
    pub fn forbidden() -> Self {
        Self(
            StatusCode::FORBIDDEN,
            "You do not have permission for this workspace.".into(),
        )
    }
    pub fn missing() -> Self {
        Self(StatusCode::NOT_FOUND, "Not found.".into())
    }
    pub fn auth() -> Self {
        Self(
            StatusCode::UNAUTHORIZED,
            "Sign in again to continue.".into(),
        )
    }
}
impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        (self.0, Json(serde_json::json!({"error":self.1}))).into_response()
    }
}
impl From<sqlx::Error> for AppError {
    fn from(e: sqlx::Error) -> Self {
        tracing::error!(error=%e,"database operation failed");
        Self(
            StatusCode::INTERNAL_SERVER_ERROR,
            "A database operation failed. Please try again.".into(),
        )
    }
}
pub type Result<T> = std::result::Result<T, AppError>;
pub async fn migrate_and_seed(
    pool: &PgPool,
) -> std::result::Result<(), Box<dyn std::error::Error + Send + Sync>> {
    sqlx::migrate!("./migrations").run(pool).await?;
    let c: models::Catalog = serde_json::from_str(include_str!("../../data/catalog.json"))?;
    sqlx::query(
        "INSERT INTO catalogs(patch_id,payload) VALUES($1,$2) ON CONFLICT(patch_id) DO NOTHING",
    )
    .bind(&c.patch.id)
    .bind(serde_json::to_value(&c)?)
    .execute(pool)
    .await?;
    Ok(())
}
pub fn app(state: AppState, origins: Vec<HeaderValue>) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(origins)
        .allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE])
        .allow_headers([
            axum::http::header::AUTHORIZATION,
            axum::http::header::CONTENT_TYPE,
        ]);
    Router::new()
        .route("/health", get(handlers::health))
        .route("/v1/catalog", get(handlers::catalog))
        .route("/v1/analyze", post(handlers::analyze))
        .route("/v1/auth/register", post(auth::register))
        .route("/v1/auth/login", post(auth::login))
        .route("/v1/auth/me", get(auth::me))
        .route("/v1/auth/logout", post(auth::logout))
        .route(
            "/v1/teams",
            get(handlers::teams).post(handlers::create_team),
        )
        .route("/v1/teams/{id}/invites", post(handlers::invite))
        .route("/v1/teams/join", post(handlers::join))
        .route(
            "/v1/drafts",
            get(handlers::drafts).post(handlers::create_draft),
        )
        .route(
            "/v1/drafts/{id}",
            get(handlers::get_draft).put(handlers::update_draft),
        )
        .route("/v1/drafts/{id}/archive", put(handlers::archive_draft))
        .fallback(|| async {
            (
                StatusCode::NOT_FOUND,
                Json(serde_json::json!({"error":"API route not found."})),
            )
        })
        .layer(axum::extract::DefaultBodyLimit::max(131072))
        .layer(cors)
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}
