use std::fs;
use tempfile::TempDir;
use tfn_toc::collect_state;

#[test]
fn collect_state_minimal_repo() {
    let tmp = TempDir::new().unwrap();
    let root = tmp.path();
    fs::create_dir_all(root.join("brain")).unwrap();
    fs::create_dir_all(root.join("missions/setup-mission")).unwrap();
    fs::write(
        root.join("brain/toc-config.md"),
        "DELEGATE_BLOCKERS=false\nAUTONOMOUS_MODE=false\n",
    )
    .unwrap();
    fs::write(root.join("brain/aar-log.md"), "# AAR Log\n").unwrap();
    fs::write(
        root.join("brain/models.md"),
        "## Harness\n| field | value |\n| harness | test |\n",
    )
    .unwrap();
    fs::write(
        root.join("missions/setup-mission/mission.md"),
        "# Intent\n\n**Objective:** GPUI test mission.\n",
    )
    .unwrap();
    fs::write(
        root.join("missions/setup-mission/squad.env"),
        "ACTIVE=1\nAUTONOMOUS_MODE=false\n",
    )
    .unwrap();
    fs::write(
        root.join("missions/setup-mission/board.md"),
        "| ID | Task | Owner | Status | Acceptance |\n|----|------|-------|--------|------------|\n| T-1 | Work | lead | todo | ok |\n",
    )
    .unwrap();

    let state = collect_state(root);
    assert_eq!(state.missions.len(), 1);
    assert!(state.missions[0].active);
    assert_eq!(state.missions[0].tasks.len(), 1);
    assert_eq!(state.operators.len(), 6);
}