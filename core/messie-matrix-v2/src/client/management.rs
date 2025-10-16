use std::path::Path;
use std::sync::Arc;

use anyhow::{anyhow, Context, Result};
use matrix_sdk::{authentication::matrix::MatrixSession, config::SyncSettings, Client};
use serde::Serialize;
use url::Url;

use crate::common::envelope::{ack_json, err_json, ok_json};
use crate::common::handle_registry::Handle;
use crate::common::runtime::runtime;

use super::session::{client_builder, load_session, persist_session, wipe_store};
use super::{ClientEntry, CLIENTS};

#[derive(Debug, Clone, Serialize)]
pub struct ClientHandleData {
    pub handle: Handle,
}

#[derive(Debug, Clone, Serialize)]
pub struct LoginData {
    pub user_id: String,
    pub device_id: Option<String>,
    pub access_token: String,
    pub homeserver_url: String,
    pub did_restore: bool,
}

pub fn client_new(hs_url: &str, base_path: &Path) -> String {
    match client_new_inner(hs_url, base_path) {
        Ok(d) => ok_json(d),
        Err(e) => err_json("sdk_error", format!("{:#}", e)),
    }
}

fn client_new_inner(hs_url: &str, base_path: &Path) -> Result<ClientHandleData> {
    let homeserver = Url::parse(hs_url).context("invalid homeserver URL")?;
    let base = base_path.to_path_buf();
    let client: Client = client_builder(&homeserver, &base)?;
    let entry = ClientEntry { client: Arc::new(client), base_path: base, homeserver: homeserver.clone() };
    let handle = CLIENTS.write().expect("clients lock").insert(entry);
    Ok(ClientHandleData { handle })
}

pub fn client_restore_or_login(handle: Handle, username: Option<&str>, password: Option<&str>) -> String {
    match client_restore_or_login_inner(handle, username, password) {
        Ok(d) => ok_json(d),
        Err(e) => err_json("sdk_error", format!("{:#}", e)),
    }
}

fn client_restore_or_login_inner(handle: Handle, username: Option<&str>, password: Option<&str>) -> Result<LoginData> {
    let runtime = runtime();
    let _guard = runtime.enter();
    let entry = {
        let reg = CLIENTS.read().expect("clients lock");
        reg.get(handle).cloned().ok_or_else(|| anyhow!("unknown client handle"))?
    };

    if let Some(stored) = load_session(&entry.base_path)? {
        runtime.block_on(async { entry.client.restore_session(stored.clone()).await }).context("failed to restore existing session")?;
        let meta = entry.client.session_meta().cloned().ok_or_else(|| anyhow!("restored client missing session metadata"))?;
        return Ok(LoginData { user_id: meta.user_id.to_string(), device_id: Some(meta.device_id.to_string()), access_token: stored.tokens.access_token, homeserver_url: entry.homeserver.to_string(), did_restore: true });
    }

    let (username, password) = match (username, password) {
        (Some(u), Some(p)) => (u.to_owned(), p.to_owned()),
        _ => return Err(anyhow!("missing username/password for login")),
    };
    let response = runtime
        .block_on(async { entry.client.matrix_auth().login_username(&username, &password).initial_device_display_name("Messie Flutter v2").send().await })
        .context("failed to login with username/password")?;
    let session: MatrixSession = (&response).into();
    persist_session(&entry.base_path, &session, &entry.homeserver)?;
    let meta = entry.client.session_meta().cloned().ok_or_else(|| anyhow!("logged-in client missing session metadata"))?;
    Ok(LoginData { user_id: meta.user_id.to_string(), device_id: Some(meta.device_id.to_string()), access_token: session.tokens.access_token, homeserver_url: entry.homeserver.to_string(), did_restore: false })
}

pub fn client_logout(handle: Handle) -> String {
    match client_logout_inner(handle) {
        Ok(()) => ack_json(),
        Err(e) => err_json("sdk_error", format!("{:#}", e)),
    }
}

fn client_logout_inner(handle: Handle) -> Result<()> {
    let entry = {
        let reg = CLIENTS.read().expect("clients lock");
        reg.get(handle).cloned().ok_or_else(|| anyhow!("unknown client handle"))?
    };
    wipe_store(&entry.base_path)
}

// Tests-only helper to drive hydration via classic sync once.
pub fn client_sync_once(handle: Handle) -> String {
    match client_sync_once_inner(handle) {
        Ok(()) => ack_json(),
        Err(e) => err_json("sdk_error", format!("{:#}", e)),
    }
}

fn client_sync_once_inner(handle: Handle) -> Result<()> {
    let entry = {
        let reg = CLIENTS.read().expect("clients lock");
        reg.get(handle).cloned().ok_or_else(|| anyhow!("unknown client handle"))?
    };
    let runtime = runtime();
    runtime.block_on(async { entry.client.sync_once(SyncSettings::default()).await }).context("sync_once failed")?;
    Ok(())
}

// ---- Client APIs (typed) ----

/// Create a client and return its handle, or None on failure.
pub fn client_create(hs_url: &str, base_path: &Path) -> Option<Handle> {
    match client_new_inner(hs_url, base_path) {
        Ok(d) => Some(d.handle),
        Err(_) => None,
    }
}

/// Restore existing session if present, otherwise login. Returns user_id on success.
pub fn client_login(handle: Handle, username: Option<&str>, password: Option<&str>) -> Option<String> {
    match client_restore_or_login_inner(handle, username, password) {
        Ok(d) => Some(d.user_id),
        Err(_) => None,
    }
}
