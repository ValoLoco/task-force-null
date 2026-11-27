//! Commander chat JSONL storage, HTTP client, and bounded in-memory rings.

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet, VecDeque};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Duration;

pub const MAX_CHAT_MESSAGES: usize = 500;
pub const CHAT_JSONL: &str = "commander-chat.jsonl";
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatMessage {
    pub ts: String,
    pub mission: String,
    pub sender: String,
    pub text: String,
}

impl ChatMessage {
    pub fn dedupe_key(&self) -> (String, String, String) {
        (self.ts.clone(), self.sender.clone(), self.text.clone())
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ChatRing {
    messages: VecDeque<ChatMessage>,
    keys: HashSet<(String, String, String)>,
}

impl ChatRing {
    pub fn push(&mut self, msg: ChatMessage) {
        let key = msg.dedupe_key();
        if self.keys.contains(&key) {
            return;
        }
        self.keys.insert(key);
        self.messages.push_back(msg);
        while self.messages.len() > MAX_CHAT_MESSAGES {
            if let Some(old) = self.messages.pop_front() {
                self.keys.remove(&old.dedupe_key());
            }
        }
    }

    pub fn merge_all(&mut self, msgs: impl IntoIterator<Item = ChatMessage>) {
        for msg in msgs {
            self.push(msg);
        }
    }

    pub fn len(&self) -> usize {
        self.messages.len()
    }

    pub fn messages(&self) -> impl Iterator<Item = &ChatMessage> {
        self.messages.iter()
    }
}

pub fn chat_log_path(repo: &Path, mission: &str) -> PathBuf {
    repo.join("missions")
        .join(mission)
        .join("logs")
        .join(CHAT_JSONL)
}

pub fn read_jsonl_file(path: &Path) -> Vec<ChatMessage> {
    let Ok(text) = std::fs::read_to_string(path) else {
        return Vec::new();
    };
    parse_jsonl_text(&text)
}

pub fn parse_jsonl_text(text: &str) -> Vec<ChatMessage> {
    let mut out = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        if let Ok(msg) = serde_json::from_str::<ChatMessage>(line) {
            if !msg.ts.is_empty() && !msg.mission.is_empty() && !msg.text.is_empty() {
                out.push(msg);
            }
        }
    }
    out
}

pub fn append_jsonl_local(repo: &Path, mission: &str, sender: &str, text: &str) -> Result<ChatMessage, String> {
    let logs_dir = repo.join("missions").join(mission).join("logs");
    std::fs::create_dir_all(&logs_dir).map_err(|e| e.to_string())?;
    let ts = chrono::Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string();
    let msg = ChatMessage {
        ts,
        mission: mission.to_string(),
        sender: sender.to_string(),
        text: text.to_string(),
    };
    let line = serde_json::to_string(&msg).map_err(|e| e.to_string())? + "\n";
    let path = chat_log_path(repo, mission);
    std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .and_then(|mut f| f.write_all(line.as_bytes()))
        .map_err(|e| e.to_string())?;
    Ok(msg)
}

#[derive(Debug, Default)]
pub struct ChatTailer {
    offsets: HashMap<String, u64>,
}

impl ChatTailer {
    pub fn poll_repo(&mut self, repo: &Path) -> Vec<ChatMessage> {
        let missions_root = repo.join("missions");
        let Ok(entries) = std::fs::read_dir(&missions_root) else {
            return Vec::new();
        };
        let mut out = Vec::new();
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let slug = entry.file_name().to_string_lossy().to_string();
            if slug.starts_with('_') {
                continue;
            }
            let log_path = path.join("logs").join(CHAT_JSONL);
            if !log_path.is_file() {
                continue;
            }
            let rel = format!("missions/{slug}/logs/{CHAT_JSONL}");
            out.extend(self.poll_file(&rel, &log_path));
        }
        out
    }

    fn poll_file(&mut self, rel: &str, full: &Path) -> Vec<ChatMessage> {
        let Ok(meta) = std::fs::metadata(full) else {
            return Vec::new();
        };
        let size = meta.len();
        let mut offset = *self.offsets.get(rel).unwrap_or(&0);
        if size < offset {
            offset = 0;
        }
        if size == offset {
            self.offsets.insert(rel.to_string(), offset);
            return Vec::new();
        }
        let Ok(mut file) = std::fs::File::open(full) else {
            return Vec::new();
        };
        use std::io::{Read, Seek, SeekFrom};
        if file.seek(SeekFrom::Start(offset)).is_err() {
            return Vec::new();
        }
        let mut chunk = Vec::new();
        let read = file.read_to_end(&mut chunk).unwrap_or(0);
        self.offsets.insert(rel.to_string(), offset + read as u64);
        let text = String::from_utf8_lossy(&chunk);
        parse_jsonl_text(&text)
    }
}

#[derive(Debug, Deserialize)]
struct ChatListResponse {
    messages: Vec<ChatMessage>,
}

pub fn fetch_chat_http(base_url: &str, mission: &str, limit: u32) -> Result<Vec<ChatMessage>, String> {
    let base = base_url.trim().trim_end_matches('/');
    let url = format!(
        "{base}/api/chat?mission={}&limit={}",
        url_encode(mission),
        limit.max(1).min(MAX_CHAT_MESSAGES as u32)
    );
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|e| e.to_string())?;
    let resp = client.get(&url).send().map_err(|e| e.to_string())?;
    if !resp.status().is_success() {
        return Err(format!("GET /api/chat status {}", resp.status()));
    }
    let body = resp.text().map_err(|e| e.to_string())?;
    let parsed: ChatListResponse = serde_json::from_str(&body).map_err(|e| e.to_string())?;
    Ok(parsed.messages)
}

pub fn post_chat_http(base_url: &str, mission: &str, text: &str) -> Result<ChatMessage, String> {
    let base = base_url.trim().trim_end_matches('/');
    let url = format!("{base}/api/chat");
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|e| e.to_string())?;
    let payload = serde_json::json!({
        "mission": mission,
        "sender": "user",
        "text": text,
    });
    let resp = client
        .post(&url)
        .header("Content-Type", "application/json")
        .body(payload.to_string())
        .send()
        .map_err(|e| e.to_string())?;
    if resp.status().as_u16() != 201 {
        return Err(format!("POST /api/chat status {}", resp.status()));
    }
    let body = resp.text().map_err(|e| e.to_string())?;
    serde_json::from_str(&body).map_err(|e| e.to_string())
}

pub fn load_mission_chat(repo: &Path, mission: &str) -> Vec<ChatMessage> {
    let path = chat_log_path(repo, mission);
    let mut msgs = read_jsonl_file(&path);
    if msgs.len() > MAX_CHAT_MESSAGES {
        msgs = msgs.split_off(msgs.len() - MAX_CHAT_MESSAGES);
    }
    msgs
}

fn url_encode(value: &str) -> String {
    let mut out = String::new();
    for b in value.bytes() {
        match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(b as char);
            }
            _ => {
                out.push('%');
                out.push_str(&format!("{b:02X}"));
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn ring_dedupes_and_caps() {
        let mut ring = ChatRing::default();
        let msg = ChatMessage {
            ts: "2020-01-01T00:00:00Z".into(),
            mission: "a".into(),
            sender: "user".into(),
            text: "hi".into(),
        };
        ring.push(msg.clone());
        ring.push(msg);
        assert_eq!(ring.len(), 1);
        for i in 0..MAX_CHAT_MESSAGES + 10 {
            ring.push(ChatMessage {
                ts: format!("t-{i}"),
                mission: "a".into(),
                sender: "user".into(),
                text: format!("line-{i}"),
            });
        }
        assert_eq!(ring.len(), MAX_CHAT_MESSAGES);
    }

    #[test]
    fn append_and_read_jsonl() {
        let tmp = TempDir::new().unwrap();
        let repo = tmp.path();
        std::fs::create_dir_all(repo.join("missions/alpha")).unwrap();
        std::fs::write(repo.join("missions/alpha/mission.md"), "# x\n").unwrap();
        let msg = append_jsonl_local(repo, "alpha", "user", "hello").unwrap();
        let reread = read_jsonl_file(&chat_log_path(repo, "alpha"));
        assert_eq!(reread.len(), 1);
        assert_eq!(reread[0].text, msg.text);
    }

    #[test]
    fn tailer_picks_new_lines() {
        let tmp = TempDir::new().unwrap();
        let repo = tmp.path();
        let log_dir = repo.join("missions/alpha/logs");
        std::fs::create_dir_all(&log_dir).unwrap();
        std::fs::write(repo.join("missions/alpha/mission.md"), "# x\n").unwrap();
        append_jsonl_local(repo, "alpha", "user", "one").unwrap();
        let mut tailer = ChatTailer::default();
        let batch = tailer.poll_repo(repo);
        assert_eq!(batch.len(), 1);
        append_jsonl_local(repo, "alpha", "user", "two").unwrap();
        let batch2 = tailer.poll_repo(repo);
        assert_eq!(batch2.len(), 1);
        assert_eq!(batch2[0].text, "two");
    }
}