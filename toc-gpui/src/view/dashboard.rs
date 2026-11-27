use gpui::{
    div, prelude::*, px, rgb, Context, IntoElement, ParentElement, Render, StatefulInteractiveElement,
    Styled, Window,
};
use crate::store::{StoreSnapshot, TocStore};
use crate::types::{MissionRow, status_bucket, ActivityLine, OperatorRow, StatusStrip, TaskRow, TocState};
use std::sync::Arc;

const BG: u32 = 0x0d1117;
const PANEL: u32 = 0x161b22;
const TEXT: u32 = 0xe6edf3;
const MUTED: u32 = 0x8b949e;
const ACCENT: u32 = 0x3fb950;
const BORDER: u32 = 0x30363d;
const DOING: u32 = 0x1565c0;
const TODO_C: u32 = 0x5c6773;
const DONE_C: u32 = 0x2e7d32;
const WARN: u32 = 0xb58105;

pub struct TocDashboard {
    store: Arc<TocStore>,
    last_version: u64,
    active_log: Option<String>,
}

impl TocDashboard {
    pub fn new(store: Arc<TocStore>, cx: &mut Context<Self>) -> Self {
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
        Self {
            store,
            last_version: 0,
            active_log: None,
        }
    }

    fn snap(&mut self) -> StoreSnapshot {
        let snap = self.store.snapshot();
        self.last_version = snap.version;
        if self.active_log.is_none() {
            if let Some(ref state) = snap.state {
                if let Some(first) = state.operator_logs.first() {
                    self.active_log = Some(first.path.clone());
                }
            }
        }
        snap
    }
}

impl Render for TocDashboard {
    fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
        let snap = self.snap();
        let state = snap.state.as_ref();

        let (utc, feed_pill, feed_color) = if let Some(st) = state {
            let pill = snap.feed_status.clone();
            let color = match pill.as_str() {
                "live" => ACCENT,
                "connecting" | "reconnecting" | "starting" => WARN,
                _ => MUTED,
            };
            (st.status_strip.utc.clone(), pill, color)
        } else {
            ("--".into(), "loading".into(), MUTED)
        };

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
            .bg(rgb(BG))
            .text_color(rgb(TEXT))
            .text_sm()
            .child(header_bar(&utc, &feed_pill, feed_color, state))
            .child(
                div()
                    .flex()
                    .flex_1()
                    .overflow_hidden()
                    .child(main_board(mission, state))
                    .child(side_panel(&snap, &mut self.active_log)),
            )
    }
}

fn header_bar(
    utc: &str,
    feed: &str,
    feed_color: u32,
    state: Option<&TocState>,
) -> impl IntoElement {
    let strip = state.map(|s| &s.status_strip);
    div()
        .w_full()
        .px_4()
        .py_3()
        .bg(rgb(PANEL))
        .border_b_1()
        .border_color(rgb(BORDER))
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
                        .child(div().text_color(rgb(MUTED)).child(format!("UTC {utc}")))
                        .child(
                            div()
                                .px_2()
                                .py_px()
                                .rounded_full()
                                .bg(rgb(feed_color))
                                .text_color(rgb(TEXT))
                                .text_xs()
                                .child(feed.to_uppercase()),
                        ),
                ),
        )
        .child(if let Some(st) = strip {
            div()
                .flex()
                .flex_wrap()
                .gap_2()
                .mt_2()
                .children(status_badges(st))
        } else {
            div().child("")
        })
}

fn status_badges(st: &StatusStrip) -> Vec<impl IntoElement> {
    let mat = &st.maturity;
    vec![
        badge(format!(
            "blockers {}",
            if st.delegation.blockers { "ON" } else { "OFF" }
        )),
        badge(format!(
            "external {}",
            if st.delegation.external { "ON" } else { "OFF" }
        )),
        badge(format!(
            "autonomous {}",
            if st.autonomous { "ON" } else { "OFF" }
        )),
        badge(format!("AARs {}/{}", mat.aar_count, mat.min_aars)),
        badge(format!(
            "missions {}/{}",
            mat.completed_missions, mat.min_missions
        )),
        badge(mat.pushback.clone()),
    ]
}

fn badge(text: String) -> impl IntoElement {
    div()
        .px_2()
        .py_px()
        .rounded_md()
        .border_1()
        .border_color(rgb(BORDER))
        .bg(rgb(BG))
        .text_xs()
        .child(text)
}

fn main_board(
    mission: Option<&MissionRow>,
    state: Option<&TocState>,
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
                .text_color(rgb(MUTED))
                .child("MISSION / TASK BOARD"),
        )
        .child(mission_panel(mission))
        .child(
            div()
                .text_xs()
                .text_color(rgb(MUTED))
                .mt_2()
                .child("ALL MISSIONS"),
        )
        .children(
            state
                .map(|s| {
                    s.missions
                        .iter()
                        .map(mission_summary_row)
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default(),
        )
}

fn mission_panel(mission: Option<&MissionRow>) -> impl IntoElement {
    div()
        .bg(rgb(PANEL))
        .border_1()
        .border_color(rgb(BORDER))
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
                            .text_color(rgb(MUTED))
                            .child(format!("{}% ({}/{})", m.pct, m.done, m.total)),
                    )
                    .into_any_element(),
                div()
                    .text_color(rgb(MUTED))
                    .mt_1()
                    .child(m.objective.clone())
                    .into_any_element(),
                progress_bar(m.pct).into_any_element(),
                kanban(&m.tasks).into_any_element(),
            ]
        } else {
            vec![div().child("No missions found.").into_any_element()]
        })
}

fn mission_summary_row(m: &MissionRow) -> impl IntoElement {
    div()
        .px_3()
        .py_2()
        .border_1()
        .border_color(rgb(BORDER))
        .rounded_md()
        .bg(rgb(PANEL))
        .mb_2()
        .child(format!(
            "{} [{}] {}%",
            m.slug,
            if m.active { "ACTIVE" } else { "idle" },
            m.pct
        ))
}

fn progress_bar(pct: u32) -> impl IntoElement {
    div()
        .mt_2()
        .h(px(6.))
        .w_full()
        .bg(rgb(BORDER))
        .rounded_md()
        .overflow_hidden()
        .child(
            div()
                .h_full()
                .w(gpui::relative((pct as f32) / 100.0))
                .bg(rgb(ACCENT)),
        )
}

fn kanban(tasks: &[TaskRow]) -> impl IntoElement {
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
        .child(kanban_col("TODO", TODO_C, &todo))
        .child(kanban_col("DOING", DOING, &doing))
        .child(kanban_col("DONE", DONE_C, &done))
}

fn kanban_col(
    title: &str,
    color: u32,
    tasks: &[&TaskRow],
) -> impl IntoElement {
    div()
        .flex_1()
        .child(
            div()
                .text_xs()
                .text_color(rgb(MUTED))
                .mb_1()
                .child(title.to_string()),
        )
        .children(tasks.iter().map(|t| task_chip(t, color)))
}

fn task_chip(t: &TaskRow, accent: u32) -> impl IntoElement {
    div()
        .mb_1()
        .px_2()
        .py_1()
        .border_l_2()
        .border_color(rgb(accent))
        .bg(rgb(BG))
        .rounded_sm()
        .text_xs()
        .child(format!("{} {}: {}", t.id, t.owner, t.name))
}

fn side_panel(
    snap: &StoreSnapshot,
    active_log: &mut Option<String>,
) -> impl IntoElement {
    let state = snap.state.as_ref();
    div()
        .w(px(380.))
        .h_full()
        .flex()
        .flex_col()
        .border_l_1()
        .border_color(rgb(BORDER))
        .bg(rgb(PANEL))
        .child(
            div()
                .p_3()
                .border_b_1()
                .border_color(rgb(BORDER))
                .child(
                    div()
                        .text_xs()
                        .text_color(rgb(MUTED))
                        .child("SQUAD ROSTER"),
                )
                .children(
                    state
                        .map(|s| {
                            s.operators
                                .iter()
                                .map(roster_row)
                                .collect::<Vec<_>>()
                        })
                        .unwrap_or_default(),
                ),
        )
        .child(
            div()
                .p_3()
                .border_b_1()
                .border_color(rgb(BORDER))
                .child(
                    div()
                        .text_xs()
                        .text_color(rgb(MUTED))
                        .child("MODEL ROUTING"),
                )
                .child(routing_block(state)),
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
                        .text_color(rgb(MUTED))
                        .mb_2()
                        .child("OPERATOR ACTIVITY"),
                )
                .child(activity_feed(&snap.activity))
                .child(
                    div()
                        .text_xs()
                        .text_color(rgb(MUTED))
                        .mt_3()
                        .mb_1()
                        .child("LOG TAIL"),
                )
                .child(log_tail(snap, active_log)),
        )
}

fn roster_row(op: &OperatorRow) -> impl IntoElement {
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
        .border_l_2()
        .border_color(rgb(ACCENT))
        .pl_2()
        .child(
            div()
                .font_weight(gpui::FontWeight::SEMIBOLD)
                .child(op.id.clone()),
        )
        .child(div().text_color(rgb(MUTED)).text_xs().child(op.title.clone()))
        .child(div().text_xs().child(task_summary))
}

fn routing_block(state: Option<&TocState>) -> impl IntoElement {
    let Some(st) = state else {
        return div().text_xs().child("loading...");
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
}

fn activity_feed(lines: &[ActivityLine]) -> impl IntoElement {
    let recent: Vec<_> = lines.iter().rev().take(24).collect();
    div()
        .id("activity-feed")
        .flex_1()
        .overflow_y_scroll()
        .text_xs()
        .children(recent.iter().map(|l| {
            div().mb_1().child(format!("[{}] {}", l.utc, l.text))
        }))
}

fn log_tail(snap: &StoreSnapshot, active_log: &Option<String>) -> impl IntoElement {
    let key = active_log.clone().unwrap_or_default();
    let body = snap
        .log_buffers
        .get(&key)
        .cloned()
        .unwrap_or_else(|| {
            if key.is_empty() {
                "Waiting for operator logs under missions/*/logs/*.log".into()
            } else {
                "(no lines yet)".into()
            }
        });
    div()
        .id("log-tail")
        .h(px(140.))
        .overflow_y_scroll()
        .p_2()
        .bg(rgb(BG))
        .border_1()
        .border_color(rgb(BORDER))
        .rounded_md()
        .text_xs()
        .child(body)
}