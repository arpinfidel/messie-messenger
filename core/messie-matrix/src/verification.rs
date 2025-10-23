use std::{collections::HashMap, sync::Arc, time::Duration};

use anyhow::{anyhow, Result};
use futures::StreamExt;
use once_cell::sync::Lazy;
use serde::Serialize;
use tokio::time::sleep;
use tokio_util::sync::CancellationToken;
use tokio::{sync::RwLock as AsyncRwLock, sync::Mutex as AsyncMutex};

use crate::{client, runtime, sliding_sync::AckResponse};
use matrix_sdk::encryption::verification::{SasVerification, VerificationRequest};
use matrix_sdk::encryption::verification::SasState as SdkSasState;
use matrix_sdk::ruma::OwnedUserId;
use matrix_sdk::config::SyncSettings;
use matrix_sdk::LoopCtrl;
use log::{debug, trace, info, warn};

#[derive(Debug, Clone, Serialize)]
pub struct StartSasResponse {
    pub flow_id: String,
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum SasState {
    Requested,
    Ready,
    KeysExchanged,
    Confirmed,
    Done,
    Cancelled,
}

#[derive(Debug, Clone, Serialize)]
struct SasPayload {
    kind: &'static str,
    flow_id: String,
    state: SasState,
    emoji: Option<Vec<String>>,
    decimals: Option<(u16, u16, u16)>,
}

static CONTROLLERS: Lazy<AsyncRwLock<HashMap<String, Arc<SasController>>>> =
    Lazy::new(|| AsyncRwLock::new(HashMap::new()));

struct SasController {
    flow_id: String,
    listeners: AsyncMutex<std::collections::HashSet<i64>>,
    state: AsyncMutex<SasState>,
    emoji: AsyncMutex<Option<Vec<String>>>,
    decimals: AsyncMutex<Option<(u16, u16, u16)>>,
    cancel_token: CancellationToken,
    request: AsyncMutex<Option<VerificationRequest>>,
    sas: AsyncMutex<Option<SasVerification>>, 
    to_device_cancel: AsyncMutex<Option<CancellationToken>>,
}

impl SasController {
    async fn create(flow_id: String) -> Arc<Self> {
        let cancel_token = CancellationToken::new();
        let controller = Arc::new(Self {
            flow_id,
            listeners: AsyncMutex::new(Default::default()),
            state: AsyncMutex::new(SasState::Requested),
            emoji: AsyncMutex::new(None),
            decimals: AsyncMutex::new(None),
            cancel_token: cancel_token.clone(),
            request: AsyncMutex::new(None),
            sas: AsyncMutex::new(None),
            to_device_cancel: AsyncMutex::new(None),
        });
        controller
    }

    async fn add_listener(&self, port: i64) {
        self.listeners.lock().await.insert(port);
        let _ = self.broadcast_snapshot().await;
    }

    async fn set_state(&self, new_state: SasState) {
        *self.state.lock().await = new_state.clone();
        let _ = self.broadcast_snapshot().await;
        if matches!(new_state, SasState::Done | SasState::Cancelled) {
            if let Some(ct) = self.to_device_cancel.lock().await.take() { ct.cancel(); }
        }
    }

    async fn snapshot(&self) -> SasPayload {
        SasPayload {
            kind: "sas_update",
            flow_id: self.flow_id.clone(),
            state: self.state.lock().await.clone(),
            emoji: self.emoji.lock().await.clone(),
            decimals: self.decimals.lock().await.clone(),
        }
    }

    async fn broadcast_snapshot(&self) -> Result<()> {
        let payload = self.snapshot().await;
        let json = serde_json::to_string(&payload)?;
        let mut listeners = self.listeners.lock().await;
        let mut stale = Vec::new();
        for &port in listeners.iter() {
            if !Self::post(port, json.clone()) {
                stale.push(port);
            }
        }
        for port in stale { listeners.remove(&port); }
        Ok(())
    }

    fn post(port: i64, payload: String) -> bool {
        allo_isolate::Isolate::new(port).post(payload)
    }

    fn shutdown(&self) { self.cancel_token.cancel(); }

    async fn attach_request(self: &Arc<Self>, req: VerificationRequest) {
        *self.request.lock().await = Some(req.clone());

        // Observe request state changes and react (idempotent start_sas on Ready/Started)
        let ctrl_for_changes = self.clone();
        runtime().spawn(async move {
            let mut changes = req.changes();
            while let Some(state) = changes.next().await {
                // Map request state to our stream and drive SAS start
                // Note: exact variants depend on matrix-sdk 0.14; we conservatively
                // handle the common ones and ignore others.
                let mut try_start_sas = false;
                match state {
                    // We initiated and peer has not accepted yet
                    matrix_sdk::encryption::verification::VerificationRequestState::Requested { .. } => {
                        ctrl_for_changes.set_state(SasState::Requested).await;
                    }
                    // Either party is ready; attempt to start SAS
                    matrix_sdk::encryption::verification::VerificationRequestState::Ready { .. } => {
                        ctrl_for_changes.set_state(SasState::Ready).await;
                        try_start_sas = true;
                    }
                    matrix_sdk::encryption::verification::VerificationRequestState::Done => {
                        ctrl_for_changes.set_state(SasState::Done).await;
                        break;
                    }
                    matrix_sdk::encryption::verification::VerificationRequestState::Cancelled(_) => {
                        ctrl_for_changes.set_state(SasState::Cancelled).await;
                        break;
                    }
                    _ => {}
                }

                if try_start_sas {
                    // If SAS already active, skip. Otherwise attempt to start.
                    if ctrl_for_changes.sas.lock().await.is_none() {
                        if let Ok(Some(sas)) = req.start_sas().await {
                            SasController::on_sas_started(ctrl_for_changes.clone(), sas).await;
                            // Once SAS is started, we continue to observe SAS stream for completion.
                        }
                    }
                }
            }
        });

        // Fallback retry loop to start SAS in case we miss a change event
        let ctrl = self.clone();
        runtime().spawn(async move {
            loop {
                if ctrl.cancel_token.is_cancelled() { break; }
                if ctrl.sas.lock().await.is_some() { break; }
                let maybe_req = { ctrl.request.lock().await.clone() };
                if let Some(req) = maybe_req {
                    if let Ok(Some(sas)) = req.start_sas().await {
                        SasController::on_sas_started(ctrl.clone(), sas).await;
                        break;
                    }
                }
                sleep(Duration::from_millis(500)).await;
            }
        });
    }

    async fn on_sas_started(self: Arc<Self>, sas: SasVerification) {
        *self.sas.lock().await = Some(sas.clone());
        let stream = sas.changes();
        // Prime snapshot
        let _ = self.broadcast_snapshot().await;
        let ctrl = self.clone();
        runtime().spawn(async move {
            let mut stream = stream;
            while let Some(state) = stream.next().await {
                match state {
                    SdkSasState::KeysExchanged { emojis, decimals } => {
                        if let Some(emojis) = emojis {
                            let texts: Vec<String> = emojis.emojis.iter().map(|e| e.symbol.to_string()).collect();
                            *ctrl.emoji.lock().await = Some(texts);
                        }
                        *ctrl.decimals.lock().await = Some(decimals);
                        ctrl.set_state(SasState::KeysExchanged).await;
                    }
                    SdkSasState::Confirmed => {
                        ctrl.set_state(SasState::Confirmed).await;
                    }
                    SdkSasState::Done { .. } => {
                        ctrl.set_state(SasState::Done).await;
                        break;
                    }
                    SdkSasState::Cancelled(_) => {
                        ctrl.set_state(SasState::Cancelled).await;
                        break;
                    }
                    SdkSasState::Created { .. } | SdkSasState::Started { .. } | SdkSasState::Accepted { .. } => {}
                }
            }
        });
    }

    async fn start_to_device_worker(&self, client: Arc<matrix_sdk::Client>) {
        // Long-polling sync loop dedicated to delivering to-device events during SAS.
        // We don't scope a filter here; default sync is acceptable for headless tests.
        let settings = SyncSettings::default().timeout(Duration::from_secs(30));

        let cancel = CancellationToken::new();
        *self.to_device_cancel.lock().await = Some(cancel.clone());

        runtime().spawn(async move {
            let _ = client
                .sync_with_callback(settings, {
                    let cancel = cancel.clone();
                    move |_response| {
                        let cancel = cancel.clone();
                        async move {
                            if cancel.is_cancelled() {
                                LoopCtrl::Break
                            } else {
                                LoopCtrl::Continue
                            }
                        }
                    }
                })
                .await;
        });
    }
}

pub async fn reset_all() {
    let mut controllers = CONTROLLERS.write().await;
    for c in controllers.values() { c.shutdown(); }
    controllers.clear();
}

pub fn request_sas_verification(user_id: &str, device_id: Option<&str>) -> Result<StartSasResponse> {
    let client = client().ok_or_else(|| anyhow!("Matrix client has not been initialised"))?;
    let user_id: OwnedUserId = user_id
        .parse()
        .map_err(|_| anyhow!("invalid user id"))?;

    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(async move {
        let encryption = client.encryption();

        // If a device id is provided, target that device explicitly; otherwise request with user identity.
        let request: VerificationRequest = if let Some(did) = device_id {
            debug!("[sas] request verification for user {} device {}", user_id, did);
            // Ensure we have up-to-date device list by doing a short /sync loop if needed.
            let mut device_opt = None;
            for attempt in 0..8 { // up to ~3.2s with sleeps
                match encryption.get_device(&user_id, did.into()).await {
                    Ok(Some(device)) => { 
                        debug!("[sas] found target device '{}' on attempt {}", did, attempt + 1);
                        device_opt = Some(device); 
                        break; 
                    }
                    Ok(None) => {
                        if attempt == 0 { debug!("[sas] target device '{}' not in store yet; nudging short syncs", did); }
                        // Kick a short sync to fetch device list updates.
                        let _ = client.sync_once(SyncSettings::default().timeout(Duration::from_millis(800))).await;
                        sleep(Duration::from_millis(200)).await;
                    }
                    Err(e) => return Err(anyhow!(format!("get_device failed: {e:?}"))),
                }
            }

            let device = device_opt.ok_or_else(|| {
                warn!("[sas] target device '{}' not found after refresh attempts", did);
                anyhow!("target device not found")
            })?;
            device
                .request_verification()
                .await
                .map_err(|e| anyhow!(format!("device.request_verification failed: {e:?}")))?
        } else {
            let identity_opt = encryption
                .get_user_identity(&user_id)
                .await
                .map_err(|e| anyhow!(format!("get_user_identity failed: {e:?}")))?;
            let identity = identity_opt.ok_or_else(|| anyhow!("user identity not found for verification"))?;
            identity
                .request_verification()
                .await
                .map_err(|e| anyhow!(format!("request_verification failed: {e:?}")))?
        };

        let flow_id = request.flow_id().to_string();
        let controller = SasController::create(flow_id.clone()).await;
        // Start a scoped to-device worker to drive verification events
        controller.start_to_device_worker(client.clone()).await;
        controller.attach_request(request).await;
        CONTROLLERS.write().await.insert(flow_id.clone(), controller);
        Ok(StartSasResponse { flow_id })
    })
}

pub fn observe_sas(flow_id: &str, port: i64) -> Result<AckResponse> {
    let flow_id = flow_id.to_owned();
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(async move {
        let controllers = CONTROLLERS.read().await;
        let Some(controller) = controllers.get(&flow_id) else {
            return Err(anyhow!("unknown sas flow_id"));
        };
        controller.add_listener(port).await;
        Ok(AckResponse { ok: true })
    })
}

pub fn confirm_sas(flow_id: &str) -> Result<()> {
    let flow_id = flow_id.to_owned();
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(async move {
        let controllers = CONTROLLERS.read().await;
        let Some(controller) = controllers.get(&flow_id) else {
            return Err(anyhow!("unknown sas flow_id"));
        };
        if let Some(sas) = controller.sas.lock().await.clone() {
            let _ = sas.confirm().await;
        }
        controller.set_state(SasState::Confirmed).await;
        Ok(())
    })
}

pub fn cancel_sas(flow_id: &str) -> Result<()> {
    let flow_id = flow_id.to_owned();
    let runtime = runtime();
    let _guard = runtime.enter();
    runtime.block_on(async move {
        let controllers = CONTROLLERS.read().await;
        let Some(controller) = controllers.get(&flow_id) else {
            return Err(anyhow!("unknown sas flow_id"));
        };
        if let Some(sas) = controller.sas.lock().await.clone() {
            let _ = sas.cancel().await;
        } else if let Some(req) = controller.request.lock().await.clone() {
            let _ = req.cancel().await;
        }
        controller.set_state(SasState::Cancelled).await;
        Ok(())
    })
}
