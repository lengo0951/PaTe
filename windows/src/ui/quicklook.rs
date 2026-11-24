pub struct QuickLookModal {
    pub is_open: bool,
}

impl QuickLookModal {
    pub fn new() -> Self {
        Self { is_open: false }
    }
}
