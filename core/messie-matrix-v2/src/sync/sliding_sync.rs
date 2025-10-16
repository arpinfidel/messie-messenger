use std::collections::HashSet;
use std::sync::Arc;

use anyhow::{anyhow, Result};
use futures::StreamExt;
use matrix_sdk::sliding_sync::{SlidingSync, SlidingSyncList, SlidingSyncMode, UpdateSummary, Version};
use matrix_sdk::ruma::{OwnedRoomId, RoomId, UInt};
use matrix_sdk::ruma::api::client::sync::sync_events::v5 as http;
use serde::Serialize;
use tokio::sync::{mpsc, Mutex as AsyncMutex, RwLock as AsyncRwLock};
use tokio::time::{self, Duration, MissedTickBehavior};

use crate::common::handle_registry::{Handle, Registry};
use crate::common::post_to_port;
use crate::common::runtime::runtime;

use log::warn;
use once_cell::sync::Lazy;

struct SlidingSyncController {
    sliding_sync: SlidingSync,
    listeners: AsyncMutex<HashSet<i64>>, // Dart ports
    room_ids: AsyncRwLock<HashSet<String>>,
    cancel_tx: mpsc::UnboundedSender<()>,
    #[cfg(feature = "test-helpers")]
    updates_count: std::sync::atomic::AtomicU64,
}

static SS_CONTROLLERS: Lazy<std::sync::RwLock<Registry<Arc<SlidingSyncController>>>> =
    Lazy::new(|| std::sync::RwLock::new(Registry::default()));

#[derive(Debug, Serialize)]
struct SlidingSyncReady { kind: &'static str }

#[derive(Debug, Serialize)]
struct SlidingSyncUpdateDto { kind: &'static str, lists: Vec<String>, rooms: Vec<String> }

#[derive(Debug, Serialize)]
struct SlidingSyncErrorDto { kind: &'static str, code: &'static str, message: String }

// Thin typed subscribe/expire helpers and API

fn register_listener(ctrl: &Arc<SlidingSyncController>, port: i64) -> Result<()> {
    let ctrl2 = ctrl.clone();
    let fut = async move {
        ctrl2.listeners.lock().await.insert(port);
        let ready = serde_json::to_string(&SlidingSyncReady { kind: "sliding_sync_ready" })?;
        if !post_to_port(port, ready) {
            ctrl2.listeners.lock().await.remove(&port);
            return Ok::<(), anyhow::Error>(());
        }

        let rooms: Vec<String> = { ctrl2.room_ids.read().await.iter().cloned().collect() };
        let lists = vec!["all".to_string()];
        let snap = serde_json::to_string(&SlidingSyncUpdateDto { kind: "sliding_sync_update", lists, rooms })?;
        if !post_to_port(port, snap) {
            ctrl2.listeners.lock().await.remove(&port);
            return Ok::<(), anyhow::Error>(());
        }
        Ok(())
    };
    runtime().block_on(fut)
}

impl SlidingSyncController {
    async fn broadcast<T: Serialize>(&self, payload: &T) {
        let json = serde_json::to_string(payload).unwrap_or_else(|_| "{}".to_string());
        let mut listeners = self.listeners.lock().await;
        let mut stale = Vec::new();
        for &port in listeners.iter() {
            if !post_to_port(port, json.clone()) {
                warn!("failed to post sliding sync update to port {port}");
                stale.push(port);
            }
        }
        for p in stale { listeners.remove(&p); }
    }
}

#[cfg(feature = "test-helpers")]
#[derive(Debug, Serialize)]
struct TestRooms { rooms: Vec<String> }

#[cfg(feature = "test-helpers")]
pub fn __test_ss_known_rooms(ss: Handle) -> String {
    let ctrl = { let reg = SS_CONTROLLERS.read().expect("ss controllers lock"); reg.get(ss).cloned() };
    let ctrl = match ctrl { Some(c) => c, None => return crate::common::envelope::err_json("unknown_handle", "unknown sliding sync handle") };
    let rooms = runtime().block_on(async { ctrl.room_ids.read().await.iter().cloned().collect::<Vec<_>>() });
    crate::common::envelope::ok_json(TestRooms { rooms })
}

#[cfg(feature = "test-helpers")]
#[derive(Debug, Serialize)]
struct TestUpdateCount { count: u64 }

#[cfg(feature = "test-helpers")]
pub fn __test_ss_update_count(ss: Handle) -> String {
    let ctrl = { let reg = SS_CONTROLLERS.read().expect("ss controllers lock"); reg.get(ss).cloned() };
    let ctrl = match ctrl { Some(c) => c, None => return crate::common::envelope::err_json("unknown_handle", "unknown sliding sync handle") };
    let count = ctrl.updates_count.load(std::sync::atomic::Ordering::Relaxed);
    crate::common::envelope::ok_json(TestUpdateCount { count })
}

// --------- Thin typed helpers for subscribe/expire ---------

pub fn sliding_sync_subscribe_to_rooms(
    ss: Handle,
    room_ids: &[String],
    timeline_limit: Option<u32>,
    required_state: Option<Vec<(String, String)>>,
    cancel_in_flight: bool,
) -> bool {
    let ctrl = { let reg = SS_CONTROLLERS.read().expect("ss controllers lock"); reg.get(ss).cloned() };
    let Some(ctrl) = ctrl else { return false };

    let owned: Vec<OwnedRoomId> = room_ids.iter().filter_map(|s| s.parse::<OwnedRoomId>().ok()).collect();
    if owned.is_empty() { return true; }
    let refs: Vec<&RoomId> = owned.iter().map(|o| o.as_ref()).collect();

    let mut sub = http::request::RoomSubscription::default();
    if let Some(tl) = timeline_limit { sub.timeline_limit = UInt::from(tl.max(1)); }
    let rs = required_state.unwrap_or_else(|| vec![
        ("m.room.name".to_string(), "".to_string()),
        ("m.room.avatar".to_string(), "".to_string()),
        ("m.room.encryption".to_string(), "".to_string()),
    ]);
    sub.required_state = rs.into_iter().map(|(et, sk)| (et.into(), sk)).collect();

    ctrl.sliding_sync.subscribe_to_rooms(&refs, Some(sub), cancel_in_flight);
    true
}

pub fn sliding_sync_expire_session(ss: Handle) -> bool {
    let ctrl = { let reg = SS_CONTROLLERS.read().expect("ss controllers lock"); reg.get(ss).cloned() };
    let Some(ctrl) = ctrl else { return false };
    let rt = runtime();
    let _g = rt.enter();
    rt.block_on(async move { ctrl.sliding_sync.expire_session().await });
    true
}

// ---------------- Thin (typed) API ----------------

#[derive(Clone, Copy, Debug, Default)]
pub struct SlidingSyncConfig {
    pub poll_timeout_ms: u32,
    pub network_timeout_ms: u32,
    pub enable_e2ee: bool,
    pub enable_to_device: bool,
}

/// Create a sliding sync controller from a thin, typed configuration.
/// Returns `Some(handle)` on success, or `None` on failure.
pub fn sliding_sync_create(client: Handle, config: SlidingSyncConfig) -> Option<Handle> {
    let entry = { let reg = crate::client::CLIENTS.read().expect("clients lock"); reg.get(client).cloned() }?;
    let runtime = crate::common::runtime::runtime();
    let _guard = runtime.enter();

    let res = runtime.block_on(async move {
        let id = "thin".to_string();
        let mut builder = entry
            .client
            .sliding_sync(&id)
            .map_err(|e| anyhow!("failed to initialise sliding sync builder: {e}"))?
            .version(Version::Native)
            .with_all_extensions();

        if !config.enable_to_device {
            builder = builder.without_to_device_extension();
        }
        let _ = config.enable_e2ee; // currently covered by with_all_extensions

        if config.poll_timeout_ms > 0 {
            builder = builder.poll_timeout(std::time::Duration::from_millis(config.poll_timeout_ms as u64));
        }
        if config.network_timeout_ms > 0 {
            builder = builder.network_timeout(std::time::Duration::from_millis(config.network_timeout_ms as u64));
        }

        // Minimal default list: growing mode, moderate batch, small timeline.
        let list = SlidingSyncList::builder("all")
            .sync_mode(SlidingSyncMode::new_growing(50))
            .timeline_limit(20);
        builder = builder.add_list(list);

        let sliding_sync = builder.build().await.map_err(|e| anyhow!("failed to build sliding sync: {e}"))?;

        let (cancel_tx, mut cancel_rx) = mpsc::unbounded_channel::<()>();
        let controller = Arc::new(SlidingSyncController {
            sliding_sync,
            listeners: AsyncMutex::new(HashSet::new()),
            room_ids: AsyncRwLock::new(HashSet::new()),
            cancel_tx,
            #[cfg(feature = "test-helpers")]
            updates_count: std::sync::atomic::AtomicU64::new(0),
        });

        let ctrl = controller.clone();
        tokio::spawn(async move {
            let mut stream = Box::pin(ctrl.sliding_sync.sync());
            loop {
                tokio::select! {
                    _ = cancel_rx.recv() => { break; }
                    maybe = stream.next() => {
                        match maybe {
                            Some(Ok(UpdateSummary { lists, rooms })) => {
                                let rooms_vec: Vec<String> = rooms.into_iter().map(|r| r.to_string()).collect();
                                let mut known = ctrl.room_ids.write().await;
                                for r in &rooms_vec { known.insert(r.clone()); }
                                drop(known);
                                let dto = SlidingSyncUpdateDto { kind: "sliding_sync_update", lists, rooms: rooms_vec };
                                ctrl.broadcast(&dto).await;
                                #[cfg(feature = "test-helpers")]
                                { ctrl.updates_count.fetch_add(1, std::sync::atomic::Ordering::Relaxed); }
                            }
                            Some(Err(e)) => {
                                let dto = SlidingSyncErrorDto { kind: "sliding_sync_error", code: "sdk_error", message: format!("{e}") };
                                ctrl.broadcast(&dto).await;
                                ctrl.sliding_sync.expire_session().await;
                            }
                            None => break,
                        }
                    }
                }
            }
        });

        // Heartbeat to keep Dart listeners nudged
        let ctrl2 = controller.clone();
        tokio::spawn(async move {
            let mut interval = time::interval(Duration::from_secs(30));
            interval.set_missed_tick_behavior(MissedTickBehavior::Delay);
            loop {
                interval.tick().await;
                let hb = serde_json::json!({"kind":"heartbeat"});
                ctrl2.broadcast(&hb).await;
            }
        });

        Ok::<Arc<SlidingSyncController>, anyhow::Error>(controller)
    });

    match res {
        Ok(c) => Some(SS_CONTROLLERS.write().expect("ss controllers lock").insert(c)),
        Err(_) => None,
    }
}

pub fn sliding_sync_start_streaming(ss: Handle, port: i64) -> bool {
    let ctrl = { let reg = SS_CONTROLLERS.read().expect("ss controllers lock"); reg.get(ss).cloned() };
    let Some(c) = ctrl else { return false };
    register_listener(&c, port).is_ok()
}

pub fn sliding_sync_stop(ss: Handle) -> bool {
    let ctrl = { let reg = SS_CONTROLLERS.read().expect("ss controllers lock"); reg.get(ss).cloned() };
    let Some(c) = ctrl else { return false };
    let _ = c.cancel_tx.send(());
    true
}
