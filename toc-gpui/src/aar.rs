use crate::types::AarEntry;
use regex::Regex;
use std::path::Path;
use std::sync::LazyLock;

static AAR_HEAD: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^## .+\bmission:").unwrap());

pub fn count_aars(path: &Path) -> u32 {
    if !path.is_file() {
        return 0;
    }
    let Ok(text) = std::fs::read_to_string(path) else {
        return 0;
    };
    let visible = strip_fenced_code(&text);
    visible
        .lines()
        .filter(|line| AAR_HEAD.is_match(line.trim()))
        .count() as u32
}

fn strip_fenced_code(text: &str) -> String {
    let cleaned = text.replace('\r', "");
    let parts: Vec<&str> = cleaned.split("```").collect();
    parts
        .iter()
        .enumerate()
        .filter_map(|(i, chunk)| if i % 2 == 0 { Some(*chunk) } else { None })
        .collect::<Vec<_>>()
        .join("")
}

pub fn parse_aar_entries(aar_path: &Path) -> Vec<AarEntry> {
    let mut entries = Vec::new();
    if !aar_path.is_file() {
        return entries;
    }
    let Ok(text) = std::fs::read_to_string(aar_path) else {
        return entries;
    };
    let visible = strip_fenced_code(&text);
    let mut current: Option<AarEntry> = None;
    for line in visible.lines() {
        if AAR_HEAD.is_match(line.trim()) {
            let head = line.trim().strip_prefix("## ").unwrap_or(line.trim());
            current = Some(AarEntry {
                head: head.to_string(),
                outcome: String::new(),
                friction: String::new(),
                fix: String::new(),
            });
            entries.push(current.as_ref().unwrap().clone());
            continue;
        }
        if let Some(ref mut cur) = current {
            if let Some(rest) = line.strip_prefix("- Outcome:") {
                cur.outcome = rest.trim().to_string();
                if let Some(last) = entries.last_mut() {
                    last.outcome = cur.outcome.clone();
                }
            } else if let Some(rest) = line.strip_prefix("- Friction:") {
                cur.friction = rest.trim().to_string();
                if let Some(last) = entries.last_mut() {
                    last.friction = cur.friction.clone();
                }
            } else if let Some(rest) = line.strip_prefix("- Fix:") {
                cur.fix = rest.trim().to_string();
                if let Some(last) = entries.last_mut() {
                    last.fix = cur.fix.clone();
                }
            }
        }
    }
    entries
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_headings() {
        let text = "## 2026-01-01T00:00:00Z | mission:alpha\n- Outcome: ok\n";
        assert_eq!(count_aars_from_text(text), 1);
    }

    fn count_aars_from_text(text: &str) -> u32 {
        let visible = strip_fenced_code(text);
        visible
            .lines()
            .filter(|line| AAR_HEAD.is_match(line.trim()))
            .count() as u32
    }
}