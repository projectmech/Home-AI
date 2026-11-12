use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::Duration;

use home_ai::db::Db;
use home_ai::{api, auth, hwdiag, spawn_scheduler, tls, AppState};

const USAGE: &str = "\
Usage: home-ai [COMMAND]

  (no command)      run the server
  setup-token       issue a one-time first-run setup token
  tls-fingerprint   print the HTTPS certificate's SHA-256 fingerprint
  hwdiag            print a read-only hardware report (JSON)
  version           print the version

Environment: APP_LISTEN, APP_TLS (off | self-signed), APP_TLS_NAMES,
APP_DATA_DIR, APP_WEB_DIR, APP_LOG_LEVEL. See README.md.";

fn env_or(key: &str, default: &str) -> String {
    std::env::var(key)
        .ok()
        .filter(|v| !v.trim().is_empty())
        .unwrap_or_else(|| default.to_string())
}

fn data_dir() -> PathBuf {
    PathBuf::from(env_or("APP_DATA_DIR", "./data"))
}

/// Names and addresses the self-signed certificate is issued for.
fn tls_names() -> Vec<String> {
    let mut names: Vec<String> = env_or("APP_TLS_NAMES", "")
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();
    for always in ["localhost", "127.0.0.1"] {
        if !names.iter().any(|n| n == always) {
            names.push(always.to_string());
        }
    }
    names
}

fn load_tls(data_dir: &Path) -> Result<tls::TlsMaterial, String> {
    tls::load_or_create(&data_dir.join("tls"), &tls_names())
}

#[tokio::main]
async fn main() -> ExitCode {
    match std::env::args().nth(1).as_deref() {
        None => {}
        Some("hwdiag") => {
            return match serde_json::to_string_pretty(&hwdiag::collect()) {
                Ok(json) => {
                    println!("{json}");
                    ExitCode::SUCCESS
                }
                Err(e) => {
                    eprintln!("hwdiag failed: {e}");
                    ExitCode::FAILURE
                }
            };
        }
        // Needs write access to the database file, so only a local
        // administrator (or the installer) can run it.
        Some("setup-token") => return setup_token_command().await,
        Some("tls-fingerprint") => {
            return match load_tls(&data_dir()) {
                Ok(m) => {
                    println!("{}", m.fingerprint);
                    ExitCode::SUCCESS
                }
                Err(e) => {
                    eprintln!("Could not read or create the certificate: {e}");
                    ExitCode::FAILURE
                }
            };
        }
        Some("version" | "--version" | "-V") => {
            println!("home-ai {}", env!("CARGO_PKG_VERSION"));
            return ExitCode::SUCCESS;
        }
        Some("help" | "--help" | "-h") => {
            println!("{USAGE}");
            return ExitCode::SUCCESS;
        }
        Some(other) => {
            eprintln!("Unknown command '{other}'.\n\n{USAGE}");
            return ExitCode::FAILURE;
        }
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
    let data_dir = data_dir();
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
            println!(
                "Any earlier token is now invalid. It is not stored; if you lose it, run this command again."
            );
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

/// Resolves on Ctrl-C, or on SIGTERM (what systemd sends on stop/restart).
async fn shutdown_signal() {
    #[cfg(unix)]
    {
        use tokio::signal::unix::{signal, SignalKind};
        match signal(SignalKind::terminate()) {
            Ok(mut term) => {
                tokio::select! {
                    _ = tokio::signal::ctrl_c() => {}
                    _ = term.recv() => {}
                }
            }
            Err(_) => {
                let _ = tokio::signal::ctrl_c().await;
            }
        }
    }
    #[cfg(not(unix))]
    {
        let _ = tokio::signal::ctrl_c().await;
    }
    tracing::info!("shutting down");
}

async fn run() -> Result<(), String> {
    let data_dir = data_dir();
    let web_dir = PathBuf::from(env_or("APP_WEB_DIR", "./web/dist"));
    let listen: SocketAddr = env_or("APP_LISTEN", "127.0.0.1:8080")
        .parse()
        .map_err(|e| format!("APP_LISTEN is not a socket address: {e}"))?;
    let tls_mode = env_or("APP_TLS", "off");
    if !matches!(tls_mode.as_str(), "off" | "self-signed") {
        return Err(format!(
            "APP_TLS must be 'off' or 'self-signed', not '{tls_mode}'"
        ));
    }
    let use_tls = tls_mode == "self-signed";

    // Plain HTTP is for loopback only (development, or behind a local proxy).
    // Refusing here means login can never be served in plaintext on the
    // network by misconfiguration.
    if !use_tls && !listen.ip().is_loopback() {
        return Err(format!(
            "refusing to serve plain HTTP on {listen}: set APP_TLS=self-signed, \
             or listen on a loopback address (see docs/adr/0002-in-process-tls.md)"
        ));
    }

    std::fs::create_dir_all(&data_dir).map_err(|e| format!("data dir: {e}"))?;
    let db = Db::open(&data_dir.join("home-ai.db")).map_err(|e| format!("database: {e}"))?;
    let state = AppState::new(db, web_dir.clone())
        .await
        .map_err(|e| format!("startup: {e:?}"))?;

    if !web_dir.join("index.html").exists() {
        tracing::warn!("no frontend build at {}", web_dir.display());
    }
    if state.setup_required() {
        // The server never issues or prints a token itself.
        tracing::warn!(
            "no administrator exists yet; run `home-ai setup-token` on this machine to get a one-time setup token"
        );
    }

    spawn_scheduler(state.clone());
    let app = api::router(state);

    if use_tls {
        // Explicit provider: the build has no implicit default.
        let _ = rustls::crypto::ring::default_provider().install_default();
        let material = load_tls(&data_dir)?;
        if material.created {
            tracing::info!("created a self-signed certificate");
        }
        let config = axum_server::tls_rustls::RustlsConfig::from_pem(
            material.cert_pem.into_bytes(),
            material.key_pem.into_bytes(),
        )
        .await
        .map_err(|e| format!("TLS configuration: {e}"))?;

        let handle = axum_server::Handle::new();
        let on_signal = handle.clone();
        tokio::spawn(async move {
            shutdown_signal().await;
            on_signal.graceful_shutdown(Some(Duration::from_secs(10)));
        });

        tracing::info!("listening on https://{listen}");
        tracing::info!(
            "certificate is self-signed; SHA-256 fingerprint {}",
            material.fingerprint
        );
        axum_server::bind_rustls(listen, config)
            .handle(handle)
            .serve(app.into_make_service())
            .await
            .map_err(|e| format!("server on {listen}: {e}"))
    } else {
        let listener = tokio::net::TcpListener::bind(listen)
            .await
            .map_err(|e| format!("bind {listen}: {e}"))?;
        tracing::info!("listening on http://{listen}");
        axum::serve(listener, app)
            .with_graceful_shutdown(shutdown_signal())
            .await
            .map_err(|e| format!("server: {e}"))
    }
}
