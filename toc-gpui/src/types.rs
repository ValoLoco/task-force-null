use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TaskRow {
    pub id: String,
    pub owner: String,
    pub status: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct MissionRow {
    pub slug: String,
    pub objective: String,
    pub active: bool,
    pub tasks: Vec<TaskRow>,
    pub done: u32,
    pub total: u32,
    pub pct: u32,
    pub completed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OperatorRow {
    pub id: String,
    pub title: String,
    pub tasks: Vec<OperatorTaskRef>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OperatorTaskRef {
    pub mission: String,
    pub id: String,
    pub status: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct AarEntry {
    pub head: String,
    pub outcome: String,
    pub friction: String,
    pub fix: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
pub struct ModelInventoryRow {
    pub model_id: String,
    pub provider: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
pub struct LearnedOverrideRow {
    pub task_pattern: String,
    pub model_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
pub struct BindingRow {
    pub mission: String,
    pub bind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
pub struct RoutingState {
    pub harness: String,
    pub inventory: Vec<ModelInventoryRow>,
    pub learned_overrides: Vec<LearnedOverrideRow>,
    pub bindings: Vec<BindingRow>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Default)]
pub struct ArmoryState {
    pub present: bool,
    pub pinned_sha: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct OperatorLogMeta {
    pub mission: String,
    pub name: String,
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StatusStrip {
    pub utc: String,
    pub delegation: DelegationFlags,
    pub autonomous: bool,
    pub maturity: MaturityStrip,
    #[serde(default)]
    pub watching: bool,
    #[serde(default)]
    pub watch_interval: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct DelegationFlags {
    pub blockers: bool,
    pub external: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct MaturityStrip {
    pub aar_count: u32,
    pub min_aars: u32,
    pub completed_missions: u32,
    pub min_missions: u32,
    pub pushback: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TocState {
    pub generated_at: String,
    pub status_strip: StatusStrip,
    pub config: HashMap<String, String>,
    pub missions: Vec<MissionRow>,
    pub operators: Vec<OperatorRow>,
    pub aars: Vec<AarEntry>,
    pub routing: RoutingState,
    pub armory: ArmoryState,
    pub operator_logs: Vec<OperatorLogMeta>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct LogLineEvent {
    pub path: String,
    pub line: String,
    pub mission: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActivityLine {
    pub utc: String,
    pub text: String,
    pub source: String,
}

/// Kanban bucket for task status strings (mirrors web TOC).
pub fn status_bucket(status: &str) -> &'static str {
    let s = status.trim().to_lowercase();
    if matches!(s.as_str(), "done" | "complete" | "closed") {
        "done"
    } else if matches!(s.as_str(), "doing" | "in progress" | "active") {
        "doing"
    } else {
        "todo"
    }
}