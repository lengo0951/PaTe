use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ContentType {
    Text,
    Link,
    Color,
    Code,
    Image,
    File,
}

impl ContentType {
    pub fn classify(text: &str) -> Self {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            return ContentType::Text;
        }

        let lower = trimmed.to_lowercase();

        // 1. Check for URL Link
        if lower.starts_with("http://")
            || lower.starts_with("https://")
            || (lower.starts_with("www.") && lower.contains('.'))
        {
            return ContentType::Link;
        }

        // 2. Check for Hex Color (#RGB, #RRGGBB, #RRGGBBAA)
        if trimmed.starts_with('#') && (trimmed.len() == 4 || trimmed.len() == 7 || trimmed.len() == 9) {
            let hex_part = &trimmed[1..];
            if hex_part.chars().all(|c| c.is_ascii_hexdigit()) {
                return ContentType::Color;
            }
        }

        // 3. Check for Code Snippet
        let code_keywords = [
            "fn ", "def ", "function ", "class ", "struct ", "impl ",
            "import ", "const ", "let ", "var ", "public ", "private ",
            "return ", "#include", "<!DOCTYPE", "SELECT ", "FROM ", "WHERE "
        ];
        let has_code_keyword = code_keywords.iter().any(|k| trimmed.contains(k));
        let has_code_syntax = trimmed.contains('{') || trimmed.contains('}') || trimmed.contains("();") || trimmed.contains("=>");
        if (has_code_keyword || has_code_syntax) && (trimmed.contains('\n') || trimmed.contains(';')) {
            return ContentType::Code;
        }

        ContentType::Text
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ClipboardItem {
    pub id: String,
    pub content_type: ContentType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text_value: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub image_file_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file_paths: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub app_bundle_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub app_name: Option<String>,
    pub created_at: String,
    pub checksum: String,
    #[serde(default)]
    pub pinboard_ids: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub custom_title: Option<String>,
}

impl ClipboardItem {
    pub fn new_text(text: String, app_name: Option<String>, app_id: Option<String>) -> Self {
        let content_type = ContentType::classify(&text);
        let checksum = format!("{:x}", text.len() ^ 0x5F3759DF);
        Self {
            id: Uuid::new_v4().to_string(),
            content_type,
            text_value: Some(text),
            image_file_name: None,
            file_paths: None,
            app_bundle_id: app_id,
            app_name,
            created_at: "2026-11-24T00:00:00Z".to_string(),
            checksum,
            pinboard_ids: Vec::new(),
            custom_title: None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Pinboard {
    pub id: String,
    pub name: String,
    pub color_hex: String,
    pub created_at: String,
    #[serde(default)]
    pub is_system: bool,
}

impl Pinboard {
    pub const HISTORY_ID: &'static str = "history";

    pub fn history() -> Self {
        Self {
            id: Self::HISTORY_ID.to_string(),
            name: "Clipboard History".to_string(),
            color_hex: "#0A84FF".to_string(),
            created_at: "2026-11-24T00:00:00Z".to_string(),
            is_system: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct AppConfig {
    pub hotkey: String,
    pub max_items: usize,
    pub launch_at_startup: bool,
    pub blacklist: Vec<String>,
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            hotkey: "Ctrl+Shift+V".to_string(),
            max_items: 500,
            launch_at_startup: false,
            blacklist: vec![
                "1Password.exe".to_string(),
                "Bitwarden.exe".to_string(),
                "KeePass.exe".to_string(),
                "KeePassXC.exe".to_string(),
                "CredentialUIBroker.exe".to_string(),
            ],
        }
    }
}
