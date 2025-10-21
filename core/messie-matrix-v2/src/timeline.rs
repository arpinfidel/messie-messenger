use std::collections::HashSet;
use std::sync::{Arc, RwLock};

use anyhow::{anyhow, Context, Result};
use futures::StreamExt;
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
        let ctrl = Arc::new(TimelineController {
            room,
            listeners: AsyncMutex::new(HashSet::new()),
            backward_token: AsyncMutex::new(None),
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
        let events = collect_latest(&ctrl, 30, true).await?;
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
        let token = { ctrl.backward_token.lock().await.clone() };
        let mut options = MessagesOptions::backward();
        if let Some(t) = token.as_deref() {
            options = options.from(t);
        }
        options.limit = UInt::from(limit);
        let resp = ctrl.room.messages(options).await?;
        {
            *ctrl.backward_token.lock().await = resp.end.clone();
        }
        let mut events = extract_events(&resp)?;
        maybe_decrypt_events(&ctrl, &mut events).await;
        let payload = serde_json::to_string(&TimelineAppendDto {
            kind: "timeline_prepend",
            events,
        })
        .unwrap_or_else(|_| "{}".to_string());
        let mut listeners = ctrl.listeners.lock().await;
        let mut stale = Vec::new();
        for &p in listeners.iter() {
            if !post_to_port(p, payload.clone()) {
                stale.push(p);
            }
        }
        for p in stale {
            listeners.remove(&p);
        }
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

