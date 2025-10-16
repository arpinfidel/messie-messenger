use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, Context, Result};
use matrix_sdk::{
    authentication::matrix::MatrixSession,
    encryption::{BackupDownloadStrategy, EncryptionSettings},
    Client, SessionMeta, SessionTokens,
};
use url::Url;

use crate::common::runtime::runtime;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub(crate) struct PersistedSession {
    pub homeserver_url: String,
    pub user_id: String,
    pub access_token: String,
    pub device_id: Option<String>,
    pub refresh_token: Option<String>,
}

impl PersistedSession {
    fn path(base_path: &Path) -> PathBuf { base_path.join("session.json") }
    fn load(base_path: &Path) -> Result<Option<Self>> {
        let path = Self::path(base_path);
        if !path.exists() { return Ok(None); }
        let contents = fs::read(&path).with_context(|| format!("failed to read session file at {}", path.display()))?;
        let session: Self = serde_json::from_slice(&contents).with_context(|| format!("failed to parse session file at {}", path.display()))?;
        Ok(Some(session))
    }
    fn save(&self, base_path: &Path) -> Result<()> {
        let path = Self::path(base_path);
        if let Some(dir) = path.parent() { fs::create_dir_all(dir).with_context(|| format!("failed to create session dir at {}", dir.display()))?; }
        let serialized = serde_json::to_vec_pretty(self).context("failed to serialise session")?;
        fs::write(&path, serialized).with_context(|| format!("failed to write session file at {}", path.display()))?;
        Ok(())
    }
}

pub(crate) fn load_session(base_path: &Path) -> Result<Option<MatrixSession>> {
    let persisted = match PersistedSession::load(base_path)? { Some(s) => s, None => return Ok(None) };
    let user_id: matrix_sdk::ruma::OwnedUserId = persisted.user_id.parse().map_err(|_| anyhow!("invalid stored user ID"))?;
    let device_id_str = persisted.device_id.ok_or_else(|| anyhow!("stored session missing device id"))?;
    let device_id = matrix_sdk::ruma::OwnedDeviceId::try_from(device_id_str.as_str()).map_err(|_| anyhow!("invalid stored device id"))?;
    Ok(Some(MatrixSession { meta: SessionMeta { user_id, device_id }, tokens: SessionTokens { access_token: persisted.access_token, refresh_token: persisted.refresh_token } }))
}

pub(crate) fn persist_session(base_path: &Path, session: &MatrixSession, homeserver_url: &Url) -> Result<()> {
    let device_id = Some(session.meta.device_id.to_string());
    let persisted = PersistedSession { homeserver_url: homeserver_url.as_ref().to_owned(), user_id: session.meta.user_id.to_string(), access_token: session.tokens.access_token.clone(), refresh_token: session.tokens.refresh_token.clone(), device_id };
    persisted.save(base_path)
}

pub(crate) fn wipe_store(base_path: &Path) -> Result<()> {
    if base_path.exists() {
        fs::remove_dir_all(base_path).with_context(|| format!("failed to wipe base path at {}", base_path.display()))?;
    }
    Ok(())
}

pub(crate) fn client_builder(homeserver_url: &Url, base_path: &Path) -> Result<Client> {
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
            let encryption_settings = EncryptionSettings { auto_enable_cross_signing: false, backup_download_strategy: BackupDownloadStrategy::OneShot, auto_enable_backups: true };
            Client::builder()
                .homeserver_url(homeserver.as_ref())
                .sqlite_store_with_cache_path(&database_path, &cache_path, None)
                .with_encryption_settings(encryption_settings)
                .build()
                .await
        })
        .context("failed to build Matrix client")
}

