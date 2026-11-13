//! Local voice command understanding.
//!
//! Text in (from a speech recogniser, or typed), one typed `Action` out. This
//! is a small fixed grammar, not an AI: it is instant, works offline and can
//! only produce the actions in `policy::Action`. The caller runs the result
//! through the same validation and permission path as a button press.
//!
//! Voice can never unlock anything: a spoken request is not proof of who is
//! speaking, so unlocking stays on the dashboard with password confirmation.

use serde_json::Value;

use crate::devices::{Device, DeviceKind};
use crate::policy::Action;

#[derive(Debug, Clone, PartialEq)]
pub enum Intent {
    /// Do this to this device; `done` is what to say if it works.
    Act {
        device_id: String,
        device_name: String,
        action: Action,
        done: String,
    },
    /// Nothing to execute; just reply. `kind` is "answer", "clarify",
    /// "refused" or "unknown".
    Say { reply: String, kind: &'static str },
}

/// Politeness, wake words and filler that never carry meaning here.
const STOP: &[&str] = &[
    "please", "could", "you", "can", "would", "the", "my", "a", "an", "hey", "ok", "okay",
    "jarvis", "me", "now", "for",
];

fn tokenize(text: &str) -> Vec<String> {
    let lowered = text.to_lowercase();
    let cleaned: String = lowered
        .chars()
        .map(|c| if c.is_alphanumeric() || c == '.' { c } else { ' ' })
        .collect();
    cleaned
        .split_whitespace()
        .map(|t| t.trim_matches('.').to_string())
        .filter(|t| !t.is_empty() && !STOP.contains(&t.as_str()))
        .collect()
}

fn small(w: &str) -> Option<u32> {
    Some(match w {
        "zero" => 0,
        "one" => 1,
        "two" => 2,
        "three" => 3,
        "four" => 4,
        "five" => 5,
        "six" => 6,
        "seven" => 7,
        "eight" => 8,
        "nine" => 9,
        "ten" => 10,
        "eleven" => 11,
        "twelve" => 12,
        "thirteen" => 13,
        "fourteen" => 14,
        "fifteen" => 15,
        "sixteen" => 16,
        "seventeen" => 17,
        "eighteen" => 18,
        "nineteen" => 19,
        "twenty" => 20,
        "thirty" => 30,
        "forty" => 40,
        "fifty" => 50,
        "sixty" => 60,
        "seventy" => 70,
        "eighty" => 80,
        "ninety" => 90,
        _ => return None,
    })
}

fn is_digits(t: &str) -> bool {
    t.chars().next().is_some_and(|c| c.is_ascii_digit())
}

fn is_number_word(t: &str) -> bool {
    is_digits(t) || small(t).is_some() || t == "hundred" || t == "and"
}

/// First number in the words: "50", "21.5", "fifty", "twenty one", "one hundred".
fn find_number(tokens: &[String]) -> Option<f64> {
    let mut i = 0;
    while i < tokens.len() {
        if is_digits(&tokens[i]) {
            if let Ok(n) = tokens[i].parse::<f64>() {
                return Some(n);
            }
        }
        if small(&tokens[i]).is_some() {
            let mut total: u32 = 0;
            let mut j = i;
            while j < tokens.len() {
                let w = tokens[j].as_str();
                if let Some(v) = small(w) {
                    total += v;
                } else if w == "hundred" && j > i {
                    total *= 100;
                } else if w == "and"
                    && j > i
                    && j + 1 < tokens.len()
                    && small(&tokens[j + 1]).is_some()
                {
                    // "one hundred and five"
                } else {
                    break;
                }
                j += 1;
            }
            return Some(total as f64);
        }
        i += 1;
    }
    None
}

fn has(tokens: &[String], words: &[&str]) -> bool {
    tokens.iter().any(|t| words.contains(&t.as_str()))
}

/// The words that say WHICH device: everything that is not a command word or a number.
fn target<'a>(tokens: &'a [String], drop: &[&str]) -> Vec<&'a str> {
    tokens
        .iter()
        .map(String::as_str)
        .filter(|t| !drop.contains(t) && !is_number_word(t))
        .collect()
}

fn norm(w: &str) -> &str {
    w.trim_end_matches('s')
}

fn words_of(d: &Device) -> Vec<String> {
    format!("{} {}", d.name, d.room)
        .to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .map(str::to_string)
        .collect()
}

fn label(d: &Device) -> String {
    format!("{} in {}", d.name, d.room)
}

/// Choose the one device of this kind that the spoken words point at.
fn pick<'a>(
    devices: &'a [Device],
    kind: DeviceKind,
    target: &[&str],
    noun: &str,
) -> Result<&'a Device, String> {
    let cands: Vec<&Device> = devices.iter().filter(|d| d.kind == kind).collect();
    if cands.is_empty() {
        return Err(format!("I don't know of any {noun}."));
    }
    if target.is_empty() {
        if cands.len() == 1 {
            return Ok(cands[0]);
        }
        let names: Vec<String> = cands.iter().map(|d| label(d)).collect();
        return Err(format!("Which {noun}? I know: {}.", names.join(", ")));
    }
    let scored: Vec<(usize, &Device)> = cands
        .iter()
        .map(|d| {
            let words = words_of(d);
            let score = target
                .iter()
                .filter(|t| words.iter().any(|w| norm(w) == norm(t)))
                .count();
            (score, *d)
        })
        .collect();
    let best = scored.iter().map(|(s, _)| *s).max().unwrap_or(0);
    if best == 0 {
        return Err(format!(
            "I couldn't find a {noun} called {}.",
            target.join(" ")
        ));
    }
    let top: Vec<&Device> = scored
        .iter()
        .filter(|(s, _)| *s == best)
        .map(|(_, d)| *d)
        .collect();
    if top.len() == 1 {
        Ok(top[0])
    } else {
        let names: Vec<String> = top.iter().map(|d| label(d)).collect();
        Err(format!("Which one: {}?", names.join(", ")))
    }
}

fn say(reply: impl Into<String>, kind: &'static str) -> Intent {
    Intent::Say {
        reply: reply.into(),
        kind,
    }
}

fn act(d: &Device, action: Action, done: String) -> Intent {
    Intent::Act {
        device_id: d.id.clone(),
        device_name: d.name.clone(),
        action,
        done,
    }
}

fn state_f64(d: &Device, key: &str) -> Option<f64> {
    d.state.get(key).and_then(Value::as_f64)
}

pub fn parse(text: &str, devices: &[Device]) -> Intent {
    let tokens = tokenize(text);
    if tokens.is_empty() {
        return say("I didn't catch anything.", "unknown");
    }
    let number = find_number(&tokens);

    // Never by voice.
    if has(&tokens, &["unlock", "unlocks"]) {
        return say(
            "For safety I can't unlock doors by voice. Use the dashboard and confirm with your password.",
            "refused",
        );
    }
    if has(&tokens, &["all", "every", "everything"]) {
        return say(
            "I can only control one device at a time for now. Name the device.",
            "clarify",
        );
    }

    // Questions: temperature readings.
    if has(&tokens, &["temperature"]) && has(&tokens, &["what", "whats", "how", "tell", "read"]) {
        let want = target(
            &tokens,
            &["temperature", "what", "whats", "s", "how", "tell", "read", "is", "in", "of", "warm", "hot", "cold", "it"],
        );
        let mut parts: Vec<String> = Vec::new();
        for d in devices {
            let value = match d.kind {
                DeviceKind::TemperatureSensor => state_f64(d, "temperature_c"),
                DeviceKind::Thermostat => state_f64(d, "current_c"),
                _ => None,
            };
            let Some(v) = value else { continue };
            let words = words_of(d);
            let matches = want.is_empty()
                || want
                    .iter()
                    .any(|t| words.iter().any(|w| norm(w) == norm(t)));
            if matches {
                let name = label(d);
                parts.push(format!("{name} reads {v:.1} degrees"));
            }
        }
        return if parts.is_empty() {
            say("I have no temperature reading for that.", "answer")
        } else {
            say(format!("{}.", parts.join(". ")), "answer")
        };
    }

    // Volume.
    if has(&tokens, &["volume", "louder", "quieter", "softer"]) {
        let t = target(
            &tokens,
            &["volume", "louder", "quieter", "softer", "up", "down", "set", "to", "percent", "turn", "speaker", "music", "it", "at"],
        );
        let d = match pick(devices, DeviceKind::Speaker, &t, "speaker") {
            Ok(d) => d,
            Err(m) => return say(m, "clarify"),
        };
        if let Some(n) = number {
            if !(0.0..=100.0).contains(&n) {
                return say("Volume must be between 0 and 100 percent.", "clarify");
            }
            let p = n as u8;
            let name = &d.name;
            let done = format!("{name} volume is {p} percent.");
            return act(d, Action::SetVolume { percent: p }, done);
        }
        let current = state_f64(d, "volume").unwrap_or(25.0);
        let target_volume: f64 = if has(&tokens, &["up", "louder"]) {
            (current + 10.0).min(100.0)
        } else if has(&tokens, &["down", "quieter", "softer"]) {
            (current - 10.0).max(0.0)
        } else {
            return say("Volume up, down, or to what percent?", "clarify");
        };
        let p = target_volume as u8;
        let name = &d.name;
        let done = format!("{name} volume is {p} percent.");
        return act(d, Action::SetVolume { percent: p }, done);
    }

    // Thermostat.
    if has(&tokens, &["thermostat", "heating", "heat", "degrees", "degree", "temperature"]) {
        let Some(c) = number else {
            return say("To what temperature? For example: set the thermostat to twenty two.", "clarify");
        };
        let t = target(
            &tokens,
            &["thermostat", "heating", "heat", "degrees", "degree", "temperature", "set", "to", "at", "turn", "up", "down", "make"],
        );
        let d = match pick(devices, DeviceKind::Thermostat, &t, "thermostat") {
            Ok(d) => d,
            Err(m) => return say(m, "clarify"),
        };
        let name = &d.name;
        let done = format!("{name} set to {c} degrees.");
        return act(d, Action::SetTargetTemperature { celsius: c }, done);
    }

    // Brightness.
    if has(&tokens, &["dim", "brighten", "brightness"])
        || (has(&tokens, &["set"]) && number.is_some() && has(&tokens, &["light", "lights", "lamp", "percent"]))
    {
        let Some(n) = number else {
            return say("To what percent?", "clarify");
        };
        if !(0.0..=100.0).contains(&n) {
            return say("Brightness must be between 0 and 100 percent.", "clarify");
        }
        let t = target(
            &tokens,
            &["dim", "brighten", "brightness", "set", "to", "percent", "light", "lights", "lamp", "at", "turn", "of"],
        );
        let d = match pick(devices, DeviceKind::Light, &t, "light") {
            Ok(d) => d,
            Err(m) => return say(m, "clarify"),
        };
        let p = n as u8;
        let name = &d.name;
        let done = format!("{name} set to {p} percent.");
        return act(d, Action::SetBrightness { percent: p }, done);
    }

    // Lock.
    if has(&tokens, &["lock", "locks"]) {
        let t = target(&tokens, &["lock", "locks", "door", "doors"]);
        let d = match pick(devices, DeviceKind::Lock, &t, "lock") {
            Ok(d) => d,
            Err(m) => return say(m, "clarify"),
        };
        let name = &d.name;
        return act(d, Action::Lock, format!("{name} is locked."));
    }

    // Power on/off for lights; on/off for music means play/pause.
    if has(&tokens, &["on", "off"])
        && has(&tokens, &["turn", "switch", "light", "lights", "lamp", "music", "speaker", "radio"])
    {
        let on = match tokens.iter().find(|t| *t == "on" || *t == "off") {
            Some(t) => t == "on",
            None => true,
        };
        let drop = [
            "turn", "switch", "on", "off", "light", "lights", "lamp", "music", "speaker", "radio", "up", "down",
        ];
        if has(&tokens, &["music", "speaker", "radio"]) {
            let t = target(&tokens, &drop);
            let d = match pick(devices, DeviceKind::Speaker, &t, "speaker") {
                Ok(d) => d,
                Err(m) => return say(m, "clarify"),
            };
            let done = if on { "Playing." } else { "Paused." };
            return act(d, Action::SetPlaying { playing: on }, done.to_string());
        }
        let t = target(&tokens, &drop);
        let d = match pick(devices, DeviceKind::Light, &t, "light") {
            Ok(d) => d,
            Err(m) => return say(m, "clarify"),
        };
        let name = &d.name;
        let state = if on { "on" } else { "off" };
        let done = format!("{name} is {state}.");
        return act(d, Action::SetPower { on }, done);
    }

    // Playback.
    if has(&tokens, &["play", "resume", "pause", "stop"]) {
        let playing = !has(&tokens, &["pause", "stop"]);
        let t = target(
            &tokens,
            &["play", "resume", "pause", "stop", "music", "speaker", "song", "songs", "radio"],
        );
        let d = match pick(devices, DeviceKind::Speaker, &t, "speaker") {
            Ok(d) => d,
            Err(m) => return say(m, "clarify"),
        };
        let done = if playing { "Playing." } else { "Paused." };
        return act(d, Action::SetPlaying { playing }, done.to_string());
    }

    say("Sorry, I didn't understand that.", "unknown")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::devices::{Connector, Simulator};

    fn devs() -> Vec<Device> {
        Simulator.discover()
    }

    fn act_of(text: &str) -> (String, Action) {
        match parse(text, &devs()) {
            Intent::Act { device_id, action, .. } => (device_id, action),
            other => panic!("'{text}' gave {other:?}"),
        }
    }

    fn say_of(text: &str) -> (String, &'static str) {
        match parse(text, &devs()) {
            Intent::Say { reply, kind } => (reply, kind),
            other => panic!("'{text}' gave {other:?}"),
        }
    }

    #[test]
    fn numbers_from_digits_and_words() {
        let t = |s: &str| find_number(&tokenize(s));
        assert_eq!(t("to 50 percent"), Some(50.0));
        assert_eq!(t("to 21.5 degrees"), Some(21.5));
        assert_eq!(t("fifty percent"), Some(50.0));
        assert_eq!(t("twenty one degrees"), Some(21.0));
        assert_eq!(t("one hundred percent"), Some(100.0));
        assert_eq!(t("one hundred and five"), Some(105.0));
        assert_eq!(t("no number here"), None);
        assert_eq!(t("inf"), None);
    }

    #[test]
    fn lights_by_room_and_name() {
        assert_eq!(
            act_of("turn on the kitchen light"),
            ("sim-light-kitchen".into(), Action::SetPower { on: true })
        );
        assert_eq!(
            act_of("Hey Jarvis, please turn off the ceiling light!"),
            ("sim-light-living".into(), Action::SetPower { on: false })
        );
        assert_eq!(
            act_of("living room light on"),
            ("sim-light-living".into(), Action::SetPower { on: true })
        );
    }

    #[test]
    fn brightness_thermostat_and_volume() {
        assert_eq!(
            act_of("set the living room light to fifty percent"),
            ("sim-light-living".into(), Action::SetBrightness { percent: 50 })
        );
        assert_eq!(
            act_of("set the thermostat to twenty two degrees"),
            ("sim-thermostat-living".into(), Action::SetTargetTemperature { celsius: 22.0 })
        );
        assert_eq!(
            act_of("volume up"),
            ("sim-speaker-living".into(), Action::SetVolume { percent: 35 })
        );
        assert_eq!(
            act_of("set volume to 70"),
            ("sim-speaker-living".into(), Action::SetVolume { percent: 70 })
        );
    }

    #[test]
    fn music_and_lock() {
        assert_eq!(
            act_of("pause the music"),
            ("sim-speaker-living".into(), Action::SetPlaying { playing: false })
        );
        assert_eq!(
            act_of("turn on the music"),
            ("sim-speaker-living".into(), Action::SetPlaying { playing: true })
        );
        assert_eq!(
            act_of("lock the front door"),
            ("sim-lock-front".into(), Action::Lock)
        );
    }

    #[test]
    fn voice_never_unlocks() {
        let (reply, kind) = say_of("unlock the front door");
        assert_eq!(kind, "refused");
        assert!(reply.contains("dashboard"));
        assert_eq!(say_of("Jarvis please unlock").1, "refused");
    }

    #[test]
    fn questions_and_clarification() {
        let (reply, kind) = say_of("what is the temperature in the bedroom");
        assert_eq!(kind, "answer");
        assert!(reply.contains("19.0"), "{reply}");
        assert_eq!(say_of("turn on the light").1, "clarify");
        assert_eq!(say_of("turn off all the lights").1, "clarify");
        assert_eq!(say_of("dim the light").1, "clarify");
        assert_eq!(say_of("dance for me").1, "unknown");
        assert_eq!(say_of("   ").1, "unknown");
    }

    #[test]
    fn out_of_range_is_not_guessed() {
        assert_eq!(say_of("set volume to one hundred and five").1, "clarify");
    }
}
