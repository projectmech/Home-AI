//! Typed device actions and the authorization policy that gates them.
//!
//! Every command, whether it comes from the web UI or (later) from an AI
//! proposal, is one of these typed actions and passes through `evaluate`.

use serde::{Deserialize, Serialize};

use crate::devices::DeviceKind;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Role {
    Admin,
    Standard,
    Restricted,
}

impl Role {
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "admin" => Some(Role::Admin),
            "standard" => Some(Role::Standard),
            "restricted" => Some(Role::Restricted),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Role::Admin => "admin",
            Role::Standard => "standard",
            Role::Restricted => "restricted",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "action", rename_all = "snake_case")]
pub enum Action {
    SetPower { on: bool },
    SetBrightness { percent: u8 },
    SetTargetTemperature { celsius: f64 },
    SetPlaying { playing: bool },
    SetVolume { percent: u8 },
    Lock,
    Unlock,
}

impl Action {
    pub fn name(&self) -> &'static str {
        match self {
            Action::SetPower { .. } => "set_power",
            Action::SetBrightness { .. } => "set_brightness",
            Action::SetTargetTemperature { .. } => "set_target_temperature",
            Action::SetPlaying { .. } => "set_playing",
            Action::SetVolume { .. } => "set_volume",
            Action::Lock => "lock",
            Action::Unlock => "unlock",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Risk {
    Medium,
    High,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Decision {
    Allow,
    /// Allowed only after the user re-enters their password.
    RequireStepUp,
    Deny(&'static str),
}

/// Capability and input validation: is this action something this kind of
/// device documents, and are the values in range?
pub fn validate(kind: DeviceKind, action: &Action) -> Result<(), String> {
    let supported = matches!(
        (kind, action),
        (DeviceKind::Light, Action::SetPower { .. })
            | (DeviceKind::Light, Action::SetBrightness { .. })
            | (DeviceKind::Thermostat, Action::SetTargetTemperature { .. })
            | (DeviceKind::Speaker, Action::SetPlaying { .. })
            | (DeviceKind::Speaker, Action::SetVolume { .. })
            | (DeviceKind::Lock, Action::Lock)
            | (DeviceKind::Lock, Action::Unlock)
    );
    if !supported {
        return Err(format!(
            "A {} does not support '{}'.",
            kind.as_str(),
            action.name()
        ));
    }
    match action {
        Action::SetBrightness { percent } | Action::SetVolume { percent } if *percent > 100 => {
            Err("Percent must be between 0 and 100.".into())
        }
        Action::SetTargetTemperature { celsius }
            if !celsius.is_finite() || *celsius < 5.0 || *celsius > 30.0 =>
        {
            Err("Target temperature must be between 5 and 30 °C.".into())
        }
        _ => Ok(()),
    }
}

pub fn risk(action: &Action) -> Risk {
    match action {
        Action::Unlock => Risk::High,
        _ => Risk::Medium,
    }
}

pub fn evaluate(role: Role, action: &Action) -> Decision {
    match (role, risk(action)) {
        (Role::Restricted, _) => {
            Decision::Deny("Your account can view devices but not control them.")
        }
        (Role::Standard, Risk::High) => Decision::Deny("Only an administrator can do this."),
        (Role::Standard, Risk::Medium) | (Role::Admin, Risk::Medium) => Decision::Allow,
        (Role::Admin, Risk::High) => Decision::RequireStepUp,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unlock_is_high_risk_and_gated() {
        assert_eq!(
            evaluate(Role::Admin, &Action::Unlock),
            Decision::RequireStepUp
        );
        assert!(matches!(
            evaluate(Role::Standard, &Action::Unlock),
            Decision::Deny(_)
        ));
        assert!(matches!(
            evaluate(Role::Restricted, &Action::Lock),
            Decision::Deny(_)
        ));
        assert_eq!(evaluate(Role::Standard, &Action::Lock), Decision::Allow);
    }

    #[test]
    fn capabilities_and_ranges_are_checked() {
        assert!(validate(DeviceKind::Light, &Action::SetPower { on: true }).is_ok());
        assert!(validate(DeviceKind::Light, &Action::SetVolume { percent: 10 }).is_err());
        assert!(validate(DeviceKind::Light, &Action::SetBrightness { percent: 101 }).is_err());
        assert!(validate(
            DeviceKind::TemperatureSensor,
            &Action::SetPower { on: true }
        )
        .is_err());
        assert!(validate(
            DeviceKind::Thermostat,
            &Action::SetTargetTemperature { celsius: 40.0 }
        )
        .is_err());
        assert!(validate(
            DeviceKind::Thermostat,
            &Action::SetTargetTemperature { celsius: f64::NAN }
        )
        .is_err());
    }
}
