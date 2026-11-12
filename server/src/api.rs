//! HTTP API, CSRF guard, security headers and static frontend serving.

use axum::extract::{Path, Request, State};
use axum::http::header::{HeaderName, HeaderValue, CACHE_CONTROL, HOST, ORIGIN, SET_COOKIE};
use axum::http::{HeaderMap, Method, StatusCode};
use axum::middleware::{self, Next};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use rusqlite::{params, OptionalExtension};
use serde::Deserialize;
use serde_json::{json, Value};
use tower_http::services::{ServeDir, ServeFile};
use tower_http::set_header::SetResponseHeaderLayer;

use crate::auth::{self, AuthUser, SetupTokenCheck};
use crate::devices;
use crate::error::ApiError;
use crate::events::Event;
use crate::policy::{self, Action, Decision, Role};
use crate::{hwdiag, now, ws, AppState};

const CSP: &str = "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; \
                   connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'";

pub fn router(state: AppState) -> Router {
    let index = state.web_dir.join("index.html");
    let static_files = ServeDir::new(&state.web_dir).fallback(ServeFile::new(index));

    let api = Router::new()
        .route("/health", get(health))
        .route("/setup", post(setup))
        .route("/login", post(login))
        .route("/logout", post(logout))
        .route("/me", get(me))
        .route("/devices", get(list_devices))
        .route("/devices/{id}/actions", post(device_action))
        .route("/server/metrics", get(server_metrics))
        .route("/server/hardware", get(server_hardware))
        .route("/audit", get(audit_log))
        .route("/ws", get(ws::ws_handler))
        .fallback(|| async { ApiError::NotFound })
        .layer(middleware::from_fn(api_guard));

    let header = |name: &'static str, value: &'static str| {
        SetResponseHeaderLayer::if_not_present(
            HeaderName::from_static(name),
            HeaderValue::from_static(value),
        )
    };

    Router::new()
        .nest("/api", api)
        .fallback_service(static_files)
        .layer(header("content-security-policy", CSP))
        .layer(header("x-content-type-options", "nosniff"))
        .layer(header("x-frame-options", "DENY"))
        .layer(header("referrer-policy", "no-referrer"))
        .with_state(state)
}

/// True when the request's Origin (if any) names the same host it was sent to.
pub fn same_origin(headers: &HeaderMap, require_origin: bool) -> bool {
    let Some(origin) = headers.get(ORIGIN).and_then(|v| v.to_str().ok()) else {
        return !require_origin;
    };
    let host = headers.get(HOST).and_then(|v| v.to_str().ok());
    let origin_host = origin
        .strip_prefix("https://")
        .or_else(|| origin.strip_prefix("http://"));
    origin_host.is_some() && origin_host == host
}

/// CSRF defence for state-changing requests (on top of SameSite=Strict
/// cookies), and no caching of API responses.
async fn api_guard(req: Request, next: Next) -> Response {
    let safe = matches!(*req.method(), Method::GET | Method::HEAD | Method::OPTIONS);
    if !safe && !same_origin(req.headers(), false) {
        return ApiError::Forbidden("Cross-origin request rejected.".into()).into_response();
    }
    let mut res = next.run(req).await;
    res.headers_mut()
        .insert(CACHE_CONTROL, HeaderValue::from_static("no-store"));
    res
}

async fn health(State(s): State<AppState>) -> Json<Value> {
    Json(json!({
        "status": "ok",
        "setup_required": s.setup_required(),
        "version": env!("CARGO_PKG_VERSION"),
    }))
}

// ---- first-run setup --------------------------------------------------------

#[derive(Deserialize)]
struct SetupReq {
    setup_token: String,
    username: String,
    password: String,
}

async fn setup(State(s): State<AppState>, Json(req): Json<SetupReq>) -> Result<Response, ApiError> {
    if !s.setup_required() {
        return Err(ApiError::Conflict(
            "Setup has already been completed.".into(),
        ));
    }
    // One shared limiter for all setup attempts: the token cannot be guessed
    // at speed, whoever is guessing.
    if let Some(wait) = s.limiter.locked_for(auth::SETUP_LIMIT_KEY) {
        return Err(ApiError::TooManyRequests(wait));
    }
    let supplied = req.setup_token.trim().to_string();
    let check =
        s.db.call(move |c| auth::check_setup_token(c, &supplied))
            .await?;
    let denial = match check {
        SetupTokenCheck::Valid => None,
        SetupTokenCheck::NotIssued => {
            Some("No setup token has been issued. Run `home-ai setup-token` on the server.")
        }
        SetupTokenCheck::Expired => Some(
            "The setup token has expired. Run `home-ai setup-token` on the server for a new one.",
        ),
        SetupTokenCheck::Wrong => Some("Setup token is not valid."),
    };
    if let Some(message) = denial {
        s.limiter.record_failure(auth::SETUP_LIMIT_KEY);
        s.audit(None, "setup", None, "denied", Some("setup token rejected"))
            .await;
        return Err(ApiError::Forbidden(message.into()));
    }
    let username = req.username.trim().to_string();
    auth::validate_username(&username)?;
    auth::validate_password(&req.password)?;

    let password = req.password;
    let hash = tokio::task::spawn_blocking(move || auth::hash_password(&password))
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))??;

    // Atomic: the admin is created only if the users table is still empty.
    let uname = username.clone();
    let created =
        s.db.call(move |c| {
            let tx = c.transaction()?;
            let created = tx.execute(
                "INSERT INTO users (username, password_hash, role, created_at)
                 SELECT ?1, ?2, 'admin', ?3 WHERE NOT EXISTS (SELECT 1 FROM users)",
                params![uname, hash, now()],
            )?;
            // The token dies in the same transaction that creates the admin.
            auth::clear_setup_token(&tx)?;
            tx.commit()?;
            Ok(created)
        })
        .await?;
    s.mark_setup_done();
    s.limiter.clear(auth::SETUP_LIMIT_KEY);
    if created == 0 {
        return Err(ApiError::Conflict(
            "Setup has already been completed.".into(),
        ));
    }
    s.audit(
        Some(&username),
        "setup",
        None,
        "ok",
        Some("administrator created"),
    )
    .await;
    Ok((StatusCode::CREATED, Json(json!({ "ok": true }))).into_response())
}

// ---- sessions ---------------------------------------------------------------

#[derive(Deserialize)]
struct LoginReq {
    username: String,
    password: String,
}

async fn login(State(s): State<AppState>, Json(req): Json<LoginReq>) -> Result<Response, ApiError> {
    let username = req.username.trim().to_string();
    let key = username.to_lowercase();
    if let Some(wait) = s.limiter.locked_for(&key) {
        return Err(ApiError::TooManyRequests(wait));
    }

    let lookup = username.clone();
    let row: Option<(i64, String, String, String)> =
        s.db.call(move |c| {
            c.prepare_cached(
                "SELECT id, username, password_hash, role FROM users WHERE username = ?1",
            )?
            .query_row([lookup], |r| {
                Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))
            })
            .optional()
        })
        .await?;

    let hash = row
        .as_ref()
        .map(|r| r.2.clone())
        .unwrap_or_else(|| auth::dummy_hash().to_string());
    let password = req.password;
    let password_ok = tokio::task::spawn_blocking(move || auth::verify_password(&password, &hash))
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;

    let user = match (row, password_ok) {
        (Some((id, name, _, role)), true) => (id, name, role),
        _ => {
            s.limiter.record_failure(&key);
            s.audit(Some(&username), "login", None, "denied", None)
                .await;
            return Err(ApiError::InvalidCredentials);
        }
    };
    s.limiter.clear(&key);

    // A fresh token on every login: no session fixation.
    let token = auth::new_token();
    let hash = auth::token_hash(&token);
    let uid = user.0;
    s.db.call(move |c| {
        c.execute(
            "INSERT INTO sessions (token_hash, user_id, created_at, expires_at)
             VALUES (?1, ?2, ?3, ?4)",
            params![hash, uid, now(), now() + auth::SESSION_TTL_S],
        )
    })
    .await?;
    s.audit(Some(&user.1), "login", None, "ok", None).await;

    Ok((
        [(SET_COOKIE, auth::session_cookie(&token))],
        Json(json!({ "username": user.1, "role": user.2 })),
    )
        .into_response())
}

async fn logout(State(s): State<AppState>, user: AuthUser) -> Result<Response, ApiError> {
    let hash = user.token_hash.clone();
    s.db.call(move |c| c.execute("DELETE FROM sessions WHERE token_hash = ?1", [hash]))
        .await?;
    s.audit(Some(&user.username), "logout", None, "ok", None)
        .await;
    Ok((
        [(SET_COOKIE, auth::clear_cookie())],
        Json(json!({ "ok": true })),
    )
        .into_response())
}

async fn me(user: AuthUser) -> Json<Value> {
    Json(json!({ "username": user.username, "role": user.role }))
}

// ---- devices ----------------------------------------------------------------

async fn list_devices(State(s): State<AppState>, _user: AuthUser) -> Result<Json<Value>, ApiError> {
    let list = s.db.call(|c| devices::list(c)).await?;
    Ok(Json(json!({ "devices": list })))
}

#[derive(Deserialize)]
struct ActionReq {
    #[serde(flatten)]
    action: Action,
    /// Step-up confirmation for high-risk actions. Never logged.
    confirm_password: Option<String>,
}

/// authenticate → resolve device → validate capability and inputs → policy →
/// step-up if needed → connector → persist → read back → publish → audit.
async fn device_action(
    State(s): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(req): Json<ActionReq>,
) -> Result<Json<Value>, ApiError> {
    let action = req.action;
    let action_name = action.name();

    let lookup = id.clone();
    let device =
        s.db.call(move |c| devices::get(c, &lookup))
            .await?
            .ok_or(ApiError::NotFound)?;

    policy::validate(device.kind, &action).map_err(ApiError::BadRequest)?;

    match policy::evaluate(user.role, &action) {
        Decision::Allow => {}
        Decision::Deny(reason) => {
            s.audit(
                Some(&user.username),
                action_name,
                Some(&id),
                "denied",
                Some(reason),
            )
            .await;
            return Err(ApiError::Forbidden(reason.into()));
        }
        Decision::RequireStepUp => {
            let Some(password) = req.confirm_password else {
                return Err(ApiError::StepUpRequired);
            };
            if !verify_current_password(&s, &user, password).await? {
                s.audit(
                    Some(&user.username),
                    action_name,
                    Some(&id),
                    "denied",
                    Some("step-up password wrong"),
                )
                .await;
                return Err(ApiError::Forbidden("Password confirmation failed.".into()));
            }
        }
    }

    let connector = s
        .connectors
        .get(device.connector.as_str())
        .ok_or_else(|| ApiError::Internal(format!("no connector '{}'", device.connector)))?;

    match connector.execute(&device, &action) {
        Err(reason) => {
            s.audit(
                Some(&user.username),
                action_name,
                Some(&id),
                "failed",
                Some(&reason),
            )
            .await;
            Ok(Json(
                json!({ "outcome": "failed", "reason": reason, "device": device }),
            ))
        }
        Ok(new_state) => {
            let lookup = id.clone();
            let updated =
                s.db.call(move |c| {
                    devices::set_state(c, &lookup, &new_state, now())?;
                    devices::get(c, &lookup)
                })
                .await?
                .ok_or(ApiError::NotFound)?;
            s.bus.publish(Event::DeviceState {
                device: updated.clone(),
            });
            s.audit(
                Some(&user.username),
                action_name,
                Some(&id),
                "confirmed",
                None,
            )
            .await;
            Ok(Json(json!({ "outcome": "confirmed", "device": updated })))
        }
    }
}

async fn verify_current_password(
    s: &AppState,
    user: &AuthUser,
    password: String,
) -> Result<bool, ApiError> {
    let key = format!("stepup:{}", user.id);
    if let Some(wait) = s.limiter.locked_for(&key) {
        return Err(ApiError::TooManyRequests(wait));
    }
    let uid = user.id;
    let hash: String =
        s.db.call(move |c| {
            c.query_row(
                "SELECT password_hash FROM users WHERE id = ?1",
                [uid],
                |r| r.get(0),
            )
        })
        .await?;
    let ok = tokio::task::spawn_blocking(move || auth::verify_password(&password, &hash))
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;
    if ok {
        s.limiter.clear(&key);
    } else {
        s.limiter.record_failure(&key);
    }
    Ok(ok)
}

// ---- server administration ---------------------------------------------------

async fn server_metrics(
    State(s): State<AppState>,
    user: AuthUser,
) -> Result<Json<Value>, ApiError> {
    user.require_admin()?;
    let st = s.clone();
    let snap = tokio::task::spawn_blocking(move || st.metrics.collect())
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;
    Ok(Json(json!({ "metrics": snap })))
}

async fn server_hardware(user: AuthUser) -> Result<Json<Value>, ApiError> {
    user.require_admin()?;
    let report = tokio::task::spawn_blocking(hwdiag::collect)
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?;
    Ok(Json(json!({ "hardware": report })))
}

async fn audit_log(State(s): State<AppState>, user: AuthUser) -> Result<Json<Value>, ApiError> {
    user.require_admin()?;
    let rows =
        s.db.call(|c| {
            let mut stmt = c.prepare_cached(
                "SELECT id, ts, username, action, target, outcome, detail
                 FROM audit_log ORDER BY id DESC LIMIT 200",
            )?;
            let rows = stmt.query_map([], |r| {
                Ok(json!({
                    "id": r.get::<_, i64>(0)?,
                    "ts": r.get::<_, i64>(1)?,
                    "username": r.get::<_, Option<String>>(2)?,
                    "action": r.get::<_, String>(3)?,
                    "target": r.get::<_, Option<String>>(4)?,
                    "outcome": r.get::<_, String>(5)?,
                    "detail": r.get::<_, Option<String>>(6)?,
                }))
            })?;
            rows.collect::<rusqlite::Result<Vec<Value>>>()
        })
        .await?;
    Ok(Json(json!({ "entries": rows })))
}

/// Used by tests and (later) the user-management API.
pub async fn create_user(
    s: &AppState,
    username: &str,
    password: &str,
    role: Role,
) -> Result<i64, ApiError> {
    auth::validate_username(username)?;
    auth::validate_password(password)?;
    let hash = auth::hash_password(password)?;
    let username = username.to_string();
    s.db.call(move |c| auth::create_user(c, &username, &hash, role))
        .await
}
