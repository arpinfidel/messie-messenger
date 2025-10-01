//! Minimal FFI glue until flutter_rust_bridge code generation is wired into CI.

use std::{
    any::Any,
    ffi::{c_char, CStr, CString},
    panic::{self, AssertUnwindSafe},
    sync::Once,
};

use crate::api;

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
pub extern "C" fn messie_ffi_free_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}
