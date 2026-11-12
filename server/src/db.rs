//! SQLite persistence: one connection, WAL, versioned migrations.

use std::path::Path;
use std::sync::{Arc, Mutex};

use rusqlite::Connection;

use crate::error::ApiError;

/// Ordered schema migrations. Append only; never edit an applied entry.
const MIGRATIONS: &[&str] = &["
    CREATE TABLE users (
        id            INTEGER PRIMARY KEY,
        username      TEXT NOT NULL UNIQUE COLLATE NOCASE,
        password_hash TEXT NOT NULL,
        role          TEXT NOT NULL CHECK (role IN ('admin','standard','restricted')),
        created_at    INTEGER NOT NULL
    );
    CREATE TABLE sessions (
        token_hash TEXT PRIMARY KEY,
        user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL
    );
    CREATE INDEX sessions_expires ON sessions(expires_at);
    CREATE TABLE devices (
        id          TEXT PRIMARY KEY,
        connector   TEXT NOT NULL,
        external_id TEXT NOT NULL,
        name        TEXT NOT NULL,
        kind        TEXT NOT NULL,
        room        TEXT NOT NULL,
        simulated   INTEGER NOT NULL,
        state       TEXT NOT NULL,
        updated_at  INTEGER NOT NULL,
        UNIQUE (connector, external_id)
    );
    CREATE TABLE audit_log (
        id       INTEGER PRIMARY KEY,
        ts       INTEGER NOT NULL,
        username TEXT,
        action   TEXT NOT NULL,
        target   TEXT,
        outcome  TEXT NOT NULL,
        detail   TEXT
    );
    CREATE INDEX audit_ts ON audit_log(ts);
    "];

#[derive(Clone)]
pub struct Db {
    conn: Arc<Mutex<Connection>>,
}

impl Db {
    pub fn open(path: &Path) -> rusqlite::Result<Self> {
        Self::init(Connection::open(path)?)
    }

    pub fn open_in_memory() -> rusqlite::Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(mut conn: Connection) -> rusqlite::Result<Self> {
        // WAL with synchronous=FULL: durability is not traded for speed.
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "FULL")?;
        conn.pragma_update(None, "foreign_keys", "ON")?;
        conn.busy_timeout(std::time::Duration::from_secs(5))?;
        migrate(&mut conn)?;
        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
        })
    }

    /// Run a closure against the connection on the blocking pool so database
    /// I/O never stalls the async executor (the target has two cores).
    pub async fn call<T, F>(&self, f: F) -> Result<T, ApiError>
    where
        F: FnOnce(&mut Connection) -> rusqlite::Result<T> + Send + 'static,
        T: Send + 'static,
    {
        let conn = self.conn.clone();
        tokio::task::spawn_blocking(move || {
            let mut guard = conn.lock().unwrap_or_else(|e| e.into_inner());
            f(&mut guard)
        })
        .await
        .map_err(|e| ApiError::Internal(format!("db task: {e}")))?
        .map_err(ApiError::from)
    }
}

fn migrate(conn: &mut Connection) -> rusqlite::Result<()> {
    let current: i64 = conn.pragma_query_value(None, "user_version", |r| r.get(0))?;
    for (i, sql) in MIGRATIONS.iter().enumerate() {
        let version = i as i64 + 1;
        if version > current {
            let tx = conn.transaction()?;
            tx.execute_batch(sql)?;
            tx.pragma_update(None, "user_version", version)?;
            tx.commit()?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migrations_apply_once_and_are_idempotent() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("t.db");
        drop(Db::open(&path).unwrap());
        let db = Db::open(&path).unwrap();
        let v: i64 = db
            .conn
            .lock()
            .unwrap()
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .unwrap();
        assert_eq!(v, MIGRATIONS.len() as i64);
    }
}
