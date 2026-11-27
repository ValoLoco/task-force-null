use crate::types::OperatorLogMeta;
use std::path::{Path, PathBuf};

pub fn safe_under_repo(repo: &Path, candidate: &Path) -> Option<PathBuf> {
    let resolved = candidate.canonicalize().ok()?;
    let repo_resolved = repo.canonicalize().unwrap_or_else(|_| repo.to_path_buf());
    resolved.strip_prefix(&repo_resolved).ok()?;
    Some(resolved)
}

pub fn rel_path(repo: &Path, full: &Path) -> Option<String> {
    let repo_resolved = repo.canonicalize().unwrap_or_else(|_| repo.to_path_buf());
    let resolved = full.canonicalize().ok()?;
    resolved
        .strip_prefix(&repo_resolved)
        .ok()
        .map(|p| p.display().to_string())
}

pub fn discover_operator_logs(repo: &Path) -> Vec<OperatorLogMeta> {
    let mut logs = Vec::new();
    let missions = repo.join("missions");
    if missions.is_dir() {
        collect_logs_under(&missions, repo, &mut logs);
    }
    let repo_logs = repo.join("logs");
    if repo_logs.is_dir() {
        collect_flat_logs(&repo_logs, repo, "logs", &mut logs);
    }
    logs.sort_by(|a, b| a.path.cmp(&b.path));
    logs
}

fn collect_logs_under(missions: &Path, repo: &Path, out: &mut Vec<OperatorLogMeta>) {
    let Ok(entries) = std::fs::read_dir(missions) else {
        return;
    };
    for entry in entries.filter_map(|e| e.ok()) {
        let slug = entry.file_name().to_string_lossy().to_string();
        if slug.starts_with('_') {
            continue;
        }
        let log_dir = entry.path().join("logs");
        if log_dir.is_dir() {
            collect_flat_logs(&log_dir, repo, &slug, out);
        }
    }
}

fn collect_flat_logs(dir: &Path, repo: &Path, mission_label: &str, out: &mut Vec<OperatorLogMeta>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.filter_map(|e| e.ok()) {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        if path.extension().and_then(|e| e.to_str()) != Some("log") {
            continue;
        }
        if safe_under_repo(repo, &path).is_none() {
            continue;
        }
        let rel = rel_path(repo, &path).unwrap_or_else(|| path.display().to_string());
        out.push(OperatorLogMeta {
            mission: mission_label.to_string(),
            name: path
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("log")
                .to_string(),
            path: rel,
        });
    }
}

pub fn watch_paths(repo: &Path) -> Vec<PathBuf> {
    let mut paths = vec![
        repo.join("brain/toc-config.md"),
        repo.join("brain/aar-log.md"),
        repo.join("brain/models.md"),
    ];
    let missions = repo.join("missions");
    if missions.is_dir() {
        if let Ok(entries) = std::fs::read_dir(&missions) {
            let mut dirs: Vec<_> = entries
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
            dirs.sort();
            for slug_dir in dirs {
                for name in ["mission.md", "board.md", "squad.env"] {
                    let p = slug_dir.join(name);
                    if p.is_file() {
                        paths.push(p);
                    }
                }
                let log_dir = slug_dir.join("logs");
                if log_dir.is_dir() {
                    if let Ok(logs) = std::fs::read_dir(&log_dir) {
                        for log in logs.filter_map(|e| e.ok()) {
                            if safe_under_repo(repo, &log.path()).is_some() {
                                paths.push(log.path());
                            }
                        }
                    }
                }
            }
        }
    }
    let repo_logs = repo.join("logs");
    if repo_logs.is_dir() {
        if let Ok(logs) = std::fs::read_dir(&repo_logs) {
            for log in logs.filter_map(|e| e.ok()) {
                if log.path().is_file() && safe_under_repo(repo, &log.path()).is_some() {
                    paths.push(log.path());
                }
            }
        }
    }
    let pinned = repo.join("armory/ecc/PINNED_SHA");
    if pinned.is_file() {
        paths.push(pinned);
    }
    paths
}