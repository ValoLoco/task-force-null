//! Board task moves and operator telemetry (headless-testable).

use crate::board::split_row;
use crate::roster::OPERATORS;
use crate::types::{TaskRow, TocState};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::time::Duration;

const ALLOWED_STATUS: &[&str] = &[
    "todo",
    "doing",
    "in_progress",
    "review",
    "done",
    "blocked",
    "complete",
    "closed",
    "active",
    "in progress",
];

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OperatorTelemetry {
    pub operator: String,
    pub active_tasks: u32,
    pub done_tasks: u32,
    pub blocked_tasks: u32,
    pub total_tasks: u32,
    pub log_lines: u32,
    pub health: String,
}

pub fn normalize_status(status: &str) -> String {
    status.trim().to_lowercase()
}

pub fn status_is_valid(status: &str) -> bool {
    ALLOWED_STATUS.contains(&normalize_status(status).as_str())
}

pub fn next_task_status(current: &str) -> &'static str {
    let cur = normalize_status(current);
    if cur == "blocked" {
        return "in_progress";
    }
    if cur == "doing" || cur == "active" || cur == "in progress" {
        return "review";
    }
    if cur == "in_progress" {
        return "review";
    }
    if cur == "review" {
        return "done";
    }
    if matches!(cur.as_str(), "done" | "complete" | "closed") {
        return "todo";
    }
    if cur == "todo" {
        return "in_progress";
    }
    "in_progress"
}

fn status_class(status: &str) -> &'static str {
    let s = normalize_status(status);
    if matches!(s.as_str(), "done" | "complete" | "closed") {
        "done"
    } else if s == "blocked" {
        "blocked"
    } else {
        "active"
    }
}

fn count_log_lines(path: &Path) -> u32 {
    let Ok(text) = std::fs::read_to_string(path) else {
        return 0;
    };
    text.lines().filter(|l| !l.trim().is_empty()).count() as u32
}

pub fn compute_operator_telemetry(
    snapshot: &TocState,
    mission_slug: &str,
    repo: &Path,
) -> Vec<OperatorTelemetry> {
    let mission = snapshot
        .missions
        .iter()
        .find(|m| m.slug == mission_slug);
    let tasks = mission.map(|m| m.tasks.as_slice()).unwrap_or(&[]);

    let mut out = Vec::new();
    for op_id in OPERATORS {
        let mut row = OperatorTelemetry {
            operator: (*op_id).to_string(),
            active_tasks: 0,
            done_tasks: 0,
            blocked_tasks: 0,
            total_tasks: 0,
            log_lines: 0,
            health: "idle".into(),
        };
        for task in tasks {
            if !task.owner.trim().eq_ignore_ascii_case(op_id) {
                continue;
            }
            row.total_tasks += 1;
            match status_class(&task.status) {
                "done" => row.done_tasks += 1,
                "blocked" => row.blocked_tasks += 1,
                _ => row.active_tasks += 1,
            }
        }
        let log_path = repo
            .join("missions")
            .join(mission_slug)
            .join("logs")
            .join(format!("{op_id}.log"));
        if log_path.is_file() {
            row.log_lines = count_log_lines(&log_path);
        }
        row.health = if row.blocked_tasks > 0 {
            "blocked".into()
        } else if row.active_tasks > 0 || row.log_lines > 0 {
            "active".into()
        } else {
            "idle".into()
        };
        out.push(row);
    }
    out
}

#[derive(Debug, Deserialize)]
struct BoardMoveResponse {
    task: TaskRow,
}

pub fn post_board_move(
    base_url: &str,
    mission: &str,
    task_id: &str,
    status: &str,
) -> Result<TaskRow, String> {
    if !status_is_valid(status) {
        return Err("invalid status".into());
    }
    let base = base_url.trim().trim_end_matches('/');
    let url = format!("{base}{}", board_move_path());
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|e| e.to_string())?;
    let payload = serde_json::json!({
        "mission": mission,
        "task_id": task_id,
        "status": status,
    });
    let resp = client
        .post(&url)
        .header("Content-Type", "application/json")
        .body(payload.to_string())
        .send()
        .map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("POST /api/board/move status {}", resp.status()));
    }
    let body = resp.text().map_err(|e| e.to_string())?;
    let parsed: BoardMoveResponse = serde_json::from_str(&body).map_err(|e| e.to_string())?;
    Ok(parsed.task)
}

pub fn board_move_path() -> &'static str {
    "/api/board/move"
}

pub fn move_board_task_local(
    repo_root: &Path,
    mission: &str,
    task_id: &str,
    target_status: &str,
) -> Result<TaskRow, String> {
    if mission.contains("..") || mission.contains('/') || mission.contains('\\') {
        return Err("invalid mission slug".into());
    }
    if task_id.trim().is_empty() {
        return Err("task_id required".into());
    }
    if !status_is_valid(target_status) {
        return Err("invalid status".into());
    }
    let mission_md = repo_root.join("missions").join(mission).join("mission.md");
    if !mission_md.is_file() {
        return Err("mission not found".into());
    }
    let board = repo_root.join("missions").join(mission).join("board.md");
    if !board.is_file() {
        return Err("mission not found".into());
    }
    let target = write_target_token(target_status);
    let text = std::fs::read_to_string(&board).map_err(|e| e.to_string())?;
    let (new_text, updated) = rewrite_board_status(&text, task_id, &target)?;
    let tmp = board.with_extension("board.md.tmp");
    std::fs::write(&tmp, &new_text).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, &board).map_err(|e| e.to_string())?;
    Ok(updated)
}

fn write_target_token(status: &str) -> String {
    let norm = normalize_status(status);
    if norm == "in progress" {
        "in progress".into()
    } else if norm == "active" {
        "doing".into()
    } else {
        norm
    }
}

fn rewrite_board_status(
    text: &str,
    task_id: &str,
    target: &str,
) -> Result<(String, TaskRow), String> {
    let mut header: Option<Vec<String>> = None;
    let mut skip_done = false;
    let mut status_i: Option<usize> = None;
    let mut owner_i: Option<usize> = None;
    let mut task_i: Option<usize> = None;
    let mut found = false;
    let mut updated = TaskRow {
        id: task_id.into(),
        owner: "-".into(),
        status: target.into(),
        name: "-".into(),
    };
    let mut out = String::new();

    for line in text.replace('\r', "").lines() {
        let raw_line = line;
        let stripped = line.trim();
        if stripped.starts_with("## ") {
            skip_done = stripped
                .to_ascii_lowercase()
                .starts_with("## done this deployment");
            header = None;
            out.push_str(raw_line);
            out.push('\n');
            continue;
        }
        if skip_done {
            out.push_str(raw_line);
            out.push('\n');
            continue;
        }
        if let Some(cells) = split_row(line) {
            let lowered: Vec<String> = cells.iter().map(|c| c.to_lowercase()).collect();
            if lowered.iter().any(|c| c == "status") && lowered.iter().any(|c| c == "owner") {
                status_i = lowered.iter().position(|c| c == "status");
                owner_i = lowered.iter().position(|c| c == "owner");
                task_i = lowered.iter().position(|c| c == "task");
                header = Some(lowered);
                out.push_str(raw_line);
                out.push('\n');
                continue;
            }
            if header.is_some() && !found {
                let row_id = cells.first().cloned().unwrap_or_default();
                if row_id == task_id {
                    found = true;
                    let mut cells = cells;
                    let si = status_i.ok_or("board table missing")?;
                    while cells.len() <= si {
                        cells.push(String::new());
                    }
                    cells[si] = target.to_string();
                    let oi = owner_i.unwrap_or(1);
                    let ti = task_i.unwrap_or(1);
                    updated.owner = cells.get(oi).cloned().unwrap_or_else(|| "-".into());
                    updated.name = cells.get(ti).cloned().unwrap_or_else(|| "-".into());
                    updated.status = target.to_string();
                    out.push_str(&format!("| {} |", cells.join(" | ")));
                    out.push('\n');
                    continue;
                }
            }
        }
        out.push_str(raw_line);
        out.push('\n');
    }
    if !found {
        return Err("task not found".into());
    }
    Ok((out, updated))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use crate::types::{
        ArmoryState, DelegationFlags, MaturityStrip, MissionRow, OperatorLogMeta, RoutingState,
        StatusStrip, TocState,
    };
    use tempfile::TempDir;

    #[test]
    fn cycles_task_statuses() {
        assert_eq!(next_task_status("todo"), "in_progress");
        assert_eq!(next_task_status("in_progress"), "review");
        assert_eq!(next_task_status("doing"), "review");
        assert_eq!(next_task_status("review"), "done");
        assert_eq!(next_task_status("done"), "todo");
        assert_eq!(next_task_status("blocked"), "in_progress");
    }

    #[test]
    fn rejects_invalid_status() {
        assert!(!status_is_valid("bogus"));
        assert!(status_is_valid("todo"));
    }

    #[test]
    fn local_board_update_atomic() {
        let tmp = TempDir::new().unwrap();
        let mission = tmp.path().join("missions/demo");
        std::fs::create_dir_all(mission.join("logs")).unwrap();
        std::fs::write(mission.join("mission.md"), "# m\n").unwrap();
        let board = "\
| ID | Task | Owner | Status | Acceptance |
|----|------|-------|--------|------------|
| T-1 | Alpha | lead | todo | ok |
";
        std::fs::write(mission.join("board.md"), board).unwrap();
        let updated = move_board_task_local(tmp.path(), "demo", "T-1", "doing").unwrap();
        assert_eq!(updated.status, "doing");
        let reread = std::fs::read_to_string(mission.join("board.md")).unwrap();
        assert!(reread.contains("| T-1 | Alpha | lead | doing | ok |"));
    }

    #[test]
    fn local_move_unknown_task() {
        let tmp = TempDir::new().unwrap();
        let mission = tmp.path().join("missions/demo");
        std::fs::create_dir_all(&mission).unwrap();
        std::fs::write(mission.join("mission.md"), "# m\n").unwrap();
        std::fs::write(
            mission.join("board.md"),
            "| ID | Task | Owner | Status |\n|----|------|-------|--------|\n| T-1 | a | lead | todo |\n",
        )
        .unwrap();
        assert!(move_board_task_local(tmp.path(), "demo", "T-9", "done").is_err());
    }

    #[test]
    fn telemetry_counts_operators() {
        let state = TocState {
            generated_at: String::new(),
            status_strip: StatusStrip {
                utc: String::new(),
                delegation: DelegationFlags {
                    blockers: false,
                    external: false,
                },
                autonomous: false,
                maturity: MaturityStrip {
                    aar_count: 0,
                    min_aars: 5,
                    completed_missions: 0,
                    min_missions: 3,
                    pushback: String::new(),
                },
                watching: false,
                watch_interval: None,
            },
            config: Default::default(),
            missions: vec![MissionRow {
                slug: "demo".into(),
                objective: String::new(),
                active: true,
                tasks: vec![
                    TaskRow {
                        id: "T-1".into(),
                        owner: "lead".into(),
                        status: "todo".into(),
                        name: "a".into(),
                    },
                    TaskRow {
                        id: "T-2".into(),
                        owner: "builder".into(),
                        status: "done".into(),
                        name: "b".into(),
                    },
                    TaskRow {
                        id: "T-3".into(),
                        owner: "lead".into(),
                        status: "blocked".into(),
                        name: "c".into(),
                    },
                ],
                done: 1,
                total: 3,
                pct: 33,
                completed: false,
            }],
            operators: vec![],
            aars: vec![],
            routing: RoutingState::default(),
            armory: ArmoryState::default(),
            operator_logs: vec![OperatorLogMeta {
                mission: "demo".into(),
                name: "lead.log".into(),
                path: "missions/demo/logs/lead.log".into(),
            }],
        };
        let tmp = TempDir::new().unwrap();
        let log_dir = tmp.path().join("missions/demo/logs");
        std::fs::create_dir_all(&log_dir).unwrap();
        let mut f = std::fs::File::create(log_dir.join("lead.log")).unwrap();
        writeln!(f, "line one").unwrap();
        writeln!(f, "line two").unwrap();
        let rows = compute_operator_telemetry(&state, "demo", tmp.path());
        let lead = rows.iter().find(|r| r.operator == "lead").unwrap();
        assert_eq!(lead.active_tasks, 1);
        assert_eq!(lead.blocked_tasks, 1);
        assert_eq!(lead.log_lines, 2);
        assert_eq!(lead.health, "blocked");
        let builder = rows.iter().find(|r| r.operator == "builder").unwrap();
        assert_eq!(builder.done_tasks, 1);
        assert_eq!(builder.health, "idle");
    }
}