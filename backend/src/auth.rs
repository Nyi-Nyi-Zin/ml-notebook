use crate::{models::*, AppError, AppState, Result};
use argon2::{
    password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use axum::{
    extract::{ConnectInfo, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use rand::{rngs::OsRng, RngCore};
use sha2::{Digest, Sha256};
use sqlx::Row;
use std::{
    net::SocketAddr,
    time::{Duration, Instant},
};
use uuid::Uuid;

pub fn token() -> String {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    hex::encode(bytes)
}
pub fn hash_token(t: &str) -> String {
    hex::encode(Sha256::digest(t.as_bytes()))
}
fn bearer(headers: &HeaderMap) -> Result<&str> {
    headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .filter(|t| t.len() == 64 && t.bytes().all(|b| b.is_ascii_hexdigit()))
        .ok_or_else(AppError::auth)
}
pub async fn user(s: &AppState, h: &HeaderMap) -> Result<User> {
    let token = bearer(h)?;
    let r=sqlx::query("SELECT u.id,u.email,u.display_name FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=$1 AND s.expires_at>now()")
        .bind(hash_token(token)).fetch_optional(&s.pool).await?.ok_or_else(AppError::auth)?;
    Ok(User {
        id: r.get("id"),
        email: r.get("email"),
        display_name: r.get("display_name"),
    })
}
fn rate_limit(s: &AppState, key: String) -> Result<()> {
    let mut limits = s
        .login_limits
        .lock()
        .map_err(|_| AppError(StatusCode::SERVICE_UNAVAILABLE, "Try again shortly.".into()))?;
    limits.retain(|_, (at, _)| at.elapsed() < Duration::from_secs(60));
    let entry = limits.entry(key).or_insert((Instant::now(), 0));
    entry.1 += 1;
    if entry.1 > 15 {
        return Err(AppError(
            StatusCode::TOO_MANY_REQUESTS,
            "Too many sign-in attempts. Wait one minute.".into(),
        ));
    }
    Ok(())
}
fn email(value: &str) -> Result<String> {
    let e = value.trim().to_lowercase();
    if e.len() > 254
        || e.len() < 5
        || e.matches('@').count() != 1
        || !e.split('@').next_back().unwrap_or("").contains('.')
        || e.chars().any(char::is_whitespace)
    {
        return Err(AppError::bad("Enter a valid email address."));
    }
    Ok(e)
}
async fn session(s: &AppState, user: User) -> Result<AuthResponse> {
    let token = token();
    sqlx::query("DELETE FROM sessions WHERE user_id=$1 AND expires_at<=now()")
        .bind(user.id)
        .execute(&s.pool)
        .await?;
    sqlx::query("INSERT INTO sessions(token_hash,user_id,expires_at) VALUES($1,$2,now()+interval '14 days')").bind(hash_token(&token)).bind(user.id).execute(&s.pool).await?;
    Ok(AuthResponse { token, user })
}
pub async fn register(
    State(s): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(r): Json<RegisterRequest>,
) -> Result<Json<AuthResponse>> {
    rate_limit(&s, format!("register:{}", addr.ip()))?;
    let email = email(&r.email)?;
    let display_name = r.display_name.trim().to_owned();
    if display_name.is_empty() || display_name.chars().count() > 60 {
        return Err(AppError::bad("Name must be 1–60 characters."));
    }
    if r.password.chars().count() < 10 || r.password.len() > 256 {
        return Err(AppError::bad("Password must be 10–256 characters."));
    }
    let password_hash = tokio::task::spawn_blocking(move || {
        Argon2::default()
            .hash_password(r.password.as_bytes(), &SaltString::generate(&mut OsRng))
            .map(|v| v.to_string())
    })
    .await
    .map_err(|_| AppError::bad("Could not create the account."))?
    .map_err(|_| AppError::bad("Could not create the account."))?;
    let u = User {
        id: Uuid::new_v4(),
        email,
        display_name,
    };
    let inserted =
        sqlx::query("INSERT INTO users(id,email,display_name,password_hash) VALUES($1,$2,$3,$4)")
            .bind(u.id)
            .bind(&u.email)
            .bind(&u.display_name)
            .bind(password_hash)
            .execute(&s.pool)
            .await;
    if let Err(e) = inserted {
        if e.as_database_error()
            .is_some_and(|e| e.is_unique_violation())
        {
            return Err(AppError(
                StatusCode::CONFLICT,
                "This email is already registered.".into(),
            ));
        }
        return Err(e.into());
    }
    Ok(Json(session(&s, u).await?))
}
pub async fn login(
    State(s): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    Json(r): Json<LoginRequest>,
) -> Result<Json<AuthResponse>> {
    rate_limit(&s, format!("login:{}", addr.ip()))?;
    let email = email(&r.email)?;
    if r.password.len() > 256 {
        return Err(AppError::auth());
    }
    let row = sqlx::query("SELECT id,email,display_name,password_hash FROM users WHERE email=$1")
        .bind(email)
        .fetch_optional(&s.pool)
        .await?;
    let hash: Option<String> = row.as_ref().map(|r| r.get("password_hash"));
    let valid = tokio::task::spawn_blocking(move || {
        let dummy;
        let hash = if let Some(h) = hash {
            h
        } else {
            dummy = Argon2::default()
                .hash_password(
                    b"dummy account verification",
                    &SaltString::generate(&mut OsRng),
                )
                .map(|v| v.to_string())
                .unwrap_or_default();
            dummy
        };
        PasswordHash::new(&hash).ok().is_some_and(|parsed| {
            Argon2::default()
                .verify_password(r.password.as_bytes(), &parsed)
                .is_ok()
        })
    })
    .await
    .unwrap_or(false);
    if !valid {
        return Err(AppError(
            StatusCode::UNAUTHORIZED,
            "Email or password is incorrect.".into(),
        ));
    }
    let row = row.ok_or_else(AppError::auth)?;
    let u = User {
        id: row.get("id"),
        email: row.get("email"),
        display_name: row.get("display_name"),
    };
    Ok(Json(session(&s, u).await?))
}
pub async fn me(State(s): State<AppState>, headers: HeaderMap) -> Result<Json<User>> {
    Ok(Json(user(&s, &headers).await?))
}
pub async fn logout(State(s): State<AppState>, headers: HeaderMap) -> Result<StatusCode> {
    let token = bearer(&headers)?;
    sqlx::query("DELETE FROM sessions WHERE token_hash=$1")
        .bind(hash_token(token))
        .execute(&s.pool)
        .await?;
    Ok(StatusCode::NO_CONTENT)
}
