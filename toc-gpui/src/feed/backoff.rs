//! SSE reconnect backoff schedule.

pub const BACKOFF_INITIAL_SECS: u64 = 1;
pub const BACKOFF_MAX_SECS: u64 = 30;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct ReconnectBackoff {
    step: u32,
}

impl ReconnectBackoff {
    pub fn reset(&mut self) {
        self.step = 0;
    }

    pub fn next_delay_secs(&mut self) -> u32 {
        let shift = self.step.min(5);
        let delay = (BACKOFF_INITIAL_SECS << shift).min(BACKOFF_MAX_SECS);
        self.step = self.step.saturating_add(1);
        delay as u32
    }

    pub fn delay_without_advance(step: u32) -> u32 {
        let shift = step.min(5);
        ((BACKOFF_INITIAL_SECS << shift).min(BACKOFF_MAX_SECS)) as u32
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn backoff_progression_and_reset() {
        let mut b = ReconnectBackoff::default();
        assert_eq!(b.next_delay_secs(), 1);
        assert_eq!(b.next_delay_secs(), 2);
        assert_eq!(b.next_delay_secs(), 4);
        assert_eq!(b.next_delay_secs(), 8);
        b.reset();
        assert_eq!(b.next_delay_secs(), 1);
    }

    #[test]
    fn caps_at_max() {
        let mut b = ReconnectBackoff { step: 10 };
        assert_eq!(b.next_delay_secs(), BACKOFF_MAX_SECS as u32);
    }
}