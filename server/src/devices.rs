//! Device registry (SQLite-backed) and the built-in simulator connector.

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

use crate::policy::Action;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DeviceKind {
    Light,
    Thermostat,
    Speaker,
    Lock,
    TemperatureSensor,
}

impl DeviceKind {
    pub fn as_str(self) -> &'static str {
        match self {
            DeviceKind::Light => "light",
            DeviceKind::Thermostat => "thermostat",
            DeviceKind::Speaker => "speaker",
            DeviceKind::Lock => "lock",
            DeviceKind::TemperatureSensor => "temperature_sensor",
        }
    }

    fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "light" => DeviceKind::Light,
            "thermostat" => DeviceKind::Thermostat,
            "speaker" => DeviceKind::Speaker,
            "lock" => DeviceKind::Lock,
            "temperature_sensor" => DeviceKind::TemperatureSensor,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct Device {
    pub id: String,
    pub connector: String,
    pub external_id: String,
    pub name: String,
    pub kind: DeviceKind,
    pub room: String,
    /// True for simulator devices. The UI must show this distinctly.
    pub simulated: bool,
    pub state: Value,
    pub updated_at: i64,
}

/// What a connector must provide. Synchronous for the in-process simulator;
/// network connectors (M2) will need an async variant with deadlines.
pub trait Connector: Send + Sync {
    fn id(&self) -> &'static str;
    fn discover(&self) -> Vec<Device>;
    /// Apply an already-validated, already-authorized action and return the
    /// state the device reports afterwards.
    fn execute(&self, device: &Device, action: &Action) -> Result<Value, String>;
}

pub struct Simulator;

pub const SIMULATOR_ID: &str = "simulator";
/// A simulated device that rejects every command, so failure reporting can be
/// exercised end to end.
pub const FAULTY_EXTERNAL_ID: &str = "light-faulty";

impl Connector for Simulator {
    fn id(&self) -> &'static str {
        SIMULATOR_ID
    }

    fn discover(&self) -> Vec<Device> {
        let mk = |ext: &str, name: &str, kind: DeviceKind, room: &str, state: Value| Device {
            id: format!("sim-{ext}"),
            connector: SIMULATOR_ID.to_string(),
            external_id: ext.to_string(),
            name: name.to_string(),
            kind,
            room: room.to_string(),
            simulated: true,
            state,
            updated_at: crate::now(),
        };
        vec![
            mk(
                "light-living",
                "Ceiling light",
                DeviceKind::Light,
                "Living room",
                json!({ "on": false, "brightness": 80 }),
            ),
            mk(
                "light-kitchen",
                "Counter light",
                DeviceKind::Light,
                "Kitchen",
                json!({ "on": true, "brightness": 60 }),
            ),
            mk(
                FAULTY_EXTERNAL_ID,
                "Faulty light (always fails)",
                DeviceKind::Light,
                "Hallway",
                json!({ "on": false, "brightness": 50 }),
            ),
            mk(
                "thermostat-living",
                "Thermostat",
                DeviceKind::Thermostat,
                "Living room",
                json!({ "target_c": 21.0, "current_c": 20.5 }),
            ),
            mk(
                "speaker-living",
                "Speaker",
                DeviceKind::Speaker,
                "Living room",
                json!({ "playing": false, "volume": 25 }),
            ),
            mk(
                "lock-front",
                "Front door lock",
                DeviceKind::Lock,
                "Hallway",
                json!({ "locked": true }),
            ),
            mk(
                "sensor-bedroom",
                "Temperature sensor",
                DeviceKind::TemperatureSensor,
                "Bedroom",
                json!({ "temperature_c": 19.0 }),
            ),
        ]
    }

    fn execute(&self, device: &Device, action: &Action) -> Result<Value, String> {
        if device.external_id == FAULTY_EXTERNAL_ID {
            return Err("Simulated device did not acknowledge the command.".into());
        }
        let mut state = device.state.clone();
        let obj = state
            .as_object_mut()
            .ok_or_else(|| "Device state is corrupt.".to_string())?;
        match action {
            Action::SetPower { on } => {
                obj.insert("on".into(), json!(on));
            }
            Action::SetBrightness { percent } => {
                obj.insert("brightness".into(), json!(percent));
                obj.insert("on".into(), json!(*percent > 0));
            }
            Action::SetTargetTemperature { celsius } => {
                obj.insert("target_c".into(), json!(celsius));
            }
            Action::SetPlaying { playing } => {
                obj.insert("playing".into(), json!(playing));
            }
            Action::SetVolume { percent } => {
                obj.insert("volume".into(), json!(percent));
            }
            Action::Lock => {
                obj.insert("locked".into(), json!(true));
            }
            Action::Unlock => {
                obj.insert("locked".into(), json!(false));
            }
        }
        Ok(state)
    }
}

// ---- registry persistence -------------------------------------------------

fn row_to_device(r: &rusqlite::Row<'_>) -> rusqlite::Result<Device> {
    let kind: String = r.get("kind")?;
    let state: String = r.get("state")?;
    Ok(Device {
        id: r.get("id")?,
        connector: r.get("connector")?,
        external_id: r.get("external_id")?,
        name: r.get("name")?,
        kind: DeviceKind::parse(&kind).ok_or_else(|| {
            rusqlite::Error::InvalidColumnType(0, "kind".into(), rusqlite::types::Type::Text)
        })?,
        room: r.get("room")?,
        simulated: r.get("simulated")?,
        state: serde_json::from_str(&state).unwrap_or(Value::Null),
        updated_at: r.get("updated_at")?,
    })
}

/// Register discovered devices. Existing rows keep their stored state, so a
/// restart does not reset anything.
pub fn register(conn: &mut Connection, devices: &[Device]) -> rusqlite::Result<()> {
    let tx = conn.transaction()?;
    for d in devices {
        tx.execute(
            "INSERT OR IGNORE INTO devices
             (id, connector, external_id, name, kind, room, simulated, state, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                d.id,
                d.connector,
                d.external_id,
                d.name,
                d.kind.as_str(),
                d.room,
                d.simulated,
                d.state.to_string(),
                d.updated_at
            ],
        )?;
    }
    tx.commit()
}

pub fn list(conn: &Connection) -> rusqlite::Result<Vec<Device>> {
    let mut stmt = conn.prepare_cached("SELECT * FROM devices ORDER BY room, name")?;
    let rows = stmt.query_map([], row_to_device)?;
    rows.collect()
}

pub fn get(conn: &Connection, id: &str) -> rusqlite::Result<Option<Device>> {
    conn.prepare_cached("SELECT * FROM devices WHERE id = ?1")?
        .query_row([id], row_to_device)
        .optional()
}

pub fn set_state(conn: &Connection, id: &str, state: &Value, ts: i64) -> rusqlite::Result<()> {
    conn.prepare_cached("UPDATE devices SET state = ?2, updated_at = ?3 WHERE id = ?1")?
        .execute(params![id, state.to_string(), ts])?;
    Ok(())
}
