//! v2 Backup/SSSS smoke tests (ignored by default).

use std::path::PathBuf;

use anyhow::{anyhow, Context, Result};
use messie_matrix_v2 as v2;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct EnvelopeOk<T> { #[allow(dead_code)] ok: bool, data: T }

#[derive(Debug, Deserialize)]
struct HandleData { handle: u64 }

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct BackupStatus { enabled: bool, exists_on_server: bool, recovery_state: String, needs_recovery: bool }

fn must_env(key: &str) -> Result<String> { std::env::var(key).map_err(|_| anyhow!("missing env {key}")) }
fn store_path(suffix: &str) -> PathBuf { let mut p = PathBuf::from("target/it_store_v2"); p.push(suffix); p }

#[test]
#[ignore]
fn backup_status_and_stream_ack() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let username = must_env("MESSIE_MATRIX_USERNAME")?;
    let password = must_env("MESSIE_MATRIX_PASSWORD")?;
    let base = store_path("backup_client");

    // Client + login (typed API)
    let client = v2::client_create(&hs, &base).ok_or_else(|| anyhow!("client_create failed"))?;
    let _ = v2::client_login(client, Some(&username), Some(&password));

    // One-shot status
    let status_env: EnvelopeOk<BackupStatus> = serde_json::from_str(&v2::backup_status_json(client)).context("parse backup_status")?;
    assert!(status_env.ok);
    let _ = status_env.data; // not asserting specific fields (depends on environment)

    // Stream start (to dummy port 0) should ACK
    let ack: serde_json::Value = serde_json::from_str(&v2::backup_status_stream_json(client, 0)).context("parse stream ack")?;
    assert_eq!(ack.get("ok").and_then(|b| b.as_bool()).unwrap_or(false), true);

    Ok(())
}
