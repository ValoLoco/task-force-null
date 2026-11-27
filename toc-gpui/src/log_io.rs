use crate::paths::discover_operator_logs;
use crate::types::LogLineEvent;
use std::collections::HashMap;
use std::path::Path;

#[derive(Debug, Default)]
pub struct LogTailer {
    offsets: HashMap<String, u64>,
}

impl LogTailer {
    pub fn poll(&mut self, repo: &Path) -> Vec<LogLineEvent> {
        let mut events = Vec::new();
        for meta in discover_operator_logs(repo) {
            let rel = meta.path.clone();
            let full = repo.join(&rel);
            if !full.is_file() {
                continue;
            }
            let Ok(meta_fs) = std::fs::metadata(&full) else {
                continue;
            };
            let size = meta_fs.len();
            let mut offset = *self.offsets.get(&rel).unwrap_or(&0);
            if size < offset {
                offset = 0;
            }
            if size == offset {
                self.offsets.insert(rel.clone(), offset);
                continue;
            }
            let Ok(mut file) = std::fs::File::open(&full) else {
                continue;
            };
            use std::io::{Read, Seek, SeekFrom};
            if file.seek(SeekFrom::Start(offset)).is_err() {
                continue;
            }
            let mut chunk = Vec::new();
            let read = file.read_to_end(&mut chunk).unwrap_or(0);
            let new_offset = offset + read as u64;
            self.offsets.insert(rel.clone(), new_offset);
            let text = String::from_utf8_lossy(&chunk);
            for line in text.lines() {
                events.push(LogLineEvent {
                    path: rel.clone(),
                    line: line.to_string(),
                    mission: meta.mission.clone(),
                    name: meta.name.clone(),
                });
            }
        }
        events
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use tempfile::TempDir;

    #[test]
    fn tails_new_lines() {
        let tmp = TempDir::new().unwrap();
        let repo = tmp.path();
        let log_dir = repo.join("missions/alpha/logs");
        std::fs::create_dir_all(&log_dir).unwrap();
        let log_path = log_dir.join("lead.log");
        {
            let mut f = std::fs::File::create(&log_path).unwrap();
            writeln!(f, "line one").unwrap();
        }
        let mut tailer = LogTailer::default();
        let ev = tailer.poll(repo);
        assert_eq!(ev.len(), 1);
        assert_eq!(ev[0].line, "line one");

        std::fs::OpenOptions::new()
            .append(true)
            .open(&log_path)
            .unwrap()
            .write_all(b"line two\n")
            .unwrap();
        let ev2 = tailer.poll(repo);
        assert_eq!(ev2.len(), 1);
        assert_eq!(ev2[0].line, "line two");
    }
}