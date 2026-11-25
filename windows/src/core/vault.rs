use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

/// Native Windows DPAPI Credential Vault (`CryptProtectData` / `CryptUnprotectData`).
/// Zero prompts, bound to the current Windows user's logon credentials, zero plaintext on disk.
pub struct CredentialVault {
    vault_file: PathBuf,
    encrypted_blobs: HashMap<String, String>,
}

impl CredentialVault {
    pub fn new(storage_dir: PathBuf) -> Self {
        let vault_file = storage_dir.join("vault.enc.json");
        let mut vault = Self {
            vault_file,
            encrypted_blobs: HashMap::new(),
        };
        vault.load();
        vault
    }

    pub fn set_secret(&mut self, item_id: &str, secret: &str) -> bool {
        if let Some(protected) = Self::protect_bytes(secret.as_bytes()) {
            self.encrypted_blobs
                .insert(item_id.to_string(), bytes_to_hex(&protected));
            let _ = self.save();
            return true;
        }
        false
    }

    pub fn get_secret(&self, item_id: &str) -> Option<String> {
        let hex_blob = self.encrypted_blobs.get(item_id)?;
        let raw_blob = hex_to_bytes(hex_blob)?;
        let plain_bytes = Self::unprotect_bytes(&raw_blob)?;
        String::from_utf8(plain_bytes).ok()
    }

    pub fn remove_secret(&mut self, item_id: &str) {
        if self.encrypted_blobs.remove(item_id).is_some() {
            let _ = self.save();
        }
    }

    fn load(&mut self) {
        if self.vault_file.exists() {
            if let Ok(data) = fs::read_to_string(&self.vault_file) {
                if let Ok(map) = serde_json::from_str::<HashMap<String, String>>(&data) {
                    self.encrypted_blobs = map;
                }
            }
        }
    }

    fn save(&self) -> std::io::Result<()> {
        if let Some(parent) = self.vault_file.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let json = serde_json::to_string(&self.encrypted_blobs)?;
        fs::write(&self.vault_file, json)
    }

    #[cfg(windows)]
    fn protect_bytes(plain: &[u8]) -> Option<Vec<u8>> {
        use windows::Win32::Foundation::{HLOCAL, LocalFree};
        use windows::Win32::Security::Cryptography::{
            CryptProtectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
        };

        unsafe {
            let mut in_buf = plain.to_vec();
            let in_blob = CRYPT_INTEGER_BLOB {
                cbData: in_buf.len() as u32,
                pbData: in_buf.as_mut_ptr(),
            };
            let mut out_blob = CRYPT_INTEGER_BLOB::default();

            if CryptProtectData(
                &in_blob,
                windows::core::PCWSTR::null(),
                None,
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut out_blob,
            )
            .is_ok()
            {
                let slice =
                    std::slice::from_raw_parts(out_blob.pbData, out_blob.cbData as usize);
                let result = slice.to_vec();
                let _ = LocalFree(HLOCAL(out_blob.pbData as *mut _));
                Some(result)
            } else {
                None
            }
        }
    }

    #[cfg(windows)]
    fn unprotect_bytes(cipher: &[u8]) -> Option<Vec<u8>> {
        use windows::Win32::Foundation::{HLOCAL, LocalFree};
        use windows::Win32::Security::Cryptography::{
            CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
        };

        unsafe {
            let mut in_buf = cipher.to_vec();
            let in_blob = CRYPT_INTEGER_BLOB {
                cbData: in_buf.len() as u32,
                pbData: in_buf.as_mut_ptr(),
            };
            let mut out_blob = CRYPT_INTEGER_BLOB::default();

            if CryptUnprotectData(
                &in_blob,
                None,
                None,
                None,
                None,
                CRYPTPROTECT_UI_FORBIDDEN,
                &mut out_blob,
            )
            .is_ok()
            {
                let slice =
                    std::slice::from_raw_parts(out_blob.pbData, out_blob.cbData as usize);
                let result = slice.to_vec();
                let _ = LocalFree(HLOCAL(out_blob.pbData as *mut _));
                Some(result)
            } else {
                None
            }
        }
    }

    /// Cross-platform test fallback when running `cargo test` on non-Windows hosts
    #[cfg(not(windows))]
    fn protect_bytes(plain: &[u8]) -> Option<Vec<u8>> {
        const KEY: &[u8] = b"PasteFlowVaultTestKey_QuocNgo_v1";
        Some(
            plain
                .iter()
                .enumerate()
                .map(|(i, &b)| b ^ KEY[i % KEY.len()])
                .collect(),
        )
    }

    #[cfg(not(windows))]
    fn unprotect_bytes(cipher: &[u8]) -> Option<Vec<u8>> {
        Self::protect_bytes(cipher)
    }
}

#[inline]
fn bytes_to_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0f) as usize] as char);
    }
    out
}

#[inline]
fn hex_to_bytes(hex: &str) -> Option<Vec<u8>> {
    if hex.len() % 2 != 0 {
        return None;
    }
    let bytes = hex.as_bytes();
    let mut out = Vec::with_capacity(bytes.len() / 2);
    let mut i = 0;
    while i < bytes.len() {
        let hi = hex_val(bytes[i])?;
        let lo = hex_val(bytes[i + 1])?;
        out.push((hi << 4) | lo);
        i += 2;
    }
    Some(out)
}

#[inline]
fn hex_val(b: u8) -> Option<u8> {
    match b {
        b'0'..=b'9' => Some(b - b'0'),
        b'a'..=b'f' => Some(b - b'a' + 10),
        b'A'..=b'F' => Some(b - b'A' + 10),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vault_roundtrip_and_persistence() {
        let temp_dir = std::env::temp_dir().join(format!("pasteflow_vault_test_{}", uuid::Uuid::new_v4()));
        let mut vault = CredentialVault::new(temp_dir.clone());
        assert!(vault.set_secret("cred-1", "Bb^lh$7P@L9x0Wl"));
        assert_eq!(vault.get_secret("cred-1").as_deref(), Some("Bb^lh$7P@L9x0Wl"));

        // Reload from disk and verify no plaintext stored
        let raw_disk = fs::read_to_string(temp_dir.join("vault.enc.json")).unwrap();
        assert!(!raw_disk.contains("Bb^lh$7P@L9x0Wl"));

        let reloaded = CredentialVault::new(temp_dir.clone());
        assert_eq!(reloaded.get_secret("cred-1").as_deref(), Some("Bb^lh$7P@L9x0Wl"));

        let mut reloaded_mut = reloaded;
        reloaded_mut.remove_secret("cred-1");
        assert_eq!(reloaded_mut.get_secret("cred-1"), None);
        let _ = fs::remove_dir_all(temp_dir);
    }
}
