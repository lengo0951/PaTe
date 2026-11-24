pub struct SettingsModal {
    pub is_open: bool,
}

impl SettingsModal {
    pub fn new() -> Self {
        Self { is_open: false }
    }
}
