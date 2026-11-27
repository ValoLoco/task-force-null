//! Bounded in-memory log line storage.

use std::collections::VecDeque;

pub const MAX_LOG_LINES: usize = 2000;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct LogRing {
    lines: VecDeque<String>,
}

impl LogRing {
    pub fn push_line(&mut self, line: impl Into<String>) {
        self.lines.push_back(line.into());
        while self.lines.len() > MAX_LOG_LINES {
            self.lines.pop_front();
        }
    }

    pub fn len(&self) -> usize {
        self.lines.len()
    }

    pub fn is_empty(&self) -> bool {
        self.lines.is_empty()
    }

    pub fn joined_text(&self) -> String {
        if self.lines.is_empty() {
            return String::new();
        }
        self.lines
            .iter()
            .map(String::as_str)
            .collect::<Vec<_>>()
            .join("\n")
    }

    pub fn lines(&self) -> impl Iterator<Item = &str> {
        self.lines.iter().map(String::as_str)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn caps_at_max_lines() {
        let mut ring = LogRing::default();
        for i in 0..MAX_LOG_LINES + 50 {
            ring.push_line(format!("line-{i}"));
        }
        assert_eq!(ring.len(), MAX_LOG_LINES);
        assert_eq!(ring.lines().next(), Some("line-50"));
    }
}