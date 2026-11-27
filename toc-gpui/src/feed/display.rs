//! Human-readable feed connection labels for the header badge.

use crate::store::FeedMode;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BadgeTone {
    Live,
    Warn,
    Muted,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConnectionBadge {
    pub label: String,
    pub tone: BadgeTone,
}

pub fn connection_badge(mode: &FeedMode, phase: &str, reconnect_secs: u32) -> ConnectionBadge {
    match mode {
        FeedMode::Filesystem => ConnectionBadge {
            label: "FILE WATCH".into(),
            tone: BadgeTone::Muted,
        },
        FeedMode::Sse => match phase {
            "live" => ConnectionBadge {
                label: "LIVE SSE".into(),
                tone: BadgeTone::Live,
            },
            "reconnecting" => ConnectionBadge {
                label: format!("RECONNECTING ({reconnect_secs}s)"),
                tone: BadgeTone::Warn,
            },
            _ => ConnectionBadge {
                label: "CONNECTING".into(),
                tone: BadgeTone::Warn,
            },
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn labels_by_mode() {
        let fs = connection_badge(&FeedMode::Filesystem, "live", 0);
        assert_eq!(fs.label, "FILE WATCH");
        let live = connection_badge(&FeedMode::Sse, "live", 0);
        assert_eq!(live.label, "LIVE SSE");
        let re = connection_badge(&FeedMode::Sse, "reconnecting", 4);
        assert_eq!(re.label, "RECONNECTING (4s)");
    }
}