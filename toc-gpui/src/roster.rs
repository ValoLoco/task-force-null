use crate::types::{MissionRow, OperatorRow, OperatorTaskRef};
use std::path::Path;

pub const OPERATORS: &[&str] = &[
    "command",
    "lead",
    "recon",
    "builder",
    "medic-qa",
    "comms",
];

pub fn operator_roster(repo: &Path, missions: &[MissionRow]) -> Vec<OperatorRow> {
    let mut roster = Vec::new();
    for op_id in OPERATORS {
        let profile_path = repo.join("profiles").join(format!("{op_id}.md"));
        let mut title = (*op_id).to_string();
        if profile_path.is_file() {
            if let Ok(text) = std::fs::read_to_string(&profile_path) {
                if let Some(first) = text.lines().next() {
                    if let Some(rest) = first.strip_prefix("# ") {
                        title = rest.trim().to_string();
                    }
                }
            }
        }
        let mut owned = Vec::new();
        for row in missions {
            for task in &row.tasks {
                if task.owner.trim().eq_ignore_ascii_case(op_id) {
                    owned.push(OperatorTaskRef {
                        mission: row.slug.clone(),
                        id: task.id.clone(),
                        status: task.status.clone(),
                        name: task.name.clone(),
                    });
                }
            }
        }
        roster.push(OperatorRow {
            id: (*op_id).to_string(),
            title,
            tasks: owned,
        });
    }
    roster
}