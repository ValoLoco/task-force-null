//! Light and dark theme palettes for the GPUI dashboard.

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ThemeMode {
    #[default]
    Dark,
    Light,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ThemePalette {
    pub bg: u32,
    pub panel: u32,
    pub text: u32,
    pub muted: u32,
    pub accent: u32,
    pub border: u32,
    pub doing: u32,
    pub todo: u32,
    pub done: u32,
    pub warn: u32,
    pub chip_active: u32,
    pub chip_idle: u32,
}

impl ThemeMode {
    pub fn palette(self) -> ThemePalette {
        match self {
            ThemeMode::Dark => ThemePalette {
                bg: 0x0d1117,
                panel: 0x161b22,
                text: 0xe6edf3,
                muted: 0x8b949e,
                accent: 0x3fb950,
                border: 0x30363d,
                doing: 0x1565c0,
                todo: 0x5c6773,
                done: 0x2e7d32,
                warn: 0xb58105,
                chip_active: 0x1f6feb,
                chip_idle: 0x21262d,
            },
            ThemeMode::Light => ThemePalette {
                bg: 0xf6f8fa,
                panel: 0xffffff,
                text: 0x1f2328,
                muted: 0x656d76,
                accent: 0x1a7f37,
                border: 0xd0d7de,
                doing: 0x0969da,
                todo: 0x6e7781,
                done: 0x1a7f37,
                warn: 0x9a6700,
                chip_active: 0x0969da,
                chip_idle: 0xeaeef2,
            },
        }
    }

    pub fn toggle(self) -> Self {
        match self {
            ThemeMode::Dark => ThemeMode::Light,
            ThemeMode::Light => ThemeMode::Dark,
        }
    }

    pub fn toggle_label(self) -> &'static str {
        match self {
            ThemeMode::Dark => "Light",
            ThemeMode::Light => "Dark",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_is_dark() {
        assert_eq!(ThemeMode::default(), ThemeMode::Dark);
    }

    #[test]
    fn toggle_roundtrip() {
        let mode = ThemeMode::Dark;
        assert_eq!(mode.toggle().toggle(), mode);
    }
}