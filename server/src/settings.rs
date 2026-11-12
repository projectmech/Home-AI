//! Home and security settings, stored as JSON in the `settings` table and
//! edited from the web interface (setup wizard, later the Settings page).

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};

const HOME_KEY: &str = "home";
const SECURITY_KEY: &str = "security";
const WIZARD_KEY: &str = "setup_wizard_complete";

pub const MAX_ROOMS: usize = 40;

fn get(conn: &Connection, key: &str) -> rusqlite::Result<Option<String>> {
    conn.query_row("SELECT value FROM settings WHERE key = ?1", [key], |r| {
        r.get(0)
    })
    .optional()
}

fn set(conn: &Connection, key: &str, value: &str) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT OR REPLACE INTO settings (key, value) VALUES (?1, ?2)",
        params![key, value],
    )?;
    Ok(())
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct HomeSettings {
    pub home_name: String,
    /// ISO 3166-1 alpha-2, upper case, or empty when not given.
    pub country: String,
    /// IANA time zone name, for example "Europe/Oslo".
    pub timezone: String,
    /// "en" or "nb". Stored as a preference; the dashboard is English only today.
    pub language: String,
    /// "celsius" or "fahrenheit": how the dashboard shows temperatures.
    pub temperature_unit: String,
    /// Room names the user expects to have.
    pub rooms: Vec<String>,
}

impl Default for HomeSettings {
    fn default() -> Self {
        Self {
            home_name: "Home".into(),
            country: String::new(),
            timezone: "UTC".into(),
            language: "en".into(),
            temperature_unit: "celsius".into(),
            rooms: ["Living room", "Kitchen", "Bedroom", "Hallway"]
                .map(String::from)
                .to_vec(),
        }
    }
}

fn valid_timezone(tz: &str) -> bool {
    // Shape check only: the server carries no time zone database yet.
    !tz.is_empty()
        && tz.len() <= 64
        && tz.split('/').count() <= 3
        && tz.split('/').all(|part| {
            !part.is_empty()
                && part
                    .chars()
                    .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '+'))
        })
}

impl HomeSettings {
    /// Trim, normalise and check every field.
    pub fn validated(mut self) -> Result<Self, String> {
        self.home_name = self.home_name.trim().to_string();
        let name_len = self.home_name.chars().count();
        if name_len == 0 || name_len > 60 {
            return Err("Home name must be 1–60 characters.".into());
        }
        if self.home_name.chars().any(char::is_control) {
            return Err("Home name contains characters that are not allowed.".into());
        }

        self.country = self.country.trim().to_ascii_uppercase();
        let country_ok = self.country.is_empty()
            || (self.country.len() == 2 && self.country.chars().all(|c| c.is_ascii_uppercase()));
        if !country_ok {
            return Err("Country must be a two-letter code such as NO, or empty.".into());
        }

        self.timezone = self.timezone.trim().to_string();
        if !valid_timezone(&self.timezone) {
            return Err("Time zone must be a name such as Europe/Oslo.".into());
        }
        if !matches!(self.language.as_str(), "en" | "nb") {
            return Err("Language must be 'en' or 'nb'.".into());
        }
        if !matches!(self.temperature_unit.as_str(), "celsius" | "fahrenheit") {
            return Err("Temperature unit must be 'celsius' or 'fahrenheit'.".into());
        }

        let mut rooms: Vec<String> = Vec::new();
        for room in &self.rooms {
            let room = room.trim();
            if room.is_empty() {
                continue;
            }
            if room.chars().count() > 40 || room.chars().any(char::is_control) {
                return Err("Room names must be 1–40 ordinary characters.".into());
            }
            if !rooms.iter().any(|r| r.eq_ignore_ascii_case(room)) {
                rooms.push(room.to_string());
            }
        }
        if rooms.len() > MAX_ROOMS {
            return Err(format!("At most {MAX_ROOMS} rooms."));
        }
        self.rooms = rooms;
        Ok(self)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct SecuritySettings {
    /// How long a sign-in lasts. Applies to sessions started after the change.
    pub session_hours: u32,
}

impl Default for SecuritySettings {
    fn default() -> Self {
        Self { session_hours: 12 }
    }
}

impl SecuritySettings {
    pub fn validated(self) -> Result<Self, String> {
        if (1..=168).contains(&self.session_hours) {
            Ok(self)
        } else {
            Err("Session length must be between 1 and 168 hours.".into())
        }
    }

    pub fn session_ttl_s(self) -> i64 {
        i64::from(self.session_hours) * 3600
    }
}

/// Stored value, or the default when nothing valid is stored.
pub fn load_home(conn: &Connection) -> rusqlite::Result<HomeSettings> {
    Ok(get(conn, HOME_KEY)?
        .and_then(|v| serde_json::from_str(&v).ok())
        .unwrap_or_default())
}

pub fn save_home(conn: &Connection, home: &HomeSettings) -> rusqlite::Result<()> {
    set(
        conn,
        HOME_KEY,
        &serde_json::to_string(home).unwrap_or_default(),
    )
}

pub fn load_security(conn: &Connection) -> rusqlite::Result<SecuritySettings> {
    Ok(get(conn, SECURITY_KEY)?
        .and_then(|v| serde_json::from_str::<SecuritySettings>(&v).ok())
        .and_then(|s| s.validated().ok())
        .unwrap_or_default())
}

pub fn save_security(conn: &Connection, security: &SecuritySettings) -> rusqlite::Result<()> {
    set(
        conn,
        SECURITY_KEY,
        &serde_json::to_string(security).unwrap_or_default(),
    )
}

pub fn wizard_complete(conn: &Connection) -> rusqlite::Result<bool> {
    Ok(get(conn, WIZARD_KEY)?.as_deref() == Some("1"))
}

pub fn mark_wizard_complete(conn: &Connection) -> rusqlite::Result<()> {
    set(conn, WIZARD_KEY, "1")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn home_settings_are_normalised() {
        let home = HomeSettings {
            home_name: "  Villa  ".into(),
            country: "no".into(),
            timezone: "Europe/Oslo".into(),
            language: "nb".into(),
            temperature_unit: "celsius".into(),
            rooms: vec![
                " Kitchen ".into(),
                "kitchen".into(),
                "".into(),
                "Loft".into(),
            ],
        }
        .validated()
        .unwrap();
        assert_eq!(home.home_name, "Villa");
        assert_eq!(home.country, "NO");
        assert_eq!(home.rooms, vec!["Kitchen".to_string(), "Loft".to_string()]);
    }

    #[test]
    fn bad_home_settings_are_rejected() {
        let base = HomeSettings::default();
        let with = |f: fn(&mut HomeSettings)| {
            let mut h = base.clone();
            f(&mut h);
            h.validated()
        };
        assert!(with(|h| h.home_name = "   ".into()).is_err());
        assert!(with(|h| h.country = "NOR".into()).is_err());
        assert!(with(|h| h.timezone = "Europe/Oslo; DROP".into()).is_err());
        assert!(with(|h| h.timezone = "../etc".into()).is_err());
        assert!(with(|h| h.language = "xx".into()).is_err());
        assert!(with(|h| h.temperature_unit = "kelvin".into()).is_err());
        assert!(with(|h| h.rooms = vec!["x".repeat(41)]).is_err());
        assert!(base.clone().validated().is_ok());
    }

    #[test]
    fn session_length_has_bounds() {
        assert!(SecuritySettings { session_hours: 0 }.validated().is_err());
        assert!(SecuritySettings { session_hours: 169 }.validated().is_err());
        assert_eq!(SecuritySettings { session_hours: 2 }.session_ttl_s(), 7200);
    }
}
