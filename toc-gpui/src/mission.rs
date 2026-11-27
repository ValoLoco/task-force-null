use crate::board::parse_tasks;
use crate::types::MissionRow;
use regex::Regex;
use std::path::Path;
use std::sync::LazyLock;

static ACTIVE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^ACTIVE=1\s*$").unwrap());
static OBJECTIVE_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"\*\*Objective:\*\*\s*(.+)").unwrap());

pub fn objective_of(mission_md: &Path) -> String {
    if !mission_md.is_file() {
        return "(no mission.md)".into();
    }
    let Ok(text) = std::fs::read_to_string(mission_md) else {
        return "(no mission.md)".into();
    };
    if let Some(caps) = OBJECTIVE_RE.captures(&text) {
        return clip_objective(&caps[1]);
    }
    if let Some(line) = text.lines().find(|l| l.starts_with("Objective:")) {
        let obj = line.split_once(':').map(|(_, v)| v).unwrap_or("").trim();
        return clip_objective(obj);
    }
    "(objective not stated)".into()
}

fn clip_objective(obj: &str) -> String {
    let obj = obj.split_whitespace().collect::<Vec<_>>().join(" ");
    if obj.len() > 96 {
        format!("{}...", &obj[..93])
    } else {
        obj
    }
}

pub fn is_active(env_path: &Path) -> bool {
    if !env_path.is_file() {
        return false;
    }
    let Ok(text) = std::fs::read_to_string(env_path) else {
        return false;
    };
    text.replace('\r', "")
        .lines()
        .map(str::trim)
        .any(|line| ACTIVE_RE.is_match(line))
}

pub fn env_bindings(env_path: &Path) -> Vec<String> {
    let mut rows = Vec::new();
    if !env_path.is_file() {
        return rows;
    }
    let Ok(text) = std::fs::read_to_string(env_path) else {
        return rows;
    };
    for line in text.replace('\r', "").lines() {
        if let Some((key, value)) = line.split_once('=') {
            if key.starts_with("MODEL_BIND_") && !value.trim().is_empty() {
                rows.push(format!("{}={}", key, value.trim()));
            }
        }
    }
    rows
}

pub fn mission_rows(repo: &Path) -> Vec<MissionRow> {
    let missions = repo.join("missions");
    if !missions.is_dir() {
        return Vec::new();
    }
    let mut rows = Vec::new();
    let Ok(entries) = std::fs::read_dir(&missions) else {
        return rows;
    };
    let mut paths: Vec<_> = entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.join("mission.md").is_file()
                && p.file_name()
                    .and_then(|n| n.to_str())
                    .map(|s| !s.starts_with('_'))
                    .unwrap_or(false)
        })
        .collect();
    paths.sort();
    for dir in paths {
        let slug = dir
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("")
            .to_string();
        let board = dir.join("board.md");
        let tasks = if board.is_file() {
            std::fs::read_to_string(&board)
                .map(|t| parse_tasks(&t))
                .unwrap_or_default()
        } else {
            Vec::new()
        };
        let done = tasks
            .iter()
            .filter(|t| {
                matches!(
                    t.status.trim().to_lowercase().as_str(),
                    "done" | "complete" | "closed"
                )
            })
            .count() as u32;
        let total = tasks.len() as u32;
        let pct = if total == 0 {
            0
        } else {
            (100 * done + total / 2) / total
        };
        let completed = total > 0 && done == total;
        rows.push(MissionRow {
            slug,
            objective: objective_of(&dir.join("mission.md")),
            active: is_active(&dir.join("squad.env")),
            tasks,
            done,
            total,
            pct,
            completed,
        });
    }
    rows
}