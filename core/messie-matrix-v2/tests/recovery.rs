//! v2 SSSS recovery key restore smoke test (ignored by default).

use std::path::PathBuf;

use anyhow::{anyhow, Context, Result};
use messie_matrix_v2 as v2;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct EnvelopeOk<T> { #[allow(dead_code)] ok: bool, data: T }

#[derive(Debug, Deserialize)]
struct HandleData { handle: u64 }

fn must_env(key: &str) -> Result<String> { std::env::var(key).map_err(|_| anyhow!("missing env {key}")) }
fn store_path(suffix: &str) -> PathBuf { let mut p = PathBuf::from("target/it_store_v2"); p.push(suffix); p }

fn load_recovery_key() -> Option<String> {
    if let Ok(k) = std::env::var("MESSIE_MATRIX_RECOVERY_KEY") {
        let k = k.trim().to_string();
        if !k.is_empty() { return Some(k); }
    }
    // Try seed state file(s)
    for path in [
        PathBuf::from("scripts/matrix/.state/recovery_key.json"),
        PathBuf::from("../scripts/matrix/.state/recovery_key.json"),
    ] {
        if let Ok(raw) = std::fs::read_to_string(&path) {
            // JSON object { recovery_key } or plain key
            if let Ok(val) = serde_json::from_str::<serde_json::Value>(&raw) {
                if let Some(k) = val.get("recovery_key").and_then(|x| x.as_str()) {
                    let k = k.trim().to_string();
                    if !k.is_empty() { return Some(k); }
                }
            }
            let k = raw.trim().to_string();
            if !k.is_empty() { return Some(k); }
        }
    }
    None
}

#[test]
#[ignore]
fn ssss_import_key_and_enable_backup() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let username = must_env("MESSIE_MATRIX_USERNAME")?;
    let password = must_env("MESSIE_MATRIX_PASSWORD")?;
    let Some(key) = load_recovery_key() else { return Ok(()); }; // skip silently if no key

    let base = store_path("recovery_client");
    let new_env: EnvelopeOk<HandleData> = serde_json::from_str(&v2::client_new(&hs, &base)).context("parse client_new")?;
    let client = new_env.data.handle;
    let _ = v2::client_restore_or_login(client, Some(&username), Some(&password));

    // Import recovery key and enable/attach to backup
    let import_env: serde_json::Value = serde_json::from_str(&v2::ssss_import_recovery_key(client, &key)).context("parse import ack")?;
    assert_eq!(import_env.get("ok").and_then(|b| b.as_bool()).unwrap_or(false), true);
    let enable_env: serde_json::Value = serde_json::from_str(&v2::enable_online_backup(client, false)).context("parse enable ack")?;
    assert_eq!(enable_env.get("ok").and_then(|b| b.as_bool()).unwrap_or(false), true);

    Ok(())
}
