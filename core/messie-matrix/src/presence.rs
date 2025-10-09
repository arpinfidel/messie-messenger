use std::collections::{HashMap, HashSet};
use std::sync::Arc;

use allo_isolate::Isolate;
use anyhow::{anyhow, Result};
use log::{warn, debug};
use matrix_sdk::ruma::{OwnedEventId, OwnedRoomId};
use matrix_sdk::{event_handler::{EventHandlerDropGuard, EventHandlerHandle}, room::Room as MatrixRoom};
use once_cell::sync::Lazy;
use serde::Serialize;
use tokio::sync::{Mutex as AsyncMutex, RwLock as AsyncRwLock};
use tokio_util::sync::CancellationToken;

use crate::client;

static CONTROLLERS: Lazy<AsyncRwLock<HashMap<String, Arc<PresenceController>>>> =
    Lazy::new(|| AsyncRwLock::new(HashMap::new()));
static RECEIPT_HANDLER: Lazy<AsyncMutex<Option<EventHandlerHandle>>> =
    Lazy::new(|| AsyncMutex::new(None));

#[derive(Debug, Clone, Serialize)]
pub struct PresenceAck { pub ok: bool }

#[derive(Debug, Clone, Serialize)]
struct PresenceSnapshotPayload {
    kind: &'static str,
    room_id: String,
    typing: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
struct ReceiptUpdatePayload {
    kind: &'static str,
    room_id: String,
    event_id: String,
    user_ids: Vec<String>,
}

pub async fn register_presence_listener(handle: &str, room_id: &str, port: i64) -> Result<PresenceAck> {
    let room_id: OwnedRoomId = room_id
        .try_into()
        .map_err(|err| anyhow!("invalid room id '{room_id}': {err}"))?;

    let key = format!("{handle}::{room_id}");
    let mut controllers = CONTROLLERS.write().await;

    let controller = if let Some(controller) = controllers.get(&key) {
        controller.clone()
    } else {
        PresenceController::new(room_id.clone()).await?
    };

    controllers.insert(key, controller.clone());
    controller.register_listener(port).await?;

    // Ensure a single global receipt handler is registered
    ensure_receipt_handler().await;
    Ok(PresenceAck { ok: true })
}

/// Called by other modules (e.g., read-receipts) to notify presence listeners.
pub async fn notify_receipt(room_id: &OwnedRoomId, event_id: &OwnedEventId, user_id: &str) {
    // Broadcast to all controllers that match this room id (across handles)
    let controllers = CONTROLLERS.read().await;
    for controller in controllers.values() {
        if controller.room_id.as_str() == room_id.as_str() {
            controller.broadcast_receipt(event_id.as_str(), user_id).await;
        }
    }
}

pub async fn reset_all() {
    let mut controllers = CONTROLLERS.write().await;
    for controller in controllers.values() {
        controller.shutdown();
    }
    controllers.clear();
    // Drop global receipt handler
    if let Some(handle) = RECEIPT_HANDLER.lock().await.take() {
        drop(handle);
    }
}

struct PresenceController {
    room_id: OwnedRoomId,
    listeners: AsyncMutex<HashSet<i64>>,
    cancel_token: CancellationToken,
    typing_guard: AsyncMutex<Option<EventHandlerDropGuard>>,
    last_typing: AsyncMutex<Vec<String>>,
}

impl PresenceController {
    async fn new(room_id: OwnedRoomId) -> Result<Arc<Self>> {
        let controller = Arc::new(Self {
            room_id,
            listeners: AsyncMutex::new(HashSet::new()),
            cancel_token: CancellationToken::new(),
            typing_guard: AsyncMutex::new(None),
            last_typing: AsyncMutex::new(Vec::new()),
        });

        // Attach typing notifications subscription for this room if possible.
        controller.attach_typing().await.ok();
        Ok(controller)
    }

    async fn register_listener(&self, port: i64) -> Result<()> {
        self.listeners.lock().await.insert(port);
        // Emit a small ready marker to mirror other streams' UX
        let ready = serde_json::to_string(&serde_json::json!({ "kind": "presence_ready" }))?;
        if !Self::post_to_port(port, ready) {
            self.listeners.lock().await.remove(&port);
        }

        // Emit a snapshot of the latest known typing list.
        let typing = self.fetch_typing().await.unwrap_or_default();
        let payload = PresenceSnapshotPayload {
            kind: "presence_snapshot",
            room_id: self.room_id.as_str().to_owned(),
            typing,
        };
        let json = serde_json::to_string(&payload)?;
        if !Self::post_to_port(port, json) {
            self.listeners.lock().await.remove(&port);
        }
        Ok(())
    }

    async fn fetch_typing(&self) -> Result<Vec<String>> {
        Ok(self.last_typing.lock().await.clone())
    }

    async fn broadcast_receipt(&self, event_id: &str, user_id: &str) {
        let payload = ReceiptUpdatePayload {
            kind: "receipt_update",
            room_id: self.room_id.as_str().to_owned(),
            event_id: event_id.to_owned(),
            user_ids: vec![user_id.to_owned()],
        };
        if let Ok(json) = serde_json::to_string(&payload) {
            let mut listeners = self.listeners.lock().await;
            let mut stale = Vec::new();
            for &port in listeners.iter() {
                if !Self::post_to_port(port, json.clone()) {
                    warn!("failed to post presence receipt update to port {port}");
                    stale.push(port);
                }
            }
            for port in stale {
                listeners.remove(&port);
            }
        }
    }

    fn post_to_port(port: i64, payload: String) -> bool {
        Isolate::new(port).post(payload)
    }

    fn shutdown(&self) {
        self.cancel_token.cancel();
    }

    async fn attach_typing(self: &Arc<Self>) -> Result<()> {
        let Some(client) = client() else { return Ok(()); };
        let Some(room) = client.get_room(&self.room_id) else { return Ok(()); };
        let (guard, mut rx) = room.subscribe_to_typing_notifications();
        {
            *self.typing_guard.lock().await = Some(guard);
        }
        let room_id = self.room_id.clone();
        let cancel = self.cancel_token.clone();
        let controller = Arc::clone(self);
        tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = cancel.cancelled() => {
                        debug!("presence typing loop cancelled for {}", room_id);
                        break;
                    }
                    res = rx.recv() => {
                        match res {
                            Ok(user_ids) => {
                                controller.update_and_broadcast_typing(user_ids.into_iter().map(|u| u.to_string()).collect()).await;
                            }
                            Err(_) => break,
                        }
                    }
                }
            }
        });
        Ok(())
    }
}

impl PresenceController {
    async fn update_and_broadcast_typing(&self, typing: Vec<String>) {
        {
            let mut guard = self.last_typing.lock().await;
            *guard = typing.clone();
        }
        let payload = PresenceSnapshotPayload {
            kind: "presence_snapshot",
            room_id: self.room_id.as_str().to_owned(),
            typing,
        };
        if let Ok(json) = serde_json::to_string(&payload) {
            let mut listeners = self.listeners.lock().await;
            let mut stale = Vec::new();
            for &port in listeners.iter() {
                if !Isolate::new(port).post(json.clone()) {
                    stale.push(port);
                }
            }
            for port in stale { listeners.remove(&port); }
        }
    }
}

async fn ensure_receipt_handler() {
    if RECEIPT_HANDLER.lock().await.is_some() { return; }
    let Some(client) = client() else { return; };
    use matrix_sdk::ruma::events::receipt::{SyncReceiptEvent, ReceiptType};
    let handle = client.add_event_handler(|ev: SyncReceiptEvent, room: MatrixRoom| async move {
        // Broadcast read receipts to all controllers for this room
        let controllers = CONTROLLERS.read().await;
        let room_id = room.room_id().to_owned();
        for (event_id, per_type) in ev.content.0.iter() {
            if let Some(users_map) = per_type.get(&ReceiptType::Read) {
                // Filter out self
                let mut user_ids: Vec<String> = Vec::new();
                if let Some(me) = room.client().user_id() {
                    for uid in users_map.keys() {
                        if uid != me {
                            user_ids.push(uid.to_string());
                        }
                    }
                } else {
                    user_ids.extend(users_map.keys().map(|u| u.to_string()));
                }
                if user_ids.is_empty() { continue; }
                for controller in controllers.values() {
                    if controller.room_id.as_str() == room_id.as_str() {
                        // Send full user list for this event
                        let payload = ReceiptUpdatePayload {
                            kind: "receipt_update",
                            room_id: room_id.as_str().to_owned(),
                            event_id: event_id.as_str().to_owned(),
                            user_ids: user_ids.clone(),
                        };
                        if let Ok(json) = serde_json::to_string(&payload) {
                            let mut listeners = controller.listeners.lock().await;
                            let mut stale = Vec::new();
                            for &port in listeners.iter() {
                                if !Isolate::new(port).post(json.clone()) {
                                    stale.push(port);
                                }
                            }
                            for port in stale { listeners.remove(&port); }
                        }
                    }
                }
            }
        }
    });
    *RECEIPT_HANDLER.lock().await = Some(handle);
}
