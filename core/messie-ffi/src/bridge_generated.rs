//! Minimal FFI glue until flutter_rust_bridge code generation is wired into CI.

use std::ffi::{c_char, CStr, CString};

use crate::api;

fn to_c_string(value: String) -> *mut c_char {
    CString::new(value).expect("CString::new failed").into_raw()
}

fn to_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned()
}

#[no_mangle]
pub extern "C" fn messie_ffi_ping() -> *mut c_char {
    to_c_string(api::ping())
}

#[no_mangle]
pub extern "C" fn messie_ffi_init_client(
    hs_url: *const c_char,
    base_path: *const c_char,
) -> *mut c_char {
    let hs_url = to_string(hs_url);
    let base_path = to_string(base_path);
    to_c_string(api::init_client(hs_url, base_path))
}

#[no_mangle]
pub extern "C" fn messie_ffi_restore_or_login(
    hs_url: *const c_char,
    username: *const c_char,
    password: *const c_char,
    base_path: *const c_char,
) -> *mut c_char {
    let hs_url = to_string(hs_url);
    let username = to_string(username);
    let password = to_string(password);
    let base_path = to_string(base_path);
    to_c_string(api::restore_or_login(hs_url, username, password, base_path))
}

#[no_mangle]
pub extern "C" fn messie_ffi_logout(base_path: *const c_char) -> *mut c_char {
    let base_path = to_string(base_path);
    to_c_string(api::logout(base_path))
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
