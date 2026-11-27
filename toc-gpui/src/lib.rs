//! Headless TOC state collection, parsing, and realtime feeds for Task Force Null.

pub mod aar;
pub mod armory;
pub mod board;
pub mod config;
pub mod feed;
pub mod log_io;
pub mod mission;
pub mod models;
pub mod paths;
pub mod roster;
pub mod state;
pub mod store;
pub mod types;

#[cfg(feature = "desktop")]
pub mod view;

pub use state::collect_state;
pub use store::{FeedMode, TocStore};
pub use types::*;