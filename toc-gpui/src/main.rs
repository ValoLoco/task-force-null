use clap::Parser;
use gpui::{
    App, Application, Bounds, WindowBounds, WindowOptions, prelude::*, px, size,
};
use std::path::PathBuf;
use tfn_toc::feed::{spawn_fs_watch, spawn_sse_feed};
use tfn_toc::shutdown::ShutdownSignal;
use tfn_toc::state::collect_state;
use tfn_toc::store::{FeedMode, StoreEvent, TocStore};
use tfn_toc::view::TocDashboard;

#[derive(Debug, Parser)]
#[command(name = "tfn-toc-gpui", about = "Task Force Null native GPUI TOC")]
struct Cli {
    /// Repository root (defaults to parent of toc-gpui when run via toc.sh).
    #[arg(long, env = "TFN_REPO_ROOT")]
    repo_root: Option<PathBuf>,

    /// Optional web TOC base URL for SSE mode (e.g. http://127.0.0.1:8765).
    #[arg(long)]
    url: Option<String>,

    /// Preferred active mission slug for the header selector.
    #[arg(long)]
    mission: Option<String>,
}

fn default_repo_root() -> PathBuf {
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest.parent().unwrap_or(&manifest).to_path_buf()
}

fn main() {
    let cli = Cli::parse();
    let repo = cli
        .repo_root
        .unwrap_or_else(default_repo_root)
        .canonicalize()
        .unwrap_or_else(|_| default_repo_root());

    let store = TocStore::new(cli.mission.clone());
    let _ = store.apply(StoreEvent::State(collect_state(&repo)));

    let shutdown = ShutdownSignal::new();
    let sse_mode = cli.url.is_some();
    store.set_feed_mode(if sse_mode {
        FeedMode::Sse
    } else {
        FeedMode::Filesystem
    });

    if let Some(url) = cli.url.clone() {
        spawn_sse_feed(&url, &repo, store.clone(), shutdown.clone());
    } else {
        spawn_fs_watch(&repo, store.clone(), shutdown.clone());
    }

    let store_ui = store.clone();
    let repo_ui = repo.clone();
    let web_url = cli.url.clone();
    Application::new().run(move |cx: &mut App| {
        let shutdown_quit = shutdown.clone();
        let _quit_sub = cx.on_app_quit(move |_cx| {
            shutdown_quit.stop();
            async {}
        });

        let bounds = Bounds::centered(None, size(px(1280.), px(800.)), cx);
        cx.open_window(
            WindowOptions {
                titlebar: Some(gpui::TitlebarOptions {
                    title: Some("Task Force Null TOC".into()),
                    ..Default::default()
                }),
                window_bounds: Some(WindowBounds::Windowed(bounds)),
                ..Default::default()
            },
            move |_, cx| {
                cx.new(|cx| {
                    TocDashboard::new(store_ui.clone(), &repo_ui, web_url.clone(), cx)
                })
            },
        )
        .expect("open window");
        cx.activate(true);
    });
}