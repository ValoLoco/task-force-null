//! Headless mission, operator, and log search filters.

use crate::roster::OPERATORS;
use crate::types::{ActivityLine, MissionRow};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum OperatorChip {
    #[default]
    All,
    Command,
    Lead,
    Recon,
    Builder,
    MedicQa,
    Comms,
}

impl OperatorChip {
    pub const ALL: [OperatorChip; 7] = [
        OperatorChip::All,
        OperatorChip::Command,
        OperatorChip::Lead,
        OperatorChip::Recon,
        OperatorChip::Builder,
        OperatorChip::MedicQa,
        OperatorChip::Comms,
    ];

    pub fn label(self) -> &'static str {
        match self {
            OperatorChip::All => "All",
            OperatorChip::Command => "Command",
            OperatorChip::Lead => "Lead",
            OperatorChip::Recon => "Recon",
            OperatorChip::Builder => "Builder",
            OperatorChip::MedicQa => "Medic-QA",
            OperatorChip::Comms => "Comms",
        }
    }

    pub fn operator_id(self) -> Option<&'static str> {
        match self {
            OperatorChip::All => None,
            OperatorChip::Command => Some("command"),
            OperatorChip::Lead => Some("lead"),
            OperatorChip::Recon => Some("recon"),
            OperatorChip::Builder => Some("builder"),
            OperatorChip::MedicQa => Some("medic-qa"),
            OperatorChip::Comms => Some("comms"),
        }
    }

    pub fn matches_operator_id(self, id: &str) -> bool {
        match self.operator_id() {
            None => true,
            Some(want) => id.eq_ignore_ascii_case(want),
        }
    }

    pub fn matches_activity(self, line: &ActivityLine) -> bool {
        if !self.matches_operator_id(&operator_id_from_activity(line)) {
            return false;
        }
        true
    }
}

pub fn operator_id_from_activity(line: &ActivityLine) -> String {
    if let Some(op) = line.source.rsplit('/').next() {
        if OPERATORS.iter().any(|id| id.eq_ignore_ascii_case(op)) {
            return op.to_ascii_lowercase();
        }
    }
    if let Some(op) = OPERATORS
        .iter()
        .find(|id| line.text.to_ascii_lowercase().contains(**id))
    {
        return (*op).to_string();
    }
    if line.source == "feed" || line.source == "system" {
        return String::new();
    }
    line.source.clone()
}

pub fn search_matches(haystack: &str, query: &str) -> bool {
    let q = query.trim();
    if q.is_empty() {
        return true;
    }
    haystack.to_ascii_lowercase().contains(&q.to_ascii_lowercase())
}

pub fn filter_activity_lines<'a>(
    lines: &'a [ActivityLine],
    chip: OperatorChip,
    query: &str,
) -> Vec<&'a ActivityLine> {
    lines
        .iter()
        .filter(|l| chip.matches_activity(l) && search_matches(&format!("{} {}", l.utc, l.text), query))
        .collect()
}

pub fn filter_log_lines<'a>(
    lines: impl Iterator<Item = &'a str>,
    chip: OperatorChip,
    query: &str,
    operator_from_path: &str,
) -> Vec<String> {
    let op_ok = chip.matches_operator_id(operator_from_path);
    lines
        .filter(|line| op_ok && search_matches(line, query))
        .map(|s| s.to_string())
        .collect()
}

pub fn mission_slugs_sorted(missions: &[MissionRow]) -> Vec<String> {
    let mut slugs: Vec<String> = missions.iter().map(|m| m.slug.clone()).collect();
    slugs.sort();
    slugs
}

pub fn default_log_for_mission(
    mission: &str,
    paths: &[(String, String)],
) -> Option<String> {
    paths
        .iter()
        .find(|(m, _)| m == mission)
        .map(|(_, path)| path.clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn operator_chip_filters_by_source() {
        let line = ActivityLine {
            utc: "12:00:00".into(),
            text: "hello".into(),
            source: "alpha/lead".into(),
        };
        assert!(OperatorChip::Lead.matches_activity(&line));
        assert!(!OperatorChip::Recon.matches_activity(&line));
        assert!(OperatorChip::All.matches_activity(&line));
    }

    #[test]
    fn search_is_case_insensitive() {
        assert!(search_matches("Hello WORLD", "world"));
        assert!(!search_matches("Hello", "missing"));
        assert!(search_matches("x", ""));
    }
}