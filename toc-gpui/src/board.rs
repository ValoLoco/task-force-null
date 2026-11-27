use crate::types::TaskRow;
use regex::Regex;
use std::sync::LazyLock;

static SEP_RE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^:?-{3,}:?$").unwrap());

pub fn split_row(line: &str) -> Option<Vec<String>> {
    let text = line.trim();
    if !text.starts_with('|') {
        return None;
    }
    let cells: Vec<String> = text
        .trim_matches('|')
        .split('|')
        .map(|c| c.trim().to_string())
        .collect();
    if cells.is_empty() {
        return None;
    }
    if cells.iter().all(|cell| {
        let c = cell.replace(' ', "");
        SEP_RE.is_match(&c) || cell.is_empty()
    }) {
        return None;
    }
    if cells
        .iter()
        .all(|cell| cell.chars().all(|ch| "-: ".contains(ch)) && cell.contains('-'))
    {
        return None;
    }
    Some(cells)
}

pub fn parse_tasks(board_text: &str) -> Vec<TaskRow> {
    let mut tasks = Vec::new();
    let mut header: Option<Vec<String>> = None;
    let mut skip_done_section = false;

    for line in board_text.replace('\r', "").lines() {
        let stripped = line.trim();
        if stripped.starts_with("## ") {
            skip_done_section = stripped
                .to_ascii_lowercase()
                .starts_with("## done this deployment");
            header = None;
            continue;
        }
        if skip_done_section {
            continue;
        }
        let Some(cells) = split_row(line) else {
            if line.starts_with('#') {
                header = None;
            }
            continue;
        };
        let lowered: Vec<String> = cells.iter().map(|c| c.to_lowercase()).collect();
        if lowered.iter().any(|c| c == "status")
            && lowered.iter().any(|c| c == "owner")
        {
            header = Some(lowered);
            continue;
        }
        let Some(hdr) = header.as_ref() else {
            continue;
        };
        let owner_i = hdr.iter().position(|c| c == "owner");
        let status_i = hdr.iter().position(|c| c == "status");
        let task_i = hdr.iter().position(|c| c == "task");
        if owner_i.is_none() || status_i.is_none() {
            continue;
        }
        let owner_i = owner_i.unwrap();
        let status_i = status_i.unwrap();
        let task_i = task_i.unwrap_or(1);
        let task_id = cells.first().cloned().unwrap_or_default();
        if task_id.is_empty() || task_id.eq_ignore_ascii_case("id") {
            continue;
        }
        let owner = cells.get(owner_i).cloned().unwrap_or_else(|| "-".into());
        let status = cells.get(status_i).cloned().unwrap_or_else(|| "-".into());
        let name = cells.get(task_i).cloned().unwrap_or_else(|| "-".into());
        tasks.push(TaskRow {
            id: task_id,
            owner,
            status,
            name,
        });
    }
    tasks
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_standard_board() {
        let text = "\
| ID | Task | Owner | Status | Acceptance |
|----|------|-------|--------|------------|
| T-1 | Alpha | lead | todo | ok |
| T-2 | Beta | builder | doing | ok |
";
        let tasks = parse_tasks(text);
        assert_eq!(tasks.len(), 2);
        assert_eq!(tasks[0].id, "T-1");
        assert_eq!(tasks[0].owner, "lead");
        assert_eq!(tasks[1].status, "doing");
    }
}