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
        // Use pretty display to include error context chain for better diagnostics.
        Err(err) => json!({ "ok": false, "error": format!("{:#}", err) }).to_string(),
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

/// Recover encrypted secrets using a recovery key.
pub fn recover_with_key(recovery_key: String) -> String {
    to_response_json(matrix::recover_with_key(&recovery_key))
}

/// Download room keys for a room using the configured backup.
pub fn download_room_keys_for_room(room_id: String) -> String {
    to_response_json(matrix::download_room_keys_for_room(&room_id))
}

/// Dump diagnostic information for a room's crypto state.
pub fn dump_room_crypto(room_id: String) -> String {
    to_response_json(matrix::dump_room_crypto(&room_id))
}

/// Import a recovery key (alias for recover_with_key for FRB naming).
pub fn import_recovery_key(recovery_key: String) -> String {
    to_response_json(matrix::import_recovery_key(&recovery_key))
}

/// Register a Dart send port to receive backup status updates.
pub fn backup_status_stream(handle: String, port: i64) -> String {
    to_response_json(matrix::register_backup_status_listener(&handle, port))
}

/// Query the current backup status (enabled flag and server existence).
pub fn backup_status() -> String {
    to_response_json(matrix::backup_status())
}

/// Attempt to enable online backup. Returns current status; may include a
/// generated recovery key in future.
pub fn enable_online_backup(generate_new: bool) -> String {
    to_response_json(matrix::enable_online_backup(generate_new))
}

/// Export the recovery key for the current account (not yet implemented).
pub fn export_recovery_key() -> String {
    to_response_json(matrix::export_recovery_key())
}

/// Import an existing SSSS recovery key (bech32).
pub fn ssss_import_recovery_key(recovery_key: String) -> String {
    to_response_json(matrix::ssss_import_recovery_key(&recovery_key))
}

/// Bootstrap SSSS (secret storage). On this SDK version this returns a clear
/// error noting that key generation/export isn't available.
pub fn ssss_bootstrap(generate_new_key: bool, passphrase: Option<String>) -> String {
    to_response_json(matrix::ssss_bootstrap(generate_new_key, passphrase.as_deref()))
}

/// Export the SSSS recovery key (not supported on this SDK version).
pub fn ssss_export_recovery_key() -> String {
    to_response_json(matrix::ssss_export_recovery_key())
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

/// Return the list of joined or invited room IDs.
pub fn list_joined_rooms() -> String {
    to_response_json(matrix::list_joined_rooms())
}

/// Fetch overview information for a room by ID.
pub fn room_overview(room_id: String) -> String {
    to_response_json(matrix::room_overview(&room_id))
}

/// Ensure a room timeline controller exists for the handle/room pair.
pub fn open_room(handle: String, room_id: String) -> String {
    to_response_json(matrix::open_room(&handle, &room_id))
}

/// Register a Dart send port for timeline updates.
pub fn timeline_stream(handle: String, room_id: String, port: i64) -> String {
    to_response_json(matrix::register_timeline_listener(&handle, &room_id, port))
}

/// Paginate backwards through the room timeline.
pub fn load_backward(handle: String, room_id: String, limit: u32) -> String {
    to_response_json(matrix::load_backward(&handle, &room_id, limit))
}

/// Send a plain text message to a room, optionally as a reply.
pub fn send_text(room_id: String, body: String, reply_to: Option<String>) -> String {
    to_response_json(matrix::send_text(
        &room_id,
        &body,
        reply_to.as_deref(),
    ))
}

/// Mark read state up to a specific event id in a room.
pub fn mark_read_up_to(room_id: String, event_id: String) -> String {
    to_response_json(matrix::mark_read_up_to(&room_id, &event_id))
}

/// Set local mute state for a room.
pub fn set_room_mute(room_id: String, muted: bool) -> String {
    to_response_json(matrix::set_room_mute(&room_id, muted))
}

/// Convert an MXC URL to a downloadable HTTP URL.
pub fn mxc_to_http(mxc: String, w: Option<u32>, h: Option<u32>) -> String {
    to_response_json(matrix::mxc_to_http(&mxc, w, h))
}

/// Request a SAS verification with a user (and optional device).
pub fn request_sas_verification(user_id: String, device_id: Option<String>) -> String {
    to_response_json(matrix::request_sas_verification(&user_id, device_id.as_deref()))
}

/// Observe SAS verification updates for a given flow id.
pub fn observe_sas(flow_id: String, port: i64) -> String {
    to_response_json(matrix::observe_sas(&flow_id, port))
}

/// Confirm a SAS verification flow.
pub fn confirm_sas(flow_id: String) -> String {
    to_response_json(matrix::confirm_sas(&flow_id))
}

/// Cancel a SAS verification flow.
pub fn cancel_sas(flow_id: String) -> String {
    to_response_json(matrix::cancel_sas(&flow_id))
}

/// Get cross-signing trust state for a user/device.
pub fn trust_state(user_id: String, device_id: Option<String>) -> String {
    to_response_json(matrix::trust_state(&user_id, device_id.as_deref()))
}
