use std::path::PathBuf;

use anyhow::{anyhow, Result};
use messie_matrix_v2 as v2;

fn must_env(key: &str) -> Result<String> { std::env::var(key).map_err(|_| anyhow!("missing env {key}")) }
fn store_path(suffix: &str) -> PathBuf { let mut p = PathBuf::from("target/it_store_v2"); p.push(suffix); p }

#[test]
#[ignore]
fn subscribe_and_expire_session() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let username = must_env("MESSIE_MATRIX_USERNAME")?;
    let password = must_env("MESSIE_MATRIX_PASSWORD")?;
    let base = store_path("subscribe_client");

    let client = v2::client_create(&hs, &base).ok_or_else(|| anyhow!("client_create failed"))?;
    let _ = v2::client_login(client, Some(&username), Some(&password));

    // Thin: create minimal sliding sync and start headless
    let ss = v2::sliding_sync_create(client, v2::SlidingSyncConfig { poll_timeout_ms: 0, network_timeout_ms: 0, enable_e2ee: true, enable_to_device: false })
        .ok_or_else(|| anyhow!("failed to create thin sliding sync"))?;
    let _ = v2::sliding_sync_start_streaming(ss, 0);

    // Get joined rooms and subscribe to subset (typed)
    let rooms: Vec<String> = v2::client_list_joined_rooms(client).unwrap_or_default();
    if !rooms.is_empty() {
        let subset: Vec<String> = rooms.into_iter().take(5).collect();
        let _ = v2::sliding_sync_subscribe_to_rooms(ss, &subset, Some(20u32), None, true);
    }

    // Force expire_session and expect no crash
    let _ = v2::sliding_sync_expire_session(ss);
    let _ = v2::sliding_sync_stop(ss);
    Ok(())
}
