//! Authenticated WebSocket: full snapshot on connect, then sequenced events.
//! A client that falls behind is sent a fresh snapshot rather than a backlog.

use std::time::Duration;

use axum::body::Bytes;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::http::HeaderMap;
use axum::response::Response;
use serde_json::json;
use tokio::sync::broadcast::error::RecvError;

use crate::auth::{self, AuthUser};
use crate::error::ApiError;
use crate::events::Event;
use crate::policy::Role;
use crate::{api, devices, AppState};

const HEARTBEAT: Duration = Duration::from_secs(30);

pub async fn ws_handler(
    State(state): State<AppState>,
    user: AuthUser,
    headers: HeaderMap,
    ws: WebSocketUpgrade,
) -> Result<Response, ApiError> {
    // Browsers do not apply CORS to WebSockets, so the Origin must be checked
    // here or any website could open a socket with the user's cookie.
    if !api::same_origin(&headers, true) {
        return Err(ApiError::Forbidden(
            "Cross-origin WebSocket rejected.".into(),
        ));
    }
    Ok(ws.on_upgrade(move |socket| client_loop(socket, state, user)))
}

async fn snapshot(state: &AppState, user: &AuthUser) -> Option<String> {
    // Read the sequence before the data: an event racing with this snapshot is
    // then delivered again rather than lost.
    let seq = state.bus.current_seq();
    let list = state.db.call(|c| devices::list(c)).await.ok()?;
    let metrics = (user.role == Role::Admin)
        .then(|| state.metrics.last())
        .flatten();
    Some(json!({ "type": "snapshot", "seq": seq, "devices": list, "metrics": metrics }).to_string())
}

async fn client_loop(mut socket: WebSocket, state: AppState, user: AuthUser) {
    let mut rx = state.bus.subscribe();
    let Some(first) = snapshot(&state, &user).await else {
        return;
    };
    if socket.send(Message::Text(first.into())).await.is_err() {
        return;
    }

    let mut heartbeat = tokio::time::interval(HEARTBEAT);
    heartbeat.tick().await; // the first tick fires immediately

    loop {
        tokio::select! {
            event = rx.recv() => {
                let text = match event {
                    Ok(env) => {
                        if matches!(env.event, Event::Metrics { .. }) && user.role != Role::Admin {
                            continue;
                        }
                        match serde_json::to_string(&*env) {
                            Ok(t) => t,
                            Err(_) => continue,
                        }
                    }
                    Err(RecvError::Lagged(_)) => match snapshot(&state, &user).await {
                        Some(t) => t,
                        None => break,
                    },
                    Err(RecvError::Closed) => break,
                };
                if socket.send(Message::Text(text.into())).await.is_err() {
                    break;
                }
            }
            incoming = socket.recv() => {
                match incoming {
                    Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                    Some(Ok(_)) => {} // clients send nothing we act on
                }
            }
            _ = heartbeat.tick() => {
                // Logging out or session expiry ends the stream too.
                let hash = user.token_hash.clone();
                let still_valid = state
                    .db
                    .call(move |c| auth::user_for_token_hash(c, &hash))
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
}
