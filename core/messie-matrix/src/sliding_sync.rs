use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
};

use allo_isolate::Isolate;
use anyhow::{anyhow, Context, Result};
use futures::StreamExt;
use log::{debug, warn};
use matrix_sdk::{
    sliding_sync::{SlidingSync, SlidingSyncList, SlidingSyncMode, UpdateSummary, Version},
    Client,
};
use matrix_sdk::ruma::assign;
use matrix_sdk::ruma::api::client::sync::sync_events::v5 as http;
use once_cell::sync::Lazy;
use serde::Serialize;
use tokio::sync::{mpsc, Mutex as AsyncMutex, RwLock as AsyncRwLock};
use tokio_util::sync::CancellationToken;

use crate::{client, runtime};

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
        });

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

    async fn register_listener(&self, port: i64) -> Result<()> {
        self.listeners.lock().await.insert(port);
        let ready = serde_json::to_string(&serde_json::json!({ "kind": "sliding_sync_ready" }))?;
        if !Self::post_to_port(port, ready) {
            self.listeners.lock().await.remove(&port);
        }
        // Also emit a lightweight snapshot so late subscribers don't block
        // waiting for the next server-side diff.
        let rooms: Vec<String> = self.room_ids().await;
        let snapshot = SlidingSyncUpdate {
            kind: "sliding_sync_update",
            lists: vec!["all".to_string()],
            rooms,
        };
        let json = serde_json::to_string(&snapshot)?;
        if !Self::post_to_port(port, json) {
            self.listeners.lock().await.remove(&port);
        }
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

    async fn publish_summary(&self, summary: UpdateSummary) -> Result<()> {
        let UpdateSummary { lists, rooms } = summary;
        let rooms: Vec<String> = rooms.into_iter().map(|room| room.to_string()).collect();

        if !rooms.is_empty() {
            let mut known = self.room_ids.write().await;
            for room in &rooms {
                known.insert(room.clone());
            }
        }

        let update = SlidingSyncUpdate {
            kind: "sliding_sync_update",
            lists,
            rooms: rooms.clone(),
        };
        self.broadcast(update).await
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

    async fn build_sliding_sync(
        client: &Client,
        handle: &str,
        config: SlidingSyncConfig,
    ) -> Result<SlidingSync> {
        let builder = client
            .sliding_sync(handle)
            .context("failed to initialise sliding sync builder")?
            .version(Version::Native)
            // Recommended extensions so unread counts, account data and crypto
            // updates propagate correctly.
            .with_to_device_extension(assign!(http::request::ToDevice::default(), { enabled: Some(true) }))
            .with_e2ee_extension(assign!(http::request::E2EE::default(), { enabled: Some(true) }))
            .with_account_data_extension(assign!(http::request::AccountData::default(), { enabled: Some(true) }))
            // Receipts are optional but recommended (read-state UX/diagnostics)
            .with_receipt_extension(assign!(http::request::Receipts::default(), { enabled: Some(true) }));

        let list = SlidingSyncList::builder("all")
            .sync_mode(SlidingSyncMode::new_growing(config.lp_batch.max(1)))
            .timeline_limit(config.lp_timeline.max(1))
            .required_state(vec![
                ("m.room.name".into(), "".to_string()),
                ("m.room.avatar".into(), "".to_string()),
                ("m.room.encryption".into(), "".to_string()),
                ("com.beeper.room_type".into(), "".to_string()),
                ("com.beeper.room_type.v2".into(), "".to_string()),
            ]);

        builder
            .add_list(list)
            .build()
            .await
            .context("failed to build sliding sync instance")
    }
}

pub async fn subscribe_rooms(handle: &str, room_ids: Vec<String>, reset: bool) -> Result<AckResponse> {
    use matrix_sdk::ruma::OwnedRoomId;

    let controllers = CONTROLLERS.read().await;
    let controller = controllers
        .get(handle)
        .cloned()
        .ok_or_else(|| anyhow!("Sliding sync '{handle}' has not been started"))?;

    // Parse and convert to the shape expected by the SDK method.
    let parsed: Result<Vec<OwnedRoomId>> = room_ids
        .into_iter()
        .map(|rid| rid.parse::<OwnedRoomId>().map_err(|e| anyhow!("invalid room id '{rid}': {e}")))
        .collect();
    let owned = parsed?;
    let refs: Vec<_> = owned.iter().map(|rid| rid.as_ref()).collect();

    controller.sliding_sync.subscribe_to_rooms(&refs, None, reset);
    Ok(AckResponse { ok: true })
}
