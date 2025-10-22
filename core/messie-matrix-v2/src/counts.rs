use crate::common::handle_registry::Handle;
use crate::common::{post_to_port, runtime::runtime};
use crate::client::CLIENTS;
use matrix_sdk::RoomState;
use std::collections::HashSet;
use std::sync::Arc;

/// Start a global unread counts stream.
/// Emits an initial counts_update snapshot for all joined rooms, then
/// forwards updates from Room::subscribe_to_updates for each joined room.
/// Returns false if the client handle is unknown.
pub fn room_counts_stream(handle: Handle, port: i64) -> bool {
    let entry = { let reg = CLIENTS.read().ok(); reg.and_then(|r| r.get(handle).cloned()) };
    let Some(entry) = entry else { return false; };
    let runtime = runtime();
    let _guard = runtime.enter();

    let client = entry.client.clone();
    runtime.spawn(async move {
        // Track rooms we already subscribed to
        let subscribed: Arc<tokio::sync::Mutex<HashSet<String>>> = Arc::new(tokio::sync::Mutex::new(HashSet::new()));

        // Helper to emit a snapshot and subscribe to updates for a room
        let subscribe_room = |room: matrix_sdk::room::Room, port_copy: i64, subscribed: Arc<tokio::sync::Mutex<HashSet<String>>>| async move {
            let rid = room.room_id().to_string();
            // Send immediate snapshot
            let mut notif = std::cmp::max(room.num_unread_notifications(), room.num_unread_messages());
            let mut mentions = room.num_unread_mentions();
            if notif == 0 || mentions == 0 {
                let srv = room.unread_notification_counts();
                if notif == 0 { notif = srv.notification_count; }
                if mentions == 0 { mentions = srv.highlight_count; }
            }
            let dto = serde_json::json!({
                "kind": "counts_update",
                "room_id": rid,
                "notification_count": notif,
                "highlight_count": mentions,
            });
            let json = serde_json::to_string(&dto).unwrap_or_else(|_| "{}".to_string());
            if !post_to_port(port_copy, json) { return; }

            // Subscribe to updates and also poll periodically to catch count changes
            let mut rx = room.subscribe_to_updates();
            let mut tick = tokio::time::interval(std::time::Duration::from_millis(1200));
            let mut last = (notif, mentions);
            loop {
                tokio::select! {
                    _ = tick.tick() => {},
                    recv = rx.recv() => {
                        if recv.is_err() { break; }
                    }
                }
                let mut n = std::cmp::max(room.num_unread_notifications(), room.num_unread_messages());
                let mut h = room.num_unread_mentions();
                if n == 0 || h == 0 {
                    let srv = room.unread_notification_counts();
                    if n == 0 { n = srv.notification_count; }
                    if h == 0 { h = srv.highlight_count; }
                }
                if (n, h) != last {
                    last = (n, h);
                    let dto = serde_json::json!({
                        "kind": "counts_update",
                        "room_id": room.room_id().to_string(),
                        "notification_count": n,
                        "highlight_count": h,
                    });
                    let json = serde_json::to_string(&dto).unwrap_or_else(|_| "{}".to_string());
                    if !post_to_port(port_copy, json) { break; }
                }
            }
            // On exit remove from subscribed set to allow re-subscription if needed
            let mut set = subscribed.lock().await;
            set.remove(&room.room_id().to_string());
        };

        // Initial pass
        for room in client.rooms() {
            if !matches!(room.state(), RoomState::Joined) { continue; }
            let rid = room.room_id().to_string();
            let mut set = subscribed.lock().await;
            if set.insert(rid.clone()) {
                let room_clone = room.clone();
                let sub_clone = subscribed.clone();
                tokio::spawn(subscribe_room(room_clone, port, sub_clone));
            }
        }

        // Periodically rescan for newly-joined rooms and subscribe
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(2));
        loop {
            interval.tick().await;
            for room in client.rooms() {
                if !matches!(room.state(), RoomState::Joined) { continue; }
                let rid = room.room_id().to_string();
                let mut set = subscribed.lock().await;
                if set.insert(rid.clone()) {
                    let room_clone = room.clone();
                    let sub_clone = subscribed.clone();
                    tokio::spawn(subscribe_room(room_clone, port, sub_clone));
                }
            }
        }
    });

    true
}
