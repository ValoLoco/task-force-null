use crate::log_ring::LogRing;
use crate::types::{ActivityLine, LogLineEvent, TocState};
use chrono::Utc;
use parking_lot::RwLock;
use std::collections::HashMap;
use std::sync::Arc;

const MAX_ACTIVITY: usize = 500;

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum FeedMode {
    #[default]
    Filesystem,
    Sse,
}

#[derive(Debug, Clone)]
pub enum StoreEvent {
    State(TocState),
    LogLine(LogLineEvent),
    FeedPhase {
        phase: String,
        reconnect_secs: Option<u32>,
    },
    Activity(String),
}

#[derive(Debug, Clone)]
pub struct TocStore {
    inner: Arc<RwLock<StoreInner>>,
}

#[derive(Debug, Default)]
struct StoreInner {
    state: Option<TocState>,
    log_buffers: HashMap<String, LogRing>,
    activity: Vec<ActivityLine>,
    feed_mode: FeedMode,
    feed_phase: String,
    reconnect_secs: u32,
    selected_mission: Option<String>,
    version: u64,
}

impl TocStore {
    pub fn new(selected_mission: Option<String>) -> Arc<Self> {
        Arc::new(Self {
            inner: Arc::new(RwLock::new(StoreInner {
                selected_mission,
                feed_phase: "starting".into(),
                feed_mode: FeedMode::Filesystem,
                ..Default::default()
            })),
        })
    }

    pub fn set_feed_mode(&self, mode: FeedMode) {
        let mut inner = self.inner.write();
        inner.feed_mode = mode.clone();
        inner.feed_phase = match mode {
            FeedMode::Filesystem => "filewatch".into(),
            FeedMode::Sse => "connecting".into(),
        };
        inner.reconnect_secs = 0;
        inner.version += 1;
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
                push_activity(&mut inner, "state refresh", "feed");
            }
            StoreEvent::LogLine(ev) => {
                let buf = inner.log_buffers.entry(ev.path.clone()).or_default();
                buf.push_line(ev.line.clone());
                let label = format!("{}/{}", ev.mission, ev.name);
                push_activity(
                    &mut inner,
                    &format!("{}: {}", label, ev.line),
                    &label,
                );
            }
            StoreEvent::FeedPhase {
                phase,
                reconnect_secs,
            } => {
                inner.feed_phase = phase;
                inner.reconnect_secs = reconnect_secs.unwrap_or(0);
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
            log_buffers: inner
                .log_buffers
                .iter()
                .map(|(k, v)| (k.clone(), v.joined_text()))
                .collect(),
            log_rings: inner.log_buffers.clone(),
            activity: inner.activity.clone(),
            feed_mode: inner.feed_mode.clone(),
            feed_phase: inner.feed_phase.clone(),
            reconnect_secs: inner.reconnect_secs,
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
    pub log_rings: HashMap<String, LogRing>,
    pub activity: Vec<ActivityLine>,
    pub feed_mode: FeedMode,
    pub feed_phase: String,
    pub reconnect_secs: u32,
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
    use crate::log_ring::MAX_LOG_LINES;
    use crate::types::LogLineEvent;

    #[test]
    fn version_increments() {
        let store = TocStore::new(None);
        let v0 = store.version();
        let _ = store.apply(StoreEvent::FeedPhase {
            phase: "ok".into(),
            reconnect_secs: None,
        });
        assert!(store.version() > v0);
    }

    #[test]
    fn log_buffer_respects_ring_cap() {
        let store = TocStore::new(None);
        for i in 0..MAX_LOG_LINES + 5 {
            let _ = store.apply(StoreEvent::LogLine(LogLineEvent {
                path: "missions/a/logs/lead.log".into(),
                line: format!("line-{i}"),
                mission: "a".into(),
                name: "lead".into(),
            }));
        }
        let snap = store.snapshot();
        let ring = snap.log_rings.get("missions/a/logs/lead.log").expect("ring");
        assert_eq!(ring.len(), MAX_LOG_LINES);
    }
}