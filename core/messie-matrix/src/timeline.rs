use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
    time::Duration,
};

use allo_isolate::Isolate;
use anyhow::{anyhow, Context, Result};
use log::{debug, warn};
use matrix_sdk::room::{Messages, MessagesOptions, Room as MatrixRoom};
use matrix_sdk::ruma::events::room::message::{MessageType, RoomMessageEventContent};
use matrix_sdk::ruma::events::{
    AnySyncMessageLikeEvent, AnySyncTimelineEvent, SyncMessageLikeEvent,
};
use matrix_sdk::ruma::{OwnedRoomId, UInt};
use matrix_sdk_common::deserialized_responses::TimelineEvent;
use once_cell::sync::Lazy;
use serde::Serialize;
use tokio::sync::{Mutex as AsyncMutex, RwLock as AsyncRwLock};
use tokio::time::interval;
use tokio_util::sync::CancellationToken;

use crate::{client, runtime};

static TIMELINES: Lazy<AsyncRwLock<HashMap<String, Arc<TimelineController>>>> =
    Lazy::new(|| AsyncRwLock::new(HashMap::new()));

const DEFAULT_PAGE_SIZE: u32 = 30;
const POLL_INTERVAL: Duration = Duration::from_secs(2);

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
    pub loaded: u32,
}

#[derive(Debug, Clone, Serialize)]
struct TimelineEnvelope {
    room_id: String,
    updates: Vec<TimelineUpdate>,
}

#[derive(Debug, Clone, Serialize)]
struct TimelineUpdate {
    op: TimelineOpKind,
    items: Vec<TimelineEntry>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
enum TimelineOpKind {
    Reset,
    Append,
    Prepend,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq, Hash)]
struct TimelineKey {
    event_id: Option<String>,
    txn_id: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
struct TimelineEntry {
    event_key: TimelineKey,
    timestamp: Option<u64>,
    sender: String,
    body: Option<String>,
    msgtype: Option<String>,
    is_own: bool,
}

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

    let controller = TimelineController::create(handle.to_owned(), room).await?;
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

    controller.load_older(limit).await
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
    snapshot: AsyncMutex<Vec<TimelineEntry>>,
    listeners: AsyncMutex<HashSet<i64>>,
    backward_token: AsyncMutex<Option<String>>,
    cancel_token: CancellationToken,
}

impl TimelineController {
    async fn create(_handle: String, room: MatrixRoom) -> Result<Arc<Self>> {
        let room_id = room.room_id().to_owned();
        let cancel_token = CancellationToken::new();

        let controller = Arc::new(Self {
            room_id,
            room: room.clone(),
            snapshot: AsyncMutex::new(Vec::new()),
            listeners: AsyncMutex::new(HashSet::new()),
            backward_token: AsyncMutex::new(None),
            cancel_token: cancel_token.clone(),
        });

        controller.initialise().await?;
        controller.spawn_background(cancel_token);

        Ok(controller)
    }

    async fn initialise(&self) -> Result<()> {
        let entries = self.fetch_latest(DEFAULT_PAGE_SIZE, true).await?;
        *self.snapshot.lock().await = entries.clone();
        let envelope = TimelineEnvelope {
            room_id: self.room_id.as_str().to_owned(),
            updates: vec![TimelineUpdate {
                op: TimelineOpKind::Reset,
                items: entries,
            }],
        };
        self.broadcast(envelope).await
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

    fn shutdown(&self) {
        self.cancel_token.cancel();
    }

    async fn register_listener(&self, port: i64) -> Result<()> {
        let mut listeners = self.listeners.lock().await;
        listeners.insert(port);

        let snapshot = self.snapshot.lock().await.clone();
        if snapshot.is_empty() {
            return Ok(());
        }

        let envelope = TimelineEnvelope {
            room_id: self.room_id.as_str().to_owned(),
            updates: vec![TimelineUpdate {
                op: TimelineOpKind::Reset,
                items: snapshot,
            }],
        };
        self.send_to(port, envelope).await
    }

    async fn load_older(&self, limit: u32) -> Result<LoadBackwardResponse> {
        let token = { self.backward_token.lock().await.clone() };
        if token.is_none() {
            return Ok(LoadBackwardResponse {
                reached_start: true,
                loaded: 0,
            });
        }

        let options = MessagesOptions::backward()
            .from(token.as_deref())
            .with_limit(limit);
        let messages = self
            .room
            .messages(options)
            .await
            .context("failed to load older messages")?;

        if messages.chunk.is_empty() {
            *self.backward_token.lock().await = None;
            return Ok(LoadBackwardResponse {
                reached_start: true,
                loaded: 0,
            });
        }

        let own_user_id = self.room.client().user_id().map(|id| id.to_string());
        let mut entries = collect_entries(&messages, own_user_id.as_deref());
        entries.reverse();

        let mut snapshot = self.snapshot.lock().await;
        let mut items = Vec::new();
        for entry in entries.into_iter().rev() {
            if snapshot
                .iter()
                .any(|existing| existing.event_key == entry.event_key)
            {
                continue;
            }
            snapshot.insert(0, entry.clone());
            items.push(entry);
        }

        items.reverse();

        *self.backward_token.lock().await = messages.end.clone();

        if items.is_empty() {
            return Ok(LoadBackwardResponse {
                reached_start: messages.end.is_none(),
                loaded: 0,
            });
        }

        let envelope = TimelineEnvelope {
            room_id: self.room_id.as_str().to_owned(),
            updates: vec![TimelineUpdate {
                op: TimelineOpKind::Prepend,
                items: items.clone(),
            }],
        };
        drop(snapshot);
        self.broadcast(envelope).await?;
        Ok(LoadBackwardResponse {
            reached_start: messages.end.is_none(),
            loaded: items.len() as u32,
        })
    }

    async fn poll_latest(&self) -> Result<()> {
        let latest = self.fetch_latest(DEFAULT_PAGE_SIZE, false).await?;
        if latest.is_empty() {
            return Ok(());
        }

        let mut snapshot = self.snapshot.lock().await;
        if snapshot.is_empty() {
            *snapshot = latest.clone();
            let envelope = TimelineEnvelope {
                room_id: self.room_id.as_str().to_owned(),
                updates: vec![TimelineUpdate {
                    op: TimelineOpKind::Reset,
                    items: latest,
                }],
            };
            drop(snapshot);
            return self.broadcast(envelope).await;
        }

        let known: HashSet<_> = snapshot
            .iter()
            .map(|entry| entry.event_key.clone())
            .collect();
        let mut new_items = Vec::new();
        for entry in latest.iter() {
            if !known.contains(&entry.event_key) {
                new_items.push(entry.clone());
            }
        }

        if new_items.is_empty() {
            return Ok(());
        }

        snapshot.extend(new_items.clone());
        drop(snapshot);

        let envelope = TimelineEnvelope {
            room_id: self.room_id.as_str().to_owned(),
            updates: vec![TimelineUpdate {
                op: TimelineOpKind::Append,
                items: new_items,
            }],
        };
        self.broadcast(envelope).await
    }

    async fn fetch_latest(&self, limit: u32, update_token: bool) -> Result<Vec<TimelineEntry>> {
        let options = MessagesOptions::backward().with_limit(limit);
        let messages = self
            .room
            .messages(options)
            .await
            .context("failed to load recent messages")?;

        if update_token {
            *self.backward_token.lock().await = messages.end.clone();
        } else if self.backward_token.lock().await.is_none() {
            *self.backward_token.lock().await = messages.end.clone();
        }

        let own_user_id = self.room.client().user_id().map(|id| id.to_string());
        let mut entries = collect_entries(&messages, own_user_id.as_deref());
        entries.reverse();
        Ok(entries)
    }

    async fn broadcast(&self, envelope: TimelineEnvelope) -> Result<()> {
        let payload = serde_json::to_string(&envelope)?;
        let mut listeners = self.listeners.lock().await;
        let mut stale = Vec::new();
        for &port in listeners.iter() {
            if !Isolate::new(port).post(payload.clone()) {
                stale.push(port);
            }
        }
        for port in stale {
            listeners.remove(&port);
        }
        Ok(())
    }

    async fn send_to(&self, port: i64, envelope: TimelineEnvelope) -> Result<()> {
        let payload = serde_json::to_string(&envelope)?;
        if !Isolate::new(port).post(payload) {
            let mut listeners = self.listeners.lock().await;
            listeners.remove(&port);
        }
        Ok(())
    }
}

fn collect_entries(messages: &Messages, own_user_id: Option<&str>) -> Vec<TimelineEntry> {
    messages
        .chunk
        .iter()
        .filter_map(|event| build_entry(event, own_user_id).ok())
        .collect()
}

fn build_entry(event: &TimelineEvent, own_user_id: Option<&str>) -> Result<TimelineEntry> {
    let raw = event.raw();
    let timeline_event: AnySyncTimelineEvent = raw.clone().deserialize()?;

    let (event_id, sender, content, timestamp, txn_id, is_own) = match timeline_event {
        AnySyncTimelineEvent::MessageLike(AnySyncMessageLikeEvent::RoomMessage(message)) => {
            match message {
                SyncMessageLikeEvent::Original(ev) => {
                    let ts = Some(u64::from(ev.origin_server_ts.get()));
                    let txn_id = ev.unsigned.transaction_id.clone().map(|id| id.to_string());
                    (
                        Some(ev.event_id.to_string()),
                        ev.sender.to_string(),
                        ev.content,
                        ts,
                        txn_id,
                        own_user_id
                            .map(|id| id == ev.sender.as_str())
                            .unwrap_or(false),
                    )
                }
                SyncMessageLikeEvent::Redacted(_) => return Err(anyhow!("redacted message")),
            }
        }
        _ => return Err(anyhow!("unsupported event type")),
    };

    let (body, msgtype) = extract_body(&content);

    Ok(TimelineEntry {
        event_key: TimelineKey { event_id, txn_id },
        timestamp,
        sender,
        body,
        msgtype,
        is_own,
    })
}

fn extract_body(content: &RoomMessageEventContent) -> (Option<String>, Option<String>) {
    match &content.msgtype {
        MessageType::Text(text) => (Some(text.body.clone()), Some("m.text".to_owned())),
        MessageType::Notice(notice) => (Some(notice.body.clone()), Some("m.notice".to_owned())),
        MessageType::Emote(emote) => (Some(emote.body.clone()), Some("m.emote".to_owned())),
        MessageType::Image(image) => (Some(image.body.clone()), Some("m.image".to_owned())),
        MessageType::Video(video) => (Some(video.body.clone()), Some("m.video".to_owned())),
        MessageType::Audio(audio) => (Some(audio.body.clone()), Some("m.audio".to_owned())),
        MessageType::File(file) => (Some(file.body.clone()), Some("m.file".to_owned())),
        _ => (None, None),
    }
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
