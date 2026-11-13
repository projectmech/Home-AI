//! Acceptance tests for the first vertical slice (docs/TEST_PLAN.md A01–A07).
//! Everything here runs against the simulator; nothing is a physical-device test.

use std::path::PathBuf;

use axum::body::Body;
use axum::http::{header, Method, Request, StatusCode};
use axum::Router;
use futures_util::StreamExt;
use home_ai::db::Db;
use home_ai::policy::Role;
use home_ai::{api, AppState};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tower::ServiceExt;

const ADMIN_PW: &str = "correct horse battery staple";

async fn new_state() -> AppState {
    AppState::new(Db::open_in_memory().unwrap(), PathBuf::from("no-web-dir"))
        .await
        .unwrap()
}

struct Reply {
    status: StatusCode,
    cookie: Option<String>,
    body: Value,
}

async fn call(
    app: &Router,
    method: Method,
    uri: &str,
    cookie: Option<&str>,
    body: Option<Value>,
) -> Reply {
    call_with(app, method, uri, cookie, body, &[]).await
}

async fn call_with(
    app: &Router,
    method: Method,
    uri: &str,
    cookie: Option<&str>,
    body: Option<Value>,
    extra: &[(&str, &str)],
) -> Reply {
    let mut req = Request::builder().method(method).uri(uri);
    if let Some(c) = cookie {
        req = req.header(header::COOKIE, c);
    }
    for (k, v) in extra {
        req = req.header(*k, *v);
    }
    let req = match body {
        Some(b) => req
            .header(header::CONTENT_TYPE, "application/json")
            .body(Body::from(b.to_string()))
            .unwrap(),
        None => req.body(Body::empty()).unwrap(),
    };
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let cookie = res
        .headers()
        .get(header::SET_COOKIE)
        .and_then(|v| v.to_str().ok())
        .and_then(|v| v.split(';').next())
        .map(str::to_string);
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    let body = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    Reply {
        status,
        cookie,
        body,
    }
}

async fn try_setup(app: &Router, token: &str, password: &str) -> Reply {
    call(
        app,
        Method::POST,
        "/api/setup",
        None,
        Some(json!({ "setup_token": token, "username": "admin", "password": password })),
    )
    .await
}

async fn setup_admin(state: &AppState, app: &Router) {
    let token = state
        .issue_setup_token()
        .await
        .unwrap()
        .expect("setup open");
    let r = call(
        app,
        Method::POST,
        "/api/setup",
        None,
        Some(json!({ "setup_token": token, "username": "admin", "password": ADMIN_PW })),
    )
    .await;
    assert_eq!(r.status, StatusCode::CREATED);
}

async fn login(app: &Router, username: &str, password: &str) -> String {
    let r = call(
        app,
        Method::POST,
        "/api/login",
        None,
        Some(json!({ "username": username, "password": password })),
    )
    .await;
    assert_eq!(r.status, StatusCode::OK, "login failed: {}", r.body);
    r.cookie.expect("session cookie")
}

async fn act(app: &Router, cookie: &str, device: &str, body: Value) -> Reply {
    call(
        app,
        Method::POST,
        &format!("/api/devices/{device}/actions"),
        Some(cookie),
        Some(body),
    )
    .await
}

/// A01
#[tokio::test]
async fn first_run_setup_creates_admin_once() {
    let state = new_state().await;
    let app = api::router(state.clone());

    let h = call(&app, Method::GET, "/api/health", None, None).await;
    assert_eq!(h.body["setup_required"], true);

    // No token issued yet: a fresh server cannot be claimed from the network.
    let unissued = try_setup(&app, &"0".repeat(64), ADMIN_PW).await;
    assert_eq!(unissued.status, StatusCode::FORBIDDEN);

    let token = state.issue_setup_token().await.unwrap().unwrap();
    let bad = try_setup(&app, &"0".repeat(64), ADMIN_PW).await;
    assert_eq!(bad.status, StatusCode::FORBIDDEN);

    // Only a hash is stored.
    let stored: String = state
        .db
        .call(|c| c.query_row("SELECT group_concat(value) FROM settings", [], |r| r.get(0)))
        .await
        .unwrap();
    assert!(
        !stored.contains(&token),
        "token must not be stored in plaintext"
    );
    let weak = call(
        &app,
        Method::POST,
        "/api/setup",
        None,
        Some(json!({ "setup_token": token, "username": "admin", "password": "short" })),
    )
    .await;
    assert_eq!(weak.status, StatusCode::BAD_REQUEST);

    // An expired token is refused.
    state
        .db
        .call(|c| {
            c.execute(
                "UPDATE settings SET value = '0' WHERE key = 'setup_token_expires'",
                [],
            )
        })
        .await
        .unwrap();
    let expired = try_setup(&app, &token, ADMIN_PW).await;
    assert_eq!(expired.status, StatusCode::FORBIDDEN);
    assert!(state.setup_required());

    // Issues a fresh token (retiring the old one) and completes setup.
    setup_admin(&state, &app).await;
    assert!(!state.setup_required());
    assert!(state.issue_setup_token().await.unwrap().is_none());
    let leftover: i64 = state
        .db
        .call(|c| c.query_row("SELECT COUNT(*) FROM settings", [], |r| r.get(0)))
        .await
        .unwrap();
    assert_eq!(leftover, 0, "token must be deleted when setup completes");

    let again = call(
        &app,
        Method::POST,
        "/api/setup",
        None,
        Some(json!({ "setup_token": token, "username": "evil", "password": ADMIN_PW })),
    )
    .await;
    assert_eq!(again.status, StatusCode::CONFLICT);

    let h = call(&app, Method::GET, "/api/health", None, None).await;
    assert_eq!(h.body["setup_required"], false);
}

#[tokio::test]
async fn setup_token_guessing_is_rate_limited() {
    let state = new_state().await;
    let app = api::router(state.clone());
    let token = state.issue_setup_token().await.unwrap().unwrap();

    for _ in 0..5 {
        let r = try_setup(&app, &"f".repeat(64), ADMIN_PW).await;
        assert_eq!(r.status, StatusCode::FORBIDDEN);
    }
    // Locked: even the real token is refused until the lock passes.
    let r = try_setup(&app, &token, ADMIN_PW).await;
    assert_eq!(r.status, StatusCode::TOO_MANY_REQUESTS);
    assert!(state.setup_required());
}

/// A restart must not issue, print or reopen anything by itself.
#[tokio::test]
async fn restart_does_not_issue_a_setup_token() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("home-ai.db");
    drop(
        AppState::new(Db::open(&path).unwrap(), PathBuf::from("x"))
            .await
            .unwrap(),
    );
    let state = AppState::new(Db::open(&path).unwrap(), PathBuf::from("x"))
        .await
        .unwrap();
    assert!(state.setup_required());
    let rows: i64 = state
        .db
        .call(|c| c.query_row("SELECT COUNT(*) FROM settings", [], |r| r.get(0)))
        .await
        .unwrap();
    assert_eq!(rows, 0);
}

/// A02
#[tokio::test]
async fn wrong_password_is_denied_then_rate_limited() {
    let state = new_state().await;
    let app = api::router(state.clone());
    setup_admin(&state, &app).await;

    for _ in 0..5 {
        let r = call(
            &app,
            Method::POST,
            "/api/login",
            None,
            Some(json!({ "username": "admin", "password": "definitely wrong" })),
        )
        .await;
        assert_eq!(r.status, StatusCode::UNAUTHORIZED);
        assert!(r.cookie.is_none());
    }
    // Locked now, even with the right password.
    let r = call(
        &app,
        Method::POST,
        "/api/login",
        None,
        Some(json!({ "username": "admin", "password": ADMIN_PW })),
    )
    .await;
    assert_eq!(r.status, StatusCode::TOO_MANY_REQUESTS);

    let unknown = call(
        &app,
        Method::POST,
        "/api/login",
        None,
        Some(json!({ "username": "nobody", "password": "whatever it is" })),
    )
    .await;
    assert_eq!(unknown.status, StatusCode::UNAUTHORIZED);
    assert_eq!(unknown.body["error"], "invalid_credentials");
}

/// A03
#[tokio::test]
async fn anonymous_requests_are_rejected() {
    let state = new_state().await;
    let app = api::router(state.clone());
    setup_admin(&state, &app).await;

    for uri in [
        "/api/devices",
        "/api/me",
        "/api/server/metrics",
        "/api/server/hardware",
        "/api/audit",
        "/api/ws",
    ] {
        let r = call(&app, Method::GET, uri, None, None).await;
        assert_eq!(r.status, StatusCode::UNAUTHORIZED, "{uri}");
    }
    let r = call(
        &app,
        Method::POST,
        "/api/devices/sim-light-living/actions",
        None,
        Some(json!({ "action": "set_power", "on": true })),
    )
    .await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED);

    let forged = "home_ai_session=".to_string() + &"a".repeat(64);
    let r = call(&app, Method::GET, "/api/devices", Some(&forged), None).await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED);
}

/// A05
#[tokio::test]
async fn commands_pass_capability_and_permission_policy() {
    let state = new_state().await;
    let app = api::router(state.clone());
    setup_admin(&state, &app).await;
    api::create_user(&state, "standard", ADMIN_PW, Role::Standard)
        .await
        .unwrap();
    api::create_user(&state, "guest", ADMIN_PW, Role::Restricted)
        .await
        .unwrap();
    let admin = login(&app, "admin", ADMIN_PW).await;
    let standard = login(&app, "standard", ADMIN_PW).await;
    let guest = login(&app, "guest", ADMIN_PW).await;

    let ok = act(
        &app,
        &admin,
        "sim-light-living",
        json!({ "action": "set_power", "on": true }),
    )
    .await;
    assert_eq!(ok.status, StatusCode::OK);
    assert_eq!(ok.body["outcome"], "confirmed");
    assert_eq!(ok.body["device"]["state"]["on"], true);
    assert_eq!(ok.body["device"]["simulated"], true);

    let range = act(
        &app,
        &admin,
        "sim-light-living",
        json!({ "action": "set_brightness", "percent": 150 }),
    )
    .await;
    assert_eq!(range.status, StatusCode::BAD_REQUEST);

    let cap = act(
        &app,
        &admin,
        "sim-light-living",
        json!({ "action": "set_volume", "percent": 10 }),
    )
    .await;
    assert_eq!(cap.status, StatusCode::BAD_REQUEST);

    let sensor = act(
        &app,
        &admin,
        "sim-sensor-bedroom",
        json!({ "action": "set_power", "on": true }),
    )
    .await;
    assert_eq!(sensor.status, StatusCode::BAD_REQUEST);

    let missing = act(
        &app,
        &admin,
        "nope",
        json!({ "action": "set_power", "on": true }),
    )
    .await;
    assert_eq!(missing.status, StatusCode::NOT_FOUND);

    // Read-only role cannot control anything but can read.
    let denied = act(
        &app,
        &guest,
        "sim-light-living",
        json!({ "action": "set_power", "on": false }),
    )
    .await;
    assert_eq!(denied.status, StatusCode::FORBIDDEN);
    let read = call(&app, Method::GET, "/api/devices", Some(&guest), None).await;
    assert_eq!(read.status, StatusCode::OK);

    // Server administration is admin only.
    let m = call(
        &app,
        Method::GET,
        "/api/server/metrics",
        Some(&standard),
        None,
    )
    .await;
    assert_eq!(m.status, StatusCode::FORBIDDEN);
    let m = call(&app, Method::GET, "/api/server/metrics", Some(&admin), None).await;
    assert_eq!(m.status, StatusCode::OK);
    assert!(m.body["metrics"]["mem_total_bytes"].as_u64().unwrap() > 0);

    // Unlock: standard denied; admin needs step-up with the right password.
    let lock = "sim-lock-front";
    let r = act(&app, &standard, lock, json!({ "action": "unlock" })).await;
    assert_eq!(r.status, StatusCode::FORBIDDEN);
    assert_eq!(r.body["error"], "forbidden");
    let r = act(&app, &standard, lock, json!({ "action": "lock" })).await;
    assert_eq!(r.body["outcome"], "confirmed");

    let r = act(&app, &admin, lock, json!({ "action": "unlock" })).await;
    assert_eq!(r.status, StatusCode::FORBIDDEN);
    assert_eq!(r.body["error"], "step_up_required");
    let r = act(
        &app,
        &admin,
        lock,
        json!({ "action": "unlock", "confirm_password": "wrong password!" }),
    )
    .await;
    assert_eq!(r.status, StatusCode::FORBIDDEN);
    let r = act(
        &app,
        &admin,
        lock,
        json!({ "action": "unlock", "confirm_password": ADMIN_PW }),
    )
    .await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(r.body["device"]["state"]["locked"], false);

    // Denials and the unlock are in the audit trail; no password is.
    let audit = call(&app, Method::GET, "/api/audit", Some(&admin), None).await;
    let text = audit.body.to_string();
    assert!(text.contains("\"unlock\""));
    assert!(text.contains("denied"));
    assert!(!text.contains(ADMIN_PW));
}

/// C03 (simulator part): a failing device reports failure and keeps its state.
#[tokio::test]
async fn failed_command_is_reported_as_failed() {
    let state = new_state().await;
    let app = api::router(state.clone());
    setup_admin(&state, &app).await;
    let admin = login(&app, "admin", ADMIN_PW).await;

    let r = act(
        &app,
        &admin,
        "sim-light-faulty",
        json!({ "action": "set_power", "on": true }),
    )
    .await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(r.body["outcome"], "failed");
    assert!(r.body["reason"].is_string());
    assert_eq!(r.body["device"]["state"]["on"], false);
}

#[tokio::test]
async fn cross_origin_posts_are_rejected() {
    let state = new_state().await;
    let app = api::router(state.clone());
    setup_admin(&state, &app).await;
    let admin = login(&app, "admin", ADMIN_PW).await;

    let r = call_with(
        &app,
        Method::POST,
        "/api/devices/sim-light-living/actions",
        Some(&admin),
        Some(json!({ "action": "set_power", "on": true })),
        &[("host", "home.local"), ("origin", "https://evil.example")],
    )
    .await;
    assert_eq!(r.status, StatusCode::FORBIDDEN);

    let r = call_with(
        &app,
        Method::POST,
        "/api/devices/sim-light-living/actions",
        Some(&admin),
        Some(json!({ "action": "set_power", "on": true })),
        &[("host", "home.local"), ("origin", "https://home.local")],
    )
    .await;
    assert_eq!(r.status, StatusCode::OK);
}

#[tokio::test]
async fn logout_invalidates_the_session() {
    let state = new_state().await;
    let app = api::router(state.clone());
    setup_admin(&state, &app).await;
    let admin = login(&app, "admin", ADMIN_PW).await;

    assert_eq!(
        call(&app, Method::GET, "/api/me", Some(&admin), None)
            .await
            .status,
        StatusCode::OK
    );
    assert_eq!(
        call(&app, Method::POST, "/api/logout", Some(&admin), None)
            .await
            .status,
        StatusCode::OK
    );
    assert_eq!(
        call(&app, Method::GET, "/api/me", Some(&admin), None)
            .await
            .status,
        StatusCode::UNAUTHORIZED
    );
}

/// A07
#[tokio::test]
async fn restart_preserves_users_sessions_and_device_state() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("home-ai.db");

    let cookie = {
        let state = AppState::new(Db::open(&path).unwrap(), PathBuf::from("x"))
            .await
            .unwrap();
        let app = api::router(state.clone());
        setup_admin(&state, &app).await;
        let cookie = login(&app, "admin", ADMIN_PW).await;
        let r = act(
            &app,
            &cookie,
            "sim-light-living",
            json!({ "action": "set_brightness", "percent": 33 }),
        )
        .await;
        assert_eq!(r.body["outcome"], "confirmed");
        cookie
    };

    let state = AppState::new(Db::open(&path).unwrap(), PathBuf::from("x"))
        .await
        .unwrap();
    assert!(
        !state.setup_required(),
        "setup must stay closed after restart"
    );
    let app = api::router(state);
    let r = call(&app, Method::GET, "/api/devices", Some(&cookie), None).await;
    assert_eq!(r.status, StatusCode::OK);
    let light = r.body["devices"]
        .as_array()
        .unwrap()
        .iter()
        .find(|d| d["id"] == "sim-light-living")
        .unwrap();
    assert_eq!(light["state"]["brightness"], 33);
}

/// A06 (+ WebSocket half of A03)
#[tokio::test]
async fn websocket_sends_snapshot_then_live_device_events() {
    let state = new_state().await;
    let app = api::router(state.clone());
    setup_admin(&state, &app).await;
    let cookie = login(&app, "admin", ADMIN_PW).await;

    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let served = app.clone();
    tokio::spawn(async move { axum::serve(listener, served).await.unwrap() });
    let url = format!("ws://{addr}/api/ws");
    let origin = format!("http://{addr}");

    // No cookie: refused before the upgrade.
    let mut req = url.as_str().into_client_request().unwrap();
    req.headers_mut().insert("origin", origin.parse().unwrap());
    assert!(tokio_tungstenite::connect_async(req).await.is_err());

    // Valid cookie from a foreign origin: refused.
    let mut req = url.as_str().into_client_request().unwrap();
    req.headers_mut().insert("cookie", cookie.parse().unwrap());
    req.headers_mut()
        .insert("origin", "https://evil.example".parse().unwrap());
    assert!(tokio_tungstenite::connect_async(req).await.is_err());

    let mut req = url.as_str().into_client_request().unwrap();
    req.headers_mut().insert("cookie", cookie.parse().unwrap());
    req.headers_mut().insert("origin", origin.parse().unwrap());
    let (mut ws, _) = tokio_tungstenite::connect_async(req).await.unwrap();

    let first: Value =
        serde_json::from_str(ws.next().await.unwrap().unwrap().to_text().unwrap()).unwrap();
    assert_eq!(first["type"], "snapshot");
    assert_eq!(first["devices"].as_array().unwrap().len(), 7);

    let r = act(
        &app,
        &cookie,
        "sim-speaker-living",
        json!({ "action": "set_volume", "percent": 40 }),
    )
    .await;
    assert_eq!(r.body["outcome"], "confirmed");

    let next = tokio::time::timeout(std::time::Duration::from_secs(5), ws.next())
        .await
        .expect("event within 5s")
        .unwrap()
        .unwrap();
    let event: Value = serde_json::from_str(next.to_text().unwrap()).unwrap();
    assert_eq!(event["type"], "device_state");
    assert_eq!(event["device"]["id"], "sim-speaker-living");
    assert_eq!(event["device"]["state"]["volume"], 40);
    assert!(event["seq"].as_u64().unwrap() > first["seq"].as_u64().unwrap());
}

/// prompts/06 §5: token-gated welcome, administrator, home, security, finish.
#[tokio::test]
async fn setup_wizard_flow() {
    let state = new_state().await;
    let app = api::router(state.clone());
    let token = state.issue_setup_token().await.unwrap().unwrap();

    // Step 1: server facts are disclosed only with the token, which is not consumed.
    let no = call(
        &app,
        Method::POST,
        "/api/setup/verify",
        None,
        Some(json!({ "setup_token": "0".repeat(64) })),
    )
    .await;
    assert_eq!(no.status, StatusCode::FORBIDDEN);
    assert!(no.body["server"].is_null());
    let yes = call(
        &app,
        Method::POST,
        "/api/setup/verify",
        None,
        Some(json!({ "setup_token": token })),
    )
    .await;
    assert_eq!(yes.status, StatusCode::OK);
    assert!(yes.body["server"]["mem_total_bytes"].as_u64().unwrap() > 0);
    assert_eq!(yes.body["server"]["version"], env!("CARGO_PKG_VERSION"));

    // Settings are closed before an administrator exists.
    let anon = call(&app, Method::GET, "/api/settings/home", None, None).await;
    assert_eq!(anon.status, StatusCode::UNAUTHORIZED);
    let anon = call(&app, Method::POST, "/api/setup/finish", None, None).await;
    assert_eq!(anon.status, StatusCode::UNAUTHORIZED);

    // Step 2: creating the administrator signs them in.
    let created = try_setup(&app, &token, ADMIN_PW).await;
    assert_eq!(created.status, StatusCode::CREATED);
    assert_eq!(created.body["setup_complete"], false);
    let admin = created.cookie.expect("setup must set a session cookie");
    let me = call(&app, Method::GET, "/api/me", Some(&admin), None).await;
    assert_eq!(me.body["role"], "admin");
    assert_eq!(me.body["setup_complete"], false);

    // The token-gated endpoints are closed from here on.
    let again = call(
        &app,
        Method::POST,
        "/api/setup/verify",
        None,
        Some(json!({ "setup_token": token })),
    )
    .await;
    assert_eq!(again.status, StatusCode::CONFLICT);

    // Step 3: home configuration, validated and normalised.
    let defaults = call(&app, Method::GET, "/api/settings/home", Some(&admin), None).await;
    assert_eq!(defaults.body["home"]["temperature_unit"], "celsius");
    let bad = call(
        &app,
        Method::PUT,
        "/api/settings/home",
        Some(&admin),
        Some(
            json!({ "home_name": "", "country": "NO", "timezone": "Europe/Oslo",
                     "language": "nb", "temperature_unit": "celsius", "rooms": [] }),
        ),
    )
    .await;
    assert_eq!(bad.status, StatusCode::BAD_REQUEST);
    let saved = call(
        &app,
        Method::PUT,
        "/api/settings/home",
        Some(&admin),
        Some(
            json!({ "home_name": " Villa ", "country": "no", "timezone": "Europe/Oslo",
                     "language": "nb", "temperature_unit": "fahrenheit",
                     "rooms": ["Stue", " Kjøkken ", "stue"] }),
        ),
    )
    .await;
    assert_eq!(saved.status, StatusCode::OK);
    assert_eq!(saved.body["home"]["home_name"], "Villa");
    assert_eq!(saved.body["home"]["country"], "NO");
    assert_eq!(saved.body["home"]["rooms"], json!(["Stue", "Kjøkken"]));

    // Step 8: session length is real: it sets the cookie lifetime of new sign-ins.
    let bad = call(
        &app,
        Method::PUT,
        "/api/settings/security",
        Some(&admin),
        Some(json!({ "session_hours": 0 })),
    )
    .await;
    assert_eq!(bad.status, StatusCode::BAD_REQUEST);
    let ok = call(
        &app,
        Method::PUT,
        "/api/settings/security",
        Some(&admin),
        Some(json!({ "session_hours": 2 })),
    )
    .await;
    assert_eq!(ok.status, StatusCode::OK);
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method(Method::POST)
                .uri("/api/login")
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from(
                    json!({ "username": "admin", "password": ADMIN_PW }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let set_cookie = res.headers()[header::SET_COOKIE]
        .to_str()
        .unwrap()
        .to_string();
    assert!(set_cookie.contains("Max-Age=7200"), "{set_cookie}");

    // Non-administrators can read home settings but change nothing.
    api::create_user(&state, "standard", ADMIN_PW, Role::Standard)
        .await
        .unwrap();
    let standard = login(&app, "standard", ADMIN_PW).await;
    let r = call(
        &app,
        Method::GET,
        "/api/settings/home",
        Some(&standard),
        None,
    )
    .await;
    assert_eq!(r.status, StatusCode::OK);
    let r = call(
        &app,
        Method::PUT,
        "/api/settings/security",
        Some(&standard),
        Some(json!({ "session_hours": 100 })),
    )
    .await;
    assert_eq!(r.status, StatusCode::FORBIDDEN);
    let r = call(
        &app,
        Method::POST,
        "/api/setup/finish",
        Some(&standard),
        None,
    )
    .await;
    assert_eq!(r.status, StatusCode::FORBIDDEN);

    // Step 9: finish.
    let done = call(&app, Method::POST, "/api/setup/finish", Some(&admin), None).await;
    assert_eq!(done.status, StatusCode::OK);
    let me = call(&app, Method::GET, "/api/me", Some(&admin), None).await;
    assert_eq!(me.body["setup_complete"], true);
}

async fn voice(app: &Router, cookie: &str, text: &str) -> Reply {
    call(
        app,
        Method::POST,
        "/api/voice/command",
        Some(cookie),
        Some(json!({ "text": text })),
    )
    .await
}

/// Voice commands go through the same policy path as button presses.
#[tokio::test]
async fn voice_commands_use_the_same_policy_path() {
    let state = new_state().await;
    let app = api::router(state.clone());
    setup_admin(&state, &app).await;
    let admin = login(&app, "admin", ADMIN_PW).await;

    // Anonymous callers are rejected.
    let r = call(
        &app,
        Method::POST,
        "/api/voice/command",
        None,
        Some(json!({ "text": "turn off the kitchen light" })),
    )
    .await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED);

    // The kitchen light starts on; a spoken command turns it off.
    let r = voice(&app, &admin, "turn off the kitchen light").await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    assert_eq!(r.body["outcome"], "confirmed");
    assert_eq!(r.body["device"]["id"], "sim-light-kitchen");
    assert_eq!(r.body["device"]["state"]["on"], false);

    // Spoken numbers work.
    let r = voice(&app, &admin, "set the thermostat to twenty two degrees").await;
    assert_eq!(r.body["outcome"], "confirmed");
    assert_eq!(r.body["device"]["state"]["target_c"], 22.0);

    // Out-of-range values are rejected by the same validation as the UI.
    let r = voice(&app, &admin, "set the thermostat to forty").await;
    assert_eq!(r.body["outcome"], "rejected");

    // Voice can never unlock, and the lock state is unchanged.
    let r = voice(&app, &admin, "unlock the front door").await;
    assert_eq!(r.body["outcome"], "refused");
    let r = call(&app, Method::GET, "/api/devices", Some(&admin), None).await;
    let lock = r.body["devices"]
        .as_array()
        .unwrap()
        .iter()
        .find(|d| d["id"] == "sim-lock-front")
        .unwrap()
        .clone();
    assert_eq!(lock["state"]["locked"], true);

    // A device that fails reports failure, not success.
    let r = voice(&app, &admin, "turn on the faulty light").await;
    assert_eq!(r.body["outcome"], "failed");

    // Questions and unknown words get a reply and execute nothing.
    let r = voice(&app, &admin, "what is the temperature in the bedroom").await;
    assert_eq!(r.body["outcome"], "answer");
    let r = voice(&app, &admin, "sing me a song").await;
    assert_eq!(r.body["outcome"], "unknown");

    // Oversized input is refused.
    let long = "turn on the light ".repeat(40);
    let r = voice(&app, &admin, &long).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
}
