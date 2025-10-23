use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};

use anyhow::{anyhow, Context, Result};
use matrix_sdk::{
    room::{Messages, MessagesOptions, Room as MatrixRoom},
    ruma::{OwnedRoomId, UInt},
};
use once_cell::sync::Lazy;
use serde::Serialize;
use tokio::sync::Mutex as AsyncMutex;
use tokio::time::{self, Duration, MissedTickBehavior};

use crate::client::CLIENTS;
use crate::common::handle_registry::{Handle, Registry};
use crate::common::post_to_port;
use crate::common::runtime::runtime;

struct TimelineController {
    room: MatrixRoom,
    listeners: AsyncMutex<HashSet<i64>>, // Dart ports
    backward_token: AsyncMutex<Option<String>>,

    // Offline cache
    cache_file: PathBuf,
    // Cursor pointing to how many oldest events remain undisclosed in cache when offline.
    // Interpreted as an index into [0..cached_len]; 0 means we've reached the start.
    cache_cursor: AsyncMutex<usize>,
}

static TL_CONTROLLERS: Lazy<RwLock<Registry<Arc<TimelineController>>>> =
    Lazy::new(|| RwLock::new(Registry::default()));

#[derive(Debug, Serialize)]
struct TimelineSnapshotDto {
    kind: &'static str,
    events: Vec<String>,
}

#[derive(Debug, Serialize)]
struct TimelineAppendDto {
    kind: &'static str,
    events: Vec<String>,
}

pub fn timeline_open(handle: Handle, room_id: &str) -> Option<Handle> {
    let entry = {
        let reg = CLIENTS.read().ok()?;
        reg.get(handle).cloned()?
    };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let rid_str = room_id.to_string();
    let fut = async move {
        let room_id: OwnedRoomId = rid_str
            .parse()
            .map_err(|_| anyhow!("invalid room id"))?;
        let Some(room) = client.get_room(&room_id) else { return Err(anyhow!("room not found")); };
        // Prepare offline cache paths and initial cursor from disk length.
        let cache_file = timeline_cache_path(&entry.base_path, &room_id);
        let cached_len = read_cached_len(&cache_file).unwrap_or(0);
        let ctrl = Arc::new(TimelineController {
            room,
            listeners: AsyncMutex::new(HashSet::new()),
            backward_token: AsyncMutex::new(None),
            cache_file,
            cache_cursor: AsyncMutex::new(cached_len),
        });
        Ok::<Arc<TimelineController>, anyhow::Error>(ctrl)
    };
    match runtime.block_on(fut) {
        Ok(ctrl) => {
            let handle = TL_CONTROLLERS
                .write()
                .ok()?
                .insert(ctrl);
            Some(handle)
        }
        Err(_) => None,
    }
}

pub fn timeline_start_streaming(tl: Handle, port: i64) -> bool {
    let ctrl = {
        let reg = TL_CONTROLLERS.read().ok();
        reg.and_then(|r| r.get(tl).cloned())
    };
    let Some(ctrl) = ctrl else { return false; };
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move {
        ctrl.listeners.lock().await.insert(port);
        // Try online fetch first; if it fails, fall back to cached snapshot.
        let events = match collect_latest(&ctrl, 30, true).await {
            Ok(events) => {
                // Update cache cursor to reflect that we've revealed the newest snapshot.
                let cached_len = read_cached_len(&ctrl.cache_file).unwrap_or(0);
                let start_idx = cached_len.saturating_sub(events.len());
                *ctrl.cache_cursor.lock().await = start_idx;
                events
            }
            Err(_) => {
                let events = load_recent_from_cache(&ctrl.cache_file, 30).unwrap_or_default();
                // If we serve from cache, ensure the cursor reflects how much history remains.
                let cached_len = read_cached_len(&ctrl.cache_file).unwrap_or(0);
                let start_idx = cached_len.saturating_sub(events.len());
                *ctrl.cache_cursor.lock().await = start_idx;
                events
            }
        };
        let payload = serde_json::to_string(&TimelineSnapshotDto {
            kind: "timeline_snapshot",
            events,
        })?;
        if !post_to_port(port, payload) {
            ctrl.listeners.lock().await.remove(&port);
        }
        spawn_timeline_background(ctrl.clone());
        Ok::<(), anyhow::Error>(())
    };
    runtime.block_on(fut).is_ok()
}

pub fn timeline_load_backward(tl: Handle, limit: u32) -> bool {
    let ctrl = {
        let reg = TL_CONTROLLERS.read().ok();
        reg.and_then(|r| r.get(tl).cloned())
    };
    let Some(ctrl) = ctrl else { return false; };
    let runtime = runtime();
    let _guard = runtime.enter();
    let fut = async move {
        // Try network pagination; if it fails, fall back to cache.
        let mut used_cache = false;
        let events = match paginate_backward_online(&ctrl, limit).await {
            Ok(mut evs) => {
                maybe_decrypt_events(&ctrl, &mut evs).await;
                evs
            }
            Err(_) => {
                used_cache = true;
                paginate_backward_from_cache(&ctrl, limit).await.unwrap_or_default()
            }
        };

        let payload = serde_json::to_string(&TimelineAppendDto { kind: "timeline_prepend", events })
            .unwrap_or_else(|_| "{}".to_string());
        let mut listeners = ctrl.listeners.lock().await;
        let mut stale = Vec::new();
        for &p in listeners.iter() {
            if !post_to_port(p, payload.clone()) {
                stale.push(p);
            }
        }
        for p in stale { listeners.remove(&p); }
        // If we used the cache, nothing else to do. If online, state already updated.
        if used_cache { /* no-op */ }
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
                        if seen.insert(ev.clone()) {
                            new.push(ev);
                        }
                    }
                    if !new.is_empty() {
                        let payload = serde_json::to_string(&TimelineAppendDto {
                            kind: "timeline_append",
                            events: new,
                        })
                        .unwrap_or_else(|_| "{}".to_string());
                        let mut listeners = ctrl.listeners.lock().await;
                        let mut stale = Vec::new();
                        for &port in listeners.iter() {
                            if !post_to_port(port, payload.clone()) {
                                stale.push(port);
                            }
                        }
                        for p in stale {
                            listeners.remove(&p);
                        }
                    }
                }
                Err(_) => {}
            }
        }
    });
}

async fn collect_latest(
    ctrl: &Arc<TimelineController>,
    limit: u32,
    update_backward: bool,
) -> Result<Vec<String>> {
    let mut options = MessagesOptions::backward();
    options.limit = UInt::from(limit);
    let resp = ctrl
        .room
        .messages(options)
        .await
        .context("failed to load recent messages")?;
    if update_backward {
        *ctrl.backward_token.lock().await = resp.end.clone();
    }
    let mut events = extract_events(&resp)?;
    maybe_decrypt_events(ctrl, &mut events).await;
    // Update offline cache with the newest snapshot.
    if let Err(e) = update_cache(&ctrl.cache_file, &events).and_then(|_| Ok(())) {
        let _ = e; // ignore cache write failures silently
    }
    Ok(events)
}

fn extract_events(messages: &Messages) -> Result<Vec<String>> {
    let mut out = Vec::new();
    for ev in messages.chunk.iter() {
        let raw = serde_json::to_string(ev.raw())
            .context("failed to serialise timeline event")?;
        out.push(raw);
    }
    out.reverse();
    Ok(out)
}

async fn maybe_decrypt_events(ctrl: &Arc<TimelineController>, events: &mut [String]) {
    use matrix_sdk::ruma::events::room::encrypted::{
        OriginalRoomEncryptedEvent, OriginalSyncRoomEncryptedEvent,
    };
    use matrix_sdk::ruma::serde::Raw;
    for raw in events.iter_mut() {
        if !raw.contains("\"m.room.encrypted\"") {
            continue;
        }
        let Ok(parsed) = Raw::<OriginalRoomEncryptedEvent>::from_json_string(raw.clone()) else { continue; };
        let sync_ev = parsed.cast::<OriginalSyncRoomEncryptedEvent>();
        if let Ok(decrypted) = ctrl.room.decrypt_event(&sync_ev, None).await {
            if let Ok(serialized) = serde_json::to_string(decrypted.raw()) {
                *raw = serialized;
            }
        }
    }
}

// ---------- Offline cache helpers ----------

const MAX_CACHED_EVENTS: usize = 500;

fn timeline_cache_path(base_path: &Path, room_id: &OwnedRoomId) -> PathBuf {
    let store_root = base_path.join("matrix_store");
    let cache_dir = store_root.join("timeline_cache");
    let _ = std::fs::create_dir_all(&cache_dir);
    let fname = sanitize_room_id(room_id.as_str()) + ".json";
    cache_dir.join(fname)
}

fn sanitize_room_id(id: &str) -> String {
    // Replace characters that are awkward in filenames.
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
    // Accept either a bare array ["raw", ...] or an object {"events": [..]}
    let value: serde_json::Value = serde_json::from_slice(&bytes).context("failed to parse cache JSON")?;
    let events = if let Some(arr) = value.as_array() {
        arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect()
    } else if let Some(arr) = value.get("events").and_then(|v| v.as_array()) {
        arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect()
    } else {
        Vec::new()
    };
    Ok(Some(events))
}

fn update_cache(path: &Path, newest_events: &[String]) -> Result<()> {
    use anyhow::Context;
    // Merge existing + newest, dedup by event_id or raw string.
    let mut merged: Vec<String> = load_cache(path)?.unwrap_or_default();
    for ev in newest_events {
        if !contains_event(&merged, ev) {
            merged.push(ev.clone());
        }
    }
    // Cap size: keep the last MAX_CACHED_EVENTS events.
    if merged.len() > MAX_CACHED_EVENTS {
        let drop = merged.len() - MAX_CACHED_EVENTS;
        merged.drain(0..drop);
    }
    let out = serde_json::json!({ "events": merged });
    let parent = path.parent();
    if let Some(dir) = parent { let _ = std::fs::create_dir_all(dir); }
    let data = serde_json::to_vec_pretty(&out).context("failed to serialise cache")?;
    std::fs::write(path, data).with_context(|| format!("failed to write cache at {}", path.display()))?;
    Ok(())
}

fn contains_event(existing: &[String], candidate: &str) -> bool {
    // Try to dedup by event_id if present, otherwise by full raw string.
    if let Some(id) = extract_event_id(candidate) {
        for raw in existing.iter() {
            if let Some(rid) = extract_event_id(raw) { if rid == id { return true; } }
        }
        false
    } else {
        existing.iter().any(|r| r == candidate)
    }
}

fn extract_event_id(raw: &str) -> Option<String> {
    let v: serde_json::Value = serde_json::from_str(raw).ok()?;
    v.get("event_id").and_then(|x| x.as_str()).map(|s| s.to_string())
}

async fn paginate_backward_online(ctrl: &Arc<TimelineController>, limit: u32) -> Result<Vec<String>> {
    let token = { ctrl.backward_token.lock().await.clone() };
    let mut options = MessagesOptions::backward();
    if let Some(t) = token.as_deref() { options = options.from(t); }
    options.limit = UInt::from(limit);
    let resp = ctrl.room.messages(options).await?;
    { *ctrl.backward_token.lock().await = resp.end.clone(); }
    let mut events = extract_events(&resp)?;
    // Update cache too, since we've received older events; prepend them in order.
    if let Ok(Some(mut existing)) = load_cache(&ctrl.cache_file) {
        // Existing is ascending chronological; resp events returned ascending too.
        // Prepend older events at the front if they are not already present.
        let mut merged: Vec<String> = Vec::new();
        for e in &events { if !contains_event(&existing, e) { merged.push(e.clone()); } }
        merged.extend(existing.into_iter());
        if merged.len() > MAX_CACHED_EVENTS {
            let drop = merged.len() - MAX_CACHED_EVENTS; let _ = merged.drain(0..drop);
        }
        let _ = std::fs::write(&ctrl.cache_file, serde_json::to_vec_pretty(&serde_json::json!({"events": merged})).unwrap_or_default());
    }
    Ok(events)
}

async fn paginate_backward_from_cache(ctrl: &Arc<TimelineController>, limit: u32) -> Result<Vec<String>> {
    let events = load_cache(&ctrl.cache_file)?.unwrap_or_default();
    let mut cursor = ctrl.cache_cursor.lock().await;
    let end = *cursor;
    let start = end.saturating_sub(limit as usize);
    let slice = if start < end { events[start..end].to_vec() } else { Vec::new() };
    *cursor = start;
    Ok(slice)
}
