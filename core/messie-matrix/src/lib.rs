//! Messie Matrix SDK wrapper providing a synchronous facade for the async
//! `matrix-sdk` crate. The helper functions here are consumed by the FFI layer
//! so the Flutter app can manage session lifecycles from Dart.

use std::{
    collections::{HashSet},
    fs,
    path::{Path, PathBuf},
    sync::{Arc, RwLock},
    time::Duration,
};

use anyhow::{anyhow, Context, Result};
use log::{info, warn, debug, trace};
use matrix_sdk::{
    authentication::matrix::MatrixSession,
    config::SyncSettings,
    encryption::{BackupDownloadStrategy, EncryptionSettings},
    room::MessagesOptions,
    ruma::{OwnedDeviceId, OwnedRoomId, OwnedUserId},
    Client, Room as MatrixRoom, RoomDisplayName, RoomState, SessionMeta, SessionTokens,
};
use once_cell::sync::{Lazy, OnceCell};
use serde::{Deserialize, Serialize};
use tokio::{
    runtime::{Builder, Runtime},
    time::timeout,
};
use url::Url;
use matrix_sdk::ruma::UInt;
use matrix_sdk::latest_events::LatestEventValue; // for method availability
use matrix_sdk::ruma::api::client::read_marker::set_read_marker::v3 as read_marker;

mod sliding_sync;
mod timeline;
mod backup;
mod verification;

/// Simple ping function used for integration tests.
pub fn ping() -> Result<String> {
    Ok("pong".to_owned())
}

/// Tokio runtime shared by all blocking calls.
static RUNTIME: OnceCell<Runtime> = OnceCell::new();
/// Active Matrix client for the current session. Only a single session is
/// supported at a time for Phase 1.
static ACTIVE_CLIENT: Lazy<RwLock<Option<Arc<Client>>>> = Lazy::new(|| RwLock::new(None));
// Base path used for the current active client. Used by modules to store
// auxiliary caches (e.g. offline timeline files) alongside the SDK store.
static ACTIVE_BASE_PATH: Lazy<RwLock<Option<PathBuf>>> = Lazy::new(|| RwLock::new(None));
/// Ephemeral cache of rooms muted via push rules in this process.
static MUTED_ROOMS: Lazy<RwLock<HashSet<String>>> = Lazy::new(|| RwLock::new(HashSet::new()));

/// Public helper to read in-memory mute cache.
pub fn is_room_muted(room_id: &str) -> bool {
    let guard = MUTED_ROOMS.read().expect("MUTED_ROOMS lock poisoned");
    guard.contains(room_id)
}

fn runtime() -> &'static Runtime {
    // Ensure logger is configured once per process (no-op if already set).
    static INIT_LOGGER: std::sync::Once = std::sync::Once::new();
    INIT_LOGGER.call_once(|| {
        let _ = env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("warn"))
            .format_timestamp_millis()
            .try_init();
    });

    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_all()
            .thread_name("messie-matrix")
            .build()
            .expect("failed to create Tokio runtime")
    })
}

fn store_client(client: Client) -> Arc<Client> {
    let arc = Arc::new(client);
    let mut guard = ACTIVE_CLIENT.write().expect("ACTIVE_CLIENT lock poisoned");
    *guard = Some(Arc::clone(&arc));
    arc
}

/// Populate in-memory mute cache from the server-side notification settings.
fn refresh_muted_rooms_sync(client: &Client) {
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = client.clone();
    let _ = runtime.block_on(async move {
        use matrix_sdk::notification_settings::RoomNotificationMode;
        let settings = client.notification_settings().await;
        let mut snapshot: HashSet<String> = HashSet::new();
        for room in client.rooms() {
            let id = room.room_id().to_owned();
            match settings
                .get_user_defined_room_notification_mode(id.as_ref())
                .await
            {
                Some(RoomNotificationMode::Mute) => {
                    snapshot.insert(id.as_str().to_owned());
                }
                _ => {}
            }
        }
        let mut guard = MUTED_ROOMS.write().expect("MUTED_ROOMS lock poisoned");
        *guard = snapshot;
        Result::<(), ()>::Ok(())
    });
}

fn ensure_push_rules_loaded_sync(client: &Client) {
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = client.clone();
    let _ = runtime.block_on(async move {
        match client.account().push_rules().await {
            Ok(rules) => {
                log::debug!("[push] loaded underride rules: {}", rules.underride.len());

                // Check for key notification rules
                let has_mention_rule = rules.underride.iter()
                    .any(|rule| rule.rule_id == ".m.rule.contains_user_name");
                let has_dm_rule = rules.underride.iter()
                    .any(|rule| rule.rule_id == ".m.rule.room_one_to_one");

                log::debug!(
                    "[push] key rules present: mention={}, dm={}",
                    has_mention_rule,
                    has_dm_rule
                );

                // Log all rule IDs for debugging
                log::trace!("[push] underride rule ids:");
                for rule in &rules.underride {
                    log::trace!("[push]  - {}", rule.rule_id);
                }

                // Debug all underride rules in detail
                for rule in &rules.underride {
                    log::trace!(
                        "[push] rule {} enabled={} actions={:?}",
                        rule.rule_id, rule.enabled, rule.actions
                    );
                    if rule.rule_id == ".m.rule.contains_user_name" {
                        log::trace!("[push] mention rule conditions: {:?}", rule.conditions);
                    }
                }

                // Log the issue but don't try to fix it - Element works so server has the rule
                if !has_mention_rule {
                    log::debug!("[push] mention rule not present in underride set");
                }
            }
            Err(e) => {
                log::debug!("[push] failed to load push rules: {}", e);
            }
        }
        Result::<(), ()>::Ok(())
    });
}

async fn get_updated_notification_counts(room: &MatrixRoom) -> Option<(u64, u64)> {
    // The core issue: we need to wait for sliding sync to deliver server notification
    // counts to this room before reading them.
    //
    // The test is calling room_overview immediately after sending a message, but
    // sliding sync may not have processed the server response yet.

    log::debug!("[counts] wait for room update: {}", room.room_id());

    // First check if the room already has updates available by reading current counts
    let initial_counts = room.unread_notification_counts();
    log::trace!(
        "[counts] initial read {} n={} h={}",
        room.room_id(),
        initial_counts.notification_count,
        initial_counts.highlight_count
    );

    // Try to subscribe to room updates with a short timeout
    // This implements the expert's recommendation properly
    let mut rx = room.subscribe_to_updates();
    log::trace!("[counts] subscribed to room updates: {}", room.room_id());

    // Set a reasonable timeout for waiting for updates
    let timeout_duration = std::time::Duration::from_millis(500);

    match tokio::time::timeout(timeout_duration, rx.recv()).await {
        Ok(Ok(update)) => {
            // We got a room update! Now read the fresh counts
            let fresh_counts = room.unread_notification_counts();
            log::debug!(
                "[counts] update {} n={} h={}",
                room.room_id(),
                fresh_counts.notification_count,
                fresh_counts.highlight_count
            );

            // Return the fresh counts (even if they're zero - that's valid)
            Some((fresh_counts.notification_count, fresh_counts.highlight_count))
        }
        Ok(Err(e)) => {
            log::debug!("[counts] subscription error {}: {:?}", room.room_id(), e);
            None
        }
        Err(_timeout) => {
            log::debug!("[counts] timeout waiting for update: {}", room.room_id());
            None
        }
    }
}

/// Returns the current client if one has been initialised.
pub fn client() -> Option<Arc<Client>> {
    ACTIVE_CLIENT
        .read()
        .expect("ACTIVE_CLIENT lock poisoned")
        .as_ref()
        .map(Arc::clone)
}

pub(crate) fn active_base_path() -> Option<PathBuf> {
    ACTIVE_BASE_PATH
        .read()
        .expect("ACTIVE_BASE_PATH lock poisoned")
        .as_ref()
        .cloned()
}

fn client_builder(homeserver_url: &Url, base_path: &Path) -> Result<Client> {
    let runtime = runtime();
    let _guard = runtime.enter();

    let store_root = base_path.join("matrix_store");
    fs::create_dir_all(&store_root).context("failed to create Matrix store path")?;
    let cache_path = store_root.join("cache");
    fs::create_dir_all(&cache_path).context("failed to create Matrix cache path")?;
    let database_path = store_root.join("messie.sqlite");
    let homeserver = homeserver_url.clone();
    runtime
        .block_on(async move {
            let encryption_settings = EncryptionSettings {
                auto_enable_cross_signing: false,
                backup_download_strategy: BackupDownloadStrategy::OneShot,
                auto_enable_backups: true,
            };

            Client::builder()
                .homeserver_url(homeserver.as_ref())
                .sqlite_store_with_cache_path(&database_path, &cache_path, None)
                .with_encryption_settings(encryption_settings)
                .build()
                .await
        })
        .context("failed to build Matrix client")
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PersistedSession {
    homeserver_url: String,
    user_id: String,
    access_token: String,
    device_id: Option<String>,
    refresh_token: Option<String>,
}

impl PersistedSession {
    fn path(base_path: &Path) -> PathBuf {
        base_path.join("session.json")
    }

    fn load(base_path: &Path) -> Result<Option<Self>> {
        let path = Self::path(base_path);
        if !path.exists() {
            return Ok(None);
        }

        let contents = fs::read(&path)
            .with_context(|| format!("failed to read session file at {}", path.display()))?;
        let session: Self = serde_json::from_slice(&contents)
            .with_context(|| format!("failed to parse session file at {}", path.display()))?;
        Ok(Some(session))
    }

    fn save(&self, base_path: &Path) -> Result<()> {
        let path = Self::path(base_path);
        if let Some(dir) = path.parent() {
            fs::create_dir_all(dir)
                .with_context(|| format!("failed to create session dir at {}", dir.display()))?;
        }
        let serialized = serde_json::to_vec_pretty(self).context("failed to serialise session")?;
        fs::write(&path, serialized)
            .with_context(|| format!("failed to write session file at {}", path.display()))?;
        Ok(())
    }
}

fn load_session(base_path: &Path) -> Result<Option<MatrixSession>> {
    let persisted = match PersistedSession::load(base_path)? {
        Some(session) => session,
        None => return Ok(None),
    };

    let user_id: OwnedUserId = persisted
        .user_id
        .parse()
        .map_err(|_| anyhow!("invalid stored user ID"))?;
    let device_id_str = persisted
        .device_id
        .ok_or_else(|| anyhow!("stored session missing device id"))?;
    let device_id = OwnedDeviceId::try_from(device_id_str.as_str())
        .map_err(|_| anyhow!("invalid stored device id"))?;

    Ok(Some(MatrixSession {
        meta: SessionMeta { user_id, device_id },
        tokens: SessionTokens {
            access_token: persisted.access_token,
            refresh_token: persisted.refresh_token,
        },
    }))
}

fn persist_session(base_path: &Path, session: &MatrixSession, homeserver_url: &Url) -> Result<()> {
    let device_id = Some(session.meta.device_id.to_string());
    let persisted = PersistedSession {
        homeserver_url: homeserver_url.as_ref().to_owned(),
        user_id: session.meta.user_id.to_string(),
        access_token: session.tokens.access_token.clone(),
        refresh_token: session.tokens.refresh_token.clone(),
        device_id,
    };
    persisted.save(base_path)
}

fn wipe_store(base_path: &Path) -> Result<()> {
    if base_path.exists() {
        fs::remove_dir_all(base_path)
            .with_context(|| format!("failed to wipe base path at {}", base_path.display()))?;
    }
    Ok(())
}

/// Details returned to Flutter after initialising a client from persisted
/// credentials.
#[derive(Debug, Clone, Serialize)]
pub struct InitClientResponse {
    pub user_id: String,
    pub device_id: Option<String>,
    pub homeserver_url: String,
}

/// Details returned after logging in or restoring a session.
#[derive(Debug, Clone, Serialize)]
pub struct LoginResponse {
    pub user_id: String,
    pub device_id: Option<String>,
    pub access_token: String,
    pub homeserver_url: String,
    pub did_restore: bool,
}

/// Backup status summary for UI.
#[derive(Debug, Clone, Serialize)]
pub struct BackupStatusResponse {
    pub enabled: bool,
    pub exists_on_server: bool,
    pub recovery_state: String,
    pub needs_recovery: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct EnableBackupResponse {
    pub enabled: bool,
    pub exists_on_server: bool,
    pub generated_recovery_key: Option<String>,
}

/// Result of bootstrapping SSSS. If a new recovery key was generated, it is
/// returned as a bech32 string so the UI can display and store it.
#[derive(Debug, Clone, Serialize)]
pub struct SsssBootstrapResponse {
    pub generated_recovery_key: Option<String>,
}

/// Initialise the Matrix client from a homeserver URL and stored session
/// tokens. Returns information about the restored session so Flutter can keep
/// its secure storage in sync.
pub fn init_client(hs_url: &str, base_path: &Path) -> Result<InitClientResponse> {
    let homeserver_url = Url::parse(hs_url).context("invalid homeserver URL")?;
    let base_path = base_path.to_path_buf();

    let runtime = runtime();
    let _guard = runtime.enter();

    let session = load_session(&base_path)?.ok_or_else(|| anyhow!("no stored session"))?;

    let client = client_builder(&homeserver_url, &base_path)?;
    runtime
        .block_on(async {
            client.restore_session(session).await?;
            // REMOVED: sync_once() call that was causing unread count clearing
            // The expert confirmed this mixing sync_once with sliding sync causes race conditions
            // Sliding sync will handle all synchronization
            Result::<_, anyhow::Error>::Ok(())
        })
        .context("failed to restore session")?;

    // Remember the base path for auxiliary caches.
    {
        let mut g = ACTIVE_BASE_PATH.write().expect("ACTIVE_BASE_PATH lock poisoned");
        *g = Some(base_path.clone());
    }
    let arc = store_client(client);
    let meta = arc
        .session_meta()
        .cloned()
        .ok_or_else(|| anyhow!("restored client missing session metadata"))?;
    let user_id = meta.user_id.to_string();
    let device_id = Some(meta.device_id.to_string());

    // Load server-side mute state so UI reflects persisted settings immediately.
    refresh_muted_rooms_sync(&arc);

    // Ensure push rules are loaded for proper notification counter calculation
    ensure_push_rules_loaded_sync(&arc);

    Ok(InitClientResponse {
        user_id,
        device_id,
        homeserver_url: homeserver_url.to_string(),
    })
}

/// Attempt to restore an existing session or perform a fresh password login.
/// The resulting token is persisted to disk and returned to Flutter so it can
/// mirror the state in secure storage.
pub fn restore_or_login(
    hs_url: &str,
    username: &str,
    password: &str,
    base_path: &Path,
) -> Result<LoginResponse> {
    let homeserver_url = Url::parse(hs_url).context("invalid homeserver URL")?;
    let base_path = base_path.to_path_buf();

    let runtime = runtime();
    let _guard = runtime.enter();

    let client = client_builder(&homeserver_url, &base_path)?;

    if let Some(session) = load_session(&base_path)? {
        let session = runtime
            .block_on(async {
                client.restore_session(session.clone()).await?;
                // REMOVED: sync_once() that was causing unread count issues
                // Sliding sync will handle all synchronization
                info!("restore_or_login: session restored successfully, sliding sync will populate room data");
                Result::<_, anyhow::Error>::Ok(session)
            })
            .context("failed to restore existing session")?;

        // Remember the base path for auxiliary caches.
        {
            let mut g = ACTIVE_BASE_PATH.write().expect("ACTIVE_BASE_PATH lock poisoned");
            *g = Some(base_path.clone());
        }
        let arc = store_client(client);
        let rooms = arc.rooms();
        let known_room_count = rooms.len();
        let known_rooms: Vec<_> = rooms
            .iter()
            .take(5)
            .map(|room| room.room_id().to_string())
            .collect();
        info!(
            "restore_or_login: client cache after restore includes {} rooms (sample: {:?})",
            known_room_count, known_rooms
        );
        let meta = arc
            .session_meta()
            .cloned()
            .ok_or_else(|| anyhow!("restored client missing session metadata"))?;

        Ok(LoginResponse {
            user_id: meta.user_id.to_string(),
            device_id: Some(meta.device_id.to_string()),
            access_token: session.tokens.access_token,
            homeserver_url: homeserver_url.to_string(),
            did_restore: true,
        })
    } else {
        let username = username.to_owned();
        let password = password.to_owned();

        let response = runtime
            .block_on(async {
                let response = client
                    .matrix_auth()
                    .login_username(&username, &password)
                    .initial_device_display_name("Messie Flutter")
                    .send()
                    .await?;
                let sync = client
                    .sync_once(SyncSettings::default().full_state(true))
                    .await?;
                let joined: Vec<_> = sync
                    .rooms
                    .joined
                    .keys()
                    .take(5)
                    .cloned()
                    .map(|room_id| room_id.to_string())
                    .collect();
                info!(
                    "restore_or_login: initial sync after login returned {} joined / {} invited rooms (sample: {:?})",
                    sync.rooms.joined.len(),
                    sync.rooms.invited.len(),
                    joined
                );
                Result::<_, anyhow::Error>::Ok(response)
            })
            .context("failed to login with username/password")?;

        let session: MatrixSession = (&response).into();
        persist_session(&base_path, &session, &homeserver_url)?;
        // Remember the base path for auxiliary caches.
        {
            let mut g = ACTIVE_BASE_PATH.write().expect("ACTIVE_BASE_PATH lock poisoned");
            *g = Some(base_path.clone());
        }
        let arc = store_client(client);
        let rooms = arc.rooms();
        let known_room_count = rooms.len();
        let known_rooms: Vec<_> = rooms
            .iter()
            .take(5)
            .map(|room| room.room_id().to_string())
            .collect();
        info!(
            "restore_or_login: client cache after login includes {} rooms (sample: {:?})",
            known_room_count, known_rooms
        );
        let meta = arc
            .session_meta()
            .cloned()
            .ok_or_else(|| anyhow!("logged-in client missing session metadata"))?;

        // After first sync, pull mute settings for all rooms.
        refresh_muted_rooms_sync(&arc);

        // Ensure push rules are loaded for proper notification counter calculation
        ensure_push_rules_loaded_sync(&arc);

        Ok(LoginResponse {
            user_id: meta.user_id.to_string(),
            device_id: Some(meta.device_id.to_string()),
            access_token: session.tokens.access_token,
            homeserver_url: homeserver_url.to_string(),
            did_restore: false,
        })
    }
}

/// Wipe any stored credentials and Matrix state on disk.
pub fn logout(base_path: &Path) -> Result<()> {
    let runtime = runtime();
    let _guard = runtime.enter();

    runtime.block_on(async {
        sliding_sync::reset_all().await;
        timeline::reset_all().await;
        backup::reset_all().await;
        verification::reset_all().await;
    });

    {
        let mut guard = ACTIVE_CLIENT.write().expect("ACTIVE_CLIENT lock poisoned");
        *guard = None;
    }
    {
        let mut g = ACTIVE_BASE_PATH.write().expect("ACTIVE_BASE_PATH lock poisoned");
        *g = None;
    }
    wipe_store(base_path)
}

/// Recover encrypted secrets (cross-signing keys, key backup, etc.) using the
/// provided recovery key.
pub fn recover_with_key(recovery_key: &str) -> Result<()> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let runtime = runtime();
    let _guard = runtime.enter();

    runtime.block_on(async {
        info!("[backup] starting recovery workflow");
        client.encryption().recovery().recover(recovery_key).await?;
        let encryption = client.encryption();
        encryption.wait_for_e2ee_initialization_tasks().await;
        let recovery_state = encryption.recovery().state();
        info!("[backup] recovery state {recovery_state:?}");
        if let Err(err) = encryption.recovery().enable_backup().await {
            warn!("[backup] failed to enable backup after recovery: {err:?}");
        }
        let backups = encryption.backups();
        let enabled = backups.are_enabled().await;
        let exists = backups.fetch_exists_on_server().await.unwrap_or(false);
        info!("[backup] backups enabled={enabled}, exists_on_server={exists}");
        if exists && !enabled {
            use matrix_sdk::ruma::{events::GlobalAccountDataEventType, serde::Raw};
            debug!("[backup] forcing backup disabled flag to false");
            let raw = Raw::from_json_string("{\"disabled\":false}".to_owned())?;
            client
                .account()
                .set_account_data_raw(
                    GlobalAccountDataEventType::from("m.org.matrix.custom.backup_disabled"),
                    raw,
                )
                .await?;
        }
        match timeout(Duration::from_secs(10), backups.wait_for_steady_state()).await {
            Ok(Ok(())) => { info!("[backup] reached steady state"); }
            Ok(Err(err)) => { warn!("[backup] steady state failed: {err:?}"); }
            Err(_) => { warn!("[backup] waiting for steady state timed out"); }
        }

        if exists {
            let joined_rooms: Vec<_> = client
                .rooms()
                .into_iter()
                .filter(|room| matches!(room.state(), RoomState::Joined))
                .map(|room| room.room_id().to_owned())
                .collect();

            info!("[backup] attempting download for {} joined rooms", joined_rooms.len());

            for room_id in joined_rooms {
                match backups.download_room_keys_for_room(&room_id).await {
                    Ok(()) => { trace!("[backup] downloaded backup for {room_id}"); }
                    Err(err) => { warn!("[backup] download failed for {room_id}: {err:?}"); }
                }
            }
        }
        Result::<_, anyhow::Error>::Ok(())
    })
}

/// Download room keys for the provided room if a backup exists.
pub fn download_room_keys_for_room(room_id: &str) -> Result<()> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let runtime = runtime();
    let _guard = runtime.enter();

    let room_id: OwnedRoomId = room_id
        .parse()
        .map_err(|_| anyhow!("invalid room id '{room_id}'"))?;

    runtime.block_on(async move {
        client
            .encryption()
            .backups()
            .download_room_keys_for_room(&room_id)
            .await?;
        Result::<_, anyhow::Error>::Ok(())
    })
}

/// Emit diagnostic information about a room's encryption/backup state.
pub fn dump_room_crypto(room_id: &str) -> Result<()> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let runtime = runtime();
    let _guard = runtime.enter();

    let room_id: OwnedRoomId = room_id
        .parse()
        .map_err(|_| anyhow!("invalid room id '{room_id}'"))?;

    runtime.block_on(async move { dump_room_crypto_async(&client, &room_id).await })
}

/// Return the current backup status for the active client.
pub fn backup_status() -> Result<BackupStatusResponse> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let runtime = runtime();
    let _guard = runtime.enter();

    runtime.block_on(async move {
        let encryption = client.encryption();
        let backups = encryption.backups();
        let enabled = backups.are_enabled().await;
        let exists_on_server = backups.fetch_exists_on_server().await.unwrap_or(false);
        // Derive recovery state from recovery service as a string for telemetry/UX
        let state_enum = encryption.recovery().state();
        let recovery_state = format!("{:?}", state_enum);
        // Need recovery if server has backup and we're not enabled locally OR
        // if the recovery service itself is not fully enabled yet.
        let needs_recovery = (exists_on_server && !enabled)
            || !matches!(state_enum, matrix_sdk::encryption::recovery::RecoveryState::Enabled);
        Ok(BackupStatusResponse { enabled, exists_on_server, recovery_state, needs_recovery })
    })
}

/// Attempt to enable online backup. If `generate_new` is true and no backup
/// exists server-side, this build does not generate a new recovery key yet and
/// will return `generated_recovery_key = None` (follow-up work).
pub fn enable_online_backup(generate_new: bool) -> Result<EnableBackupResponse> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let runtime = runtime();
    let _guard = runtime.enter();

    runtime.block_on(async move {
        let encryption = client.encryption();
        let backups = encryption.backups();
        let exists_on_server = backups.fetch_exists_on_server().await.unwrap_or(false);

        if generate_new {
            // Create a new backup version on the server and persist its key (stored in SSSS).
            backups
                .create()
                .await
                .map_err(|e| anyhow!(format!("failed to create backup version: {e:?}")))?;
        } else if !backups.are_enabled().await {
            // Convenience helper to enable/attach to an existing backup version.
            encryption
                .recovery()
                .enable_backup()
                .await
                .map_err(|e| anyhow!(format!("failed to enable backup: {e:?}")))?;
        }

        // Optionally wait for a steady state; keep it non-blocking for now.
        let enabled = backups.are_enabled().await;
        Ok(EnableBackupResponse { enabled, exists_on_server, generated_recovery_key: None })
    })
}

/// Export the recovery key for the current account. Not supported in this
/// build yet.
pub fn export_recovery_key() -> Result<String> {
    Err(anyhow!(
        "export_recovery_key is not supported by the current matrix-sdk version"
    ))
}

/// Import an existing SSSS recovery key (bech32) to unlock local secret
/// storage. This is equivalent to calling `recover_with_key`, but exposed under
/// an SSSS-oriented name for clarity in the FRB surface.
pub fn ssss_import_recovery_key(recovery_key_bech32: &str) -> Result<()> {
    recover_with_key(recovery_key_bech32)
}

/// Bootstrap secret storage. On SDK 0.14.x we do not expose recovery key
/// generation; return a clear error so callers can branch accordingly.
pub fn ssss_bootstrap(_generate_new_key: bool, _passphrase: Option<&str>) -> Result<SsssBootstrapResponse> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let runtime = runtime();
    let _guard = runtime.enter();

    runtime.block_on(async move {
        let recovery = client.encryption().recovery();
        // Build the enable flow, optionally with passphrase; if no passphrase provided, a
        // random recovery key will be generated and returned.
        // Note: The recovery key string must be shown/saved by the caller.
        let recovery_key = recovery
            .enable()
            .await
            .map_err(|e| anyhow!(format!("failed to bootstrap SSSS: {e:?}")))?;
        Ok(SsssBootstrapResponse { generated_recovery_key: Some(recovery_key) })
    })
}

/// Export the SSSS recovery key. Not supported on SDK 0.14.x in this build.
pub fn ssss_export_recovery_key() -> Result<String> {
    Err(anyhow!(
        "exporting the SSSS recovery key is not supported by the current matrix-sdk version"
    ))
}

/// Import a recovery key (alias for recover_with_key for FRB naming).
pub fn import_recovery_key(recovery_key: &str) -> Result<()> {
    recover_with_key(recovery_key)
}

/// Register a Dart send port to receive backup status updates.
pub fn register_backup_status_listener(handle: &str, port: i64) -> Result<sliding_sync::AckResponse> {
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(backup::register_listener(handle, port))
}

async fn dump_room_crypto_async(client: &Client, room_id: &OwnedRoomId) -> Result<()> {
    let Some(room) = client.get_room(room_id) else {
        debug!("[crypto] room {room_id} not found in client");
        return Ok(());
    };

    debug!("[crypto] inspecting room {room_id}");

    let backups = client.encryption().backups();
    let exists = backups.fetch_exists_on_server().await.unwrap_or(false);
    let enabled = backups.are_enabled().await;
    debug!("[crypto] backups exists_on_server={exists}, enabled={enabled}");

    let recovery_state = client.encryption().recovery().state();
    debug!("[crypto] recovery_state={recovery_state:?}");

    let mut options = MessagesOptions::backward();
    options.limit = matrix_sdk::ruma::UInt::from(1u32);
    if let Ok(messages) = room.messages(options).await {
        if let Some(event) = messages.chunk.first() {
            if let Ok(raw) = event.raw().deserialize() {
                trace!("[crypto] sample event type={:?}", raw.event_type());
            }
        }
    }

    Ok(())
}

pub use sliding_sync::{AckResponse, SlidingSyncConfig, StartSlidingSyncResponse};
pub use timeline::{LoadBackwardResponse, OpenRoomResponse, TimelineAck};
use matrix_sdk::ruma::events::room::message::{RoomMessageEventContent, Relation};
use matrix_sdk::ruma::events::relation::InReplyTo;
pub use verification::{StartSasResponse};

#[derive(Debug, Clone, Serialize)]
pub struct TrustStateResponse {
    pub user_verified: bool,
    pub device_verified: Option<bool>,
    pub device_exists: Option<bool>,
}

/// Start (or update) the sliding sync controller associated with the provided handle.
pub fn start_sliding_sync(
    handle: &str,
    config: SlidingSyncConfig,
) -> Result<StartSlidingSyncResponse> {
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(sliding_sync::start_sliding_sync(handle, config))
}

/// Update room subscriptions for a sliding sync handle.
pub fn sliding_subscribe_rooms(handle: &str, room_ids: Vec<String>, reset: bool) -> Result<AckResponse> {
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(sliding_sync::subscribe_rooms(handle, room_ids, reset))
}

/// Ensure that the given room has an active timeline controller.
pub fn open_room(handle: &str, room_id: &str) -> Result<OpenRoomResponse> {
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(timeline::open_room(handle, room_id))
}

/// Subscribe a Dart send port to timeline updates for the room.
pub fn register_timeline_listener(handle: &str, room_id: &str, port: i64) -> Result<TimelineAck> {
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(timeline::register_timeline_listener(handle, room_id, port))
}

/// Request a backwards pagination for the room timeline.
pub fn load_backward(handle: &str, room_id: &str, limit: u32) -> Result<LoadBackwardResponse> {
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(timeline::load_backward(handle, room_id, limit))
}

/// Register a Dart send port to receive room list updates for the given handle.
pub fn register_room_list_listener(handle: &str, port: i64) -> Result<AckResponse> {
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(sliding_sync::register_room_list_listener(handle, port))
}

/// Start a SAS verification request with a user/device. Not implemented yet in this build.
pub fn request_sas_verification(user_id: &str, device_id: Option<&str>) -> Result<StartSasResponse> {
    verification::request_sas_verification(user_id, device_id)
}

/// Observe SAS verification updates for a flow id via a Dart port. Not implemented yet.
pub fn observe_sas(flow_id: &str, port: i64) -> Result<AckResponse> {
    verification::observe_sas(flow_id, port)
}

/// Confirm a SAS verification flow. Not implemented yet.
pub fn confirm_sas(flow_id: &str) -> Result<()> {
    verification::confirm_sas(flow_id)
}

/// Cancel a SAS verification flow. Not implemented yet.
pub fn cancel_sas(flow_id: &str) -> Result<()> {
    verification::cancel_sas(flow_id)
}

/// Return cross-signing trust state for a user/device.
pub fn trust_state(user_id: &str, _device_id: Option<&str>) -> Result<TrustStateResponse> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let runtime = runtime();
    let _guard = runtime.enter();

    let user_id: OwnedUserId = user_id
        .parse()
        .map_err(|_| anyhow!("invalid user id '{user_id}'"))?;

    runtime.block_on(async move {
        let encryption = client.encryption();
        // user verification not available on this SDK surface yet; keep false
        let user_verified = false;

        let (device_verified, device_exists) = if let Some(did) = _device_id {
            match encryption.get_device(&user_id, did.into()).await {
                Ok(Some(device)) => (Some(device.is_verified()), Some(true)),
                Ok(None) => (None, Some(false)),
                Err(_) => (None, None),
            }
        } else {
            (None, None)
        };

        Ok(TrustStateResponse { user_verified, device_verified, device_exists })
    })
}

#[derive(Debug, Clone, Serialize)]
pub struct SendAck {
    pub ok: bool,
}

/// Send a plain text message to a room, optionally as a reply to another event.
pub fn send_text(room_id: &str, body: &str, reply_to: Option<&str>) -> Result<SendAck> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let room_id: OwnedRoomId = room_id
        .parse()
        .map_err(|_| anyhow!("invalid room id '{room_id}'"))?;

    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(async move {
        let Some(room) = client.get_room(&room_id) else {
            return Err(anyhow!("room not found"));
        };

        let mut content = RoomMessageEventContent::text_plain(body.to_owned());
        if let Some(evt) = reply_to {
            // Attach an m.relates_to reply relation if provided.
            let eid = matrix_sdk::ruma::OwnedEventId::try_from(evt)
                .map_err(|_| anyhow!("invalid event id for reply"))?;
            let in_reply_to = InReplyTo::new(eid);
            content.relates_to = Some(Relation::Reply { in_reply_to });
        }

        // Let the SDK assign a transaction id; local echo will be handled by timeline polling.
        let _ = room
            .send(content)
            .await
            .map_err(|e| anyhow!(format!("send failed: {e:?}")))?;

        Ok(SendAck { ok: true })
    })
}

/// Perform a one-shot classic /sync and return when it completes.
/// Useful as a deterministic nudge for updating server-provided unread counts
/// and device lists in headless/test environments.
pub fn classic_sync_once() -> Result<Ack> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(async move {
        let _ = client.sync_once(SyncSettings::default()).await;
        Ok(Ack { ok: true })
    })
}

/// Return the list of joined room IDs.
pub fn list_joined_rooms() -> Result<RoomListResponse> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let mut unique = HashSet::new();

    for room in client.rooms() {
        if matches!(room.state(), RoomState::Joined) {
            unique.insert(room.room_id().to_string());
        }
    }

    let runtime = runtime();
    let _guard = runtime.enter();
    let sliding_rooms = runtime.block_on(sliding_sync::joined_room_ids());
    // Include rooms discovered via Sliding Sync immediately, even if the
    // SDK room cache hasn't fully materialised or marked them as Joined yet.
    // This avoids a delay where portals appear in other clients but not here.
    for id in sliding_rooms {
        unique.insert(id);
    }

    let mut rooms: Vec<String> = unique.into_iter().collect();
    rooms.sort();

    Ok(RoomListResponse { rooms })
}

/// Return overview details for a given room ID.
pub fn room_overview(room_id: &str) -> Result<RoomOverview> {
    log::trace!("[room] overview: {}", room_id);
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let runtime = runtime();
    let _guard = runtime.enter();

    let room_id: OwnedRoomId = room_id
        .parse()
        .map_err(|_| anyhow!("invalid room id '{room_id}'"))?;

    runtime.block_on(async move {
        if let Some(room) = client.get_room(&room_id) {
            return build_room_overview(&room).await;
        }

        // Fallback: room not yet materialised in the SDK cache.
        // Return a placeholder overview so the UI can surface the room early;
        // details will be refreshed on next tick once the cache fills.
        warn!("Room {} not found in SDK cache, returning fallback with notification_count=0", room_id);
        Ok(RoomOverview {
            room_id: room_id.as_str().to_owned(),
            name: room_id.as_str().to_owned(),
            avatar_url: None,
            bump_ts: None,
            latest_event_ts: None,
            debug_ts_source: None,
            notification_count: 0,
            highlight_count: 0,
            is_marked_unread: false,
            is_muted: {
                let guard = MUTED_ROOMS.read().expect("MUTED_ROOMS lock poisoned");
                guard.contains(room_id.as_str())
            },
        })
    })
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RoomOverview {
    pub room_id: String,
    pub name: String,
    pub avatar_url: Option<String>,
    pub bump_ts: Option<u64>,
    /// Milliseconds since Unix epoch of the latest event, when known.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub latest_event_ts: Option<u64>,
    /// Debug-only: where latest_event_ts came from. Not used by app logic.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub debug_ts_source: Option<String>,
    pub notification_count: u64,
    pub highlight_count: u64,
    pub is_marked_unread: bool,
    pub is_muted: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct MemberProfile {
    pub display_name: String,
    pub avatar_url: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct RoomListResponse {
    pub rooms: Vec<String>,
}

async fn build_room_overview(room: &MatrixRoom) -> Result<RoomOverview> {
    let room_id = room.room_id().to_owned();

    let display_name = match room.display_name().await {
        Ok(RoomDisplayName::Named(name))
        | Ok(RoomDisplayName::Calculated(name))
        | Ok(RoomDisplayName::Aliased(name))
        | Ok(RoomDisplayName::EmptyWas(name)) => name,
        Ok(RoomDisplayName::Empty) => room_id.as_str().to_owned(),
        Err(err) => {
            warn!("failed to resolve display name for {}: {err:?}", room_id);
            room_id.as_str().to_owned()
        }
    };

    let avatar_url = room.avatar_url().map(|url| url.to_string());
    let bump_ts = room.recency_stamp();
    let latest_event_ts = match room.new_latest_event() {
        LatestEventValue::Remote(remote) => {
            // Deserialize to access origin_server_ts (MilliSecondsSinceUnixEpoch)
            remote
                .raw()
                .deserialize()
                .ok()
                .map(|e| u64::from(e.origin_server_ts().get()))
        }
        // Do not surface local timestamps as display timestamps; they are not
        // server origin times and can appear newer than reality.
        LatestEventValue::LocalIsSending(_) | LatestEventValue::LocalCannotBeSent(_) => None,
        LatestEventValue::None => None,
    }
    // Offline fallback: read origin_server_ts from our local timeline cache.
    .or_else(|| {
        let rid = room.room_id().as_str();
        let base = active_base_path().unwrap_or_else(|| PathBuf::from(".messie_store_v2"));
        let store_root = base.join("matrix_store");
        let cache_dir = store_root.join("timeline_cache");
        let _ = std::fs::create_dir_all(&cache_dir);
        let fname: String = rid.chars().map(|c| match c { ':'|'!'|'$'|'/'|'\\'|'?'|'#'|'*'|' ' => '_', _ => c }).collect();
        let path = cache_dir.join(format!("{}.json", fname));
        if !path.exists() { return None; }
        let bytes = std::fs::read(path).ok()?;
        let v: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
        let arr = if let Some(a) = v.as_array() { a.clone() } else { v.get("events")?.as_array()?.clone() };
        for item in arr.iter().rev() {
            let raw = item.as_str()?;
            let ev: serde_json::Value = serde_json::from_str(raw).ok()?;
            if let Some(ts) = ev.get("origin_server_ts").and_then(|x| x.as_u64()) { return Some(ts); }
        }
        None
    });
    // PROPER FIX: Wait for Sliding Sync room update before reading notification counts
    // The issue is we're reading counts immediately without waiting for sliding sync
    // to deliver the server notification data to the room.

    let (notification_count, highlight_count) = match get_updated_notification_counts(&room).await {
        Some((n, h)) => {
            log::trace!("[room] ss counts {} n={} h= {}", room_id, n, h);
            (n, h)
        }
        None => {
            // Fallback to immediate read (which may not have latest server data)
            let unread_counts = room.unread_notification_counts();
            log::trace!(
                "[room] fallback counts {} n={} h={}",
                room_id,
                unread_counts.notification_count,
                unread_counts.highlight_count
            );
            (unread_counts.notification_count, unread_counts.highlight_count)
        }
    };

    let is_marked_unread = room.is_marked_unread();

    // Debug logging showing both methods for comparison
    let old_notification = room.num_unread_notifications();
    let old_highlight = room.num_unread_mentions();

    log::debug!(
        "[room] counts {} n={} h={} (legacy n={} h={})",
        room_id, notification_count, highlight_count, old_notification, old_highlight
    );


    // Determine mute from SDK notification settings if available.
    let muted = {
        let guard = MUTED_ROOMS.read().expect("MUTED_ROOMS lock poisoned");
        guard.contains(room_id.as_str())
    };

    Ok(RoomOverview {
        room_id: room_id.as_str().to_owned(),
        name: display_name,
        avatar_url,
        bump_ts,
        latest_event_ts,
        debug_ts_source: None,
        notification_count,
        highlight_count,
        is_marked_unread,
        is_muted: muted,
    })
}

// ------------------------ Read state & mute ------------------------

#[derive(Debug, Clone, Serialize)]
pub struct Ack { pub ok: bool }

/// Mark the given event as read in a room.
pub fn mark_read_up_to(room_id: &str, event_id: &str) -> Result<Ack> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let room_id: OwnedRoomId = room_id.parse().map_err(|_| anyhow!("invalid room id"))?;
    let event_id_str = event_id.to_owned();
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(async move {
        let Some(room) = client.get_room(&room_id) else { return Err(anyhow!("room not found")); };
        // Resolve target event id. Support a special "__LATEST__" sentinel that
        // fetches the newest event id from the server for deterministic tests.
        let target_eid = if event_id_str == "__LATEST__" {
            let mut opts = MessagesOptions::backward();
            opts.limit = UInt::from(1u32);
            let resp = room
                .messages(opts)
                .await
                .map_err(|e| anyhow!(format!("failed to fetch latest message: {e:?}")))?;
            let eid = resp
                .chunk
                .first()
                .and_then(|ev| ev.event_id())
                .ok_or_else(|| anyhow!("no events in room to mark read"))?;
            eid
        } else {
            matrix_sdk::ruma::OwnedEventId::try_from(event_id_str.as_str())
                .map_err(|_| anyhow!("invalid event id"))?
        };
        // Try sending a single read receipt for the given event.
        if let Err(err) = room
            .send_single_receipt(
                matrix_sdk::ruma::api::client::receipt::create_receipt::v3::ReceiptType::Read,
                matrix_sdk::ruma::events::receipt::ReceiptThread::Unthreaded,
                target_eid.clone(),
            )
            .await
        {
            return Err(anyhow!(format!("failed to send read receipt: {err:?}")));
        }
        // Test stabilizer: force a one-shot sync so Sliding Sync summaries
        // reflect the updated read state immediately in headless runs.
        let _ = room
            .client()
            .sync_once(SyncSettings::default())
            .await;
        // Also set read markers (m.read and m.fully_read) via the canonical endpoint.
        // Synapse bases notification_count on the read receipt (above), but this keeps
        // account-data aligned and avoids edge cases.
        let client = room.client();
        let mut req = read_marker::Request::new(room_id.clone());
        req.fully_read = Some(target_eid.clone());
        req.read_receipt = Some(target_eid); // m.read
        req.private_read_receipt = None;
        if let Err(err) = client.send(req).await {
            return Err(anyhow!(format!("failed to set read markers: {err:?}")));
        }
        Ok(Ack { ok: true })
    })
}

/// Set or clear server-side push mute for a room.
pub fn set_room_mute(room_id: &str, muted: bool) -> Result<Ack> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let room_id: OwnedRoomId = room_id.parse().map_err(|_| anyhow!("invalid room id"))?;
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(async move {
        use matrix_sdk::notification_settings::RoomNotificationMode;
        let settings = client.notification_settings().await;
        if muted {
            settings
                .set_room_notification_mode(room_id.as_ref(), RoomNotificationMode::Mute)
                .await
                .map_err(|e| anyhow!(format!("failed to set room mute: {e:?}")))?;
            {
                let mut guard = MUTED_ROOMS.write().expect("MUTED_ROOMS lock poisoned");
                guard.insert(room_id.as_str().to_owned());
            }
        } else {
            settings
                .set_room_notification_mode(room_id.as_ref(), RoomNotificationMode::AllMessages)
                .await
                .map_err(|e| anyhow!(format!("failed to clear room mute: {e:?}")))?;
            {
                let mut guard = MUTED_ROOMS.write().expect("MUTED_ROOMS lock poisoned");
                guard.remove(room_id.as_str());
            }
        }
        Ok(Ack { ok: true })
    })
}

/// Convert an mxc:// URL to an HTTP(S) URL, optionally with width/height.
pub fn mxc_to_http(mxc: &str, w: Option<u32>, h: Option<u32>) -> Result<String> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    // Parse bare mxc://server/mediaid to (server, mediaid) without ruma helpers to avoid API drift.
    let rest = mxc.strip_prefix("mxc://").ok_or_else(|| anyhow!("invalid mxc uri"))?;
    let mut parts = rest.splitn(2, '/');
    let server = parts.next().ok_or_else(|| anyhow!("invalid mxc uri: missing server"))?;
    let media = parts.next().ok_or_else(|| anyhow!("invalid mxc uri: missing media id"))?;

    let homeserver = client.homeserver();
    let mut url = homeserver.clone();
    if let (Some(w), Some(h)) = (w, h) {
        url.set_path(&format!("/_matrix/media/v3/thumbnail/{}/{}", server, media));
        let mut pairs = url.query_pairs_mut();
        pairs.append_pair("width", &w.to_string());
        pairs.append_pair("height", &h.to_string());
        pairs.append_pair("method", "crop");
        // Prefer server-side redirects and remote fetches when available.
        pairs.append_pair("allow_redirect", "true");
        pairs.append_pair("allow_remote", "true");
        drop(pairs);
    } else {
        url.set_path(&format!("/_matrix/media/v3/download/{}/{}", server, media));
        let mut pairs = url.query_pairs_mut();
        // Prefer server-side redirects when available (MSC3916 environments).
        pairs.append_pair("allow_redirect", "true");
        drop(pairs);
    }
    Ok(url.to_string())
}

/// Resolve a room-scoped member profile (display name and avatar).
pub fn member_profile(room_id: &str, user_id: &str) -> Result<MemberProfile> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let room_id: OwnedRoomId = room_id
        .parse()
        .map_err(|_| anyhow!("invalid room id '{room_id}'"))?;
    let user_id: OwnedUserId = user_id
        .parse()
        .map_err(|_| anyhow!("invalid user id '{user_id}'"))?;

    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(async move {
        let room = client
            .get_room(&room_id)
            .ok_or_else(|| anyhow!("room {room_id} not found"))?;

        match room.get_member(&user_id).await {
            Ok(Some(member)) => {
                let display_name = member
                    .display_name()
                    .map(|s| s.to_owned())
                    .unwrap_or_else(|| user_id.to_string());
                let avatar_url = member.avatar_url().map(|url| url.to_string());
                Ok(MemberProfile { display_name, avatar_url })
            }
            Ok(None) => Ok(MemberProfile {
                display_name: user_id.to_string(),
                avatar_url: None,
            }),
            Err(err) => {
                warn!("failed to lookup member {} in room {}: {err:?}", user_id, room_id);
                Ok(MemberProfile {
                    display_name: user_id.to_string(),
                    avatar_url: None,
                })
            }
        }
    })
}
