//! Public API exposed to Flutter through the handcrafted bridge layer.

use std::path::Path;

use messie_matrix as matrix;
use serde::Serialize;
use serde_json::json;

/// Returns a "pong" string confirming that the Rust core is reachable from Flutter.
pub fn ping() -> String {
    matrix::ping().expect("ping should never fail")
}

fn to_response_json<T: Serialize>(result: anyhow::Result<T>) -> String {
    match result.and_then(|value| serde_json::to_value(value).map_err(Into::into)) {
        Ok(value) => json!({ "ok": true, "data": value }).to_string(),
        Err(err) => json!({ "ok": false, "error": err.to_string() }).to_string(),
    }
}

/// Initialise the Matrix client from secure storage entries.
pub fn init_client(hs_url: String, base_path: String) -> String {
    to_response_json(matrix::init_client(&hs_url, Path::new(&base_path)))
}

/// Attempt to restore an existing session or login with username/password.
pub fn restore_or_login(
    hs_url: String,
    username: String,
    password: String,
    base_path: String,
) -> String {
    to_response_json(matrix::restore_or_login(
        &hs_url,
        &username,
        &password,
        Path::new(&base_path),
    ))
}

/// Remove all stored credentials and Matrix caches.
pub fn logout(base_path: String) -> String {
    to_response_json(matrix::logout(Path::new(&base_path)))
}

/// Start or update the sliding sync controller for the provided handle.
pub fn start_sliding_sync(
    handle: String,
    hp_size: u32,
    lp_batch: u32,
    hp_timeline: u32,
    lp_timeline: u32,
) -> String {
    let config = matrix::SlidingSyncConfig {
        hp_size,
        lp_batch,
        hp_timeline,
        lp_timeline,
    };
    to_response_json(matrix::start_sliding_sync(&handle, config))
}

/// Register a Dart send port to receive room list updates.
pub fn room_list_stream(handle: String, port: i64) -> String {
    to_response_json(matrix::register_room_list_listener(&handle, port))
}

/// Update the pinned high priority rooms for the sliding sync controller.
pub fn set_hp_rooms(handle: String, rooms_json: String) -> String {
    let rooms: anyhow::Result<Vec<String>> = serde_json::from_str(&rooms_json).map_err(Into::into);
    match rooms {
        Ok(rooms) => to_response_json(matrix::set_hp_rooms(&handle, rooms)),
        Err(err) => to_response_json::<matrix::AckResponse>(Err(err)),
    }
}

/// Request more low priority rooms.
pub fn subscribe_more_lp(handle: String) -> String {
    to_response_json(matrix::subscribe_more_lp(&handle))
}

/// Force a sliding sync resubscribe cycle.
pub fn resubscribe_all(handle: String) -> String {
    to_response_json(matrix::resubscribe_all(&handle))
}
