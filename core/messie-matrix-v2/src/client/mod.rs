pub mod management;
mod session;

use once_cell::sync::Lazy;
use std::path::PathBuf;
use std::sync::{Arc, RwLock};
use url::Url;

use matrix_sdk::Client;

use crate::common::handle_registry::Registry;

#[derive(Clone)]
pub(crate) struct ClientEntry {
    pub client: Arc<Client>,
    pub base_path: PathBuf,
    pub homeserver: Url,
}

pub(crate) static CLIENTS: Lazy<RwLock<Registry<ClientEntry>>> =
    Lazy::new(|| RwLock::new(Registry::default()));
