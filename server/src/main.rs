use std::net::SocketAddr;
use std::path::PathBuf;
use std::process::ExitCode;

use home_ai::db::Db;
use home_ai::{api, auth, hwdiag, spawn_scheduler, AppState};

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key)
        .ok()
        .filter(|v| !v.trim().is_empty())
        .unwrap_or_else(|| default.to_string())
}

#[tokio::main]
async fn main() -> ExitCode {
    // `home-ai hwdiag` prints a read-only hardware report and exits.
    if std::env::args().nth(1).as_deref() == Some("hwdiag") {
        match serde_json::to_string_pretty(&hwdiag::collect()) {
            Ok(json) => {
                println!("{json}");
                return ExitCode::SUCCESS;
            }
            Err(e) => {
                eprintln!("hwdiag failed: {e}");
                return ExitCode::FAILURE;
            }
        }
    }

    // `home-ai setup-token` issues the one-time first-run token. It needs
    // write access to the database file, so only a local administrator (or the
    // installer) can run it. Run it again if the token expired or was lost.
    if std::env::args().nth(1).as_deref() == Some("setup-token") {
        return setup_token_command().await;
    }

    let level = env_or("APP_LOG_LEVEL", "info")
        .parse::<tracing::Level>()
        .unwrap_or(tracing::Level::INFO);
    tracing_subscriber::fmt().with_max_level(level).init();

    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            tracing::error!("{e}");
            ExitCode::FAILURE
        }
    }
}

async fn setup_token_command() -> ExitCode {
    let data_dir = PathBuf::from(env_or("APP_DATA_DIR", "./data"));
    let issued = async {
        std::fs::create_dir_all(&data_dir).map_err(|e| format!("data dir: {e}"))?;
        let db = Db::open(&data_dir.join("home-ai.db")).map_err(|e| format!("database: {e}"))?;
        db.call(auth::issue_setup_token)
            .await
            .map_err(|e| format!("{e:?}"))
    }
    .await;
    match issued {
        Ok(Some(token)) => {
            println!(
                "One-time setup token (valid for {} minutes, single use):\n",
                auth::SETUP_TOKEN_TTL_S / 60
            );
            println!("  {token}\n");
            println!("Any earlier token is now invalid. It is not stored; if you lose it, run this command again.");
            ExitCode::SUCCESS
        }
        Ok(None) => {
            eprintln!("Setup is already complete: an administrator exists. No token was issued.");
            ExitCode::FAILURE
        }
        Err(e) => {
            eprintln!("Could not issue a setup token: {e}");
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<(), String> {
    let data_dir = PathBuf::from(env_or("APP_DATA_DIR", "./data"));
    let web_dir = PathBuf::from(env_or("APP_WEB_DIR", "./web/dist"));
    let listen: SocketAddr = env_or("APP_LISTEN", "127.0.0.1:8080")
        .parse()
        .map_err(|e| format!("APP_LISTEN is not a socket address: {e}"))?;

    // This process speaks plain HTTP. It must only be reachable through
    // loopback, with a TLS-terminating proxy in front for LAN access
    // (docs/adr/0001). Refusing here means login can never be served over
    // plaintext on the network by misconfiguration.
    if !listen.ip().is_loopback() {
        return Err(format!(
            "refusing to listen on {listen}: only loopback addresses are allowed; \
             put a TLS proxy in front (see docs/adr/0001-foundation.md)"
        ));
    }

    std::fs::create_dir_all(&data_dir).map_err(|e| format!("data dir: {e}"))?;
    let db = Db::open(&data_dir.join("home-ai.db")).map_err(|e| format!("database: {e}"))?;
    let state = AppState::new(db, web_dir.clone())
        .await
        .map_err(|e| format!("startup: {e:?}"))?;

    if !web_dir.join("index.html").exists() {
        tracing::warn!(
            "no frontend build at {}; run `npm run build` in web/",
            web_dir.display()
        );
    }
    if state.setup_required() {
        // The server never issues or prints a token itself.
        tracing::warn!(
            "no administrator exists yet; run `home-ai setup-token` on this machine to get a one-time setup token"
        );
    }

    spawn_scheduler(state.clone());

    let listener = tokio::net::TcpListener::bind(listen)
        .await
        .map_err(|e| format!("bind {listen}: {e}"))?;
    tracing::info!("listening on http://{listen}");

    axum::serve(listener, api::router(state))
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
            tracing::info!("shutting down");
        })
        .await
        .map_err(|e| format!("server: {e}"))
}
