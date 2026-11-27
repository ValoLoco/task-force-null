use crate::types::ArmoryState;
use std::path::Path;

pub fn collect_armory(repo: &Path) -> ArmoryState {
    let armory = repo.join("armory/ecc");
    let pinned = armory.join("PINNED_SHA");
    let mut out = ArmoryState {
        present: armory.is_dir(),
        pinned_sha: "(missing)".into(),
    };
    if pinned.is_file() {
        if let Ok(text) = std::fs::read_to_string(&pinned) {
            let first = text.lines().next().unwrap_or("").trim();
            out.pinned_sha = if first.is_empty() {
                "(empty)".into()
            } else {
                first.to_string()
            };
        }
    }
    out
}