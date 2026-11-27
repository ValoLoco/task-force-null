use std::collections::HashMap;
use std::path::Path;

pub const KEYS: &[&str] = &[
    "DELEGATE_BLOCKERS",
    "DELEGATE_EXTERNAL",
    "AUTONOMOUS_MODE",
    "MIN_AARS_FOR_DELEGATION",
    "MIN_COMPLETED_MISSIONS_FOR_DELEGATION",
];

pub fn defaults() -> HashMap<String, String> {
    HashMap::from([
        (
            "DELEGATE_BLOCKERS".to_string(),
            "false".to_string(),
        ),
        (
            "DELEGATE_EXTERNAL".to_string(),
            "false".to_string(),
        ),
        (
            "AUTONOMOUS_MODE".to_string(),
            "false".to_string(),
        ),
        (
            "MIN_AARS_FOR_DELEGATION".to_string(),
            "5".to_string(),
        ),
        (
            "MIN_COMPLETED_MISSIONS_FOR_DELEGATION".to_string(),
            "3".to_string(),
        ),
    ])
}

pub fn parse_config(text: &str) -> HashMap<String, String> {
    let mut vals = defaults();
    for line in text.replace('\r', "").lines() {
        let bare = line.trim();
        if bare.is_empty() || bare.starts_with('#') {
            continue;
        }
        let Some((key, value)) = bare.split_once('=') else {
            continue;
        };
        let key = key.trim();
        if KEYS.contains(&key) {
            vals.insert(key.to_string(), value.trim().to_lowercase());
        }
    }
    vals
}

pub fn load_config(repo: &Path) -> HashMap<String, String> {
    let path = repo.join("brain/toc-config.md");
    if path.is_file() {
        if let Ok(text) = std::fs::read_to_string(&path) {
            return parse_config(&text);
        }
    }
    defaults()
}

pub fn as_bool(value: &str) -> bool {
    matches!(
        value.trim().to_lowercase().as_str(),
        "1" | "true" | "yes" | "on"
    )
}