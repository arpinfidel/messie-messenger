//! Minimal v2 client flow; ignored by default.

use std::path::PathBuf;

use anyhow::{anyhow, Context, Result};
use messie_matrix_v2 as v2;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct EnvelopeOk<T> { #[allow(dead_code)] ok: bool, data: T }

#[derive(Debug, Deserialize)]
struct ClientHandleData { handle: u64 }

#[derive(Debug, Deserialize)]
struct LoginData { user_id: String }

fn must_env(key: &str) -> Result<String> { std::env::var(key).map_err(|_| anyhow!("missing env {key}")) }
fn store_path(suffix: &str) -> PathBuf { let mut p = PathBuf::from("target/it_store_v2"); p.push(suffix); p }

#[test]
#[ignore]
fn login_ok() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let username = must_env("MESSIE_MATRIX_USERNAME")?;
    let password = must_env("MESSIE_MATRIX_PASSWORD")?;
    let base = store_path("client");

    let new_json = v2::client_new(&hs, &base);
    let handle_env: EnvelopeOk<ClientHandleData> = serde_json::from_str(&new_json).context("parse client_new envelope")?;
    assert!(handle_env.ok);
    let handle = handle_env.data.handle;

    let login_json = v2::client_restore_or_login(handle, Some(&username), Some(&password));
    let env: EnvelopeOk<LoginData> = serde_json::from_str(&login_json).context("parse login envelope")?;
    assert!(env.ok);
    assert!(!env.data.user_id.is_empty());

    // Do not logout here to preserve the stored session and avoid rate-limits
    // on repeated test runs. Subsequent runs should restore from disk.
    Ok(())
}
