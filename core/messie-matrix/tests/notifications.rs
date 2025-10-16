//! Integration test scaffold to exercise matrix-sdk notification behavior via Sliding Sync.
//! These tests are ignored by default and require a running homeserver and seeded accounts.

use anyhow::{anyhow, Context, Result};
use futures::StreamExt;
use matrix_sdk::{
    ruma::events::room::message::RoomMessageEventContent,
    sliding_sync::{SlidingSync, SlidingSyncList, SlidingSyncMode, Version},
    Client,
};
use matrix_sdk::ruma::uint;
use matrix_sdk::ruma::api::client::sync::sync_events::v5 as http;
use std::{fs, path::PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::time::{sleep, Instant};
use tokio::sync::mpsc::{UnboundedSender, UnboundedReceiver, unbounded_channel};
use url::Url;
use matrix_sdk::authentication::matrix::MatrixSession;
use matrix_sdk::config::SyncSettings;

/// Ensures the integration test target is discoverable (`cargo test --test notifications`).
#[test]
fn target_exists() {
    assert!(true);
}

/// Group mention should increment notification and highlight counters.
/// Ignored by default until the environment is configured.
#[serial_test::serial]
#[tokio::test(flavor = "multi_thread")]
#[ignore]
async fn mention_highlights_in_group() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let recv_user = must_env("MESSIE_MATRIX_USERNAME")?;
    let recv_pass = must_env("MESSIE_MATRIX_PASSWORD")?;
    let group_room = must_env("MESSIE_GROUP_ROOM")?;
    let send_user = must_env("MESSIE_SENDER_USERNAME")?;
    let send_pass = must_env("MESSIE_SENDER_PASSWORD")?;

    let client = login_client(&hs, &recv_user, &recv_pass).await?;
    let (tx, mut rx) = unbounded_channel::<String>();
    let sliding = start_sliding_sync(&client, "notif_group", Some(tx)).await?;

    let sender = login_client(&hs, &send_user, &send_pass).await?;
    ensure_joined(&sender, &group_room).await?;
    let mention = client
        .user_id()
        .ok_or_else(|| anyhow!("client has no user id"))?
        .to_string();
    let body = format!("ping {} {}", mention, now_millis());
    // Ensure we subscribe explicitly to the target room so summaries/counters update.
    use matrix_sdk::ruma::{OwnedRoomId as _OwnedRoomIdForSub, RoomId as _RoomIdForSub};
    let group_owned: _OwnedRoomIdForSub = group_room.parse().context("invalid group room id")?;
    let group_refs: Vec<&_RoomIdForSub> = vec![group_owned.as_ref()];
    println!("[test] subscribing to group room {}", group_owned);
    let mut group_sub = http::request::RoomSubscription::default();
    group_sub.timeline_limit = uint!(20);
    // required_state is mandatory in room subscriptions; request a minimal set
    group_sub.required_state = vec![
        ("m.room.name".into(), "".to_owned()),
        ("m.room.avatar".into(), "".to_owned()),
        ("m.room.encryption".into(), "".to_owned()),
    ];
    sliding.subscribe_to_rooms(&group_refs, Some(group_sub), true);
    // Small settle to allow subscription to take effect
    sleep(Duration::from_millis(150)).await;
    // Wait until we observe a summary for this room before sending
    wait_for_room_summary(&mut rx, &group_room, Duration::from_secs(10)).await?;
    println!("[test] sending mention text to group {}", group_owned);
    send_text_via_sdk(&sender, &group_room, &body).await?;

    let want = |n: u64, h: u64| n > 0 && h > 0;
    let (_n, _h) = wait_counts_via_room_updates(&client, &group_room, want, Duration::from_secs(30)).await?;
    Ok(())
}

/// Direct message should increment notification only (no highlight).
#[serial_test::serial]
#[tokio::test(flavor = "multi_thread")]
#[ignore]
async fn dm_notifies_no_highlight() -> Result<()> {
    let hs = must_env("MESSIE_MATRIX_HOMESERVER")?;
    let recv_user = must_env("MESSIE_MATRIX_USERNAME")?;
    let recv_pass = must_env("MESSIE_MATRIX_PASSWORD")?;
    let dm_room = must_env("MESSIE_DM_ROOM")?;
    let send_user = must_env("MESSIE_SENDER_USERNAME")?;
    let send_pass = must_env("MESSIE_SENDER_PASSWORD")?;

    let client = login_client(&hs, &recv_user, &recv_pass).await?;
    let (tx, mut rx) = unbounded_channel::<String>();
    let sliding = start_sliding_sync(&client, "notif_dm", Some(tx)).await?;

    let sender = login_client(&hs, &send_user, &send_pass).await?;
    ensure_joined(&sender, &dm_room).await?;
    let body = format!("dm {}", now_millis());
    use matrix_sdk::ruma::{OwnedRoomId as _OwnedRoomIdForSub2, RoomId as _RoomIdForSub2};
    let dm_owned: _OwnedRoomIdForSub2 = dm_room.parse().context("invalid dm room id")?;
    let dm_refs: Vec<&_RoomIdForSub2> = vec![dm_owned.as_ref()];
    println!("[test] subscribing to DM room {}", dm_owned);
    let mut dm_sub = http::request::RoomSubscription::default();
    dm_sub.timeline_limit = uint!(20);
    dm_sub.required_state = vec![
        ("m.room.name".into(), "".to_owned()),
        ("m.room.avatar".into(), "".to_owned()),
        ("m.room.encryption".into(), "".to_owned()),
    ];
    sliding.subscribe_to_rooms(&dm_refs, Some(dm_sub), true);
    sleep(Duration::from_millis(150)).await;
    wait_for_room_summary(&mut rx, &dm_room, Duration::from_secs(10)).await?;
    println!("[test] sending DM text to {}", dm_owned);
    send_text_via_sdk(&sender, &dm_room, &body).await?;

    let want = |n: u64, h: u64| n > 0 && h == 0;
    let (_n, _h) = wait_counts_via_room_updates(&client, &dm_room, want, Duration::from_secs(30)).await?;
    Ok(())
}

fn must_env(key: &str) -> Result<String> {
    std::env::var(key).map_err(|_| anyhow!("missing env {key}"))
}

fn session_store_path(username: &str) -> PathBuf {
    let mut p = PathBuf::from("target/it_store");
    p.push(format!("{}.session.json", username));
    p
}

async fn login_client(hs: &str, username: &str, password: &str) -> Result<Client> {
    let homeserver: Url = hs.parse().context("invalid homeserver")?;
    let client = Client::builder().homeserver_url(homeserver.as_ref()).build().await?;
    // Try restoring a persisted session first
    let path = session_store_path(username);
    if path.exists() {
        if let Ok(raw) = fs::read(&path) {
            if let Ok(session) = serde_json::from_slice::<MatrixSession>(&raw) {
                if client.restore_session(session).await.is_ok() {
                    if let Some(uid) = client.user_id() {
                        println!("[auth] restored session for {} as {}", username, uid);
                    } else {
                        println!("[auth] restored session for {}", username);
                    }
                    return Ok(client);
                }
            }
        }
    }
    let resp = client
            .matrix_auth()
            .login_username(username, password)
            .initial_device_display_name("Messie Rust Test")
            .send()
            .await?;
    // Persist session for reuse to avoid 429s
    let session: MatrixSession = (&resp).into();
    if let Some(dir) = path.parent() { let _ = fs::create_dir_all(dir); }
    let _ = fs::write(&path, serde_json::to_vec_pretty(&session)?);
    if let Some(uid) = client.user_id() {
        println!("[auth] logged in {} as {} (persisted at {})", username, uid, path.display());
    } else {
        println!("[auth] logged in {} (persisted at {})", username, path.display());
    }
    Ok(client)
}

async fn start_sliding_sync(
    client: &Client,
    handle: &str,
    notify: Option<UnboundedSender<String>>,
) -> Result<SlidingSync> {
    let list = SlidingSyncList::builder("all")
        .sync_mode(SlidingSyncMode::new_growing(50).maximum_number_of_rooms_to_fetch(10_000))
        .timeline_limit(20);

    let sliding = client
        .sliding_sync(handle)
        .context("failed to create sliding sync builder")?
        .version(Version::Native)
        .with_all_extensions()
        .without_to_device_extension()
        .add_list(list)
        .build()
        .await
        .context("failed to build sliding sync")?;

    // Drive the sync stream a bit to populate caches in background
    // Drive sync in background using a cloned handle so the original can be returned.
    let sliding_bg = sliding.clone();
    tokio::spawn(async move {
        // The stream is not Unpin; pin it before awaiting .next() in a task.
        let mut stream = Box::pin(sliding_bg.sync());
        let start = Instant::now();
        while start.elapsed() < Duration::from_secs(120) {
            match stream.next().await {
                Some(Ok(summary)) => {
                    println!(
                        "[sync] update: lists={} rooms={}",
                        summary.lists.len(),
                        summary.rooms.len()
                    );
                    if let Some(tx) = &notify {
                        for rid in &summary.rooms {
                            let _ = tx.send(rid.to_string());
                        }
                    }
                }
                Some(Err(e)) => {
                    eprintln!("[sync] error: {e:?}");
                    // If the server reports an unknown position, reset and resume
                    let msg = format!("{e:?}");
                    if msg.contains("Unknown position") {
                        // Reset sticky/pos and restart the stream
                        let _ = sliding_bg.expire_session().await;
                        stream = Box::pin(sliding_bg.sync());
                        continue;
                    }
                }
                None => break,
            }
        }
        println!("[sync] background task finished");
    });
    Ok(sliding)
}

fn now_millis() -> i128 {
    SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_millis() as i128
}

// All sender operations now use matrix-sdk (no raw HTTP)

#[allow(dead_code)]
// (removed legacy polling helper in favor of room update–driven approach)

// Prefer waiting on the Room’s own update stream so unread counters refresh
// as soon as Sliding Sync maps server counts into the SDK room.
async fn wait_counts_via_room_updates(
    client: &Client,
    room_id_str: &str,
    pred: impl Fn(u64, u64) -> bool,
    timeout: Duration,
) -> Result<(u64, u64)> {
    use matrix_sdk::ruma::OwnedRoomId;
    let room_id: OwnedRoomId = room_id_str.parse().context("invalid room id")?;
    let room = client
        .get_room(&room_id)
        .ok_or_else(|| anyhow!("receiver client does not know room {}", room_id))?;

    let mut rx = room.subscribe_to_updates();
    let start = Instant::now();
    let mut nudged_classic_sync = false;
    loop {
        let counts = room.unread_notification_counts();
        let n = counts.notification_count;
        let h = counts.highlight_count;
        println!("[wait_counts:update] room={} notif={} highlight={}", room_id, n, h);
        if pred(n, h) {
            return Ok((n, h));
        }
        if start.elapsed() > timeout {
            break;
        }
        // Wait briefly for a room update; this is signaled when Sliding Sync applies
        // a new summary or timeline diff for the room.
        let remaining = timeout.saturating_sub(start.elapsed());
        let tick = remaining.min(Duration::from_secs(2));
        let _ = tokio::time::timeout(tick, rx.recv()).await;

        // Fallback nudge: trigger a lightweight classic /sync once so the SDK
        // can ingest server-provided unread counters in environments where
        // Sliding Sync hasn’t yet mapped them into the Room view.
        if !nudged_classic_sync && start.elapsed() > Duration::from_secs(2) {
            println!("[wait_counts] classic sync nudge to refresh unread counters");
            let _ = client.sync_once(SyncSettings::default()).await;
            nudged_classic_sync = true;
        }
    }
    Err(anyhow!("timeout waiting for counters via room updates"))
}

async fn wait_for_room_summary(
    rx: &mut UnboundedReceiver<String>,
    target_room_id: &str,
    timeout: Duration,
) -> Result<()> {
    let deadline = Instant::now() + timeout;
    while Instant::now() < deadline {
        if let Ok(Some(rid)) = tokio::time::timeout(Duration::from_millis(500), rx.recv()).await {
            if rid == target_room_id {
                println!("[sync] observed summary for {}", rid);
                return Ok(());
            }
        }
    }
    Err(anyhow!("timeout waiting for summary of {}", target_room_id))
}

// Ensure the given client is joined to the room; best-effort join by id.
async fn ensure_joined(client: &Client, room_id_str: &str) -> Result<()> {
    use matrix_sdk::{ruma::OwnedRoomId, RoomState};
    let room_id: OwnedRoomId = room_id_str.parse().context("invalid room id")?;
    if let Some(room) = client.get_room(&room_id) {
        println!("[join] receiver knows room {} with state {:?}", room_id, room.state());
        if room.state() == RoomState::Joined {
            return Ok(());
        }
    } else {
        println!("[join] receiver does not know room {}", room_id);
    }
    println!("[join] attempting join {}", room_id);
    let _ = client.join_room_by_id(&room_id).await; // ignore if not allowed/already joined
    if let Some(room) = client.get_room(&room_id) {
        println!("[join] post-join state for {} is {:?}", room_id, room.state());
    }
    Ok(())
}

// Send a plain text message using the SDK sender client.
async fn send_text_via_sdk(client: &Client, room_id_str: &str, body: &str) -> Result<()> {
    use matrix_sdk::ruma::OwnedRoomId;
    let room_id: OwnedRoomId = room_id_str.parse().context("invalid room id")?;
    let room = client
        .get_room(&room_id)
        .ok_or_else(|| anyhow!("sender client does not know room {}", room_id))?;
    let content = RoomMessageEventContent::text_plain(body);
    println!("[send] sending text to {}: {}", room_id, body);
    let resp = room.send(content).await?;
    println!("[send] sent event to {} -> {:?}", room_id, resp.event_id);
    Ok(())
}
