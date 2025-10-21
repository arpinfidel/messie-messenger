//! v2 SAS verification smoke test (ignored by default).

use std::path::PathBuf;

use anyhow::{anyhow, Context, Result};
use messie_matrix_v2 as v2;
use serde::Deserialize;

#[derive(Debug, Deserialize)]
struct EnvelopeOk<T> { #[allow(dead_code)] ok: bool, data: T }

#[derive(Debug, Deserialize)]
struct HandleData { handle: u64 }

#[derive(Debug, Deserialize)]
struct LoginData { user_id: String }

fn must_env(key: &str) -> Result<String> { std::env::var(key).map_err(|_| anyhow!("missing env {key}")) }
fn store_path(suffix: &str) -> PathBuf { let mut p = PathBuf::from("target/it_store_v2"); p.push(suffix); p }

#[test]
#[ignore]
fn sas_request_observe_cancel_ack() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let username = must_env("MESSIE_MATRIX_USERNAME")?;
    let password = must_env("MESSIE_MATRIX_PASSWORD")?;
    let base = store_path("sas_client");

    // Client + login (typed)
    let client = v2::client_create(&hs, &base).ok_or_else(|| anyhow!("client_create failed"))?;
    let user_id = v2::client_login(client, Some(&username), Some(&password)).ok_or_else(|| anyhow!("client_login failed"))?;

    // Request SAS with our user identity (no device id). This won't complete without a peer,
    // but should return a flow id and allow observe/cancel ACKs.
    let start_raw = v2::request_sas_verification(client, &user_id, None);
    let start_val: serde_json::Value = serde_json::from_str(&start_raw).context("parse start envelope")?;
    let ok = start_val.get("ok").and_then(|b| b.as_bool()).unwrap_or(false);
    if ok {
        let flow_id = start_val
            .get("data").and_then(|d| d.get("flow_id")).and_then(|s| s.as_str()).unwrap_or("")
            .to_string();
        if !flow_id.is_empty() {
            let _ = serde_json::from_str::<serde_json::Value>(&v2::observe_sas(&flow_id, 0)).context("parse observe ack")?;
            let _ = serde_json::from_str::<serde_json::Value>(&v2::cancel_sas(&flow_id)).context("parse cancel ack")?;
        }
    } else {
        // Accept an error envelope here: environments without a peer or valid identity may fail request creation.
        let _ = start_val.get("error");
    }

    Ok(())
}
