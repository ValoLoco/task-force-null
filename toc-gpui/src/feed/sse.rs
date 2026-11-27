use crate::feed::backoff::ReconnectBackoff;
use crate::shutdown::ShutdownSignal;
use crate::state::collect_state;
use crate::store::{StoreEvent, TocStore};
use crate::types::{LogLineEvent, TocState};
use std::io::{BufRead, BufReader, Read};
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

#[derive(Debug, Default)]
struct SseBlock {
    event: String,
    data: Vec<String>,
}

impl SseBlock {
    fn reset(&mut self) {
        self.event.clear();
        self.data.clear();
    }

    fn joined_data(&self) -> String {
        self.data.join("\n")
    }
}

/// Parse one SSE field line (`event:` or `data:`).
pub fn parse_sse_field(line: &str) -> Option<(&str, &str)> {
    let line = line.trim_end_matches(['\r', '\n']);
    if line.starts_with(':') {
        return None;
    }
    if let Some(rest) = line.strip_prefix("event:") {
        return Some(("event", rest.trim()));
    }
    if let Some(rest) = line.strip_prefix("data:") {
        return Some(("data", rest.trim()));
    }
    None
}

/// Apply a parsed SSE block to the store (unit-testable).
pub fn parse_sse_payload(event: &str, data: &str, store: &Arc<TocStore>) {
    dispatch_sse(event, data, store);
}

pub fn spawn_sse_feed(base_url: &str, repo: &Path, store: Arc<TocStore>, shutdown: ShutdownSignal) {
    let base = normalize_base(base_url);
    let repo = repo.to_path_buf();
    std::thread::Builder::new()
        .name("tfn-toc-sse".into())
        .spawn(move || sse_loop(&base, &repo, store, shutdown))
        .ok();
}

fn normalize_base(url: &str) -> String {
    let trimmed = url.trim().trim_end_matches('/');
    trimmed.to_string()
}

fn sse_loop(base: &str, repo: &Path, store: Arc<TocStore>, shutdown: ShutdownSignal) {
    let events_url = format!("{base}/events");
    let state_url = format!("{base}/api/state");
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(3600))
        .build();
    let Ok(client) = client else {
        let _ = store.apply(StoreEvent::FeedPhase {
            phase: "error".into(),
            reconnect_secs: None,
        });
        return;
    };

    let mut backoff = ReconnectBackoff::default();

    while !shutdown.should_stop() {
        let _ = store.apply(StoreEvent::FeedPhase {
            phase: "connecting".into(),
            reconnect_secs: None,
        });

        if let Ok(resp) = client.get(&state_url).send() {
            if let Ok(text) = resp.text() {
                if let Ok(state) = serde_json::from_str::<TocState>(&text) {
                    let _ = store.apply(StoreEvent::State(state));
                }
            }
        }

        let Ok(mut resp) = client.get(&events_url).send() else {
            let delay = backoff.next_delay_secs();
            let _ = store.apply(StoreEvent::FeedPhase {
                phase: "reconnecting".into(),
                reconnect_secs: Some(delay),
            });
            shutdown.sleep_or_stop(Duration::from_secs(delay as u64));
            continue;
        };

        backoff.reset();
        let _ = store.apply(StoreEvent::FeedPhase {
            phase: "live".into(),
            reconnect_secs: None,
        });

        let mut reader = BufReader::new(resp.by_ref());
        let mut block = SseBlock::default();
        loop {
            if shutdown.should_stop() {
                return;
            }
            let mut line = String::new();
            let nbytes = reader.read_line(&mut line);
            if nbytes.unwrap_or(0) == 0 {
                break;
            }
            let trimmed = line.trim_end_matches(['\r', '\n']);
            if trimmed.is_empty() {
                if !block.event.is_empty() && !block.data.is_empty() {
                    dispatch_sse(&block.event, &block.joined_data(), &store);
                }
                block.reset();
                continue;
            }
            if let Some((kind, value)) = parse_sse_field(trimmed) {
                match kind {
                    "event" => block.event = value.to_string(),
                    "data" => block.data.push(value.to_string()),
                    _ => {}
                }
            }
        }

        if shutdown.should_stop() {
            return;
        }

        let delay = backoff.next_delay_secs();
        let _ = store.apply(StoreEvent::FeedPhase {
            phase: "reconnecting".into(),
            reconnect_secs: Some(delay),
        });
        let _ = store.apply(StoreEvent::State(collect_state(repo)));
        shutdown.sleep_or_stop(Duration::from_secs(delay as u64));
    }
}

fn dispatch_sse(event: &str, data: &str, store: &Arc<TocStore>) {
    match event {
        "state" => {
            if let Ok(state) = serde_json::from_str::<TocState>(data) {
                let _ = store.apply(StoreEvent::State(state));
            }
        }
        "log" => {
            if let Ok(payload) = serde_json::from_str::<LogLineEvent>(data) {
                let _ = store.apply(StoreEvent::LogLine(payload));
            }
        }
        _ if data.contains("\"missions\"") => {
            if let Ok(state) = serde_json::from_str::<TocState>(data) {
                let _ = store.apply(StoreEvent::State(state));
            }
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::TocStore;

    #[test]
    fn parses_sse_fields() {
        assert_eq!(
            parse_sse_field("event: log"),
            Some(("event", "log"))
        );
        assert_eq!(
            parse_sse_field("data: {\"x\":1}"),
            Some(("data", "{\"x\":1}"))
        );
        assert!(parse_sse_field(": keepalive").is_none());
    }

    #[test]
    fn parse_log_payload() {
        let store = TocStore::new(None);
        let data = r#"{"path":"p","line":"hi","mission":"m","name":"lead"}"#;
        parse_sse_payload("log", data, &store);
        let snap = store.snapshot();
        assert!(snap.log_buffers.get("p").is_some());
    }

    #[test]
    fn normalize_base_url() {
        assert_eq!(normalize_base("http://127.0.0.1:8765/"), "http://127.0.0.1:8765");
    }
}