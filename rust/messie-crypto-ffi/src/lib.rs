mod bindings {
    uniffi::include_scaffolding!("native_crypto");
}

use once_cell::sync::Lazy;
use serde_json::json;
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

use bindings::NativeCryptoError;
use bindings::{DecryptRequest, DecryptResponse, EncryptRequest, EncryptResponse, InitOptions, VerificationStatus};

static ACTIVE_HANDLES: Lazy<Mutex<HashMap<String, NativeHandle>>> = Lazy::new(|| Mutex::new(HashMap::new()));

struct NativeHandle {
    #[allow(dead_code)]
    created_at: u64,
    options: InitOptions,
}

fn now_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64
}

fn with_handle<T, F>(handle_id: &str, f: F) -> Result<T, NativeCryptoError>
where
    F: FnOnce(&NativeHandle) -> Result<T, NativeCryptoError>,
{
    let handles = ACTIVE_HANDLES
        .lock()
        .map_err(|err| NativeCryptoError::Internal(format!("handle lock poisoned: {err}")))?;
    let handle = handles
        .get(handle_id)
        .ok_or_else(|| NativeCryptoError::InvalidHandle(format!("unknown handle id: {handle_id}")))?;
    f(handle)
}

#[allow(clippy::module_name_repetitions)]
pub use bindings::version;

pub fn init(options: InitOptions) -> Result<String, NativeCryptoError> {
    let handle_id = Uuid::new_v4().to_string();
    let mut handles = ACTIVE_HANDLES
        .lock()
        .map_err(|err| NativeCryptoError::Internal(format!("handle lock poisoned: {err}")))?;
    handles.insert(
        handle_id.clone(),
        NativeHandle {
            created_at: now_millis(),
            options,
        },
    );
    Ok(handle_id)
}

pub fn encrypt_event(handle_id: String, request: EncryptRequest) -> Result<EncryptResponse, NativeCryptoError> {
    with_handle(&handle_id, |_| {
        let mut content = serde_json::from_str::<serde_json::Value>(&request.content_json)
            .map_err(|err| NativeCryptoError::Internal(format!("invalid content json: {err}")))?;
        if let serde_json::Value::Object(ref mut map) = content {
            map.insert(
                "_messieNative".to_string(),
                serde_json::Value::String("noop".to_string()),
            );
        }
        let event = serde_json::json!({
            "room_id": request.room_id,
            "type": request.event_type,
            "content": content,
        });
        Ok(EncryptResponse {
            event_json: serde_json::to_string(&event)
                .map_err(|err| NativeCryptoError::Internal(format!("failed to stringify event: {err}")))?,
        })
    })
}

pub fn decrypt_event(handle_id: String, request: DecryptRequest) -> Result<DecryptResponse, NativeCryptoError> {
    with_handle(&handle_id, |_| {
        let value: serde_json::Value = serde_json::from_str(&request.event_json)
            .map_err(|err| NativeCryptoError::Internal(format!("invalid event json: {err}")))?;
        Ok(DecryptResponse {
            clear_event_json: serde_json::to_string(&value)
                .map_err(|err| NativeCryptoError::Internal(format!("failed to stringify event: {err}")))?,
            was_encrypted: false,
            sender_curve25519_key: None,
            claimed_ed25519_key: None,
        })
    })
}

pub fn download_keys(handle_id: String, _user_ids: Vec<String>) -> Result<(), NativeCryptoError> {
    with_handle(&handle_id, |_| Ok(()))
}

pub fn refresh_device_lists(handle_id: String) -> Result<(), NativeCryptoError> {
    with_handle(&handle_id, |_| Ok(()))
}

pub fn get_user_verification_status(handle_id: String, user_id: String) -> Result<VerificationStatus, NativeCryptoError> {
    with_handle(&handle_id, |_| {
        Ok(VerificationStatus {
            user_id,
            verified: false,
        })
    })
}

pub fn set_device_verified(handle_id: String, _user_id: String, _device_id: String, _verified: bool) -> Result<(), NativeCryptoError> {
    with_handle(&handle_id, |_| Ok(()))
}

pub fn flush(handle_id: String) -> Result<(), NativeCryptoError> {
    with_handle(&handle_id, |_| Ok(()))
}

pub fn close(handle_id: String) -> Result<(), NativeCryptoError> {
    let mut handles = ACTIVE_HANDLES
        .lock()
        .map_err(|err| NativeCryptoError::Internal(format!("handle lock poisoned: {err}")))?;
    handles.remove(&handle_id);
    Ok(())
}
