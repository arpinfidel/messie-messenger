use std::collections::{HashMap, HashSet};
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

use crate::{client, runtime};

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
}

impl TimelineController {
    async fn create(room: MatrixRoom) -> Result<Arc<Self>> {
        let room_id = room.room_id().to_owned();
        let cancel_token = CancellationToken::new();

        let controller = Arc::new(Self {
            room_id,
            room,
            listeners: AsyncMutex::new(HashSet::new()),
            backward_token: AsyncMutex::new(None),
            seen_event_ids: AsyncMutex::new(HashSet::new()),
            seen_event_hashes: AsyncMutex::new(HashSet::new()),
            cancel_token: cancel_token.clone(),
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
        let events = self.collect_latest(DEFAULT_PAGE_SIZE, true).await?;
        self.record_seen(&events).await;
        self.send_to(port, "timeline_snapshot", events).await
    }

    async fn load_backward(&self, limit: u32) -> Result<LoadBackwardResponse> {
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
        let reached_start = messages.end.is_none();
        self.record_seen(&events).await;

        Ok(LoadBackwardResponse {
            reached_start,
            events: events.into_iter().map(|event| event.raw).collect(),
        })
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
                    warn!("decryption retry failed for room {}: {err:?}", self.room_id);
                    println!("decryption retry failed for room {}: {err:?}", self.room_id);
                }
            }
        }
    }

    fn shutdown(&self) {
        self.cancel_token.cancel();
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
