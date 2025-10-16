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

#[test]
#[ignore]
fn list_joined_rooms_and_summaries() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let username = must_env("MESSIE_MATRIX_USERNAME")?;
    let password = must_env("MESSIE_MATRIX_PASSWORD")?;
    let base = store_path("summaries_client");

    let new_json = v2::client_new(&hs, &base);
    let handle_env: EnvelopeOk<HandleData> = serde_json::from_str(&new_json).context("parse client_new envelope")?;
    let client = handle_env.data.handle;

    let login_json = v2::client_restore_or_login(client, Some(&username), Some(&password));
    let _: EnvelopeOk<serde_json::Value> = serde_json::from_str(&login_json).context("parse login envelope")?;

    let rooms: Vec<String> = v2::client_list_joined_rooms(client).unwrap_or_default();
    if rooms.is_empty() { return Ok(()); }

    let subset: Vec<String> = rooms.into_iter().take(3).collect();
    let ids_json = serde_json::to_string(&subset).unwrap();
    let summaries_json = v2::client_list_room_summaries(client, &ids_json);
    let env: EnvelopeOk<serde_json::Value> = serde_json::from_str(&summaries_json).context("parse summaries envelope")?;
    assert!(env.ok);
    assert!(env.data.is_array());
    Ok(())
}
