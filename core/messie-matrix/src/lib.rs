//! Messie Matrix SDK wrapper providing a synchronous facade for the async
//! `matrix-sdk` crate. The helper functions here are consumed by the FFI layer
//! so the Flutter app can manage session lifecycles from Dart.

use std::{
    fs,
    path::{Path, PathBuf},
    sync::{Arc, RwLock},
};

use anyhow::{anyhow, Context, Result};
use matrix_sdk::{
    authentication::matrix::MatrixSession,
    ruma::{OwnedDeviceId, OwnedUserId},
    Client, SessionMeta, SessionTokens,
};
use once_cell::sync::{Lazy, OnceCell};
use serde::{Deserialize, Serialize};
use tokio::runtime::{Builder, Runtime};
use url::Url;

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

    {
        let mut guard = ACTIVE_CLIENT.write().expect("ACTIVE_CLIENT lock poisoned");
        *guard = None;
    }
    wipe_store(base_path)
}
