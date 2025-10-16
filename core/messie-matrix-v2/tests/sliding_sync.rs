//! Minimal v2 sliding sync flow; ignored by default.

use std::path::PathBuf;

use anyhow::{anyhow, Context, Result};
use messie_matrix_v2 as v2;
use serde::Deserialize;
use std::thread;
use std::time::{Duration, Instant};

#[derive(Debug, Deserialize)]
struct EnvelopeOk<T> { #[allow(dead_code)] ok: bool, data: T }


#[derive(Debug, Deserialize)]
struct HandleData { handle: u64 }

fn must_env(key: &str) -> Result<String> { std::env::var(key).map_err(|_| anyhow!("missing env {key}")) }
fn store_path(suffix: &str) -> PathBuf { let mut p = PathBuf::from("target/it_store_v2"); p.push(suffix); p }

#[test]
#[ignore]
fn sliding_sync_start_stops() -> Result<()> {
    // Pre-req: valid homeserver + credentials
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let username = must_env("MESSIE_MATRIX_USERNAME")?;
    let password = must_env("MESSIE_MATRIX_PASSWORD")?;
    let base = store_path("ss_client");

    // Create client and login/restore
    let new_json = v2::client_new(&hs, &base);
    let handle_env: EnvelopeOk<HandleData> = serde_json::from_str(&new_json).context("parse client_new envelope")?;
    assert!(handle_env.ok);
    let client = handle_env.data.handle;

    let login_json = v2::client_restore_or_login(client, Some(&username), Some(&password));
    let _: EnvelopeOk<serde_json::Value> = serde_json::from_str(&login_json).context("parse login envelope")?;

    // Thin: create and start/stop
    let ss = v2::sliding_sync_create(client, v2::SlidingSyncConfig { poll_timeout_ms: 0, network_timeout_ms: 0, enable_e2ee: true, enable_to_device: false })
        .ok_or_else(|| anyhow!("failed to create thin sliding sync"))?;
    assert!(v2::sliding_sync_start_streaming(ss, 0));
    assert!(v2::sliding_sync_stop(ss));
    Ok(())
}

#[test]
#[ignore]
#[cfg(feature = "test-helpers")]
fn unknown_pos_recovery_via_expire_session() -> Result<()> {
    // Requires a real homeserver and credentials via env
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let username = must_env("MESSIE_MATRIX_USERNAME")?;
    let password = must_env("MESSIE_MATRIX_PASSWORD")?;
    let base = store_path("ss_unknownpos_recover");

    // Create client and login/restore
    let new_json = v2::client_new(&hs, &base);
    let handle_env: EnvelopeOk<HandleData> = serde_json::from_str(&new_json).context("parse client_new envelope")?;
    let client = handle_env.data.handle;

    let _ = v2::client_restore_or_login(client, Some(&username), Some(&password));

    // Thin minimal sliding sync and start
    let ss = v2::sliding_sync_create(client, v2::SlidingSyncConfig { poll_timeout_ms: 0, network_timeout_ms: 0, enable_e2ee: true, enable_to_device: false })
        .ok_or_else(|| anyhow!("failed to create thin sliding sync"))?;

    // Nudge hydration to kick initial updates
    let _ = v2::client_sync_once(client);

    // Start without a port (headless)
    let _ = v2::sliding_sync_start_streaming(ss, 0);

    // Wait for at least one update
    let start_deadline = Instant::now() + Duration::from_secs(30);
    let mut first_count = 0u64;
    while Instant::now() < start_deadline {
        let cnt_json = v2::__test_ss_update_count(ss);
        let v: serde_json::Value = serde_json::from_str(&cnt_json).context("parse count json")?;
        if v.get("ok").and_then(|b| b.as_bool()).unwrap_or(false) {
            if let Some(c) = v.get("data").and_then(|d| d.get("count")).and_then(|n| n.as_u64()) {
                first_count = c;
                if first_count >= 1 { break; }
            }
        }
        thread::sleep(Duration::from_millis(500));
    }
    assert!(first_count >= 1, "expected at least one sliding_sync update before expire_session");

    // Expire session explicitly (mimics recovery action)
    let _ = v2::sliding_sync_expire_session(ss);

    // Expect update count to increase within timeout
    let after_deadline = Instant::now() + Duration::from_secs(30);
    let mut advanced = false;
    while Instant::now() < after_deadline {
        let cnt_json = v2::__test_ss_update_count(ss);
        let v: serde_json::Value = serde_json::from_str(&cnt_json).context("parse count json")?;
        if v.get("ok").and_then(|b| b.as_bool()).unwrap_or(false) {
            if let Some(c) = v.get("data").and_then(|d| d.get("count")).and_then(|n| n.as_u64()) {
                if c > first_count { advanced = true; break; }
            }
        }
        thread::sleep(Duration::from_millis(500));
    }

    let _ = v2::sliding_sync_stop(ss);
    assert!(advanced, "expected sliding_sync updates to continue after expire_session");
    Ok(())
}

#[test]
#[ignore]
#[cfg(feature = "test-helpers")]
fn sliding_sync_produces_room_ids() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let username = must_env("MESSIE_MATRIX_USERNAME")?;
    let password = must_env("MESSIE_MATRIX_PASSWORD")?;
    let base = store_path("ss_rooms");

    // Create client and login/restore
    let new_json = v2::client_new(&hs, &base);
    let handle_env: EnvelopeOk<HandleData> = serde_json::from_str(&new_json).context("parse client_new envelope")?;
    let client = handle_env.data.handle;

    let login_json = v2::client_restore_or_login(client, Some(&username), Some(&password));
    let _: EnvelopeOk<serde_json::Value> = serde_json::from_str(&login_json).context("parse login envelope")?;

    // Thin sliding sync (same goal)
    let ss = v2::sliding_sync_create(client, v2::SlidingSyncConfig { poll_timeout_ms: 0, network_timeout_ms: 0, enable_e2ee: true, enable_to_device: false })
        .ok_or_else(|| anyhow!("failed to create thin sliding sync"))?;

    // Nudge hydration via classic sync_once
    let _ = v2::client_sync_once(client);

    // Start without a port (headless) and poll room IDs via test-only helper
    let _ = v2::sliding_sync_start_streaming(ss, 0);

    let deadline = Instant::now() + Duration::from_secs(20);
    let mut seen_any = false;
    while Instant::now() < deadline {
        // test-only helper returns rooms
        let rooms_json = v2::__test_ss_known_rooms(ss);
        let v: serde_json::Value = serde_json::from_str(&rooms_json).context("parse rooms json")?;
        if v.get("ok").and_then(|b| b.as_bool()).unwrap_or(false) {
            if let Some(arr) = v.get("data").and_then(|d| d.get("rooms")).and_then(|r| r.as_array()) {
                if !arr.is_empty() {
                    seen_any = true;
                    break;
                }
            }
        }
        thread::sleep(Duration::from_millis(500));
    }

    let _ = v2::sliding_sync_stop(ss);
    assert!(seen_any, "expected to see at least one room id via sliding sync within timeout");
    Ok(())
}
