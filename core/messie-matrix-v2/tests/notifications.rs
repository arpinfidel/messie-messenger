//! v2 notifications & highlights tests (ignored by default).
// Compile these tests only when the `test-helpers` feature is enabled.
// Run with: `cargo test -p messie-matrix-v2 --features test-helpers -- --ignored`
#![cfg(feature = "test-helpers")]

use std::path::PathBuf;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use serde::Deserialize;
 

use messie_matrix_v2 as v2;

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct EnvelopeOk<T> { #[allow(dead_code)] ok: bool, data: T }

fn must_env(key: &str) -> Result<String> { std::env::var(key).map_err(|_| anyhow!("missing env {key}")) }
fn store_path(suffix: &str) -> PathBuf { let mut p = PathBuf::from("target/it_store_v2"); p.push(suffix); p }

// These helpers are no longer needed with typed APIs.

fn wait_counts_min(client: u64, room_id: &str, notif_min: u64, highlight_min: u64, timeout: Duration) -> Result<(u64, u64)> {
    let res = v2::__test_wait_counts_min(client, room_id, notif_min, highlight_min, timeout.as_millis() as u64);
    let v: serde_json::Value = serde_json::from_str(&res).context("parse wait_counts_min json")?;
    if v.get("ok").and_then(|b| b.as_bool()).unwrap_or(false) {
        let n = v.get("data").and_then(|d| d.get("notification_count")).and_then(|x| x.as_u64()).unwrap_or(0);
        let h = v.get("data").and_then(|d| d.get("highlight_count")).and_then(|x| x.as_u64()).unwrap_or(0);
        return Ok((n, h));
    }
    Err(anyhow!("wait_counts_min failed: {:?}", v.get("error")))
}

#[test]
#[ignore]
fn v2_group_mention_increments_and_read_decreases() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let recv_user = must_env("MESSIE_MATRIX_USERNAME")?;
    let recv_pass = must_env("MESSIE_MATRIX_PASSWORD")?;
    let group_room = must_env("MESSIE_GROUP_ROOM")?;
    let send_user = must_env("MESSIE_SENDER_USERNAME")?;
    let send_pass = must_env("MESSIE_SENDER_PASSWORD")?;

    // Receiver client + login
    let recv = v2::client_create(&hs, &store_path("v2_notif_recv")).ok_or_else(|| anyhow!("client_create failed"))?;
    let user_id = v2::client_login(recv, Some(&recv_user), Some(&recv_pass)).ok_or_else(|| anyhow!("client_login failed"))?;

    // Receiver Sliding Sync thin + subscribe to target room
    let ss = v2::sliding_sync_create(recv, v2::SlidingSyncConfig { poll_timeout_ms: 0, network_timeout_ms: 0, enable_e2ee: true, enable_to_device: false })
        .ok_or_else(|| anyhow!("failed to create thin sliding sync"))?;
    let _ = v2::sliding_sync_subscribe_to_rooms(ss, &vec![group_room.clone()], Some(20u32), None, true);

    // Sender client + login
    let sender = v2::client_create(&hs, &store_path("v2_notif_sender")).ok_or_else(|| anyhow!("client_create failed"))?;
    let _ = v2::client_login(sender, Some(&send_user), Some(&send_pass));
    // Ensure sender is joined and hydrate its store
    let _ = v2::room_join(sender, &group_room);
    let _ = v2::client_sync_once(sender);

    // Send mention to receiver
    let body = format!("ping {}", user_id);
    assert!(v2::room_send_text(sender, &group_room, &body, None), "send failed");

    // Expect notification and highlight to increase (>0)
    let (_n, _h) = wait_counts_min(recv, &group_room, 1, 1, Duration::from_secs(45))?;

    // Mark read up to latest and expect counts drop
    let _ = v2::room_mark_read_up_to(recv, &group_room, "__LATEST__");
    let (_n2, _h2) = wait_counts_min(recv, &group_room, 0, 0, Duration::from_secs(45))?;

    Ok(())
}

#[test]
#[ignore]
fn v2_dm_notifies_no_highlight_then_read_clears() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let recv_user = must_env("MESSIE_MATRIX_USERNAME")?;
    let recv_pass = must_env("MESSIE_MATRIX_PASSWORD")?;
    let dm_room = must_env("MESSIE_DM_ROOM")?;
    let send_user = must_env("MESSIE_SENDER_USERNAME")?;
    let send_pass = must_env("MESSIE_SENDER_PASSWORD")?;

    let recv = v2::client_create(&hs, &store_path("v2_notif_recv_dm")).ok_or_else(|| anyhow!("client_create failed"))?;
    let _ = v2::client_login(recv, Some(&recv_user), Some(&recv_pass));

    // Receiver SS thin + subscribe
    let ss = v2::sliding_sync_create(recv, v2::SlidingSyncConfig { poll_timeout_ms: 0, network_timeout_ms: 0, enable_e2ee: true, enable_to_device: false })
        .ok_or_else(|| anyhow!("failed to create thin sliding sync"))?;
    let _ = v2::sliding_sync_subscribe_to_rooms(ss, &vec![dm_room.clone()], Some(20u32), None, true);

    // Sender
    let sender = v2::client_create(&hs, &store_path("v2_notif_sender_dm")).ok_or_else(|| anyhow!("client_create failed"))?;
    let _ = v2::client_login(sender, Some(&send_user), Some(&send_pass));
    let _ = v2::room_join(sender, &dm_room);
    let _ = v2::client_sync_once(sender);

    // Send plain DM
    let body = format!("dm {}", std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis());
    assert!(v2::room_send_text(sender, &dm_room, &body, None), "send failed");

    // Expect notification > 0 and highlight == 0
    let (_n, _h) = wait_counts_min(recv, &dm_room, 1, 0, Duration::from_secs(45))?;

    // Mark read clears to zero
    let _ = v2::room_mark_read_up_to(recv, &dm_room, "__LATEST__");
    let (_n2, _h2) = wait_counts_min(recv, &dm_room, 0, 0, Duration::from_secs(45))?;

    Ok(())
}
