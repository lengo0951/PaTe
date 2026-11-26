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
    Credential,
}

/// Fast single-pass 64-bit FNV-1a checksum with zero heap allocations
#[inline]
pub fn compute_fnv1a_hex(bytes: &[u8]) -> String {
    let mut hash: u64 = 0xcbf29ce484222325;
    for &b in bytes {
        hash ^= b as u64;
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{:016x}", hash)
}

impl ContentType {
    pub fn classify(text: &str) -> Self {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            return ContentType::Text;
        }

        // 1. Check for Hex Color (#RGB, #RRGGBB, #RRGGBBAA) in O(1) without allocating lowercase String
        if trimmed.starts_with('#') && (trimmed.len() == 4 || trimmed.len() == 7 || trimmed.len() == 9) {
            if trimmed[1..].bytes().all(|b| b.is_ascii_hexdigit()) {
                return ContentType::Color;
            }
        }

        // 2. Check for URL Link using ASCII case-insensitive prefix check (zero allocation)
        if trimmed.len() >= 8 {
            let prefix8 = &trimmed.as_bytes()[..8.min(trimmed.len())];
            if prefix8.starts_with_ignore_ascii_case(b"https://")
                || prefix8.starts_with_ignore_ascii_case(b"http://")
                || (prefix8.starts_with_ignore_ascii_case(b"www.") && trimmed.contains('.'))
            {
                return ContentType::Link;
            }
        } else if trimmed.as_bytes().starts_with_ignore_ascii_case(b"www.") && trimmed.contains('.') {
            return ContentType::Link;
        }

        // 3. Check for Code Snippet with early short-circuit
        if trimmed.contains('\n') || trimmed.contains(';') {
            let has_code_syntax = trimmed.contains('{')
                || trimmed.contains('}')
                || trimmed.contains("();")
                || trimmed.contains("=>");
            if has_code_syntax {
                return ContentType::Code;
            }
            let code_keywords = [
                "fn ", "def ", "function ", "class ", "struct ", "impl ",
                "import ", "const ", "let ", "var ", "public ", "private ",
                "return ", "#include", "<!DOCTYPE", "SELECT ", "FROM ", "WHERE ",
            ];
            if code_keywords.iter().any(|k| trimmed.contains(k)) {
                return ContentType::Code;
            }
        }

        ContentType::Text
    }
}

trait AsciiPrefixExt {
    fn starts_with_ignore_ascii_case(&self, prefix: &[u8]) -> bool;
}

impl AsciiPrefixExt for [u8] {
    #[inline]
    fn starts_with_ignore_ascii_case(&self, prefix: &[u8]) -> bool {
        self.len() >= prefix.len() && self[..prefix.len()].eq_ignore_ascii_case(prefix)
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
    pub thumbnail_file_name: Option<String>,
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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub credential_username: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub credential_url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub has_vault_secret: Option<bool>,

    /// Pre-encoded UTF-16 preview slice for zero-allocation Win32 WM_PAINT rendering
    #[serde(skip)]
    pub cached_preview_utf16: Vec<u16>,
    #[serde(skip)]
    pub cached_header_utf16: Vec<u16>,
}

impl ClipboardItem {
    pub fn rebuild_render_cache(&mut self) {
        let header = self
            .custom_title
            .as_deref()
            .or(self.app_name.as_deref())
            .unwrap_or(match self.content_type {
                ContentType::Credential => "Account",
                ContentType::Code => "Code",
                ContentType::Link => "Link",
                ContentType::Color => "Color",
                ContentType::Image => "Image",
                ContentType::File => "File",
                ContentType::Text => "Text",
            });
        self.cached_header_utf16 = header.chars().take(28).collect::<String>().encode_utf16().collect();

        let preview = if self.content_type == ContentType::Credential {
            let user = self.credential_username.as_deref().unwrap_or("(no user)");
            format!("User: {}\r\nPass: ••••••••••••\r\n\r\n[Enter/2xClick] User -> Pass\r\n[Ctrl+U] User (+Copy Pass)", user)
        } else if let Some(ref text) = self.text_value {
            text.chars().take(160).collect::<String>()
        } else {
            String::new()
        };
        self.cached_preview_utf16 = preview.encode_utf16().collect();
    }

    pub fn new_text(text: String, app_name: Option<String>, app_id: Option<String>) -> Self {
        let content_type = ContentType::classify(&text);
        let checksum = compute_fnv1a_hex(text.as_bytes());
        let mut item = Self {
            id: Uuid::new_v4().to_string(),
            content_type,
            text_value: Some(text),
            image_file_name: None,
            thumbnail_file_name: None,
            file_paths: None,
            app_bundle_id: app_id,
            app_name,
            created_at: "2026-11-25T00:00:00Z".to_string(),
            checksum,
            pinboard_ids: Vec::new(),
            custom_title: None,
            credential_username: None,
            credential_url: None,
            has_vault_secret: None,
            cached_preview_utf16: Vec::new(),
            cached_header_utf16: Vec::new(),
        };
        item.rebuild_render_cache();
        item
    }

    pub fn new_credential(
        title: String,
        username: String,
        url: Option<String>,
    ) -> Self {
        let seed = format!("cred:{}:{}", title, username);
        let checksum = compute_fnv1a_hex(seed.as_bytes());
        let mut item = Self {
            id: Uuid::new_v4().to_string(),
            content_type: ContentType::Credential,
            text_value: None,
            image_file_name: None,
            thumbnail_file_name: None,
            file_paths: None,
            app_bundle_id: None,
            app_name: Some("Vault".to_string()),
            created_at: "2026-11-25T00:00:00Z".to_string(),
            checksum,
            pinboard_ids: vec![Pinboard::VAULT_ID.to_string()],
            custom_title: Some(title),
            credential_username: Some(username),
            credential_url: url,
            has_vault_secret: Some(true),
            cached_preview_utf16: Vec::new(),
            cached_header_utf16: Vec::new(),
        };
        item.rebuild_render_cache();
        item
    }

    pub fn is_pinned(&self) -> bool {
        self.content_type == ContentType::Credential || !self.pinboard_ids.is_empty()
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
    pub const VAULT_ID: &'static str = "vault";

    pub fn history() -> Self {
        Self {
            id: Self::HISTORY_ID.to_string(),
            name: "Clipboard History".to_string(),
            color_hex: "#0A84FF".to_string(),
            created_at: "2026-11-25T00:00:00Z".to_string(),
            is_system: true,
        }
    }

    pub fn vault() -> Self {
        Self {
            id: Self::VAULT_ID.to_string(),
            name: "Accounts".to_string(),
            color_hex: "#FF375F".to_string(),
            created_at: "2026-11-25T00:00:00Z".to_string(),
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
            max_items: 1000,
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
