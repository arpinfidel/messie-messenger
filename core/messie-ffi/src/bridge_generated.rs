//! Minimal FFI glue until flutter_rust_bridge code generation is wired into CI.

use std::{
    any::Any,
    ffi::{c_char, CStr, CString},
    panic::{self, AssertUnwindSafe},
    sync::Once,
};

use crate::api;
use allo_isolate::ffi::DartPostCObjectFnType;

static INIT: Once = Once::new();

fn ensure_initialized() {
    INIT.call_once(|| {
        #[cfg(target_os = "android")]
        {
            android_logger::init_once(
                android_logger::Config::default()
                    .with_max_level(log::LevelFilter::Info)
                    .with_tag("messie_ffi"),
            );
        }

        panic::set_hook(Box::new(|info| {
            #[cfg(target_os = "android")]
            {
                log::error!("panic in messie_ffi: {info}");
            }
            #[cfg(not(target_os = "android"))]
            {
                eprintln!("panic in messie_ffi: {info}");
            }
        }));
    });
}

fn sanitize_for_c(value: String) -> Result<CString, String> {
    if value.as_bytes().contains(&0) {
        let escaped = value.replace('\0', "\\u0000");
        return CString::new(escaped).map_err(|_| "failed to allocate CString".to_string());
    }
    CString::new(value).map_err(|_| "failed to allocate CString".to_string())
}

fn to_c_string(value: String) -> *mut c_char {
    match sanitize_for_c(value) {
        Ok(cstr) => cstr.into_raw(),
        Err(err) => sanitize_for_c(json_error(err))
            .expect("failed to allocate CString for error message")
            .into_raw(),
    }
}

fn json_error(message: impl ToString) -> String {
    serde_json::json!({ "ok": false, "error": message.to_string() }).to_string()
}

fn read_c_string(ptr: *const c_char, name: &str) -> Result<String, String> {
    if ptr.is_null() {
        return Err(format!("{name} is null"));
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map(|value| value.to_owned())
        .map_err(|err| format!("{name} is not valid UTF-8: {err}"))
}

fn panic_payload_to_string(payload: Box<dyn Any + Send>) -> String {
    let payload_ref = &*payload;
    if let Some(message) = payload_ref.downcast_ref::<String>() {
        return message.clone();
    }
    if let Some(message) = payload_ref.downcast_ref::<&'static str>() {
        return (*message).to_string();
    }
    "unknown panic".to_string()
}

fn ffi_safe<F>(operation: F) -> *mut c_char
where
    F: FnOnce() -> Result<String, String>,
{
    ensure_initialized();
    match panic::catch_unwind(AssertUnwindSafe(operation)) {
        Ok(Ok(result)) => to_c_string(result),
        Ok(Err(err)) => {
            log::error!("messie_ffi error: {err}");
            to_c_string(json_error(err))
        }
        Err(payload) => {
            let message = panic_payload_to_string(payload);
            log::error!("messie_ffi panic: {message}");
            to_c_string(json_error(format!("panic: {message}")))
        }
    }
}

#[no_mangle]
pub extern "C" fn messie_ffi_ping() -> *mut c_char {
    ffi_safe(|| Ok(api::ping()))
}

#[no_mangle]
pub extern "C" fn messie_ffi_init_client(
    hs_url: *const c_char,
    base_path: *const c_char,
) -> *mut c_char {
    ffi_safe(|| {
        let hs_url = read_c_string(hs_url, "homeserverUrl")?;
        let base_path = read_c_string(base_path, "basePath")?;
        Ok(api::init_client(hs_url, base_path))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_restore_or_login(
    hs_url: *const c_char,
    username: *const c_char,
    password: *const c_char,
    base_path: *const c_char,
) -> *mut c_char {
    ffi_safe(|| {
        let hs_url = read_c_string(hs_url, "homeserverUrl")?;
        let username = read_c_string(username, "username")?;
        let password = read_c_string(password, "password")?;
        let base_path = read_c_string(base_path, "basePath")?;
        Ok(api::restore_or_login(hs_url, username, password, base_path))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_logout(base_path: *const c_char) -> *mut c_char {
    ffi_safe(|| {
        let base_path = read_c_string(base_path, "basePath")?;
        Ok(api::logout(base_path))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_download_room_keys_for_room(room_id: *const c_char) -> *mut c_char {
    ffi_safe(|| {
        let room_id = read_c_string(room_id, "roomId")?;
        Ok(api::download_room_keys_for_room(room_id))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_dump_room_crypto(room_id: *const c_char) -> *mut c_char {
    ffi_safe(|| {
        let room_id = read_c_string(room_id, "roomId")?;
        Ok(api::dump_room_crypto(room_id))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_backup_status() -> *mut c_char {
    ffi_safe(|| Ok(api::backup_status()))
}

#[no_mangle]
pub extern "C" fn messie_ffi_import_recovery_key(recovery_key: *const c_char) -> *mut c_char {
    ffi_safe(|| {
        let recovery_key = read_c_string(recovery_key, "recoveryKey")?;
        Ok(api::import_recovery_key(recovery_key))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_backup_status_stream(handle: *const c_char, port: i64) -> *mut c_char {
    ffi_safe(|| {
        let handle = read_c_string(handle, "handle")?;
        Ok(api::backup_status_stream(handle, port))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_enable_online_backup(generate_new: bool) -> *mut c_char {
    ffi_safe(|| Ok(api::enable_online_backup(generate_new)))
}

#[no_mangle]
pub extern "C" fn messie_ffi_export_recovery_key() -> *mut c_char {
    ffi_safe(|| Ok(api::export_recovery_key()))
}

#[no_mangle]
pub extern "C" fn messie_ffi_ssss_import_recovery_key(recovery_key: *const c_char) -> *mut c_char {
    ffi_safe(|| {
        let recovery_key = read_c_string(recovery_key, "recoveryKey")?;
        Ok(api::ssss_import_recovery_key(recovery_key))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_ssss_bootstrap(generate_new_key: bool, passphrase: *const c_char) -> *mut c_char {
    ffi_safe(|| {
        let passphrase = if passphrase.is_null() { None } else { Some(read_c_string(passphrase, "passphrase")?) };
        Ok(api::ssss_bootstrap(generate_new_key, passphrase))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_ssss_export_recovery_key() -> *mut c_char {
    ffi_safe(|| Ok(api::ssss_export_recovery_key()))
}

#[no_mangle]
pub extern "C" fn messie_ffi_recover_with_key(recovery_key: *const c_char) -> *mut c_char {
    ffi_safe(|| {
        let recovery_key = read_c_string(recovery_key, "recoveryKey")?;
        Ok(api::recover_with_key(recovery_key))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_request_sas_verification(user_id: *const c_char, device_id: *const c_char) -> *mut c_char {
    ffi_safe(|| {
        let user_id = read_c_string(user_id, "userId")?;
        let device_id = if device_id.is_null() {
            None
        } else {
            let s = read_c_string(device_id, "deviceId")?;
            if s.is_empty() { None } else { Some(s) }
        };
        Ok(api::request_sas_verification(user_id, device_id))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_observe_sas(flow_id: *const c_char, port: i64) -> *mut c_char {
    ffi_safe(|| {
        let flow_id = read_c_string(flow_id, "flowId")?;
        Ok(api::observe_sas(flow_id, port))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_confirm_sas(flow_id: *const c_char) -> *mut c_char {
    ffi_safe(|| {
        let flow_id = read_c_string(flow_id, "flowId")?;
        Ok(api::confirm_sas(flow_id))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_cancel_sas(flow_id: *const c_char) -> *mut c_char {
    ffi_safe(|| {
        let flow_id = read_c_string(flow_id, "flowId")?;
        Ok(api::cancel_sas(flow_id))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_trust_state(user_id: *const c_char, device_id: *const c_char) -> *mut c_char {
    ffi_safe(|| {
        let user_id = read_c_string(user_id, "userId")?;
        let device_id = if device_id.is_null() {
            None
        } else {
            let s = read_c_string(device_id, "deviceId")?;
            if s.is_empty() { None } else { Some(s) }
        };
        Ok(api::trust_state(user_id, device_id))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_start_sliding_sync(
    handle: *const c_char,
    hp_size: u32,
    lp_batch: u32,
    hp_timeline: u32,
    lp_timeline: u32,
) -> *mut c_char {
    ffi_safe(|| {
        let handle = read_c_string(handle, "handle")?;
        Ok(api::start_sliding_sync(
            handle,
            hp_size,
            lp_batch,
            hp_timeline,
            lp_timeline,
        ))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_room_list_stream(handle: *const c_char, port: i64) -> *mut c_char {
    ffi_safe(|| {
        let handle = read_c_string(handle, "handle")?;
        Ok(api::room_list_stream(handle, port))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_list_joined_rooms() -> *mut c_char {
    ffi_safe(|| Ok(api::list_joined_rooms()))
}

#[no_mangle]
pub extern "C" fn messie_ffi_room_overview(room_id: *const c_char) -> *mut c_char {
    ffi_safe(|| {
        let room_id = read_c_string(room_id, "roomId")?;
        Ok(api::room_overview(room_id))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_open_room(
    handle: *const c_char,
    room_id: *const c_char,
) -> *mut c_char {
    ffi_safe(|| {
        let handle = read_c_string(handle, "handle")?;
        let room_id = read_c_string(room_id, "roomId")?;
        Ok(api::open_room(handle, room_id))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_timeline_stream(
    handle: *const c_char,
    room_id: *const c_char,
    port: i64,
) -> *mut c_char {
    ffi_safe(|| {
        let handle = read_c_string(handle, "handle")?;
        let room_id = read_c_string(room_id, "roomId")?;
        Ok(api::timeline_stream(handle, room_id, port))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_load_backward(
    handle: *const c_char,
    room_id: *const c_char,
    limit: u32,
) -> *mut c_char {
    ffi_safe(|| {
        let handle = read_c_string(handle, "handle")?;
        let room_id = read_c_string(room_id, "roomId")?;
        Ok(api::load_backward(handle, room_id, limit))
    })
}

#[no_mangle]
pub extern "C" fn messie_ffi_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}

#[no_mangle]
pub unsafe extern "C" fn messie_ffi_store_dart_post_cobject(ptr: DartPostCObjectFnType) {
    allo_isolate::store_dart_post_cobject(ptr);
}
