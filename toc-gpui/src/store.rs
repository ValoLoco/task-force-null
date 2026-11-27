use crate::types::{ActivityLine, LogLineEvent, TocState};
use chrono::Utc;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::Arc;

const MAX_ACTIVITY: usize = 500;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FeedMode {
    Filesystem,
    Sse,
}

#[derive(Debug, Clone)]
pub enum StoreEvent {
    State(TocState),
    LogLine(LogLineEvent),
    FeedStatus(String),
    Activity(String),
}

#[derive(Debug, Clone)]
pub struct TocStore {
    inner: Arc<RwLock<StoreInner>>,
}

#[derive(Debug, Default)]
struct StoreInner {
    state: Option<TocState>,
    log_buffers: HashMap<String, String>,
    activity: Vec<ActivityLine>,
    feed_status: String,
    selected_mission: Option<String>,
    version: u64,
}

impl TocStore {
    pub fn new(selected_mission: Option<String>) -> Arc<Self> {
        Arc::new(Self {
            inner: Arc::new(RwLock::new(StoreInner {
                selected_mission,
                feed_status: "starting".into(),
                ..Default::default()
            })),
        })
    }

    pub fn apply(&self, event: StoreEvent) -> u64 {
        let mut inner = self.inner.write();
        inner.version += 1;
        match event {
            StoreEvent::State(state) => {
                if inner.selected_mission.is_none() {
                    inner.selected_mission = state
                        .missions
                        .iter()
                        .find(|m| m.active)
                        .map(|m| m.slug.clone())
                        .or_else(|| state.missions.first().map(|m| m.slug.clone()));
                }
                inner.state = Some(state);
                push_activity(
                    &mut inner,
                    "state refresh",
                    "feed",
                );
            }
            StoreEvent::LogLine(ev) => {
                let buf = inner.log_buffers.entry(ev.path.clone()).or_default();
                if !buf.is_empty() && !buf.ends_with('\n') {
                    buf.push('\n');
                }
                buf.push_str(&ev.line);
                buf.push('\n');
                let label = format!("{}/{}", ev.mission, ev.name);
                push_activity(
                    &mut inner,
                    &format!("{}: {}", label, ev.line),
                    &label,
                );
            }
            StoreEvent::FeedStatus(status) => {
                inner.feed_status = status;
            }
            StoreEvent::Activity(text) => {
                push_activity(&mut inner, &text, "system");
            }
        }
        inner.version
    }

    pub fn version(&self) -> u64 {
        self.inner.read().version
    }

    pub fn snapshot(&self) -> StoreSnapshot {
        let inner = self.inner.read();
        StoreSnapshot {
            state: inner.state.clone(),
            log_buffers: inner.log_buffers.clone(),
            activity: inner.activity.clone(),
            feed_status: inner.feed_status.clone(),
            selected_mission: inner.selected_mission.clone(),
            version: inner.version,
        }
    }

    pub fn set_selected_mission(&self, slug: Option<String>) {
        let mut inner = self.inner.write();
        inner.selected_mission = slug;
        inner.version += 1;
    }
}

#[derive(Debug, Clone)]
pub struct StoreSnapshot {
    pub state: Option<TocState>,
    pub log_buffers: HashMap<String, String>,
    pub activity: Vec<ActivityLine>,
    pub feed_status: String,
    pub selected_mission: Option<String>,
    pub version: u64,
}

fn push_activity(inner: &mut StoreInner, text: &str, source: &str) {
    let line = ActivityLine {
        utc: Utc::now().format("%H:%M:%S").to_string(),
        text: text.to_string(),
        source: source.to_string(),
    };
    inner.activity.push(line);
    if inner.activity.len() > MAX_ACTIVITY {
        let drain = inner.activity.len() - MAX_ACTIVITY;
        inner.activity.drain(0..drain);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_increments() {
        let store = TocStore::new(None);
        let v0 = store.version();
        let _ = store.apply(StoreEvent::FeedStatus("ok".into()));
        assert!(store.version() > v0);
    }
}