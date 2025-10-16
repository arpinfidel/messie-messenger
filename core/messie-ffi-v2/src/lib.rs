//! FFI layer for Messie v2. Minimal, hand-written C ABI with JSON envelopes.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use allo_isolate::ffi::DartPostCObjectFnType;

#[no_mangle]
pub unsafe extern "C" fn messie_v2_store_dart_post_cobject(ptr: DartPostCObjectFnType) {
    allo_isolate::store_dart_post_cobject(ptr);
}

fn str_from_ptr(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() { return None; }
    let s = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().to_string();
    Some(s)
}

fn to_c_string(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_else(|_| CString::new("{\"ok\":false,\"error\":{\"code\":\"sdk_error\",\"message\":\"invalid utf8\"}}").unwrap()).into_raw()
}

#[no_mangle]
pub extern "C" fn messie_v2_free_string(ptr: *mut c_char) {
    if ptr.is_null() { return; }
    unsafe { let _ = CString::from_raw(ptr); }
}

// ---- v2 Client APIs (thin only) ----

// ---- v2 Client THIN APIs ----

// Unified error codes for v2
#[repr(C)]
#[derive(Copy, Clone)]
pub enum MessieV2Error {
    Success = 0,
    InvalidHandle = 1,
    NetworkTimeout = 2,
    AuthenticationFailed = 3,
    NotFound = 4,
    InvalidArgument = 5,
    Internal = 255,
}

#[allow(dead_code)]
fn err_from_bool(ok: bool) -> MessieV2Error { if ok { MessieV2Error::Success } else { MessieV2Error::Internal } }

#[repr(C)]
pub struct MessieV2ClientCreateResult { pub error: MessieV2Error, pub handle: u64 }

#[repr(C)]
pub struct MessieV2LoginResult { pub error: MessieV2Error, pub user_id: *mut c_char }

// (no extended result variants; error included in base structs)

#[no_mangle]
pub extern "C" fn messie_v2_client_create(hs_url: *const c_char, base_path: *const c_char) -> MessieV2ClientCreateResult {
    let hs = str_from_ptr(hs_url).unwrap_or_default();
    let base = str_from_ptr(base_path).unwrap_or_default();
    match messie_matrix_v2::client_create(&hs, std::path::Path::new(&base)) {
        Some(handle) => MessieV2ClientCreateResult { error: MessieV2Error::Success, handle },
        None => MessieV2ClientCreateResult { error: MessieV2Error::Internal, handle: 0 },
    }
}

#[no_mangle]
pub extern "C" fn messie_v2_client_login(
    handle: u64,
    username: *const c_char,
    password: *const c_char,
) -> MessieV2LoginResult {
    let username = if username.is_null() { None } else { str_from_ptr(username) };
    let password = if password.is_null() { None } else { str_from_ptr(password) };
    match messie_matrix_v2::client_login(handle, username.as_deref(), password.as_deref()) {
        Some(user_id) => MessieV2LoginResult { error: MessieV2Error::Success, user_id: CString::new(user_id).unwrap_or_else(|_| CString::new("").unwrap()).into_raw() },
        None => MessieV2LoginResult { error: MessieV2Error::Internal, user_id: std::ptr::null_mut() },
    }
}

// (removed *_ex client variants)

// Purged JSON Sliding Sync APIs; use typed variants below.

// ---- v2 Sliding Sync THIN (typed) APIs ----

#[repr(C)]
pub struct MessieV2SlidingSyncConfig {
    pub poll_timeout_ms: u32,
    pub network_timeout_ms: u32,
    pub enable_e2ee: bool,
    pub enable_to_device: bool,
}

#[repr(C)]
pub struct MessieV2SlidingSyncHandle(pub u64);

#[repr(C)]
pub struct MessieV2SlidingSyncResult {
    pub error: MessieV2Error,
    pub handle: MessieV2SlidingSyncHandle,
}

// (no extended sliding sync result)

#[no_mangle]
pub extern "C" fn messie_v2_sliding_sync_create(client: u64, config: MessieV2SlidingSyncConfig) -> MessieV2SlidingSyncResult {
    let cfg = messie_matrix_v2::SlidingSyncConfig {
        poll_timeout_ms: config.poll_timeout_ms,
        network_timeout_ms: config.network_timeout_ms,
        enable_e2ee: config.enable_e2ee,
        enable_to_device: config.enable_to_device,
    };
    match messie_matrix_v2::sliding_sync_create(client, cfg) {
        Some(handle) => MessieV2SlidingSyncResult { error: MessieV2Error::Success, handle: MessieV2SlidingSyncHandle(handle) },
        None => MessieV2SlidingSyncResult { error: MessieV2Error::Internal, handle: MessieV2SlidingSyncHandle(0) },
    }
}

#[no_mangle]
pub extern "C" fn messie_v2_sliding_sync_start_streaming(sync: MessieV2SlidingSyncHandle, port: i64) -> bool {
    messie_matrix_v2::sliding_sync_start_streaming(sync.0, port)
}

#[no_mangle]
pub extern "C" fn messie_v2_sliding_sync_stop(sync: MessieV2SlidingSyncHandle) -> bool {
    messie_matrix_v2::sliding_sync_stop(sync.0)
}

#[repr(C)]
pub struct MessieV2StrPair { pub key1: *const c_char, pub key2: *const c_char }

#[no_mangle]
pub extern "C" fn messie_v2_sliding_sync_subscribe_to_rooms(
    ss: u64,
    room_ids_ptr: *const *const c_char,
    room_ids_len: usize,
    has_timeline: bool,
    timeline_limit: u32,
    pairs_ptr: *const MessieV2StrPair,
    pairs_len: usize,
    cancel_in_flight: bool,
) -> bool {
    // Collect room ids
    let mut ids: Vec<String> = Vec::new();
    if !room_ids_ptr.is_null() && room_ids_len > 0 {
        let slice = unsafe { std::slice::from_raw_parts(room_ids_ptr, room_ids_len) };
        for &cstr_ptr in slice.iter() {
            if cstr_ptr.is_null() { continue; }
            let s = unsafe { CStr::from_ptr(cstr_ptr) }.to_string_lossy().to_string();
            if !s.is_empty() { ids.push(s); }
        }
    }

    // Collect required_state pairs if any
    let mut pairs: Vec<(String, String)> = Vec::new();
    if !pairs_ptr.is_null() && pairs_len > 0 {
        let slice = unsafe { std::slice::from_raw_parts(pairs_ptr, pairs_len) };
        for pair in slice.iter() {
            let left = if pair.key1.is_null() { String::new() } else { unsafe { CStr::from_ptr(pair.key1) }.to_string_lossy().to_string() };
            let right = if pair.key2.is_null() { String::new() } else { unsafe { CStr::from_ptr(pair.key2) }.to_string_lossy().to_string() };
            pairs.push((left, right));
        }
    }

    let tl = if has_timeline { Some(timeline_limit) } else { None };
    messie_matrix_v2::sliding_sync_subscribe_to_rooms(ss, &ids, tl, if pairs.is_empty() { None } else { Some(pairs) }, cancel_in_flight)
}

#[no_mangle]
pub extern "C" fn messie_v2_sliding_sync_expire_session(ss: u64) -> bool {
    messie_matrix_v2::sliding_sync_expire_session(ss)
}

// (removed *_ex sliding sync create)
#[no_mangle]
pub extern "C" fn messie_v2_client_sync_once(handle: u64) -> bool {
    // Reuse existing JSON helper but map to bool ack
    let json = messie_matrix_v2::client_sync_once(handle);
    json.contains("\"ok\":true")
}

// ---- v2 Timeline / Messaging APIs (typed only) ----

// Thin (typed) Timeline FFI

#[repr(C)]
pub struct MessieV2TimelineHandle(pub u64);

#[repr(C)]
pub struct MessieV2TimelineResult {
    pub error: MessieV2Error,
    pub handle: MessieV2TimelineHandle,
}

// (no extended timeline result struct)

#[no_mangle]
pub extern "C" fn messie_v2_timeline_open(client: u64, room_id: *const c_char) -> MessieV2TimelineResult {
    let rid = str_from_ptr(room_id).unwrap_or_default();
    match messie_matrix_v2::timeline_open(client, &rid) {
        Some(h) => MessieV2TimelineResult { error: MessieV2Error::Success, handle: MessieV2TimelineHandle(h) },
        None => MessieV2TimelineResult { error: MessieV2Error::Internal, handle: MessieV2TimelineHandle(0) },
    }
}

#[no_mangle]
pub extern "C" fn messie_v2_timeline_start_streaming(timeline: MessieV2TimelineHandle, port: i64) -> bool {
    messie_matrix_v2::timeline_start_streaming(timeline.0, port)
}

#[no_mangle]
pub extern "C" fn messie_v2_timeline_load_backward(timeline: MessieV2TimelineHandle, limit: u32) -> bool {
    messie_matrix_v2::timeline_load_backward(timeline.0, limit)
}

// (removed *_ex timeline variants)

// (JSON timeline variants removed)

// (JSON send removed)

// Thin (typed) Room Ops FFI

#[no_mangle]
pub extern "C" fn messie_v2_room_send_text(client: u64, room_id: *const c_char, body: *const c_char, reply_to: *const c_char) -> bool {
    let rid = str_from_ptr(room_id).unwrap_or_default();
    let body = str_from_ptr(body).unwrap_or_default();
    let reply = if reply_to.is_null() { None } else { str_from_ptr(reply_to) };
    messie_matrix_v2::room_send_text(client, &rid, &body, reply.as_deref())
}

// (removed *_ex room_send_text)

// (JSON mark read removed)

#[no_mangle]
pub extern "C" fn messie_v2_room_mark_read_up_to(client: u64, room_id: *const c_char, event_id: *const c_char) -> bool {
    let rid = str_from_ptr(room_id).unwrap_or_default();
    let eid = str_from_ptr(event_id).unwrap_or_default();
    messie_matrix_v2::room_mark_read_up_to(client, &rid, &eid)
}

// (removed *_ex room_mark_read_up_to)

// Optional helper: join a room by id (best-effort) — useful for tests
// (no public test helpers exported in v2 FFI)

// ---- v2 Rooms / Summaries ----

#[repr(C)]
pub struct MessieV2StrList { pub ptr: *mut *mut c_char, pub len: usize }

#[no_mangle]
pub extern "C" fn messie_v2_client_list_joined_rooms(handle: u64) -> MessieV2StrList {
    let mut out = MessieV2StrList { ptr: std::ptr::null_mut(), len: 0 };
    if let Some(rooms) = messie_matrix_v2::client_list_joined_rooms(handle) {
        let mut arr: Vec<*mut c_char> = Vec::with_capacity(rooms.len());
        for s in rooms {
            arr.push(CString::new(s).unwrap_or_else(|_| CString::new("").unwrap()).into_raw());
        }
        let mut boxed = arr.into_boxed_slice();
        out.len = boxed.len();
        out.ptr = boxed.as_mut_ptr();
        std::mem::forget(boxed); // transfer ownership to caller
    }
    out
}

#[no_mangle]
pub extern "C" fn messie_v2_free_str_list(list: MessieV2StrList) {
    if list.ptr.is_null() || list.len == 0 { return; }
    unsafe {
        // Reconstruct Vec to free the buffer and element strings
        let vec = Vec::from_raw_parts(list.ptr, list.len, list.len);
        for p in vec {
            if !p.is_null() { let _ = CString::from_raw(p); }
        }
        // vec drops here, freeing the pointer array
    }
}

// Thin (typed) room summary for a single room
#[repr(C)]
pub struct MessieV2RoomSummary {
    pub success: bool,
    pub room_id: *mut c_char,
    pub name: *mut c_char,
    pub avatar_url: *mut c_char, // nullable
    pub notification_count: u64,
    pub highlight_count: u64,
    pub is_marked_unread: bool,
}

#[no_mangle]
pub extern "C" fn messie_v2_room_get_summary(handle: u64, room_id: *const c_char) -> MessieV2RoomSummary {
    let rid = str_from_ptr(room_id).unwrap_or_default();
    match messie_matrix_v2::room_get_summary(handle, &rid) {
        Some(d) => MessieV2RoomSummary {
            success: true,
            room_id: CString::new(d.room_id).unwrap_or_else(|_| CString::new("").unwrap()).into_raw(),
            name: CString::new(d.name).unwrap_or_else(|_| CString::new("").unwrap()).into_raw(),
            avatar_url: d.avatar_url.map(|s| CString::new(s).unwrap_or_else(|_| CString::new("").unwrap()).into_raw()).unwrap_or(std::ptr::null_mut()),
            notification_count: d.notification_count,
            highlight_count: d.highlight_count,
            is_marked_unread: d.is_marked_unread,
        },
        None => MessieV2RoomSummary {
            success: false,
            room_id: std::ptr::null_mut(),
            name: std::ptr::null_mut(),
            avatar_url: std::ptr::null_mut(),
            notification_count: 0,
            highlight_count: 0,
            is_marked_unread: false,
        },
    }
}

// ---- v2 Backup / SSSS ----

#[repr(C)]
pub struct MessieV2BackupStatus { pub success: bool, pub enabled: bool, pub exists_on_server: bool, pub needs_recovery: bool, pub recovery_state: *mut c_char }

#[no_mangle]
pub extern "C" fn messie_v2_backup_status(handle: u64) -> MessieV2BackupStatus {
    match messie_matrix_v2::backup_status(handle) {
        Some(d) => MessieV2BackupStatus {
            success: true,
            enabled: d.enabled,
            exists_on_server: d.exists_on_server,
            needs_recovery: d.needs_recovery,
            recovery_state: CString::new(d.recovery_state).unwrap_or_else(|_| CString::new("").unwrap()).into_raw(),
        },
        None => MessieV2BackupStatus { success: false, enabled: false, exists_on_server: false, needs_recovery: false, recovery_state: std::ptr::null_mut() }
    }
}

#[no_mangle]
pub extern "C" fn messie_v2_backup_status_stream(handle: u64, port: i64) -> bool {
    messie_matrix_v2::backup_status_stream(handle, port)
}

// ---- v2 SAS Verification ----

#[no_mangle]
pub extern "C" fn messie_v2_request_sas_verification(handle: u64, user_id: *const c_char, device_id: *const c_char) -> *mut c_char {
    let uid = str_from_ptr(user_id).unwrap_or_default();
    let did_opt = if device_id.is_null() { None } else { str_from_ptr(device_id) };
    let json = messie_matrix_v2::request_sas_verification(handle, &uid, did_opt.as_deref());
    to_c_string(json)
}

#[no_mangle]
pub extern "C" fn messie_v2_observe_sas(flow_id: *const c_char, port: i64) -> *mut c_char {
    let fid = str_from_ptr(flow_id).unwrap_or_default();
    let json = messie_matrix_v2::observe_sas(&fid, port);
    to_c_string(json)
}

#[no_mangle]
pub extern "C" fn messie_v2_confirm_sas(flow_id: *const c_char) -> *mut c_char {
    let fid = str_from_ptr(flow_id).unwrap_or_default();
    let json = messie_matrix_v2::confirm_sas(&fid);
    to_c_string(json)
}

#[no_mangle]
pub extern "C" fn messie_v2_cancel_sas(flow_id: *const c_char) -> *mut c_char {
    let fid = str_from_ptr(flow_id).unwrap_or_default();
    let json = messie_matrix_v2::cancel_sas(&fid);
    to_c_string(json)
}

// ---- v2 SAS Verification (typed thin) ----

#[repr(C)]
pub struct MessieV2SasHandle(pub u64);

#[repr(C)]
pub struct MessieV2SasResult { pub success: bool, pub handle: MessieV2SasHandle }

#[no_mangle]
pub extern "C" fn messie_v2_sas_request(client: u64, user_id: *const c_char, device_id: *const c_char) -> MessieV2SasResult {
    let uid = str_from_ptr(user_id).unwrap_or_default();
    let did_opt = if device_id.is_null() { None } else { str_from_ptr(device_id) };
    match messie_matrix_v2::sas_request_verification(client, &uid, did_opt.as_deref()) {
        Some(h) => MessieV2SasResult { success: true, handle: MessieV2SasHandle(h) },
        None => MessieV2SasResult { success: false, handle: MessieV2SasHandle(0) },
    }
}

#[no_mangle]
pub extern "C" fn messie_v2_sas_start_streaming(handle: MessieV2SasHandle, port: i64) -> bool {
    messie_matrix_v2::sas_start_streaming(handle.0, port)
}

#[no_mangle]
pub extern "C" fn messie_v2_sas_confirm(handle: MessieV2SasHandle) -> bool {
    messie_matrix_v2::sas_confirm(handle.0)
}

#[no_mangle]
pub extern "C" fn messie_v2_sas_cancel(handle: MessieV2SasHandle) -> bool {
    messie_matrix_v2::sas_cancel(handle.0)
}

#[repr(C)]
pub struct MessieV2SasEmoji {
    pub count: u8,
    pub item0: *mut c_char,
    pub item1: *mut c_char,
    pub item2: *mut c_char,
    pub item3: *mut c_char,
    pub item4: *mut c_char,
    pub item5: *mut c_char,
    pub item6: *mut c_char,
}

#[repr(C)]
pub struct MessieV2SasDecimals { pub success: bool, pub a: u16, pub b: u16, pub c: u16 }

#[no_mangle]
pub extern "C" fn messie_v2_sas_get_emoji(handle: MessieV2SasHandle) -> MessieV2SasEmoji {
    let vec_opt = messie_matrix_v2::sas_get_emoji(handle.0);
    let mut items: [*mut c_char; 7] = [std::ptr::null_mut(); 7];
    let mut count: u8 = 0;
    if let Some(vec) = vec_opt {
        for (i, s) in vec.into_iter().enumerate().take(7) {
            items[i] = CString::new(s).unwrap_or_else(|_| CString::new("").unwrap()).into_raw();
            count += 1;
        }
    }
    MessieV2SasEmoji {
        count,
        item0: items[0],
        item1: items[1],
        item2: items[2],
        item3: items[3],
        item4: items[4],
        item5: items[5],
        item6: items[6],
    }
}

#[no_mangle]
pub extern "C" fn messie_v2_sas_get_decimals(handle: MessieV2SasHandle) -> MessieV2SasDecimals {
    match messie_matrix_v2::sas_get_decimals(handle.0) {
        Some((a, b, c)) => MessieV2SasDecimals { success: true, a, b, c },
        None => MessieV2SasDecimals { success: false, a: 0, b: 0, c: 0 },
    }
}

#[no_mangle]
pub extern "C" fn messie_v2_sas_free(handle: MessieV2SasHandle) -> bool {
    messie_matrix_v2::sas_free(handle.0)
}

#[no_mangle]
pub extern "C" fn messie_v2_enable_online_backup(handle: u64, generate_new: bool) -> *mut c_char {
    let json = messie_matrix_v2::enable_online_backup(handle, generate_new);
    to_c_string(json)
}

#[no_mangle]
pub extern "C" fn messie_v2_ssss_import_recovery_key(handle: u64, recovery_key: *const c_char) -> *mut c_char {
    let key = str_from_ptr(recovery_key).unwrap_or_default();
    let json = messie_matrix_v2::ssss_import_recovery_key(handle, &key);
    to_c_string(json)
}

#[no_mangle]
pub extern "C" fn messie_v2_ssss_bootstrap(handle: u64, generate_new_key: bool, passphrase: *const c_char) -> *mut c_char {
    let _ = generate_new_key; // unused in current SDK wiring
    let pass = if passphrase.is_null() { None } else { str_from_ptr(passphrase).map(|s| s).filter(|s| !s.is_empty()) };
    let json = messie_matrix_v2::ssss_bootstrap(handle, generate_new_key, pass.as_deref());
    to_c_string(json)
}

#[no_mangle]
pub extern "C" fn messie_v2_ssss_export_recovery_key(handle: u64) -> *mut c_char {
    let json = messie_matrix_v2::ssss_export_recovery_key(handle);
    to_c_string(json)
}
// Removed JSON list_room_summaries and room_overview in thin v2

// ---- Test helpers ----

#[cfg(feature = "test-helpers")]
#[no_mangle]
pub extern "C" fn messie_v2_room_join(handle: u64, room_id: *const c_char) -> *mut c_char {
    let rid = str_from_ptr(room_id).unwrap_or_default();
    let json = messie_matrix_v2::room_join(handle, &rid);
    to_c_string(json)
}

#[cfg(feature = "test-helpers")]
#[no_mangle]
pub extern "C" fn messie_v2_test_wait_counts_min(client: u64, room_id: *const c_char, notif_min: u64, highlight_min: u64, timeout_ms: u64) -> *mut c_char {
    let rid = str_from_ptr(room_id).unwrap_or_default();
    let json = messie_matrix_v2::__test_wait_counts_min(client, &rid, notif_min, highlight_min, timeout_ms);
    to_c_string(json)
}

// (JSON room updates/counts removed)

// Thin (typed) unread counts

#[repr(C)]
pub struct MessieV2UnreadCounts { pub notification_count: u64, pub highlight_count: u64 }

#[no_mangle]
pub extern "C" fn messie_v2_room_get_unread_counts(handle: u64, room_id: *const c_char) -> MessieV2UnreadCounts {
    let rid = str_from_ptr(room_id).unwrap_or_default();
    match messie_matrix_v2::room_get_unread_counts(handle, &rid) {
        Some((n, h)) => MessieV2UnreadCounts { notification_count: n, highlight_count: h },
        None => MessieV2UnreadCounts { notification_count: 0, highlight_count: 0 },
    }
}

#[no_mangle]
pub extern "C" fn messie_v2_room_subscribe_to_count_changes(handle: u64, room_id: *const c_char, port: i64) -> bool {
    let rid = str_from_ptr(room_id).unwrap_or_default();
    messie_matrix_v2::room_subscribe_to_count_changes(handle, &rid, port)
}
