//! Minimal FFI glue until flutter_rust_bridge code generation is wired into CI.

use std::ffi::{c_char, CString};

use crate::api;

#[no_mangle]
pub extern "C" fn messie_ffi_ping() -> *mut c_char {
    let response = api::ping();
    CString::new(response)
        .expect("CString::new failed")
        .into_raw()
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
