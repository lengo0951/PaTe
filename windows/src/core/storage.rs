use std::collections::HashSet;
use std::fs;
use std::path::PathBuf;
use crate::core::types::{AppConfig, ClipboardItem, ContentType, Pinboard};
use crate::core::vault::CredentialVault;

pub struct HistoryStore {
    pub items: Vec<ClipboardItem>,
    pub pinboards: Vec<Pinboard>,
    pub config: AppConfig,
    pub vault: CredentialVault,
    storage_dir: PathBuf,
    checksum_set: HashSet<String>,
}

impl HistoryStore {
    pub fn new(storage_dir: PathBuf) -> Self {
        let vault = CredentialVault::new(storage_dir.clone());
        let mut store = Self {
            items: Vec::new(),
            pinboards: vec![Pinboard::history(), Pinboard::vault()],
            config: AppConfig::default(),
            vault,
            storage_dir,
            checksum_set: HashSet::new(),
        };
        store.load();
        store
    }

    pub fn is_blacklisted(&self, app_name: Option<&str>, app_id: Option<&str>) -> bool {
        let check = |target: &str| {
            self.config.blacklist.iter().any(|b| {
                contains_ascii_case_insensitive(target, b) || contains_ascii_case_insensitive(b, target)
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

    pub fn add_item(&mut self, mut item: ClipboardItem) -> bool {
        if self.is_blacklisted(item.app_name.as_deref(), item.app_bundle_id.as_deref()) {
            return false;
        }

        // Fast O(1) checksum check before O(N) scan
        if self.checksum_set.contains(&item.checksum) {
            if let Some(pos) = self.items.iter().position(|i| {
                i.checksum == item.checksum && i.text_value == item.text_value
            }) {
                let mut existing = self.items.remove(pos);
                for pb in item.pinboard_ids {
                    if !existing.pinboard_ids.contains(&pb) {
                        existing.pinboard_ids.push(pb);
                    }
                }
                self.items.insert(0, existing);
                return true;
            }
        }

        item.rebuild_render_cache();
        self.checksum_set.insert(item.checksum.clone());
        self.items.insert(0, item);

        // Enforce LRU cap without evicting pinned or credential items
        while self.items.len() > self.config.max_items {
            if let Some(idx) = self.items.iter().rposition(|i| !i.is_pinned()) {
                let removed = self.items.remove(idx);
                self.checksum_set.remove(&removed.checksum);
            } else {
                break;
            }
        }

        true
    }

    pub fn save_credential(
        &mut self,
        existing_id: Option<&str>,
        title: String,
        username: String,
        password: &str,
        url: Option<String>,
    ) -> String {
        if let Some(id) = existing_id {
            if let Some(item) = self.items.iter_mut().find(|it| it.id == id) {
                item.content_type = ContentType::Credential;
                item.custom_title = Some(title);
                item.credential_username = Some(username);
                item.credential_url = url;
                item.text_value = None;
                item.has_vault_secret = Some(true);
                if !item.pinboard_ids.iter().any(|p| p == Pinboard::VAULT_ID) {
                    item.pinboard_ids.push(Pinboard::VAULT_ID.to_string());
                }
                if !password.is_empty() {
                    self.vault.set_secret(id, password);
                }
                item.rebuild_render_cache();
                return id.to_string();
            }
        }

        let item = ClipboardItem::new_credential(title, username, url);
        let id = item.id.clone();
        self.vault.set_secret(&id, password);
        self.checksum_set.insert(item.checksum.clone());
        self.items.insert(0, item);
        id
    }

    pub fn remove_item(&mut self, id: &str) {
        if let Some(pos) = self.items.iter().position(|i| i.id == id) {
            let removed = self.items.remove(pos);
            self.checksum_set.remove(&removed.checksum);
            if removed.content_type == ContentType::Credential || removed.has_vault_secret == Some(true) {
                self.vault.remove_secret(&removed.id);
            }
        }
    }

    pub fn rename_item(&mut self, id: &str, new_title: Option<String>) {
        if let Some(item) = self.items.iter_mut().find(|it| it.id == id) {
            item.custom_title = new_title.filter(|t| !t.trim().is_empty());
            item.rebuild_render_cache();
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
                if let Ok(mut pbs) = serde_json::from_str::<Vec<Pinboard>>(&data) {
                    if !pbs.iter().any(|p| p.id == Pinboard::VAULT_ID) {
                        let idx = 1.min(pbs.len());
                        pbs.insert(idx, Pinboard::vault());
                    }
                    self.pinboards = pbs;
                }
            }
        }

        let history_file = self.storage_dir.join("history.json");
        if history_file.exists() {
            if let Ok(data) = fs::read_to_string(&history_file) {
                if let Ok(mut its) = serde_json::from_str::<Vec<ClipboardItem>>(&data) {
                    self.checksum_set.clear();
                    for it in &mut its {
                        it.rebuild_render_cache();
                        self.checksum_set.insert(it.checksum.clone());
                    }
                    self.items = its;
                }
            }
        }
    }

    pub fn save(&self) -> std::io::Result<()> {
        let _ = fs::create_dir_all(&self.storage_dir);

        let config_file = self.storage_dir.join("config.json");
        fs::write(config_file, serde_json::to_string(&self.config)?)?;

        let pinboards_file = self.storage_dir.join("pinboards.json");
        fs::write(pinboards_file, serde_json::to_string(&self.pinboards)?)?;

        let history_file = self.storage_dir.join("history.json");
        fs::write(history_file, serde_json::to_string(&self.items)?)?;

        Ok(())
    }
}

/// Zero-allocation ASCII case-insensitive substring search
#[inline]
fn contains_ascii_case_insensitive(haystack: &str, needle: &str) -> bool {
    let h = haystack.as_bytes();
    let n = needle.as_bytes();
    if n.is_empty() {
        return true;
    }
    if n.len() > h.len() {
        return false;
    }
    h.windows(n.len()).any(|w| w.eq_ignore_ascii_case(n))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_credential_save_and_lru_protection() {
        let temp_dir = std::env::temp_dir().join(format!("pasteflow_store_test_{}", uuid::Uuid::new_v4()));
        let mut store = HistoryStore::new(temp_dir.clone());
        store.config.max_items = 2;

        let cred_id = store.save_credential(
            None,
            "dgcb sso prod".to_string(),
            "quoc.ngo".to_string(),
            "SuperSecret#2026",
            Some("https://sso.cnsc.com.vn".to_string()),
        );
        assert_eq!(store.vault.get_secret(&cred_id).as_deref(), Some("SuperSecret#2026"));

        // Add 3 normal clips; credential must NOT be evicted!
        store.add_item(ClipboardItem::new_text("clip 1".to_string(), None, None));
        store.add_item(ClipboardItem::new_text("clip 2".to_string(), None, None));
        store.add_item(ClipboardItem::new_text("clip 3".to_string(), None, None));

        assert!(store.items.iter().any(|i| i.id == cred_id));
        store.save().unwrap();

        // Ensure plaintext password is NEVER written into history.json
        let history_raw = fs::read_to_string(temp_dir.join("history.json")).unwrap();
        assert!(!history_raw.contains("SuperSecret#2026"));

        let _ = fs::remove_dir_all(temp_dir);
    }
}
