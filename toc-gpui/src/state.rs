use crate::aar::{count_aars, parse_aar_entries};
use crate::armory::collect_armory;
use crate::config::{as_bool, load_config};
use crate::mission::mission_rows;
use crate::models::collect_routing;
use crate::paths::discover_operator_logs;
use crate::roster::operator_roster;
use crate::types::{
    DelegationFlags, MaturityStrip, StatusStrip, TocState,
};
use chrono::Utc;
use std::path::Path;

pub fn collect_state(repo: &Path) -> TocState {
    let repo = repo
        .canonicalize()
        .unwrap_or_else(|_| repo.to_path_buf());
    let vals = load_config(&repo);
    let min_aars: u32 = vals
        .get("MIN_AARS_FOR_DELEGATION")
        .and_then(|s| s.parse().ok())
        .unwrap_or(5);
    let min_missions: u32 = vals
        .get("MIN_COMPLETED_MISSIONS_FOR_DELEGATION")
        .and_then(|s| s.parse().ok())
        .unwrap_or(3);
    let aar_path = repo.join("brain/aar-log.md");
    let aar_count = count_aars(&aar_path);
    let missions = mission_rows(&repo);
    let operators = operator_roster(&repo, &missions);
    let completed = missions.iter().filter(|m| m.completed).count() as u32;
    let pushback = if aar_count >= min_aars && completed >= min_missions {
        "pushback ready"
    } else {
        "pushback active"
    };
    let now = Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();

    TocState {
        generated_at: now.clone(),
        status_strip: StatusStrip {
            utc: now,
            delegation: DelegationFlags {
                blockers: as_bool(vals.get("DELEGATE_BLOCKERS").map(String::as_str).unwrap_or("false")),
                external: as_bool(vals.get("DELEGATE_EXTERNAL").map(String::as_str).unwrap_or("false")),
            },
            autonomous: as_bool(vals.get("AUTONOMOUS_MODE").map(String::as_str).unwrap_or("false")),
            maturity: MaturityStrip {
                aar_count,
                min_aars,
                completed_missions: completed,
                min_missions,
                pushback: pushback.into(),
            },
            watching: false,
            watch_interval: None,
        },
        config: vals,
        missions,
        operators,
        aars: parse_aar_entries(&aar_path),
        routing: collect_routing(&repo),
        armory: collect_armory(&repo),
        operator_logs: discover_operator_logs(&repo),
    }
}

pub fn collect_state_json(repo: &Path) -> String {
    serde_json::to_string(&collect_state(repo)).unwrap_or_else(|_| "{}".into())
}
