use crate::shutdown::ShutdownSignal;
use crate::state::collect_state;
use crate::store::{StoreEvent, TocStore};
use crate::log_io::LogTailer;
use notify::{Config, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

pub fn spawn_fs_watch(repo: &Path, store: Arc<TocStore>, shutdown: ShutdownSignal) {
    let repo = repo.to_path_buf();
    let store_cb = store.clone();
    std::thread::Builder::new()
        .name("tfn-toc-fs".into())
        .spawn(move || {
            let _ = store_cb.apply(StoreEvent::FeedPhase {
                phase: "filewatch".into(),
                reconnect_secs: None,
            });
            let _ = store_cb.apply(StoreEvent::State(collect_state(&repo)));

            let mut tailer = LogTailer::default();
            let mut last_tail = std::time::Instant::now();

            let (tx, rx) = std::sync::mpsc::channel();
            let mut watcher = RecommendedWatcher::new(
                move |res| {
                    let _ = tx.send(res);
                },
                Config::default(),
            );
            if let Ok(ref mut w) = watcher {
                let _ = w.watch(&repo, RecursiveMode::Recursive);
            }

            while !shutdown.should_stop() {
                while rx.try_recv().is_ok() {
                    let state = collect_state(&repo);
                    let _ = store_cb.apply(StoreEvent::State(state));
                }
                if last_tail.elapsed() >= Duration::from_millis(250) {
                    last_tail = std::time::Instant::now();
                    for ev in tailer.poll(&repo) {
                        let _ = store_cb.apply(StoreEvent::LogLine(ev));
                    }
                }
                shutdown.sleep_or_stop(Duration::from_millis(100));
            }
        })
        .ok();
}

/// Unit-test helper: classify notify kinds we care about.
pub fn is_content_event(kind: &EventKind) -> bool {
    matches!(
        kind,
        EventKind::Modify(_) | EventKind::Create(_) | EventKind::Remove(_)
    )
}