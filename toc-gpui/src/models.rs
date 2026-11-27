use crate::board::split_row;
use crate::mission::env_bindings;
use crate::types::{BindingRow, LearnedOverrideRow, ModelInventoryRow, RoutingState};
use std::path::Path;

fn section_tables(models_text: &str) -> std::collections::HashMap<String, Vec<String>> {
    let mut sections: std::collections::HashMap<String, Vec<String>> =
        std::collections::HashMap::new();
    let mut current = String::new();
    for line in models_text.replace('\r', "").lines() {
        if let Some(title) = line.strip_prefix("## ") {
            current = title.trim().to_lowercase();
            sections.entry(current.clone()).or_default();
            continue;
        }
        if !current.is_empty() {
            sections.entry(current.clone()).or_default().push(line.to_string());
        }
    }
    sections
}

fn table_rows(lines: &[String]) -> Vec<std::collections::HashMap<String, String>> {
    let mut rows = Vec::new();
    let mut header: Option<Vec<String>> = None;
    for line in lines {
        let Some(cells) = split_row(line) else {
            continue;
        };
        if header.is_none() {
            header = Some(cells.iter().map(|c| c.to_lowercase()).collect());
            continue;
        }
        if cells
            .iter()
            .all(|cell| cell.chars().all(|ch| "-: ".contains(ch)))
        {
            continue;
        }
        let Some(hdr) = header.as_ref() else {
            continue;
        };
        let mut row = std::collections::HashMap::new();
        for (i, key) in hdr.iter().enumerate() {
            row.insert(
                key.clone(),
                cells.get(i).cloned().unwrap_or_default(),
            );
        }
        rows.push(row);
    }
    rows
}

pub fn collect_routing(repo: &Path) -> RoutingState {
    let models_path = repo.join("brain/models.md");
    let mut routing = RoutingState {
        harness: "(models.md missing)".into(),
        ..Default::default()
    };
    if !models_path.is_file() {
        return routing;
    }
    let Ok(text) = std::fs::read_to_string(&models_path) else {
        return routing;
    };
    let sections = section_tables(&text);
    let mut harness = String::new();
    for row in table_rows(sections.get("harness").map(|v| v.as_slice()).unwrap_or(&[])) {
        if row.get("field").map(|s| s.trim()) == Some("harness") {
            harness = row.get("value").cloned().unwrap_or_default().trim().to_string();
        }
    }
    routing.harness = if harness.is_empty() {
        "(not bootstrapped)".into()
    } else {
        harness
    };
    for row in table_rows(sections.get("inventory").map(|v| v.as_slice()).unwrap_or(&[])) {
        let mid = row.get("model_id").cloned().unwrap_or_default().trim().to_string();
        if !mid.is_empty() && mid != "|" && mid != "(no models detected)" {
            routing.inventory.push(ModelInventoryRow {
                model_id: mid,
                provider: row.get("provider").cloned().unwrap_or_default().trim().to_string(),
            });
        }
    }
    for row in table_rows(
        sections
            .get("learned overrides")
            .map(|v| v.as_slice())
            .unwrap_or(&[]),
    ) {
        let pattern = row
            .get("task_pattern")
            .cloned()
            .unwrap_or_default()
            .trim()
            .to_string();
        let model_id = row.get("model_id").cloned().unwrap_or_default().trim().to_string();
        if !pattern.is_empty() && !model_id.is_empty() {
            routing.learned_overrides.push(LearnedOverrideRow {
                task_pattern: pattern,
                model_id,
            });
        }
    }
    let missions_dir = repo.join("missions");
    if missions_dir.is_dir() {
        if let Ok(entries) = std::fs::read_dir(&missions_dir) {
            let mut envs: Vec<_> = entries
                .filter_map(|e| e.ok())
                .map(|e| e.path().join("squad.env"))
                .filter(|p| {
                    p.is_file()
                        && p.parent()
                            .and_then(|d| d.file_name())
                            .and_then(|n| n.to_str())
                            .map(|s| !s.starts_with('_'))
                            .unwrap_or(false)
                })
                .collect();
            envs.sort();
            for env in envs {
                let mission = env
                    .parent()
                    .and_then(|d| d.file_name())
                    .and_then(|n| n.to_str())
                    .unwrap_or("")
                    .to_string();
                for item in env_bindings(&env) {
                    routing.bindings.push(BindingRow {
                        mission: mission.clone(),
                        bind: item,
                    });
                }
            }
        }
    }
    routing
}