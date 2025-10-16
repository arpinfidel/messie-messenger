//! v2 Timeline minimal flow; ignored by default.

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
struct JoinedRooms { rooms: Vec<String> }

#[derive(Debug, Deserialize)]
#[allow(dead_code)]
struct LoadBackward { reached_start: bool, events: Vec<String> }

fn must_env(key: &str) -> Result<String> { std::env::var(key).map_err(|_| anyhow!("missing env {key}")) }
fn store_path(suffix: &str) -> PathBuf { let mut p = PathBuf::from("target/it_store_v2"); p.push(suffix); p }

#[test]
#[ignore]
fn timeline_open_send_read_and_backward() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let username = must_env("MESSIE_MATRIX_USERNAME")?;
    let password = must_env("MESSIE_MATRIX_PASSWORD")?;
    let base = store_path("timeline_client");

    // Client + login
    let new_json = v2::client_new(&hs, &base);
    let new_env: EnvelopeOk<HandleData> = serde_json::from_str(&new_json).context("parse client_new")?;
    let client = new_env.data.handle;
    let _ = v2::client_restore_or_login(client, Some(&username), Some(&password));

    // Pick a room if present
    let rooms_opt = v2::client_list_joined_rooms(client).unwrap_or_default();
    if rooms_opt.is_empty() {
        // No rooms on this account; nothing to test here.
        return Ok(());
    }
    let room_id = rooms_opt[0].clone();

    // Open timeline (typed) and start headless stream
    let tl = v2::timeline_open(client, &room_id).ok_or_else(|| anyhow!("timeline_open failed"))?;
    assert!(v2::timeline_start_streaming(tl, 0));

    // Load a small backward page (typed)
    assert!(v2::timeline_load_backward(tl, 5));
    // Events may be empty on fresh rooms; do not assert count > 0

    // Send a text message to the room and set read up to latest (typed)
    assert!(v2::room_send_text(client, &room_id, "hello from test", None));
    let _ = v2::client_sync_once(client);
    assert!(v2::room_mark_read_up_to(client, &room_id, "__LATEST__"));

    Ok(())
}
