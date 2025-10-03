//! Messie Matrix SDK wrapper providing a synchronous facade for the async
//! `matrix-sdk` crate. The helper functions here are consumed by the FFI layer
//! so the Flutter app can manage session lifecycles from Dart.

use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Arc, RwLock},
};

use anyhow::{anyhow, Context, Result};
use log::warn;
use matrix_sdk::{
    authentication::matrix::MatrixSession,
    ruma::{OwnedDeviceId, OwnedRoomId, OwnedUserId},
    Client, Room as MatrixRoom, RoomDisplayName, RoomState, SessionMeta, SessionTokens,
};
use once_cell::sync::{Lazy, OnceCell};
use serde::{Deserialize, Serialize};
use tokio::runtime::{Builder, Runtime};
use url::Url;

mod sliding_sync;
mod timeline;

/// Simple ping function used for integration tests.
pub fn ping() -> Result<String> {
    Ok("pong".to_owned())
}

/// Tokio runtime shared by all blocking calls.
static RUNTIME: OnceCell<Runtime> = OnceCell::new();
/// Active Matrix client for the current session. Only a single session is
/// supported at a time for Phase 1.
static ACTIVE_CLIENT: Lazy<RwLock<Option<Arc<Client>>>> = Lazy::new(|| RwLock::new(None));

fn runtime() -> &'static Runtime {
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

/// Returns the current client if one has been initialised.
#[allow(dead_code)]
pub fn client() -> Option<Arc<Client>> {
    ACTIVE_CLIENT
        .read()
        .expect("ACTIVE_CLIENT lock poisoned")
        .as_ref()
        .map(Arc::clone)
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
            Client::builder()
                .homeserver_url(homeserver.as_ref())
                .sqlite_store_with_cache_path(&database_path, &cache_path, None)
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
            Result::<_, anyhow::Error>::Ok(())
        })
        .context("failed to restore session")?;

    let arc = store_client(client);
    let meta = arc
        .session_meta()
        .cloned()
        .ok_or_else(|| anyhow!("restored client missing session metadata"))?;
    let user_id = meta.user_id.to_string();
    let device_id = Some(meta.device_id.to_string());

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
                Result::<_, anyhow::Error>::Ok(session)
            })
            .context("failed to restore existing session")?;

        let arc = store_client(client);
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
                Result::<_, anyhow::Error>::Ok(response)
            })
            .context("failed to login with username/password")?;

        let session: MatrixSession = (&response).into();
        persist_session(&base_path, &session, &homeserver_url)?;
        let arc = store_client(client);
        let meta = arc
            .session_meta()
            .cloned()
            .ok_or_else(|| anyhow!("logged-in client missing session metadata"))?;

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
    });

    {
        let mut guard = ACTIVE_CLIENT.write().expect("ACTIVE_CLIENT lock poisoned");
        *guard = None;
    }
    wipe_store(base_path)
}

pub use sliding_sync::{AckResponse, SlidingSyncConfig, StartSlidingSyncResponse};
pub use timeline::{LoadBackwardResponse, OpenRoomResponse, TimelineAck};

/// Start (or update) the sliding sync controller associated with the provided handle.
pub fn start_sliding_sync(
    handle: &str,
    config: SlidingSyncConfig,
) -> Result<StartSlidingSyncResponse> {
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(sliding_sync::start_sliding_sync(handle, config))
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

/// Return the list of joined or invited room IDs.
pub fn list_joined_rooms() -> Result<RoomListResponse> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let rooms = client.rooms();
    let mut result = Vec::new();
    for room in rooms {
        if matches!(room.state(), RoomState::Joined | RoomState::Invited) {
            result.push(room.room_id().to_string());
        }
    }
    Ok(RoomListResponse { rooms: result })
}

/// Return overview details for a given room ID.
pub fn room_overview(room_id: &str) -> Result<RoomOverview> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let runtime = runtime();
    let _guard = runtime.enter();

    let room_id: OwnedRoomId = room_id
        .parse()
        .map_err(|_| anyhow!("invalid room id '{room_id}'"))?;

    runtime.block_on(async move {
        let room = client
            .get_room(&room_id)
            .ok_or_else(|| anyhow!("room {room_id} not found"))?;
        build_room_overview(&room).await
    })
}

#[derive(Debug, Clone, Serialize)]
pub struct RoomOverview {
    pub room_id: String,
    pub name: String,
    pub avatar_url: Option<String>,
    pub bump_ts: Option<u64>,
    pub notification_count: u64,
    pub highlight_count: u64,
    pub is_marked_unread: bool,
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
    let notification_counts = room.unread_notification_counts();
    let is_marked_unread = room.is_marked_unread();

    Ok(RoomOverview {
        room_id: room_id.as_str().to_owned(),
        name: display_name,
        avatar_url,
        bump_ts,
        notification_count: notification_counts.notification_count,
        highlight_count: notification_counts.highlight_count,
        is_marked_unread,
    })
}
