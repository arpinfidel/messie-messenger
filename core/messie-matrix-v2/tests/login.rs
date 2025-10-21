//! Minimal v2 client flow; ignored by default.

use std::path::PathBuf;

use anyhow::{anyhow, Context, Result};
use messie_matrix_v2 as v2;
use serde::Deserialize;

fn must_env(key: &str) -> Result<String> { std::env::var(key).map_err(|_| anyhow!("missing env {key}")) }
fn store_path(suffix: &str) -> PathBuf { let mut p = PathBuf::from("target/it_store_v2"); p.push(suffix); p }

#[test]
#[ignore]
fn login_ok() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let username = must_env("MESSIE_MATRIX_USERNAME")?;
    let password = must_env("MESSIE_MATRIX_PASSWORD")?;
    let base = store_path("client");

    let handle = v2::client_create(&hs, &base).ok_or_else(|| anyhow!("client_create failed"))?;
    let user_id = v2::client_login(handle, Some(&username), Some(&password)).ok_or_else(|| anyhow!("client_login failed"))?;
    assert!(!user_id.is_empty());

    // Do not logout here to preserve the stored session and avoid rate-limits
    // on repeated test runs. Subsequent runs should restore from disk.
    Ok(())
}
