//! Voice clients (phones, room units): one-time pairing, long-lived client
//! tokens, and the WebSocket they use to send audio and commands.
//!
//! A client is not a person. It acts with the `standard` role at most, so it
//! can never perform an administrator-only action, and voice can never unlock
//! (see `voice.rs`). Only the SHA-256 of the pairing code and of the client
//! token is stored. An administrator can revoke a client at any time; a revoked
//! client's open connection is closed within one heartbeat.

use std::time::Duration;

use axum::body::Bytes;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::{Path, State};
use axum::http::header::AUTHORIZATION;
use axum::http::HeaderMap;
use axum::response::Response;
use axum::routing::{delete, get, post};
use axum::{Json, Router};
use rand::RngCore;
use rusqlite::{params, Connection, OptionalExtension};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::api;
use crate::auth::{self, AuthUser};
use crate::error::ApiError;
use crate::policy::Role;
use crate::AppState;

/// Unambiguous characters only (no 0/O, 1/I): easy to read off a screen.
const CODE_ALPHABET: &[u8; 32] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LEN: usize = 10;
const PAIR_TTL_S: i64 = 600;
const PAIR_LIMIT_KEY: &str = "voice-pair";

/// Audio the host accepts: 16 kHz, 16-bit, mono, at most this many seconds
/// per utterance (about 470 KB).
pub const MAX_UTTERANCE_S: usize = 15;
const BYTES_PER_MS: usize = 32;
const MAX_UTTERANCE_BYTES: usize = MAX_UTTERANCE_S * 1000 * BYTES_PER_MS;
/// One WebSocket message (a chunk of audio or a JSON command).
const MAX_MESSAGE: usize = 64 * 1024;
const HEARTBEAT: Duration = Duration::from_secs(30);

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/voice/clients", get(list_clients).post(create_client))
        .route("/voice/clients/{id}", delete(revoke_client))
        .route("/voice/pair", post(pair))
        .route("/voice/stream", get(stream))
}

// ---- pairing codes --------------------------------------------------------

fn new_code_raw() -> String {
    let mut bytes = [0u8; CODE_LEN];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    bytes
        .iter()
        .map(|b| CODE_ALPHABET[(*b & 31) as usize] as char)
        .collect()
}

fn display_code(raw: &str) -> String {
    format!("{}-{}", &raw[..5], &raw[5..])
}

fn normalize_code(input: &str) -> Option<String> {
    let code: String = input
        .chars()
        .filter(|c| !c.is_whitespace() && *c != '-')
        .map(|c| c.to_ascii_uppercase())
        .collect();
    let ok = code.len() == CODE_LEN && code.bytes().all(|b| CODE_ALPHABET.contains(&b));
    ok.then_some(code)
}

// ---- administration (admin only) -------------------------------------------

#[derive(Deserialize)]
struct NewClientReq {
    name: String,
    room: String,
}

async fn create_client(
    State(s): State<AppState>,
    user: AuthUser,
    Json(req): Json<NewClientReq>,
) -> Result<Json<Value>, ApiError> {
    user.require_admin()?;
    let name = req.name.trim().to_string();
    let room = req.room.trim().to_string();
    let valid = |t: &str| (1..=40).contains(&t.chars().count());
    if !valid(&name) || !valid(&room) {
        let msg = "Name and room must be 1 to 40 characters.";
        return Err(ApiError::BadRequest(msg.into()));
    }
    let id = format!("vc-{}", &auth::new_token()[..12]);
    let raw = new_code_raw();
    let pair_hash = auth::token_hash(&raw);
    let created_by = user.username.clone();
    let (i, n, r) = (id.clone(), name.clone(), room.clone());
    s.db.call(move |c| {
        let now = crate::now();
        c.execute(
            "INSERT INTO voice_clients
             (id, name, room, pair_hash, pair_expires, created_by, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![i, n, r, pair_hash, now + PAIR_TTL_S, created_by, now],
        )
    })
    .await?;
    let who = Some(user.username.as_str());
    s.audit(who, "voice_client_create", Some(&id), "ok", None)
        .await;
    Ok(Json(json!({
        "id": id,
        "name": name,
        "room": room,
        "pairing_code": display_code(&raw),
        "expires_in_s": PAIR_TTL_S,
    })))
}

async fn list_clients(
    State(s): State<AppState>,
    user: AuthUser,
) -> Result<Json<Value>, ApiError> {
    user.require_admin()?;
    let clients = s
        .db
        .call(|c| {
            let mut stmt = c.prepare(
                "SELECT id, name, room, paired_at, last_seen, revoked,
                        (pair_hash IS NOT NULL AND COALESCE(pair_expires, 0) > ?1)
                 FROM voice_clients ORDER BY created_at DESC",
            )?;
            let rows = stmt.query_map([crate::now()], |r| {
                let paired_at: Option<i64> = r.get(3)?;
                Ok(json!({
                    "id": r.get::<_, String>(0)?,
                    "name": r.get::<_, String>(1)?,
                    "room": r.get::<_, String>(2)?,
                    "paired": paired_at.is_some(),
                    "last_seen": r.get::<_, Option<i64>>(4)?,
                    "revoked": r.get::<_, bool>(5)?,
                    "pairing_open": r.get::<_, bool>(6)?,
                }))
            })?;
            rows.collect::<rusqlite::Result<Vec<Value>>>()
        })
        .await?;
    Ok(Json(json!({ "clients": clients })))
}

async fn revoke_client(
    State(s): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> Result<Json<Value>, ApiError> {
    user.require_admin()?;
    let lookup = id.clone();
    let changed = s
        .db
        .call(move |c| {
            c.execute(
                "UPDATE voice_clients
                 SET revoked = 1, token_hash = NULL, pair_hash = NULL, pair_expires = NULL
                 WHERE id = ?1",
                [lookup],
            )
        })
        .await?;
    if changed == 0 {
        return Err(ApiError::NotFound);
    }
    let who = Some(user.username.as_str());
    s.audit(who, "voice_client_revoke", Some(&id), "ok", None)
        .await;
    Ok(Json(json!({ "ok": true })))
}

// ---- pairing (the client itself, with the one-time code) --------------------

#[derive(Deserialize)]
struct PairReq {
    code: String,
}

/// Trade a valid one-time code for the client's long-lived token. The token is
/// returned once and never stored in readable form.
async fn pair(
    State(s): State<AppState>,
    Json(req): Json<PairReq>,
) -> Result<Json<Value>, ApiError> {
    if let Some(wait) = s.limiter.locked_for(PAIR_LIMIT_KEY) {
        return Err(ApiError::TooManyRequests(wait));
    }
    let wrong = || ApiError::Forbidden("Wrong or expired pairing code.".into());
    let Some(raw) = normalize_code(&req.code) else {
        s.limiter.record_failure(PAIR_LIMIT_KEY);
        return Err(wrong());
    };
    let pair_hash = auth::token_hash(&raw);
    let token = auth::new_token();
    let token_hash = auth::token_hash(&token);
    let found = s
        .db
        .call(move |c| {
            let tx = c.transaction()?;
            let now = crate::now();
            let row: Option<(String, String, String)> = tx
                .query_row(
                    "SELECT id, name, room FROM voice_clients
                     WHERE pair_hash = ?1 AND pair_expires > ?2 AND revoked = 0",
                    params![pair_hash, now],
                    |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
                )
                .optional()?;
            if let Some((id, _, _)) = &row {
                tx.execute(
                    "UPDATE voice_clients
                     SET token_hash = ?2, pair_hash = NULL, pair_expires = NULL,
                         paired_at = ?3, last_seen = ?3
                     WHERE id = ?1",
                    params![id, token_hash, now],
                )?;
            }
            tx.commit()?;
            Ok(row)
        })
        .await?;
    let Some((id, name, room)) = found else {
        s.limiter.record_failure(PAIR_LIMIT_KEY);
        return Err(wrong());
    };
    s.limiter.clear(PAIR_LIMIT_KEY);
    let who = format!("voice:{name}");
    s.audit(Some(&who), "voice_client_pair", Some(&id), "ok", None)
        .await;
    Ok(Json(json!({
        "client_id": id,
        "name": name,
        "room": room,
        "token": token,
    })))
}

// ---- the audio and command WebSocket -----------------------------------------

#[derive(Clone)]
struct VoiceClient {
    id: String,
    name: String,
    room: String,
    token_hash: String,
}

/// Look the client up by its token hash and note that it was seen.
fn client_for_hash(conn: &Connection, hash: &str) -> rusqlite::Result<Option<VoiceClient>> {
    let row: Option<(String, String, String)> = conn
        .query_row(
            "SELECT id, name, room FROM voice_clients WHERE token_hash = ?1 AND revoked = 0",
            [hash],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .optional()?;
    if let Some((id, _, _)) = &row {
        conn.execute(
            "UPDATE voice_clients SET last_seen = ?2 WHERE id = ?1",
            params![id, crate::now()],
        )?;
    }
    Ok(row.map(|(id, name, room)| VoiceClient {
        id,
        name,
        room,
        token_hash: hash.to_string(),
    }))
}

/// The speech recogniser. None is installed yet, so audio is received, bounded
/// and measured but not understood; a client with its own recogniser sends
/// `{"type":"command","text":...}` instead. This is the single hook where the
/// local recogniser (see docs/adr/0005-voice-architecture.md) will plug in.
fn recognise(_pcm: &[u8]) -> Option<String> {
    None
}

/// Clients are not browsers: they authenticate with `Authorization: Bearer
/// <client token>`, which a web page cannot set on a WebSocket, so a website
/// cannot ride on a client.
async fn stream(
    State(s): State<AppState>,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Result<Response, ApiError> {
    let token = headers
        .get(AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.strip_prefix("Bearer "))
        .map(str::trim)
        .filter(|t| t.len() == 64 && t.bytes().all(|b| b.is_ascii_hexdigit()))
        .ok_or(ApiError::Unauthorized)?;
    let hash = auth::token_hash(token);
    let client = s
        .db
        .call(move |c| client_for_hash(c, &hash))
        .await?
        .ok_or(ApiError::Unauthorized)?;
    Ok(ws
        .max_message_size(MAX_MESSAGE)
        .max_frame_size(MAX_MESSAGE)
        .on_upgrade(move |socket| client_loop(socket, s, client)))
}

async fn client_loop(mut socket: WebSocket, s: AppState, client: VoiceClient) {
    let user = AuthUser {
        id: 0,
        username: format!("voice:{}", client.name),
        role: Role::Standard,
        token_hash: String::new(),
    };
    let ready = json!({
        "type": "ready",
        "client": client.name,
        "room": client.room,
        "audio": {
            "format": "pcm_s16le",
            "rate_hz": 16000,
            "channels": 1,
            "max_utterance_s": MAX_UTTERANCE_S,
        },
    });
    if socket
        .send(Message::Text(ready.to_string().into()))
        .await
        .is_err()
    {
        return;
    }

    let mut pcm: Vec<u8> = Vec::new();
    let mut overflow = false;
    let mut heartbeat = tokio::time::interval(HEARTBEAT);
    heartbeat.tick().await; // the first tick fires immediately

    loop {
        tokio::select! {
            incoming = socket.recv() => {
                let Some(Ok(msg)) = incoming else { break };
                match msg {
                    Message::Binary(chunk) => {
                        if pcm.len() + chunk.len() > MAX_UTTERANCE_BYTES {
                            overflow = true;
                        } else if !overflow {
                            pcm.extend_from_slice(&chunk);
                        }
                    }
                    Message::Text(text) => {
                        let reply = on_text(&s, &user, text.as_str(), &mut pcm, &mut overflow).await;
                        if socket.send(Message::Text(reply.to_string().into())).await.is_err() {
                            break;
                        }
                    }
                    Message::Close(_) => break,
                    _ => {}
                }
            }
            _ = heartbeat.tick() => {
                // A revoked client is dropped here; this also updates last_seen.
                let hash = client.token_hash.clone();
                let still_valid = s
                    .db
                    .call(move |c| client_for_hash(c, &hash))
                    .await
                    .ok()
                    .flatten()
                    .is_some();
                if !still_valid || socket.send(Message::Ping(Bytes::new())).await.is_err() {
                    break;
                }
            }
        }
    }
    let _ = socket.send(Message::Close(None)).await;
    tracing::debug!(client = %client.id, "voice client disconnected");
}

async fn on_text(
    s: &AppState,
    user: &AuthUser,
    text: &str,
    pcm: &mut Vec<u8>,
    overflow: &mut bool,
) -> Value {
    let Ok(msg) = serde_json::from_str::<Value>(text) else {
        return json!({ "type": "error", "message": "Messages must be JSON." });
    };
    match msg["type"].as_str() {
        Some("command") => {
            let said = msg["text"].as_str().unwrap_or("");
            command_reply(s, user, said).await
        }
        Some("end") => {
            let audio = std::mem::take(pcm);
            let too_long = std::mem::take(overflow);
            if too_long {
                let message = format!("That was longer than {MAX_UTTERANCE_S} seconds.");
                return json!({ "type": "error", "message": message });
            }
            if audio.is_empty() {
                return json!({ "type": "error", "message": "No audio was received." });
            }
            match recognise(&audio) {
                Some(heard) => command_reply(s, user, &heard).await,
                None => json!({
                    "type": "reply",
                    "outcome": "unavailable",
                    "reply": "No speech recogniser is installed on this host yet.",
                    "audio_ms": audio.len() / BYTES_PER_MS,
                }),
            }
        }
        _ => json!({ "type": "error", "message": "Unknown message type." }),
    }
}

async fn command_reply(s: &AppState, user: &AuthUser, text: &str) -> Value {
    match api::run_voice_text(s, user, text).await {
        Ok(mut v) => {
            v["type"] = json!("reply");
            v
        }
        Err(ApiError::BadRequest(m)) => json!({ "type": "error", "message": m }),
        Err(_) => json!({ "type": "error", "message": "The host could not handle that." }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_are_unambiguous_and_normalised() {
        let raw = new_code_raw();
        assert_eq!(raw.len(), CODE_LEN);
        assert!(raw.bytes().all(|b| CODE_ALPHABET.contains(&b)));
        let shown = display_code(&raw);
        assert_eq!(normalize_code(&shown), Some(raw.clone()));
        assert_eq!(normalize_code(&shown.to_lowercase()), Some(raw));
        assert_eq!(normalize_code("short"), None);
        assert_eq!(normalize_code("0O1I0-O1I01"), None);
        assert_eq!(normalize_code("ÄÄÄÄÄ-ÄÄÄÄÄ"), None);
    }
}
