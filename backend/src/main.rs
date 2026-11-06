use draftroom_api::{app, migrate_and_seed, AppState};
use sqlx::postgres::PgPoolOptions;
use std::{net::SocketAddr, time::Duration};

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    dotenvy::dotenv().ok();
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "draftroom_api=info,tower_http=info".into()),
        )
        .init();
    let url =
        std::env::var("DATABASE_URL").map_err(|_| "DATABASE_URL is required. See .env.example.")?;
    let max_connections = std::env::var("DB_MAX_CONNECTIONS")
        .unwrap_or_else(|_| "10".into())
        .parse::<u32>()?;
    let pool = PgPoolOptions::new()
        .max_connections(max_connections)
        .acquire_timeout(Duration::from_secs(10))
        .connect(&url)
        .await?;
    migrate_and_seed(&pool).await?;
    let origins = std::env::var("APP_ORIGINS")
        .unwrap_or_else(|_| "http://localhost:5173,http://127.0.0.1:5173".into())
        .split(',')
        .filter(|s| !s.trim().is_empty())
        .map(|s| s.trim().parse())
        .collect::<Result<Vec<_>, _>>()?;
    let port = std::env::var("PORT").unwrap_or_else(|_| "8080".into());
    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{port}")).await?;
    tracing::info!(port=%port,"DraftRoom Rust API is ready");
    axum::serve(
        listener,
        app(AppState::new(pool.clone()), origins)
            .into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(async {
        tokio::signal::ctrl_c().await.ok();
    })
    .await?;
    pool.close().await;
    Ok(())
}
