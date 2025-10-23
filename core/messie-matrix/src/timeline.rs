use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use allo_isolate::Isolate;
use anyhow::{anyhow, Context, Result};
use log::{debug, trace, warn};
use matrix_sdk::room::{Messages, MessagesOptions, Room as MatrixRoom};
use matrix_sdk::ruma::{
    events::room::encrypted::{OriginalRoomEncryptedEvent, OriginalSyncRoomEncryptedEvent},
    serde::Raw,
    OwnedRoomId, UInt,
};
use once_cell::sync::Lazy;
use serde::Serialize;
use tokio::sync::{Mutex as AsyncMutex, RwLock as AsyncRwLock};
use tokio::time::interval;
use tokio_util::sync::CancellationToken;

use crate::{client, runtime, active_base_path};

static TIMELINES: Lazy<AsyncRwLock<HashMap<String, Arc<TimelineController>>>> =
    Lazy::new(|| AsyncRwLock::new(HashMap::new()));

#[derive(Debug, Clone, Serialize)]
pub struct OpenRoomResponse {
    pub room_id: String,
    pub initialized: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct TimelineAck {
    pub ok: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct LoadBackwardResponse {
    pub reached_start: bool,
    pub events: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
struct TimelinePayload {
    kind: &'static str,
    room_id: String,
    events: Vec<String>,
}

const DEFAULT_PAGE_SIZE: u32 = 30;
const POLL_INTERVAL: Duration = Duration::from_secs(2);

pub async fn open_room(handle: &str, room_id: &str) -> Result<OpenRoomResponse> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let room_id: OwnedRoomId = room_id
        .try_into()
        .map_err(|err| anyhow!("invalid room id '{room_id}': {err}"))?;

    let room = client
        .get_room(&room_id)
        .ok_or_else(|| anyhow!("room {room_id} not found"))?;

    let key = timeline_key(handle, &room_id);
    let mut timelines = TIMELINES.write().await;

    if timelines.contains_key(&key) {
        return Ok(OpenRoomResponse {
            room_id: room_id.as_str().to_owned(),
            initialized: false,
        });
    }

    let controller = TimelineController::create(room).await?;
    timelines.insert(key, controller);

    Ok(OpenRoomResponse {
        room_id: room_id.as_str().to_owned(),
        initialized: true,
    })
}

pub async fn register_timeline_listener(
    handle: &str,
    room_id: &str,
    port: i64,
) -> Result<TimelineAck> {
    let room_id: OwnedRoomId = room_id
        .try_into()
        .map_err(|err| anyhow!("invalid room id '{room_id}': {err}"))?;
    let timelines = TIMELINES.read().await;
    let key = timeline_key(handle, &room_id);
    let controller = timelines
        .get(&key)
        .cloned()
        .ok_or_else(|| anyhow!("timeline for room {room_id} not opened"))?;

    controller.register_listener(port).await?;
    Ok(TimelineAck { ok: true })
}

pub async fn load_backward(
    handle: &str,
    room_id: &str,
    limit: u32,
) -> Result<LoadBackwardResponse> {
    let room_id: OwnedRoomId = room_id
        .try_into()
        .map_err(|err| anyhow!("invalid room id '{room_id}': {err}"))?;
    let timelines = TIMELINES.read().await;
    let key = timeline_key(handle, &room_id);
    let controller = timelines
        .get(&key)
        .cloned()
        .ok_or_else(|| anyhow!("timeline for room {room_id} not opened"))?;

    controller.load_backward(limit).await
}

pub async fn reset_all() {
    let mut timelines = TIMELINES.write().await;
    for controller in timelines.values() {
        controller.shutdown();
    }
    timelines.clear();
}

fn timeline_key(handle: &str, room_id: &OwnedRoomId) -> String {
    format!("{handle}::{room_id}")
}

struct TimelineController {
    room_id: OwnedRoomId,
    room: MatrixRoom,
    listeners: AsyncMutex<HashSet<i64>>,
    backward_token: AsyncMutex<Option<String>>,
    seen_event_ids: AsyncMutex<HashSet<String>>,
    seen_event_hashes: AsyncMutex<HashSet<String>>,
    cancel_token: CancellationToken,
    // Offline cache
    cache_file: PathBuf,
    cache_cursor: AsyncMutex<usize>,
}

impl TimelineController {
    async fn create(room: MatrixRoom) -> Result<Arc<Self>> {
        let room_id = room.room_id().to_owned();
        let cancel_token = CancellationToken::new();
        let cache_file = timeline_cache_path(&room_id);
        let cached_len = read_cached_len(&cache_file).unwrap_or(0);

        let controller = Arc::new(Self {
            room_id,
            room,
            listeners: AsyncMutex::new(HashSet::new()),
            backward_token: AsyncMutex::new(None),
            seen_event_ids: AsyncMutex::new(HashSet::new()),
            seen_event_hashes: AsyncMutex::new(HashSet::new()),
            cancel_token: cancel_token.clone(),
            cache_file,
            cache_cursor: AsyncMutex::new(cached_len),
        });

        controller.spawn_background(cancel_token);
        Ok(controller)
    }

    fn spawn_background(self: &Arc<Self>, cancel_token: CancellationToken) {
        let controller = Arc::clone(self);
        runtime().spawn(async move {
            let mut ticker = interval(POLL_INTERVAL);
            loop {
                tokio::select! {
                    _ = cancel_token.cancelled() => {
                        debug!("timeline '{}' cancelled", controller.room_id);
                        break;
                    }
                    _ = ticker.tick() => {
                        if let Err(err) = controller.poll_latest().await {
                            warn!("failed to poll timeline {}: {err:?}", controller.room_id);
                        }
                    }
                }
            }
        });
    }

    async fn register_listener(&self, port: i64) -> Result<()> {
        self.listeners.lock().await.insert(port);
        // Try online first; on failure, use offline cache snapshot
        let events = match self.collect_latest(DEFAULT_PAGE_SIZE, true).await {
            Ok(e) => {
                // Adjust offline cursor to latest window
                let cached_len = read_cached_len(&self.cache_file).unwrap_or(0);
                let start_idx = cached_len.saturating_sub(e.len());
                *self.cache_cursor.lock().await = start_idx;
                e
            }
            Err(_) => {
                let e = load_recent_from_cache(&self.cache_file, DEFAULT_PAGE_SIZE as usize).unwrap_or_default();
                let cached_len = read_cached_len(&self.cache_file).unwrap_or(0);
                let start_idx = cached_len.saturating_sub(e.len());
                *self.cache_cursor.lock().await = start_idx;
                parse_cached_events(e)
            }
        };
        self.record_seen(&events).await;
        self.send_to(port, "timeline_snapshot", events).await
    }

    async fn load_backward(&self, limit: u32) -> Result<LoadBackwardResponse> {
        // Try network; on error, serve from offline cache
        match self.paginate_backward_online(limit).await {
            Ok((events, reached_start)) => Ok(LoadBackwardResponse { reached_start, events }),
            Err(_) => {
                let events = self.paginate_backward_from_cache(limit).await.unwrap_or_default();
                Ok(LoadBackwardResponse { reached_start: events.is_empty() || *self.cache_cursor.lock().await == 0, events })
            }
        }
    }

    async fn poll_latest(&self) -> Result<()> {
        let events = self.collect_latest(DEFAULT_PAGE_SIZE, false).await?;
        let new_events = self.filter_new(events).await;
        if new_events.is_empty() {
            return Ok(());
        }
        self.broadcast("timeline_append", new_events).await
    }

    async fn collect_latest(
        &self,
        limit: u32,
        update_backward: bool,
    ) -> Result<Vec<CollectedEvent>> {
        let options = MessagesOptions::backward().with_limit(limit);
        let messages = self
            .room
            .messages(options)
            .await
            .context("failed to load recent messages")?;

        if update_backward {
            *self.backward_token.lock().await = messages.end.clone();
        } else if self.backward_token.lock().await.is_none() {
            *self.backward_token.lock().await = messages.end.clone();
        }

        let mut events = Self::extract_events(&messages)?;
        self.maybe_decrypt_events(&mut events).await;
        // Update offline cache with latest events
        if let Err(e) = update_cache(&self.cache_file, &events.iter().map(|e| e.raw.clone()).collect::<Vec<_>>()) { let _ = e; }
        Ok(events)
    }

    async fn record_seen(&self, events: &[CollectedEvent]) {
        let mut ids = self.seen_event_ids.lock().await;
        let mut hashes = self.seen_event_hashes.lock().await;
        for event in events {
            if let Some(id) = &event.id {
                ids.insert(id.clone());
            } else {
                hashes.insert(event.raw.clone());
            }
        }
    }

    async fn filter_new(&self, events: Vec<CollectedEvent>) -> Vec<String> {
        let mut ids = self.seen_event_ids.lock().await;
        let mut hashes = self.seen_event_hashes.lock().await;
        let mut result = Vec::new();

        for event in events {
            let is_new = if let Some(id) = event.id {
                ids.insert(id)
            } else {
                hashes.insert(event.raw.clone())
            };

            if is_new {
                result.push(event.raw);
            }
        }

        result
    }

    async fn broadcast(&self, kind: &'static str, events: Vec<String>) -> Result<()> {
        if events.is_empty() {
            return Ok(());
        }

        let payload = TimelinePayload {
            kind,
            room_id: self.room_id.as_str().to_owned(),
            events,
        };

        let json = serde_json::to_string(&payload)?;
        let mut listeners = self.listeners.lock().await;
        let mut stale = Vec::new();
        for &port in listeners.iter() {
            if !Self::post_to_port(port, json.clone()) {
                stale.push(port);
            }
        }
        for port in stale {
            listeners.remove(&port);
        }
        Ok(())
    }

    async fn send_to(
        &self,
        port: i64,
        kind: &'static str,
        events: Vec<CollectedEvent>,
    ) -> Result<()> {
        let payload = TimelinePayload {
            kind,
            room_id: self.room_id.as_str().to_owned(),
            events: events.into_iter().map(|event| event.raw).collect(),
        };
        let json = serde_json::to_string(&payload)?;
        if !Self::post_to_port(port, json) {
            self.listeners.lock().await.remove(&port);
        }
        Ok(())
    }

    fn post_to_port(port: i64, payload: String) -> bool {
        Isolate::new(port).post(payload)
    }

    fn extract_events(messages: &Messages) -> Result<Vec<CollectedEvent>> {
        let mut events = Vec::new();
        for event in messages.chunk.iter() {
            if let Ok(Some(event_type)) = event.raw().get_field::<String>("type") {
                trace!(
                    "timeline {} collected event of type {event_type}",
                    messages.start
                );
            }
            let raw =
                serde_json::to_string(event.raw()).context("failed to serialise timeline event")?;
            let id = event.event_id().map(|id| id.to_string());
            events.push(CollectedEvent { id, raw });
        }
        events.reverse();
        Ok(events)
    }

    async fn maybe_decrypt_events(&self, events: &mut [CollectedEvent]) {
        for event in events.iter_mut() {
            if !event.raw.contains("\"m.room.encrypted\"") {
                continue;
            }

            let raw_event: Raw<OriginalRoomEncryptedEvent> =
                match Raw::from_json_string(event.raw.clone()) {
                    Ok(raw) => raw,
                    Err(err) => {
                        warn!("failed to parse encrypted event for decryption: {err:?}");
                        continue;
                    }
                };

            let sync_event = raw_event.cast::<OriginalSyncRoomEncryptedEvent>();

            match self.room.decrypt_event(&sync_event, None).await {
                Ok(decrypted) => {
                    if let Ok(serialized) = serde_json::to_string(decrypted.raw()) {
                        event.raw = serialized;
                    }
                    if let Some(event_id) = decrypted.event_id() {
                        event.id = Some(event_id.to_string());
                    }
                }
                Err(err) => {
                    warn!("[timeline] decryption retry failed for room {}: {err:?}", self.room_id);
                }
            }
        }
    }

    fn shutdown(&self) {
        self.cancel_token.cancel();
    }
}

// ---------- Offline cache helpers ----------

fn timeline_cache_path(room_id: &OwnedRoomId) -> PathBuf {
    let base = active_base_path().unwrap_or_else(|| PathBuf::from(".messie_store_v2"));
    let store_root = base.join("matrix_store");
    let cache_dir = store_root.join("timeline_cache");
    let _ = std::fs::create_dir_all(&cache_dir);
    let fname = sanitize_room_id(room_id.as_str()) + ".json";
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

fn read_cached_len(path: &Path) -> Result<usize> { Ok(load_cache(path)?.map(|v| v.len()).unwrap_or(0)) }

fn load_recent_from_cache(path: &Path, limit: usize) -> Result<Vec<String>> {
    let Some(mut all) = load_cache(path)? else { return Ok(Vec::new()) };
    if all.len() > limit { all.drain(0..all.len() - limit); }
    Ok(all)
}

fn load_cache(path: &Path) -> Result<Option<Vec<String>>> {
    use anyhow::Context;
    if !path.exists() { return Ok(None); }
    let bytes = std::fs::read(path).with_context(|| format!("failed to read cache at {}", path.display()))?;
    let value: serde_json::Value = serde_json::from_slice(&bytes).context("failed to parse cache JSON")?;
    let events = if let Some(arr) = value.as_array() {
        arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect()
    } else if let Some(arr) = value.get("events").and_then(|v| v.as_array()) {
        arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect()
    } else { Vec::new() };
    Ok(Some(events))
}

const MAX_CACHED_EVENTS: usize = 500;

fn update_cache(path: &Path, newest: &[String]) -> Result<()> {
    use anyhow::Context;
    let mut merged: Vec<String> = load_cache(path)?.unwrap_or_default();
    for ev in newest { if !merged.contains(ev) { merged.push(ev.clone()); } }
    if merged.len() > MAX_CACHED_EVENTS { let drop = merged.len() - MAX_CACHED_EVENTS; merged.drain(0..drop); }
    let parent = path.parent(); if let Some(dir) = parent { let _ = std::fs::create_dir_all(dir); }
    let out = serde_json::json!({"events": merged});
    std::fs::write(path, serde_json::to_vec_pretty(&out).context("serialize cache")?).with_context(|| format!("failed to write cache at {}", path.display()))?;
    Ok(())
}

impl TimelineController {
    async fn paginate_backward_online(&self, limit: u32) -> Result<(Vec<String>, bool)> {
        let token = { self.backward_token.lock().await.clone() };
        let options = match token.as_deref() {
            Some(token) => MessagesOptions::backward().from(token).with_limit(limit),
            None => MessagesOptions::backward().with_limit(limit),
        };
        let messages = self
            .room
            .messages(options)
            .await
            .context("failed to load older messages")?;

        *self.backward_token.lock().await = messages.end.clone();

        let mut events = Self::extract_events(&messages)?;
        self.maybe_decrypt_events(&mut events).await;
        // Prepend to cache since these are older events
        if let Ok(Some(existing)) = load_cache(&self.cache_file) {
            let mut merged = Vec::new();
            for e in &events { if !existing.contains(&e.raw) { merged.push(e.raw.clone()); } }
            merged.extend(existing.into_iter());
            if merged.len() > MAX_CACHED_EVENTS { let drop = merged.len() - MAX_CACHED_EVENTS; let _ = merged.drain(0..drop); }
            let _ = std::fs::write(&self.cache_file, serde_json::to_vec_pretty(&serde_json::json!({"events": merged})).unwrap_or_default());
        }
        let reached_start = messages.end.is_none();
        Ok((events.into_iter().map(|e| e.raw).collect(), reached_start))
    }

    async fn paginate_backward_from_cache(&self, limit: u32) -> Result<Vec<String>> {
        let events = load_cache(&self.cache_file)?.unwrap_or_default();
        let mut cursor = self.cache_cursor.lock().await;
        let end = *cursor;
        let start = end.saturating_sub(limit as usize);
        let slice = if start < end { events[start..end].to_vec() } else { Vec::new() };
        *cursor = start;
        Ok(slice)
    }
}

struct CollectedEvent {
    id: Option<String>,
    raw: String,
}

trait MessagesOptionsExt {
    fn with_limit(self, limit: u32) -> Self;
}

impl MessagesOptionsExt for MessagesOptions {
    fn with_limit(mut self, limit: u32) -> Self {
        self.limit = UInt::from(limit);
        self
    }
}

fn parse_cached_events(raws: Vec<String>) -> Vec<CollectedEvent> {
    raws
        .into_iter()
        .map(|raw| {
            let id = extract_event_id(&raw);
            CollectedEvent { id, raw }
        })
        .collect()
}

fn extract_event_id(raw: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(raw).ok()?;
    v.get("event_id").and_then(|x| x.as_str()).map(|s| s.to_string())
}
