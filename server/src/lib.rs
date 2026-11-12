//! Home AI core: a single-binary modular monolith.

pub mod api;
pub mod auth;
pub mod db;
pub mod devices;
pub mod error;
pub mod events;
pub mod hwdiag;
pub mod metrics;
pub mod policy;
pub mod settings;
pub mod tls;
pub mod ws;

use std::collections::HashMap;
use std::ops::Deref;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use rusqlite::params;

use crate::auth::LoginLimiter;
use crate::db::Db;
use crate::devices::{Connector, Simulator};
use crate::error::ApiError;
use crate::events::EventBus;
use crate::metrics::MetricsCollector;

/// Unix time in seconds.
pub fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

pub struct Inner {
    pub db: Db,
    pub bus: EventBus,
    pub metrics: MetricsCollector,
    pub limiter: LoginLimiter,
    pub connectors: HashMap<&'static str, Arc<dyn Connector>>,
    pub web_dir: PathBuf,
    /// True once an administrator exists. Setup can never reopen after that.
    setup_done: AtomicBool,
}

#[derive(Clone)]
pub struct AppState(Arc<Inner>);

impl Deref for AppState {
    type Target = Inner;
    fn deref(&self) -> &Inner {
        &self.0
    }
}

impl AppState {
    pub async fn new(db: Db, web_dir: PathBuf) -> Result<Self, ApiError> {
        let mut connectors: HashMap<&'static str, Arc<dyn Connector>> = HashMap::new();
        let sim: Arc<dyn Connector> = Arc::new(Simulator);
        connectors.insert(sim.id(), sim.clone());

        let discovered = sim.discover();
        let user_count: i64 = db
            .call(move |c| {
                devices::register(c, &discovered)?;
                c.query_row("SELECT COUNT(*) FROM users", [], |r| r.get(0))
            })
            .await?;

        Ok(Self(Arc::new(Inner {
            db,
            bus: EventBus::default(),
            metrics: MetricsCollector::default(),
            limiter: LoginLimiter::default(),
            connectors,
            web_dir,
            setup_done: AtomicBool::new(user_count > 0),
        })))
    }

    /// True while no administrator exists.
    pub fn setup_required(&self) -> bool {
        !self.setup_done.load(Ordering::SeqCst)
    }

    pub(crate) fn mark_setup_done(&self) {
        self.setup_done.store(true, Ordering::SeqCst);
    }

    /// Issue a one-time setup token (see `auth::issue_setup_token`). Used by
    /// the `home-ai setup-token` command and by tests; no HTTP route calls it.
    pub async fn issue_setup_token(&self) -> Result<Option<String>, ApiError> {
        self.db.call(auth::issue_setup_token).await
    }

    /// Append to the audit log. Never pass secrets in `detail`.
    pub async fn audit(
        &self,
        username: Option<&str>,
        action: &str,
        target: Option<&str>,
        outcome: &str,
        detail: Option<&str>,
    ) {
        let (u, a, t, o, d) = (
            username.map(str::to_string),
            action.to_string(),
            target.map(str::to_string),
            outcome.to_string(),
            detail.map(str::to_string),
        );
        let res = self
            .db
            .call(move |c| {
                c.prepare_cached(
                    "INSERT INTO audit_log (ts, username, action, target, outcome, detail)
                     VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                )?
                .execute(params![now(), u, a, t, o, d])
            })
            .await;
        if res.is_err() {
            tracing::error!(action, "failed to write audit entry");
        }
    }
}

/// Background work, driven from one place: metrics sampling (only while a
/// dashboard is connected) and hourly cleanup of expired sessions.
pub fn spawn_scheduler(state: AppState) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        let mut metrics_tick = tokio::time::interval(std::time::Duration::from_secs(10));
        let mut cleanup_tick = tokio::time::interval(std::time::Duration::from_secs(3600));
        loop {
            tokio::select! {
                _ = metrics_tick.tick() => {
                    if state.bus.subscriber_count() > 0 {
                        let s = state.clone();
                        if let Ok(snap) = tokio::task::spawn_blocking(move || s.metrics.collect()).await {
                            state.bus.publish(events::Event::Metrics { metrics: snap });
                        }
                    }
                }
                _ = cleanup_tick.tick() => {
                    let _ = state
                        .db
                        .call(|c| c.execute("DELETE FROM sessions WHERE expires_at <= ?1", [now()]))
                        .await;
                }
            }
        }
    })
}
