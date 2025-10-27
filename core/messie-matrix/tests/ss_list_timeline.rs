//! Prove that native Sliding Sync list updates include timeline items with
//! origin_server_ts without per-room subscriptions.
//!
//! Env:
//! - MESSIE_MATRIX_HOMESERVER
//! - MESSIE_MATRIX_USERNAME
//! - MESSIE_MATRIX_PASSWORD

use anyhow::{anyhow, Context, Result};
use rand::{distributions::Alphanumeric, Rng};
use reqwest::Client;
use serde_json::{json, Value};

fn must_env(key: &str) -> Result<String> {
    std::env::var(key).map_err(|_| anyhow!("missing env {key}"))
}

#[tokio::test(flavor = "multi_thread")]
async fn sliding_sync_list_returns_timeline_ts() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let user = must_env("MESSIE_MATRIX_USERNAME")?;
    let pass = must_env("MESSIE_MATRIX_PASSWORD")?;

    let http = Client::builder().build()?;

    // Login to obtain an access token for the bearer header
    let login_url = format!("{}/_matrix/client/v3/login", hs.trim_end_matches('/'));
    let login_body = json!({
        "type": "m.login.password",
        "identifier": {"type": "m.id.user", "user": user},
        "password": pass,
        "initial_device_display_name": "Messie SS List Test"
    });
    let login_resp: Value = http
        .post(login_url)
        .json(&login_body)
        .send()
        .await
        .context("login request failed")?
        .error_for_status()
        .context("login response not 2xx")?
        .json()
        .await
        .context("login decode failed")?;
    let token = login_resp
        .get("access_token")
        .and_then(|v| v.as_str())
        .ok_or_else(|| anyhow!("login response missing access_token"))?;

    // Build one-shot native Sliding Sync payload equivalent to the curl
    let conn_id: String = {
        let s: String = rand::thread_rng()
            .sample_iter(&Alphanumeric)
            .take(10)
            .map(char::from)
            .collect();
        format!("p{}", s)
    };
    let body = json!({
        "conn_id": conn_id,
        "lists": {
            "main": {
                "ranges": [[0, 5]],
                "sort": ["by_recency"],
                "timeline_limit": 1,
                "required_state": [["m.room.name", ""], ["m.room.avatar", ""]]
            }
        },
        "room_subscriptions": {},
        "extensions": {
            "to_device": {"enabled": false},
            "typing": {"enabled": false},
            "e2ee": {"enabled": false},
            "account_data": {"enabled": false},
            "receipts": {"enabled": false}
        }
    });

    let url = format!(
        "{}/_matrix/client/unstable/org.matrix.simplified_msc3575/sync",
        hs.trim_end_matches('/')
    );
    let resp: Value = http
        .post(url)
        .bearer_auth(token)
        .json(&body)
        .send()
        .await
        .context("sliding sync request failed")?
        .error_for_status()
        .context("sliding sync response not 2xx")?
        .json()
        .await
        .context("sliding sync decode failed")?;

    // Normalize rooms with IDs so we can report readable output
    let rooms: Vec<(String, Value)> = if let Some(obj) = resp.get("rooms").and_then(|v| v.as_object()) {
        obj.iter().map(|(k, v)| (k.clone(), v.clone())).collect()
    } else if let Some(arr) = resp.get("rooms").and_then(|v| v.as_array()) {
        arr.iter().map(|v| {
            let rid = v.get("room_id").and_then(|x| x.as_str()).unwrap_or("<unknown>").to_string();
            (rid, v.clone())
        }).collect()
    } else {
        vec![]
    };

    assert!(!rooms.is_empty(), "no rooms in sliding sync response: {}", resp);

    // Extract diagnostic rows
    #[derive(Debug, Clone)]
    struct Row { rid: String, name: String, ts: Option<i64>, reason: &'static str }

    fn extract_name(room: &Value) -> String {
        // Try required_state.name first
        if let Some(rs) = room.get("required_state").and_then(|v| v.as_array()) {
            for item in rs {
                let ty = item.get("type").and_then(|x| x.as_str()).unwrap_or("");
                if ty == "m.room.name" {
                    if let Some(name) = item.get("content").and_then(|c| c.get("name")).and_then(|x| x.as_str()) {
                        return name.to_string();
                    }
                }
            }
        }
        room.get("name").and_then(|x| x.as_str()).unwrap_or("").to_string()
    }

    fn last_timeline_ts(room: &Value) -> (Option<i64>, &'static str) {
        let tl = room.get("timeline");
        if tl.is_none() { return (None, "no_timeline"); }
        if let Some(tlobj) = tl.and_then(|v| v.as_object()) {
            if let Some(evts) = tlobj.get("events").and_then(|x| x.as_array()) {
                if let Some(last) = evts.last() { return (last.get("origin_server_ts").and_then(|v| v.as_i64()), "events_array"); }
                return (None, "events_empty");
            }
            return (None, "timeline_obj_no_events");
        } else if let Some(arr) = tl.and_then(|v| v.as_array()) {
            if let Some(last) = arr.last() { return (last.get("origin_server_ts").and_then(|v| v.as_i64()), "timeline_array"); }
            return (None, "timeline_array_empty");
        }
        (None, "timeline_unknown")
    }

    let mut rows: Vec<Row> = Vec::new();
    let mut reasons: std::collections::HashMap<&'static str, usize> = std::collections::HashMap::new();
    for (rid, room) in rooms.iter() {
        let name = extract_name(room);
        let (ts, why) = last_timeline_ts(room);
        *reasons.entry(why).or_default() += 1;
        rows.push(Row { rid: rid.clone(), name, ts, reason: why });
    }

    let with_ts = rows.iter().filter(|r| r.ts.is_some()).count();
    let without_ts = rows.len() - with_ts;
    println!("[ss-list] rooms={} with_ts={} without_ts={}", rows.len(), with_ts, without_ts);
    for (why, cnt) in reasons.iter() { println!("[ss-list]   reason={} count={}", why, cnt); }

    // Print top 15 by timestamp and a small sample without ts for diagnostics
    let mut with_rows: Vec<_> = rows.iter().filter(|r| r.ts.is_some()).cloned().collect();
    with_rows.sort_by(|a,b| b.ts.unwrap().cmp(&a.ts.unwrap()));
    println!("[ss-list] top with ts:");
    for r in with_rows.iter().take(15) {
        println!("  {} | {} | ts={}", r.rid, r.name, r.ts.unwrap());
    }
    println!("[ss-list] sample without ts:");
    for r in rows.iter().filter(|r| r.ts.is_none()).take(15) {
        println!("  {} | {} | ts=- ({})", r.rid, r.name, r.reason);
    }

    assert!(with_ts > 0, "no origin_server_ts found in sliding sync list timeline");
    Ok(())
}
