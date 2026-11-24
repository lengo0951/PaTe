use std::fs;
use std::path::PathBuf;
use crate::core::types::{AppConfig, ClipboardItem, Pinboard};

pub struct HistoryStore {
    pub items: Vec<ClipboardItem>,
    pub pinboards: Vec<Pinboard>,
    pub config: AppConfig,
    storage_dir: PathBuf,
}

impl HistoryStore {
    pub fn new(storage_dir: PathBuf) -> Self {
        let mut store = Self {
            items: Vec::new(),
            pinboards: vec![Pinboard::history()],
            config: AppConfig::default(),
            storage_dir,
        };
        store.load();
        store
    }

    pub fn is_blacklisted(&self, app_name: Option<&str>, app_id: Option<&str>) -> bool {
        let check = |target: &str| {
            let lower_target = target.to_lowercase();
            self.config.blacklist.iter().any(|b| {
                let lower_b = b.to_lowercase();
                lower_target.contains(&lower_b) || lower_b.contains(&lower_target)
            })
        };

        if let Some(name) = app_name {
            if check(name) {
                return true;
            }
        }
        if let Some(id) = app_id {
            if check(id) {
                return true;
            }
        }
        false
    }

    pub fn add_item(&mut self, item: ClipboardItem) -> bool {
        // 1. Check blacklist
        if self.is_blacklisted(item.app_name.as_deref(), item.app_bundle_id.as_deref()) {
            return false;
        }

        // 2. Check duplicate text
        if let Some(ref text) = item.text_value {
            if let Some(pos) = self.items.iter().position(|i| i.text_value.as_ref() == Some(text)) {
                let mut existing = self.items.remove(pos);
                // Preserve pinboards
                for pb in item.pinboard_ids {
                    if !existing.pinboard_ids.contains(&pb) {
                        existing.pinboard_ids.push(pb);
                    }
                }
                self.items.insert(0, existing);
                return true;
            }
        }

        // 3. Insert at top
        self.items.insert(0, item);

        // 4. Enforce LRU cap (do not evict pinned items)
        if self.items.len() > self.config.max_items {
            let mut unpinned_indices: Vec<usize> = self
                .items
                .iter()
                .enumerate()
                .filter(|(_, i)| i.pinboard_ids.is_empty())
                .map(|(idx, _)| idx)
                .collect();

            while self.items.len() > self.config.max_items && !unpinned_indices.is_empty() {
                let remove_idx = unpinned_indices.pop().unwrap();
                if remove_idx < self.items.len() {
                    self.items.remove(remove_idx);
                }
            }
        }

        true
    }

    pub fn rename_item(&mut self, id: &str, new_title: Option<String>) {
        if let Some(item) = self.items.iter_mut().find(|it| it.id == id) {
            item.custom_title = new_title.filter(|t| !t.trim().is_empty());
        }
    }

    pub fn load(&mut self) {
        let config_file = self.storage_dir.join("config.json");
        if config_file.exists() {
            if let Ok(data) = fs::read_to_string(&config_file) {
                if let Ok(cfg) = serde_json::from_str(&data) {
                    self.config = cfg;
                }
            }
        }

        let pinboards_file = self.storage_dir.join("pinboards.json");
        if pinboards_file.exists() {
            if let Ok(data) = fs::read_to_string(&pinboards_file) {
                if let Ok(pbs) = serde_json::from_str(&data) {
                    self.pinboards = pbs;
                }
            }
        }

        let history_file = self.storage_dir.join("history.json");
        if history_file.exists() {
            if let Ok(data) = fs::read_to_string(&history_file) {
                if let Ok(its) = serde_json::from_str(&data) {
                    self.items = its;
                }
            }
        }
    }

    pub fn save(&self) -> std::io::Result<()> {
        let _ = fs::create_dir_all(&self.storage_dir);

        let config_file = self.storage_dir.join("config.json");
        let data = serde_json::to_string_pretty(&self.config)?;
        fs::write(config_file, data)?;

        let pinboards_file = self.storage_dir.join("pinboards.json");
        let data = serde_json::to_string_pretty(&self.pinboards)?;
        fs::write(pinboards_file, data)?;

        let history_file = self.storage_dir.join("history.json");
        let data = serde_json::to_string_pretty(&self.items)?;
        fs::write(history_file, data)?;

        Ok(())
    }
}
