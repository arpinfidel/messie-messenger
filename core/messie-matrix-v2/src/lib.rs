//! Messie Matrix v2 — separate crate with its own runtime and API.

mod common;
mod client;
mod sync;
mod rooms;

use std::collections::HashSet;
use std::sync::{Arc, RwLock};

use anyhow::{anyhow, Context, Result};
use matrix_sdk::{
    config::SyncSettings,
    room::{Messages, MessagesOptions, Room as MatrixRoom},
    Client,
    RoomState, RoomDisplayName,
};
use matrix_sdk::ruma::{OwnedEventId, OwnedRoomId, UInt};
use matrix_sdk::encryption::verification::{SasVerification, VerificationRequest, SasState as SdkSasState};
use matrix_sdk::ruma::OwnedUserId;
use matrix_sdk::LoopCtrl;
use once_cell::sync::Lazy;
use serde::{Serialize};
use tokio::time::{self, Duration, MissedTickBehavior};
use allo_isolate::Isolate;
use futures::StreamExt;
use tokio::sync::{Mutex as AsyncMutex, RwLock as AsyncRwLock};

// ---------- Runtime (private to v2) ----------
use common::runtime::runtime;

// ---------- Envelope helpers ----------
use common::envelope::{ack_json, err_json, ok_json};

// ---------- Handle registry ----------

use common::handle_registry::{Handle, Registry};
use client::CLIENTS;
use crate::common::post_to_port;

// ---------- Sliding Sync registries ----------

// ---------- Timeline registries ----------

struct TimelineController {
    room: MatrixRoom,
    listeners: AsyncMutex<HashSet<i64>>, // Dart ports
    backward_token: AsyncMutex<Option<String>>,
}

static TL_CONTROLLERS: Lazy<RwLock<Registry<Arc<TimelineController>>>> = Lazy::new(|| RwLock::new(Registry::default()));

// ---------- Public v2 API ----------

pub use client::management::{
    client_new,
    client_restore_or_login,
    client_logout,
    // Tests-only helper to drive hydration via classic sync once.
    client_sync_once,
};

// ---------- Sliding Sync ----------
pub use crate::sync::sliding_sync::{
    SlidingSyncConfig,
    sliding_sync_create,
    sliding_sync_start_streaming,
    sliding_sync_stop,
    sliding_sync_subscribe_to_rooms,
    sliding_sync_expire_session,
};

// ---------- Client + Rooms ----------
pub use crate::client::management::{
    client_create,
    client_login,
};

pub use crate::rooms::{
    RoomSummary,
    room_get_summary,
};

// ---------- Test helpers (feature = "test-helpers") ----------
#[cfg(feature = "test-helpers")]
pub use crate::sync::sliding_sync::{__test_ss_known_rooms, __test_ss_update_count};

#[cfg(feature = "test-helpers")]
#[derive(Debug, Serialize)]
struct TestCounts { notification_count: u64, highlight_count: u64 }

#[cfg(feature = "test-helpers")]
pub fn __test_wait_counts_min(client: Handle, room_id: &str, notif_min: u64, highlight_min: u64, timeout_ms: u64) -> String {
    let entry = { let reg = CLIENTS.read().expect("clients lock"); reg.get(client).cloned() };
    let entry = match entry { Some(e) => e, None => return err_json("unknown_handle", "unknown client handle") };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let rid = room_id.to_string();
    let fut = async move {
        use tokio::time::{timeout, Duration};
        let room_id: OwnedRoomId = rid.parse().map_err(|_| anyhow!("invalid room id"))?;
        let mut room_opt = client.get_room(&room_id);
        if room_opt.is_none() {
            // Best-effort join and hydrate so tests and first-run sends succeed.
            let _ = client.join_room_by_id(&room_id).await;
            let _ = client.sync_once(SyncSettings::default()).await;
            room_opt = client.get_room(&room_id);
        }
        let Some(room) = room_opt else { return Err(anyhow!("room not found")); };
        let mut rx = room.subscribe_to_updates();
        let deadline = std::time::Instant::now() + std::time::Duration::from_millis(timeout_ms);
        let mut nudged = false;
        loop {
            let counts = room.unread_notification_counts();
            if counts.notification_count >= notif_min && counts.highlight_count >= highlight_min {
                return Ok::<TestCounts, anyhow::Error>(TestCounts { notification_count: counts.notification_count, highlight_count: counts.highlight_count });
            }
            if std::time::Instant::now() >= deadline { break; }
            let remain = deadline.saturating_duration_since(std::time::Instant::now());
            let tick = std::cmp::min(remain, std::time::Duration::from_millis(1500));
            let _ = timeout(Duration::from_millis(tick.as_millis() as u64), rx.recv()).await;
            if !nudged && std::time::Instant::now() + std::time::Duration::from_secs(0) > deadline - std::time::Duration::from_secs(28) {
                let _ = room.client().sync_once(SyncSettings::default()).await;
                nudged = true;
            }
        }
        Err(anyhow!("timeout waiting for counts to reach minimum"))
    };
    match runtime.block_on(fut) { Ok(c) => ok_json(c), Err(e) => err_json("timeout", format!("{e:#}")) }
}

// ---------- Timeline ----------

#[derive(Debug, Serialize)]
struct TimelineSnapshotDto { kind: &'static str, events: Vec<String> }

#[derive(Debug, Serialize)]
struct TimelineAppendDto { kind: &'static str, events: Vec<String> }

// Thin (typed) Timeline API
pub fn timeline_open(handle: Handle, room_id: &str) -> Option<Handle> {
    let entry = { let reg = CLIENTS.read().ok()?; reg.get(handle).cloned()? };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let rid_str = room_id.to_string();
    let fut = async move {
        let room_id: OwnedRoomId = rid_str.parse().map_err(|_| anyhow!("invalid room id"))?;
        let Some(room) = client.get_room(&room_id) else { return Err(anyhow!("room not found")); };
        let ctrl = Arc::new(TimelineController { room, listeners: AsyncMutex::new(HashSet::new()), backward_token: AsyncMutex::new(None) });
        Ok::<Arc<TimelineController>, anyhow::Error>(ctrl)
    };
    match runtime.block_on(fut) {
        Ok(ctrl) => {
            let handle = TL_CONTROLLERS.write().ok()?.insert(ctrl);
            Some(handle)
        }
        Err(_) => None,
    }
}

pub fn timeline_start_streaming(tl: Handle, port: i64) -> bool {
    let ctrl = { let reg = TL_CONTROLLERS.read().ok(); reg.and_then(|r| r.get(tl).cloned()) };
    let Some(ctrl) = ctrl else { return false; };
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move {
        ctrl.listeners.lock().await.insert(port);
        let events = collect_latest(&ctrl, 30, true).await?;
        let payload = serde_json::to_string(&TimelineSnapshotDto { kind: "timeline_snapshot", events })?;
        if !post_to_port(port, payload) { ctrl.listeners.lock().await.remove(&port); }
        spawn_timeline_background(ctrl.clone());
        Ok::<(), anyhow::Error>(())
    };
    runtime.block_on(fut).is_ok()
}

pub fn timeline_load_backward(tl: Handle, limit: u32) -> bool {
    let ctrl = { let reg = TL_CONTROLLERS.read().ok(); reg.and_then(|r| r.get(tl).cloned()) };
    let Some(ctrl) = ctrl else { return false; };
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move {
        let token = { ctrl.backward_token.lock().await.clone() };
        let mut options = MessagesOptions::backward();
        if let Some(t) = token.as_deref() { options = options.from(t); }
        options.limit = UInt::from(limit);
        let resp = ctrl.room.messages(options).await?;
        { *ctrl.backward_token.lock().await = resp.end.clone(); }
        let mut events = extract_events(&resp)?;
        maybe_decrypt_events(&ctrl, &mut events).await;
        // Push as a prepend event to current listeners
        let payload = serde_json::to_string(&TimelineAppendDto { kind: "timeline_prepend", events }).unwrap_or_else(|_| "{}".to_string());
        let mut listeners = ctrl.listeners.lock().await;
        let mut stale = Vec::new();
        for &p in listeners.iter() { if !post_to_port(p, payload.clone()) { stale.push(p); } }
        for p in stale { listeners.remove(&p); }
        Ok::<(), anyhow::Error>(())
    };
    runtime.block_on(fut).is_ok()
}

fn spawn_timeline_background(ctrl: Arc<TimelineController>) {
    tokio::spawn(async move {
        let mut interval = time::interval(Duration::from_secs(2));
        interval.set_missed_tick_behavior(MissedTickBehavior::Delay);
        let mut seen = std::collections::HashSet::<String>::new();
        loop {
            interval.tick().await;
            match collect_latest(&ctrl, 30, false).await {
                Ok(events) => {
                    let mut new = Vec::new();
                    for ev in events {
                        if seen.insert(ev.clone()) { new.push(ev); }
                    }
                    if !new.is_empty() {
                        let payload = serde_json::to_string(&TimelineAppendDto { kind: "timeline_append", events: new }).unwrap_or_else(|_| "{}".to_string());
                        let mut listeners = ctrl.listeners.lock().await;
                        let mut stale = Vec::new();
                        for &port in listeners.iter() { if !post_to_port(port, payload.clone()) { stale.push(port); } }
                        for p in stale { listeners.remove(&p); }
                    }
                }
                Err(_) => {}
            }
        }
    });
}

async fn collect_latest(ctrl: &Arc<TimelineController>, limit: u32, update_backward: bool) -> Result<Vec<String>> {
    let mut options = MessagesOptions::backward();
    options.limit = UInt::from(limit);
    let resp = ctrl.room.messages(options).await.context("failed to load recent messages")?;
    if update_backward { *ctrl.backward_token.lock().await = resp.end.clone(); }
    let mut events = extract_events(&resp)?;
    maybe_decrypt_events(ctrl, &mut events).await;
    Ok(events)
}

fn extract_events(messages: &Messages) -> Result<Vec<String>> {
    let mut out = Vec::new();
    for ev in messages.chunk.iter() {
        let raw = serde_json::to_string(ev.raw()).context("failed to serialise timeline event")?;
        out.push(raw);
    }
    out.reverse();
    Ok(out)
}

async fn maybe_decrypt_events(ctrl: &Arc<TimelineController>, events: &mut [String]) {
    use matrix_sdk::ruma::events::room::encrypted::{OriginalRoomEncryptedEvent, OriginalSyncRoomEncryptedEvent};
    use matrix_sdk::ruma::serde::Raw;
    for raw in events.iter_mut() {
        if !raw.contains("\"m.room.encrypted\"") { continue; }
        let Ok(parsed) = Raw::<OriginalRoomEncryptedEvent>::from_json_string(raw.clone()) else { continue; };
        let sync_ev = parsed.cast::<OriginalSyncRoomEncryptedEvent>();
        if let Ok(decrypted) = ctrl.room.decrypt_event(&sync_ev, None).await {
            if let Ok(serialized) = serde_json::to_string(decrypted.raw()) { *raw = serialized; }
        }
    }
}

// ---------- Messaging / Read state ----------

fn room_subscribe_to_updates_inner(handle: Handle, room_id: &str, port: i64) -> Result<()> {
    let entry = { let reg = CLIENTS.read().expect("clients lock"); reg.get(handle).cloned().ok_or_else(|| anyhow!("unknown client handle"))? };
    let runtime = runtime();
    let _guard = runtime.enter();

    let room_id: OwnedRoomId = room_id.parse().map_err(|_| anyhow!("invalid room id"))?;
    let room = entry.client.get_room(&room_id).ok_or_else(|| anyhow!("room not found"))?;

    let mut updates_receiver = room.subscribe_to_updates();

    // Spawn task to listen for room updates and forward notification changes (like working Rust test)
    runtime.spawn(async move {
        loop {
            match updates_receiver.recv().await {
                Ok(_update) => {
                    // For any room update, send current notification counts (like Rust test does)
                    let counts = room.unread_notification_counts();
                    let update_dto = serde_json::json!({
                        "kind": "room_update",
                        "room_id": room_id.to_string(),
                        "notification_count": counts.notification_count,
                        "highlight_count": counts.highlight_count
                    });
                    let json = serde_json::to_string(&update_dto).unwrap_or_else(|_| "{}".to_string());
                    if !Isolate::new(port).post(json) {
                        break; // Port closed, stop listening
                    }
                }
                Err(_) => break, // Channel closed
            }
        }
    });

    Ok(())
}

#[derive(Debug, Clone, Serialize)]
struct NotificationCounts {
    notification_count: u64,
    highlight_count: u64,
}

fn room_unread_notification_counts_inner(handle: Handle, room_id: &str) -> Result<NotificationCounts> {
    let entry = { let reg = CLIENTS.read().expect("clients lock"); reg.get(handle).cloned().ok_or_else(|| anyhow!("unknown client handle"))? };

    let room_id: OwnedRoomId = room_id.parse().map_err(|_| anyhow!("invalid room id"))?;
    let room = entry.client.get_room(&room_id).ok_or_else(|| anyhow!("room not found"))?;

    let counts = room.unread_notification_counts();
    Ok(NotificationCounts {
        notification_count: counts.notification_count,
        highlight_count: counts.highlight_count,
    })
}

// Thin (typed) unread counts
pub fn room_get_unread_counts(handle: Handle, room_id: &str) -> Option<(u64, u64)> {
    match room_unread_notification_counts_inner(handle, room_id) {
        Ok(c) => Some((c.notification_count, c.highlight_count)),
        Err(_) => None,
    }
}

#[cfg(feature = "test-helpers")]
pub fn room_join(handle: Handle, room_id: &str) -> String {
    match room_join_inner(handle, room_id) { Ok(()) => ack_json(), Err(e) => err_json("sdk_error", format!("{:#}", e)) }
}

#[cfg(feature = "test-helpers")]
fn room_join_inner(handle: Handle, room_id: &str) -> Result<()> {
    let entry = { let reg = CLIENTS.read().expect("clients lock"); reg.get(handle).cloned().ok_or_else(|| anyhow!("unknown client handle"))? };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let rid = room_id.to_string();
    let fut = async move {
        let room_id: OwnedRoomId = rid.parse().map_err(|_| anyhow!("invalid room id"))?;
        client.join_room_by_id(&room_id).await.map_err(|e| anyhow!(format!("join failed: {e:?}")))?;
        Ok(())
    };
    runtime.block_on(fut)
}

// (no other public test helpers; join via normal app flows)

pub fn room_send_text(handle: Handle, room_id: &str, body: &str, reply_to: Option<&str>) -> bool {
    let entry = { let reg = CLIENTS.read().ok(); reg.and_then(|r| r.get(handle).cloned()) };
    let Some(entry) = entry else { return false; };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let rid = room_id.to_string();
    let body = body.to_string();
    let reply = reply_to.map(|s| s.to_string());
    let fut = async move {
        use matrix_sdk::ruma::events::{relation::InReplyTo, room::message::{Relation, RoomMessageEventContent}};
        let room_id: OwnedRoomId = rid.parse().map_err(|_| anyhow!("invalid room id"))?;
        let Some(room) = client.get_room(&room_id) else { return Err(anyhow!("room not found")); };
        let mut content = RoomMessageEventContent::text_plain(body);
        if let Some(evt) = reply.as_deref() {
            let eid = OwnedEventId::try_from(evt).map_err(|_| anyhow!("invalid event id for reply"))?;
            let in_reply_to = InReplyTo::new(eid);
            content.relates_to = Some(Relation::Reply { in_reply_to });
        }
        room.send(content).await.map_err(|e| anyhow!(format!("send failed: {e:?}")))?;
        Ok::<(), anyhow::Error>(())
    };
    runtime.block_on(fut).is_ok()
}

pub fn room_mark_read_up_to(handle: Handle, room_id: &str, event_id: &str) -> bool {
    let entry = { let reg = CLIENTS.read().ok(); reg.and_then(|r| r.get(handle).cloned()) };
    let Some(entry) = entry else { return false; };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let rid = room_id.to_string();
    let eid_str = event_id.to_string();
    let fut = async move {
        use matrix_sdk::ruma::{api::client::receipt::create_receipt::v3::ReceiptType, events::receipt::ReceiptThread};
        let room_id: OwnedRoomId = rid.parse().map_err(|_| anyhow!("invalid room id"))?;
        let Some(room) = client.get_room(&room_id) else { return Err(anyhow!("room not found")); };
        let target_eid: OwnedEventId = if eid_str == "__LATEST__" {
            let mut opts = MessagesOptions::backward();
            opts.limit = UInt::from(1u32);
            let resp = room.messages(opts).await.map_err(|e| anyhow!(format!("failed to fetch latest message: {e:?}")))?;
            resp.chunk.first().and_then(|ev| ev.event_id()).ok_or_else(|| anyhow!("no events in room to mark read"))?
        } else {
            OwnedEventId::try_from(eid_str.as_str()).map_err(|_| anyhow!("invalid event id"))?
        };
        room.send_single_receipt(ReceiptType::Read, ReceiptThread::Unthreaded, target_eid.clone()).await.map_err(|e| anyhow!(format!("failed to send read receipt: {e:?}")))?;
        let _ = room.client().sync_once(SyncSettings::default()).await;
        let mut req = matrix_sdk::ruma::api::client::read_marker::set_read_marker::v3::Request::new(room_id.clone());
        req.fully_read = Some(target_eid.clone());
        req.read_receipt = Some(target_eid);
        req.private_read_receipt = None;
        room.client().send(req).await.map_err(|e| anyhow!(format!("failed to set read markers: {e:?}")))?;
        Ok::<(), anyhow::Error>(())
    };
    runtime.block_on(fut).is_ok()
}

pub fn room_subscribe_to_count_changes(handle: Handle, room_id: &str, port: i64) -> bool {
    room_subscribe_to_updates_inner(handle, room_id, port).is_ok()
}

// (no public test helpers; tests should observe SDK-driven updates)

// ---------- Rooms / Summaries (v2) ----------

#[derive(Debug, Clone, Serialize)]
pub struct RoomSummaryDto {
    pub room_id: String,
    pub name: String,
    pub avatar_url: Option<String>,
    pub bump_ts: Option<u64>,
    pub notification_count: u64,
    pub highlight_count: u64,
    pub is_marked_unread: bool,
}

#[derive(Debug, Clone, Serialize)]
struct JoinedRooms { rooms: Vec<String> }

pub fn client_list_joined_rooms_json(handle: Handle) -> String {
    let entry = { let reg = CLIENTS.read().expect("clients lock"); reg.get(handle).cloned() };
    let entry = match entry { Some(e) => e, None => return err_json("unknown_handle", "unknown client handle") };
    let mut unique = std::collections::HashSet::new();
    for room in entry.client.rooms() {
        if matches!(room.state(), RoomState::Joined) {
            unique.insert(room.room_id().to_string());
        }
    }
    let mut rooms: Vec<String> = unique.into_iter().collect();
    rooms.sort();
    ok_json(JoinedRooms { rooms })
}

// Thin (typed) list of joined rooms
pub fn client_list_joined_rooms(handle: Handle) -> Option<Vec<String>> {
    let entry = { let reg = CLIENTS.read().ok()?; reg.get(handle).cloned()? };
    let mut unique = std::collections::HashSet::new();
    for room in entry.client.rooms() {
        if matches!(room.state(), RoomState::Joined) {
            unique.insert(room.room_id().to_string());
        }
    }
    let mut rooms: Vec<String> = unique.into_iter().collect();
    rooms.sort();
    Some(rooms)
}

pub fn client_list_room_summaries(handle: Handle, room_ids_json: &str) -> String {
    let entry = { let reg = CLIENTS.read().expect("clients lock"); reg.get(handle).cloned() };
    let entry = match entry { Some(e) => e, None => return err_json("unknown_handle", "unknown client handle") };
    let ids: Vec<String> = match serde_json::from_str(room_ids_json) {
        Ok(v) => v,
        Err(e) => return err_json("invalid_arg", format!("room_ids_json: {e}")),
    };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let fut = async move {
        let mut out: Vec<RoomSummaryDto> = Vec::with_capacity(ids.len());
        for id_str in ids {
            let rs = build_room_summary_for_id(&client, &id_str).await.unwrap_or_else(|| RoomSummaryDto {
                room_id: id_str.clone(),
                name: id_str.clone(),
                avatar_url: None,
                bump_ts: None,
                notification_count: 0,
                highlight_count: 0,
                is_marked_unread: false,
            });
            out.push(rs);
        }
        out
    };
    let summaries = runtime.block_on(fut);
    ok_json(summaries)
}

pub fn room_overview(handle: Handle, room_id: &str) -> String {
    let entry = { let reg = CLIENTS.read().expect("clients lock"); reg.get(handle).cloned() };
    let entry = match entry { Some(e) => e, None => return err_json("unknown_handle", "unknown client handle") };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let id = room_id.to_string();
    let id_for_future = id.clone();
    let fut = async move { build_room_summary_for_id(&client, &id_for_future).await };
    match runtime.block_on(fut) {
        Some(summary) => ok_json(summary),
        None => ok_json(RoomSummaryDto {
            room_id: id.clone(),
            name: id.clone(),
            avatar_url: None,
            bump_ts: None,
            notification_count: 0,
            highlight_count: 0,
            is_marked_unread: false,
        }),
    }
}

pub(crate) async fn build_room_summary_for_id(client: &Client, room_id_str: &str) -> Option<RoomSummaryDto> {
    let room_id: OwnedRoomId = room_id_str.parse().ok()?;
    let room = client.get_room(&room_id)?;
    let display_name = match room.display_name().await {
        Ok(RoomDisplayName::Named(name))
        | Ok(RoomDisplayName::Calculated(name))
        | Ok(RoomDisplayName::Aliased(name))
        | Ok(RoomDisplayName::EmptyWas(name)) => name,
        Ok(RoomDisplayName::Empty) => room_id.as_str().to_owned(),
        Err(_) => room_id.as_str().to_owned(),
    };
    let avatar_url = room.avatar_url().map(|u| u.to_string());
    let bump_ts = room.recency_stamp();
    let counts = room.unread_notification_counts();
    let is_marked_unread = room.is_marked_unread();
    Some(RoomSummaryDto {
        room_id: room_id.as_str().to_owned(),
        name: display_name,
        avatar_url,
        bump_ts,
        notification_count: counts.notification_count,
        highlight_count: counts.highlight_count,
        is_marked_unread,
    })
}

// ---------- Backup / SSSS (v2 – carried forward) ----------

#[derive(Debug, Clone, Serialize)]
pub struct BackupStatusDto {
    pub enabled: bool,
    pub exists_on_server: bool,
    pub recovery_state: String,
    pub needs_recovery: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct EnableBackupDto {
    pub enabled: bool,
    pub exists_on_server: bool,
    pub generated_recovery_key: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct SsssBootstrapDto {
    pub generated_recovery_key: Option<String>,
}

pub fn backup_status_json(handle: Handle) -> String {
    let entry = { let reg = CLIENTS.read().expect("clients lock"); reg.get(handle).cloned() };
    let entry = match entry { Some(e) => e, None => return err_json("unknown_handle", "unknown client handle") };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let fut = async move {
        let encryption = client.encryption();
        let backups = encryption.backups();
        let enabled = backups.are_enabled().await;
        let exists_on_server = backups.fetch_exists_on_server().await.unwrap_or(false);
        let state_enum = encryption.recovery().state();
        let recovery_state = format!("{:?}", state_enum);
        let needs_recovery = (exists_on_server && !enabled)
            || !matches!(state_enum, matrix_sdk::encryption::recovery::RecoveryState::Enabled);
        Ok::<BackupStatusDto, anyhow::Error>(BackupStatusDto { enabled, exists_on_server, recovery_state, needs_recovery })
    };
    match runtime.block_on(fut) { Ok(d) => ok_json(d), Err(e) => err_json("sdk_error", format!("{e:#}")) }
}

// Thin (typed) Backup status
pub fn backup_status(handle: Handle) -> Option<BackupStatusDto> {
    let entry = { let reg = CLIENTS.read().ok()?; reg.get(handle).cloned()? };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let fut = async move {
        let encryption = client.encryption();
        let backups = encryption.backups();
        let enabled = backups.are_enabled().await;
        let exists_on_server = backups.fetch_exists_on_server().await.unwrap_or(false);
        let state_enum = encryption.recovery().state();
        let recovery_state = format!("{:?}", state_enum);
        let needs_recovery = (exists_on_server && !enabled)
            || !matches!(state_enum, matrix_sdk::encryption::recovery::RecoveryState::Enabled);
        Ok::<BackupStatusDto, anyhow::Error>(BackupStatusDto { enabled, exists_on_server, recovery_state, needs_recovery })
    };
    match runtime.block_on(fut) { Ok(d) => Some(d), Err(_) => None }
}

pub fn enable_online_backup(handle: Handle, generate_new: bool) -> String {
    let entry = { let reg = CLIENTS.read().expect("clients lock"); reg.get(handle).cloned() };
    let entry = match entry { Some(e) => e, None => return err_json("unknown_handle", "unknown client handle") };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let fut = async move {
        let encryption = client.encryption();
        let backups = encryption.backups();
        let exists_on_server = backups.fetch_exists_on_server().await.unwrap_or(false);
        if generate_new {
            backups.create().await.map_err(|e| anyhow!(format!("failed to create backup version: {e:?}")))?;
        } else if !backups.are_enabled().await {
            encryption.recovery().enable_backup().await.map_err(|e| anyhow!(format!("failed to enable backup: {e:?}")))?;
        }
        let enabled = backups.are_enabled().await;
        Ok::<EnableBackupDto, anyhow::Error>(EnableBackupDto { enabled, exists_on_server, generated_recovery_key: None })
    };
    match runtime.block_on(fut) { Ok(d) => ok_json(d), Err(e) => err_json("sdk_error", format!("{e:#}")) }
}

pub fn ssss_import_recovery_key(handle: Handle, recovery_key_bech32: &str) -> String {
    let entry = { let reg = CLIENTS.read().expect("clients lock"); reg.get(handle).cloned() };
    let entry = match entry { Some(e) => e, None => return err_json("unknown_handle", "unknown client handle") };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let key = recovery_key_bech32.to_string();
    let fut = async move {
        client.encryption().recovery().recover(&key).await.map_err(|e| anyhow!(format!("failed to import recovery key: {e:?}")))?;
        Ok::<(), anyhow::Error>(())
    };
    match runtime.block_on(fut) { Ok(()) => ack_json(), Err(e) => err_json("sdk_error", format!("{e:#}")) }
}

pub fn ssss_bootstrap(handle: Handle, _generate_new_key: bool, _passphrase: Option<&str>) -> String {
    let entry = { let reg = CLIENTS.read().expect("clients lock"); reg.get(handle).cloned() };
    let entry = match entry { Some(e) => e, None => return err_json("unknown_handle", "unknown client handle") };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let fut = async move {
        let recovery_key = client
            .encryption()
            .recovery()
            .enable()
            .await
            .map_err(|e| anyhow!(format!("failed to bootstrap SSSS: {e:?}")))?;
        Ok::<SsssBootstrapDto, anyhow::Error>(SsssBootstrapDto { generated_recovery_key: Some(recovery_key) })
    };
    match runtime.block_on(fut) { Ok(d) => ok_json(d), Err(e) => err_json("sdk_error", format!("{e:#}")) }
}

pub fn ssss_export_recovery_key(_handle: Handle) -> String {
    err_json("sdk_error", "exporting the SSSS recovery key is not supported by the current matrix-sdk version")
}

// Streaming backup status snapshots (per-client controller)
use std::collections::HashMap;
use tokio_util::sync::CancellationToken;

struct BackupStatusControllerV2 {
    handle: Handle,
    listeners: AsyncMutex<std::collections::HashSet<i64>>,
}

static BACKUP_CONTROLLERS: Lazy<AsyncRwLock<HashMap<Handle, Arc<BackupStatusControllerV2>>>> = Lazy::new(|| AsyncRwLock::new(HashMap::new()));

impl BackupStatusControllerV2 {
    async fn create(handle: Handle) -> Result<Arc<Self>> {
        // validate client exists
        {
            let reg = CLIENTS.read().expect("clients lock");
            let _ = reg.get(handle).ok_or_else(|| anyhow!("unknown client handle"))?;
        }
        let cancel_token = CancellationToken::new();
        let controller = Arc::new(Self { handle, listeners: AsyncMutex::new(Default::default()) });
        controller.spawn_background(cancel_token);
        Ok(controller)
    }

    fn spawn_background(self: &Arc<Self>, cancel_token: CancellationToken) {
        let controller = self.clone();
        runtime().spawn(async move {
            let mut ticker = time::interval(Duration::from_secs(3));
            ticker.set_missed_tick_behavior(MissedTickBehavior::Delay);
            loop {
                tokio::select! {
                    _ = cancel_token.cancelled() => break,
                    _ = ticker.tick() => {
                        if let Ok(payload) = controller.snapshot().await {
                            let json = serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string());
                            let mut listeners = controller.listeners.lock().await;
                            let mut stale = Vec::new();
                            for &port in listeners.iter() { if !post_to_port(port, json.clone()) { stale.push(port); } }
                            for p in stale { listeners.remove(&p); }
                        }
                    }
                }
            }
        });
    }

    async fn add_listener(&self, port: i64) -> Result<()> {
        self.listeners.lock().await.insert(port);
        if let Ok(payload) = self.snapshot().await {
            let json = serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string());
            if !post_to_port(port, json) { self.listeners.lock().await.remove(&port); }
        }
        Ok(())
    }

    async fn snapshot(&self) -> Result<serde_json::Value> {
        let entry = { let reg = CLIENTS.read().expect("clients lock"); reg.get(self.handle).cloned().ok_or_else(|| anyhow!("unknown client handle"))? };
        let client = entry.client.clone();
        let enabled;
        let exists_on_server;
        let recovery_state;
        let needs_recovery;
        {
            let encryption = client.encryption();
            let backups = encryption.backups();
            enabled = backups.are_enabled().await;
            exists_on_server = backups.fetch_exists_on_server().await.unwrap_or(false);
            let state_enum = encryption.recovery().state();
            recovery_state = format!("{:?}", state_enum);
            needs_recovery = (exists_on_server && !enabled)
                || !matches!(state_enum, matrix_sdk::encryption::recovery::RecoveryState::Enabled);
        }
        Ok(serde_json::json!({
            "kind": "backup_status",
            "enabled": enabled,
            "exists_on_server": exists_on_server,
            "recovery_state": recovery_state,
            "needs_recovery": needs_recovery,
        }))
    }
}

pub fn backup_status_stream_json(handle: Handle, port: i64) -> String {
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move {
        let mut ctrls = BACKUP_CONTROLLERS.write().await;
        let ctrl = if let Some(c) = ctrls.get(&handle) { c.clone() } else { let c = BackupStatusControllerV2::create(handle).await?; ctrls.insert(handle, c.clone()); c };
        ctrl.add_listener(port).await?;
        Ok::<(), anyhow::Error>(())
    };
    match runtime.block_on(fut) { Ok(()) => ack_json(), Err(e) => err_json("sdk_error", format!("{e:#}")) }
}

// Thin (typed) Backup status stream (ack via bool)
pub fn backup_status_stream(handle: Handle, port: i64) -> bool {
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move {
        let mut ctrls = BACKUP_CONTROLLERS.write().await;
        let ctrl = if let Some(c) = ctrls.get(&handle) { c.clone() } else { let c = BackupStatusControllerV2::create(handle).await?; ctrls.insert(handle, c.clone()); c };
        ctrl.add_listener(port).await?;
        Ok::<(), anyhow::Error>(())
    };
    runtime.block_on(fut).is_ok()
}

// ---------- SAS Verification ----------

#[derive(Debug, Clone, Serialize)]
pub struct StartSasDto { pub flow_id: String }

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum SasStateV2 { Requested, Ready, KeysExchanged, Confirmed, Done, Cancelled }

#[derive(Debug, Clone, Serialize)]
struct SasPayloadV2 {
    kind: &'static str,
    flow_id: String,
    state: SasStateV2,
    emoji: Option<Vec<String>>,
    decimals: Option<(u16, u16, u16)>,
}

struct SasControllerV2 {
    flow_id: String,
    listeners: AsyncMutex<std::collections::HashSet<i64>>,
    state: AsyncMutex<SasStateV2>,
    emoji: AsyncMutex<Option<Vec<String>>>,
    decimals: AsyncMutex<Option<(u16, u16, u16)>>,
    // no controller-wide cancel token; per-to-device flow uses its own
    request: AsyncMutex<Option<VerificationRequest>>,
    sas: AsyncMutex<Option<SasVerification>>,
    to_device_cancel: AsyncMutex<Option<tokio_util::sync::CancellationToken>>,
}

static SAS_CONTROLLERS: Lazy<AsyncRwLock<std::collections::HashMap<String, Arc<SasControllerV2>>>> = Lazy::new(|| AsyncRwLock::new(std::collections::HashMap::new()));

impl SasControllerV2 {
    async fn create(flow_id: String) -> Arc<Self> {
        Arc::new(Self {
            flow_id,
            listeners: AsyncMutex::new(Default::default()),
            state: AsyncMutex::new(SasStateV2::Requested),
            emoji: AsyncMutex::new(None),
            decimals: AsyncMutex::new(None),
            request: AsyncMutex::new(None),
            sas: AsyncMutex::new(None),
            to_device_cancel: AsyncMutex::new(None),
        })
    }

    async fn add_listener(&self, port: i64) {
        self.listeners.lock().await.insert(port);
        let _ = self.broadcast_snapshot().await;
    }

    async fn set_state(&self, new_state: SasStateV2) {
        *self.state.lock().await = new_state.clone();
        let _ = self.broadcast_snapshot().await;
        if matches!(new_state, SasStateV2::Done | SasStateV2::Cancelled) {
            if let Some(ct) = self.to_device_cancel.lock().await.take() { ct.cancel(); }
        }
    }

    async fn snapshot(&self) -> SasPayloadV2 {
        SasPayloadV2 {
            kind: "sas_update",
            flow_id: self.flow_id.clone(),
            state: self.state.lock().await.clone(),
            emoji: self.emoji.lock().await.clone(),
            decimals: self.decimals.lock().await.clone(),
        }
    }

    async fn broadcast_snapshot(&self) -> Result<()> {
        let payload = self.snapshot().await;
        let json = serde_json::to_string(&payload)?;
        let mut listeners = self.listeners.lock().await;
        let mut stale = Vec::new();
        for &port in listeners.iter() { if !post_to_port(port, json.clone()) { stale.push(port); } }
        for p in stale { listeners.remove(&p); }
        Ok(())
    }

    async fn attach_request(self: &Arc<Self>, req: VerificationRequest) {
        *self.request.lock().await = Some(req.clone());
        let ctrl_for_changes = self.clone();
        runtime().spawn(async move {
            let mut changes = req.changes();
            while let Some(state) = changes.next().await {
                let mut try_start_sas = false;
                match state {
                    matrix_sdk::encryption::verification::VerificationRequestState::Requested { .. } => {
                        ctrl_for_changes.set_state(SasStateV2::Requested).await;
                    }
                    matrix_sdk::encryption::verification::VerificationRequestState::Ready { .. } => {
                        ctrl_for_changes.set_state(SasStateV2::Ready).await;
                        try_start_sas = true;
                    }
                    matrix_sdk::encryption::verification::VerificationRequestState::Done => {
                        ctrl_for_changes.set_state(SasStateV2::Done).await;
                        break;
                    }
                    matrix_sdk::encryption::verification::VerificationRequestState::Cancelled(_) => {
                        ctrl_for_changes.set_state(SasStateV2::Cancelled).await;
                        break;
                    }
                    _ => {}
                }
                if try_start_sas {
                    if ctrl_for_changes.sas.lock().await.is_none() {
                        if let Ok(Some(sas)) = req.start_sas().await {
                            SasControllerV2::on_sas_started(ctrl_for_changes.clone(), sas).await;
                        }
                    }
                }
            }
        });

        let ctrl = self.clone();
        runtime().spawn(async move {
            loop {
                if ctrl.sas.lock().await.is_some() { break; }
                let maybe_req = { ctrl.request.lock().await.clone() };
                if let Some(req) = maybe_req {
                    if let Ok(Some(sas)) = req.start_sas().await {
                        SasControllerV2::on_sas_started(ctrl.clone(), sas).await;
                        break;
                    }
                }
                time::sleep(Duration::from_millis(500)).await;
            }
        });
    }

    async fn on_sas_started(self: Arc<Self>, sas: SasVerification) {
        *self.sas.lock().await = Some(sas.clone());
        let stream = sas.changes();
        let _ = self.broadcast_snapshot().await;
        let ctrl = self.clone();
        runtime().spawn(async move {
            let mut stream = stream;
            while let Some(state) = stream.next().await {
                match state {
                    SdkSasState::KeysExchanged { emojis, decimals } => {
                        if let Some(emojis) = emojis {
                            let texts: Vec<String> = emojis.emojis.iter().map(|e| e.symbol.to_string()).collect();
                            *ctrl.emoji.lock().await = Some(texts);
                        }
                        *ctrl.decimals.lock().await = Some(decimals);
                        ctrl.set_state(SasStateV2::KeysExchanged).await;
                    }
                    SdkSasState::Confirmed => { ctrl.set_state(SasStateV2::Confirmed).await; }
                    SdkSasState::Done { .. } => { ctrl.set_state(SasStateV2::Done).await; break; }
                    SdkSasState::Cancelled(_) => { ctrl.set_state(SasStateV2::Cancelled).await; break; }
                    SdkSasState::Created { .. } | SdkSasState::Started { .. } | SdkSasState::Accepted { .. } => {}
                }
            }
        });
    }

    async fn start_to_device_worker(&self, client: Arc<Client>) {
        let settings = SyncSettings::default().timeout(Duration::from_secs(30));
        let cancel = tokio_util::sync::CancellationToken::new();
        *self.to_device_cancel.lock().await = Some(cancel.clone());
        runtime().spawn(async move {
            let _ = client.sync_with_callback(settings, {
                let cancel = cancel.clone();
                move |_response| {
                    let cancel = cancel.clone();
                    async move { if cancel.is_cancelled() { LoopCtrl::Break } else { LoopCtrl::Continue } }
                }
            }).await;
        });
    }
}

pub fn request_sas_verification(handle: Handle, user_id: &str, device_id: Option<&str>) -> String {
    let entry = { let reg = CLIENTS.read().expect("clients lock"); reg.get(handle).cloned() };
    let Some(entry) = entry else { return err_json("unknown_handle", "unknown client handle"); };
    let user_id: OwnedUserId = match user_id.parse() { Ok(u) => u, Err(_) => return err_json("invalid_arg", "invalid user id"), };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let fut = async move {
        let encryption = client.encryption();
        let request: VerificationRequest = if let Some(did) = device_id {
            let mut device_opt = None;
            for _ in 0..8 {
                match encryption.get_device(&user_id, did.into()).await {
                    Ok(Some(device)) => { device_opt = Some(device); break; }
                    Ok(None) => { let _ = client.sync_once(SyncSettings::default().timeout(Duration::from_millis(800))).await; time::sleep(Duration::from_millis(200)).await; }
                    Err(e) => return Err(anyhow!(format!("get_device failed: {e:?}"))),
                }
            }
            let device = device_opt.ok_or_else(|| anyhow!("target device not found"))?;
            device.request_verification().await.map_err(|e| anyhow!(format!("device.request_verification failed: {e:?}")))?
        } else {
            let identity_opt = encryption.get_user_identity(&user_id).await.map_err(|e| anyhow!(format!("get_user_identity failed: {e:?}")))?;
            let identity = identity_opt.ok_or_else(|| anyhow!("user identity not found for verification"))?;
            identity.request_verification().await.map_err(|e| anyhow!(format!("request_verification failed: {e:?}")))?
        };
        let flow_id = request.flow_id().to_string();
        let controller = SasControllerV2::create(flow_id.clone()).await;
        controller.start_to_device_worker(client.clone()).await;
        controller.attach_request(request).await;
        SAS_CONTROLLERS.write().await.insert(flow_id.clone(), controller);
        Ok::<StartSasDto, anyhow::Error>(StartSasDto { flow_id })
    };
    match runtime.block_on(fut) { Ok(d) => ok_json(d), Err(e) => err_json("sdk_error", format!("{e:#}")) }
}

pub fn observe_sas(flow_id: &str, port: i64) -> String {
    let flow_id = flow_id.to_owned();
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move {
        let ctrls = SAS_CONTROLLERS.read().await;
        let Some(ctrl) = ctrls.get(&flow_id) else { return Err(anyhow!("unknown sas flow_id")); };
        ctrl.add_listener(port).await;
        Ok::<(), anyhow::Error>(())
    };
    match runtime.block_on(fut) { Ok(()) => ack_json(), Err(e) => err_json("invalid_arg", format!("{e:#}")) }
}

pub fn confirm_sas(flow_id: &str) -> String {
    let flow_id = flow_id.to_owned();
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move {
        let ctrls = SAS_CONTROLLERS.read().await;
        let Some(ctrl) = ctrls.get(&flow_id) else { return Err(anyhow!("unknown sas flow_id")); };
        if let Some(sas) = ctrl.sas.lock().await.clone() { let _ = sas.confirm().await; }
        ctrl.set_state(SasStateV2::Confirmed).await;
        Ok::<(), anyhow::Error>(())
    };
    match runtime.block_on(fut) { Ok(()) => ack_json(), Err(e) => err_json("invalid_arg", format!("{e:#}")) }
}

pub fn cancel_sas(flow_id: &str) -> String {
    let flow_id = flow_id.to_owned();
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move {
        let ctrls = SAS_CONTROLLERS.read().await;
        let Some(ctrl) = ctrls.get(&flow_id) else { return Err(anyhow!("unknown sas flow_id")); };
        if let Some(sas) = ctrl.sas.lock().await.clone() { let _ = sas.cancel().await; }
        else if let Some(req) = ctrl.request.lock().await.clone() { let _ = req.cancel().await; }
        ctrl.set_state(SasStateV2::Cancelled).await;
        Ok::<(), anyhow::Error>(())
    };
    match runtime.block_on(fut) { Ok(()) => ack_json(), Err(e) => err_json("invalid_arg", format!("{e:#}")) }
}

// ---------- SAS (thin wrappers) ----------

// Provide a typed handle registry for SAS flows while we transition away from
// flow-id strings at the FFI boundary. Internally we still reuse the existing
// SasControllerV2, keeping stream payloads JSON as planned.
static SAS_HANDLES: Lazy<RwLock<Registry<Arc<SasControllerV2>>>> = Lazy::new(|| RwLock::new(Registry::default()));

pub fn sas_request_verification(client: Handle, user_id: &str, device_id: Option<&str>) -> Option<Handle> {
    // Reuse existing JSON-api function to create controller and insert into SAS_CONTROLLERS
    let res_json = request_sas_verification(client, user_id, device_id);
    let parsed: serde_json::Value = serde_json::from_str(&res_json).ok()?;
    let ok = parsed.get("ok").and_then(|v| v.as_bool()).unwrap_or(false);
    if !ok { return None; }
    let flow_id = parsed.get("data").and_then(|d| d.get("flow_id")).and_then(|v| v.as_str())?.to_string();
    // Look up controller and register typed handle
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move {
        let ctrls = SAS_CONTROLLERS.read().await;
        let ctrl = ctrls.get(&flow_id).cloned();
        Ok::<Option<Arc<SasControllerV2>>, anyhow::Error>(ctrl)
    };
    let ctrl = runtime.block_on(fut).ok().flatten()?;
    let mut reg = SAS_HANDLES.write().expect("sas registry lock");
    Some(reg.insert(ctrl))
}

pub fn sas_start_streaming(handle: Handle, port: i64) -> bool {
    let ctrl = {
        let reg = SAS_HANDLES.read().expect("sas registry lock");
        reg.get(handle).cloned()
    };
    let Some(ctrl) = ctrl else { return false; };
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move { ctrl.add_listener(port).await };
    let _ = runtime.block_on(fut);
    true
}

pub fn sas_confirm(handle: Handle) -> bool {
    let ctrl = {
        let reg = SAS_HANDLES.read().expect("sas registry lock");
        reg.get(handle).cloned()
    };
    let Some(ctrl) = ctrl else { return false; };
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move {
        if let Some(sas) = ctrl.sas.lock().await.clone() { let _ = sas.confirm().await; }
        ctrl.set_state(SasStateV2::Confirmed).await;
    };
    let _ = runtime.block_on(fut);
    true
}

pub fn sas_cancel(handle: Handle) -> bool {
    let ctrl = {
        let reg = SAS_HANDLES.read().expect("sas registry lock");
        reg.get(handle).cloned()
    };
    let Some(ctrl) = ctrl else { return false; };
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move {
        if let Some(sas) = ctrl.sas.lock().await.clone() { let _ = sas.cancel().await; }
        else if let Some(req) = ctrl.request.lock().await.clone() { let _ = req.cancel().await; }
        ctrl.set_state(SasStateV2::Cancelled).await;
    };
    let _ = runtime.block_on(fut);
    true
}

pub fn sas_get_emoji(handle: Handle) -> Option<Vec<String>> {
    let ctrl = {
        let reg = SAS_HANDLES.read().expect("sas registry lock");
        reg.get(handle).cloned()
    }?;
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move { ctrl.emoji.lock().await.clone() };
    runtime.block_on(fut)
}

pub fn sas_get_decimals(handle: Handle) -> Option<(u16, u16, u16)> {
    let ctrl = {
        let reg = SAS_HANDLES.read().expect("sas registry lock");
        reg.get(handle).cloned()
    }?;
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move { ctrl.decimals.lock().await.clone() };
    runtime.block_on(fut)
}

pub fn sas_free(handle: Handle) -> bool {
    let mut reg = SAS_HANDLES.write().expect("sas registry lock");
    // Best-effort: drop typed handle mapping; controller may stay referenced by flow-id map
    let (idx, gen) = Registry::<Arc<SasControllerV2>>::split_handle(handle);
    if let Some(slot) = reg.slots.get_mut(idx as usize) {
        if slot.occupied && slot.gen == gen { slot.occupied = false; slot.value = None; reg.free.push(idx); return true; }
    }
    false
}
