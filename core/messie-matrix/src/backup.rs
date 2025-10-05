use std::{collections::HashMap, sync::Arc, time::Duration};

use allo_isolate::Isolate;
use anyhow::{anyhow, Result};
use once_cell::sync::Lazy;
use serde::Serialize;
use tokio::time::interval;
use tokio_util::sync::CancellationToken;
use tokio::{sync::RwLock as AsyncRwLock, sync::Mutex as AsyncMutex};

use crate::{client, runtime, sliding_sync::AckResponse};
use matrix_sdk::encryption::recovery::RecoveryState;

static CONTROLLERS: Lazy<AsyncRwLock<HashMap<String, Arc<BackupStatusController>>>> =
    Lazy::new(|| AsyncRwLock::new(HashMap::new()));

const POLL_INTERVAL: Duration = Duration::from_secs(3);

#[derive(Debug, Clone, Serialize)]
pub struct BackupStatusPayload {
    pub kind: &'static str,
    pub enabled: bool,
    pub exists_on_server: bool,
    pub recovery_state: String,
    pub needs_recovery: bool,
}


pub async fn register_listener(handle: &str, port: i64) -> Result<AckResponse> {
    let mut controllers = CONTROLLERS.write().await;
    let controller = if let Some(existing) = controllers.get(handle) {
        existing.clone()
    } else {
        let created = BackupStatusController::create(handle.to_owned()).await?;
        controllers.insert(handle.to_owned(), created.clone());
        created
    };

    controller.add_listener(port).await?;
    Ok(AckResponse { ok: true })
}

pub async fn reset_all() {
    let mut controllers = CONTROLLERS.write().await;
    for controller in controllers.values() {
        controller.shutdown();
    }
    controllers.clear();
}

struct BackupStatusController {
    _handle: String,
    listeners: AsyncMutex<std::collections::HashSet<i64>>,
    cancel_token: CancellationToken,
}

impl BackupStatusController {
    async fn create(handle: String) -> Result<Arc<Self>> {
        // ensure client exists now to fail fast
        let _ = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
        let cancel_token = CancellationToken::new();
        let controller = Arc::new(Self {
            _handle: handle,
            listeners: AsyncMutex::new(Default::default()),
            cancel_token: cancel_token.clone(),
        });
        controller.spawn_background(cancel_token);
        Ok(controller)
    }

    fn spawn_background(self: &Arc<Self>, cancel_token: CancellationToken) {
        let controller = self.clone();
        runtime().spawn(async move {
            let mut ticker = interval(POLL_INTERVAL);
            loop {
                tokio::select! {
                    _ = cancel_token.cancelled() => break,
                    _ = ticker.tick() => {
                        if let Err(err) = controller.poll_and_broadcast().await {
                            eprintln!("backup_status poll failed: {err:?}");
                        }
                    }
                }
            }
        });
    }

    async fn add_listener(&self, port: i64) -> Result<()> {
        self.listeners.lock().await.insert(port);
        // Send an immediate snapshot
        if let Ok(payload) = self.snapshot().await {
            let json = serde_json::to_string(&payload)?;
            if !Self::post(port, json) {
                self.listeners.lock().await.remove(&port);
            }
        }
        Ok(())
    }

    async fn poll_and_broadcast(&self) -> Result<()> {
        let payload = self.snapshot().await?;
        let json = serde_json::to_string(&payload)?;
        let mut listeners = self.listeners.lock().await;
        let mut stale = Vec::new();
        for &port in listeners.iter() {
            if !Self::post(port, json.clone()) {
                stale.push(port);
            }
        }
        for port in stale {
            listeners.remove(&port);
        }
        Ok(())
    }

    async fn snapshot(&self) -> Result<BackupStatusPayload> {
        let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
        let encryption = client.encryption();
        let backups = encryption.backups();
        let enabled = backups.are_enabled().await;
        let exists = backups.fetch_exists_on_server().await.unwrap_or(false);
        let state_enum = encryption.recovery().state();
        let recovery_state = format!("{:?}", state_enum);
        // Need recovery if server has a backup but we are not locally enabled,
        // OR if the recovery service itself is not in Enabled state yet.
        let needs_recovery = (exists && !enabled)
            || !matches!(state_enum, RecoveryState::Enabled);
        Ok(BackupStatusPayload {
            kind: "backup_status",
            enabled,
            exists_on_server: exists,
            recovery_state,
            needs_recovery,
        })
    }

    fn post(port: i64, payload: String) -> bool { Isolate::new(port).post(payload) }

    fn shutdown(&self) { self.cancel_token.cancel(); }
}
