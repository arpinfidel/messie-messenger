use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
};

use allo_isolate::Isolate;
use anyhow::{anyhow, Context, Result};
use futures::StreamExt;
use log::{debug, warn, trace};
use matrix_sdk::{
    sliding_sync::{SlidingSync, SlidingSyncList, SlidingSyncMode, UpdateSummary, Version},
    Client, RoomDisplayName, RoomState,
    room::Room as MatrixRoom,
    room::MessagesOptions,
};
// use matrix_sdk::config::SyncSettings;
use matrix_sdk::ruma::api::client::sync::sync_events::v5 as http;
use once_cell::sync::Lazy;
use serde::Serialize;
use tokio::sync::{mpsc, Mutex as AsyncMutex, RwLock as AsyncRwLock};
use tokio_util::sync::CancellationToken;
use tokio::time::{sleep, Duration};

use crate::{client, runtime, active_base_path};
use std::path::PathBuf;

static CONTROLLERS: Lazy<AsyncRwLock<HashMap<String, Arc<SlidingSyncController>>>> =
    Lazy::new(|| AsyncRwLock::new(HashMap::new()));

#[derive(Debug, Clone, Copy)]
pub struct SlidingSyncConfig {
    pub hp_size: u32,
    pub lp_batch: u32,
    pub hp_timeline: u32,
    pub lp_timeline: u32,
}

pub async fn joined_room_ids() -> Vec<String> {
    let controllers_guard = CONTROLLERS.read().await;
    let controllers: Vec<_> = controllers_guard.values().cloned().collect();
    drop(controllers_guard);

    let mut rooms = HashSet::new();
    for controller in controllers {
        rooms.extend(controller.room_ids().await);
    }

    let mut rooms: Vec<String> = rooms.into_iter().collect();
    rooms.sort();
    rooms
}

#[derive(Debug, Clone, Serialize)]
pub struct StartSlidingSyncResponse {
    pub started: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct AckResponse {
    pub ok: bool,
}

#[derive(Debug, Serialize)]
struct SlidingSyncUpdate {
    kind: &'static str,
    lists: Vec<String>,
    rooms: Vec<String>,
    summaries: Vec<crate::RoomOverview>,
}

#[derive(Debug, Serialize)]
struct SlidingSyncErrorPayload {
    kind: &'static str,
    message: String,
}

#[derive(Debug)]
enum Command {
    Resubscribe,
}

pub async fn start_sliding_sync(
    handle: &str,
    config: SlidingSyncConfig,
) -> Result<StartSlidingSyncResponse> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let mut controllers = CONTROLLERS.write().await;

    if controllers.contains_key(handle) {
        return Ok(StartSlidingSyncResponse { started: false });
    }

    let controller = SlidingSyncController::create(handle.to_owned(), client, config).await?;
    controllers.insert(handle.to_owned(), controller);

    Ok(StartSlidingSyncResponse { started: true })
}

pub async fn register_room_list_listener(handle: &str, port: i64) -> Result<AckResponse> {
    let controllers = CONTROLLERS.read().await;
    let controller = controllers
        .get(handle)
        .cloned()
        .ok_or_else(|| anyhow!("Sliding sync '{handle}' has not been started"))?;

    controller.register_listener(port).await?;
    Ok(AckResponse { ok: true })
}

pub async fn reset_all() {
    let mut controllers = CONTROLLERS.write().await;
    for controller in controllers.values() {
        controller.shutdown();
    }
    controllers.clear();
}

struct SlidingSyncController {
    handle: String,
    sliding_sync: SlidingSync,
    listeners: AsyncMutex<HashSet<i64>>,
    room_ids: AsyncRwLock<HashSet<String>>,
    command_tx: mpsc::UnboundedSender<Command>,
    cancel_token: CancellationToken,
    /// Config used to build this controller; reused for per-room subscriptions
    config: SlidingSyncConfig,
}

impl SlidingSyncController {
    async fn create(
        handle: String,
        client: Arc<Client>,
        config: SlidingSyncConfig,
    ) -> Result<Arc<Self>> {
        let sliding_sync = Self::build_sliding_sync(&client, &handle, config).await?;
        let (command_tx, command_rx) = mpsc::unbounded_channel();
        let cancel_token = CancellationToken::new();

        let controller = Arc::new(Self {
            handle,
            sliding_sync,
            listeners: AsyncMutex::new(std::collections::HashSet::new()),
            room_ids: AsyncRwLock::new(HashSet::new()),
            command_tx,
            cancel_token: cancel_token.clone(),
            config,
        });

        // No extra seeding; rely entirely on Sliding Sync.

        controller.spawn_background(command_rx, cancel_token);
        Ok(controller)
    }

    fn spawn_background(
        self: &Arc<Self>,
        mut command_rx: mpsc::UnboundedReceiver<Command>,
        cancel_token: CancellationToken,
    ) {
        let controller = Arc::clone(self);
        runtime().spawn(async move {
            let mut stream = Box::pin(controller.sliding_sync.sync());
            loop {
                tokio::select! {
                    _ = cancel_token.cancelled() => {
                        debug!("sliding sync '{}' cancelled", controller.handle);
                        break;
                    }
                    Some(command) = command_rx.recv() => {
                        if let Err(err) = controller.handle_command(command).await {
                            warn!("sliding sync '{}' command failed: {err:?}", controller.handle);
                        }
                    }
                    Some(result) = stream.next() => {
                        match result {
                            Ok(summary) => {
                                if let Err(err) = controller.publish_summary(summary).await {
                                    warn!("sliding sync '{}' update handling failed: {err:?}", controller.handle);
                                }
                            }
                            Err(err) => {
                                warn!("sliding sync '{}' stream error: {err:?}", controller.handle);
                                if let Err(e2) = controller.broadcast_error(format!("{err:?}")).await {
                                    warn!("sliding sync '{}' failed to broadcast error: {e2:?}", controller.handle);
                                }
                                controller.enqueue(Command::Resubscribe);
                            }
                        }
                    }
                    else => break,
                }
            }
        });
    }

    async fn register_listener(self: &Arc<Self>, port: i64) -> Result<()> {
        self.listeners.lock().await.insert(port);
        // If a persisted room-list cache exists, emit it immediately so the UI
        // can render offline after app restart.
        maybe_wipe_legacy_room_list_cache();
        if let Some(persisted) = load_persisted_room_list() {
            let rooms: Vec<String> = persisted.iter().map(|s| s.room_id.clone()).collect();
            let payload = SlidingSyncUpdate { kind: "sliding_sync_update", lists: vec!["all".to_string()], rooms, summaries: persisted };
            let json = serde_json::to_string(&payload)?;
            if !Self::post_to_port(port, json) {
                self.listeners.lock().await.remove(&port);
                return Ok(());
            }
        }

        // Also emit a live snapshot from the SDK cache (works offline if rooms
        // are hydrated in the store), then mark the stream as ready.
        // Prefer known rooms from sliding controller; if empty (e.g., first
        // start offline), build from SDK store so we still render.
        let mut rooms: Vec<String> = self.room_ids().await;
        if rooms.is_empty() {
            if let Some(client) = crate::client() {
                rooms = client
                    .rooms()
                    .into_iter()
                    .filter(|r| matches!(r.state(), RoomState::Joined))
                    .map(|r| r.room_id().to_string())
                    .collect();
                rooms.sort();
            }
        }
        let live = build_summaries(&rooms).await;
        if !live.is_empty() { let _ = persist_room_list(&live); }
        let json = serde_json::to_string(&SlidingSyncUpdate { kind: "sliding_sync_update", lists: vec!["all".to_string()], rooms: rooms.clone(), summaries: live })?;
        if !Self::post_to_port(port, json) {
            self.listeners.lock().await.remove(&port);
            return Ok(());
        }
        // Warm-up pass: allow event cache to compute latest_event, then re-emit.
        self.spawn_warmup_broadcast(rooms.clone());
        let ready = serde_json::to_string(&serde_json::json!({ "kind": "sliding_sync_ready" }))?;
        if !Self::post_to_port(port, ready) { self.listeners.lock().await.remove(&port); }
        Ok(())
    }

    async fn handle_command(&self, command: Command) -> Result<()> {
        match command {
            Command::Resubscribe => {
                self.sliding_sync.expire_session().await;
            }
        }
        Ok(())
    }

    async fn publish_summary(self: &Arc<Self>, summary: UpdateSummary) -> Result<()> {
        let UpdateSummary { lists, rooms } = summary;
        let rooms: Vec<String> = rooms.into_iter().map(|room| room.to_string()).collect();

        // Concise overview; use trace for details
        debug!("[ss] update: {} rooms", rooms.len());

        if !rooms.is_empty() {
            let mut known = self.room_ids.write().await;
            for room in &rooms {
                known.insert(room.clone());
            }

            // TRACE: per-room notification data (noisy)
            if let Some(client) = crate::client() {
                for room_id_str in &rooms {
                    if let Ok(room_id) = room_id_str.parse::<matrix_sdk::ruma::OwnedRoomId>() {
                        if let Some(room) = client.get_room(&room_id) {
                            let counts = room.unread_notification_counts();
                            trace!("[ss] room {} counts n={} h={}", room_id_str, counts.notification_count, counts.highlight_count);

                            // Also check if this room has any recent activity
                            let recency = room.recency_stamp();
                            trace!("[ss] room {} recency: {:?}", room_id_str, recency);
                        } else {
                            trace!("[ss] room {} not in cache", room_id_str);
                        }
                    }
                }
            } else {
                trace!("[ss] update with no client available");
            }
        }

        // Build lightweight summaries for updated rooms only.
        let summaries: Vec<crate::RoomOverview> = build_summaries(&rooms).await;
        // Merge into persisted cache so restarts show recent data offline.
        if !summaries.is_empty() { let _ = merge_persisted_room_list(&summaries); }
        let update = SlidingSyncUpdate { kind: "sliding_sync_update", lists: lists.clone(), rooms: rooms.clone(), summaries };
        self.broadcast(update).await?;
        // Warm-up pass to allow latest_event to settle in cache; no extra network.
        self.spawn_warmup_broadcast(rooms);
        Ok(())
    }

    async fn broadcast_error(&self, message: impl ToString) -> Result<()> {
        let payload = SlidingSyncErrorPayload { kind: "sliding_sync_error", message: message.to_string() };
        self.broadcast(payload).await
    }

    async fn broadcast<T: Serialize>(&self, payload: T) -> Result<()> {
        let json = serde_json::to_string(&payload)?;
        let mut listeners = self.listeners.lock().await;
        let mut stale = Vec::new();
        for &port in listeners.iter() {
            if !Self::post_to_port(port, json.clone()) {
                warn!("failed to post sliding sync update to port {port}");
                stale.push(port);
            }
        }
        for port in stale {
            listeners.remove(&port);
        }
        Ok(())
    }

    fn enqueue(&self, command: Command) {
        if let Err(err) = self.command_tx.send(command) {
            warn!("failed to enqueue sliding sync command: {err:?}");
        }
    }

    fn shutdown(&self) {
        self.cancel_token.cancel();
    }

    fn post_to_port(port: i64, payload: String) -> bool {
        Isolate::new(port).post(payload)
    }

    async fn room_ids(&self) -> Vec<String> {
        self.room_ids.read().await.iter().cloned().collect()
    }

    fn spawn_warmup_broadcast(self: &Arc<Self>, rooms: Vec<String>) {
        let this = Arc::clone(self);
        runtime().spawn(async move {
            // Small delay to let cache settle
            sleep(Duration::from_millis(450)).await;
            let summaries = build_summaries(&rooms).await;
            if !summaries.is_empty() { let _ = merge_persisted_room_list(&summaries); }
            let payload = SlidingSyncUpdate { kind: "sliding_sync_update", lists: vec!["all".to_string()], rooms: rooms.clone(), summaries };
            let _ = this.broadcast(payload).await;
        });
    }

    // No targeted backfill; rely solely on Sliding Sync timelines.

    async fn build_sliding_sync(
        client: &Client,
        handle: &str,
        config: SlidingSyncConfig,
    ) -> Result<SlidingSync> {
        let builder = client
            .sliding_sync(handle)
            .context("failed to initialise sliding sync builder")?
            .version(Version::Native)
            // Enable standard extensions but disable to-device here to avoid
            // token-type conflicts when classic /sync is also used.
            .with_all_extensions()
            .without_to_device_extension();

        let hp_u32: u32 = config.hp_size.max(1);
        let hp_end: u32 = hp_u32.saturating_sub(1);
        let list = SlidingSyncList::builder("all")
            // Use Selective with explicit ranges; Growing mode doesn't expose add_range on our SDK version.
            .sync_mode(SlidingSyncMode::new_selective().add_range(0..=hp_end))
            .timeline_limit(config.lp_timeline.max(1))
            .required_state(vec![
                ("m.room.name".into(), "".to_string()),
                ("m.room.avatar".into(), "".to_string()),
                ("m.room.encryption".into(), "".to_string()),
                ("com.beeper.room_type".into(), "".to_string()),
                ("com.beeper.room_type.v2".into(), "".to_string()),
            ]);

        let sliding = builder
            .add_list(list)
            .build()
            .await
            .context("failed to build sliding sync instance")
            ?;

        // Ensure event cache is active so latest_event can be computed from
        // the sliding sync timeline items without additional network calls.
        let _ = client.event_cache().subscribe();

        Ok(sliding)
    }
}

// ---------- Room list persistence helpers ----------

fn room_list_cache_path() -> PathBuf {
    let base = active_base_path().unwrap_or_else(|| PathBuf::from(".messie_store_v2"));
    let store_root = base.join("matrix_store");
    let _ = std::fs::create_dir_all(&store_root);
    store_root.join("room_list_cache.json")
}

fn persist_room_list(summaries: &[crate::RoomOverview]) -> anyhow::Result<()> {
    let path = room_list_cache_path();
    let payload = serde_json::json!({ "rooms": summaries });
    let data = serde_json::to_vec_pretty(&payload)?;
    std::fs::write(path, data)?;
    Ok(())
}

/// Detect and wipe old room_list_cache that was persisted without
/// `latest_event_ts` (older builds). Those snapshots cause incorrect
/// ordering on startup until a fresh live snapshot replaces them.
fn maybe_wipe_legacy_room_list_cache() {
    let path = room_list_cache_path();
    if !path.exists() { return; }
    let bytes = match std::fs::read(&path) { Ok(b) => b, Err(_) => return };
    let v: serde_json::Value = match serde_json::from_slice(&bytes) { Ok(v) => v, Err(_) => return };
    let Some(arr) = v.get("rooms").and_then(|x| x.as_array()) else { return };
    let mut total = 0usize; let mut missing = 0usize;
    for item in arr { if let Some(obj) = item.as_object() { total += 1; if !obj.contains_key("latest_event_ts") { missing += 1; } } }
    if total > 0 && missing * 2 >= total { // majority missing -> legacy snapshot
        let _ = std::fs::remove_file(&path);
        log::debug!("[ss] wiped legacy room_list_cache.json missing latest_event_ts");
    }
}

fn load_persisted_room_list() -> Option<Vec<crate::RoomOverview>> {
    let path = room_list_cache_path();
    if !path.exists() { return None; }
    let bytes = std::fs::read(path).ok()?;
    let v: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    let arr = v.get("rooms")?.as_array()?.clone();
    let mut out = Vec::new();
    for item in arr.into_iter() {
        if let Ok(room) = serde_json::from_value::<crate::RoomOverview>(item) { out.push(room); }
    }
    Some(out)
}

fn merge_persisted_room_list(updated: &[crate::RoomOverview]) -> anyhow::Result<()> {
    let mut map: std::collections::HashMap<String, crate::RoomOverview> = load_persisted_room_list()
        .unwrap_or_default()
        .into_iter()
        .map(|r| (r.room_id.clone(), r))
        .collect();
    for r in updated { map.insert(r.room_id.clone(), r.clone()); }
    let mut all: Vec<_> = map.into_values().collect();
    // Sort desc by real latest_event_ts when available, else bump_ts; fallback by name
    all.sort_by(|a,b| {
        let ascore = a.latest_event_ts.or(a.bump_ts).unwrap_or(0);
        let bscore = b.latest_event_ts.or(b.bump_ts).unwrap_or(0);
        bscore.cmp(&ascore).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    persist_room_list(&all)
}

fn timeline_cache_path_for(room_id: &str) -> PathBuf {
    let base = active_base_path().unwrap_or_else(|| PathBuf::from(".messie_store_v2"));
    let store_root = base.join("matrix_store");
    let cache_dir = store_root.join("timeline_cache");
    let _ = std::fs::create_dir_all(&cache_dir);
    let fname = sanitize_room_id(room_id) + ".json";
    cache_dir.join(fname)
}

fn sanitize_room_id(id: &str) -> String {
    id.chars()
        .map(|c| match c {
            ':' | '!' | '$' | '/' | '\\' | '?' | '#' | '*' | ' ' => '_',
            _ => c,
        })
        .collect()
}

fn latest_ts_from_timeline_cache(room_id: &str) -> Option<u64> {
    let path = timeline_cache_path_for(room_id);
    if !path.exists() { return None; }
    let bytes = std::fs::read(path).ok()?;
    let v: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    let arr = if let Some(a) = v.as_array() { a.clone() } else { v.get("events")?.as_array()?.clone() };
    for item in arr.iter().rev() {
        let raw = item.as_str()?;
        let ev: serde_json::Value = serde_json::from_str(raw).ok()?;
        if let Some(ts) = ev.get("origin_server_ts").and_then(|x| x.as_u64()) { return Some(ts); }
    }
    None
}

/// Returns the latest origin_server_ts of a message-like event from the
/// offline timeline cache. Treats encrypted events as message-like so E2EE
/// rooms are correctly ordered by the most recent message.
fn latest_message_ts_from_timeline_cache(room_id: &str) -> Option<u64> {
    let path = timeline_cache_path_for(room_id);
    if !path.exists() { return None; }
    let bytes = std::fs::read(path).ok()?;
    let v: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    let arr = if let Some(a) = v.as_array() { a.clone() } else { v.get("events")?.as_array()?.clone() };
    for item in arr.iter().rev() {
        let raw = item.as_str()?;
        let ev: serde_json::Value = serde_json::from_str(raw).ok()?;
        let ety = ev.get("type").and_then(|x| x.as_str()).unwrap_or("");
        // Consider normal messages, stickers, and encrypted payloads as message-like
        let is_message_like = matches!(ety,
            "m.room.message" | "m.sticker" | "m.room.encrypted" | "m.image" | "m.video" | "m.audio" | "m.file"
        );
        if !is_message_like { continue; }
        if let Some(ts) = ev.get("origin_server_ts").and_then(|x| x.as_u64()) { return Some(ts); }
    }
    None
}

/// Light online probe to find the latest message-like event timestamp without
/// opening full timelines in the UI. This uses a small backward pagination and
/// stops at the first message-like event.
async fn latest_message_ts_online(room: &MatrixRoom) -> Option<u64> {
    use matrix_sdk::ruma::UInt;
    // Keep it modest to reduce bandwidth; we only need the latest page.
    let mut opts = MessagesOptions::backward();
    opts.limit = UInt::from(20u32);
    let messages = match room.messages(opts).await { Ok(m) => m, Err(_) => return None };
    for ev in messages.chunk.iter().rev() { // newest last; iterate reversed
        let ety = ev.raw().get_field::<String>("type").ok().flatten().unwrap_or_default();
        let is_message_like = matches!(ety.as_str(),
            "m.room.message" | "m.sticker" | "m.room.encrypted" | "m.image" | "m.video" | "m.audio" | "m.file"
        );
        if !is_message_like { continue; }
        if let Ok(Some(ts)) = ev.raw().get_field::<u64>("origin_server_ts") { return Some(ts); }
    }
    None
}

async fn build_summaries(room_ids: &[String]) -> Vec<crate::RoomOverview> {
    let mut summaries: Vec<crate::RoomOverview> = Vec::new();
    if let Some(client) = crate::client() {
        for room_id_str in room_ids {
            if let Ok(room_id) = room_id_str.parse::<matrix_sdk::ruma::OwnedRoomId>() {
                if let Some(room) = client.get_room(&room_id) {
                    let display_name = match room.display_name().await {
                        Ok(RoomDisplayName::Named(n))
                        | Ok(RoomDisplayName::Calculated(n))
                        | Ok(RoomDisplayName::Aliased(n))
                        | Ok(RoomDisplayName::EmptyWas(n)) => n,
                        Ok(RoomDisplayName::Empty) => room_id.as_str().to_owned(),
                        Err(_) => room_id.as_str().to_owned(),
                    };
                    let avatar_url = room.avatar_url().map(|u| u.to_string());
                    let bump_ts = room.recency_stamp();
                    // Prefer a message-like timestamp from cache when available
                    // to better match Element's behavior of sorting by last
                    // message activity. Fallback to the SDK's latest event.
                    let (remote_ts, remote_type): (Option<u64>, Option<String>) = match room.new_latest_event() {
                        matrix_sdk::latest_events::LatestEventValue::Remote(remote) => {
                            let ty = remote.raw().get_field::<String>("type").ok().flatten();
                            let ts = remote
                                .raw()
                                .deserialize()
                                .ok()
                                .map(|e| u64::from(e.origin_server_ts().get()));
                            (ts, ty)
                        }
                        matrix_sdk::latest_events::LatestEventValue::LocalIsSending(_)
                        | matrix_sdk::latest_events::LatestEventValue::LocalCannotBeSent(_) => (None, None),
                        matrix_sdk::latest_events::LatestEventValue::None => (None, None),
                    }
                    // Safe offline fallback: only origin_server_ts from cached events.
                    ;
                    let mut latest_event_ts = remote_ts.or_else(|| latest_ts_from_timeline_cache(room_id.as_str()));
                    // If the remote latest event isn't a message-like type, try to
                    // replace it with a message-like timestamp to better match clients.
                    let remote_is_message_like = match remote_type.as_deref() {
                        Some("m.room.message" | "m.sticker" | "m.room.encrypted" | "m.image" | "m.video" | "m.audio" | "m.file") => true,
                        _ => false,
                    };
                    if !remote_is_message_like {
                        if let Some(ts) = latest_message_ts_from_timeline_cache(room_id.as_str()) { latest_event_ts = Some(ts); }
                    }
                    // As a last resort, do a light online probe for message-like ts
                    if latest_event_ts.is_none() || !remote_is_message_like {
                        if let Some(client) = crate::client() {
                            if let Some(r) = client.get_room(&room_id) {
                                if let Some(ts) = latest_message_ts_online(&r).await { latest_event_ts = Some(ts); }
                            }
                        }
                    }
                    let is_marked_unread = room.is_marked_unread();
                    let is_muted = crate::is_room_muted(room_id.as_str());
                    let counts = room.unread_notification_counts();
                    summaries.push(crate::RoomOverview {
                        room_id: room_id.as_str().to_owned(),
                        name: display_name,
                        avatar_url,
                        bump_ts,
                        latest_event_ts,
                        notification_count: counts.notification_count,
                        highlight_count: counts.highlight_count,
                        is_marked_unread,
                        is_muted,
                    });
                }
            }
        }
    }
    summaries
}

pub async fn subscribe_rooms(handle: &str, room_ids: Vec<String>, reset: bool) -> Result<AckResponse> {
    let controllers = CONTROLLERS.read().await;
    let controller = controllers
        .get(handle)
        .cloned()
        .ok_or_else(|| anyhow!("Sliding sync '{handle}' has not been started"))?;
    drop(controllers);

    debug!("[ss] subscribing to {} rooms", room_ids.len());
    for room_id in &room_ids {
        trace!("[ss] subscribing: {}", room_id);
    }

    // Subscribe to specific rooms with notifications enabled
    // This is required for the SDK to properly track notification counters
    if !room_ids.is_empty() {
        // Parse room IDs and keep the owned versions alive
        let owned_room_ids: Vec<matrix_sdk::ruma::OwnedRoomId> = room_ids.iter()
            .filter_map(|id| {
                match id.parse() {
                    Ok(parsed) => {
                        trace!("[ss] parsed room id: {}", id);
                        Some(parsed)
                    }
                    Err(e) => {
                        debug!("failed to parse room id '{}': {:?}", id, e);
                        None
                    }
                }
            })
            .collect();

        if !owned_room_ids.is_empty() {
            let room_id_refs: Vec<&matrix_sdk::ruma::RoomId> = owned_room_ids
                .iter()
                .map(|id| id.as_ref())
                .collect();

            debug!("[ss] subscribe_to_rooms with {} valid ids", room_id_refs.len());

            // Provide a RoomSubscription with required_state to satisfy Synapse.
            let mut sub = http::request::RoomSubscription::default();
            // Ensure a few timeline events are included per subscribed room so the
            // SDK can compute a proper latest_event timestamp without extra calls.
            let tl = controller.config.lp_timeline.max(1);
            sub.timeline_limit = matrix_sdk::ruma::UInt::from(tl);
            sub.required_state = vec![
                ("m.room.name".into(), "".to_string()),
                ("m.room.avatar".into(), "".to_string()),
                ("m.room.encryption".into(), "".to_string()),
            ];
            controller
                .sliding_sync
                .subscribe_to_rooms(&room_id_refs, Some(sub), reset);
            debug!("[ss] subscribed: {} rooms (reset={})", room_id_refs.len(), reset);
        } else {
            debug!("[ss] no valid room ids to subscribe to");
        }
    } else {
        debug!("[ss] no room ids provided for subscription");
    }

    Ok(AckResponse { ok: true })
}
