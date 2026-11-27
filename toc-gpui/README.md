# Task Force Null GPUI TOC (optional)

Native, browser-independent tactical operations center built with [GPUI](https://crates.io/crates/gpui) **0.2.2** (Zed's GPU-accelerated Rust UI).

## Quick start

From the repo root (requires [Rust](https://rustup.rs/) and a working desktop display):

```bash
./scripts/toc.sh --gpui
./scripts/toc.sh --native setup-mission
./scripts/toc.sh --gpui --url http://127.0.0.1:8765
```

`--native` is an alias for `--gpui`. The launcher builds `tfn-toc-gpui` on first run if needed.

## Modes

| Mode | Flags | Behavior |
|------|-------|----------|
| Filesystem (default) | (none) | `notify` watches repo paths, tail operator logs under `missions/*/logs/` and `logs/`. |
| SSE | `--url http://127.0.0.1:<port>` | Streams `event: state` and `event: log` from `scripts/toc.sh --web`. |

## Build manually

```bash
cd toc-gpui
cargo test
cargo build --release --features desktop
./target/release/tfn-toc-gpui --repo-root ..
```

CLI options:

- `--repo-root` (env `TFN_REPO_ROOT`)
- `--url` for SSE mode
- `--mission` to pin the header mission slug

## Prerequisites

### Linux (including Arch/Omarchy, Wayland, Vulkan)

- Rust stable (1.85+ recommended; matches GPUI deps on crates.io)
- Vulkan drivers for your GPU (`vulkan-tools`, Mesa or proprietary stack)
- Wayland or X11 session with a compositor
- Dev packages (names vary by distro): `build-essential`, `libxkbcommon-dev`, `libxkbcommon-x11-dev`, `libwayland-dev`, `libvulkan-dev`, `libfontconfig1-dev`, `libfreetype6-dev`, `libssl-dev`, `pkg-config`

On some distros, link `libstdc++` explicitly when building:

```bash
export TFN_TOC_GPUI_RUSTFLAGS='-C link-arg=-L/usr/lib/gcc/x86_64-linux-gnu/13 -C link-arg=-lstdc++'
```

### macOS

- Xcode command line tools
- Rust stable via `rustup`

### Windows

- Rust stable via `rustup`
- Visual Studio Build Tools (C++ workload)
- GPUI on Windows is supported upstream; expect longer first builds

## Architecture

```
toc-gpui/
  src/lib.rs          # Headless library (tests run without GPUI)
  src/state.rs        # collect_state (mirrors scripts/toc_lib.py JSON)
  src/board.rs        # board.md parser
  src/feed/           # filesystem watch + SSE client
  src/store.rs        # shared state + activity feed
  src/view/           # GPUI dashboard (desktop feature)
  src/main.rs         # Binary entry (desktop feature)
```

The `desktop` Cargo feature enables `gpui` and the binary. Default `cargo test` exercises only headless modules.

## Patch note

GPUI depends on `xattr` 0.2.3, which fails to compile on some Linux libc versions. This repo patches it via `toc-gpui/patches/xattr` and `[patch.crates-io]` in `Cargo.toml`.

## Zero dependency core

`./scripts/verify.sh` does not require Rust. Terminal and web TOCs remain the default path when Cargo is not installed.