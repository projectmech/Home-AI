//! Passwords (Argon2id), opaque session tokens, login rate limiting and the
//! `AuthUser` extractor that every protected handler takes.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use argon2::password_hash::rand_core::OsRng;
use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use axum::extract::FromRequestParts;
use axum::http::header::COOKIE;
use axum::http::request::Parts;
use axum::http::HeaderMap;
use rand::RngCore;
use rusqlite::{params, Connection, OptionalExtension};
use sha2::{Digest, Sha256};

use crate::error::ApiError;
use crate::policy::Role;
use crate::AppState;

pub const SESSION_COOKIE: &str = "home_ai_session";
pub const SESSION_TTL_S: i64 = 12 * 60 * 60;
pub const MIN_PASSWORD_LEN: usize = 12;
const MAX_PASSWORD_LEN: usize = 256;

const MAX_FAILURES: u32 = 5;
const FAILURE_WINDOW: Duration = Duration::from_secs(300);
const LOCKOUT: Duration = Duration::from_secs(60);
const LIMITER_MAX_KEYS: usize = 10_000;

/// Argon2id with the crate's default parameters (v0x13, m=19 MiB, t=2, p=1).
pub fn hash_password(password: &str) -> Result<String, ApiError> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| ApiError::Internal(format!("hash: {e}")))
}

pub fn verify_password(password: &str, hash: &str) -> bool {
    PasswordHash::new(hash)
        .map(|parsed| {
            Argon2::default()
                .verify_password(password.as_bytes(), &parsed)
                .is_ok()
        })
        .unwrap_or(false)
}

/// A real hash to verify against when the username does not exist, so the
/// response time does not reveal which usernames are valid.
pub fn dummy_hash() -> &'static str {
    static DUMMY: OnceLock<String> = OnceLock::new();
    DUMMY.get_or_init(|| hash_password(&new_token()).expect("argon2 available"))
}

pub fn validate_username(u: &str) -> Result<(), ApiError> {
    let ok_len = (3..=64).contains(&u.chars().count());
    let ok_chars = u
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-' | '@'));
    if ok_len && ok_chars {
        Ok(())
    } else {
        Err(ApiError::BadRequest(
            "Username must be 3–64 characters: letters, digits, and . _ - @".into(),
        ))
    }
}

pub fn validate_password(p: &str) -> Result<(), ApiError> {
    let n = p.chars().count();
    if n < MIN_PASSWORD_LEN {
        return Err(ApiError::BadRequest(format!(
            "Password must be at least {MIN_PASSWORD_LEN} characters."
        )));
    }
    if n > MAX_PASSWORD_LEN {
        return Err(ApiError::BadRequest("Password is too long.".into()));
    }
    Ok(())
}

/// 256 bits from the OS RNG, hex-encoded.
pub fn new_token() -> String {
    let mut bytes = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    hex::encode(bytes)
}

/// Only the SHA-256 of a session token is stored, so a leaked database does
/// not contain usable sessions.
pub fn token_hash(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}

pub fn session_cookie(token: &str) -> String {
    format!(
        "{SESSION_COOKIE}={token}; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age={SESSION_TTL_S}"
    )
}

pub fn clear_cookie() -> String {
    format!("{SESSION_COOKIE}=; HttpOnly; Secure; SameSite=Strict; Path=/; Max-Age=0")
}

pub fn cookie_token(headers: &HeaderMap) -> Option<String> {
    headers
        .get_all(COOKIE)
        .iter()
        .filter_map(|v| v.to_str().ok())
        .flat_map(|v| v.split(';'))
        .filter_map(|pair| pair.trim().split_once('='))
        .find(|(k, _)| *k == SESSION_COOKIE)
        .map(|(_, v)| v.to_string())
        .filter(|v| v.len() == 64 && v.bytes().all(|b| b.is_ascii_hexdigit()))
}

// ---- one-time setup token ---------------------------------------------------

pub const SETUP_TOKEN_TTL_S: i64 = 60 * 60;
/// Rate-limit key shared by every setup attempt.
pub const SETUP_LIMIT_KEY: &str = "setup-token";
const SETUP_HASH_KEY: &str = "setup_token_hash";
const SETUP_EXPIRES_KEY: &str = "setup_token_expires";

/// Issue a fresh one-time setup token, replacing any earlier one. Only its
/// hash and expiry are stored. Returns `None` once an administrator exists.
///
/// This is reachable only from the `home-ai setup-token` command, which needs
/// write access to the database file: that is the "authorized local
/// administrative procedure". The server never issues a token by itself, so a
/// restart cannot reopen or re-key setup.
pub fn issue_setup_token(conn: &mut Connection) -> rusqlite::Result<Option<String>> {
    let tx = conn.transaction()?;
    let users: i64 = tx.query_row("SELECT COUNT(*) FROM users", [], |r| r.get(0))?;
    if users > 0 {
        return Ok(None);
    }
    let token = new_token();
    let expires = (crate::now() + SETUP_TOKEN_TTL_S).to_string();
    tx.execute(
        "INSERT OR REPLACE INTO settings (key, value) VALUES (?1, ?2)",
        params![SETUP_HASH_KEY, token_hash(&token)],
    )?;
    tx.execute(
        "INSERT OR REPLACE INTO settings (key, value) VALUES (?1, ?2)",
        params![SETUP_EXPIRES_KEY, expires],
    )?;
    tx.commit()?;
    Ok(Some(token))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SetupTokenCheck {
    Valid,
    NotIssued,
    Expired,
    Wrong,
}

fn setting(conn: &Connection, key: &str) -> rusqlite::Result<Option<String>> {
    conn.query_row("SELECT value FROM settings WHERE key = ?1", [key], |r| {
        r.get(0)
    })
    .optional()
}

pub fn check_setup_token(conn: &Connection, supplied: &str) -> rusqlite::Result<SetupTokenCheck> {
    use subtle::ConstantTimeEq;

    let Some(stored) = setting(conn, SETUP_HASH_KEY)? else {
        return Ok(SetupTokenCheck::NotIssued);
    };
    let expires: i64 = setting(conn, SETUP_EXPIRES_KEY)?
        .and_then(|v| v.parse().ok())
        .unwrap_or(0);
    if expires <= crate::now() {
        return Ok(SetupTokenCheck::Expired);
    }
    let supplied_hash = token_hash(supplied);
    Ok(
        if supplied_hash
            .as_bytes()
            .ct_eq(stored.as_bytes())
            .unwrap_u8()
            == 1
        {
            SetupTokenCheck::Valid
        } else {
            SetupTokenCheck::Wrong
        },
    )
}

/// Remove the token. Call inside the transaction that creates the admin.
pub fn clear_setup_token(conn: &Connection) -> rusqlite::Result<()> {
    conn.execute(
        "DELETE FROM settings WHERE key IN (?1, ?2)",
        params![SETUP_HASH_KEY, SETUP_EXPIRES_KEY],
    )?;
    Ok(())
}

pub fn create_user(
    conn: &Connection,
    username: &str,
    password_hash: &str,
    role: Role,
) -> rusqlite::Result<i64> {
    conn.execute(
        "INSERT INTO users (username, password_hash, role, created_at) VALUES (?1, ?2, ?3, ?4)",
        params![username, password_hash, role.as_str(), crate::now()],
    )?;
    Ok(conn.last_insert_rowid())
}

#[derive(Debug, Clone)]
pub struct AuthUser {
    pub id: i64,
    pub username: String,
    pub role: Role,
    pub token_hash: String,
}

impl AuthUser {
    pub fn require_admin(&self) -> Result<(), ApiError> {
        if self.role == Role::Admin {
            Ok(())
        } else {
            Err(ApiError::Forbidden("Administrator access required.".into()))
        }
    }
}

pub fn user_for_token_hash(conn: &Connection, hash: &str) -> rusqlite::Result<Option<AuthUser>> {
    conn.prepare_cached(
        "SELECT u.id, u.username, u.role FROM sessions s JOIN users u ON u.id = s.user_id
         WHERE s.token_hash = ?1 AND s.expires_at > ?2",
    )?
    .query_row(params![hash, crate::now()], |r| {
        let role: String = r.get(2)?;
        Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, role))
    })
    .optional()
    .map(|row| {
        row.and_then(|(id, username, role)| {
            Some(AuthUser {
                id,
                username,
                role: Role::parse(&role)?,
                token_hash: hash.to_string(),
            })
        })
    })
}

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> Result<Self, ApiError> {
        let token = cookie_token(&parts.headers).ok_or(ApiError::Unauthorized)?;
        let hash = token_hash(&token);
        state
            .db
            .call(move |c| user_for_token_hash(c, &hash))
            .await?
            .ok_or(ApiError::Unauthorized)
    }
}

/// In-memory failed-login limiter keyed by username. Five failures inside
/// five minutes lock that username for a minute. The lock is temporary and
/// the table is bounded, so it cannot be used to lock an account out for good
/// or to exhaust memory.
#[derive(Default)]
pub struct LoginLimiter {
    entries: Mutex<HashMap<String, Entry>>,
}

struct Entry {
    failures: u32,
    window_start: Instant,
    locked_until: Option<Instant>,
}

impl LoginLimiter {
    /// Seconds left on a lockout, if the key is locked.
    pub fn locked_for(&self, key: &str) -> Option<u64> {
        let map = self.entries.lock().unwrap_or_else(|e| e.into_inner());
        let until = map.get(key)?.locked_until?;
        let now = Instant::now();
        (until > now).then(|| (until - now).as_secs().max(1))
    }

    pub fn record_failure(&self, key: &str) {
        let mut map = self.entries.lock().unwrap_or_else(|e| e.into_inner());
        let now = Instant::now();
        if map.len() >= LIMITER_MAX_KEYS {
            map.retain(|_, e| e.locked_until.is_some_and(|u| u > now));
        }
        let e = map.entry(key.to_string()).or_insert(Entry {
            failures: 0,
            window_start: now,
            locked_until: None,
        });
        if now.duration_since(e.window_start) > FAILURE_WINDOW {
            e.failures = 0;
            e.window_start = now;
        }
        e.failures += 1;
        if e.failures >= MAX_FAILURES {
            e.locked_until = Some(now + LOCKOUT);
            e.failures = 0;
            e.window_start = now;
        }
    }

    pub fn clear(&self, key: &str) {
        self.entries
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .remove(key);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn argon2id_roundtrip() {
        let h = hash_password("correct horse battery").unwrap();
        assert!(h.starts_with("$argon2id$"));
        assert!(verify_password("correct horse battery", &h));
        assert!(!verify_password("wrong", &h));
        assert!(!verify_password("x", "not-a-hash"));
    }

    #[test]
    fn limiter_locks_after_five_failures() {
        let l = LoginLimiter::default();
        for _ in 0..4 {
            l.record_failure("a");
        }
        assert!(l.locked_for("a").is_none());
        l.record_failure("a");
        assert!(l.locked_for("a").is_some());
        assert!(l.locked_for("b").is_none());
    }

    #[test]
    fn cookie_parsing_rejects_malformed_tokens() {
        let mut h = HeaderMap::new();
        h.insert(COOKIE, "other=1; home_ai_session=zz".parse().unwrap());
        assert!(cookie_token(&h).is_none());
        let t = new_token();
        h.insert(
            COOKIE,
            format!("a=b; {SESSION_COOKIE}={t}").parse().unwrap(),
        );
        assert_eq!(cookie_token(&h), Some(t));
    }
}
