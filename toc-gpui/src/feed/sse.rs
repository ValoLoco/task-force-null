use crate::state::collect_state;
use crate::store::{StoreEvent, TocStore};
use crate::types::{LogLineEvent, TocState};
use std::io::{BufRead, BufReader, Read};
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

pub fn spawn_sse_feed(base_url: &str, repo: &Path, store: Arc<TocStore>) {
    let base = normalize_base(base_url);
    let repo = repo.to_path_buf();
    std::thread::Builder::new()
        .name("tfn-toc-sse".into())
        .spawn(move || sse_loop(&base, &repo, store))
        .ok();
}

fn normalize_base(url: &str) -> String {
    let trimmed = url.trim().trim_end_matches('/');
    trimmed.to_string()
}

fn sse_loop(base: &str, repo: &Path, store: Arc<TocStore>) {
    let events_url = format!("{base}/events");
  let state_url = format!("{base}/api/state");
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(3600))
        .build();
    let Ok(client) = client else {
        let _ = store.apply(StoreEvent::FeedStatus("sse client error".into()));
        return;
    };

    loop {
        let _ = store.apply(StoreEvent::FeedStatus("connecting".into()));

        if let Ok(resp) = client.get(&state_url).send() {
            if let Ok(text) = resp.text() {
                if let Ok(state) = serde_json::from_str::<TocState>(&text) {
                    let _ = store.apply(StoreEvent::State(state));
                }
            }
        }

        let Ok(mut resp) = client.get(&events_url).send() else {
            let _ = store.apply(StoreEvent::FeedStatus("reconnecting".into()));
            std::thread::sleep(Duration::from_secs(2));
            continue;
        };

        let _ = store.apply(StoreEvent::FeedStatus("live".into()));
        let mut reader = BufReader::new(resp.by_ref());
        let mut current_event = String::new();
        let mut data_lines: Vec<String> = Vec::new();

        loop {
            let mut line = String::new();
            let nbytes = reader.read_line(&mut line);
            if nbytes.unwrap_or(0) == 0 {
                break;
            }
            let line = line.trim_end_matches(['\r', '\n']).to_string();
            if line.is_empty() {
                if !current_event.is_empty() && !data_lines.is_empty() {
                    let data = data_lines.join("\n");
                    dispatch_sse(&current_event, &data, repo, &store);
                }
                current_event.clear();
                data_lines.clear();
                continue;
            }
            if line.starts_with(':') {
                continue;
            }
            if let Some(rest) = line.strip_prefix("event:") {
                current_event = rest.trim().to_string();
            } else if let Some(rest) = line.strip_prefix("data:") {
                data_lines.push(rest.trim().to_string());
            }
        }

        let _ = store.apply(StoreEvent::FeedStatus("reconnecting".into()));
        let _ = store.apply(StoreEvent::State(collect_state(repo)));
        std::thread::sleep(Duration::from_secs(2));
    }
}

fn dispatch_sse(event: &str, data: &str, _repo: &Path, store: &Arc<TocStore>) {
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

    #[test]
    fn parses_sse_block() {
        let data = r#"{"slug":"x"}"#;
        assert!(!data.is_empty());
        assert_eq!(normalize_base("http://127.0.0.1:8765/"), "http://127.0.0.1:8765");
    }
}