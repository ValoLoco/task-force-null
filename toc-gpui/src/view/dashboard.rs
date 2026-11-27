use crate::chat::{
    append_jsonl_local, fetch_chat_http, load_mission_chat, post_chat_http, ChatMessage,
};
use crate::feed::display::{connection_badge, BadgeTone};
use crate::filter::{
    filter_activity_lines, mission_slugs_sorted, search_matches, OperatorChip,
};
use crate::store::{StoreEvent, StoreSnapshot, TocStore};
use crate::theme::{ThemeMode, ThemePalette};
use crate::types::{status_bucket, ActivityLine, MissionRow, OperatorRow, StatusStrip, TaskRow, TocState};
use gpui::{
    div, prelude::*, px, rgb, App, Context, FocusHandle, Focusable, IntoElement, KeyDownEvent,
    ParentElement, Render, SharedString, StatefulInteractiveElement, Styled, Window,
};
use std::path::Path;
use std::sync::Arc;

pub struct TocDashboard {
    store: Arc<TocStore>,
    repo_root: std::path::PathBuf,
    web_url: Option<String>,
    focus: FocusHandle,
    last_version: u64,
    active_log: Option<String>,
    theme: ThemeMode,
    operator_filter: OperatorChip,
    search_query: String,
    search_focused: bool,
    chat_open: bool,
    chat_input: String,
    chat_focused: bool,
    chat_error: Option<String>,
}

impl TocDashboard {
    pub fn new(
        store: Arc<TocStore>,
        repo_root: &Path,
        web_url: Option<String>,
        cx: &mut Context<Self>,
    ) -> Self {
        let focus = cx.focus_handle();
        let store_bg = store.clone();
        cx.spawn(async move |this, cx| {
            let mut prev = store_bg.version();
            loop {
                cx.background_executor()
                    .timer(std::time::Duration::from_millis(150))
                    .await;
                let cur = store_bg.version();
                if cur != prev {
                    prev = cur;
                    let _ = this.update(cx, |_, cx| cx.notify());
                }
            }
        })
        .detach();
        let dash = Self {
            store,
            repo_root: repo_root.to_path_buf(),
            web_url,
            focus,
            last_version: 0,
            active_log: None,
            theme: ThemeMode::default(),
            operator_filter: OperatorChip::default(),
            search_query: String::new(),
            search_focused: false,
            chat_open: false,
            chat_input: String::new(),
            chat_focused: false,
            chat_error: None,
        };
        dash
    }

    fn ensure_chat_loaded(&self, mission: &str, cx: &mut Context<Self>) {
        let existing = self.store.chat_for_mission(mission);
        if !existing.is_empty() {
            return;
        }
        let store = self.store.clone();
        let repo = self.repo_root.clone();
        let base = self.web_url.clone();
        let mission = mission.to_string();
        cx.spawn(async move |_this, _cx| {
            let result = if let Some(url) = base {
                fetch_chat_http(&url, &mission, 500)
            } else {
                Ok(load_mission_chat(&repo, &mission))
            };
            if let Ok(msgs) = result {
                let _ = store.apply(StoreEvent::ChatHistory {
                    mission,
                    messages: msgs,
                });
            }
        })
        .detach();
    }

    fn snap(&mut self) -> StoreSnapshot {
        let snap = self.store.snapshot();
        self.last_version = snap.version;
        if let Some(ref slug) = snap.selected_mission {
            if self.active_log.is_none() {
                if let Some(st) = snap.state.as_ref() {
                    let paths: Vec<(String, String)> = st
                        .operator_logs
                        .iter()
                        .map(|m| (m.mission.clone(), m.path.clone()))
                        .collect();
                    if let Some(path) = crate::filter::default_log_for_mission(slug, &paths) {
                        self.active_log = Some(path);
                    }
                }
            }
        }
        if self.active_log.is_none() {
            if let Some(ref state) = snap.state {
                if let Some(first) = state.operator_logs.first() {
                    self.active_log = Some(first.path.clone());
                }
            }
        }
        snap
    }

    fn palette(&self) -> ThemePalette {
        self.theme.palette()
    }

    fn on_mission_select(&mut self, slug: String, cx: &mut Context<Self>) {
        self.store.set_selected_mission(Some(slug.clone()));
        if let Some(st) = self.store.snapshot().state {
            let paths: Vec<(String, String)> = st
                .operator_logs
                .iter()
                .map(|m| (m.mission.clone(), m.path.clone()))
                .collect();
            self.active_log = crate::filter::default_log_for_mission(&slug, &paths);
        }
        if self.chat_open {
            self.ensure_chat_loaded(&slug, cx);
        }
        cx.notify();
    }

    fn toggle_chat(&mut self, cx: &mut Context<Self>) {
        self.chat_open = !self.chat_open;
        self.chat_error = None;
        if self.chat_open {
            if let Some(slug) = self.store.snapshot().selected_mission.clone() {
                self.ensure_chat_loaded(&slug, cx);
            }
        }
        cx.notify();
    }

    fn send_chat(&mut self, cx: &mut Context<Self>) {
        let text = self.chat_input.trim().to_string();
        if text.is_empty() {
            return;
        }
        let Some(mission) = self.store.snapshot().selected_mission.clone() else {
            self.chat_error = Some("No active mission selected.".into());
            cx.notify();
            return;
        };
        let store = self.store.clone();
        let repo = self.repo_root.clone();
        let base = self.web_url.clone();
        self.chat_error = None;
        self.chat_input.clear();
        cx.notify();
        cx.spawn(async move |this, cx| {
            let outcome = if let Some(url) = base {
                post_chat_http(&url, &mission, &text)
            } else {
                append_jsonl_local(&repo, &mission, "user", &text)
            };
            let _ = this.update(cx, move |view, cx| {
                match outcome {
                    Ok(msg) => {
                        let _ = store.apply(StoreEvent::ChatMessage(msg));
                        view.chat_error = None;
                    }
                    Err(err) => {
                        view.chat_error = Some(err);
                    }
                }
                cx.notify();
            });
        })
        .detach();
    }

    fn handle_key(&mut self, event: &KeyDownEvent, cx: &mut Context<Self>) {
        let key = event.keystroke.key.as_str();
        if self.chat_focused {
            if key == "backspace" {
                self.chat_input.pop();
                cx.notify();
                return;
            }
            if key == "escape" {
                self.chat_focused = false;
                cx.notify();
                return;
            }
            if key == "enter" {
                self.send_chat(cx);
                return;
            }
            if let Some(ch) = event.keystroke.key_char.as_deref() {
                if ch.len() == 1 && !event.keystroke.modifiers.platform && !event.keystroke.modifiers.control {
                    self.chat_input.push_str(ch);
                    cx.notify();
                }
            }
            return;
        }
        if self.search_focused {
            if key == "backspace" {
                self.search_query.pop();
                cx.notify();
                return;
            }
            if key == "escape" {
                self.search_focused = false;
                cx.notify();
                return;
            }
            if let Some(ch) = event.keystroke.key_char.as_deref() {
                if ch.len() == 1 && !event.keystroke.modifiers.platform && !event.keystroke.modifiers.control {
                    self.search_query.push_str(ch);
                    cx.notify();
                }
            }
            return;
        }
        if key == "t" && !event.keystroke.modifiers.platform && !event.keystroke.modifiers.control {
            self.theme = self.theme.toggle();
            cx.notify();
        }
        if key == "c" && !event.keystroke.modifiers.platform && !event.keystroke.modifiers.control {
            self.toggle_chat(cx);
        }
    }
}

impl Focusable for TocDashboard {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus.clone()
    }
}

impl Render for TocDashboard {
    fn render(&mut self, _window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let snap = self.snap();
        let state = snap.state.as_ref();
        let palette = self.palette();
        let badge = connection_badge(&snap.feed_mode, &snap.feed_phase, snap.reconnect_secs);

        let mission = state.and_then(|st| {
            if let Some(slug) = &snap.selected_mission {
                st.missions.iter().find(|m| m.slug == *slug)
            } else {
                st.missions
                    .iter()
                    .find(|m| m.active)
                    .or(st.missions.first())
            }
        });

        div()
            .size_full()
            .flex()
            .flex_col()
            .bg(rgb(palette.bg))
            .text_color(rgb(palette.text))
            .text_sm()
            .track_focus(&self.focus)
            .on_key_down(cx.listener(|this, event, _, cx| this.handle_key(event, cx)))
            .child(header_bar(
                state,
                &badge,
                palette,
                self.theme,
                self.chat_open,
                cx,
            ))
            .child(controls_row(
                self.operator_filter,
                &self.search_query,
                self.search_focused,
                palette,
                cx,
            ))
            .child(
                div()
                    .flex()
                    .flex_1()
                    .overflow_hidden()
                    .child(main_board(
                        mission,
                        state,
                        &snap.selected_mission,
                        palette,
                        cx,
                    ))
                    .child(side_panel(
                        &snap,
                        &mut self.active_log,
                        self.operator_filter,
                        &self.search_query,
                        palette,
                    )),
            )
            .children(if self.chat_open {
                let slug = snap.selected_mission.clone().unwrap_or_default();
                let msgs = snap
                    .chat_rings
                    .get(&slug)
                    .map(|r| r.messages().cloned().collect::<Vec<_>>())
                    .unwrap_or_default();
                vec![commander_chat_panel(
                    &slug,
                    &msgs,
                    &self.chat_input,
                    self.chat_focused,
                    self.chat_error.as_deref(),
                    palette,
                    cx,
                )
                .into_any_element()]
            } else {
                Vec::new()
            })
    }
}

fn header_bar(
    state: Option<&TocState>,
    badge: &crate::feed::display::ConnectionBadge,
    palette: ThemePalette,
    theme: ThemeMode,
    chat_open: bool,
    cx: &mut Context<TocDashboard>,
) -> impl IntoElement {
    let utc = state
        .map(|s| s.status_strip.utc.clone())
        .unwrap_or_else(|| "--".into());
    let feed_color = match badge.tone {
        BadgeTone::Live => palette.accent,
        BadgeTone::Warn => palette.warn,
        BadgeTone::Muted => palette.muted,
    };
    let strip = state.map(|s| &s.status_strip);
    div()
        .w_full()
        .px_4()
        .py_3()
        .bg(rgb(palette.panel))
        .border_b_1()
        .border_color(rgb(palette.border))
        .child(
            div()
                .flex()
                .justify_between()
                .items_center()
                .child(
                    div()
                        .text_lg()
                        .font_weight(gpui::FontWeight::BOLD)
                        .child("TASK FORCE NULL TOC"),
                )
                .child(
                    div()
                        .flex()
                        .gap_2()
                        .items_center()
                        .child(
                            div()
                                .id("theme-toggle")
                                .px_2()
                                .py_px()
                                .rounded_md()
                                .border_1()
                                .border_color(rgb(palette.border))
                                .cursor_pointer()
                                .on_click(cx.listener(|this, _, _, cx| {
                                    this.theme = this.theme.toggle();
                                    cx.notify();
                                }))
                                .child(format!("Theme: {} (t)", theme.toggle_label())),
                        )
                        .child(
                            div()
                                .id("chat-toggle")
                                .px_2()
                                .py_px()
                                .rounded_md()
                                .border_1()
                                .border_color(rgb(palette.border))
                                .bg(rgb(if chat_open {
                                    palette.chip_active
                                } else {
                                    palette.chip_idle
                                }))
                                .cursor_pointer()
                                .on_click(cx.listener(|this, _, _, cx| this.toggle_chat(cx)))
                                .child(format!(
                                    "Commander Chat ({})",
                                    if chat_open { "on" } else { "c" }
                                )),
                        )
                        .child(div().text_color(rgb(palette.muted)).child(format!("UTC {utc}")))
                        .child(
                            div()
                                .px_2()
                                .py_px()
                                .rounded_full()
                                .bg(rgb(feed_color))
                                .text_color(rgb(palette.text))
                                .text_xs()
                                .child(badge.label.clone()),
                        ),
                ),
        )
        .child(if let Some(st) = strip {
            div()
                .flex()
                .flex_wrap()
                .gap_2()
                .mt_2()
                .children(status_badges(st, palette))
        } else {
            div().child("")
        })
}

fn controls_row(
    selected: OperatorChip,
    search: &str,
    search_focused: bool,
    palette: ThemePalette,
    cx: &mut Context<TocDashboard>,
) -> impl IntoElement {
    div()
        .px_4()
        .py_2()
        .flex()
        .flex_col()
        .gap_2()
        .bg(rgb(palette.panel))
        .border_b_1()
        .border_color(rgb(palette.border))
        .child(
            div()
                .flex()
                .flex_wrap()
                .gap_1()
                .children(OperatorChip::ALL.iter().map(|chip| {
                    let active = *chip == selected;
                    let label = chip.label();
                    div()
                        .id(label)
                        .px_2()
                        .py_px()
                        .rounded_md()
                        .cursor_pointer()
                        .bg(rgb(if active {
                            palette.chip_active
                        } else {
                            palette.chip_idle
                        }))
                        .border_1()
                        .border_color(rgb(palette.border))
                        .on_click(cx.listener(move |this, _, _, cx| {
                            this.operator_filter = *chip;
                            cx.notify();
                        }))
                        .child(label.to_string())
                })),
        )
        .child(
            div()
                .flex()
                .items_center()
                .gap_2()
                .child(
                    div()
                        .text_xs()
                        .text_color(rgb(palette.muted))
                        .child("LOG SEARCH"),
                )
                .child(
                    div()
                        .id("log-search")
                        .flex_1()
                        .px_2()
                        .py_1()
                        .rounded_md()
                        .border_1()
                        .border_color(rgb(if search_focused {
                            palette.chip_active
                        } else {
                            palette.border
                        }))
                        .bg(rgb(palette.bg))
                        .cursor_text()
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.search_focused = true;
                            cx.notify();
                        }))
                        .child(if search.is_empty() {
                            "Type to filter logs (Esc to blur)".to_string()
                        } else {
                            search.to_string()
                        }),
                ),
        )
}

fn status_badges(st: &StatusStrip, palette: ThemePalette) -> Vec<impl IntoElement> {
    let mat = &st.maturity;
    vec![
        badge(
            format!(
                "blockers {}",
                if st.delegation.blockers { "ON" } else { "OFF" }
            ),
            palette,
        ),
        badge(
            format!(
                "external {}",
                if st.delegation.external { "ON" } else { "OFF" }
            ),
            palette,
        ),
        badge(
            format!(
                "autonomous {}",
                if st.autonomous { "ON" } else { "OFF" }
            ),
            palette,
        ),
        badge(format!("AARs {}/{}", mat.aar_count, mat.min_aars), palette),
        badge(
            format!(
                "missions {}/{}",
                mat.completed_missions, mat.min_missions
            ),
            palette,
        ),
        badge(mat.pushback.clone(), palette),
    ]
}

fn badge(text: String, palette: ThemePalette) -> impl IntoElement {
    div()
        .px_2()
        .py_px()
        .rounded_md()
        .border_1()
        .border_color(rgb(palette.border))
        .bg(rgb(palette.bg))
        .text_xs()
        .child(text)
}

fn main_board(
    mission: Option<&MissionRow>,
    state: Option<&TocState>,
    selected: &Option<String>,
    palette: ThemePalette,
    cx: &mut Context<TocDashboard>,
) -> impl IntoElement {
    div()
        .flex_1()
        .flex()
        .flex_col()
        .gap_3()
        .p_4()
        .id("main-scroll")
        .overflow_y_scroll()
        .child(
            div()
                .text_xs()
                .text_color(rgb(palette.muted))
                .child("MISSION / TASK BOARD"),
        )
        .child(mission_panel(mission, palette))
        .child(
            div()
                .text_xs()
                .text_color(rgb(palette.muted))
                .mt_2()
                .child("MISSION SWITCHER"),
        )
        .children(
            state
                .map(|s| {
                    mission_slugs_sorted(&s.missions)
                        .into_iter()
                        .map(|slug| {
                            let row = s.missions.iter().find(|m| m.slug == slug);
                            let is_selected = selected.as_deref() == Some(slug.as_str());
                            mission_switcher_row(slug, row, is_selected, palette, cx)
                        })
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default(),
        )
}

fn mission_switcher_row(
    slug: String,
    row: Option<&MissionRow>,
    active: bool,
    palette: ThemePalette,
    cx: &mut Context<TocDashboard>,
) -> impl IntoElement {
    let pct = row.map(|m| m.pct).unwrap_or(0);
    let status = row.map(|m| if m.active { "ACTIVE" } else { "idle" }).unwrap_or("?");
    let row_id = SharedString::from(format!("mission-{slug}"));
    let label = format!("{slug} [{status}] {pct}%");
    div()
        .id(row_id)
        .px_3()
        .py_2()
        .border_1()
        .border_color(rgb(if active {
            palette.chip_active
        } else {
            palette.border
        }))
        .rounded_md()
        .bg(rgb(if active { palette.chip_idle } else { palette.panel }))
        .mb_2()
        .cursor_pointer()
        .on_click(cx.listener({
            let slug = slug.clone();
            move |this, _, _, cx| this.on_mission_select(slug.clone(), cx)
        }))
        .child(label)
}

fn mission_panel(mission: Option<&MissionRow>, palette: ThemePalette) -> impl IntoElement {
    div()
        .bg(rgb(palette.panel))
        .border_1()
        .border_color(rgb(palette.border))
        .rounded_md()
        .p_4()
        .children(if let Some(m) = mission {
            let status = if m.active { "ACTIVE" } else { "INACTIVE" };
            vec![
                div()
                    .flex()
                    .justify_between()
                    .child(
                        div()
                            .text_base()
                            .font_weight(gpui::FontWeight::SEMIBOLD)
                            .child(format!("{}  {status}", m.slug)),
                    )
                    .child(
                        div()
                            .text_color(rgb(palette.muted))
                            .child(format!("{}% ({}/{})", m.pct, m.done, m.total)),
                    )
                    .into_any_element(),
                div()
                    .text_color(rgb(palette.muted))
                    .mt_1()
                    .child(m.objective.clone())
                    .into_any_element(),
                progress_bar(m.pct, palette).into_any_element(),
                kanban(&m.tasks, palette).into_any_element(),
            ]
        } else {
            vec![div().child("No missions found.").into_any_element()]
        })
}

fn progress_bar(pct: u32, palette: ThemePalette) -> impl IntoElement {
    div()
        .mt_2()
        .h(px(6.))
        .w_full()
        .bg(rgb(palette.border))
        .rounded_md()
        .overflow_hidden()
        .child(
            div()
                .h_full()
                .w(gpui::relative((pct as f32) / 100.0))
                .bg(rgb(palette.accent)),
        )
}

fn kanban(tasks: &[TaskRow], palette: ThemePalette) -> impl IntoElement {
    let mut todo = Vec::new();
    let mut doing = Vec::new();
    let mut done = Vec::new();
    for t in tasks {
        match status_bucket(&t.status) {
            "done" => done.push(t),
            "doing" => doing.push(t),
            _ => todo.push(t),
        }
    }
    div()
        .flex()
        .gap_3()
        .mt_3()
        .child(kanban_col("TODO", palette.todo, &todo, palette))
        .child(kanban_col("DOING", palette.doing, &doing, palette))
        .child(kanban_col("DONE", palette.done, &done, palette))
}

fn kanban_col(
    title: &str,
    color: u32,
    tasks: &[&TaskRow],
    palette: ThemePalette,
) -> impl IntoElement {
    div()
        .flex_1()
        .child(
            div()
                .text_xs()
                .text_color(rgb(palette.muted))
                .mb_1()
                .child(title.to_string()),
        )
        .children(tasks.iter().map(|t| task_chip(t, color, palette)))
}

fn task_chip(t: &TaskRow, accent: u32, palette: ThemePalette) -> impl IntoElement {
    div()
        .mb_1()
        .px_2()
        .py_1()
        .border_l_2()
        .border_color(rgb(accent))
        .bg(rgb(palette.bg))
        .rounded_sm()
        .text_xs()
        .child(format!("{} {}: {}", t.id, t.owner, t.name))
}

fn side_panel(
    snap: &StoreSnapshot,
    active_log: &mut Option<String>,
    operator_filter: OperatorChip,
    search_query: &str,
    palette: ThemePalette,
) -> impl IntoElement {
    let state = snap.state.as_ref();
    let filtered: Vec<&ActivityLine> =
        filter_activity_lines(&snap.activity, operator_filter, search_query);
    let recent: Vec<_> = filtered.iter().rev().take(48).collect();
    div()
        .w(px(380.))
        .h_full()
        .flex()
        .flex_col()
        .border_l_1()
        .border_color(rgb(palette.border))
        .bg(rgb(palette.panel))
        .child(
            div()
                .p_3()
                .border_b_1()
                .border_color(rgb(palette.border))
                .child(
                    div()
                        .text_xs()
                        .text_color(rgb(palette.muted))
                        .child("SQUAD ROSTER"),
                )
                .children(
                    state
                        .map(|s| {
                            s.operators
                                .iter()
                                .map(|op| roster_row(op, operator_filter, palette))
                                .collect::<Vec<_>>()
                        })
                        .unwrap_or_default(),
                ),
        )
        .child(
            div()
                .p_3()
                .border_b_1()
                .border_color(rgb(palette.border))
                .child(
                    div()
                        .text_xs()
                        .text_color(rgb(palette.muted))
                        .child("MODEL ROUTING"),
                )
                .child(routing_block(state, palette)),
        )
        .child(
            div()
                .flex_1()
                .flex()
                .flex_col()
                .p_3()
                .overflow_hidden()
                .child(
                    div()
                        .text_xs()
                        .text_color(rgb(palette.muted))
                        .mb_2()
                        .child("OPERATOR ACTIVITY"),
                )
                .child(activity_feed(&recent, palette))
                .child(
                    div()
                        .text_xs()
                        .text_color(rgb(palette.muted))
                        .mt_3()
                        .mb_1()
                        .child("LOG TAIL"),
                )
                .child(log_tail(snap, active_log, operator_filter, search_query, palette)),
        )
}

fn roster_row(op: &OperatorRow, filter: OperatorChip, palette: ThemePalette) -> impl IntoElement {
    let highlighted = filter.matches_operator_id(&op.id);
    let task_summary = if op.tasks.is_empty() {
        "(no owned tasks)".to_string()
    } else {
        op.tasks
            .iter()
            .take(4)
            .map(|t| format!("{}/{} [{}]", t.mission, t.id, t.status))
            .collect::<Vec<_>>()
            .join(", ")
    };
    div()
        .mb_2()
        .px_2()
        .py_1()
        .rounded_md()
        .bg(rgb(if highlighted {
            palette.chip_idle
        } else {
            palette.panel
        }))
        .border_l_2()
        .border_color(rgb(if highlighted {
            palette.chip_active
        } else {
            palette.accent
        }))
        .child(
            div()
                .font_weight(gpui::FontWeight::SEMIBOLD)
                .child(op.id.clone()),
        )
        .child(div().text_color(rgb(palette.muted)).text_xs().child(op.title.clone()))
        .child(div().text_xs().child(task_summary))
}

fn routing_block(state: Option<&TocState>, _palette: ThemePalette) -> impl IntoElement {
    let Some(st) = state else {
        return div().text_xs().child("loading...").into_any_element();
    };
    let r = &st.routing;
    let inv = if r.inventory.is_empty() {
        "(none)".to_string()
    } else {
        r.inventory
            .iter()
            .take(4)
            .map(|i| format!("{} ({})", i.model_id, i.provider))
            .collect::<Vec<_>>()
            .join("; ")
    };
    let binds = if r.bindings.is_empty() {
        "(none)".to_string()
    } else {
        r.bindings
            .iter()
            .take(4)
            .map(|b| format!("{} {}", b.mission, b.bind))
            .collect::<Vec<_>>()
            .join("; ")
    };
    div()
        .text_xs()
        .child(format!("harness: {}", r.harness))
        .child(div().mt_1().child(format!("inventory: {inv}")))
        .child(div().mt_1().child(format!("bindings: {binds}")))
        .into_any_element()
}

fn activity_feed(lines: &[&&ActivityLine], _palette: ThemePalette) -> impl IntoElement {
    div()
        .id("activity-feed")
        .flex_1()
        .overflow_y_scroll()
        .text_xs()
        .children(lines.iter().map(|l| {
            div()
                .mb_1()
                .child(format!("[{}] {}", l.utc, l.text))
        }))
}

fn log_tail(
    snap: &StoreSnapshot,
    active_log: &Option<String>,
    operator_filter: OperatorChip,
    search_query: &str,
    palette: ThemePalette,
) -> impl IntoElement {
    let key = active_log.clone().unwrap_or_default();
    let op_from_path = key
        .rsplit('/')
        .next()
        .unwrap_or("")
        .trim_end_matches(".log")
        .to_string();
    let body = if let Some(ring) = snap.log_rings.get(&key) {
        let filtered: Vec<String> = ring
            .lines()
            .filter(|line| {
                operator_filter.matches_operator_id(&op_from_path)
                    && search_matches(line, search_query)
            })
            .map(|s| s.to_string())
            .collect();
        if filtered.is_empty() {
            "(no matching lines)".into()
        } else {
            filtered.join("\n")
        }
    } else if key.is_empty() {
        "Waiting for operator logs under missions/*/logs/*.log".into()
    } else {
        "(no lines yet)".into()
    };
    div()
        .id("log-tail")
        .h(px(140.))
        .overflow_y_scroll()
        .p_2()
        .bg(rgb(palette.bg))
        .border_1()
        .border_color(rgb(palette.border))
        .rounded_md()
        .text_xs()
        .child(body)
}

fn chat_history_list(messages: &[ChatMessage], _palette: ThemePalette) -> impl IntoElement {
    div()
        .id("commander-chat-history")
        .flex_1()
        .overflow_y_scroll()
        .px_4()
        .py_2()
        .text_xs()
        .children(messages.iter().map(|m| {
            div()
                .mb_1()
                .child(format!("[{}] {}: {}", m.ts, m.sender, m.text))
        }))
}

fn commander_chat_panel(
    mission: &str,
    messages: &[ChatMessage],
    input: &str,
    input_focused: bool,
    error: Option<&str>,
    palette: ThemePalette,
    cx: &mut Context<TocDashboard>,
) -> impl IntoElement {
    let mission_label = if mission.is_empty() {
        "(no mission selected)".to_string()
    } else {
        mission.to_string()
    };
    div()
        .id("commander-chat-panel")
        .w_full()
        .h(px(220.))
        .flex()
        .flex_col()
        .border_t_1()
        .border_color(rgb(palette.border))
        .bg(rgb(palette.panel))
        .child(
            div()
                .px_4()
                .py_2()
                .flex()
                .justify_between()
                .items_center()
                .border_b_1()
                .border_color(rgb(palette.border))
                .child(
                    div()
                        .text_xs()
                        .text_color(rgb(palette.muted))
                        .child(format!("COMMANDER CHAT | mission {mission_label}")),
                )
                .child(
                    div()
                        .text_xs()
                        .text_color(rgb(palette.muted))
                        .child("Enter send | Esc blur"),
                ),
        )
        .child(chat_history_list(messages, palette))
        .child(
            div()
                .px_4()
                .py_2()
                .border_t_1()
                .border_color(rgb(palette.border))
                .flex()
                .flex_col()
                .gap_2()
                .child(
                    div()
                        .id("commander-chat-input")
                        .px_2()
                        .py_1()
                        .min_h(px(28.))
                        .rounded_md()
                        .border_1()
                        .border_color(rgb(if input_focused {
                            palette.chip_active
                        } else {
                            palette.border
                        }))
                        .bg(rgb(palette.bg))
                        .cursor_text()
                        .on_click(cx.listener(|this, _, _, cx| {
                            this.chat_focused = true;
                            cx.notify();
                        }))
                        .child(if input.is_empty() && !input_focused {
                            "Click to type a message to Command...".to_string()
                        } else {
                            input.to_string()
                        }),
                )
                .child(
                    div()
                        .flex()
                        .justify_between()
                        .items_center()
                        .child(
                            div()
                                .id("commander-chat-send")
                                .px_2()
                                .py_px()
                                .rounded_md()
                                .bg(rgb(palette.accent))
                                .text_color(rgb(palette.text))
                                .cursor_pointer()
                                .on_click(cx.listener(|this, _, _, cx| this.send_chat(cx)))
                                .child("Send"),
                        )
                        .children(if let Some(e) = error {
                            vec![div()
                                .text_xs()
                                .text_color(rgb(palette.warn))
                                .child(e.to_string())
                                .into_any_element()]
                        } else {
                            Vec::new()
                        }),
                ),
        )
}