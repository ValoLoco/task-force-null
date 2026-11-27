//! Cooperative shutdown flag for background feed threads.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

#[derive(Debug, Clone)]
pub struct ShutdownSignal(Arc<AtomicBool>);

impl Default for ShutdownSignal {
    fn default() -> Self {
        Self::new()
    }
}

impl ShutdownSignal {
    pub fn new() -> Self {
        Self(Arc::new(AtomicBool::new(false)))
    }

    pub fn stop(&self) {
        self.0.store(true, Ordering::Relaxed);
    }

    pub fn should_stop(&self) -> bool {
        self.0.load(Ordering::Relaxed)
    }

    pub fn sleep_or_stop(&self, total: std::time::Duration) {
        let step = std::time::Duration::from_millis(100);
        let mut remaining = total;
        while remaining > std::time::Duration::ZERO {
            if self.should_stop() {
                return;
            }
            let slice = remaining.min(step);
            std::thread::sleep(slice);
            remaining = remaining.saturating_sub(slice);
        }
    }
}