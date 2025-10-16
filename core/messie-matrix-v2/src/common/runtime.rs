use once_cell::sync::OnceCell;
use tokio::runtime::{Builder, Runtime};

static RUNTIME: OnceCell<Runtime> = OnceCell::new();

pub fn runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        Builder::new_multi_thread()
            .enable_all()
            .thread_name("messie-matrix-v2")
            .build()
            .expect("failed to create Tokio runtime (v2)")
    })
}

