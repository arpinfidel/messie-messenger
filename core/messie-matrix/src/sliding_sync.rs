use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
};

use allo_isolate::Isolate;
use anyhow::{anyhow, Context, Result};
use futures::{future, StreamExt};
use log::{debug, warn};
use matrix_sdk::ruma::{events::StateEventType, OwnedRoomId};
use matrix_sdk::{
    sliding_sync::{SlidingSync, SlidingSyncList, SlidingSyncMode, UpdateSummary, Version},
    Client, Room, RoomDisplayName, RoomState,
};
use once_cell::sync::Lazy;
use serde::Serialize;
use tokio::sync::{mpsc, Mutex as AsyncMutex, RwLock as AsyncRwLock};
use tokio_util::sync::CancellationToken;

use crate::{client, runtime};

/// Global registry storing active sliding sync controllers, keyed by the handle
/// provided by Flutter.
static CONTROLLERS: Lazy<AsyncRwLock<HashMap<String, Arc<SlidingSyncController>>>> =
    Lazy::new(|| AsyncRwLock::new(HashMap::new()));

/// Configuration payload for starting or updating a sliding sync controller.
#[derive(Debug, Clone, Copy)]
pub struct SlidingSyncConfig {
    pub hp_size: u32,
    pub lp_batch: u32,
    pub hp_timeline: u32,
    pub lp_timeline: u32,
}

#[derive(Debug, Clone, Serialize)]
pub struct StartSlidingSyncResponse {
    pub started: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct AckResponse {
    pub ok: bool,
}

/// Register or update a sliding sync controller for the current Matrix client.
pub async fn start_sliding_sync(
    handle: &str,
    config: SlidingSyncConfig,
) -> Result<StartSlidingSyncResponse> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let mut write_guard = CONTROLLERS.write().await;

    if let Some(controller) = write_guard.get(handle) {
        controller.update_config(config).await?;
        return Ok(StartSlidingSyncResponse { started: false });
    }

    let controller = SlidingSyncController::create(handle.to_owned(), client, config).await?;
    write_guard.insert(handle.to_owned(), controller);

    Ok(StartSlidingSyncResponse { started: true })
}

/// Subscribe a Dart `SendPort` to receive room list updates.
pub async fn register_room_list_listener(handle: &str, port: i64) -> Result<AckResponse> {
    let controllers = CONTROLLERS.read().await;
    let controller = controllers
        .get(handle)
        .cloned()
        .ok_or_else(|| anyhow!("Sliding sync '{handle}' has not been started"))?;

    controller.register_listener(port).await?;
    Ok(AckResponse { ok: true })
}

/// Update the high priority pinned rooms and trigger a recompute.
pub async fn set_hp_rooms(handle: &str, rooms: Vec<String>) -> Result<AckResponse> {
    let controllers = CONTROLLERS.read().await;
    let controller = controllers
        .get(handle)
        .cloned()
        .ok_or_else(|| anyhow!("Sliding sync '{handle}' has not been started"))?;

    controller.set_pinned_hp_rooms(rooms).await?;
    Ok(AckResponse { ok: true })
}

/// Request the controller to grow the LP window by the configured batch size.
pub async fn subscribe_more_lp(handle: &str) -> Result<AckResponse> {
    let controllers = CONTROLLERS.read().await;
    let controller = controllers
        .get(handle)
        .cloned()
        .ok_or_else(|| anyhow!("Sliding sync '{handle}' has not been started"))?;

    controller.expand_lp_window().await?;
    Ok(AckResponse { ok: true })
}

/// Force the controller to expire the current session position and rehydrate.
pub async fn resubscribe_all(handle: &str) -> Result<AckResponse> {
    let controllers = CONTROLLERS.read().await;
    let controller = controllers
        .get(handle)
        .cloned()
        .ok_or_else(|| anyhow!("Sliding sync '{handle}' has not been started"))?;

    controller.force_resubscribe().await?;
    Ok(AckResponse { ok: true })
}

/// Tear down all active sliding sync controllers. Invoked on logout.
pub async fn reset_all() {
    let mut controllers = CONTROLLERS.write().await;
    for controller in controllers.values() {
        controller.shutdown();
    }
    controllers.clear();
}

/// Internal commands sent to the background task driving the sliding sync loop.
#[derive(Debug)]
enum Command {
    Recompute,
    Resubscribe,
}

/// Primary state holder for a sliding sync instance.
struct SlidingSyncController {
    handle: String,
    client: Arc<Client>,
    sliding_sync: SlidingSync,
    config: AsyncMutex<ControllerConfig>,
    pinned_hp: AsyncRwLock<Vec<OwnedRoomId>>,
    snapshot: AsyncMutex<RoomListSnapshot>,
    listeners: AsyncMutex<HashSet<i64>>, // keyed by port
    command_tx: mpsc::UnboundedSender<Command>,
    cancel_token: CancellationToken,
}

#[derive(Debug, Clone)]
struct ControllerConfig {
    hp_size: u32,
    lp_batch: u32,
    hp_timeline: u32,
    lp_timeline: u32,
    lp_window: u32,
}

#[derive(Debug, Default, Clone)]
struct RoomListSnapshot {
    hp: Vec<RoomSummary>,
    lp: Vec<RoomSummary>,
    lp_total: usize,
}

#[derive(Debug, Clone, PartialEq)]
struct RoomSummary {
    room_id: OwnedRoomId,
    item: RoomListItem,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
struct RoomListItem {
    room_id: String,
    name: String,
    avatar_url: Option<String>,
    bump_ts: Option<u64>,
    notification_count: u64,
    highlight_count: u64,
    is_marked_unread: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "lowercase")]
enum RoomListKind {
    Hp,
    Lp,
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "op", rename_all = "SCREAMING_SNAKE_CASE")]
enum RoomListOp {
    Insert { index: u32, item: RoomListItem },
    Update { index: u32, item: RoomListItem },
    Remove { index: u32 },
    Reorder { from: u32, to: u32 },
}

#[derive(Debug, Clone, Serialize)]
struct RoomListUpdate {
    list: RoomListKind,
    ops: Vec<RoomListOp>,
}

#[derive(Debug, Clone, Serialize)]
struct RoomListEnvelope {
    kind: &'static str,
    hp_size: u32,
    lp_window: u32,
    lp_total: usize,
    updates: Vec<RoomListUpdate>,
}

impl SlidingSyncController {
    async fn create(
        handle: String,
        client: Arc<Client>,
        config: SlidingSyncConfig,
    ) -> Result<Arc<Self>> {
        let sliding_sync = Self::build_sliding_sync(&client, &handle, config).await?;

        let controller_config = ControllerConfig {
            hp_size: config.hp_size.max(1),
            lp_batch: config.lp_batch.max(1),
            hp_timeline: config.hp_timeline.max(1),
            lp_timeline: config.lp_timeline.max(1),
            lp_window: config.lp_batch.max(1),
        };

        let (command_tx, command_rx) = mpsc::unbounded_channel();
        let cancel_token = CancellationToken::new();

        let controller = Arc::new(Self {
            handle,
            client,
            sliding_sync,
            config: AsyncMutex::new(controller_config),
            pinned_hp: AsyncRwLock::new(Vec::new()),
            snapshot: AsyncMutex::new(RoomListSnapshot::default()),
            listeners: AsyncMutex::new(HashSet::new()),
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
                    Some(cmd) = command_rx.recv() => {
                        if let Err(err) = controller.handle_command(cmd).await {
                            warn!("sliding sync '{}' command failed: {err:?}", controller.handle);
                        }
                    }
                    Some(result) = stream.next() => {
                        match result {
                            Ok(summary) => {
                                if let Err(err) = controller.handle_update(summary).await {
                                    warn!("sliding sync '{}' update handling failed: {err:?}", controller.handle);
                                }
                            }
                            Err(err) => {
                                warn!("sliding sync '{}' stream error: {err:?}", controller.handle);
                                let message = err.to_string();
                                if message.contains("Unknown pos") {
                                    if let Err(err) = controller.handle_command(Command::Resubscribe).await {
                                        warn!("failed to resubscribe sliding sync '{}': {err:?}", controller.handle);
                                    }
                                }
                            }
                        }
                    }
                    else => break,
                }
            }
        });
    }

    async fn handle_command(&self, cmd: Command) -> Result<()> {
        match cmd {
            Command::Recompute => {
                self.recompute_and_publish().await?;
            }
            Command::Resubscribe => {
                self.sliding_sync.expire_session().await;
                self.recompute_and_publish().await?;
            }
        }
        Ok(())
    }

    async fn handle_update(&self, _summary: UpdateSummary) -> Result<()> {
        self.recompute_and_publish().await
    }

    async fn update_config(&self, new_config: SlidingSyncConfig) -> Result<()> {
        {
            let mut config = self.config.lock().await;
            config.hp_size = new_config.hp_size.max(1);
            config.lp_batch = new_config.lp_batch.max(1);
            config.hp_timeline = new_config.hp_timeline.max(1);
            config.lp_timeline = new_config.lp_timeline.max(1);
            if config.lp_window < config.lp_batch {
                config.lp_window = config.lp_batch;
            }
        }

        // Update list parameters.
        let config = self.config.lock().await.clone();
        let hp_size = config.hp_size;
        let hp_timeline = config.hp_timeline;
        if let Some(_) = self
            .sliding_sync
            .on_list("hp", move |list: &SlidingSyncList| {
                list.set_sync_mode(Self::hp_sync_mode(hp_size));
                list.set_timeline_limit(hp_timeline);
                future::ready(())
            })
            .await
        {
            debug!("updated HP list configuration for '{}'", self.handle);
        }

        let lp_batch = config.lp_batch;
        let lp_timeline = config.lp_timeline;
        if let Some(_) = self
            .sliding_sync
            .on_list("lp", move |list: &SlidingSyncList| {
                list.set_sync_mode(SlidingSyncMode::new_growing(lp_batch));
                list.set_timeline_limit(lp_timeline);
                future::ready(())
            })
            .await
        {
            debug!("updated LP list configuration for '{}'", self.handle);
        }

        self.enqueue(Command::Recompute);
        Ok(())
    }

    async fn register_listener(&self, port: i64) -> Result<()> {
        let mut listeners = self.listeners.lock().await;
        listeners.insert(port);

        // Emit the latest snapshot immediately.
        self.emit_current_snapshot_to(port).await
    }

    async fn set_pinned_hp_rooms(&self, room_ids: Vec<String>) -> Result<()> {
        let mut parsed = Vec::new();
        for room in room_ids {
            let owned = OwnedRoomId::try_from(room.as_str())
                .map_err(|err| anyhow!("invalid room id '{room}': {err}"))?;
            if !parsed.contains(&owned) {
                parsed.push(owned);
            }
        }

        *self.pinned_hp.write().await = parsed;
        self.enqueue(Command::Recompute);
        Ok(())
    }

    async fn expand_lp_window(&self) -> Result<()> {
        {
            let mut cfg = self.config.lock().await;
            cfg.lp_window = cfg.lp_window.saturating_add(cfg.lp_batch);
        }
        self.enqueue(Command::Recompute);
        Ok(())
    }

    async fn force_resubscribe(&self) -> Result<()> {
        self.enqueue(Command::Resubscribe);
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

    async fn emit_current_snapshot_to(&self, port: i64) -> Result<()> {
        let cfg = self.config.lock().await.clone();
        let snapshot = self.snapshot.lock().await.clone();
        let envelope = RoomListEnvelope {
            kind: "room_list",
            hp_size: cfg.hp_size,
            lp_window: cfg.lp_window,
            lp_total: snapshot.lp_total,
            updates: vec![
                RoomListUpdate {
                    list: RoomListKind::Hp,
                    ops: Self::compute_diff(&[], &snapshot.hp),
                },
                RoomListUpdate {
                    list: RoomListKind::Lp,
                    ops: Self::compute_diff(&[], &snapshot.lp),
                },
            ],
        };

        if envelope.updates.iter().all(|update| update.ops.is_empty()) {
            return Ok(());
        }

        let payload = serde_json::to_string(&envelope)?;
        if !Self::post_to_port(port, payload) {
            warn!("failed to post initial snapshot to port {port}");
            self.listeners.lock().await.remove(&port);
        }
        Ok(())
    }

    async fn recompute_and_publish(&self) -> Result<()> {
        let snapshot = self.build_snapshot().await?;
        let cfg = self.config.lock().await.clone();

        let mut state_guard = self.snapshot.lock().await;
        let hp_ops = Self::compute_diff(&state_guard.hp, &snapshot.hp);
        let lp_ops = Self::compute_diff(&state_guard.lp, &snapshot.lp);

        if hp_ops.is_empty() && lp_ops.is_empty() {
            *state_guard = snapshot;
            return Ok(());
        }

        let updates = vec![
            RoomListUpdate {
                list: RoomListKind::Hp,
                ops: hp_ops,
            },
            RoomListUpdate {
                list: RoomListKind::Lp,
                ops: lp_ops,
            },
        ];

        *state_guard = snapshot.clone();
        drop(state_guard);

        let envelope = RoomListEnvelope {
            kind: "room_list",
            hp_size: cfg.hp_size,
            lp_window: cfg.lp_window,
            lp_total: snapshot.lp_total,
            updates,
        };

        let payload = serde_json::to_string(&envelope)?;
        let mut listeners = self.listeners.lock().await;
        let mut stale = Vec::new();
        for &port in listeners.iter() {
            if !Self::post_to_port(port, payload.clone()) {
                warn!("failed to post update to port {port}");
                stale.push(port);
            }
        }
        for port in stale {
            listeners.remove(&port);
        }

        Ok(())
    }

    async fn build_snapshot(&self) -> Result<RoomListSnapshot> {
        let cfg = self.config.lock().await.clone();
        let pinned = self.pinned_hp.read().await.clone();

        let mut rooms = self.client.rooms();
        rooms.retain(|room| matches!(room.state(), RoomState::Joined | RoomState::Invited));

        let mut summaries = Vec::new();
        for room in rooms {
            summaries.push(Self::build_room_summary(&room).await?);
        }

        summaries.sort_by(|a, b| {
            b.item
                .bump_ts
                .cmp(&a.item.bump_ts)
                .then(a.item.room_id.cmp(&b.item.room_id))
        });

        let pinned_lookup: HashSet<OwnedRoomId> = pinned.iter().cloned().collect();
        let mut hp_list = Vec::new();

        // Add pinned rooms first, preserving provided order.
        for room_id in &pinned {
            if let Some(pos) = summaries.iter().position(|entry| entry.room_id == *room_id) {
                hp_list.push(summaries.remove(pos));
            }
        }

        while hp_list.len() < cfg.hp_size as usize && !summaries.is_empty() {
            hp_list.push(summaries.remove(0));
        }

        // Remaining rooms form the LP pool.
        let lp_total = summaries.len();
        let lp_window = cfg.lp_window as usize;
        let mut lp_list = summaries.into_iter().take(lp_window).collect::<Vec<_>>();

        // Remove pinned duplicates from LP list if any remain due to window growth.
        lp_list.retain(|entry| !pinned_lookup.contains(&entry.room_id));

        Ok(RoomListSnapshot {
            hp: hp_list,
            lp: lp_list,
            lp_total,
        })
    }

    async fn build_room_summary(room: &Room) -> Result<RoomSummary> {
        let room_id = room.room_id().to_owned();

        let display_name = match room.display_name().await {
            Ok(RoomDisplayName::Named(name))
            | Ok(RoomDisplayName::Calculated(name))
            | Ok(RoomDisplayName::Aliased(name))
            | Ok(RoomDisplayName::EmptyWas(name)) => name,
            Ok(RoomDisplayName::Empty) => room
                .canonical_alias()
                .map(|alias| alias.to_string())
                .unwrap_or_else(|| room_id.as_str().to_owned()),
            Err(err) => {
                warn!("failed to resolve display name for {}: {err:?}", room_id);
                room_id.as_str().to_owned()
            }
        };

        let avatar_url = room.avatar_url().map(|url| url.to_string());
        let bump_ts = room.recency_stamp();
        let notification_counts = room.unread_notification_counts();
        let is_marked_unread = room.is_marked_unread();

        Ok(RoomSummary {
            room_id: room_id.clone(),
            item: RoomListItem {
                room_id: room_id.as_str().to_owned(),
                name: display_name,
                avatar_url,
                bump_ts,
                notification_count: notification_counts.notification_count,
                highlight_count: notification_counts.highlight_count,
                is_marked_unread,
            },
        })
    }

    fn compute_diff(previous: &[RoomSummary], next: &[RoomSummary]) -> Vec<RoomListOp> {
        let mut ops = Vec::new();
        let mut working: Vec<RoomSummary> = previous.to_vec();

        let next_ids: HashSet<&OwnedRoomId> = next.iter().map(|item| &item.room_id).collect();
        let mut index = working.len();
        while index > 0 {
            index -= 1;
            if !next_ids.contains(&working[index].room_id) {
                working.remove(index);
                ops.push(RoomListOp::Remove {
                    index: index as u32,
                });
            }
        }

        for (desired_index, desired) in next.iter().cloned().enumerate() {
            match working
                .iter()
                .position(|entry| entry.room_id == desired.room_id)
            {
                Some(current_index) => {
                    if current_index != desired_index {
                        let entry = working.remove(current_index);
                        working.insert(desired_index, entry);
                        ops.push(RoomListOp::Reorder {
                            from: current_index as u32,
                            to: desired_index as u32,
                        });
                    }

                    if working[desired_index] != desired {
                        working[desired_index] = desired.clone();
                        ops.push(RoomListOp::Update {
                            index: desired_index as u32,
                            item: desired.item.clone(),
                        });
                    }
                }
                None => {
                    working.insert(desired_index, desired.clone());
                    ops.push(RoomListOp::Insert {
                        index: desired_index as u32,
                        item: desired.item.clone(),
                    });
                }
            }
        }

        ops
    }

    fn post_to_port(port: i64, payload: String) -> bool {
        Isolate::new(port).post(payload)
    }

    fn hp_sync_mode(hp_size: u32) -> SlidingSyncMode {
        if hp_size == 0 {
            return SlidingSyncMode::new_selective().into();
        }
        SlidingSyncMode::new_selective()
            .add_range(0..=hp_size.saturating_sub(1))
            .into()
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
            .with_all_extensions();

        let required_state = vec![
            (StateEventType::RoomName, "".to_owned()),
            (StateEventType::RoomAvatar, "".to_owned()),
            (StateEventType::RoomCanonicalAlias, "".to_owned()),
        ];

        let hp_list = SlidingSyncList::builder("hp")
            .sync_mode(Self::hp_sync_mode(config.hp_size.max(1)))
            .timeline_limit(config.hp_timeline.max(1))
            .required_state(required_state.clone());

        let lp_list = SlidingSyncList::builder("lp")
            .sync_mode(SlidingSyncMode::new_growing(config.lp_batch.max(1)))
            .timeline_limit(config.lp_timeline.max(1))
            .required_state(required_state);

        let builder = builder.add_list(hp_list).add_list(lp_list);

        builder
            .build()
            .await
            .context("failed to build sliding sync instance")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn summary(id: &str, bump_ts: Option<u64>) -> RoomSummary {
        RoomSummary {
            room_id: id.try_into().unwrap(),
            item: RoomListItem {
                room_id: id.to_owned(),
                name: id.to_owned(),
                avatar_url: None,
                bump_ts,
                notification_count: 0,
                highlight_count: 0,
                is_marked_unread: false,
            },
        }
    }

    #[test]
    fn compute_diff_handles_insert_update_remove() {
        let prev = vec![
            summary("!a:example", Some(10)),
            summary("!b:example", Some(9)),
        ];
        let next = vec![
            summary("!b:example", Some(12)),
            summary("!c:example", Some(8)),
        ];

        let ops = SlidingSyncController::compute_diff(&prev, &next);
        assert_eq!(ops.len(), 4);
        matches!(
            ops[0],
            RoomListOp::Remove { index: 0 } | RoomListOp::Remove { index: 1 }
        );
    }
}
